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
    /// JWT signing secret. Must be ≥32 characters.
    #[serde(default = "default_jwt_secret")]
    pub jwt_secret: String,
    /// Optional path to TLS certificate PEM file.
    pub tls_cert: Option<String>,
    /// Optional path to TLS private key PEM file.
    pub tls_key: Option<String>,
}

fn default_jwt_secret() -> String {
    "vyuh-hmi-CHANGE-ME-insecure-default".to_string()
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
        let config: Self = toml::from_str(&content)
            .unwrap_or_else(|e| panic!("Failed to parse config '{}': {}", path, e));

        // Validate JWT secret length for production security
        if config.server.jwt_secret.len() < 32 {
            panic!(
                "jwt_secret must be at least 32 characters (got {}). Update config.toml.",
                config.server.jwt_secret.len()
            );
        }
        if config.server.jwt_secret.contains("CHANGE-ME") || config.server.jwt_secret.contains("change-me") {
            tracing::warn!("⚠ jwt_secret contains default placeholder — change it before production!");
        }

        config
    }
}
