use serde::{Deserialize, Serialize};

/// Top-level server configuration loaded from `config.toml`.
#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub devices: Vec<DeviceConfig>,
}

/// HTTP server bind address and port.
#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

/// Database configuration.
#[derive(Debug, Deserialize, Clone)]
pub struct DatabaseConfig {
    pub path: String,
}

/// A single PLC device to connect to.
///
/// Each device has its own protocol, address, register range, and
/// list of writable registers. The server spawns one polling task per device.
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct DeviceConfig {
    pub id: String,
    pub name: String,
    pub address: String,
    pub protocol: String,       // "modbus" | "opcua" (Phase 7)
    pub poll_rate_ms: u64,
    pub register_start: u16,
    pub register_count: u16,
    pub writable: Vec<u16>,
}

impl AppConfig {
    /// Load configuration from a TOML file.
    pub fn load(path: &str) -> Self {
        let content = std::fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("Failed to read config '{}': {}", path, e));
        toml::from_str(&content)
            .unwrap_or_else(|e| panic!("Failed to parse config '{}': {}", path, e))
    }
}
