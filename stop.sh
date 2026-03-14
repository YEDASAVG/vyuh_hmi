#!/bin/bash
#───────────────────────────────────────────────────────────────
# VYUH Technology — Clean Shutdown
#───────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT_DIR/.vyuh_pids"

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[38;5;243m'
NC='\033[0m'

echo ""
echo -e "${RED}  ██╗   ██╗██╗   ██╗██╗   ██╗██╗  ██╗${NC}"
echo -e "${RED}  ╚██╗ ██╔╝ ╚██╔╝  ██║   ██║██╔══██║${NC}"
echo -e "${RED}   ╚████╔╝   ██║   ╚██████╔╝██║  ██║${NC}"
echo -e "${RED}    ╚═══╝    ╚═╝    ╚═════╝ ╚═╝  ╚═╝${NC}"
echo ""
echo -e "  ${RED}${BOLD}Shutting down all services${NC}"
echo -e "${GRAY}  ─────────────────────────────────────────${NC}"
echo ""

KILLED=0

# Kill PIDs from the PID file
if [ -f "$PID_FILE" ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            PROC_NAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            kill "$pid" 2>/dev/null
            echo -e "  ${RED}✗${NC} Stopped ${GRAY}$PROC_NAME${NC} ${GRAY}(PID $pid)${NC}"
            KILLED=$((KILLED + 1))
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

# Kill any stragglers by name
for PATTERN in "modbus_sim.py" "opcua_sim" "server/target.*server"; do
    PIDS=$(pgrep -f "$PATTERN" 2>/dev/null || true)
    for pid in $PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            PROC_NAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            kill "$pid" 2>/dev/null
            echo -e "  ${RED}✗${NC} Stopped ${GRAY}$PROC_NAME${NC} ${GRAY}(PID $pid)${NC}"
            KILLED=$((KILLED + 1))
        fi
    done
done

# Clean up temp logs
rm -f /tmp/vyuh_server.log

echo ""
echo -e "${GRAY}  ─────────────────────────────────────────${NC}"
if [ "$KILLED" -gt 0 ]; then
    echo -e "  ${GREEN}●${NC} Stopped ${WHITE}$KILLED${NC} service(s) — ${GREEN}clean shutdown${NC}"
else
    echo -e "  ${YELLOW}●${NC} No VYUH services were running"
fi
echo ""
