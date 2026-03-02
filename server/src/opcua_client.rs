//! OPC UA client — implements PlcProtocol trait.
//!
//! Connects to any OPC UA server (real Siemens/AB PLC or our simulator).
//! Maps register addresses (u16) to OPC UA NodeIds (ns=2, numeric).
//! Same interface as ModbusClient — the server doesn't know the difference.
//!
//! `opcua 0.12.0` is synchronous — all calls are blocking. We use
//! `tokio::task::spawn_blocking` to bridge into our async PlcProtocol trait.

use std::collections::HashMap;
use std::sync::{Arc, Mutex as StdMutex};

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
    /// Cached register values from OPC UA subscription (address → value).
    /// Updated by the DataChangeCallback on the session's event loop thread.
    sub_cache: Arc<StdMutex<HashMap<u32, u16>>>,
    /// Whether a subscription is actively delivering data.
    sub_active: bool,
    /// Number of consecutive reads where the subscription cache was empty.
    /// If this exceeds the threshold, we fall back to polling.
    sub_empty_reads: u32,
}

impl OpcUaClient {
    pub fn new(url: &str) -> Self {
        Self {
            url: url.to_string(),
            session: None,
            _keepalive: None,
            sub_cache: Arc::new(StdMutex::new(HashMap::new())),
            sub_active: false,
            sub_empty_reads: 0,
        }
    }
}

#[async_trait]
impl PlcProtocol for OpcUaClient {
    async fn connect(&mut self) -> Result<(), String> {
        let url = self.url.clone();
        let sub_cache = self.sub_cache.clone();

        // Clear stale subscription cache
        if let Ok(mut cache) = sub_cache.lock() {
            cache.clear();
        }

        // connect_to_endpoint is blocking — run on blocking thread pool
        let (session, keepalive, sub_active) = tokio::task::spawn_blocking(move || {
            let mut client = ClientBuilder::new()
                .application_name("Vyuh HMI OPC UA Client")
                .application_uri("urn:VyuhHmiClient")
                .create_sample_keypair(true)
                .trust_server_certs(true)
                .pki_dir("./opcua-pki-client")
                .session_retry_limit(0)   // NO internal auto-reconnect — protocol.rs handles it
                .max_message_size(4 * 1024 * 1024) // 4MB — match server limits
                .max_chunk_count(64)
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

            // Give the transport thread time to start the message pump.
            // Without this, create_subscription can race with transport init.
            std::thread::sleep(std::time::Duration::from_millis(200));

            // ── Try to create a subscription for push-based data ──
            // If it fails, we fall back to regular polling (existing behavior).
            let sub_active = {
                let session_guard = session.read();
                match create_data_subscription(&*session_guard, sub_cache) {
                    Ok(()) => {
                        eprintln!("[opcua] Subscription created — push mode active");
                        true
                    }
                    Err(e) => {
                        eprintln!("[opcua] Subscription failed, using polling: {e}");
                        false
                    }
                }
            };

            Ok::<(Arc<RwLock<Session>>, Box<dyn std::any::Any + Send>, bool), String>(
                (session, keepalive, sub_active),
            )
        })
        .await
        .map_err(|e| format!("Spawn blocking failed: {:?}", e))?
        ?;

        info!(
            "OPC UA connected to {} ({})",
            self.url,
            if sub_active { "subscription" } else { "polling" }
        );
        self.session = Some(session);
        self._keepalive = Some(keepalive);
        self.sub_active = sub_active;
        self.sub_empty_reads = 0;
        Ok(())
    }

    async fn read_registers(&mut self, start: u16, count: u16) -> Result<Vec<u16>, String> {
        // Subscription mode: return from cache if it has data.
        // If the cache stays empty for too many reads, the subscription
        // callback is probably not firing — demote to polling mode.
        if self.sub_active {
            if let Ok(cache) = self.sub_cache.lock() {
                let has_data = cache.values().any(|&v| v != 0);
                if has_data {
                    self.sub_empty_reads = 0;
                    return Ok((start..start + count)
                        .map(|reg| *cache.get(&(reg as u32)).unwrap_or(&0))
                        .collect());
                }
            }
            // Cache is still empty — count consecutive misses
            self.sub_empty_reads += 1;
            if self.sub_empty_reads > 5 {
                tracing::warn!(
                    "OPC UA subscription produced no data after {} reads — falling back to polling",
                    self.sub_empty_reads
                );
                self.sub_active = false;
            }
        }

        // Polling mode: regular blocking read
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
                self.sub_active = false;
                if let Ok(mut c) = self.sub_cache.lock() { c.clear(); }
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
                self.sub_active = false;
                if let Ok(mut c) = self.sub_cache.lock() { c.clear(); }
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

// ── OPC UA Subscription ─────────────────────────────────────────
//
// Creates a subscription on the connected OPC UA session that
// monitors registers 1028–1035 (ns=2). When the server pushes a
// data-change notification the callback writes the new value into
// the shared `cache`. The polling loop in `read_registers()` then
// returns cached values instantly (zero network round-trip).

/// Set up a push-based subscription on the OPC UA server.
/// Called from within `spawn_blocking` — all opcua 0.12 calls are synchronous.
fn create_data_subscription(
    session: &Session,
    cache: Arc<StdMutex<HashMap<u32, u16>>>,
) -> Result<(), String> {
    let subscription_id = session
        .create_subscription(
            1000.0, // publishing interval (ms) — match simulator 1s tick
            100,    // lifetime count (high to prevent premature expiry)
            30,     // max keepalive count
            0,      // max notifications per publish (0 = unlimited)
            0,      // priority
            true,   // publishing enabled
            DataChangeCallback::new(move |items| {
                if let Ok(mut cache) = cache.lock() {
                    for item in items.iter() {
                        let handle = item.client_handle();
                        let val = variant_to_u16(&item.last_value().value);
                        cache.insert(handle, val);
                    }
                    if !items.is_empty() {
                        eprintln!("[opcua] Subscription data: {} items updated", items.len());
                    }
                }
            }),
        )
        .map_err(|e| format!("create_subscription failed: {e:?}"))?;

    // Monitor registers 1028–1035 in namespace 2
    let items_to_create: Vec<MonitoredItemCreateRequest> = (1028u32..=1035)
        .map(|reg| MonitoredItemCreateRequest {
            item_to_monitor: ReadValueId::from(NodeId::new(2, reg)),
            monitoring_mode: MonitoringMode::Reporting,
            requested_parameters: MonitoringParameters {
                client_handle: reg,
                sampling_interval: 250.0,
                filter: ExtensionObject::null(),
                queue_size: 1,
                discard_oldest: true,
            },
        })
        .collect();

    let results = session
        .create_monitored_items(
            subscription_id,
            TimestampsToReturn::Both,
            &items_to_create,
        )
        .map_err(|e| format!("create_monitored_items failed: {e:?}"))?;

    // Log any per-item failures
    for (i, result) in results.iter().enumerate() {
        if !result.status_code.is_good() {
            eprintln!(
                "[opcua] MonitoredItem ns=2;i={} status: {:?}",
                1028 + i,
                result.status_code
            );
        }
    }

    Ok(())
}
