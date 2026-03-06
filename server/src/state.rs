use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use sqlx::SqlitePool;
use tokio::sync::{broadcast, mpsc, Mutex, RwLock};
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

/// Brute-force protection: tracks failed login attempts per username.
/// (attempt_count, first_failure_time)
pub type LoginAttempts = Arc<Mutex<HashMap<String, (u32, Instant)>>>;

/// Active sessions — maps session_id → (user_id, expires_at_epoch).
/// Used for server-side session revocation.
pub type SessionStore = Arc<RwLock<HashMap<String, (String, i64)>>>;

#[derive(Clone)]
pub struct AppState {
    pub tx: broadcast::Sender<String>,
    pub db: SqlitePool,
    pub devices: DeviceRegistry,
    pub config: AppConfig,
    /// JWT signing secret loaded from config.
    pub jwt_secret: String,
    /// Brute-force protection: failed login attempts per user.
    pub login_attempts: LoginAttempts,
    /// Server-side session store for token revocation.
    pub sessions: SessionStore,
}

impl AppState {
    pub fn new(db: SqlitePool, config: AppConfig) -> Self {
        let (tx, _rx) = broadcast::channel(2000); // increased from 100 to handle 3+ devices
        let devices = Arc::new(RwLock::new(HashMap::new()));
        let jwt_secret = config.server.jwt_secret.clone();
        let login_attempts = Arc::new(Mutex::new(HashMap::new()));
        let sessions = Arc::new(RwLock::new(HashMap::new()));
        Self { tx, db, devices, config, jwt_secret, login_attempts, sessions }
    }
}
