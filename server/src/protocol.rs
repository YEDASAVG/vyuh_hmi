use async_trait::async_trait;
use chrono::Utc;
use sqlx::SqlitePool;
use std::time::Duration;
use tokio::sync::{broadcast, mpsc};
use tokio::task::JoinHandle;
use tracing::{error, info, warn};

use crate::config::DeviceConfig;
use crate::db;
use crate::models::{AlarmPriority, PlcData, RaiseAlarmRequest};
use crate::state::WriteCommand;

/// Alarm threshold definition (hardcoded for known registers).
struct AlarmThreshold {
    register: u16,
    label: &'static str,
    warn_high: Option<f64>,
    crit_high: Option<f64>,
    warn_low: Option<f64>,
    crit_low: Option<f64>,
}

/// Known alarm thresholds for the pharma/chemical plant.
const ALARM_THRESHOLDS: &[AlarmThreshold] = &[
    AlarmThreshold { register: 1028, label: "Temperature", warn_high: Some(85.0), crit_high: Some(100.0), warn_low: None, crit_low: None },
    AlarmThreshold { register: 1029, label: "Pressure",    warn_high: Some(1200.0), crit_high: Some(1400.0), warn_low: None, crit_low: None },
];

/// Batch state codes from the simulator.
const BATCH_IDLE: u16 = 0;
const BATCH_HEATING: u16 = 1;
const BATCH_COMPLETE: u16 = 4;

fn batch_phase_name(code: u16) -> &'static str {
    match code {
        0 => "Idle",
        1 => "Heating",
        2 => "Holding",
        3 => "Cooling",
        4 => "Complete",
        _ => "Unknown",
    }
}

// ── PlcProtocol Trait ───────────────────────────────────────────
// Every PLC protocol (Modbus, OPC UA, EtherNet/IP) implements this.
// The polling loop and Flutter app don't care which protocol is used.

#[async_trait]
pub trait PlcProtocol: Send {
    /// Connect to the PLC device.
    async fn connect(&mut self) -> Result<(), String>;

    /// Read holding registers starting at `start` for `count` registers.
    async fn read_registers(&mut self, start: u16, count: u16) -> Result<Vec<u16>, String>;

    /// Write a single register at `address` with `value`.
    async fn write_register(&mut self, address: u16, value: u16) -> Result<(), String>;

    /// Check if the connection is still alive.
    fn is_connected(&self) -> bool;

    /// Protocol name for logging.
    fn protocol_name(&self) -> &str;
}

// ── Generic Polling Loop ────────────────────────────────────────
// Works with ANY PlcProtocol implementation. Reads registers on a
// timer, handles write commands via tokio::select!, auto-reconnects.
// Returns a JoinHandle so the caller can track or abort the task.

