use std::time::Duration;
use std::net::SocketAddr;
use chrono::Utc;
use tokio::sync::broadcast;
use sqlx::SqlitePool;
use tokio_modbus::prelude::*;
use tokio_modbus::client::tcp;
use tracing::{info, warn, error};

use crate::models::PlcData;
use crate::db;

// start background polling task
// connect to PLC via modbus TCP reads registers every sec

pub fn start_polling(tx: broadcast::Sender<String>, db: SqlitePool, address: String) {
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

                    // poll loop - reads registers every second
                    loop {
                        interval.tick().await;
                        // Read 4 registers starting at 1028
                        match ctx.read_holding_registers(1028, 4).await {
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
                                info!(
                                    "PLC data: temp={}°C pressure={:.1}bar humidity={}% flow={}L/min",
                                    registers[0],
                                    registers[1] as f64 / 100.0,
                                    registers[2],
                                    registers[3]
                                );
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
                    }
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