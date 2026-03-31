#pragma once
/**
 * hal.h — Hardware Abstraction Layer for the EM-crossbow MCU firmware.
 *
 * All hardware I/O is routed through this interface so the same firmware
 * binary can be unit-tested on a host, simulated inside Godot, or flashed
 * to an STM32 / AVR without touching any logic code.
 *
 * Implementation objects:
 *   GodotHal   (gdextension/godot_hal.h)  — Godot simulation
 *   StubHal    (firmware/stub_hal.h)      — unit-test / headless
 *   Stm32Hal   (hardware/stm32_hal.h)     — real MCU (future)
 */

#include <cstdint>

namespace mcu {

// ── Stage indices & counts ────────────────────────────────────────────────────
static constexpr int MAX_STAGES = 32;

// ── Per-stage hardware channels ───────────────────────────────────────────────
struct StageHW {
    int index;          ///< stage number 0..N-1
};

// ── HAL interface ─────────────────────────────────────────────────────────────
class IHal {
public:
    virtual ~IHal() = default;

    // ── Time ─────────────────────────────────────────────────────────────────
    /// Monotonic time in seconds since firmware start.
    virtual float time_s() const = 0;

    // ── Capacitor bank control (per stage) ───────────────────────────────────
    /// Start charging stage i to target_v volts.
    virtual void cap_begin_charge(int stage, float target_v) = 0;
    /// Close the fire MOSFET for stage i.
    virtual void cap_fire(int stage) = 0;
    /// Open fire switch and close bleed resistor for stage i.
    virtual void cap_drain(int stage) = 0;
    /// Open all switches (idle/safe state).
    virtual void cap_safe(int stage) = 0;

    // ── Sensors (per stage) ───────────────────────────────────────────────────
    /// Capacitor voltage [V].
    virtual float sense_voltage(int stage) const = 0;
    /// Coil current [A].
    virtual float sense_current(int stage) const = 0;
    /// Coil temperature [°C].
    virtual float sense_temp(int stage) const = 0;
    /// True while stage i capacitor bank is still charging.
    virtual bool  is_charging(int stage) const = 0;
    /// True while stage i fire switch is closed.
    virtual bool  is_firing(int stage) const = 0;
    /// True while stage i drain switch is closed.
    virtual bool  is_draining(int stage) const = 0;

    // ── Barrel position sensor ────────────────────────────────────────────────
    /// Current ferronock world-X position [m].
    virtual float ferronock_x() const = 0;
    /// Current bolt velocity [m/s].
    virtual float bolt_vx() const = 0;

    // ── Fault / log ───────────────────────────────────────────────────────────
    /// Non-fatal log (serial / Godot print).
    virtual void log(const char* msg) = 0;
    /// Per-stage fault (logged + drives fault LED / Godot signal).
    virtual void fault(int stage, const char* reason) = 0;
    /// System-level master kill: disables all gate drivers simultaneously
    /// (e.g. pull a single GPIO low to cut power to every driver IC).
    /// Default loops cap_safe() over all stages; override for a true HW interlock.
    virtual void system_kill(int stage_count) {
        for (int i = 0; i < stage_count; ++i) cap_safe(i);
    }

    // ── Callbacks INTO Godot / application layer ──────────────────────────────
    virtual void on_stage_charging(int stage)                {}
    virtual void on_stage_armed(int stage)                   {}
    virtual void on_stage_fired(int stage)                   {}
    virtual void on_stage_drained(int stage)                 {}
    virtual void on_stage_safe(int stage)                    {}
    virtual void on_mcu_ready()                              {}
    virtual void on_fault(int stage, const char* reason)     {}
    virtual void on_system_fault(const char* reason)         {}
    virtual void on_muzzle_velocity(float v_ms)              {}
};

} // namespace mcu
