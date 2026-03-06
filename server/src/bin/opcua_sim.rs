//! OPC UA Pharma Simulator — Sterile Filling Line
//!
//! A standalone Rust binary that acts as an OPC UA server,
//! simulating a pharmaceutical batch process. Exposes the same
//! 8 registers (1028-1035) as the Modbus simulator so the HMI
//! server can treat them identically via the PlcProtocol trait.
//!
//! Run: `cargo run --bin opcua_sim`
//! Endpoint: opc.tcp://127.0.0.1:4840/

use std::sync::Arc;

use opcua::server::prelude::*;
use opcua::sync::Mutex;
use opcua::types::NumericRange;

// ── Node IDs (namespace 2, matching Modbus register addresses) ──
const REG_TEMPERATURE: u32 = 1028;
const REG_PRESSURE: u32 = 1029;
const REG_HUMIDITY: u32 = 1030;
const REG_FLOW_RATE: u32 = 1031;
const REG_BATCH_STATE: u32 = 1032;
const REG_BATCH_PROGRESS: u32 = 1033;
const REG_AGITATOR_RPM: u32 = 1034;
const REG_PH: u32 = 1035;

fn main() {
    // Init logging via env_logger (set RUST_LOG=info to see output)
    let _ = opcua::console_logging::init();

    // Detect the machine's LAN IP for discovery URLs so remote clients
    // can find us, but bind to 0.0.0.0 so we accept connections on ALL
    // interfaces (loopback 127.0.0.1 + LAN + any other).
    let local_ip = (|| -> Option<String> {
        let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
        socket.connect("8.8.8.8:80").ok()?;
        let addr = socket.local_addr().ok()?;
        Some(addr.ip().to_string())
    })()
    .unwrap_or_else(|| "127.0.0.1".to_string());

    println!("Detected LAN IP: {local_ip}");
    println!("Binding to: 0.0.0.0:4840 (all interfaces)");

    // ── Build server (anonymous access, no encryption) ──
    // Bind to 0.0.0.0 so both 127.0.0.1 and LAN IP connections work.
    // Discovery URLs include both localhost and LAN IP.
    let mut server = ServerBuilder::new_anonymous("OPC UA Pharma Simulator")
        .application_uri("urn:VyuhPharmaSim")
        .product_uri("urn:VyuhPharmaSim")
        .host_and_port("0.0.0.0", 4840)
        .discovery_urls(vec![
            format!("opc.tcp://127.0.0.1:4840/"),
            format!("opc.tcp://{}:4840/", local_ip),
        ])
        .create_sample_keypair(true)
        .pki_dir("./opcua-pki-sim")
        .discovery_server_url(None)
        .trust_client_certs()
        // Increase max message/chunk limits for subscription PublishResponse
        .max_message_size(4 * 1024 * 1024)  // 4 MB
        .max_chunk_count(64)
        .server()
        .expect("Failed to create OPC UA server");

    // ── Register namespace and add pharma variables ──
    let ns = {
        let address_space = server.address_space();
        let mut address_space = address_space.write();
        let ns = address_space
            .register_namespace("urn:pharma-sim")
            .expect("Failed to register namespace");

        // Create a folder for the batch reactor nodes
        let folder_id = address_space
            .add_folder(
                "SterileFillingLine",
                "Sterile Filling Line",
                &NodeId::objects_folder_id(),
            )
            .expect("Failed to add folder");

        // Add all 8 process variables (UInt16, matching Modbus register convention)
        let add_results = address_space.add_variables(
            vec![
                Variable::new(&NodeId::new(ns, REG_TEMPERATURE), "Temperature", "Temperature (°C)", 65u16),
                Variable::new(&NodeId::new(ns, REG_PRESSURE), "Pressure", "Pressure (mbar)", 1013u16),
                Variable::new(&NodeId::new(ns, REG_HUMIDITY), "Humidity", "Humidity (%RH)", 45u16),
                Variable::new(&NodeId::new(ns, REG_FLOW_RATE), "FlowRate", "Flow Rate (L/min)", 50u16),
                Variable::new(&NodeId::new(ns, REG_BATCH_STATE), "BatchState", "Batch State (0=Idle,1=Heat,2=Run,3=Cool,4=Done)", 0u16),
                Variable::new(&NodeId::new(ns, REG_BATCH_PROGRESS), "BatchProgress", "Batch Progress (%)", 0u16),
                Variable::new(&NodeId::new(ns, REG_AGITATOR_RPM), "AgitatorRPM", "Agitator RPM", 0u16),
                Variable::new(&NodeId::new(ns, REG_PH), "pH", "pH Level (x10)", 70u16),
            ],
            &folder_id,
        );
        println!("add_variables results: {:?}", add_results);
        println!("Namespace index: {ns}");

        // ── Fix for OPC UA subscriptions ──
        // Variable::new() stores DataValues with status=None and no timestamps.
        // The opcua server treats status=None as "no data yet" so subscription
        // MonitoredItems stay in BadWaitingForInitialData forever.
        // Explicitly set each variable's DataValue with StatusCode::Good.
        let now = DateTime::now();
        for &(reg, val) in &[
            (REG_TEMPERATURE, 65u16),
            (REG_PRESSURE, 1013),
            (REG_HUMIDITY, 45),
            (REG_FLOW_RATE, 50),
            (REG_BATCH_STATE, 0),
            (REG_BATCH_PROGRESS, 0),
            (REG_AGITATOR_RPM, 0),
            (REG_PH, 70),
        ] {
            let node_id = NodeId::new(ns, reg);
            if let Some(v) = address_space.find_variable_mut(node_id) {
                let _ = v.set_value(NumericRange::None, DataValue {
                    value: Some(Variant::UInt16(val)),
                    status: Some(StatusCode::Good),
                    source_timestamp: Some(now.clone()),
                    source_picoseconds: None,
                    server_timestamp: Some(now.clone()),
                    server_picoseconds: None,
                });
            }
        }

        ns
    };

    // ── Simulation loop — update values every second ──
    let sim_state = Arc::new(Mutex::new(SimState::default()));

    {
        let address_space = server.address_space();
        let sim_state = sim_state.clone();

        server.add_polling_action(1000, move || {
            let mut state = sim_state.lock();
            state.tick();

            let mut address_space = address_space.write();
            let now = DateTime::now();

            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_TEMPERATURE),
                state.temperature,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_PRESSURE),
                state.pressure,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_HUMIDITY),
                state.humidity,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_FLOW_RATE),
                state.flow_rate,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_BATCH_STATE),
                state.batch_state,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_BATCH_PROGRESS),
                state.batch_progress,
                &now,
                &now,
            );
            // Don't overwrite AgitatorRPM if HMI wrote a non-zero value;
            // otherwise drive it from the sim based on batch state.
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_AGITATOR_RPM),
                state.agitator_rpm,
                &now,
                &now,
            );
            let _ = address_space.set_variable_value(
                NodeId::new(ns, REG_PH),
                state.ph,
                &now,
                &now,
            );
        });
    }

    println!("╔══════════════════════════════════════════════════════════════╗");
    println!("║  OPC UA Pharma Simulator — Sterile Filling Line            ║");
    println!("║  Listening: 0.0.0.0:4840 (all interfaces)                  ║");
    println!("║  Connect via: opc.tcp://127.0.0.1:4840/                    ║");
    println!("║            or opc.tcp://{}:4840/", local_ip);
    println!("║  Namespace: urn:pharma-sim (ns=2)                          ║");
    println!("║  Nodes: ns=2;i=1028..1035 (8 registers)                   ║");
    println!("╚══════════════════════════════════════════════════════════════╝");

    server.run();
}

