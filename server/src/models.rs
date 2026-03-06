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

/// Request to add a new device at runtime (POST /api/devices).
#[derive(Debug, Deserialize)]
pub struct AddDeviceRequest {
    pub id: String,
    pub name: String,
    pub address: String,
    pub protocol: String,
    pub poll_rate_ms: Option<u64>,
    pub register_start: u16,
    pub register_count: u16,
    pub writable: Vec<u16>,
}

/// Optional body for POST /api/discover — custom targets/ports.
#[derive(Debug, Deserialize)]
pub struct ScanRequest {
    pub targets: Option<Vec<String>>,
    pub ports: Option<Vec<u16>>,
}

/// Request to browse nodes on an OPC UA server.
#[derive(Debug, Deserialize)]
pub struct BrowseOpcUaRequest {
    pub url: String,
    /// If omitted, browses from the Objects folder (ns=0;i=85).
    pub parent_node_id: Option<String>,
}

// ── ISA-18.2 Alarm Management ───────────────────────────────────

/// Alarm priority levels per ISA-18.2.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AlarmPriority {
    Critical = 1,
    High = 2,
    Medium = 3,
    Low = 4,
    Info = 5,
}

impl AlarmPriority {
    pub fn from_i32(v: i32) -> Self {
        match v {
            1 => Self::Critical,
            2 => Self::High,
            3 => Self::Medium,
            4 => Self::Low,
            _ => Self::Info,
        }
    }

    pub fn as_i32(&self) -> i32 {
        *self as i32
    }

    pub fn as_str(&self) -> &str {
        match self {
            Self::Critical => "critical",
            Self::High => "high",
            Self::Medium => "medium",
            Self::Low => "low",
            Self::Info => "info",
        }
    }
}

/// Alarm state per ISA-18.2 state machine.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AlarmState {
    Active,        // condition present, unacknowledged
    Acknowledged,  // condition present, acknowledged by operator
    Cleared,       // condition gone, was acknowledged
    Shelved,       // temporarily suppressed
}

impl AlarmState {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Active => "active",
            Self::Acknowledged => "acknowledged",
            Self::Cleared => "cleared",
            Self::Shelved => "shelved",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "acknowledged" => Self::Acknowledged,
            "cleared" => Self::Cleared,
            "shelved" => Self::Shelved,
            _ => Self::Active,
        }
    }
}

/// A single alarm record.
#[derive(Debug, Clone, Serialize)]
pub struct Alarm {
    pub id: i64,
    pub device_id: String,
    pub register: u16,
    pub label: String,
    pub priority: AlarmPriority,
    pub state: AlarmState,
    pub value: f64,
    pub threshold: f64,
    pub message: String,
    pub timestamp: String,
    pub acked_by: Option<String>,
    pub acked_at: Option<String>,
    pub shelved_until: Option<String>,
    pub shelved_by: Option<String>,
    pub cleared_at: Option<String>,
}

/// Request to acknowledge an alarm.
#[derive(Debug, Deserialize)]
pub struct AckAlarmRequest {
    pub comment: Option<String>,
}

/// Request to shelve an alarm.
#[derive(Debug, Deserialize)]
pub struct ShelveAlarmRequest {
    /// Duration in minutes to shelve. Max 480 (8 hours).
    pub duration_minutes: u32,
    pub reason: String,
}

/// Request to raise an alarm from the polling engine.
#[derive(Debug, Clone)]
pub struct RaiseAlarmRequest {
    pub device_id: String,
    pub register: u16,
    pub label: String,
    pub priority: AlarmPriority,
    pub value: f64,
    pub threshold: f64,
    pub message: String,
}

/// Query params for listing alarms.
#[derive(Debug, Deserialize)]
pub struct AlarmQueryParams {
    pub device_id: Option<String>,
    pub state: Option<String>,
    pub priority: Option<i32>,
    pub limit: Option<i64>,
}

// ── ISA-88 Batch Records ────────────────────────────────────────

/// Batch status.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BatchStatus {
    Running,
    Completed,
    Aborted,
    Held,
}

impl BatchStatus {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Aborted => "aborted",
            Self::Held => "held",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "completed" => Self::Completed,
            "aborted" => Self::Aborted,
            "held" => Self::Held,
            _ => Self::Running,
        }
    }
}

/// A batch record (ISA-88 batch header).
#[derive(Debug, Clone, Serialize)]
pub struct BatchRecord {
    pub id: i64,
    pub batch_id: String,
    pub recipe_name: String,
    pub device_id: String,
    pub operator: String,
    pub status: BatchStatus,
    pub start_time: String,
    pub end_time: Option<String>,
    pub notes: Option<String>,
}

/// A step within a batch (ISA-88 phase/step).
#[derive(Debug, Clone, Serialize)]
pub struct BatchStep {
    pub id: i64,
    pub batch_record_id: i64,
    pub step_number: i32,
    pub name: String,
    pub status: String,
    pub start_time: String,
    pub end_time: Option<String>,
    pub parameters: Option<String>,
    pub result: Option<String>,
}

/// Query params for listing batches.
#[derive(Debug, Deserialize)]
pub struct BatchQueryParams {
    pub device_id: Option<String>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}