#!/usr/bin/env python3
"""
Pharma Batch Reactor Simulator — Modbus TCP on port 5020

Simulates a realistic pharma manufacturing batch process:
  IDLE → HEATING → HOLDING → COOLING → COMPLETE → IDLE (repeat)

Registers (Holding Registers, address 1028-1035):
  1028 = Temperature (°C)         [READ-ONLY — driven by simulation]
  1029 = Pressure (mbar)          [READ-ONLY — driven by simulation]
  1030 = Humidity (%)              [READ-ONLY — driven by simulation]
  1031 = Flow Rate (L/min)         [READ-ONLY — driven by simulation]
  1032 = Batch State               [WRITABLE — 0=IDLE resets batch]
  1033 = Batch Progress (0-100%)   [READ-ONLY — driven by simulation]
  1034 = Agitator Speed (RPM)      [WRITABLE — operator override]
  1035 = pH Level (×10)            [READ-ONLY — driven by simulation]

Phase 4: Now handles Modbus write requests for registers 1032 and 1034.
  - Writing 0 to register 1032 → forces batch to IDLE (emergency stop)
  - Writing to register 1034 → overrides agitator speed (operator control)
"""

import random
import time
import threading
import math
from pymodbus.server import StartTcpServer
from pymodbus.datastore import (
    ModbusSequentialDataBlock,
    ModbusDeviceContext,
    ModbusServerContext,
)

# --- Batch States ---
IDLE = 0
HEATING = 1
HOLDING = 2
COOLING = 3
COMPLETE = 4

STATE_NAMES = {
    IDLE: "IDLE",
    HEATING: "HEATING",
    HOLDING: "HOLDING",
    COOLING: "COOLING",
    COMPLETE: "COMPLETE",
}

# --- Process Parameters ---
AMBIENT_TEMP = 25.0       # Starting temperature (°C)
TARGET_TEMP = 80.0        # Batch target temperature (°C)
COOL_TEMP = 30.0          # Cooling target (°C)
HEAT_RATE = 2.0           # °C per second (heating)
COOL_RATE = 1.5           # °C per second (cooling)
HOLD_DURATION = 30        # Seconds to hold at target temp
IDLE_DURATION = 5         # Seconds between batches


