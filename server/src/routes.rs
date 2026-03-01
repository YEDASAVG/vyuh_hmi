use axum::{
    Json,
    extract::{Query, State},
};
use serde::Deserialize;

use crate::db;
use crate::models::{ApiResponse, PlcData, PlcDevice, WriteRequest};
use crate::state::{AppState, WriteCommand};

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

    Json(ApiResponse {
        success: true,
        data: Some(history),
        error: None,
    })
}

// post write handler

pub async fn post_write(
    State(state): State<AppState>,
    Json(req): Json<WriteRequest>,
) -> Json<ApiResponse<String>> {
    // validation
    let writable_registers: Vec<u16> = vec![1032, 1034]; // batch state, agitator
    if !writable_registers.contains(&req.register) {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Register {} is not writable", req.register)),
        });
    }

    // send write command to modbus task
    let (resp_tx, resp_rx) = tokio::sync::oneshot::channel();
    let cmd = WriteCommand {
        register: req.register,
        value: req.value,
        response: resp_tx,
    };

    // send through mpsc channel to the modbus polling task
    if let Err(e) = state.write_tx.send(cmd).await {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Failed to queue write command: {}", e)),
        });
    }

    // await the result from the modbus task
    match resp_rx.await {
        Ok(Ok(())) => Json(ApiResponse {
            success: true,
            data: Some(format!("Register {} set to {}", req.register, req.value)),
            error: None,
        }),
        Ok(Err(e)) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Modbus write failed: {}", e)),
        }),
        Err(_) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some("Write command response channel dropped".to_string()),
        }),
    }
}
