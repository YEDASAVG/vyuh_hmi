use sqlx::SqlitePool;
use tokio::sync::{broadcast, mpsc};

/// APplication state shared across all handlers

#[derive(Debug)]
pub struct WriteCommand {
    pub register: u16,
    pub value: u16,
    pub response: tokio::sync::oneshot::Sender<Result<(), String>>,
}
#[derive(Clone)]
pub struct AppState{
    pub tx: broadcast::Sender<String>, // broadcast channel to send plc data to all websocket clients
    pub db: SqlitePool,
    pub write_tx: mpsc::Sender<WriteCommand>, 
}

impl AppState {
    pub fn new(db: SqlitePool, write_tx:mpsc::Sender<WriteCommand>) -> Self {
        let (tx, _rx) = broadcast::channel(100);
        Self { tx, db, write_tx }
    }
}

