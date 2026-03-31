#pragma once
/**
 * mcu_fw.h — EM-crossbow N-stage coilgun sequencer firmware.
 *
 * This is the same logic that will be flashed to the physical MCU.
 * All hardware I/O goes through IHal; no platform-specific code here.
 *
 * Stage firing is POSITION-BASED:
 *   tick() is called every control loop cycle (≥ 1 kHz on hardware,
 *   every physics frame in Godot).  The firmware reads ferronock_x()
 *   from the HAL and fires stage i when the ferronock enters its
 *   capture zone (1 coil_half before centre).
 *
 * Velocity profile:
 *   arm_request() pre-computes per-stage capacitor voltages so each
 *   stage delivers an equal ΔKE, producing a linear velocity ramp
 *   from 0 → target_velocity_ms.
 */

#include "hal.h"
#include <cmath>
#include <cstring>

namespace mcu {

// ── Configuration (mirrors MCU export vars in mcu.gd) ────────────────────────
struct Config {
    int   stage_count        = 20;
    float firing_timeout_s   = 2.0f;
    float target_velocity_ms = 50.0f;
    float bolt_mass_kg       = 0.030f;
    float stage_efficiency   = 0.04f;   ///< cap energy → KE conversion factor
    float min_stage_voltage  = 50.0f;   ///< floor voltage per stage [V]
    int   group_size         = 10;      ///< stages per charge group

    /// Solenoid geometry per stage (all stages identical for now).
    float coil_half_m        = 0.15f;   ///< half coil length [m]
    /// World-X of stage i centre = stage0_cx + i * stage_pitch_m
    float stage0_cx          = 0.50f;
    float stage_pitch_m      = 0.40f;

    /// System-level fault thresholds (0 = disabled).
    float max_voltage_v      = 400.0f;  ///< overvoltage kill threshold [V]
    float max_current_a      = 200.0f;  ///< overcurrent kill threshold [A]
    float max_temp_c         = 120.0f;  ///< overtemperature kill threshold [°C]
    float safe_drain_v       = 5.0f;    ///< voltage below which a cap is "safe" [V]
};

// ── System-level state machine ────────────────────────────────────────────────
enum class SystemState : uint8_t {
    IDLE,    ///< Not armed; no shot in progress.
    ACTIVE,  ///< Armed or shooting; normal operation.
    FAULT,   ///< System fault: safedown in progress or complete.
};

// ── Stage state machine ───────────────────────────────────────────────────────
enum class StageState : uint8_t {
    SAFE,
    CHARGING,
    ARMED,
    FIRING,
    DRAINING,
    FAULT,
};

static const char* state_name(StageState s) {
    switch (s) {
        case StageState::SAFE:     return "SAFE";
        case StageState::CHARGING: return "CHARGING";
        case StageState::ARMED:    return "ARMED";
        case StageState::FIRING:   return "FIRING";
        case StageState::DRAINING: return "DRAINING";
        case StageState::FAULT:    return "FAULT";
        default:                   return "INVALID";
    }
}

// ── Firmware class ────────────────────────────────────────────────────────────
class McuFirmware {
public:
    explicit McuFirmware(IHal* hal, Config cfg = {})
        : _hal(hal), _cfg(cfg)
    {
        reset_arrays();
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// Call once at startup (after HAL is ready).
    void begin();

    /// Call every control loop tick (physics frame in simulation).
    /// delta_s: time since last call [seconds].
    void tick(float delta_s);

    // ── User interface ────────────────────────────────────────────────────────

    /// Compute voltage profile and start charging all stages.
    void arm_request();

    /// Fire stage 0 and begin position-cascade (must be ARMED).
    void fire_request();

    /// Direct stage control (also used internally by cascade).
    void arm_stage(int i);
    void fire_stage(int i);
    void drain_stage(int i);
    void reset_fault(int i);

    // ── Queries ───────────────────────────────────────────────────────────────

    StageState stage_state(int i) const {
        return (i >= 0 && i < _cfg.stage_count) ? _state[i] : StageState::FAULT;
    }
    const char* stage_state_name(int i) const {
        return state_name(stage_state(i));
    }

    /// Highest-indexed FIRING stage, or -1.
    int  firing_stage() const;

    /// Pre-computed target velocity after stage i.
    float v_profile(int i) const {
        return (i >= 0 && i < MAX_STAGES) ? _v_profile[i] : _cfg.target_velocity_ms;
    }

    float target_voltage(int i) const {
        return (i >= 0 && i < MAX_STAGES) ? _stage_target_v[i] : _cfg.min_stage_voltage;
    }

    int   stage_count() const { return _cfg.stage_count; }
    bool  shot_active() const { return _shot_active; }

    // ── System fault queries / control ───────────────────────────────────────

    /// True while the system is in FAULT state (safedown active or complete).
    bool system_fault_active() const { return _system_state == SystemState::FAULT; }

    /// Human-readable reason for the current system fault (empty string if none).
    const char* system_fault_reason() const { return _system_fault_reason; }

    /// Clear a FAULT and return to IDLE (only valid once all caps are drained).
    void clear_system_fault();

    // ── Config mutation (before arm_request) ─────────────────────────────────
    void set_config(const Config& c) { _cfg = c; reset_arrays(); }
    const Config& config() const     { return _cfg; }

private:
    IHal*  _hal;
    Config _cfg;

    StageState _state[MAX_STAGES]       = {};
    float      _fire_timer[MAX_STAGES]  = {};
    bool       _fired[MAX_STAGES]       = {};   ///< fired this shot?

    float      _stage_target_v[MAX_STAGES] = {};
    float      _v_profile[MAX_STAGES]      = {};

    float _sim_time     = 0.0f;
    float _current_vx   = 0.0f;
    bool  _shot_active  = false;
    bool  _group0_ready = false;

    float _t_muzzle0    = 0.0f;

    // ── System fault state ────────────────────────────────────────────────────
    SystemState _system_state        = SystemState::IDLE;
    char        _system_fault_reason[128] = {};
    bool        _safedown_complete   = false;

    void reset_arrays();

    // ── Internal helpers ──────────────────────────────────────────────────────
    void _charge_stage(int i);
    void _on_stage_charged(int i);
    void _update_position_cascade(float fx);
    void _compute_stage_voltages(int from_stage, float from_vx);
    void _set_state(int i, StageState s);
    void _trigger_fault(int i, const char* reason);

    // ── System fault helpers ──────────────────────────────────────────────────
    /// Check all sensors; call _trigger_system_fault() on any threshold breach.
    void _check_sensors();
    /// Initiate immediate system-wide safedown.
    void _trigger_system_fault(const char* reason);
    /// Open all switches and route charged caps to bleed resistors.
    void _safedown_all();
    /// Poll drain progress each tick; log "SYSTEM SAFE" when complete.
    void _monitor_safedown();

    float _stage_cx(int i) const {
        return _cfg.stage0_cx + i * _cfg.stage_pitch_m;
    }
};

} // namespace mcu