// ── Simulation State ────────────────────────────────────────────

struct SimState {
    temperature: u16,
    pressure: u16,
    humidity: u16,
    flow_rate: u16,
    batch_state: u16,
    batch_progress: u16,
    ph: u16,
    agitator_rpm: u16,
    tick_count: u32,
}

impl Default for SimState {
    fn default() -> Self {
        Self {
            temperature: 65,
            pressure: 1013,
            humidity: 45,
            flow_rate: 50,
            batch_state: 0,
            batch_progress: 0,
            ph: 70,
            agitator_rpm: 0,
            tick_count: 0,
        }
    }
}

impl SimState {
    fn tick(&mut self) {
        self.tick_count += 1;

        // Temperature: sinusoidal 60–80°C
        let t_phase = (self.tick_count as f64 * 0.05).sin();
        self.temperature = (70.0 + t_phase * 10.0) as u16;

        // Pressure: slight variation around 1013 mbar
        let p_phase = (self.tick_count as f64 * 0.03).cos();
        self.pressure = (1013.0 + p_phase * 50.0) as u16;

        // Humidity: slow drift 40–55%
        let h_phase = (self.tick_count as f64 * 0.02).sin();
        self.humidity = (47.0 + h_phase * 8.0) as u16;

        // Flow rate: 45–55 L/min
        let f_phase = (self.tick_count as f64 * 0.04).sin();
        self.flow_rate = (50.0 + f_phase * 5.0) as u16;

        // Batch process state machine
        match self.batch_state {
            0 => {
                // Idle → start after 10 ticks
                if self.tick_count % 60 == 10 {
                    self.batch_state = 1;
                    self.batch_progress = 0;
                }
            }
            1 => {
                // Heating
                self.batch_progress = (self.batch_progress + 2).min(30);
                if self.batch_progress >= 30 {
                    self.batch_state = 2;
                }
            }
            2 => {
                // Running
                self.batch_progress = (self.batch_progress + 1).min(90);
                if self.batch_progress >= 90 {
                    self.batch_state = 3;
                }
            }
            3 => {
                // Cooling
                self.batch_progress = (self.batch_progress + 1).min(100);
                if self.batch_progress >= 100 {
                    self.batch_state = 4;
                }
            }
            4 => {
                // Complete → reset after pause
                if self.tick_count % 60 == 0 {
                    self.batch_state = 0;
                    self.batch_progress = 0;
                }
            }
            _ => {
                self.batch_state = 0;
            }
        }

        // pH: 6.8–7.2 (stored as x10: 68–72)
        let ph_phase = (self.tick_count as f64 * 0.025).sin();
        self.ph = (70.0 + ph_phase * 2.0) as u16;

        // Agitator RPM: driven by batch state
        self.agitator_rpm = match self.batch_state {
            1 => 150, // Heating — slow mix
            2 => 300, // Running — full speed
            3 => 100, // Cooling — gentle
            _ => 0,   // Idle / Complete
        };
    }
}
