use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use tokio::sync::mpsc;
use tracing::info;

use crate::config::DeviceConfig;
use crate::db;
use crate::discovery;
use crate::modbus::ModbusClient;
use crate::models::{AddDeviceRequest, ApiResponse, PlcData, PlcDevice, ScanRequest, WriteRequest};
use crate::protocol;
use crate::state::{AppState, DeviceHandle, WriteCommand};

// query param for history endpoint
#[derive(Deserialize)]
pub struct HistoryParams {
    pub device_id: String,
    pub limit: Option<i64>,
}

// ── GET /api/devices ────────────────────────────────────────────
// List all active devices with REAL connection status.
pub async fn get_devices(State(state): State<AppState>) -> Json<ApiResponse<Vec<PlcDevice>>> {
    let registry = state.devices.read().await;
    let devices: Vec<PlcDevice> = registry
        .values()
        .map(|handle| PlcDevice {
            id: handle.config.id.clone(),
            name: handle.config.name.clone(),
            address: handle.config.address.clone(),
            protocol: handle.config.protocol.clone(),
            is_connected: !handle.task.is_finished(),
        })
        .collect();

    Json(ApiResponse {
        success: true,
        data: Some(devices),
        error: None,
    })
}

// ── POST /api/devices ───────────────────────────────────────────
// Add a new device at runtime — starts polling immediately.
pub async fn add_device(
    State(state): State<AppState>,
    Json(req): Json<AddDeviceRequest>,
) -> Json<ApiResponse<PlcDevice>> {
    // Check if device already exists
    {
        let registry = state.devices.read().await;
        if registry.contains_key(&req.id) {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Device '{}' already exists", req.id)),
            });
        }
    }

    let dev_config = DeviceConfig {
        id: req.id.clone(),
        name: req.name.clone(),
        address: req.address.clone(),
        protocol: req.protocol.clone(),
        poll_rate_ms: req.poll_rate_ms.unwrap_or(1000),
        register_start: req.register_start,
        register_count: req.register_count,
        writable: req.writable.clone(),
    };

    // Create protocol client
    let client: Box<dyn protocol::PlcProtocol> = match dev_config.protocol.as_str() {
        "modbus" => Box::new(ModbusClient::new(&dev_config.address)),
        other => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Unsupported protocol: {}", other)),
            });
        }
    };

    // Create per-device write channel and start polling
    let (write_tx, write_rx) = mpsc::channel(32);
    let task = protocol::start_device_polling(
        dev_config.clone(),
        client,
        state.tx.clone(),
        state.db.clone(),
        write_rx,
    );

    let device = PlcDevice {
        id: dev_config.id.clone(),
        name: dev_config.name.clone(),
        address: dev_config.address.clone(),
        protocol: dev_config.protocol.clone(),
        is_connected: true,
    };

    // Register in device registry
    {
        let mut registry = state.devices.write().await;
        registry.insert(
            dev_config.id.clone(),
            DeviceHandle {
                write_tx,
                task,
                config: dev_config.clone(),
            },
        );
    }

    // Persist to DB (survives restart)
    db::save_device(&state.db, &dev_config).await;

    info!("Device '{}' added at runtime → {}", req.id, req.address);

    Json(ApiResponse {
        success: true,
        data: Some(device),
        error: None,
    })
}

// ── DELETE /api/devices/:id ─────────────────────────────────────
// Remove a device — stops polling task.
pub async fn remove_device(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Json<ApiResponse<String>> {
    let mut registry = state.devices.write().await;

    if let Some(handle) = registry.remove(&device_id) {
        handle.task.abort(); // kill the polling task
        db::delete_device(&state.db, &device_id).await;
        info!("Device '{}' removed", device_id);
        Json(ApiResponse {
            success: true,
            data: Some(format!("Device '{}' removed", device_id)),
            error: None,
        })
    } else {
        Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Device '{}' not found", device_id)),
        })
    }
}

// ── POST /api/discover ──────────────────────────────────────────
// Scan the network for Modbus devices.
pub async fn discover_devices(
    Json(req): Json<Option<ScanRequest>>,
) -> Json<ApiResponse<Vec<discovery::DiscoveredDevice>>> {
    let (default_targets, default_ports) = discovery::default_scan_targets();

    let targets = req
        .as_ref()
        .and_then(|r| r.targets.clone())
        .unwrap_or(default_targets);
    let ports = req
        .as_ref()
        .and_then(|r| r.ports.clone())
        .unwrap_or(default_ports);

    let found = discovery::scan_network(&targets, &ports).await;

    Json(ApiResponse {
        success: true,
        data: Some(found),
        error: None,
    })
}

// ── GET /api/history ────────────────────────────────────────────
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

// ── POST /api/write ─────────────────────────────────────────────
// Route write to the correct device's channel.
pub async fn post_write(
    State(state): State<AppState>,
    Json(req): Json<WriteRequest>,
) -> Json<ApiResponse<String>> {
    // Find the device in registry
    let registry = state.devices.read().await;
    let Some(handle) = registry.get(&req.device_id) else {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Unknown device: {}", req.device_id)),
        });
    };

    // Validate writable registers
    if !handle.config.writable.contains(&req.register) {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Register {} is not writable on '{}'", req.register, req.device_id)),
        });
    }

    // Send write command through this device's channel
    let (resp_tx, resp_rx) = tokio::sync::oneshot::channel();
    let cmd = WriteCommand {
        register: req.register,
        value: req.value,
        response: resp_tx,
    };

    if let Err(e) = handle.write_tx.send(cmd).await {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Failed to queue write: {}", e)),
        });
    }

    // Must drop the read lock before awaiting the response
    drop(registry);

    match resp_rx.await {
        Ok(Ok(())) => Json(ApiResponse {
            success: true,
            data: Some(format!("[{}] Register {} = {}", req.device_id, req.register, req.value)),
            error: None,
        }),
        Ok(Err(e)) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Write failed: {}", e)),
        }),
        Err(_) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some("Write channel dropped".to_string()),
        }),
    }
}
