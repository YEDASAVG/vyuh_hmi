use crate::models::PlcData;
use sqlx::{SqlitePool, sqlite::SqlitePoolOptions};

//Initialize the DB -> create file + create tables

pub async fn init_db() -> SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect("sqlite:hmi_data.db?mode=rwc") // rwc = read,write,create
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
    .expect("Failed to create table");

    tracing::info!("Database initialized: hmi_data.db");
    pool
}

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