mod state;
mod models;
mod ws;
mod db;
mod routes;
mod modbus;
mod opcua_client;
mod config;
mod protocol;
mod discovery;
mod auth;
mod export;
mod rate_limit;
mod tsdb;

use axum::middleware as axum_mw;
use axum::routing::{delete, get, post};
use axum::Router;
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, warn};

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

    // ── Auth tables + seed default users ──
    auth::init_auth_tables(&pool).await;

    // ── App state (no single write_tx anymore — per-device channels) ──
    let app_state = AppState::new(pool.clone(), config.clone());

    // ── Start polling for ALL config devices ──
    for device in &config.devices {
        let client: Box<dyn protocol::PlcProtocol> = match device.protocol.as_str() {
            "modbus" => Box::new(modbus::ModbusClient::new(&device.address)),
            "opcua" => Box::new(opcua_client::OpcUaClient::new(&device.address)),
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
            "opcua" => Box::new(opcua_client::OpcUaClient::new(&device.address)),
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

    // CORS — allow Flutter web/desktop to connect
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Public routes (no auth required)
    let public_routes = Router::new()
        .route("/health", get(health))
        .route("/api/auth/login", post(auth::login))
        .route("/api/auth/verify", post(auth::verify_token_handler))
        .route("/api/auth/logout", post(auth::logout))
        // WebSocket — accepts upgrade then authenticates via first message
        .route("/ws", get(ws::ws_handler));

    // Protected routes — require valid JWT (any role)
    let protected_routes = Router::new()
        .route("/api/devices", get(routes::get_devices))
        .route("/api/history", get(routes::get_history))
        .route("/api/audit", get(auth::get_audit_trail))
        .route("/api/auth/esig", post(auth::electronic_signature))
        .route("/api/alarms", get(routes::list_alarms))
        .route("/api/alarms/{id}", get(routes::get_alarm))
        .route("/api/batches", get(routes::list_batches))
        .route("/api/batches/{id}", get(routes::get_batch))
        // CSV export endpoints (Phase 10.1)
        .route("/api/export/alarms.csv", get(export::export_alarms_csv))
        .route("/api/export/batches.csv", get(export::export_batches_csv))
        .route("/api/export/audit.csv", get(export::export_audit_csv))
        .route("/api/export/history.csv", get(export::export_history_csv))
        .layer(axum_mw::from_fn_with_state(app_state.clone(), auth::auth_middleware));

    // Operator routes — require Operator or Admin role
    let operator_routes = Router::new()
        .route("/api/devices", post(routes::add_device))
        .route("/api/devices/{id}", delete(routes::remove_device))
        .route("/api/devices/{id}/connect", post(routes::connect_device))
        .route("/api/devices/{id}/disconnect", post(routes::disconnect_device))
        .route("/api/discover", post(routes::discover_devices))
        .route("/api/browse/opcua", post(routes::browse_opcua))
        .route("/api/write", post(routes::post_write))
        .route("/api/alarms/{id}/ack", post(routes::ack_alarm))
        .route("/api/alarms/{id}/shelve", post(routes::shelve_alarm))
        .layer(axum_mw::from_fn_with_state(app_state.clone(), auth::require_operator));

    // Admin routes — require Admin role
    let admin_routes = Router::new()
        .route("/api/users", get(auth::list_users))
        .route("/api/users", post(auth::create_user))
        .layer(axum_mw::from_fn_with_state(app_state.clone(), auth::require_admin));

    let app = Router::new()
        .merge(public_routes)
        .merge(protected_routes)
        .merge(operator_routes)
        .merge(admin_routes)
        .layer(axum_mw::from_fn(rate_limit::rate_limit_middleware))
        .layer(cors)
        .with_state(app_state);

    // ── TLS / Plain HTTP ──
    if let (Some(cert_path), Some(key_path)) = (&config.server.tls_cert, &config.server.tls_key) {
        info!("🔒 TLS enabled — loading cert={cert_path}, key={key_path}");
        let rustls_config = axum_server::tls_rustls::RustlsConfig::from_pem_file(cert_path, key_path)
            .await
            .unwrap_or_else(|e| {
                eprintln!("ERROR: Failed to load TLS certificate: {e}");
                std::process::exit(1);
            });
        let addr: std::net::SocketAddr = bind_addr.parse().unwrap();
        info!("Server running on https://{}", bind_addr);
        axum_server::bind_rustls(addr, rustls_config)
            .serve(app.into_make_service())
            .await
            .unwrap();
    } else {
        warn!("⚠ TLS not configured — running plain HTTP. Set tls_cert and tls_key in config.toml for production.");
        let listener = TcpListener::bind(&bind_addr).await.unwrap_or_else(|e| {
            eprintln!("ERROR: Cannot bind to {bind_addr}: {e}");
            eprintln!("       Is another server already running? Try: lsof -i :3000");
            std::process::exit(1);
        });
        info!("Server running on http://{}", bind_addr);
        axum::serve(listener, app).await.unwrap();
    }
}

async fn health() -> &'static str {
    "OK"
}