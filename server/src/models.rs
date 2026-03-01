use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlcData { // Data coming from PLC (one reading)
    pub device_id: String,
    pub register: u16,
    pub value: f64,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlcDevice { // A plc device on the network
    pub id: String,
    pub name: String,
    pub address: String,
    pub protocol: String,
    pub is_connected: bool,
}

#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> { // Standard API response wrapper
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct WriteRequest {
    pub device_id: String,
    pub register: u16,
    pub value: u16,
}