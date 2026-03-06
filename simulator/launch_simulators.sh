#!/bin/bash
# Launch two Modbus simulators for multi-PLC testing (Phase 6)
# Usage: ./launch_simulators.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIM="$SCRIPT_DIR/modbus_sim.py"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Phase 6: Multi-PLC Simulator Launcher              ║"
echo "║  PLC-01: Batch Reactor  → port 5020                 ║"
echo "║  PLC-02: Cooling Tower  → port 5021                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Start PLC-01 (Batch Reactor) in background
python3 "$SIM" --port 5020 --name "Batch Reactor (PLC-01)" &
PID1=$!
echo "Started PLC-01 (PID: $PID1) on port 5020"

# Small delay to avoid port conflicts
sleep 1

# Start PLC-02 (Cooling Tower) in background
python3 "$SIM" --port 5021 --name "Cooling Tower (PLC-02)" &
PID2=$!
echo "Started PLC-02 (PID: $PID2) on port 5021"

echo ""
echo "Both simulators running. Press Ctrl+C to stop all."
echo ""

# Trap Ctrl+C to kill both
trap "echo 'Stopping simulators...'; kill $PID1 $PID2 2>/dev/null; exit 0" SIGINT SIGTERM

# Wait for both
wait
