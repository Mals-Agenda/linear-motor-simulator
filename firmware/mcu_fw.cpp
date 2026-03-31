/**
 * mcu_fw.cpp — EM-crossbow MCU firmware implementation.
 *
 * Porting notes for the physical MCU:
 *   • Replace all calls to _hal->sense_*() / _hal->cap_*() with the
 *     appropriate ADC reads / GPIO writes in your Stm32Hal / ArduinoHal.
 *   • tick() maps to your main control-loop ISR or RTOS task.
 *   • No dynamic allocation; all arrays are fixed to MAX_STAGES.
 */

#include "mcu_fw.h"
#include <cstdio>
#include <cstring>
#include <algorithm>

namespace mcu {

// ─────────────────────────────────────────────────────────────────────────────
//  Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

void McuFirmware::begin() {
    reset_arrays();
    char buf[64];
    std::snprintf(buf, sizeof(buf),
        "MCU firmware ready  stage_count=%d", _cfg.stage_count);
    _hal->log(buf);
}

void McuFirmware::tick(float delta_s) {
    _sim_time += delta_s;

    const int n = _cfg.stage_count;

    // ── 0. Sensor checks — highest priority, runs every tick ─────────────────
    _check_sensors();

    // ── If system fault: monitor safedown and return; no normal processing ────
    if (_system_state == SystemState::FAULT) {
        _monitor_safedown();
        return;
    }

    // ── Poll charging completion ──────────────────────────────────────────────
    for (int i = 0; i < n; ++i) {
        if (_state[i] == StageState::CHARGING) {
            if (!_hal->is_charging(i)) {
                _on_stage_charged(i);
            }
        }
    }

    // ── Monitor FIRING / DRAINING stages ─────────────────────────────────────
    for (int i = 0; i < n; ++i) {
        switch (_state[i]) {
            case StageState::FIRING:
                _fire_timer[i] += delta_s;
                if (_fire_timer[i] > _cfg.firing_timeout_s) {
                    char buf[64];
                    std::snprintf(buf, sizeof(buf), "S%d firing timeout", i);
                    _trigger_fault(i, buf);
                } else if (!_hal->is_firing(i)) {
                    _set_state(i, StageState::SAFE);
                }
                break;
            case StageState::DRAINING:
                if (!_hal->is_draining(i)) {
                    _set_state(i, StageState::SAFE);
                }
                break;
            default:
                break;
        }
    }

    // ── Position-cascade trigger ──────────────────────────────────────────────
    if (_shot_active) {
        _current_vx = _hal->bolt_vx();
        _update_position_cascade(_hal->ferronock_x());
    }

    // ── Clear _shot_active once all stages return to SAFE / FAULT ────────────
    if (_shot_active) {
        bool done = true;
        for (int i = 0; i < n; ++i) {
            if (_state[i] != StageState::SAFE &&
                _state[i] != StageState::FAULT) {
                done = false; break;
            }
        }
        if (done) _shot_active = false;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  User interface
// ─────────────────────────────────────────────────────────────────────────────

void McuFirmware::arm_request() {
    _group0_ready = false;
    _compute_stage_voltages(0, 0.0f);
    for (int i = 0; i < _cfg.stage_count; ++i) {
        _charge_stage(i);
    }
}

void McuFirmware::fire_request() {
    if (_state[0] != StageState::ARMED) return;

    _sim_time    = 0.0f;
    _shot_active = true;
    _t_muzzle0   = 0.0f;

    std::memset(_fired, 0, sizeof(_fired));
    _fired[0] = true;   // stage 0 triggered manually right now
    fire_stage(0);
}

void McuFirmware::arm_stage(int i) {
    if (i < 0 || i >= _cfg.stage_count) return;
    if (_state[i] == StageState::SAFE) {
        _set_state(i, StageState::ARMED);
    }
}

void McuFirmware::fire_stage(int i) {
    if (i < 0 || i >= _cfg.stage_count) return;
    if (_state[i] != StageState::ARMED) return;
    _hal->cap_fire(i);
    _fire_timer[i] = 0.0f;
    _set_state(i, StageState::FIRING);
}

void McuFirmware::drain_stage(int i) {
    if (i < 0 || i >= _cfg.stage_count) return;
    _hal->cap_drain(i);
    _set_state(i, StageState::DRAINING);
}

void McuFirmware::reset_fault(int i) {
    if (i < 0 || i >= _cfg.stage_count) return;
    if (_state[i] == StageState::FAULT) {
        _hal->cap_safe(i);
        _set_state(i, StageState::SAFE);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Queries
// ─────────────────────────────────────────────────────────────────────────────

int McuFirmware::firing_stage() const {
    for (int i = _cfg.stage_count - 1; i >= 0; --i) {
        if (_state[i] == StageState::FIRING) return i;
    }
    return -1;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Private helpers
// ─────────────────────────────────────────────────────────────────────────────

void McuFirmware::reset_arrays() {
    std::memset(_state,          0, sizeof(_state));
    std::memset(_fire_timer,     0, sizeof(_fire_timer));
    std::memset(_fired,          0, sizeof(_fired));
    std::memset(_stage_target_v, 0, sizeof(_stage_target_v));
    std::memset(_v_profile,      0, sizeof(_v_profile));
}

// ── Position-cascade (called every tick during active shot) ──────────────────
void McuFirmware::_update_position_cascade(float fx) {
    for (int i = 0; i < _cfg.stage_count; ++i) {
        if (_fired[i])                           continue;
        if (_state[i] != StageState::ARMED)      continue;
        const float cx   = _stage_cx(i);
        const float half = _cfg.coil_half_m;
        if (fx >= cx - half) {
            _fired[i] = true;
            fire_stage(i);
        }
    }
}

// ── Voltage profile ───────────────────────────────────────────────────────────
/**
 * Pre-compute per-stage capacitor voltages so each stage delivers an equal
 * ΔKE, producing a linear velocity ramp from from_vx → target_velocity_ms.
 *
 * For stage i:
 *   KE_in  = ½ m v_in²
 *   KE_out = ½ m v_out²
 *   ΔKE    = ½ m (v_out² - v_in²)
 *   E_cap  = ΔKE / efficiency
 *   V      = √(2 E_cap / C)   where C = capacitance (from HAL)
 */
void McuFirmware::_compute_stage_voltages(int from_stage, float from_vx) {
    const int n   = _cfg.stage_count;
    const int rem = n - from_stage;
    if (rem <= 0) return;

    const float v_rem = std::max(_cfg.target_velocity_ms - from_vx, 0.0f);
    const float dv    = v_rem / static_cast<float>(rem);

    // Assume a fixed capacitance; on real hardware query from HAL per-stage.
    // Use a compile-time default; override by subclassing or config field.
    // Default: 1 mF (matches power_pack.gd default capacitance_f = 0.001).
    const float C_default = 0.001f;

    for (int i = from_stage; i < n; ++i) {
        const int   j     = i - from_stage;
        const float v_in  = from_vx + j * dv;
        const float v_out = from_vx + (j + 1) * dv;
        _v_profile[i]     = v_out;

        const float dke   = 0.5f * _cfg.bolt_mass_kg *
                            (v_out * v_out - v_in * v_in);
        const float e_cap = std::max(dke, 1e-9f) /
                            std::max(_cfg.stage_efficiency, 0.01f);
        const float v_tgt = std::sqrt(2.0f * e_cap / C_default);
        _stage_target_v[i] = std::max(v_tgt, _cfg.min_stage_voltage);
    }

    char buf[128];
    std::snprintf(buf, sizeof(buf),
        "MCU: velocity profile  V[%d]=%.1fV  V[%d]=%.1fV  target=%.0f m/s",
        from_stage,    _stage_target_v[from_stage],
        n - 1,         _stage_target_v[n - 1],
        _cfg.target_velocity_ms);
    _hal->log(buf);
}

// ── Stage charging helpers ────────────────────────────────────────────────────
void McuFirmware::_charge_stage(int i) {
    if (i < 0 || i >= _cfg.stage_count) return;
    if (_state[i] == StageState::CHARGING ||
        _state[i] == StageState::ARMED    ||
        _state[i] == StageState::FIRING)    return;

    const float target = (i < MAX_STAGES) ? _stage_target_v[i]
                                           : _cfg.min_stage_voltage;
    _hal->cap_begin_charge(i, target);
    _set_state(i, StageState::CHARGING);
}

void McuFirmware::_on_stage_charged(int i) {
    _set_state(i, StageState::ARMED);

    if (_group0_ready) return;   // mcu_ready already emitted this arm cycle

    // Emit mcu_ready when all stages in group 0 reach ARMED.
    const int g = std::min(_cfg.group_size, _cfg.stage_count);
    for (int s = 0; s < g; ++s) {
        if (_state[s] != StageState::ARMED) return;
    }
    _group0_ready = true;
    char buf[64];
    std::snprintf(buf, sizeof(buf),
        "MCU: GROUP 0 (%d stages) ARMED — READY TO FIRE", g);
    _hal->log(buf);
    _hal->on_mcu_ready();
}

// ── State transition with HAL callbacks ───────────────────────────────────────
void McuFirmware::_set_state(int i, StageState s) {
    _state[i] = s;
    char buf[64];
    switch (s) {
        case StageState::CHARGING:
            std::snprintf(buf, sizeof(buf), "MCU: S%d CHARGING", i);
            _hal->log(buf);
            _hal->on_stage_charging(i);
            break;
        case StageState::ARMED:
            std::snprintf(buf, sizeof(buf), "MCU: S%d ARMED  V=%.1f",
                i, _hal->sense_voltage(i));
            _hal->log(buf);
            _hal->on_stage_armed(i);
            break;
        case StageState::FIRING:
            std::snprintf(buf, sizeof(buf), "MCU: S%d FIRING  V=%.1f",
                i, _hal->sense_voltage(i));
            _hal->log(buf);
            _hal->on_stage_fired(i);
            break;
        case StageState::DRAINING:
            std::snprintf(buf, sizeof(buf), "MCU: S%d DRAINING", i);
            _hal->log(buf);
            _hal->on_stage_drained(i);
            break;
        case StageState::SAFE:
            std::snprintf(buf, sizeof(buf), "MCU: S%d SAFE", i);
            _hal->log(buf);
            _hal->on_stage_safe(i);
            break;
        case StageState::FAULT:
            break;   // logged by _trigger_fault
    }
}

void McuFirmware::_trigger_fault(int i, const char* reason) {
    char buf[128];
    std::snprintf(buf, sizeof(buf), "MCU: *** FAULT S%d *** %s", i, reason);
    _hal->log(buf);
    _hal->cap_drain(i);
    _state[i] = StageState::FAULT;
    _hal->on_fault(i, reason);
    _hal->fault(i, reason);
}

// ─────────────────────────────────────────────────────────────────────────────
//  System fault FSM
// ─────────────────────────────────────────────────────────────────────────────

void McuFirmware::_check_sensors() {
    if (_system_state == SystemState::FAULT) return;  // already faulted

    const int n = _cfg.stage_count;
    char buf[128];

    for (int i = 0; i < n; ++i) {
        // Skip stages that are fully safe — no energy, no risk.
        if (_state[i] == StageState::SAFE) continue;

        if (_cfg.max_voltage_v > 0.0f) {
            const float v = _hal->sense_voltage(i);
            if (v > _cfg.max_voltage_v) {
                std::snprintf(buf, sizeof(buf),
                    "S%d overvoltage %.1fV > %.1fV", i, v, _cfg.max_voltage_v);
                _trigger_system_fault(buf);
                return;
            }
        }
        if (_cfg.max_current_a > 0.0f) {
            const float a = _hal->sense_current(i);
            if (a > _cfg.max_current_a) {
                std::snprintf(buf, sizeof(buf),
                    "S%d overcurrent %.1fA > %.1fA", i, a, _cfg.max_current_a);
                _trigger_system_fault(buf);
                return;
            }
        }
        if (_cfg.max_temp_c > 0.0f) {
            const float t = _hal->sense_temp(i);
            if (t > _cfg.max_temp_c) {
                std::snprintf(buf, sizeof(buf),
                    "S%d overtemp %.1f°C > %.1f°C", i, t, _cfg.max_temp_c);
                _trigger_system_fault(buf);
                return;
            }
        }
    }
}

void McuFirmware::_trigger_system_fault(const char* reason) {
    std::strncpy(_system_fault_reason, reason, sizeof(_system_fault_reason) - 1);
    _system_fault_reason[sizeof(_system_fault_reason) - 1] = '\0';

    char buf[160];
    std::snprintf(buf, sizeof(buf), "MCU: *** SYSTEM FAULT *** %s", reason);
    _hal->log(buf);

    _system_state    = SystemState::FAULT;
    _safedown_complete = false;
    _shot_active     = false;

    _safedown_all();

    _hal->on_system_fault(reason);
}

void McuFirmware::_safedown_all() {
    const int n = _cfg.stage_count;

    // Step 1: hardware master kill — cuts all gate drivers simultaneously.
    _hal->system_kill(n);

    // Step 2: for each stage with stored energy, open all switches then
    // route to bleed resistor so the cap drains through R_bleed safely.
    for (int i = 0; i < n; ++i) {
        _hal->cap_safe(i);   // open fire switch (redundant after system_kill)

        const float v = _hal->sense_voltage(i);
        if (v > _cfg.safe_drain_v) {
            _hal->cap_drain(i);
            _state[i] = StageState::DRAINING;
        } else {
            _state[i] = StageState::FAULT;
        }
    }

    _hal->log("MCU: SAFEDOWN initiated — all stages draining");
}

void McuFirmware::_monitor_safedown() {
    if (_safedown_complete) return;

    const int n = _cfg.stage_count;
    bool all_safe = true;

    for (int i = 0; i < n; ++i) {
        if (_state[i] == StageState::DRAINING) {
            const float v = _hal->sense_voltage(i);
            if (v <= _cfg.safe_drain_v && !_hal->is_draining(i)) {
                _hal->cap_safe(i);
                _state[i] = StageState::FAULT;  // stay in FAULT until clear_system_fault()
            } else {
                all_safe = false;
            }
        }
    }

    if (all_safe) {
        _safedown_complete = true;
        _hal->log("MCU: *** SYSTEM SAFE — all caps drained ***");
    }
}

void McuFirmware::clear_system_fault() {
    if (_system_state != SystemState::FAULT) return;
    if (!_safedown_complete) {
        _hal->log("MCU: clear_system_fault() refused — safedown not complete");
        return;
    }

    const int n = _cfg.stage_count;
    for (int i = 0; i < n; ++i) {
        _hal->cap_safe(i);
        _state[i] = StageState::SAFE;
    }
    _system_state    = SystemState::IDLE;
    _safedown_complete = false;
    std::memset(_system_fault_reason, 0, sizeof(_system_fault_reason));
    _hal->log("MCU: system fault cleared — ready to arm");
}

} // namespace mcu
