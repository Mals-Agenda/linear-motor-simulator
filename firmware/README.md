# EM Crossbow MCU Firmware

Pure C++17, no platform dependencies.
Same source flashes to hardware **and** drives the Godot digital twin.

## Files

| File | Purpose |
|------|---------|
| `hal.h` | `IHal` interface — all hardware I/O routed through this |
| `mcu_fw.h / .cpp` | `McuFirmware` — state machine, cascade, velocity profile |
| `stub_hal.h` | Minimal HAL for unit testing without Godot |
| `stub_test.cpp` | Unit tests (ARM / cascade / fault) |

## Architecture

```
┌────────────────────────────────────────┐
│           McuFirmware                  │  ← same on sim + hardware
│  • N-stage state machine               │
│  • Position-cascade firing             │
│  • Velocity-profile voltage calc       │
└──────────────────┬─────────────────────┘
                   │ IHal*
        ┌──────────┴──────────┐
        │                     │
  ┌─────┴──────┐       ┌──────┴───────┐
  │ GodotHal   │       │  Stm32Hal    │
  │(gdextension│       │  ArduinoHal  │  (future)
  │ /godot_hal)│       └──────────────┘
  └─────┬──────┘
        │ calls Godot Object methods
  ┌─────┴────────────────────────┐
  │  PowerPack.gd  Solenoid.gd  │
  │  (GDScript physics nodes)   │
  └─────────────────────────────┘
```

## Build — unit tests (no Godot)

```bash
cd firmware
g++ -std=c++17 stub_test.cpp mcu_fw.cpp -o stub_test && ./stub_test
```

## Build — GDExtension (Godot digital twin)

```bash
# 1. Clone godot-cpp next to this project (branch 4.x)
git clone https://github.com/godotengine/godot-cpp.git ../godot-cpp

# 2. Build godot-cpp
cd ../godot-cpp && scons platform=linux && cd -

# 3. Build the extension
cd gdextension && scons platform=linux

# 4. Copy mcu.gdextension to res:// and set the MCU node to McuNode type
```

## Porting to hardware (STM32 / Arduino)

1. Implement `IHal` in `hardware/stm32_hal.h` (or `arduino_hal.h`).
2. Map `cap_begin_charge()` → your MOSFET gate driver + PWM charger.
3. Map `sense_voltage()` → ADC channel.
4. Call `fw.tick(delta_s)` from your 1 kHz timer ISR or RTOS task.
5. All state-machine logic stays in `mcu_fw.cpp` — unchanged.

## Stage state machine

```
       arm_request()
SAFE ──────────────► CHARGING
                         │ charge_complete
                         ▼
                      ARMED
                         │ fire_stage(i)
                         ▼
                      FIRING ──► timeout ──► FAULT
                         │ coil drains
                         ▼
                       SAFE
```
