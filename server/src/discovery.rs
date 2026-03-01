use serde::Serialize;
use std::net::SocketAddr;
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
}

/// Scan a list of addresses on common Modbus ports (502, 5020).
/// Returns only reachable devices. Timeout per probe: 500ms.
pub async fn scan_network(targets: &[String], ports: &[u16]) -> Vec<DiscoveredDevice> {
    let mut handles = Vec::new();

    for target in targets {
        for &port in ports {
            let addr = format!("{}:{}", target, port);
            handles.push(tokio::spawn(probe_address(addr, port)));
        }
    }

    let mut found = Vec::new();
    for h in handles {
        if let Ok(Some(dev)) = h.await {
            found.push(dev);
        }
    }

    info!("Discovery scan complete: {} device(s) found", found.len());
    found
}

/// Probe a single address with TCP connect (timeout 500ms).
/// If the port accepts a connection, it's likely a Modbus device.
async fn probe_address(addr: String, port: u16) -> Option<DiscoveredDevice> {
    let socket_addr: SocketAddr = match addr.parse() {
        Ok(a) => a,
        Err(_) => return None,
    };

    match timeout(Duration::from_millis(500), TcpStream::connect(socket_addr)).await {
        Ok(Ok(_stream)) => {
            info!("Discovery: found device at {}", addr);
            Some(DiscoveredDevice {
                address: socket_addr.ip().to_string(),
                port,
                protocol: "modbus".to_string(),
                reachable: true,
            })
        }
        _ => None,
    }
}

/// Generate a list of localhost targets for scanning (common sim ports).
pub fn default_scan_targets() -> (Vec<String>, Vec<u16>) {
    let targets = vec!["127.0.0.1".to_string()];
    let ports = vec![502, 5020, 5021, 5022, 5023, 5024, 5025];
    (targets, ports)
}
