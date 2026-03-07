use crate::config::DeviceConfig;
use crate::models::{
    Alarm, AlarmPriority, AlarmQueryParams, AlarmState, BatchQueryParams, BatchRecord, BatchStep,
    BatchStatus, PlcData, RaiseAlarmRequest,
};
use sqlx::{SqlitePool, sqlite::SqlitePoolOptions};

//Initialize the DB -> create file + create tables

pub async fn init_db(path: &str) -> SqlitePool {
    let url = format!("sqlite:{}?mode=rwc", path);
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .expect("Failed to connect to SQLite");

    init_db_with_pool(&pool).await;
    tracing::info!("Database initialized: {}", path);
    pool
}

/// Initialize all tables given an existing pool (useful for in-memory testing).
pub async fn init_db_with_pool(pool: &SqlitePool) {
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
    .execute(pool)
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
    .execute(pool)
    .await
    .expect("Failed to create devices table");

    // ── ISA-18.2: Alarm history table ───────────────────────────
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS alarms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            register INTEGER NOT NULL,
            label TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 3,
            state TEXT NOT NULL DEFAULT 'active',
            value REAL NOT NULL,
            threshold REAL NOT NULL,
            message TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            acked_by TEXT,
            acked_at TEXT,
            shelved_until TEXT,
            shelved_by TEXT,
            cleared_at TEXT
        )",
    )
    .execute(pool)
    .await
    .expect("Failed to create alarms table");

    // ── ISA-88: Batch records ───────────────────────────────────
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS batch_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            batch_id TEXT NOT NULL UNIQUE,
            recipe_name TEXT NOT NULL,
            device_id TEXT NOT NULL,
            operator TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'running',
            start_time TEXT NOT NULL,
            end_time TEXT,
            notes TEXT
        )",
    )
    .execute(pool)
    .await
    .expect("Failed to create batch_records table");

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS batch_steps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            batch_record_id INTEGER NOT NULL REFERENCES batch_records(id),
            step_number INTEGER NOT NULL,
            name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            start_time TEXT NOT NULL,
            end_time TEXT,
            parameters TEXT,
            result TEXT
        )",
    )
    .execute(pool)
    .await
    .expect("Failed to create batch_steps table");
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
    .map_err(|e| {
        tracing::error!("CRITICAL: Failed to save PLC reading for {}/{}: {}", data.device_id, data.register, e);
        e
    })
    .ok();
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

// ── ISA-18.2: Alarm operations ──────────────────────────────────

/// Raise a new alarm (insert into DB). Returns the new alarm ID.
pub async fn raise_alarm(pool: &SqlitePool, req: &RaiseAlarmRequest) -> Option<i64> {
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "INSERT INTO alarms (device_id, register, label, priority, state, value, threshold, message, timestamp)
         VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?)",
    )
    .bind(&req.device_id)
    .bind(req.register as i64)
    .bind(&req.label)
    .bind(req.priority.as_i32())
    .bind(req.value)
    .bind(req.threshold)
    .bind(&req.message)
    .bind(&now)
    .execute(pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to raise alarm: {}", e);
        e
    })
    .ok()?;

    Some(result.last_insert_rowid())
}

/// Check if there's already an active/unresolved alarm for this device+register.
pub async fn has_active_alarm(pool: &SqlitePool, device_id: &str, register: u16) -> bool {
    let row = sqlx::query_as::<_, (i64,)>(
        "SELECT COUNT(*) FROM alarms WHERE device_id = ? AND register = ? AND state IN ('active', 'acknowledged')",
    )
    .bind(device_id)
    .bind(register as i64)
    .fetch_one(pool)
    .await
    .unwrap_or((0,));

    row.0 > 0
}

/// Get the ID of an active alarm for device+register (for auto-clearing).
pub async fn get_active_alarm_id(pool: &SqlitePool, device_id: &str, register: u16) -> Option<i64> {
    sqlx::query_as::<_, (i64,)>(
        "SELECT id FROM alarms WHERE device_id = ? AND register = ? AND state IN ('active', 'acknowledged') ORDER BY id DESC LIMIT 1",
    )
    .bind(device_id)
    .bind(register as i64)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()
    .map(|r| r.0)
}

