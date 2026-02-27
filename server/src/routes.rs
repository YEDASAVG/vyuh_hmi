use axum::{
    Json,
    extract::{Query, State},
};

use serde::Deserialize;

use crate::db;
use crate::models::{ApiResponse, PlcData, PlcDevice};
use crate::state::AppState;

// query param for history endpoint
#[derive(Deserialize)]
pub struct HistoryParams {
    pub device_id: String,
    pub limit: Option<i64>,
}

// get /api/devices -> list all known PLC devices
pub async fn get_devices(State(_state): State<AppState>) -> Json<ApiResponse<Vec<PlcDevice>>> {
    // for now returning hardcoded device list
    // Later query from SQLite device registry
    let devices = vec![PlcDevice {
        id: "plc-01".to_string(),
        name: "Reactor Temperature PLC".to_string(),
        address: "192.168.0.105:502".to_string(),
        protocol: "modbus".to_string(),
        is_connected: false,
    }];
    Json(ApiResponse {
        success: true,
        data: Some(devices),
        error: None,
    })
}

// Get /api/history?device_id-plc-01&limit=50
pub async fn get_history(
    State(state): State<AppState>,
    Query(params): Query<HistoryParams>,
) -> Json<ApiResponse<Vec<PlcData>>> {
    let limit = params.limit.unwrap_or(100);
    let history = db::get_history(&state.db, &params.device_id, limit).await;

    Json(ApiResponse { success: true, data: Some(history), error: None })
}