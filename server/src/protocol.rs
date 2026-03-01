use async_trait::async_trait;
use chrono::Utc;
use sqlx::SqlitePool;
use std::time::Duration;
use tokio::sync::{broadcast, mpsc};
use tokio::task::JoinHandle;
use tracing::{error, info, warn};

use crate::config::DeviceConfig;
use crate::db;
use crate::models::PlcData;
use crate::state::WriteCommand;

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
                                        for (i, &value) in registers.iter().enumerate() {
                                            let data = PlcData {
                                                device_id: device.id.clone(),
                                                register: device.register_start + i as u16,
                                                value: value as f64,
                                                timestamp: Utc::now(),
                                            };
                                            db::save_plc_data(&db, &data).await;
                                            let json = serde_json::to_string(&data).unwrap_or_default();
                                            let _ = tx.send(json);
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