/// Get the most recent running batch for a device.
pub async fn get_running_batch(pool: &SqlitePool, device_id: &str) -> Option<(i64, String)> {
    sqlx::query_as::<_, (i64, String)>(
        "SELECT id, batch_id FROM batch_records WHERE device_id = ? AND status = 'running' ORDER BY id DESC LIMIT 1",
    )
    .bind(device_id)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()
}

/// Acknowledge an alarm — operator confirmation.
pub async fn ack_alarm(
    pool: &SqlitePool,
    alarm_id: i64,
    username: &str,
    comment: Option<&str>,
) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();

    // Verify alarm exists and is in 'active' state
    let row = sqlx::query_as::<_, (String,)>("SELECT state FROM alarms WHERE id = ?")
        .bind(alarm_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| format!("DB error: {e}"))?;

    let Some((state,)) = row else {
        return Err("Alarm not found".into());
    };

    if state != "active" {
        return Err(format!("Cannot acknowledge alarm in '{state}' state"));
    }

    let mut message_update = String::new();
    if let Some(c) = comment {
        message_update = format!(" — Ack comment: {c}");
    }

    sqlx::query(
        "UPDATE alarms SET state = 'acknowledged', acked_by = ?, acked_at = ?,
         message = message || ? WHERE id = ?",
    )
    .bind(username)
    .bind(&now)
    .bind(&message_update)
    .bind(alarm_id)
    .execute(pool)
    .await
    .map_err(|e| format!("Failed to ack alarm: {e}"))?;

    Ok(())
}

/// Shelve an alarm — temporarily suppress for the given duration.
pub async fn shelve_alarm(
    pool: &SqlitePool,
    alarm_id: i64,
    username: &str,
    duration_minutes: u32,
    _reason: &str,
) -> Result<(), String> {
    // Max 8 hours
    let mins = duration_minutes.min(480);
    let until =
        chrono::Utc::now() + chrono::Duration::minutes(mins as i64);
    let until_str = until.to_rfc3339();

    let row = sqlx::query_as::<_, (String,)>("SELECT state FROM alarms WHERE id = ?")
        .bind(alarm_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| format!("DB error: {e}"))?;

    let Some((state,)) = row else {
        return Err("Alarm not found".into());
    };

    if state == "cleared" {
        return Err("Cannot shelve a cleared alarm".into());
    }

    sqlx::query(
        "UPDATE alarms SET state = 'shelved', shelved_until = ?, shelved_by = ? WHERE id = ?",
    )
    .bind(&until_str)
    .bind(username)
    .bind(alarm_id)
    .execute(pool)
    .await
    .map_err(|e| format!("Failed to shelve alarm: {e}"))?;

    Ok(())
}

/// Clear an alarm — condition has returned to normal.
pub async fn clear_alarm(pool: &SqlitePool, alarm_id: i64) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query("UPDATE alarms SET state = 'cleared', cleared_at = ? WHERE id = ? AND state != 'cleared'")
        .bind(&now)
        .bind(alarm_id)
        .execute(pool)
        .await
        .map_err(|e| format!("Failed to clear alarm: {e}"))?;

    Ok(())
}

/// Un-shelve expired alarms (call periodically).
pub async fn unshelve_expired(pool: &SqlitePool) {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE alarms SET state = 'active', shelved_until = NULL, shelved_by = NULL
         WHERE state = 'shelved' AND shelved_until IS NOT NULL AND shelved_until < ?",
    )
    .bind(&now)
    .execute(pool)
    .await
    .ok();
}

