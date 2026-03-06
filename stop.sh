#!/bin/bash
#───────────────────────────────────────────────────────────────
# Vyuh HMI — Clean Shutdown
# Stops all services started by start.sh
#───────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT_DIR/.vyuh_pids"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║          Vyuh HMI — Stopping All Services                ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

KILLED=0

# Kill PIDs from the PID file
if [ -f "$PID_FILE" ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            PROC_NAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            kill "$pid" 2>/dev/null
            echo -e "  ${RED}✗${NC} Stopped PID $pid ($PROC_NAME)"
            KILLED=$((KILLED + 1))
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

# Also kill any stragglers by name (safety net)
for PATTERN in "modbus_sim.py" "opcua_sim" "server/target.*server"; do
    PIDS=$(pgrep -f "$PATTERN" 2>/dev/null || true)
    for pid in $PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            PROC_NAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            kill "$pid" 2>/dev/null
            echo -e "  ${RED}✗${NC} Stopped PID $pid ($PROC_NAME) [straggler]"
            KILLED=$((KILLED + 1))
        fi
    done
done

# Clean up temp logs
rm -f /tmp/vyuh_server.log

echo ""
if [ "$KILLED" -gt 0 ]; then
    echo -e "${GREEN}  Done — stopped $KILLED process(es).${NC}"
else
    echo -e "${YELLOW}  No Vyuh HMI processes were running.${NC}"
fi
echo ""
