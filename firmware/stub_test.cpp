/**
 * stub_test.cpp — Unit test for McuFirmware using StubHal.
 *
 * Build:
 *   g++ -std=c++17 -I.. stub_test.cpp mcu_fw.cpp -o stub_test && ./stub_test
 *
 * Tests:
 *   1. arm_request() → all stages reach ARMED.
 *   2. fire_request() → stage 0 fires; cascade fires subsequent stages
 *      as the simulated bolt advances past each capture zone.
 *   3. De-energise (via tick() timeout) returns stages to SAFE.
 *   4. Fault injection → FAULT state, mcu_fault callback.
 */

#include "stub_hal.h"
#include "mcu_fw.h"
#include <cassert>
#include <cstdio>
#include <cstring>

using namespace mcu;

// ── helpers ───────────────────────────────────────────────────────────────────
static int g_ready_count = 0;
static int g_fired_stages[MAX_STAGES] = {};
static int g_fired_count = 0;
static int g_fault_stage = -1;

static void cb_ready()                  { ++g_ready_count; }
static void cb_fired(int s)             { g_fired_stages[g_fired_count++] = s; }
static void cb_fault(int s, const char*){ g_fault_stage = s; }

static void reset_counters() {
    g_ready_count = 0;
    g_fired_count = 0;
    g_fault_stage = -1;
    std::memset(g_fired_stages, 0, sizeof(g_fired_stages));
}

// ── Test 1 — ARM ──────────────────────────────────────────────────────────────
static void test_arm() {
    std::puts("\n=== TEST 1: arm_request ===");
    reset_counters();

    Config cfg;
    cfg.stage_count = 4;
    cfg.group_size  = 4;

    StubHal hal;
    hal.on_ready_cb = cb_ready;
    hal.on_fired_cb = cb_fired;

    McuFirmware fw(&hal, cfg);
    fw.begin();

    fw.arm_request();

    // Immediately mark all banks as charged
    hal.instant_charge_all(cfg.stage_count);

    // One tick to let firmware detect charge completion
    fw.tick(0.001f);

    for (int i = 0; i < cfg.stage_count; ++i) {
        assert(fw.stage_state(i) == StageState::ARMED
            && "All stages should be ARMED");
    }
    assert(g_ready_count == 1 && "mcu_ready should fire once");
    std::puts("  PASS: all stages ARMED, mcu_ready emitted");
}

// ── Test 2 — FIRE cascade ─────────────────────────────────────────────────────
static void test_fire_cascade() {
    std::puts("\n=== TEST 2: fire cascade ===");
    reset_counters();

    Config cfg;
    cfg.stage_count  = 4;
    cfg.group_size   = 4;
    cfg.stage0_cx    = 0.50f;
    cfg.stage_pitch_m = 0.40f;
    cfg.coil_half_m  = 0.15f;
    cfg.firing_timeout_s = 5.0f;

    StubHal hal;
    hal.on_ready_cb = cb_ready;
    hal.on_fired_cb = cb_fired;
    hal.bolt_x = -0.5f;   // start well before barrel
    hal.bolt_v = 10.0f;

    McuFirmware fw(&hal, cfg);
    fw.begin();

    fw.arm_request();
    hal.instant_charge_all(cfg.stage_count);
    fw.tick(0.001f);   // detect charge complete

    assert(fw.stage_state(0) == StageState::ARMED);

    fw.fire_request();
    assert(fw.stage_state(0) == StageState::FIRING);
    assert(g_fired_count == 1 && g_fired_stages[0] == 0);

    // Advance bolt through each stage's capture zone
    const float dt = 0.001f;
    for (int step = 0; step < 5000; ++step) {
        hal.sim_time += dt;
        hal.bolt_x   += hal.bolt_v * dt;

        // Drain stages when their cap would naturally discharge
        for (int i = 0; i < cfg.stage_count; ++i) {
            if (hal.banks[i].firing && hal.bolt_x >
                    cfg.stage0_cx + i * cfg.stage_pitch_m + cfg.coil_half_m) {
                hal.instant_drain(i);
            }
        }
        fw.tick(dt);
    }

    // All 4 stages should have fired
    assert(g_fired_count == cfg.stage_count);
    std::printf("  Fired stages: ");
    for (int i = 0; i < g_fired_count; ++i)
        std::printf("%d ", g_fired_stages[i]);
    std::printf("\n  PASS: all %d stages fired in order\n", cfg.stage_count);
}

