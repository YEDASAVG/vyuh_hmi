# Vyuh HMI

**HMI Demo Platform for Industrial Automation** — Flutter app + Rust WebSocket server + Modbus TCP integration for real-time PLC control and monitoring.

Built for pharma industry demos.

## Architecture

```
┌─────────────────────────────────┐
│       Flutter HMI App           │
│  (Charts, Gauges, Controls)     │
│  MobX State + WebSocket Client  │
└──────────────┬──────────────────┘
               │ WebSocket + REST API
               │
┌──────────────┴──────────────────┐
│       Rust Server (Axum)        │
│  - WebSocket broadcast          │
│  - REST API (history/config)    │
│  - SQLite storage               │
│  - Background PLC polling       │
└──────────────┬──────────────────┘
               │ Modbus TCP / OPC UA
               │
┌──────────────┴──────────────────┐
│    PLC Devices / Simulators     │
└─────────────────────────────────┘
```

## Tech Stack

### Rust Server
- **Axum** — HTTP + WebSocket server
- **Tokio** — Async runtime
- **tokio-modbus** — Modbus TCP client
- **SQLx** — SQLite database
- **Serde** — JSON serialization

### Flutter App
- **MobX** — Reactive state management
- **fl_chart** — Real-time data charts
- **web_socket_channel** — WebSocket client

## Getting Started

### Server

```bash
cd server
cargo run
```

Server runs on `http://localhost:3000`

### Flutter App

```bash
cd app
flutter pub get
flutter run
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/devices` | List all PLC devices |
| GET | `/api/history?device_id=X&limit=N` | Get historical data |
| WS | `/ws` | Real-time data stream |

## License

MIT
