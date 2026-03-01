use std::collections::HashMap;
use std::sync::Arc;

use sqlx::SqlitePool;
use tokio::sync::{broadcast, mpsc, RwLock};
use tokio::task::JoinHandle;

use crate::config::{AppConfig, DeviceConfig};

/// A write command routed to a specific device's polling task.
#[derive(Debug)]
pub struct WriteCommand {
    pub register: u16,
    pub value: u16,
    pub response: tokio::sync::oneshot::Sender<Result<(), String>>,
}

/// Per-device runtime info: write channel + polling task handle.
pub struct DeviceHandle {
    pub write_tx: mpsc::Sender<WriteCommand>,
    pub task: JoinHandle<()>,
    pub config: DeviceConfig,
}

/// Thread-safe device registry — add/remove devices at runtime.
pub type DeviceRegistry = Arc<RwLock<HashMap<String, DeviceHandle>>>;

#[derive(Clone)]
pub struct AppState {
    pub tx: broadcast::Sender<String>,
    pub db: SqlitePool,
    pub devices: DeviceRegistry,
    pub config: AppConfig,
}

impl AppState {
    pub fn new(db: SqlitePool, config: AppConfig) -> Self {
        let (tx, _rx) = broadcast::channel(100);
        let devices = Arc::new(RwLock::new(HashMap::new()));
        Self { tx, db, devices, config }
    }
}