class BatchReactor:
    """Simulates a pharma batch reactor process.

    Phase 4 additions:
      - agitator_override: when set (not None), agitator RPM is locked
        to the operator-commanded value instead of following simulation.
      - handle_write(): processes incoming Modbus write commands for
        registers 1032 (batch state) and 1034 (agitator speed).
    """

    def __init__(self):
        self.state = IDLE
        self.temperature = AMBIENT_TEMP
        self.pressure = 1013.0  # mbar (1 atm)
        self.humidity = 55.0
        self.flow_rate = 0.0
        self.agitator_rpm = 0
        self.ph = 7.0
        self.progress = 0
        self.state_timer = 0
        self.batch_count = 0
        # Phase 4: operator overrides
        self.agitator_override = None  # None = simulation-driven, int = operator-set RPM
        self.emergency_stopped = False  # True = stay in IDLE, don't auto-restart
        # Setpoint overrides (None = simulation-driven)
        self.temp_setpoint = None      # temperature override °C
        self.flow_setpoint = None      # flow rate override L/min
        self.ph_setpoint = None        # pH override (raw x10 value)

    def tick(self):
        """Advance simulation by 1 second"""
        self.state_timer += 1
        noise = random.gauss(0, 0.3)  # small random noise

        if self.state == IDLE:
            self.temperature = AMBIENT_TEMP + noise
            self.pressure = 1013.0 + random.gauss(0, 2)
            self.flow_rate = 0
            self.agitator_rpm = 0
            self.ph = 7.0 + random.gauss(0, 0.05)
            self.progress = 0

            if self.state_timer >= IDLE_DURATION and not self.emergency_stopped:
                self._transition(HEATING)

        elif self.state == HEATING:
            self.temperature = min(self.temperature + HEAT_RATE + noise * 0.5, TARGET_TEMP)
            self.pressure = 1013.0 + (self.temperature - AMBIENT_TEMP) * 5  # pressure rises with temp
            self.flow_rate = 15 + random.gauss(0, 1)  # feed flow
            self.agitator_rpm = 200 + int(random.gauss(0, 5))
            self.ph = 7.0 - (self.temperature - AMBIENT_TEMP) * 0.01 + random.gauss(0, 0.02)
            self.progress = int(min((self.temperature - AMBIENT_TEMP) / (TARGET_TEMP - AMBIENT_TEMP) * 33, 33))

            if self.temperature >= TARGET_TEMP - 0.5:
                self._transition(HOLDING)

        elif self.state == HOLDING:
            # Temperature holds with small oscillation
            self.temperature = TARGET_TEMP + math.sin(self.state_timer * 0.3) * 0.3 + noise * 0.1
            self.pressure = 1013.0 + (TARGET_TEMP - AMBIENT_TEMP) * 5 + random.gauss(0, 3)
            self.flow_rate = 5 + random.gauss(0, 0.5)  # maintenance flow
            self.agitator_rpm = 300 + int(random.gauss(0, 3))
            self.ph = 6.5 + random.gauss(0, 0.03)
            self.progress = 33 + int(min(self.state_timer / HOLD_DURATION * 34, 34))

            if self.state_timer >= HOLD_DURATION:
                self._transition(COOLING)

        elif self.state == COOLING:
            self.temperature = max(self.temperature - COOL_RATE + noise * 0.3, COOL_TEMP)
            self.pressure = 1013.0 + (self.temperature - AMBIENT_TEMP) * 5
            self.flow_rate = 20 + random.gauss(0, 1.5)  # coolant flow
            self.agitator_rpm = 150 + int(random.gauss(0, 5))
            self.ph = 6.8 + (COOL_TEMP / self.temperature) * 0.2 + random.gauss(0, 0.02)
            self.progress = 67 + int(min((TARGET_TEMP - self.temperature) / (TARGET_TEMP - COOL_TEMP) * 33, 33))

            if self.temperature <= COOL_TEMP + 0.5:
                self._transition(COMPLETE)

        elif self.state == COMPLETE:
            self.temperature = COOL_TEMP + noise
            self.pressure = 1013.0 + random.gauss(0, 2)
            self.flow_rate = 0
            self.agitator_rpm = 0
            self.ph = 7.0 + random.gauss(0, 0.05)
            self.progress = 100

            if self.state_timer >= 3:
                self.batch_count += 1
                self._transition(IDLE)

    def _transition(self, new_state):
        print(f"  ⚙️  State: {STATE_NAMES[self.state]} → {STATE_NAMES[new_state]}")
        self.state = new_state
        self.state_timer = 0

    def handle_write(self, register, value):
        """Process an external Modbus write request.

        Writable registers:
          1028: Temperature — setpoint override °C (0 clears)
          1031: Flow Rate — setpoint override L/min (0 clears)
          1032: Batch State — writing 0 forces IDLE (emergency stop)
          1034: Agitator Speed — operator override RPM (0 clears)
          1035: pH Level — setpoint override x10 (0 clears)
        """
        if register == 1028:
            if value == 0:
                print(f"  🔄 Temperature setpoint CLEARED — returning to auto")
                self.temp_setpoint = None
            else:
                clamped = max(10, min(150, value))  # safety: 10-150 °C
                self.temp_setpoint = clamped
                print(f"  🌡️  Temperature SETPOINT set to {clamped} °C")
        elif register == 1031:
            if value == 0:
                print(f"  🔄 Flow rate setpoint CLEARED — returning to auto")
                self.flow_setpoint = None
            else:
                clamped = max(0, min(100, value))  # safety: 0-100 L/min
                self.flow_setpoint = clamped
                print(f"  💧 Flow rate SETPOINT set to {clamped} L/min")
        elif register == 1032:
            if value == IDLE:
                print(f"  🛑 EMERGENCY STOP — operator forced IDLE (locked)")
                self._transition(IDLE)
                self.agitator_override = None  # clear agitator override too
                self.emergency_stopped = True  # stay stopped until operator restarts
            elif value == HEATING:
                print(f"  ▶️  OPERATOR START — resuming batch from IDLE")
                self.emergency_stopped = False
                self._transition(HEATING)
            else:
                print(f"  ⚠️  Write to batch state ignored (only 0=STOP, 1=START allowed)")
        elif register == 1034:
            if value == 0:
                print(f"  🔄 Agitator override CLEARED — returning to auto")
                self.agitator_override = None
            else:
                clamped = max(0, min(500, value))  # safety: 0-500 RPM
                self.agitator_override = clamped
                print(f"  🎛️  Agitator OVERRIDE set to {clamped} RPM")
        elif register == 1035:
            if value == 0:
                print(f"  🔄 pH setpoint CLEARED — returning to auto")
                self.ph_setpoint = None
            else:
                clamped = max(30, min(130, value))  # safety: pH 3.0-13.0 (x10)
                self.ph_setpoint = clamped
                print(f"  🧪 pH SETPOINT set to {clamped/10:.1f}")
        else:
            print(f"  ⚠️  Write to read-only register {register} ignored")

    def get_registers(self):
        """Return register values as integers (Modbus only supports u16).

        Operator overrides take precedence over simulation values.
        """
        temp = self.temp_setpoint if self.temp_setpoint is not None else max(0, int(self.temperature))
        flow = self.flow_setpoint if self.flow_setpoint is not None else max(0, int(self.flow_rate))
        agitator = self.agitator_override if self.agitator_override is not None else self.agitator_rpm
        ph = self.ph_setpoint if self.ph_setpoint is not None else max(0, min(140, int(self.ph * 10)))
        return [
            max(0, int(temp)),                                 # 1028: temp °C
            max(0, int(self.pressure)),                        # 1029: pressure mbar
            max(0, min(100, int(self.humidity + random.gauss(0, 1)))),  # 1030: humidity %
            max(0, int(flow)),                                 # 1031: flow L/min
            self.state,                                        # 1032: batch state
            self.progress,                                     # 1033: progress %
            max(0, agitator),                                  # 1034: agitator RPM (may be overridden)
            max(0, int(ph)),                                   # 1035: pH × 10
        ]


