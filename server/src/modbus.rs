use chrono::Utc;
use sqlx::SqlitePool;
use std::net::SocketAddr;
use std::time::Duration;
use tokio::sync::{broadcast, mpsc};
use tokio_modbus::client::tcp;
use tokio_modbus::prelude::*;
use tracing::{error, info, warn};

use crate::db;
use crate::models::PlcData;
use crate::state::WriteCommand;

// start background polling task
// connect to PLC via modbus TCP reads registers every sec

pub fn start_polling(
    tx: broadcast::Sender<String>,
    db: SqlitePool,
    address: String,
    mut write_rx: mpsc::Receiver<WriteCommand>,
) {
    tokio::spawn(async move {
        info!("Modbus polling task started for {}", address);
        let socket_addr: SocketAddr = address.parse().expect("Invalid PLC address");

        loop {
            // try to connect to plc
            info!("Connecting to PLC at {}", address);

            match tcp::connect(socket_addr).await {
                Ok(mut ctx) => {
                    info!("Connected to PLC at {}", address);
                    let mut interval = tokio::time::interval(Duration::from_secs(1));

                    // poll loop - reads registers every second, also handles write commands
                    loop {
                        tokio::select! {
                            // Handle write commands from the API
                            Some(cmd) = write_rx.recv() => {
                                info!("Writing register {} = {}", cmd.register, cmd.value);
                                match ctx.write_single_register(cmd.register, cmd.value).await {
                                    Ok(Ok(())) => {
                                        info!("Write successful: reg {} = {}", cmd.register, cmd.value);
                                        let _ = cmd.response.send(Ok(()));
                                    }
                                    Ok(Err(e)) => {
                                        error!("Modbus write exception: {:?}", e);
                                        let _ = cmd.response.send(Err(format!("Modbus exception: {:?}", e)));
                                    }
                                    Err(e) => {
                                        error!("Write failed: {}", e);
                                        let _ = cmd.response.send(Err(format!("Write failed: {}", e)));
                                        break; // connection lost, reconnect
                                    }
                                }
                            }
                            // Regular polling tick
                            _ = interval.tick() => {
                        // Read 8 registers starting at 1028
                        match ctx.read_holding_registers(1028, 8).await {
                            Ok(Ok(registers)) => {
                                // registers[0]=temp, [1]=pressure, [2]=humidity, [3]=flow

                                for (i, &value) in registers.iter().enumerate() {
                                    let data = PlcData {
                                        device_id: "plc-01".to_string(),
                                        register: 1028 + i as u16,
                                        value: value as f64,
                                        timestamp: Utc::now(),
                                    };
                                    // save to db
                                    db::save_plc_data(&db, &data).await;

                                    //  Broadcast to Websocket clients
                                    let json = serde_json::to_string(&data).unwrap_or_default();
                                    let _ = tx.send(json);
                                }
                                let state_name = match registers[4] {
                                    0 => "IDLE",
                                    1 => "HEATING",
                                    2 => "HOLDING",
                                    3 => "COOLING",
                                    4 => "COMPLETE",
                                    _ => "UNKNOWN",
                                };
                                info!(
                                    "[{}] temp={}°C press={}mbar humid={}% flow={}L/min agit={}RPM pH={:.1} progress={}%",
                                    state_name,
                                    registers[0],
                                    registers[1],
                                    registers[2],
                                    registers[3],
                                    registers[6],
                                    registers[7] as f64 / 10.0,
                                    registers[5],
                                )
                            }
                            Ok(Err(e)) => {
                                error!("Modbus exception: {:?}", e);
                                break; // exit poll loop -> reconnect
                            }
                            Err(e) => {
                                error!("Read failed: {}", e);
                                break; // exit poll loop -> reconnect
                            }
                        }
                            } // end _ = interval.tick()
                        } // end tokio::select!
                    } // end loop
                }
                Err(e) => {
                    warn!("Failed to connect to PLC: {}", e);
                }
            }
            warn!("Reconnecting in 5 seconds...");
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });
}
