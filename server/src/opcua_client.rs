//! OPC UA client — implements PlcProtocol trait.
//!
//! Connects to any OPC UA server (real Siemens/AB PLC or our simulator).
//! Maps register addresses (u16) to OPC UA NodeIds (ns=2, numeric).
//! Same interface as ModbusClient — the server doesn't know the difference.
//!
//! `opcua 0.12.0` is synchronous — all calls are blocking. We use
//! `tokio::task::spawn_blocking` to bridge into our async PlcProtocol trait.

use std::sync::Arc;

use async_trait::async_trait;
use opcua::client::prelude::*;
use opcua::sync::RwLock;
use tracing::info;

use crate::protocol::PlcProtocol;

/// OPC UA client that implements PlcProtocol.
///
/// Connects to an OPC UA endpoint (e.g. `opc.tcp://127.0.0.1:4840`),
/// reads/writes nodes by numeric ID in namespace 2 (matching register addresses).
pub struct OpcUaClient {
    url: String,
    session: Option<Arc<RwLock<Session>>>,
    /// Keeps the OPC UA Client + session event loop alive.
    /// Dropping either kills the connection.
    _keepalive: Option<Box<dyn std::any::Any + Send>>,
}

impl OpcUaClient {
    pub fn new(url: &str) -> Self {
        Self {
            url: url.to_string(),
            session: None,
            _keepalive: None,
        }
    }
}

#[async_trait]
impl PlcProtocol for OpcUaClient {
    async fn connect(&mut self) -> Result<(), String> {
        let url = self.url.clone();

        // connect_to_endpoint is blocking — run on blocking thread pool
        let (session, keepalive) = tokio::task::spawn_blocking(move || {
            let mut client = ClientBuilder::new()
                .application_name("Vyuh HMI OPC UA Client")
                .application_uri("urn:VyuhHmiClient")
                .create_sample_keypair(true)
                .trust_server_certs(true)
                .pki_dir("./opcua-pki-client")
                .session_retry_limit(3)
                .client()
                .ok_or_else(|| "Failed to build OPC UA client".to_string())?;

            let endpoint: EndpointDescription = (
                url.as_str(),
                SecurityPolicy::None.to_str(),
                MessageSecurityMode::None,
                UserTokenPolicy::anonymous(),
            )
                .into();

            let session = client
                .connect_to_endpoint(endpoint, IdentityToken::Anonymous)
                .map_err(|e| format!("OPC UA connect failed: {:?}", e))?;

            // Start the session event loop in a background thread.
            // MUST keep both `client` and `tx` alive — dropping either kills the connection.
            let tx = Session::run_async(session.clone());

            // Box both client and tx together to keep them alive
            let keepalive: Box<dyn std::any::Any + Send> = Box::new((client, tx));

            Ok::<(Arc<RwLock<Session>>, Box<dyn std::any::Any + Send>), String>(
                (session, keepalive),
            )
        })
        .await
        .map_err(|e| format!("Spawn blocking failed: {:?}", e))?
        ?;

        info!("OPC UA connected to {}", self.url);
        self.session = Some(session);
        self._keepalive = Some(keepalive);
        Ok(())
    }

    async fn read_registers(&mut self, start: u16, count: u16) -> Result<Vec<u16>, String> {
        let session = self.session.clone().ok_or("Not connected")?;

        let result = tokio::task::spawn_blocking(move || {
            let session = session.read();

            // Map register addresses → OPC UA NodeIds in namespace 2
            let nodes_to_read: Vec<ReadValueId> = (start..start + count)
                .map(|reg| ReadValueId::from(NodeId::new(2, reg as u32)))
                .collect();

            let results = session
                .read(&nodes_to_read, TimestampsToReturn::Both, 0.0)
                .map_err(|e| format!("OPC UA read failed: {:?}", e))?;

            // Convert OPC UA DataValues → u16
            let values: Vec<u16> = results
                .iter()
                .map(|dv| variant_to_u16(&dv.value))
                .collect();

            Ok::<Vec<u16>, String>(values)
        })
        .await
        .map_err(|e| format!("Spawn blocking failed: {:?}", e))?;

        match result {
            Ok(values) => Ok(values),
            Err(e) => {
                self.session = None;
                self._keepalive = None;
                Err(e)
            }
        }
    }

    async fn write_register(&mut self, address: u16, value: u16) -> Result<(), String> {
        let session = self.session.clone().ok_or("Not connected")?;

        let result = tokio::task::spawn_blocking(move || {
            let session = session.read();

            let node_to_write = WriteValue {
                node_id: NodeId::new(2, address as u32),
                attribute_id: AttributeId::Value as u32,
                index_range: UAString::null(),
                value: DataValue::new_now(Variant::UInt16(value)),
            };

            let results = session
                .write(&[node_to_write])
                .map_err(|e| format!("OPC UA write failed: {:?}", e))?;

            if let Some(&status) = results.first() {
                if status.is_good() {
                    Ok(())
                } else {
                    Err(format!("OPC UA write error: {:?}", status))
                }
            } else {
                Err("No write result returned".to_string())
            }
        })
        .await
        .map_err(|e| format!("Spawn blocking failed: {:?}", e))?;

        match result {
            Ok(()) => Ok(()),
            Err(e) => {
                self.session = None;
                self._keepalive = None;
                Err(e)
            }
        }
    }

    fn is_connected(&self) -> bool {
        self.session.is_some()
    }

    fn protocol_name(&self) -> &str {
        "opcua"
    }
}

/// Convert an OPC UA Variant to u16 — handles all common numeric types.
fn variant_to_u16(value: &Option<Variant>) -> u16 {
    match value {
        Some(Variant::UInt16(v)) => *v,
        Some(Variant::Int16(v)) => *v as u16,
        Some(Variant::UInt32(v)) => *v as u16,
        Some(Variant::Int32(v)) => *v as u16,
        Some(Variant::Float(v)) => *v as u16,
        Some(Variant::Double(v)) => *v as u16,
        Some(Variant::Byte(v)) => *v as u16,
        Some(Variant::SByte(v)) => *v as u16,
        Some(Variant::UInt64(v)) => *v as u16,
        Some(Variant::Int64(v)) => *v as u16,
        _ => 0,
    }
}
