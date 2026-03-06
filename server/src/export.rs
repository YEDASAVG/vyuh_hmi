//! Phase 10.1: Data Export — CSV reports for alarms, batches, audit trail.
//!
//! Endpoints return `Content-Type: text/csv` with proper headers for download.

use axum::{
    extract::{Query, State},
    http::{HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
};
use serde::Deserialize;

use crate::db;
use crate::models::{AlarmQueryParams, BatchQueryParams};
use crate::state::AppState;

/// Query params for audit CSV export.
#[derive(Debug, Deserialize)]
pub struct AuditExportParams {
    pub user_id: Option<String>,
    pub device_id: Option<String>,
    pub action: Option<String>,
    pub limit: Option<i64>,
}

// ── GET /api/export/alarms.csv ──────────────────────────────────

pub async fn export_alarms_csv(
    State(state): State<AppState>,
    Query(params): Query<AlarmQueryParams>,
) -> Response {
    let alarms = db::list_alarms(&state.db, &params).await;

    let mut wtr = csv::Writer::from_writer(Vec::new());
    // Header
    wtr.write_record([
        "id", "device_id", "register", "label", "priority", "state",
        "value", "threshold", "message", "timestamp",
        "acked_by", "acked_at", "shelved_by", "shelved_until", "cleared_at",
    ]).ok();

    for a in &alarms {
        wtr.write_record([
            &a.id.to_string(),
            &a.device_id,
            &a.register.to_string(),
            &a.label,
            &format!("{:?}", a.priority),
            &format!("{:?}", a.state),
            &a.value.to_string(),
            &a.threshold.to_string(),
            &a.message,
            &a.timestamp,
            a.acked_by.as_deref().unwrap_or(""),
            a.acked_at.as_deref().unwrap_or(""),
            a.shelved_by.as_deref().unwrap_or(""),
            a.shelved_until.as_deref().unwrap_or(""),
            a.cleared_at.as_deref().unwrap_or(""),
        ]).ok();
    }

    let csv_bytes = wtr.into_inner().unwrap_or_default();
    csv_response(csv_bytes, "alarms_export.csv")
}

// ── GET /api/export/batches.csv ─────────────────────────────────

pub async fn export_batches_csv(
    State(state): State<AppState>,
    Query(params): Query<BatchQueryParams>,
) -> Response {
    let batches = db::list_batches(&state.db, &params).await;

    let mut wtr = csv::Writer::from_writer(Vec::new());
    wtr.write_record([
        "id", "batch_id", "recipe_name", "device_id", "operator",
        "status", "start_time", "end_time", "notes",
    ]).ok();

    for b in &batches {
        wtr.write_record([
            &b.id.to_string(),
            &b.batch_id,
            &b.recipe_name,
            &b.device_id,
            &b.operator,
            &format!("{:?}", b.status),
            &b.start_time,
            b.end_time.as_deref().unwrap_or(""),
            b.notes.as_deref().unwrap_or(""),
        ]).ok();
    }

    let csv_bytes = wtr.into_inner().unwrap_or_default();
    csv_response(csv_bytes, "batches_export.csv")
}

// ── GET /api/export/audit.csv ───────────────────────────────────

pub async fn export_audit_csv(
    State(state): State<AppState>,
    Query(params): Query<AuditExportParams>,
) -> Response {
    let limit = params.limit.unwrap_or(1000);

    // Fetch audit entries (reuse the same query pattern from auth.rs)
    let rows = sqlx::query_as::<_, (i64, String, String, String, Option<String>, String, String, Option<String>)>(
        "SELECT id, user_id, username, action, device_id, details, timestamp, ip_address
         FROM audit_trail ORDER BY id DESC LIMIT ?"
    )
    .bind(limit)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let mut wtr = csv::Writer::from_writer(Vec::new());
    wtr.write_record([
        "id", "user_id", "username", "action", "device_id",
        "details", "timestamp", "ip_address",
    ]).ok();

    for (id, user_id, username, action, device_id, details, timestamp, ip_address) in &rows {
        wtr.write_record([
            &id.to_string(),
            user_id,
            username,
            action,
            device_id.as_deref().unwrap_or(""),
            details,
            timestamp,
            ip_address.as_deref().unwrap_or(""),
        ]).ok();
    }

    let csv_bytes = wtr.into_inner().unwrap_or_default();
    csv_response(csv_bytes, "audit_export.csv")
}

// ── GET /api/export/history.csv ─────────────────────────────────

pub async fn export_history_csv(
    State(state): State<AppState>,
    Query(params): Query<HistoryExportParams>,
) -> Response {
    let limit = params.limit.unwrap_or(5000);
    let history = db::get_history(&state.db, &params.device_id, limit).await;

    let mut wtr = csv::Writer::from_writer(Vec::new());
    wtr.write_record(["device_id", "register", "value", "timestamp"]).ok();

    for h in &history {
        wtr.write_record([
            &h.device_id,
            &h.register.to_string(),
            &h.value.to_string(),
            &h.timestamp.to_rfc3339(),
        ]).ok();
    }

    let csv_bytes = wtr.into_inner().unwrap_or_default();
    csv_response(csv_bytes, &format!("{}_history.csv", params.device_id))
}

#[derive(Debug, Deserialize)]
pub struct HistoryExportParams {
    pub device_id: String,
    pub limit: Option<i64>,
}

/// Build a CSV download response with proper headers.
fn csv_response(data: Vec<u8>, filename: &str) -> Response {
    let mut headers = HeaderMap::new();
    headers.insert("content-type", HeaderValue::from_static("text/csv; charset=utf-8"));
    headers.insert(
        "content-disposition",
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .unwrap_or_else(|_| HeaderValue::from_static("attachment; filename=\"export.csv\"")),
    );

    (StatusCode::OK, headers, data).into_response()
}