// ── Test 3 — Fault injection ──────────────────────────────────────────────────
static void test_fault() {
    std::puts("\n=== TEST 3: fault injection ===");
    reset_counters();

    Config cfg;
    cfg.stage_count      = 2;
    cfg.group_size       = 2;
    cfg.firing_timeout_s = 0.1f;   // very short timeout to trigger fault

    StubHal hal;
    hal.on_fault_cb = cb_fault;
    hal.bolt_x = -1.0f;
    hal.bolt_v = 0.0f;   // bolt doesn't move → stage will time out

    McuFirmware fw(&hal, cfg);
    fw.begin();

    fw.arm_request();
    hal.instant_charge_all(cfg.stage_count);
    fw.tick(0.001f);

    fw.fire_request();
    assert(fw.stage_state(0) == StageState::FIRING);

    // Tick past firing timeout without draining
    for (int i = 0; i < 200; ++i) fw.tick(0.001f);

    assert(fw.stage_state(0) == StageState::FAULT);
    assert(g_fault_stage == 0 && "fault callback should report stage 0");
    std::puts("  PASS: firing timeout triggers FAULT");
}

// ── Test 4 — System fault (overvoltage) ───────────────────────────────────────
static bool g_system_fault_called = false;
static char g_system_fault_reason[128] = {};

static void cb_system_fault(const char* r) {
    g_system_fault_called = true;
    std::strncpy(g_system_fault_reason, r, sizeof(g_system_fault_reason) - 1);
}

static void test_system_fault() {
    std::puts("\n=== TEST 4: system fault (overvoltage) ===");
    g_system_fault_called = false;
    std::memset(g_system_fault_reason, 0, sizeof(g_system_fault_reason));

    Config cfg;
    cfg.stage_count      = 4;
    cfg.group_size       = 4;
    cfg.max_voltage_v    = 300.0f;  // 300 V limit
    cfg.safe_drain_v     = 5.0f;

    StubHal hal;
    hal.on_system_fault_cb = cb_system_fault;

    McuFirmware fw(&hal, cfg);
    fw.begin();

    fw.arm_request();
    hal.instant_charge_all(cfg.stage_count);
    fw.tick(0.001f);  // detect charge complete → stages ARMED

    assert(!fw.system_fault_active() && "no fault yet");

    // Inject overvoltage on stage 2
    hal.banks[2].voltage = 350.0f;  // above max_voltage_v = 300 V

    fw.tick(0.001f);  // _check_sensors() should trigger system fault

    assert(fw.system_fault_active() && "system fault should be active");
    assert(g_system_fault_called    && "on_system_fault callback should fire");
    assert(hal.system_kill_count >= 1 && "system_kill() should have been called");
    std::printf("  Fault reason: %s\n", fw.system_fault_reason());

    // All stages should be DRAINING (they had voltage) or FAULT (already drained)
    for (int i = 0; i < cfg.stage_count; ++i) {
        StageState s = fw.stage_state(i);
        assert((s == StageState::DRAINING || s == StageState::FAULT)
            && "all stages must be DRAINING or FAULT after system fault");
    }

    // Simulate caps draining to zero (below safe_drain_v)
    for (int i = 0; i < cfg.stage_count; ++i) {
        hal.banks[i].voltage  = 0.0f;
        hal.banks[i].draining = false;
    }

    // Tick until safedown complete
    for (int t = 0; t < 10; ++t) fw.tick(0.001f);

    // Now clear the fault
    fw.clear_system_fault();
    assert(!fw.system_fault_active() && "fault should be cleared");
    for (int i = 0; i < cfg.stage_count; ++i) {
        assert(fw.stage_state(i) == StageState::SAFE && "stages must return to SAFE");
    }

    std::puts("  PASS: overvoltage triggers system fault, safedown, and clear");
}

// ── main ──────────────────────────────────────────────────────────────────────
int main() {
    std::puts("McuFirmware unit tests");
    test_arm();
    test_fire_cascade();
    test_fault();
    test_system_fault();
    std::puts("\n=== ALL TESTS PASSED ===");
    return 0;
}