/// List alarms with optional filters.
pub async fn list_alarms(pool: &SqlitePool, params: &AlarmQueryParams) -> Vec<Alarm> {
    let limit = params.limit.unwrap_or(200);

    // Build dynamic WHERE clauses
    let mut conditions = Vec::new();
    let mut bind_values: Vec<String> = Vec::new();

    if let Some(ref device_id) = params.device_id {
        conditions.push("device_id = ?".to_string());
        bind_values.push(device_id.clone());
    }
    if let Some(ref state) = params.state {
        conditions.push("state = ?".to_string());
        bind_values.push(state.clone());
    }
    if let Some(priority) = params.priority {
        conditions.push("priority = ?".to_string());
        bind_values.push(priority.to_string());
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    let sql = format!(
        "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
         FROM alarms {where_clause} ORDER BY id DESC LIMIT {limit}"
    );

    // We'll use a simple approach: build the query dynamically
    let rows = sqlx::query_as::<_, (
        i64, String, i64, String, i32, String, f64, f64, String,
        String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
    )>(&sql)
    .fetch_all(pool)
    .await;

    // Note: sqlx dynamic binding is cumbersome, so for the MVP we'll use
    // the simpler approach of separate queries per filter combination.
    // For a more robust solution, consider using sqlx::QueryBuilder.

    // Actually let's just do separate filtered queries:
    drop(rows); // ignore the above

    let rows = if params.device_id.is_some() && params.state.is_some() && params.priority.is_some() {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms WHERE device_id = ? AND state = ? AND priority = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.device_id.as_deref().unwrap())
        .bind(params.state.as_deref().unwrap())
        .bind(params.priority.unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.device_id.is_some() && params.state.is_some() {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms WHERE device_id = ? AND state = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.device_id.as_deref().unwrap())
        .bind(params.state.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.device_id.is_some() {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms WHERE device_id = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.device_id.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.state.is_some() {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms WHERE state = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.state.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.priority.is_some() {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms WHERE priority = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.priority.unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as::<_, (
            i64, String, i64, String, i32, String, f64, f64, String,
            String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
        )>(
            "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                    timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
             FROM alarms ORDER BY id DESC LIMIT ?"
        )
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    };

    rows.into_iter()
        .map(|(id, device_id, register, label, priority, state, value, threshold, message,
               timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at)| {
            Alarm {
                id,
                device_id,
                register: register as u16,
                label,
                priority: AlarmPriority::from_i32(priority),
                state: AlarmState::from_str(&state),
                value,
                threshold,
                message,
                timestamp,
                acked_by,
                acked_at,
                shelved_until,
                shelved_by,
                cleared_at,
            }
        })
        .collect()
}

/// Get a single alarm by ID.
pub async fn get_alarm(pool: &SqlitePool, alarm_id: i64) -> Option<Alarm> {
    let row = sqlx::query_as::<_, (
        i64, String, i64, String, i32, String, f64, f64, String,
        String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>,
    )>(
        "SELECT id, device_id, register, label, priority, state, value, threshold, message,
                timestamp, acked_by, acked_at, shelved_until, shelved_by, cleared_at
         FROM alarms WHERE id = ?",
    )
    .bind(alarm_id)
    .fetch_optional(pool)
    .await
    .ok()??;

    Some(Alarm {
        id: row.0,
        device_id: row.1,
        register: row.2 as u16,
        label: row.3,
        priority: AlarmPriority::from_i32(row.4),
        state: AlarmState::from_str(&row.5),
        value: row.6,
        threshold: row.7,
        message: row.8,
        timestamp: row.9,
        acked_by: row.10,
        acked_at: row.11,
        shelved_until: row.12,
        shelved_by: row.13,
        cleared_at: row.14,
    })
}

// ── ISA-88: Batch record operations ─────────────────────────────

/// Create a new batch record.
pub async fn create_batch(
    pool: &SqlitePool,
    batch_id: &str,
    recipe_name: &str,
    device_id: &str,
    operator: &str,
) -> Option<i64> {
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "INSERT INTO batch_records (batch_id, recipe_name, device_id, operator, status, start_time)
         VALUES (?, ?, ?, ?, 'running', ?)",
    )
    .bind(batch_id)
    .bind(recipe_name)
    .bind(device_id)
    .bind(operator)
    .bind(&now)
    .execute(pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to create batch record: {}", e);
        e
    })
    .ok()?;

    Some(result.last_insert_rowid())
}

/// Update batch status.
pub async fn update_batch_status(
    pool: &SqlitePool,
    batch_id: &str,
    status: &str,
    notes: Option<&str>,
) -> Result<(), String> {
    let end_time = if status == "completed" || status == "aborted" {
        Some(chrono::Utc::now().to_rfc3339())
    } else {
        None
    };

    sqlx::query(
        "UPDATE batch_records SET status = ?, end_time = COALESCE(?, end_time), notes = COALESCE(?, notes)
         WHERE batch_id = ?",
    )
    .bind(status)
    .bind(&end_time)
    .bind(notes)
    .bind(batch_id)
    .execute(pool)
    .await
    .map_err(|e| format!("Failed to update batch: {e}"))?;

    Ok(())
}

/// Add a step to a batch record.
pub async fn add_batch_step(
    pool: &SqlitePool,
    batch_record_id: i64,
    step_number: i32,
    name: &str,
    parameters: Option<&str>,
) -> Option<i64> {
    let now = chrono::Utc::now().to_rfc3339();
    let result = sqlx::query(
        "INSERT INTO batch_steps (batch_record_id, step_number, name, status, start_time, parameters)
         VALUES (?, ?, ?, 'running', ?, ?)",
    )
    .bind(batch_record_id)
    .bind(step_number)
    .bind(name)
    .bind(&now)
    .bind(parameters)
    .execute(pool)
    .await
    .ok()?;

    Some(result.last_insert_rowid())
}

/// Complete a batch step.
pub async fn complete_batch_step(
    pool: &SqlitePool,
    step_id: i64,
    status: &str,
    result_text: Option<&str>,
) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE batch_steps SET status = ?, end_time = ?, result = ? WHERE id = ?")
        .bind(status)
        .bind(&now)
        .bind(result_text)
        .bind(step_id)
        .execute(pool)
        .await
        .map_err(|e| format!("Failed to complete batch step: {e}"))?;

    Ok(())
}

/// List batch records with optional filters.
pub async fn list_batches(pool: &SqlitePool, params: &BatchQueryParams) -> Vec<BatchRecord> {
    let limit = params.limit.unwrap_or(100);

    let rows = if params.device_id.is_some() && params.status.is_some() {
        sqlx::query_as::<_, (i64, String, String, String, String, String, String, Option<String>, Option<String>)>(
            "SELECT id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes
             FROM batch_records WHERE device_id = ? AND status = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.device_id.as_deref().unwrap())
        .bind(params.status.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.device_id.is_some() {
        sqlx::query_as::<_, (i64, String, String, String, String, String, String, Option<String>, Option<String>)>(
            "SELECT id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes
             FROM batch_records WHERE device_id = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.device_id.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else if params.status.is_some() {
        sqlx::query_as::<_, (i64, String, String, String, String, String, String, Option<String>, Option<String>)>(
            "SELECT id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes
             FROM batch_records WHERE status = ? ORDER BY id DESC LIMIT ?"
        )
        .bind(params.status.as_deref().unwrap())
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as::<_, (i64, String, String, String, String, String, String, Option<String>, Option<String>)>(
            "SELECT id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes
             FROM batch_records ORDER BY id DESC LIMIT ?"
        )
        .bind(limit)
        .fetch_all(pool)
        .await
        .unwrap_or_default()
    };

    rows.into_iter()
        .map(|(id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes)| {
            BatchRecord {
                id,
                batch_id,
                recipe_name,
                device_id,
                operator,
                status: BatchStatus::from_str(&status),
                start_time,
                end_time,
                notes,
            }
        })
        .collect()
}

/// Get a single batch record with its steps.
pub async fn get_batch_with_steps(pool: &SqlitePool, batch_id: &str) -> Option<(BatchRecord, Vec<BatchStep>)> {
    let row = sqlx::query_as::<_, (i64, String, String, String, String, String, String, Option<String>, Option<String>)>(
        "SELECT id, batch_id, recipe_name, device_id, operator, status, start_time, end_time, notes
         FROM batch_records WHERE batch_id = ?"
    )
    .bind(batch_id)
    .fetch_optional(pool)
    .await
    .ok()??;

    let record = BatchRecord {
        id: row.0,
        batch_id: row.1,
        recipe_name: row.2,
        device_id: row.3,
        operator: row.4,
        status: BatchStatus::from_str(&row.5),
        start_time: row.6,
        end_time: row.7,
        notes: row.8,
    };

    let step_rows = sqlx::query_as::<_, (i64, i64, i32, String, String, String, Option<String>, Option<String>, Option<String>)>(
        "SELECT id, batch_record_id, step_number, name, status, start_time, end_time, parameters, result
         FROM batch_steps WHERE batch_record_id = ? ORDER BY step_number"
    )
    .bind(record.id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let steps: Vec<BatchStep> = step_rows
        .into_iter()
        .map(|(id, batch_record_id, step_number, name, status, start_time, end_time, parameters, result)| {
            BatchStep {
                id,
                batch_record_id,
                step_number,
                name,
                status,
                start_time,
                end_time,
                parameters,
                result,
            }
        })
        .collect();

    Some((record, steps))
}