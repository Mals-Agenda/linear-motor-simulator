#pragma once
/**
 * mcu_node.h — GDExtension Node that wraps McuFirmware.
 *
 * Drop-in replacement for scripts/mcu.gd:
 *   • Exposes exactly the same signals and methods as mcu.gd.
 *   • Owns a McuFirmware instance and a GodotHal.
 *   • SimCtrl continues calling update_bolt_state() / update_ferronock_pos()
 *     exactly as before.
 *
 * Scene binding:
 *   Attach this script to the MCU node in Coilgun20.tscn, or set the
 *   class_name in the .gdextension file and use it as the node type.
 */

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

#include "../firmware/mcu_fw.h"
#include "godot_hal.h"

namespace godot {

class McuNode : public Node {
    GDCLASS(McuNode, Node)

public:
    McuNode();
    ~McuNode() override;

    // ── Godot lifecycle ───────────────────────────────────────────────────────
    void _ready()  override;
    void _physics_process(double delta) override;

    // ── Exports (mirror mcu.gd @export vars) ──────────────────────────────────
    void  set_stage_count(int v);
    int   get_stage_count()       const { return _cfg.stage_count; }

    void  set_target_velocity_ms(float v) { _cfg.target_velocity_ms = v; }
    float get_target_velocity_ms()  const { return _cfg.target_velocity_ms; }

    void  set_bolt_mass_kg(float v)  { _cfg.bolt_mass_kg = v; }
    float get_bolt_mass_kg()  const  { return _cfg.bolt_mass_kg; }

    void  set_stage_efficiency(float v) { _cfg.stage_efficiency = v; }
    float get_stage_efficiency()  const { return _cfg.stage_efficiency; }

    void  set_min_stage_voltage_v(float v) { _cfg.min_stage_voltage = v; }
    float get_min_stage_voltage_v()  const { return _cfg.min_stage_voltage; }

    void  set_group_size(int v)  { _cfg.group_size = v; }
    int   get_group_size() const { return _cfg.group_size; }

    void  set_firing_timeout_s(float v) { _cfg.firing_timeout_s = v; }
    float get_firing_timeout_s() const  { return _cfg.firing_timeout_s; }

    // ── Public methods (same API as mcu.gd) ───────────────────────────────────
    void arm_request();
    void fire_request();
    void fire_stage(int i);
    void drain_stage(int i);
    void reset_fault(int i);

    /// Called by SimCtrl every physics frame.
    void update_bolt_state(float fx, float vx);
    void update_ferronock_pos(float fx);   // legacy compat

    /// Query used by SimCtrl / HUD.
    int    get_firing_stage() const;
    String get_stage_state_name(int i) const;
    float  get_v_profile(int i) const;

    // ── Signals ───────────────────────────────────────────────────────────────
    // Declared in _bind_methods(); names must match mcu.gd exactly so
    // ShotRecorder / HUD connect() calls still work.

protected:
    static void _bind_methods();

private:
    mcu::Config       _cfg;
    mcu::GodotHal*    _hal = nullptr;
    mcu::McuFirmware* _fw  = nullptr;

    void _build_firmware();
    void _bind_hal_callbacks();
    void _discover_stage_nodes();

    // node references populated in _ready
    Object* _pp[mcu::MAX_STAGES]  = {};
    Object* _sol[mcu::MAX_STAGES] = {};
};

} // namespace godot
