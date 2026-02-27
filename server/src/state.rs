use sqlx::SqlitePool;
use tokio::sync::broadcast;

/// APplication state shared across all handlers

#[derive(Clone)]
pub struct AppState{
    pub tx: broadcast::Sender<String>, // broadcast channel to send plc data to all websocket clients
    pub db: SqlitePool 
}

impl AppState {
    pub fn new(db: SqlitePool) -> Self {
        let (tx, _rx) = broadcast::channel(100);
        Self { tx, db }
    }
}