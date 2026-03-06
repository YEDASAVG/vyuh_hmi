use axum::{
    Json,
    extract::{Path, Query, State, Request},
};
use serde::Deserialize;
use tokio::sync::mpsc;
use tracing::info;

use crate::auth::{self, Claims};
use crate::config::DeviceConfig;
use crate::db;
use crate::discovery;
use crate::modbus::ModbusClient;
use crate::opcua_client::OpcUaClient;
use crate::models::{
    AckAlarmRequest, AddDeviceRequest, AlarmQueryParams, ApiResponse, BatchQueryParams,
    BrowseOpcUaRequest, PlcData, PlcDevice, ScanRequest, ShelveAlarmRequest, WriteRequest,
};
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
        "opcua" => Box::new(OpcUaClient::new(&dev_config.address)),
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

// ── POST /api/devices/:id/disconnect ───────────────────────────
// Stop polling a device — keeps it in the registry so it shows as OFFLINE.
pub async fn disconnect_device(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Json<ApiResponse<String>> {
    let mut registry = state.devices.write().await;

    let Some(handle) = registry.get_mut(&device_id) else {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Device '{}' not found", device_id)),
        });
    };

    if handle.task.is_finished() {
        return Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("Device '{}' is already disconnected", device_id)),
        });
    }

    handle.task.abort();
    info!("Device '{}' disconnected (polling stopped)", device_id);

    Json(ApiResponse {
        success: true,
        data: Some(format!("Device '{}' disconnected", device_id)),
        error: None,
    })
}

// ── POST /api/devices/:id/connect ──────────────────────────────
// Reconnect a previously disconnected device — starts a fresh polling task.
pub async fn connect_device(
    State(state): State<AppState>,
    Path(device_id): Path<String>,
) -> Json<ApiResponse<PlcDevice>> {
    // Read current config from registry
    let config = {
        let registry = state.devices.read().await;
        let Some(handle) = registry.get(&device_id) else {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Device '{}' not found", device_id)),
            });
        };

        if !handle.task.is_finished() {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Device '{}' is already connected", device_id)),
            });
        }

        handle.config.clone()
    };

    // Create a new protocol client
    let client: Box<dyn protocol::PlcProtocol> = match config.protocol.as_str() {
        "modbus" => Box::new(ModbusClient::new(&config.address)),
        "opcua" => Box::new(OpcUaClient::new(&config.address)),
        other => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Unsupported protocol: {}", other)),
            });
        }
    };

    // Start new polling task with a fresh write channel
    let (write_tx, write_rx) = mpsc::channel(32);
    let task = protocol::start_device_polling(
        config.clone(),
        client,
        state.tx.clone(),
        state.db.clone(),
        write_rx,
    );

    // Update registry with new task + write channel
    {
        let mut registry = state.devices.write().await;
        if let Some(handle) = registry.get_mut(&device_id) {
            handle.task = task;
            handle.write_tx = write_tx;
        }
    }

    info!("Device '{}' reconnected → {}", device_id, config.address);

    Json(ApiResponse {
        success: true,
        data: Some(PlcDevice {
            id: config.id.clone(),
            name: config.name.clone(),
            address: config.address.clone(),
            protocol: config.protocol.clone(),
            is_connected: true,
        }),
        error: None,
    })
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

// ── POST /api/browse/opcua ──────────────────────────────────────
// Browse nodes on an OPC UA server.
pub async fn browse_opcua(
    Json(req): Json<BrowseOpcUaRequest>,
) -> Json<ApiResponse<Vec<discovery::OpcUaNode>>> {
    match discovery::browse_opcua_nodes(&req.url, req.parent_node_id.as_deref()).await {
        Ok(nodes) => Json(ApiResponse {
            success: true,
            data: Some(nodes),
            error: None,
        }),
        Err(e) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some(e),
        }),
    }
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
// Now extracts user info from auth middleware for audit trail.
pub async fn post_write(
    State(state): State<AppState>,
    request: Request,
) -> Json<ApiResponse<String>> {
    // Extract auth claims (injected by operator middleware)
    let claims = request.extensions().get::<Claims>().cloned();

    // Parse body
    let body = match axum::body::to_bytes(request.into_body(), 1024 * 16).await {
        Ok(b) => b,
        Err(_) => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some("Invalid request body".to_string()),
            });
        }
    };
    let req: WriteRequest = match serde_json::from_slice(&body) {
        Ok(r) => r,
        Err(e) => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid JSON: {e}")),
            });
        }
    };

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
        Ok(Ok(())) => {
            // Audit trail: log the write operation
            if let Some(ref claims) = claims {
                let details = serde_json::json!({
                    "register": req.register,
                    "value": req.value,
                })
                .to_string();
                auth::log_audit(
                    &state.db,
                    &claims.user_id,
                    &claims.sub,
                    "write_register",
                    Some(&req.device_id),
                    &details,
                    None,
                )
                .await;
            }

            Json(ApiResponse {
                success: true,
                data: Some(format!("[{}] Register {} = {}", req.device_id, req.register, req.value)),
                error: None,
            })
        }
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

