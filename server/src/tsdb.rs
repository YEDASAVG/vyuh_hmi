//! Phase 10.2: Time-Series Database Adapter
//!
//! Defines a trait-based adapter so the storage backend can be swapped
//! from SQLite to InfluxDB, TimescaleDB, or QuestDB without changing
//! the rest of the application.
//!
//! Current implementation: SQLite (via sqlx). To add a new backend,
//! implement the `TimeSeriesStore` trait and wire it in `main.rs`.

use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::models::PlcData;

/// Trait for storing and querying time-series PLC readings.
///
/// Implement this for each backend (SQLite, InfluxDB, TimescaleDB, etc.).
#[async_trait]
pub trait TimeSeriesStore: Send + Sync + 'static {
    /// Insert a single reading.
    async fn insert(&self, data: &PlcData);
    /// Query history for a device, most recent first.
    async fn query(&self, device_id: &str, limit: i64) -> Vec<PlcData>;
    /// Query history for a device within a time range.
    async fn query_range(
        &self,
        device_id: &str,
        from: &str,
        to: &str,
        limit: i64,
    ) -> Vec<PlcData>;
    /// Delete readings older than `days` days.  Returns count deleted.
    async fn purge_older_than(&self, days: i64) -> u64;
}

// ─────────────────────────────────────────────────────────────────
// SQLite backend (default)
// ─────────────────────────────────────────────────────────────────

/// SQLite-backed time-series store. Production-ready for single-node
/// deployments. For high-throughput multi-node, swap to InfluxDB adapter.
pub struct SqliteTimeSeries {
    pool: SqlitePool,
}

impl SqliteTimeSeries {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl TimeSeriesStore for SqliteTimeSeries {
    async fn insert(&self, data: &PlcData) {
        sqlx::query(
            "INSERT INTO plc_readings (device_id, register, value, timestamp) VALUES (?, ?, ?, ?)",
        )
        .bind(&data.device_id)
        .bind(data.register as i64)
        .bind(data.value)
        .bind(data.timestamp.to_rfc3339())
        .execute(&self.pool)
        .await
        .ok();
    }

    async fn query(&self, device_id: &str, limit: i64) -> Vec<PlcData> {
        crate::db::get_history(&self.pool, device_id, limit).await
    }

    async fn query_range(
        &self,
        device_id: &str,
        from: &str,
        to: &str,
        limit: i64,
    ) -> Vec<PlcData> {
        sqlx::query_as::<_, (String, i64, f64, String)>(
            "SELECT device_id, register, value, timestamp FROM plc_readings
             WHERE device_id = ? AND timestamp >= ? AND timestamp <= ?
             ORDER BY timestamp DESC LIMIT ?",
        )
        .bind(device_id)
        .bind(from)
        .bind(to)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|(did, reg, val, ts)| PlcData {
            device_id: did,
            register: reg as u16,
            value: val,
            timestamp: chrono::DateTime::parse_from_rfc3339(&ts)
                .map(|dt| dt.with_timezone(&chrono::Utc))
                .unwrap_or_else(|_| chrono::Utc::now()),
        })
        .collect()
    }

    async fn purge_older_than(&self, days: i64) -> u64 {
        let cutoff = (chrono::Utc::now() - chrono::Duration::days(days)).to_rfc3339();
        let result = sqlx::query("DELETE FROM plc_readings WHERE timestamp < ?")
            .bind(cutoff)
            .execute(&self.pool)
            .await;
        result.map(|r| r.rows_affected()).unwrap_or(0)
    }
}

// ─────────────────────────────────────────────────────────────────
// Stub: InfluxDB backend (for future implementation)
// ─────────────────────────────────────────────────────────────────

// To implement:
//
// pub struct InfluxTimeSeries { client: influxdb2::Client, bucket: String }
//
// #[async_trait]
// impl TimeSeriesStore for InfluxTimeSeries {
//     async fn insert(&self, data: &PlcData) { /* Influx write */ }
//     async fn query(&self, device_id: &str, limit: i64) -> Vec<PlcData> { /* Flux query */ }
//     ...
// }