pub fn start_device_polling(
    device: DeviceConfig,
    mut client: Box<dyn PlcProtocol>,
    tx: broadcast::Sender<String>,
    db: SqlitePool,
    mut write_rx: mpsc::Receiver<WriteCommand>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let proto = client.protocol_name().to_string();
        info!("[{}] Polling started ({}://{})", device.id, proto, device.address);

        // Batch tracking state
        let mut prev_batch_state: Option<u16> = None;
        let mut batch_counter: u32 = 0;

        loop {
            info!("[{}] Connecting via {}...", device.id, proto);

            match client.connect().await {
                Ok(()) => {
                    info!("[{}] Connected to {} at {}", device.id, proto, device.address);
                    let mut interval =
                        tokio::time::interval(Duration::from_millis(device.poll_rate_ms));

                    // ── Poll + Write loop ──
                    loop {
                        tokio::select! {
                            // Handle write commands from the REST API
                            Some(cmd) = write_rx.recv() => {
                                info!("[{}] Writing register {} = {}", device.id, cmd.register, cmd.value);
                                match client.write_register(cmd.register, cmd.value).await {
                                    Ok(()) => {
                                        info!("[{}] Write OK: reg {} = {}", device.id, cmd.register, cmd.value);
                                        let _ = cmd.response.send(Ok(()));
                                    }
                                    Err(e) => {
                                        error!("[{}] Write failed: {}", device.id, e);
                                        let _ = cmd.response.send(Err(e));
                                        if !client.is_connected() { break; }
                                    }
                                }
                            }
                            // Regular polling tick
                            _ = interval.tick() => {
                                match client.read_registers(device.register_start, device.register_count).await {
                                    Ok(registers) => {
                                        // Build a register map for alarm/batch checks
                                        let mut reg_map: std::collections::HashMap<u16, f64> = std::collections::HashMap::new();

                                        for (i, &value) in registers.iter().enumerate() {
                                            let reg_addr = device.register_start + i as u16;
                                            reg_map.insert(reg_addr, value as f64);

                                            let data = PlcData {
                                                device_id: device.id.clone(),
                                                register: reg_addr,
                                                value: value as f64,
                                                timestamp: Utc::now(),
                                            };
                                            db::save_plc_data(&db, &data).await;
                                            let json = serde_json::to_string(&data).unwrap_or_default();
                                            let _ = tx.send(json);
                                        }

                                        // ── Alarm Monitoring ──
                                        for th in ALARM_THRESHOLDS {
                                            if let Some(&val) = reg_map.get(&th.register) {
                                                let has_alarm = db::has_active_alarm(&db, &device.id, th.register).await;

                                                // Check critical high
                                                if let Some(crit) = th.crit_high {
                                                    if val >= crit && !has_alarm {
                                                        let req = RaiseAlarmRequest {
                                                            device_id: device.id.clone(),
                                                            register: th.register,
                                                            label: th.label.to_string(),
                                                            priority: AlarmPriority::Critical,
                                                            value: val,
                                                            threshold: crit,
                                                            message: format!("CRITICAL: {} {:.1} exceeds {:.0}", th.label, val, crit),
                                                        };
                                                        if let Some(id) = db::raise_alarm(&db, &req).await {
                                                            info!("[{}] 🚨 Alarm raised #{}: {}", device.id, id, req.message);
                                                        }
                                                    }
                                                }
                                                // Check warning high (only if not already critical)
                                                else if let Some(warn) = th.warn_high {
                                                    if val >= warn && !has_alarm {
                                                        let req = RaiseAlarmRequest {
                                                            device_id: device.id.clone(),
                                                            register: th.register,
                                                            label: th.label.to_string(),
                                                            priority: AlarmPriority::High,
                                                            value: val,
                                                            threshold: warn,
                                                            message: format!("WARNING: {} {:.1} approaching limit ({:.0})", th.label, val, warn),
                                                        };
                                                        if let Some(id) = db::raise_alarm(&db, &req).await {
                                                            info!("[{}] ⚠️ Warning raised #{}: {}", device.id, id, req.message);
                                                        }
                                                    }
                                                }

                                                // Auto-clear when value returns to safe range
                                                if has_alarm {
                                                    let below_warn = th.warn_high.map_or(true, |w| val < w * 0.95);
                                                    let above_low = th.warn_low.map_or(true, |w| val > w * 1.05);
                                                    if below_warn && above_low {
                                                        if let Some(alarm_id) = db::get_active_alarm_id(&db, &device.id, th.register).await {
                                                            let _ = db::clear_alarm(&db, alarm_id).await;
                                                            info!("[{}] ✅ Alarm #{} auto-cleared ({} = {:.1})", device.id, alarm_id, th.label, val);
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── Batch Tracking ──
                                        if let Some(&batch_val) = reg_map.get(&1032) {
                                            let batch_state = batch_val as u16;
                                            let prev = prev_batch_state.unwrap_or(batch_state);

                                            // Transition: IDLE → HEATING = new batch started
                                            if prev == BATCH_IDLE && batch_state == BATCH_HEATING {
                                                batch_counter += 1;
                                                let batch_id = format!("BATCH-{}-{:04}", device.id, batch_counter);
                                                info!("[{}] 🧪 Batch started: {}", device.id, batch_id);
                                                let _ = db::create_batch(&db, &batch_id, "Reactor Cycle", &device.id, "system").await;
                                            }

                                            // Transition: any → COMPLETE = batch finished
                                            if prev != BATCH_COMPLETE && batch_state == BATCH_COMPLETE {
                                                if let Some((_row_id, batch_id)) = db::get_running_batch(&db, &device.id).await {
                                                    info!("[{}] ✅ Batch completed: {}", device.id, batch_id);
                                                    let _ = db::update_batch_status(&db, &batch_id, "completed", None).await;
                                                }
                                            }

                                            // Transition: running → IDLE (emergency stop)
                                            if prev != BATCH_IDLE && prev != BATCH_COMPLETE && batch_state == BATCH_IDLE {
                                                if let Some((_row_id, batch_id)) = db::get_running_batch(&db, &device.id).await {
                                                    info!("[{}] 🛑 Batch aborted: {}", device.id, batch_id);
                                                    let _ = db::update_batch_status(&db, &batch_id, "aborted", Some("Emergency stop")).await;
                                                }
                                            }

                                            prev_batch_state = Some(batch_state);
                                        }
                                    }
                                    Err(e) => {
                                        error!("[{}] Read failed: {}", device.id, e);
                                        if !client.is_connected() { break; }
                                    }
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!("[{}] Connection failed: {}", device.id, e);
                }
            }

            warn!("[{}] Reconnecting in 5 seconds...", device.id);
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    })
}