// ── ISA-18.2: Alarm Routes ──────────────────────────────────────

/// GET /api/alarms — list alarms with optional filters.
pub async fn list_alarms(
    State(state): State<AppState>,
    Query(params): Query<AlarmQueryParams>,
) -> Json<ApiResponse<Vec<crate::models::Alarm>>> {
    // Un-shelve any expired alarms first
    db::unshelve_expired(&state.db).await;

    let alarms = db::list_alarms(&state.db, &params).await;
    Json(ApiResponse {
        success: true,
        data: Some(alarms),
        error: None,
    })
}

/// GET /api/alarms/:id — get a single alarm.
pub async fn get_alarm(
    State(state): State<AppState>,
    Path(alarm_id): Path<i64>,
) -> Json<ApiResponse<crate::models::Alarm>> {
    match db::get_alarm(&state.db, alarm_id).await {
        Some(alarm) => Json(ApiResponse {
            success: true,
            data: Some(alarm),
            error: None,
        }),
        None => Json(ApiResponse {
            success: false,
            data: None,
            error: Some("Alarm not found".into()),
        }),
    }
}

/// POST /api/alarms/:id/ack — acknowledge an alarm (operator+).
pub async fn ack_alarm(
    State(state): State<AppState>,
    Path(alarm_id): Path<i64>,
    request: Request,
) -> Json<ApiResponse<String>> {
    let claims = request.extensions().get::<Claims>().cloned();
    let username = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_default();

    // Parse optional body
    let body = axum::body::to_bytes(request.into_body(), 1024 * 4)
        .await
        .unwrap_or_default();
    let req: AckAlarmRequest = serde_json::from_slice(&body).unwrap_or(AckAlarmRequest { comment: None });

    match db::ack_alarm(&state.db, alarm_id, &username, req.comment.as_deref()).await {
        Ok(()) => {
            // Audit trail
            if let Some(ref claims) = claims {
                auth::log_audit(
                    &state.db,
                    &claims.user_id,
                    &claims.sub,
                    "alarm_ack",
                    None,
                    &format!("Acknowledged alarm #{alarm_id}"),
                    None,
                )
                .await;
            }
            Json(ApiResponse {
                success: true,
                data: Some(format!("Alarm #{alarm_id} acknowledged")),
                error: None,
            })
        }
        Err(e) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some(e),
        }),
    }
}

/// POST /api/alarms/:id/shelve — shelve an alarm temporarily.
pub async fn shelve_alarm(
    State(state): State<AppState>,
    Path(alarm_id): Path<i64>,
    request: Request,
) -> Json<ApiResponse<String>> {
    let claims = request.extensions().get::<Claims>().cloned();
    let username = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_default();

    let body = axum::body::to_bytes(request.into_body(), 1024 * 4)
        .await
        .unwrap_or_default();

    let req: ShelveAlarmRequest = match serde_json::from_slice(&body) {
        Ok(r) => r,
        Err(e) => {
            return Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid JSON: {e}")),
            });
        }
    };

    match db::shelve_alarm(&state.db, alarm_id, &username, req.duration_minutes, &req.reason).await {
        Ok(()) => {
            if let Some(ref claims) = claims {
                auth::log_audit(
                    &state.db,
                    &claims.user_id,
                    &claims.sub,
                    "alarm_shelve",
                    None,
                    &format!("Shelved alarm #{alarm_id} for {} min: {}", req.duration_minutes, req.reason),
                    None,
                )
                .await;
            }
            Json(ApiResponse {
                success: true,
                data: Some(format!("Alarm #{alarm_id} shelved for {} minutes", req.duration_minutes)),
                error: None,
            })
        }
        Err(e) => Json(ApiResponse {
            success: false,
            data: None,
            error: Some(e),
        }),
    }
}

// ── ISA-88: Batch Record Routes ─────────────────────────────────

/// GET /api/batches — list batch records.
pub async fn list_batches(
    State(state): State<AppState>,
    Query(params): Query<BatchQueryParams>,
) -> Json<ApiResponse<Vec<crate::models::BatchRecord>>> {
    let batches = db::list_batches(&state.db, &params).await;
    Json(ApiResponse {
        success: true,
        data: Some(batches),
        error: None,
    })
}

/// GET /api/batches/:id — get a single batch with steps.
pub async fn get_batch(
    State(state): State<AppState>,
    Path(batch_id): Path<String>,
) -> Json<ApiResponse<serde_json::Value>> {
    match db::get_batch_with_steps(&state.db, &batch_id).await {
        Some((record, steps)) => {
            let data = serde_json::json!({
                "record": record,
                "steps": steps,
            });
            Json(ApiResponse {
                success: true,
                data: Some(data),
                error: None,
            })
        }
        None => Json(ApiResponse {
            success: false,
            data: None,
            error: Some("Batch not found".into()),
        }),
    }
}
