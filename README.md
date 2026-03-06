# Vyuh HMI

**Production-grade Human-Machine Interface for GMP-regulated manufacturing** — Rust server + Flutter cross-platform client with real-time PLC monitoring, ISA-18.2 alarms, ISA-88 batch records, and 21 CFR Part 11 compliance.

Built for pharma, biotech, and specialty chemical plants.

---

## Quick Start

```bash
# Start everything — simulators, server, and app
./start.sh

# Stop everything
./stop.sh
```

That's it. The launcher starts Modbus simulators (2 PLCs), OPC UA simulator, the Rust server on port 3000, and the Flutter app.

### Manual Start

```bash
# 1. Simulators
cd simulator && python3 modbus_sim.py --port 5020 &
python3 modbus_sim.py --port 5021 &

# 2. Server
cd server && cargo run --bin server

# 3. App (pick a platform)
cd app && flutter run -d macos    # or chrome, linux, windows
```

---

## Architecture

```
┌─────────────────────┐    HTTP/WS     ┌────────────────────────┐
│    Flutter App       │◄──────────────►│     Rust Server        │
│                      │    :3000       │     (Axum + Tokio)     │
│  7-Tab Navigation    │               │                        │
│  • Dashboard         │               │  • JWT Auth (RBAC)     │
│  • PLC Detail        │               │  • Audit Trail         │
│  • History           │               │  • Rate Limiting       │
│  • Alarms (ISA-18.2) │               │  • TLS/HTTPS           │
│  • Batches (ISA-88)  │               │  • CSV Export          │
│  • Devices           │               │  • WebSocket Broadcast │
│  • Audit Trail       │               │  • SQLite / TSDB       │
└─────────────────────┘               └──────────┬─────────────┘
                                                  │
                                    ┌─────────────┼─────────────┐
                                    │             │             │
                              ┌─────▼─────┐ ┌────▼─────┐ ┌────▼─────┐
                              │ Modbus TCP│ │ OPC UA   │ │ SQLite   │
                              │ PLC-01,02 │ │ PLC-03   │ │   DB     │
                              └───────────┘ └──────────┘ └──────────┘
```

---

## Features

### Industrial Protocols
- **Modbus TCP** — tokio-modbus client with per-device polling
- **OPC UA** — native Rust client (opcua crate), browse + subscribe
- **Protocol abstraction** — trait-based, add MQTT/EtherNet/IP without changing core

### Alarm Management (ISA-18.2)
- Priority levels: Critical, High, Medium, Low, Info
- State machine: Active → Acknowledged → Cleared / Shelved
- Operator acknowledgment with comments
- Time-based shelving with auto-unshelve
- Full alarm history with CSV export

### Batch Records (ISA-88)
- Batch lifecycle: Running → Completed / Aborted
- Step tracking with parameters and results
- Operator attribution on every action
- Exportable batch records for compliance audits

### 21 CFR Part 11 Compliance
- Role-based access (Admin / Operator / Viewer)
- Argon2 password hashing with complexity enforcement
- JWT authentication with server-side session revocation
- Electronic signatures for critical operations
- Immutable audit trail (user, action, timestamp, IP)
- Brute-force protection (5 attempts → lockout)
- Session inactivity timeout (15 minutes)

### Production Hardening
- **TLS/HTTPS** — axum-server + rustls, config-driven
- **Rate limiting** — token-bucket per IP (100 burst, 20/sec)
- **Docker** — multi-stage Dockerfile + docker-compose
- **CSV export** — alarms, batches, audit trail, history
- **Time-series adapter** — pluggable SQLite → InfluxDB/TimescaleDB
- **15 integration tests** — config, DB CRUD, auth, JWT, TSDB

---

## Tech Stack

### Rust Server (~15 MB binary, <1s startup)
| Crate | Purpose |
|-------|---------|
| **axum 0.8** | HTTP + WebSocket server |
| **tokio** | Async runtime |
| **tokio-modbus** | Modbus TCP client |
| **opcua 0.12** | OPC UA client + simulator |
| **sqlx** | SQLite with compile-time safety |
| **axum-server** | TLS/HTTPS (rustls) |
| **argon2** | Password hashing |
| **jsonwebtoken** | JWT auth |
| **csv** | Data export |

### Flutter App (iOS, Android, Web, macOS, Windows, Linux)
| Package | Purpose |
|---------|---------|
| **MobX** | Reactive state management |
| **fl_chart** | Real-time line/bar charts |
| **web_socket_channel** | Live data streaming |
| **google_fonts** | Typography |
| **shared_preferences** | Local settings |

