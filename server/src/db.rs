use crate::config::DeviceConfig;
use crate::models::PlcData;
use sqlx::{SqlitePool, sqlite::SqlitePoolOptions};

//Initialize the DB -> create file + create tables

pub async fn init_db(path: &str) -> SqlitePool {
    let url = format!("sqlite:{}?mode=rwc", path);
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .expect("Failed to connect to SQLite");

    // Create tables if not exist

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS plc_readings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            register INTEGER NOT NULL,
            value REAL NOT NULL,
            timestamp TEXT NOT NULL
        )"
    )
    .execute(&pool)
    .await
    .expect("Failed to create plc_readings table");

    // Phase 6: persist runtime-added devices
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            protocol TEXT NOT NULL,
            poll_rate_ms INTEGER NOT NULL DEFAULT 1000,
            register_start INTEGER NOT NULL,
            register_count INTEGER NOT NULL,
            writable TEXT NOT NULL DEFAULT '[]'
        )"
    )
    .execute(&pool)
    .await
    .expect("Failed to create devices table");

    tracing::info!("Database initialized: {}", path);
    pool
}

// ── Device persistence ──────────────────────────────────────────

/// Save a runtime-added device to the database.
pub async fn save_device(pool: &SqlitePool, dev: &DeviceConfig) {
    let writable_json = serde_json::to_string(&dev.writable).unwrap_or_default();
    sqlx::query(
        "INSERT OR REPLACE INTO devices (id, name, address, protocol, poll_rate_ms, register_start, register_count, writable)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(&dev.id)
    .bind(&dev.name)
    .bind(&dev.address)
    .bind(&dev.protocol)
    .bind(dev.poll_rate_ms as i64)
    .bind(dev.register_start as i64)
    .bind(dev.register_count as i64)
    .bind(&writable_json)
    .execute(pool)
    .await
    .ok();
}

/// Load all runtime-added devices from the database.
pub async fn load_devices(pool: &SqlitePool) -> Vec<DeviceConfig> {
    let rows = sqlx::query_as::<_, (String, String, String, String, i64, i64, i64, String)>(
        "SELECT id, name, address, protocol, poll_rate_ms, register_start, register_count, writable FROM devices"
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.into_iter()
        .map(|(id, name, address, protocol, poll_rate_ms, register_start, register_count, writable)| {
            let writable: Vec<u16> = serde_json::from_str(&writable).unwrap_or_default();
            DeviceConfig {
                id,
                name,
                address,
                protocol,
                poll_rate_ms: poll_rate_ms as u64,
                register_start: register_start as u16,
                register_count: register_count as u16,
                writable,
            }
        })
        .collect()
}

/// Remove a runtime-added device from the database.
pub async fn delete_device(pool: &SqlitePool, device_id: &str) {
    sqlx::query("DELETE FROM devices WHERE id = ?")
        .bind(device_id)
        .execute(pool)
        .await
        .ok();
}

// ── PLC readings ────────────────────────────────────────────────

//save plc reading in DB

pub async fn save_plc_data(pool: &SqlitePool, data: &PlcData) {
    let timestamp = data.timestamp.to_rfc3339();

    sqlx::query(
        "INSERT INTO plc_readings (device_id, register, value, timestamp)
         VALUES (?, ?, ?, ?)"
    )
    .bind(&data.device_id)
    .bind(data.register as i64)
    .bind(data.value)
    .bind(&timestamp)
    .execute(pool)
    .await
    .ok(); // silently ignore errors (log later)
}

// retrive historical data - last N readings for a device

pub async fn get_history(pool: &SqlitePool, device_id: &str, limit: i64) -> Vec<PlcData> {
    let rows = sqlx::query_as::<_, (String, i64, f64, String)>(
        "SELECT device_id, register, value, timestamp
         FROM plc_readings
         WHERE device_id = ?
         ORDER BY id DESC
         LIMIT ?"
    )
    .bind(device_id)
    .bind(limit)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.into_iter()
    .filter_map(|(device_id, register, value, timestamp)|{
        let ts = timestamp.parse::<chrono::DateTime<chrono::Utc>>().ok()?;
        Some(PlcData {
            device_id,
            register: register as u16,
            value,
            timestamp: ts,
        })
    })
    .collect()
}