mod state;
mod models;
mod ws;
mod db;
mod routes;
mod modbus;

use axum::{routing::{get, post}, Router};
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tracing::info;
use state::AppState;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init(); // logging setup

    let pool = db::init_db().await;
    let (write_tx, write_rx) = mpsc::channel(32);
    let app_state = AppState::new(pool, write_tx);

    modbus::start_polling(
        app_state.tx.clone(),
        app_state.db.clone(),
        "127.0.0.1:5020".to_string(),
        write_rx,
    );

    let app = Router::new() // router with routes
        .route("/health", get(health))
        .route("/ws", get(ws::ws_handler))
        .route("/api/devices", get(routes::get_devices))
        .route("/api/history", get(routes::get_history))
        .route("/api/write", post(routes::post_write))
        .with_state(app_state);

    let listener = TcpListener::bind("0.0.0.0:3000").await.unwrap();
    info!("Server running on http://0.0.0.0:3000"); // listen on port 3000

    axum::serve(listener, app).await.unwrap();
}

async fn health() -> &'static str {
    "OK"
}