---

## API Overview

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/login` | — | Login, get JWT |
| POST | `/api/auth/logout` | Any | Invalidate session |
| POST | `/api/auth/esig` | Any | Electronic signature |
| GET | `/api/devices` | Any | List PLC devices |
| POST | `/api/devices` | Operator+ | Add device at runtime |
| DELETE | `/api/devices/{id}` | Operator+ | Remove device |
| POST | `/api/discover` | Operator+ | Scan network for PLCs |
| GET | `/api/history` | Any | Historical readings |
| POST | `/api/write` | Operator+ | Write to PLC register |
| GET | `/api/alarms` | Any | List alarms |
| POST | `/api/alarms/{id}/ack` | Operator+ | Acknowledge alarm |
| POST | `/api/alarms/{id}/shelve` | Operator+ | Shelve alarm |
| GET | `/api/batches` | Any | List batch records |
| GET | `/api/batches/{id}` | Any | Batch with steps |
| GET | `/api/audit` | Any | Audit trail |
| GET | `/api/export/*.csv` | Any | CSV data export |
| GET | `/api/users` | Admin | User management |
| GET | `/ws` | Token | Real-time WebSocket |
| GET | `/health` | — | Health check |

Full details in [API-REFERENCE.md](API-REFERENCE.md).

---

## Configuration

Edit `server/config.toml` — zero code changes needed:

```toml
[server]
host = "0.0.0.0"
port = 3000
jwt_secret = "your-secret-at-least-32-characters-long"
# tls_cert = "certs/cert.pem"
# tls_key = "certs/key.pem"

[database]
path = "hmi_data.db"

[[devices]]
id = "plc-01"
name = "Batch Reactor"
address = "127.0.0.1:5020"
protocol = "modbus"           # or "opcua"
poll_rate_ms = 1000
register_start = 1028
register_count = 8
writable = [1032, 1034]
```

---

## Default Users

| Username | Password | Role |
|----------|----------|------|
| `admin` | `Admin123!` | Admin |
| `operator` | `Operator123!` | Operator |
| `viewer` | `Viewer123!` | Viewer |

⚠ Change all passwords before production deployment.

---

## Docker

```bash
docker compose up -d        # Start server
docker compose logs -f      # View logs
docker compose down         # Stop
```

---

## Testing

```bash
cd server && cargo test     # 15 integration tests
cd app && flutter test      # Widget tests
```

---

## Project Structure

```
vyuh_hmi/
├── start.sh                 # One-command launcher
├── stop.sh                  # Clean shutdown
├── docker-compose.yml       # Container deployment
├── server/
│   ├── config.toml          # Device & server config
│   ├── Dockerfile           # Multi-stage build
│   └── src/
│       ├── main.rs          # Bootstrap, routing
│       ├── auth.rs          # Auth, audit, e-sig (21 CFR 11)
│       ├── routes.rs        # API handlers
│       ├── db.rs            # SQLite CRUD
│       ├── ws.rs            # WebSocket streaming
│       ├── modbus.rs        # Modbus TCP client
│       ├── opcua_client.rs  # OPC UA client
│       ├── protocol.rs      # Protocol abstraction trait
│       ├── discovery.rs     # Network device scanning
│       ├── export.rs        # CSV export
│       ├── rate_limit.rs    # Token-bucket rate limiter
│       └── tsdb.rs          # Time-series DB adapter
├── app/
│   └── lib/
│       ├── main.dart        # App entry, 7-tab nav
│       ├── screens/         # Dashboard, Alarms, Batches, etc.
│       ├── services/        # HTTP + WebSocket clients
│       ├── stores/          # MobX state stores
│       └── widgets/         # Charts, gauges, cards
├── simulator/
│   └── modbus_sim.py        # Pharma batch reactor simulator
└── docs/
    ├── API-REFERENCE.md
    ├── DEPLOYMENT-GUIDE.md
    └── MARKET-RESEARCH.md
```

---

## Documentation

- [API Reference](API-REFERENCE.md) — All endpoints with request/response examples
- [Deployment Guide](DEPLOYMENT-GUIDE.md) — Docker, TLS, systemd, backups
- [Market Research](MARKET-RESEARCH.md) — Competitive analysis vs Ignition, WinCC, FactoryTalk
- [Build Plan](VYUH-HMI-BUILD-PLAN.md) — 88-step development plan (100% complete)

---

## License

MIT
