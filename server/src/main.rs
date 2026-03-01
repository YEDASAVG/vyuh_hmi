mod state;
mod models;
mod ws;
mod db;
mod routes;
mod modbus;
mod config;
mod protocol;
mod discovery;

use axum::routing::{delete, get, post};
use axum::Router;
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tracing::info;

use config::AppConfig;
use state::{AppState, DeviceHandle};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // ── Load config ──
    let config = AppConfig::load("config.toml");
    info!("Loaded config: {} device(s)", config.devices.len());

    // ── Database ──
    let pool = db::init_db(&config.database.path).await;

    // ── App state (no single write_tx anymore — per-device channels) ──
    let app_state = AppState::new(pool.clone(), config.clone());

    // ── Start polling for ALL config devices ──
    for device in &config.devices {
        let client: Box<dyn protocol::PlcProtocol> = match device.protocol.as_str() {
            "modbus" => Box::new(modbus::ModbusClient::new(&device.address)),
            other => {
                tracing::warn!("Skipping device '{}': unsupported protocol '{}'", device.id, other);
                continue;
            }
        };

        let (write_tx, write_rx) = mpsc::channel(32);
        let task = protocol::start_device_polling(
            device.clone(),
            client,
            app_state.tx.clone(),
            pool.clone(),
            write_rx,
        );

        let mut registry = app_state.devices.write().await;
        registry.insert(
            device.id.clone(),
            DeviceHandle {
                write_tx,
                task,
                config: device.clone(),
            },
        );
        info!("[{}] Registered and polling → {}", device.id, device.address);
    }

    // ── Load DB-persisted devices (added at runtime in previous session) ──
    let db_devices = db::load_devices(&pool).await;
    for device in db_devices {
        // Skip if already in config (avoid double-polling)
        {
            let registry = app_state.devices.read().await;
            if registry.contains_key(&device.id) {
                continue;
            }
        }

        let client: Box<dyn protocol::PlcProtocol> = match device.protocol.as_str() {
            "modbus" => Box::new(modbus::ModbusClient::new(&device.address)),
            other => {
                tracing::warn!("Skipping DB device '{}': unsupported protocol '{}'", device.id, other);
                continue;
            }
        };

        let (write_tx, write_rx) = mpsc::channel(32);
        let task = protocol::start_device_polling(
            device.clone(),
            client,
            app_state.tx.clone(),
            pool.clone(),
            write_rx,
        );

        let mut registry = app_state.devices.write().await;
        registry.insert(
            device.id.clone(),
            DeviceHandle {
                write_tx,
                task,
                config: device.clone(),
            },
        );
        info!("[{}] Restored from DB → {}", device.id, device.address);
    }

    // ── Router ──
    let bind_addr = format!("{}:{}", config.server.host, config.server.port);
    let app = Router::new()
        .route("/health", get(health))
        .route("/ws", get(ws::ws_handler))
        .route("/api/devices", get(routes::get_devices))
        .route("/api/devices", post(routes::add_device))
        .route("/api/devices/{id}", delete(routes::remove_device))
        .route("/api/discover", post(routes::discover_devices))
        .route("/api/history", get(routes::get_history))
        .route("/api/write", post(routes::post_write))
        .with_state(app_state);

    let listener = TcpListener::bind(&bind_addr).await.unwrap();
    info!("Server running on http://{}", bind_addr);

    axum::serve(listener, app).await.unwrap();
}

async fn health() -> &'static str {
    "OK"
}