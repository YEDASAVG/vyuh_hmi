use opcua::client::prelude::*;
use serde::Serialize;
use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::time::timeout;
use tracing::info;

/// Result of scanning a single address+port.
#[derive(Debug, Clone, Serialize)]
pub struct DiscoveredDevice {
    pub address: String,
    pub port: u16,
    pub protocol: String,
    pub reachable: bool,
    /// OPC UA server application name (only for opcua devices).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub server_name: Option<String>,
    /// OPC UA endpoint URL (only for opcua devices).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endpoint_url: Option<String>,
}

/// A single node discovered by browsing an OPC UA server.
#[derive(Debug, Clone, Serialize)]
pub struct OpcUaNode {
    pub node_id: String,
    pub browse_name: String,
    pub display_name: String,
    pub node_class: String,
}

/// Scan a list of addresses on given ports.
/// Returns only reachable devices. Timeout per probe: 500ms.
pub async fn scan_network(targets: &[String], ports: &[u16]) -> Vec<DiscoveredDevice> {
    let mut handles = Vec::new();

    for target in targets {
        for &port in ports {
            let addr = format!("{}:{}", target, port);
            let protocol = if is_opcua_port(port) { "opcua" } else { "modbus" };
            handles.push(tokio::spawn(probe_address(addr, port, protocol.to_string())));
        }
    }

    let mut found = Vec::new();
    for h in handles {
        if let Ok(Some(dev)) = h.await {
            found.push(dev);
        }
    }

    // For OPC UA reachable devices, try FindServers to get application names
    let mut enriched = Vec::new();
    for dev in found {
        if dev.protocol == "opcua" {
            let url = format!("opc.tcp://{}:{}", dev.address, dev.port);
            match find_opcua_servers(&url).await {
                Ok(servers) if !servers.is_empty() => {
                    for s in servers {
                        enriched.push(DiscoveredDevice {
                            address: dev.address.clone(),
                            port: dev.port,
                            protocol: "opcua".to_string(),
                            reachable: true,
                            server_name: Some(s.application_name.text.as_ref().to_string()),
                            endpoint_url: s.discovery_urls
                                .as_ref()
                                .and_then(|urls| urls.first().map(|u| u.as_ref().to_string())),
                        });
                    }
                }
                _ => enriched.push(dev),
            }
        } else {
            enriched.push(dev);
        }
    }

    info!("Discovery scan complete: {} device(s) found", enriched.len());
    enriched
}

fn is_opcua_port(port: u16) -> bool {
    (4840..=4850).contains(&port)
}

/// Probe a single address with TCP connect (timeout 500ms).
async fn probe_address(addr: String, port: u16, protocol: String) -> Option<DiscoveredDevice> {
    let socket_addr: SocketAddr = match addr.parse() {
        Ok(a) => a,
        Err(_) => return None,
    };

    match timeout(Duration::from_millis(500), TcpStream::connect(socket_addr)).await {
        Ok(Ok(_stream)) => {
            info!("Discovery: found {} device at {}", protocol, addr);
            Some(DiscoveredDevice {
                address: socket_addr.ip().to_string(),
                port,
                protocol,
                reachable: true,
                server_name: None,
                endpoint_url: None,
            })
        }
        _ => None,
    }
}

/// Use OPC UA FindServers to enumerate servers at a URL.
async fn find_opcua_servers(url: &str) -> Result<Vec<ApplicationDescription>, String> {
    let url = url.to_string();
    tokio::task::spawn_blocking(move || {
        let mut client = ClientBuilder::new()
            .application_name("Vyuh HMI Discovery")
            .application_uri("urn:VyuhHmiDiscovery")
            .create_sample_keypair(true)
            .trust_server_certs(true)
            .pki_dir("./opcua-pki-client")
            .session_retry_limit(0)
            .client()
            .ok_or_else(|| "Failed to build OPC UA client".to_string())?;

        client
            .find_servers(&url)
            .map_err(|e| format!("FindServers failed: {:?}", e))
    })
    .await
    .map_err(|e| format!("Spawn blocking: {:?}", e))?
}

/// Browse child nodes of a given parent on an OPC UA server.
/// If `parent_node_id` is None, browses from the Objects folder (ns=0;i=85).
pub async fn browse_opcua_nodes(
    url: &str,
    parent_node_id: Option<&str>,
) -> Result<Vec<OpcUaNode>, String> {
    let url = url.to_string();
    let parent = parent_node_id.unwrap_or("ns=0;i=85").to_string();

    tokio::task::spawn_blocking(move || {
        let mut client = ClientBuilder::new()
            .application_name("Vyuh HMI Browser")
            .application_uri("urn:VyuhHmiBrowser")
            .create_sample_keypair(true)
            .trust_server_certs(true)
            .pki_dir("./opcua-pki-client")
            .session_retry_limit(0)
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

        let _tx = Session::run_async(session.clone());
        std::thread::sleep(std::time::Duration::from_millis(200));

        let parent_node: NodeId = NodeId::from_str(&parent)
            .unwrap_or_else(|_| ObjectId::ObjectsFolder.into());

        let session = session.read();
        let results = session
            .browse(&[BrowseDescription {
                node_id: parent_node,
                browse_direction: BrowseDirection::Forward,
                reference_type_id: ReferenceTypeId::HierarchicalReferences.into(),
                include_subtypes: true,
                node_class_mask: 0, // all classes
                result_mask: BrowseDescriptionResultMask::all().bits(),
            }])
            .map_err(|e| format!("Browse failed: {:?}", e))?;

        let mut nodes = Vec::new();
        if let Some(refs_vec) = results {
          if let Some(result) = refs_vec.first() {
            if let Some(refs) = &result.references {
                for r in refs {
                    nodes.push(OpcUaNode {
                        node_id: r.node_id.node_id.to_string(),
                        browse_name: r.browse_name.name.to_string(),
                        display_name: r.display_name.text.to_string(),
                        node_class: format!("{:?}", r.node_class),
                    });
                }
            }
          }
        }

        Ok(nodes)
    })
    .await
    .map_err(|e| format!("Spawn blocking: {:?}", e))?
}

/// Generate a list of localhost targets for scanning (Modbus + OPC UA ports).
pub fn default_scan_targets() -> (Vec<String>, Vec<u16>) {
    let targets = vec!["127.0.0.1".to_string()];
    let ports = vec![502, 5020, 5021, 5022, 5023, 5024, 5025, 4840, 4841, 4842];
    (targets, ports)
}
