/**
 * mcu_node.cpp — GDExtension McuNode implementation.
 */

#include "mcu_node.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// ── Constructor / destructor ──────────────────────────────────────────────────

McuNode::McuNode() {
    // Set firmware defaults matching mcu.gd @export defaults.
    _cfg.stage_count        = 20;
    _cfg.firing_timeout_s   = 2.0f;
    _cfg.target_velocity_ms = 50.0f;
    _cfg.bolt_mass_kg       = 0.030f;
    _cfg.stage_efficiency   = 0.04f;
    _cfg.min_stage_voltage  = 50.0f;
    _cfg.group_size         = 10;
}

McuNode::~McuNode() {
    delete _fw;
    delete _hal;
}

// ── _ready ────────────────────────────────────────────────────────────────────

void McuNode::_ready() {
    if (Engine::get_singleton()->is_editor_hint()) return;

    _discover_stage_nodes();
    _build_firmware();
    _bind_hal_callbacks();
    _fw->begin();

    UtilityFunctions::print(
        String("McuNode ready  stage_count=") + String::num(_cfg.stage_count));
}

void McuNode::_discover_stage_nodes() {
    for (int i = 0; i < _cfg.stage_count; ++i) {
        Node* pp  = get_node_or_null(
            NodePath("../Segment" + String::num(i) + "/PowerPack"));
        Node* sol = get_node_or_null(
            NodePath("../Segment" + String::num(i) + "/Solenoid"));
        _pp[i]  = pp;
        _sol[i] = sol;
    }
}

void McuNode::_build_firmware() {
    delete _fw;
    delete _hal;

    _hal = new mcu::GodotHal(this);
    for (int i = 0; i < _cfg.stage_count; ++i) {
        _hal->bind_stage(i, _pp[i], _sol[i]);
    }
    _fw = new mcu::McuFirmware(_hal, _cfg);
}

void McuNode::_bind_hal_callbacks() {
    // Wire HAL callbacks to Godot signal emissions.
    _hal->cb_charging = [this](int s) { emit_signal("mcu_stage_charging", s); };
    _hal->cb_armed    = [this](int s) { emit_signal("mcu_stage_armed",    s); };
    _hal->cb_fired    = [this](int s) { emit_signal("mcu_stage_fired",    s); };
    _hal->cb_drained  = [this](int s) { emit_signal("mcu_stage_drained",  s); };
    _hal->cb_safe     = [this](int s) { emit_signal("mcu_stage_safe",     s); };
    _hal->cb_ready    = [this]()      { emit_signal("mcu_ready");              };
    _hal->cb_fault    = [this](int s, String r) {
        emit_signal("mcu_fault", s, r);
    };
    _hal->cb_muzzle   = [this](float v) {
        // Show muzzle velocity on HUD (same as mcu.gd _on_muzzle_exit)
        Node* hud = get_node_or_null(NodePath("../HUD"));
        if (hud && hud->has_method("show_muzzle_velocity")) {
            hud->call("show_muzzle_velocity", v);
        }
    };
}

// ── _physics_process ──────────────────────────────────────────────────────────

void McuNode::_physics_process(double delta) {
    if (!_fw) return;
    _hal->advance_time(static_cast<float>(delta));
    _fw->tick(static_cast<float>(delta));
}

// ── Public API ────────────────────────────────────────────────────────────────

void McuNode::arm_request() {
    if (_fw) {
        // Recompute voltage profile with current config before arming
        _fw->set_config(_cfg);
        _fw->arm_request();
    }
}

void McuNode::fire_request() {
    if (_fw) {
        // SimCtrl reset_bolt is called by firmware via HAL —
        // but SimCtrl expects to be called from GDScript.  Call it directly.
        Node* sc = get_node_or_null(NodePath("../SimCtrl"));
        if (sc && sc->has_method("reset_bolt")) sc->call("reset_bolt");
        _fw->fire_request();
    }
}

void McuNode::fire_stage(int i) {
    if (_fw) _fw->fire_stage(i);
}

void McuNode::drain_stage(int i) {
    if (_fw) _fw->drain_stage(i);
}

void McuNode::reset_fault(int i) {
    if (_fw) _fw->reset_fault(i);
}

void McuNode::update_bolt_state(float fx, float vx) {
    if (!_fw) return;
    _hal->set_bolt_state(fx, vx);
    // tick() handles cascade; no extra call needed here.
    // (SimCtrl calls this, then _physics_process also calls tick —
    //  ordering is fine because set_bolt_state just caches the values.)
}

void McuNode::update_ferronock_pos(float fx) {
    update_bolt_state(fx, 0.0f);
}

int McuNode::get_firing_stage() const {
    return _fw ? _fw->firing_stage() : -1;
}

String McuNode::get_stage_state_name(int i) const {
    if (!_fw) return "INVALID";
    return String(_fw->stage_state_name(i));
}

float McuNode::get_v_profile(int i) const {
    return _fw ? _fw->v_profile(i) : _cfg.target_velocity_ms;
}

