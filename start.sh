#!/bin/bash
#───────────────────────────────────────────────────────────────
# Vyuh HMI — One-Command Launcher
# Starts: Modbus Simulators → OPC UA Simulator → Rust Server → Flutter App
#───────────────────────────────────────────────────────────────

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT_DIR/.vyuh_pids"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          ${GREEN}Vyuh HMI — Full Stack Launcher${CYAN}                  ║${NC}"
echo -e "${CYAN}║                                                           ║${NC}"
echo -e "${CYAN}║  ${NC}1. Modbus Simulators  (ports 5020, 5021)${CYAN}                 ║${NC}"
echo -e "${CYAN}║  ${NC}2. OPC UA Simulator   (port 4840)${CYAN}                        ║${NC}"
echo -e "${CYAN}║  ${NC}3. Rust Server        (port 3000)${CYAN}                        ║${NC}"
echo -e "${CYAN}║  ${NC}4. Flutter App         (run separately)${CYAN}                  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Clean up any old PID file
rm -f "$PID_FILE"
touch "$PID_FILE"

cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down... (use ./stop.sh for clean shutdown)${NC}"
    bash "$ROOT_DIR/stop.sh" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

#───────────────────────────────────────────────────────────────
# 1. Modbus Simulators
#───────────────────────────────────────────────────────────────
echo -e "${GREEN}[1/4]${NC} Starting Modbus simulators..."

python3 "$ROOT_DIR/simulator/modbus_sim.py" --port 5020 --name "Batch Reactor (PLC-01)" > /dev/null 2>&1 &
echo "$!" >> "$PID_FILE"
echo -e "  ✓ PLC-01  Batch Reactor    → port 5020  (PID $!)"

sleep 0.5

python3 "$ROOT_DIR/simulator/modbus_sim.py" --port 5021 --name "Cooling Tower (PLC-02)" > /dev/null 2>&1 &
echo "$!" >> "$PID_FILE"
echo -e "  ✓ PLC-02  Cooling Tower    → port 5021  (PID $!)"

sleep 0.5

#───────────────────────────────────────────────────────────────
# 2. OPC UA Simulator
#───────────────────────────────────────────────────────────────
echo -e "${GREEN}[2/4]${NC} Starting OPC UA simulator..."

# Check if the binary exists, build if not
OPCUA_BIN="$ROOT_DIR/server/target/release/opcua_sim"
if [ ! -f "$OPCUA_BIN" ]; then
    OPCUA_BIN="$ROOT_DIR/server/target/debug/opcua_sim"
fi
if [ ! -f "$OPCUA_BIN" ]; then
    echo -e "  ${YELLOW}Building OPC UA simulator (first run)...${NC}"
    (cd "$ROOT_DIR/server" && cargo build --bin opcua_sim 2>/dev/null)
    OPCUA_BIN="$ROOT_DIR/server/target/debug/opcua_sim"
fi

if [ -f "$OPCUA_BIN" ]; then
    (cd "$ROOT_DIR/server" && "$OPCUA_BIN") > /dev/null 2>&1 &
    echo "$!" >> "$PID_FILE"
    echo -e "  ✓ PLC-03  Sterile Filling  → port 4840  (PID $!)"
else
    echo -e "  ${YELLOW}⚠ OPC UA simulator not found — skipping (Modbus PLCs still work)${NC}"
fi

sleep 1

#───────────────────────────────────────────────────────────────
# 3. Rust Server
#───────────────────────────────────────────────────────────────
echo -e "${GREEN}[3/4]${NC} Starting Rust server..."

# Check if release binary exists, otherwise use cargo run
SERVER_BIN="$ROOT_DIR/server/target/release/server"
if [ ! -f "$SERVER_BIN" ]; then
    SERVER_BIN="$ROOT_DIR/server/target/debug/server"
fi
if [ ! -f "$SERVER_BIN" ]; then
    echo -e "  ${YELLOW}Building server (first run — may take a minute)...${NC}"
    (cd "$ROOT_DIR/server" && cargo build --bin server 2>/dev/null)
    SERVER_BIN="$ROOT_DIR/server/target/debug/server"
fi

(cd "$ROOT_DIR/server" && RUST_LOG=info "$SERVER_BIN") > /tmp/vyuh_server.log 2>&1 &
echo "$!" >> "$PID_FILE"
echo -e "  ✓ Server                   → http://localhost:3000  (PID $!)"

# Wait for server to be ready
echo -n "  Waiting for server..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
        echo -e " ${GREEN}ready!${NC}"
        break
    fi
    sleep 0.5
    echo -n "."
done

#───────────────────────────────────────────────────────────────
# Done
#───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All services running!${NC}"
echo -e ""
echo -e "  API:       ${CYAN}http://localhost:3000${NC}"
echo -e "  Health:    ${CYAN}http://localhost:3000/health${NC}"
echo -e "  WebSocket: ${CYAN}ws://localhost:3000/ws${NC}"
echo -e ""
echo -e "  Flutter:   ${CYAN}cd app && flutter run -d macos${NC}"
echo -e ""
echo -e "  Logs:      tail -f /tmp/vyuh_server.log"
echo -e "  Stop:      ${YELLOW}./stop.sh${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Keep script alive so Ctrl+C triggers cleanup
wait
