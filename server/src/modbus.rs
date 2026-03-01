use async_trait::async_trait;
use std::net::SocketAddr;
use tokio_modbus::client::tcp;
use tokio_modbus::prelude::*;
use tracing::info;

use crate::protocol::PlcProtocol;

/// Modbus TCP client — implements PlcProtocol trait.
///
/// Connects to a Modbus TCP device (real PLC or simulator),
/// reads holding registers, writes single registers.
pub struct ModbusClient {
    address: SocketAddr,
    ctx: Option<tokio_modbus::client::Context>,
}

impl ModbusClient {
    pub fn new(address: &str) -> Self {
        let socket_addr: SocketAddr = address.parse().expect("Invalid Modbus address");
        Self {
            address: socket_addr,
            ctx: None,
        }
    }
}

#[async_trait]
impl PlcProtocol for ModbusClient {
    async fn connect(&mut self) -> Result<(), String> {
        match tcp::connect(self.address).await {
            Ok(ctx) => {
                self.ctx = Some(ctx);
                info!("Modbus connected to {}", self.address);
                Ok(())
            }
            Err(e) => Err(format!("Modbus connect failed: {}", e)),
        }
    }

    async fn read_registers(&mut self, start: u16, count: u16) -> Result<Vec<u16>, String> {
        let ctx = self.ctx.as_mut().ok_or("Not connected")?;
        match ctx.read_holding_registers(start, count).await {
            Ok(Ok(regs)) => Ok(regs),
            Ok(Err(e)) => Err(format!("Modbus exception: {:?}", e)),
            Err(e) => {
                self.ctx = None; // connection lost
                Err(format!("Read failed: {}", e))
            }
        }
    }

    async fn write_register(&mut self, address: u16, value: u16) -> Result<(), String> {
        let ctx = self.ctx.as_mut().ok_or("Not connected")?;
        match ctx.write_single_register(address, value).await {
            Ok(Ok(())) => Ok(()),
            Ok(Err(e)) => Err(format!("Modbus write exception: {:?}", e)),
            Err(e) => {
                self.ctx = None; // connection lost
                Err(format!("Write failed: {}", e))
            }
        }
    }

    fn is_connected(&self) -> bool {
        self.ctx.is_some()
    }

    fn protocol_name(&self) -> &str {
        "modbus"
    }
}
