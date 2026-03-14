#!/bin/bash
#───────────────────────────────────────────────────────────────
# VYUH Technology — Industrial HMI Launcher
#───────────────────────────────────────────────────────────────

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT_DIR/.vyuh_pids"

# ── Colors ────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
ORANGE='\033[38;5;208m'
WHITE='\033[1;37m'
GRAY='\033[38;5;243m'
NC='\033[0m'

# ── Animated spinner ──────────────────────────────────────────
spin() {
    local msg="$1"
    local pid="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${ORANGE}${frames[$i]}${NC} ${GRAY}%s${NC}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
    printf "\r"
}

# ── Progress bar ──────────────────────────────────────────────
progress_bar() {
    local current=$1
    local total=$2
    local width=30
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▰"; done
    for ((i=0; i<empty; i++)); do bar+="▱"; done
    printf "${ORANGE}%s${GRAY}${NC}" "$bar"
}

clear
echo ""
echo ""
echo -e "${CYAN}  ██╗   ██╗██╗   ██╗██╗   ██╗██╗  ██╗${NC}"
echo -e "${CYAN}  ██║   ██║╚██╗ ██╔╝██║   ██║██║  ██║${NC}"
echo -e "${CYAN}  ██║   ██║ ╚████╔╝ ██║   ██║███████║${NC}"
echo -e "${CYAN}  ╚██╗ ██╔╝  ╚██╔╝  ██║   ██║██╔══██║${NC}"
echo -e "${CYAN}   ╚████╔╝    ██║   ╚██████╔╝██║  ██║${NC}"
echo -e "${CYAN}    ╚═══╝     ╚═╝    ╚═════╝ ╚═╝  ╚═╝${NC}"
echo -e "${GRAY}          T E C H N O L O G Y${NC}"
echo ""
echo -e "${WHITE}     Industrial HMI — SCADA Control System${NC}"
echo ""
echo -e "${GRAY}  ─────────────────────────────────────────${NC}"
echo -e "  ${DIM}●${NC} PLC-01  Batch Reactor      ${DIM}Modbus  → port 5020${NC}"
echo -e "  ${DIM}●${NC} PLC-02  Cooling Tower      ${DIM}Modbus  → port 5021${NC}"
echo -e "  ${DIM}●${NC} PLC-03  Sterile Filling    ${DIM}OPC UA → port 4840${NC}"
echo -e "  ${DIM}●${NC} VYUH Server                ${DIM}API    → port 3000${NC}"
echo -e "${GRAY}  ─────────────────────────────────────────${NC}"
echo ""

# Clean up any old PID file
rm -f "$PID_FILE"
touch "$PID_FILE"

