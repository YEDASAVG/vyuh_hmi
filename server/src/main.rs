mod state;
mod models;
mod ws;
mod db;
mod routes;
mod modbus;

use axum::{routing::get, Router};
use tokio::net::TcpListener;
use tracing::info;
use state::AppState;
#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init(); // logging setup

    let pool = db::init_db().await;
    let app_state = AppState::new(pool);

    modbus::start_polling(
        app_state.tx.clone(),
        app_state.db.clone(),
        "127.0.0.1:5020".to_string(),
    );

    let app = Router::new()// router with routes
    .route("/health", get(health))
    .route("/ws", get(ws::ws_handler))
    .route("/api/devices", get(routes::get_devices))
    .route("/api/history", get(routes::get_history)) 
    .with_state(app_state);

    let listener = TcpListener::bind("0.0.0.0:3000").await.unwrap();
    info!("Server running on http://0.0.0.0:3000"); // listen on port 3000

    axum::serve(listener, app).await.unwrap();
}

async fn health() -> &'static str {
    "OK"
}