void McuNode::set_stage_count(int v) {
    _cfg.stage_count = v;
    // Firmware will be rebuilt on next _ready() call.
}

// ── _bind_methods ─────────────────────────────────────────────────────────────

void McuNode::_bind_methods() {
    // Signals — must match mcu.gd signal names exactly
    ADD_SIGNAL(MethodInfo("mcu_stage_charging",
        PropertyInfo(Variant::INT, "stage")));
    ADD_SIGNAL(MethodInfo("mcu_stage_armed",
        PropertyInfo(Variant::INT, "stage")));
    ADD_SIGNAL(MethodInfo("mcu_stage_fired",
        PropertyInfo(Variant::INT, "stage")));
    ADD_SIGNAL(MethodInfo("mcu_stage_drained",
        PropertyInfo(Variant::INT, "stage")));
    ADD_SIGNAL(MethodInfo("mcu_stage_safe",
        PropertyInfo(Variant::INT, "stage")));
    ADD_SIGNAL(MethodInfo("mcu_ready"));
    ADD_SIGNAL(MethodInfo("mcu_fault",
        PropertyInfo(Variant::INT,    "stage"),
        PropertyInfo(Variant::STRING, "reason")));

    // Methods
    ClassDB::bind_method(D_METHOD("arm_request"),           &McuNode::arm_request);
    ClassDB::bind_method(D_METHOD("fire_request"),          &McuNode::fire_request);
    ClassDB::bind_method(D_METHOD("fire_stage",   "i"),     &McuNode::fire_stage);
    ClassDB::bind_method(D_METHOD("drain_stage",  "i"),     &McuNode::drain_stage);
    ClassDB::bind_method(D_METHOD("reset_fault",  "i"),     &McuNode::reset_fault);
    ClassDB::bind_method(D_METHOD("update_bolt_state", "fx", "vx"),
                         &McuNode::update_bolt_state);
    ClassDB::bind_method(D_METHOD("update_ferronock_pos", "fx"),
                         &McuNode::update_ferronock_pos);
    ClassDB::bind_method(D_METHOD("get_firing_stage"),      &McuNode::get_firing_stage);
    ClassDB::bind_method(D_METHOD("get_stage_state_name","i"),
                         &McuNode::get_stage_state_name);
    ClassDB::bind_method(D_METHOD("get_v_profile", "i"),    &McuNode::get_v_profile);

    // Exports
    ClassDB::bind_method(D_METHOD("set_stage_count",          "v"), &McuNode::set_stage_count);
    ClassDB::bind_method(D_METHOD("get_stage_count"),                &McuNode::get_stage_count);
    ClassDB::bind_method(D_METHOD("set_target_velocity_ms",   "v"), &McuNode::set_target_velocity_ms);
    ClassDB::bind_method(D_METHOD("get_target_velocity_ms"),         &McuNode::get_target_velocity_ms);
    ClassDB::bind_method(D_METHOD("set_bolt_mass_kg",         "v"), &McuNode::set_bolt_mass_kg);
    ClassDB::bind_method(D_METHOD("get_bolt_mass_kg"),               &McuNode::get_bolt_mass_kg);
    ClassDB::bind_method(D_METHOD("set_stage_efficiency",     "v"), &McuNode::set_stage_efficiency);
    ClassDB::bind_method(D_METHOD("get_stage_efficiency"),           &McuNode::get_stage_efficiency);
    ClassDB::bind_method(D_METHOD("set_min_stage_voltage_v",  "v"), &McuNode::set_min_stage_voltage_v);
    ClassDB::bind_method(D_METHOD("get_min_stage_voltage_v"),        &McuNode::get_min_stage_voltage_v);
    ClassDB::bind_method(D_METHOD("set_group_size",           "v"), &McuNode::set_group_size);
    ClassDB::bind_method(D_METHOD("get_group_size"),                 &McuNode::get_group_size);
    ClassDB::bind_method(D_METHOD("set_firing_timeout_s",     "v"), &McuNode::set_firing_timeout_s);
    ClassDB::bind_method(D_METHOD("get_firing_timeout_s"),           &McuNode::get_firing_timeout_s);

    ADD_PROPERTY(PropertyInfo(Variant::INT,   "stage_count"),
                 "set_stage_count", "get_stage_count");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "target_velocity_ms"),
                 "set_target_velocity_ms", "get_target_velocity_ms");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bolt_mass_kg"),
                 "set_bolt_mass_kg", "get_bolt_mass_kg");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stage_efficiency"),
                 "set_stage_efficiency", "get_stage_efficiency");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_stage_voltage_v"),
                 "set_min_stage_voltage_v", "get_min_stage_voltage_v");
    ADD_PROPERTY(PropertyInfo(Variant::INT,   "group_size"),
                 "set_group_size", "get_group_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "firing_timeout_s"),
                 "set_firing_timeout_s", "get_firing_timeout_s");
}