cleanup() {
    echo ""
    echo -e "  ${YELLOW}Shutting down... (use ./stop.sh for clean shutdown)${NC}"
    bash "$ROOT_DIR/stop.sh" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

STEP=0
TOTAL=5

#───────────────────────────────────────────────────────────────
# 1. PLC-01 — Batch Reactor (Modbus)
#───────────────────────────────────────────────────────────────
STEP=$((STEP + 1))
printf "  $(progress_bar $STEP $TOTAL)  ${GRAY}Initializing PLC-01 Batch Reactor...${NC}"
sleep 1.2

python3 "$ROOT_DIR/simulator/modbus_sim.py" --port 5020 --name "Batch Reactor (PLC-01)" > /dev/null 2>&1 &
echo "$!" >> "$PID_FILE"
printf "\r\033[K  ${GREEN}✓${NC} PLC-01  Batch Reactor      ${GRAY}Modbus  → port 5020${NC}\n"

sleep 0.8
STEP=$((STEP + 1))
printf "  $(progress_bar $STEP $TOTAL)  ${GRAY}Initializing PLC-02 Cooling Tower...${NC}"
sleep 1.0

python3 "$ROOT_DIR/simulator/modbus_sim.py" --port 5021 --name "Cooling Tower (PLC-02)" > /dev/null 2>&1 &
echo "$!" >> "$PID_FILE"
printf "\r\033[K  ${GREEN}✓${NC} PLC-02  Cooling Tower      ${GRAY}Modbus  → port 5021${NC}\n"

#───────────────────────────────────────────────────────────────
# 2. PLC-03 — Sterile Filling (OPC UA)
#───────────────────────────────────────────────────────────────
sleep 0.8
STEP=$((STEP + 1))
printf "  $(progress_bar $STEP $TOTAL)  ${GRAY}Initializing PLC-03 Sterile Filling...${NC}"

OPCUA_BIN="$ROOT_DIR/server/target/release/opcua_sim"
if [ ! -f "$OPCUA_BIN" ]; then
    OPCUA_BIN="$ROOT_DIR/server/target/debug/opcua_sim"
fi
if [ ! -f "$OPCUA_BIN" ]; then
    echo -e "  ${YELLOW}⚠${NC}  Building OPC UA simulator (first run)..."
    (cd "$ROOT_DIR/server" && cargo build --bin opcua_sim 2>/dev/null)
    OPCUA_BIN="$ROOT_DIR/server/target/debug/opcua_sim"
fi

if [ -f "$OPCUA_BIN" ]; then
    sleep 1.2
    (cd "$ROOT_DIR/server" && "$OPCUA_BIN") > /dev/null 2>&1 &
    echo "$!" >> "$PID_FILE"
    printf "\r\033[K  ${GREEN}✓${NC} PLC-03  Sterile Filling    ${GRAY}OPC UA → port 4840${NC}\n"
else
    printf "\r\033[K  ${YELLOW}⚠${NC}  OPC UA simulator not found — skipping\n"
fi

#───────────────────────────────────────────────────────────────
# 3. VYUH Server
#───────────────────────────────────────────────────────────────
sleep 0.8
STEP=$((STEP + 1))
printf "  $(progress_bar $STEP $TOTAL)  ${GRAY}Starting VYUH Server...${NC}"

SERVER_BIN="$ROOT_DIR/server/target/release/server"
if [ ! -f "$SERVER_BIN" ]; then
    SERVER_BIN="$ROOT_DIR/server/target/debug/server"
fi
if [ ! -f "$SERVER_BIN" ]; then
    echo -e "  ${YELLOW}⚠${NC}  Building server (first run — may take a minute)..."
    (cd "$ROOT_DIR/server" && cargo build --bin server 2>/dev/null)
    SERVER_BIN="$ROOT_DIR/server/target/debug/server"
fi

(cd "$ROOT_DIR/server" && RUST_LOG=info "$SERVER_BIN") > /tmp/vyuh_server.log 2>&1 &
echo "$!" >> "$PID_FILE"

# Wait for server health check
printf "  ${ORANGE}⠋${NC} ${GRAY}VYUH Server starting...${NC}"
for i in $(seq 1 30); do
    if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
        break
    fi
    # Spinner animation while waiting
    frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    idx=$(( (i - 1) % 10 ))
    printf "\r  ${ORANGE}${frames[$idx]}${NC} ${GRAY}VYUH Server starting...${NC}"
    sleep 0.5
done
printf "\r\033[K  ${GREEN}✓${NC} VYUH Server                ${GRAY}API    → port 3000${NC}\n"

STEP=$((STEP + 1))

#───────────────────────────────────────────────────────────────
# Done
#───────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAY}  ─────────────────────────────────────────${NC}"
echo ""
echo -e "  $(progress_bar $TOTAL $TOTAL)  ${GREEN}${BOLD}All systems operational${NC}"
echo ""
echo -e "  ${WHITE}API${NC}          ${CYAN}http://localhost:3000${NC}"
echo -e "  ${WHITE}WebSocket${NC}    ${CYAN}ws://localhost:3000/ws${NC}"
echo -e "  ${WHITE}Dashboard${NC}    ${CYAN}cd app && flutter run -d macos${NC}"
echo ""
echo -e "  ${GRAY}Logs  →  tail -f /tmp/vyuh_server.log${NC}"
echo -e "  ${GRAY}Stop  →  ${YELLOW}./stop.sh${NC}"
echo ""

# Keep script alive so Ctrl+C triggers cleanup
wait
