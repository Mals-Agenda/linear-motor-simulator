#pragma once
/**
 * godot_hal.h — Godot simulation HAL for McuFirmware.
 *
 * Bridges the firmware HAL interface to the GDScript PowerPack /
 * Solenoid nodes that already exist in the scene.
 *
 * Usage (inside McuNode::_ready):
 *   _hal = new GodotHal(this);           // pass the Node* owner
 *   _hal->set_stage_count(stage_count);
 *   for (int i = 0; i < n; ++i) {
 *       _hal->bind_stage(i, _pp[i], _sol[i]);
 *   }
 *   _fw = new McuFirmware(_hal, cfg);
 *   _fw->begin();
 */

#include "../firmware/hal.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>

namespace mcu {

class GodotHal : public IHal {
public:
    explicit GodotHal(godot::Node* owner) : _owner(owner) {}

    void bind_stage(int i, godot::Object* pp, godot::Object* sol) {
        if (i < 0 || i >= MAX_STAGES) return;
        _pp[i]  = pp;
        _sol[i] = sol;
    }

    // Callback pointers — set by McuNode so signals can be emitted.
    std::function<void(int)>        cb_charging;
    std::function<void(int)>        cb_armed;
    std::function<void(int)>        cb_fired;
    std::function<void(int)>        cb_drained;
    std::function<void(int)>        cb_safe;
    std::function<void()>           cb_ready;
    std::function<void(int,godot::String)> cb_fault;
    std::function<void(float)>      cb_muzzle;

    // ── IHal overrides ────────────────────────────────────────────────────────
    float time_s() const override {
        // _sim_time is accumulated externally (by McuNode ticking McuFirmware)
        return _time;
    }
    void advance_time(float dt) { _time += dt; }

    // Cap control — delegates to PowerPack GDScript methods
    void cap_begin_charge(int i, float target_v) override {
        auto* pp = _pp[i];
        if (!pp) return;
        // Set the target voltage on the PowerPack before beginning charge
        pp->set("target_voltage_v", target_v);
        pp->call("begin_charge");
    }
    void cap_fire(int i) override {
        if (_pp[i]) _pp[i]->call("fire");
    }
    void cap_drain(int i) override {
        if (_pp[i]) _pp[i]->call("drain");
    }
    void cap_safe(int i) override {
        if (_pp[i]) _pp[i]->call("safe");
    }

    // Sensors
    float sense_voltage(int i) const override {
        if (!_pp[i]) return 0.0f;
        return static_cast<float>(
            static_cast<double>(_pp[i]->call("get_voltage")));
    }
    float sense_current(int i) const override {
        if (!_pp[i]) return 0.0f;
        return static_cast<float>(
            static_cast<double>(_pp[i]->call("get_rms_current")));
    }
    float sense_temp(int i) const override {
        if (!_pp[i]) return 20.0f;
        return static_cast<float>(
            static_cast<double>(_pp[i]->call("get_coil_temp_c")));
    }
    bool is_charging(int i) const override {
        if (!_pp[i]) return false;
        return static_cast<bool>(_pp[i]->call("is_charging"));
    }
    bool is_firing(int i) const override {
        if (!_pp[i]) return false;
        return static_cast<bool>(_pp[i]->call("is_fire_active"));
    }
    bool is_draining(int i) const override {
        if (!_pp[i]) return false;
        return static_cast<bool>(_pp[i]->call("is_drain_active"));
    }

    // Position — set every tick by McuNode from SimCtrl data
    float ferronock_x() const override { return _ferronock_x; }
    float bolt_vx()     const override { return _bolt_vx;     }
    void  set_bolt_state(float fx, float vx) {
        _ferronock_x = fx;
        _bolt_vx     = vx;
    }

    // Logging
    void log(const char* msg) override {
        godot::UtilityFunctions::print(godot::String(msg));
    }
    void fault(int stage, const char* reason) override {
        // Actual fault signal is emitted via on_fault callback
        (void)stage; (void)reason;
    }

    // State-change callbacks → emit Godot signals
    void on_stage_charging(int s)  override { if (cb_charging) cb_charging(s); }
    void on_stage_armed(int s)     override { if (cb_armed)    cb_armed(s);    }
    void on_stage_fired(int s)     override { if (cb_fired)    cb_fired(s);    }
    void on_stage_drained(int s)   override { if (cb_drained)  cb_drained(s);  }
    void on_stage_safe(int s)      override { if (cb_safe)     cb_safe(s);     }
    void on_mcu_ready()            override { if (cb_ready)    cb_ready();     }
    void on_fault(int s, const char* r) override {
        if (cb_fault) cb_fault(s, godot::String(r));
    }
    void on_muzzle_velocity(float v) override {
        if (cb_muzzle) cb_muzzle(v);
    }

private:
    godot::Node*   _owner = nullptr;
    godot::Object* _pp[MAX_STAGES]  = {};
    godot::Object* _sol[MAX_STAGES] = {};
    float _ferronock_x = 0.0f;
    float _bolt_vx     = 0.0f;
    float _time        = 0.0f;
};

} // namespace mcu
