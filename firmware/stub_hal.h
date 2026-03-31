#pragma once
/**
 * stub_hal.h — Minimal HAL for unit-testing McuFirmware without Godot.
 *
 * Simulates N capacitor banks with instant-charge behaviour and
 * a bolt that moves at constant velocity, just enough to exercise
 * the state machine and position cascade.
 *
 * Build & run (any C++17 compiler):
 *   g++ -std=c++17 -I.. stub_test.cpp ../mcu_fw.cpp -o stub_test && ./stub_test
 */

#include "hal.h"
#include <cstdio>
#include <cstring>

namespace mcu {

class StubHal : public IHal {
public:
    // Simulation state accessible to test code
    struct CapBank {
        float   voltage     = 0.0f;
        float   target_v    = 0.0f;
        bool    charging    = false;
        bool    firing      = false;
        bool    draining    = false;
    };

    CapBank banks[MAX_STAGES] = {};
    float   sim_time          = 0.0f;
    float   bolt_x            = 0.0f;  ///< ferronock position
    float   bolt_v            = 0.0f;  ///< bolt velocity

    /// Callbacks (set by test to observe transitions)
    void (*on_ready_cb)()                          = nullptr;
    void (*on_fired_cb)(int)                       = nullptr;
    void (*on_fault_cb)(int, const char*)          = nullptr;
    void (*on_system_fault_cb)(const char*)        = nullptr;

    /// How many times system_kill() has been called this test run.
    int system_kill_count = 0;

    // ── IHal ─────────────────────────────────────────────────────────────────
    float time_s() const override { return sim_time; }

    void cap_begin_charge(int i, float tv) override {
        if (i < 0 || i >= MAX_STAGES) return;
        banks[i].charging  = true;
        banks[i].firing    = false;
        banks[i].draining  = false;
        banks[i].voltage   = 0.0f;
        banks[i].target_v  = tv;
    }
    void cap_fire(int i) override {
        if (i < 0 || i >= MAX_STAGES) return;
        banks[i].firing    = true;
        banks[i].charging  = false;
        banks[i].draining  = false;
    }
    void cap_drain(int i) override {
        if (i < 0 || i >= MAX_STAGES) return;
        banks[i].draining  = true;
        banks[i].firing    = false;
        banks[i].charging  = false;
    }
    void cap_safe(int i) override {
        if (i < 0 || i >= MAX_STAGES) return;
        banks[i] = CapBank{};
    }

    float sense_voltage(int i) const override {
        return (i >= 0 && i < MAX_STAGES) ? banks[i].voltage : 0.0f;
    }
    float sense_current(int i) const override { (void)i; return 0.0f; }
    float sense_temp(int i)    const override { (void)i; return 20.0f; }
    bool  is_charging(int i)   const override {
        return (i >= 0 && i < MAX_STAGES) && banks[i].charging;
    }
    bool  is_firing(int i)     const override {
        return (i >= 0 && i < MAX_STAGES) && banks[i].firing;
    }
    bool  is_draining(int i)   const override {
        return (i >= 0 && i < MAX_STAGES) && banks[i].draining;
    }

    float ferronock_x() const override { return bolt_x; }
    float bolt_vx()     const override { return bolt_v; }

    void log(const char* msg) override { std::puts(msg); }
    void fault(int, const char*) override {}

    // Callbacks
    void on_mcu_ready()            override { if (on_ready_cb) on_ready_cb(); }
    void on_stage_fired(int s)     override { if (on_fired_cb) on_fired_cb(s); }
    void on_fault(int s, const char* r) override {
        if (on_fault_cb) on_fault_cb(s, r);
    }
    void on_system_fault(const char* r) override {
        if (on_system_fault_cb) on_system_fault_cb(r);
    }

    /// Override to count system_kill calls (and still open all gates).
    void system_kill(int stage_count) override {
        ++system_kill_count;
        for (int i = 0; i < stage_count; ++i) cap_safe(i);
    }

    // ── Test helpers ──────────────────────────────────────────────────────────

    /// Instantly charge all banks to their target voltages and mark them ARMED.
    void instant_charge_all(int n_stages) {
        for (int i = 0; i < n_stages; ++i) {
            if (banks[i].charging) {
                banks[i].voltage  = banks[i].target_v;
                banks[i].charging = false;
            }
        }
    }

    /// Instantly drain a firing stage (simulate coil pulse completing).
    void instant_drain(int i) {
        if (i < 0 || i >= MAX_STAGES) return;
        banks[i].firing  = false;
        banks[i].voltage = 0.0f;
    }
};

} // namespace mcu