# --- Modbus Setup ---
block = ModbusSequentialDataBlock(0, [0] * 2000)
store = ModbusDeviceContext(hr=block)
context = ModbusServerContext(devices=store, single=True)

reactor = BatchReactor()

# Writable register addresses and their offsets from base (1028)
WRITABLE_REGISTERS = {1028: 0, 1031: 3, 1032: 4, 1034: 6, 1035: 7}

# Track last-written values to detect external writes
last_written = {1028: None, 1031: None, 1032: None, 1034: None, 1035: None}


def update_values():
    """Run batch reactor simulation, update registers every second.

    Also checks for external Modbus writes to writable registers and
    forwards them to the reactor's handle_write() method.
    """
    global last_written  # noqa: PLW0603
    while True:
        time.sleep(1)

        # --- Check for external writes BEFORE ticking simulation ---
        for reg, offset in WRITABLE_REGISTERS.items():
            current = context[0x00].getValues(3, reg, 1)[0]
            if last_written[reg] is not None and current != last_written[reg]:
                reactor.handle_write(reg, current)
            last_written[reg] = current

        reactor.tick()
        values = reactor.get_registers()
        context[0x00].setValues(3, 1028, values)

        # Update last_written after simulation writes (so we don't false-trigger)
        for reg, offset in WRITABLE_REGISTERS.items():
            last_written[reg] = values[offset]

        state_name = STATE_NAMES[reactor.state]
        override_tag = " [AGI-OVR]" if reactor.agitator_override is not None else ""
        print(
            f"[Batch #{reactor.batch_count + 1}] {state_name:>9} | "
            f"temp={values[0]:3d}°C  press={values[1]:5d}mbar  "
            f"humid={values[2]:2d}%  flow={values[3]:2d}L/min  "
            f"agit={values[6]:3d}RPM  pH={values[7]/10:.1f}  "
            f"progress={values[5]:3d}%{override_tag}"
        )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Pharma Modbus Simulator")
    parser.add_argument("--port", type=int, default=5020, help="Modbus TCP port (default: 5020)")
    parser.add_argument("--name", type=str, default="Batch Reactor", help="Device name for display")
    args = parser.parse_args()

    t = threading.Thread(target=update_values, daemon=True)
    t.start()

    print("=" * 65)
    print(f"  🏭 {args.name} Simulator")
    print(f"  Modbus TCP on 0.0.0.0:{args.port}")
    print("=" * 65)
    print("Registers:")
    print("  1028 = Temperature (°C)        [WRITABLE → setpoint override]")
    print("  1029 = Pressure (mbar)          [READ-ONLY]")
    print("  1030 = Humidity (%)              [READ-ONLY]")
    print("  1031 = Flow Rate (L/min)         [WRITABLE → setpoint override]")
    print("  1032 = Batch State               [WRITABLE → 0=IDLE stops batch]")
    print("  1033 = Batch Progress (0-100%)   [READ-ONLY]")
    print("  1034 = Agitator Speed (RPM)      [WRITABLE → operator override]")
    print("  1035 = pH Level (×10)            [WRITABLE → setpoint override]")
    print("=" * 65)
    print()
    StartTcpServer(context=context, address=("0.0.0.0", args.port))