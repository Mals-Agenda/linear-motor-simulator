extends Node

## Physics controller for the N-stage coilgun.
##
## KEY PHYSICS INSIGHT:
##   The solenoid attracts the FERRONOCK (rear of bolt), not the bolt centre.
##   All solenoid force / de-energise / back-EMF calculations use ferronock_x.
##
##   ferronock_x = bolt.global_position.x - ferronock_offset
##
## Each physics frame:
##   1. Computes ferronock_x.
##   2. Passes (ferronock_x, vx) to each PowerPack for back-EMF coupling.
##   3. Calls mcu.update_ferronock_pos() for position-cascade stage firing.
##   4. De-energises each stage when ferronock reaches that solenoid centre.
##   5. Sums solenoid forces (evaluated at ferronock_x) + friction + drag + magnet.
##   6. Applies total force to bolt.constant_force.

@onready var bolt:         RigidBody3D = $"../Bolt"
@onready var breach_door               = $"../BreachDoor"
@onready var mcu:          Node        = $"../MCU"
@onready var _telem_graph: Node        = $"../TelemetryGraph"
@onready var _recorder:    Node        = $"../ShotRecorder"

@export var friction_coeff:      float = 0.05   ## viscous barrel friction [N·s/m]
@export var drag_coeff:          float = 0.001  ## quadratic aero drag [N·s²/m²]
@export var ferronock_offset:    float = 0.37   ## bolt_centre → ferronock [m]
@export var barrel_start_x:      float = 0.00
@export var barrel_end_x:        float = 9.50
@export var de_energise_advance: float = 0.0   ## de-energise this many metres BEFORE solenoid centre [m]

var _pp:          Array = []
var _sol:         Array = []
var _deenergised: Array = []

var _breach_ok:      bool  = false
var _mcu_ok:         bool  = false
var _sim_time:       float = 0.0
var _last_chg_log:   float = -1.0

var _csv_file:       FileAccess = null
var _last_telem_log: float      = -1.0
const TELEM_LOG_HZ:  float      = 60.0   ## rows written per second to CSV

func _ready() -> void:
	## Force 600 Hz physics tick rate — the Godot editor reverts the project.godot
	## setting, so we set it in code to guarantee it sticks.
	Engine.physics_ticks_per_second = 600

	if not bolt:
		push_error("SimCtrl: Bolt node missing"); return

	_breach_ok = breach_door != null and breach_door.has_method("get_magnet_force")
	_mcu_ok    = mcu         != null and mcu.has_method("fire_stage")

	var n: int = mcu.stage_count if (_mcu_ok and "stage_count" in mcu) else 2
	for i in range(n):
		## Nodes live inside BarrelSegment instances: Segment0/Solenoid, etc.
		var pp:  Node = get_node_or_null("../Segment%d/PowerPack" % i)
		var sol: Node = get_node_or_null("../Segment%d/Solenoid"  % i)
		_pp.append(pp)
		_sol.append(sol)
		_deenergised.append(false)

	var cx_str: String = ""
	for i in range(min(_sol.size(), 4)):
		var s: Node = _sol[i]
		cx_str += " cx%d=%.2f" % [i, s.global_position.x if s else 0.0]
	print("SimCtrl ready  stages=%d%s  breach=%s  mcu=%s" \
		% [_pp.size(), cx_str, _breach_ok, _mcu_ok])
	_open_csv()

func _physics_process(delta: float) -> void:
	if not bolt: return
	_sim_time += delta

	var x:  float = bolt.global_position.x
	var vx: float = bolt.linear_velocity.x
	var fx: float = x - ferronock_offset   ## ferronock world-x

	## ── 1. Back-EMF coupling: sync bolt position into every PowerPack ───────────
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if pp:
			pp.set_bolt_state(fx, vx, sol)

	## ── 2. Position-cascade: MCU fires next stage when ferronock arrives ────────
	if _mcu_ok:
		if mcu.has_method("update_bolt_state"):
			mcu.update_bolt_state(fx, vx)
		else:
			mcu.update_ferronock_pos(fx)

	## ── 3. Physics step every PowerPack (after MCU may have set fire switches) ──
	## Driving step() here (instead of PowerPack._physics_process) ensures that
	## newly-fired stages build current in the SAME frame the MCU triggers them,
	## using the up-to-date bolt position from set_bolt_state above.
	for i in range(_pp.size()):
		if _pp[i]:
			_pp[i].step(delta)

	## ── 4. Forces — skip stages where bolt has already passed centre ────────────
	## Computing forces before de-energise preserves current for the final approach
	## tick.  But if the bolt is already past cx, dL/dx < 0 → backward force.
	## De-energise (step 5) will zero it immediately after; skipping here prevents
	## the one-tick backward impulse that subtracts 1-2 m/s per late-firing stage.
	var f_total: float = 0.0
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if not pp or not sol: continue
		if pp.is_fire_active():
			var cx_i: float = sol.center_x if "center_x" in sol else sol.global_position.x
			if fx >= cx_i: continue  ## past centre → backward force; skip, let de-energise fire
		var isq:   float = pp.get_avg_current_sq()
		var f_sol: float = sol.get_force(fx, isq) if sol.has_method("get_force") else 0.0
		f_total += f_sol

	## ── 5. De-energise when ferronock reaches solenoid centre ─────────────────
	for i in range(_pp.size()):
		var pp:  Node = _pp[i]
		var sol: Node = _sol[i]
		if not pp or not sol: continue
		var cx: float = sol.center_x if "center_x" in sol else sol.global_position.x
		if not _deenergised[i] and pp.is_fire_active() and fx >= cx - de_energise_advance:
			_deenergised[i] = true
			pp.safe()
			var ev: String = "S%d_deenergised" % i
			print("EVENT: S%d de-energised  t=%.4f  fx=%.3f  v=%.3f" % [i, _sim_time, fx, vx])
			_write_csv_row(bolt.global_position.x, vx, fx, 0.0, 0.0, 0.0, ev)

	var in_barrel:  bool  = x > barrel_start_x and x < barrel_end_x
	var f_friction: float = -friction_coeff * vx if in_barrel else 0.0
	var f_drag:     float = -drag_coeff * vx * abs(vx)
	var f_magnet:   float = breach_door.get_magnet_force(fx) if _breach_ok else 0.0

	f_total += f_friction + f_drag + f_magnet
	bolt.constant_force = Vector3(f_total, 0.0, 0.0)

	_log_telemetry(x, vx, fx, f_friction, f_drag, f_magnet)
	_log_charge_status()
	_feed_instruments(x, vx, f_friction, f_drag, f_magnet)

## ── Public interface ──────────────────────────────────────────────────────────

func reset_bolt() -> void:
	if not bolt: return
	for i in range(_deenergised.size()):
		_deenergised[i] = false
	_sim_time        = 0.0
	_last_telem_log  = -1.0
	bolt.constant_force = Vector3.ZERO

	## Position bolt so ferronock starts at ξ = -1.0 behind solenoid0 centre.
	var sol0: Node  = _sol[0] if _sol.size() > 0 else null
	var cx0:  float = sol0.global_position.x if sol0 else 0.50
	var half: float = 0.15
	if sol0 and "coil_length" in sol0:
		half = sol0.coil_length * 0.5
	var ferronock_start: float = cx0 - 0.44 * half ## ξ ≈ -0.44 (peak dL/dx position)
	var new_pos: Vector3 = Vector3(ferronock_start + ferronock_offset, 0.0, 0.0)

	## Use the physics server directly so Jolt applies the teleport immediately,
	## rather than relying on the one-frame-delayed node-layer assignment.
	var rid: RID = bolt.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis.IDENTITY, new_pos))
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
		Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
		Vector3.ZERO)
	bolt.global_position = new_pos   ## keep node transform in sync

	## Pre-set bolt state in every PowerPack so the very first physics step
	## (which processes PowerPacks before SimCtrl) uses the correct position.
	for i in range(_pp.size()):
		if _pp[i]:
			_pp[i].set_bolt_state(ferronock_start, 0.0, _sol[i])

func fire() -> void:
	reset_bolt()
	if _mcu_ok:
		mcu.fire_stage(0)
	elif _pp.size() > 0 and _pp[0]:
		_pp[0].arm()
		_pp[0].fire()

func get_bolt_vx() -> float:
	return bolt.linear_velocity.x if bolt else 0.0

func get_bolt_euler_deg() -> Vector3:
	return bolt.rotation_degrees if bolt else Vector3.ZERO

func get_bolt_omega() -> Vector3:
	return bolt.angular_velocity if bolt else Vector3.ZERO

## ── Telemetry ─────────────────────────────────────────────────────────────────

func _active_stage() -> int:
	## Highest-indexed FIRING stage, falling back to the last de-energised one.
	if _mcu_ok and mcu.has_method("get_firing_stage"):
		var s: int = mcu.get_firing_stage()
		if s >= 0: return s
	for i in range(_deenergised.size() - 1, -1, -1):
		if _deenergised[i]: return i
	return 0

func _log_telemetry(x: float, vx: float, fx: float,
		ff: float, fd: float, fm: float) -> void:
	if not _csv_file: return
	if _sim_time - _last_telem_log < 1.0 / TELEM_LOG_HZ: return
	_last_telem_log = _sim_time
	_write_csv_row(x, vx, fx, ff, fd, fm, "")

func _log_charge_status() -> void:
	## Throttle to 1 Hz — charging spans many seconds so per-tick output is noise.
	if _sim_time - _last_chg_log < 1.0: return
	var parts: PackedStringArray = []
	for i in range(_pp.size()):
		var pp: Node = _pp[i]
		if not pp: continue
		## Use MCU stage state as authoritative source — pp._charging can flip
		## within the same physics frame if PowerPack processes before SimCtrl.
		var is_chg: bool
		if _mcu_ok and mcu.has_method("get_stage_state_name"):
			is_chg = (mcu.get_stage_state_name(i) == "CHARGING")
		else:
			is_chg = pp.is_charging()
		if not is_chg: continue
		var vc:   float = pp.get_voltage()
		var vtgt: float = pp.target_voltage_v
		var frac: float = pp.get_charge_fraction() * 100.0
		## dV per second at current voltage: P/max(V,1) / C
		var dvdt: float = pp.charge_power_w / maxf(vc, 1.0) / pp.capacitance_f
		parts.append("S%d %.1f/%.1fV %.0f%% (+%.1fV/s)" % [i, vc, vtgt, frac, dvdt])
	if parts.size() > 0:
		_last_chg_log = _sim_time
		print("CHG t=%.1f  %s" % [_sim_time, "  ".join(parts)])

func _feed_instruments(x: float, vx: float,
		ff: float, fd: float, fm: float) -> void:
	var fx:  float = x - ferronock_offset
	var act: int   = _active_stage()
	var pp:  Node  = _pp[act]  if act < _pp.size()  else null
	var sol: Node  = _sol[act] if act < _sol.size() else null

	var vc:    float = pp.get_voltage()        if pp  else 0.0
	var I:     float = pp.get_rms_current()    if pp  else 0.0
	var T:     float = pp.get_coil_temp_c()    if pp  else 0.0
	var isq:   float = pp.get_avg_current_sq() if pp  else 0.0
	var F:     float = sol.get_force(fx, isq)  if sol else 0.0
	var L:     float = sol.get_inductance(fx)  if sol else 0.0
	var v_tgt: float = 50.0
	if _mcu_ok and mcu.has_method("get_v_profile"):
		v_tgt = mcu.get_v_profile(act)

	if _telem_graph and _telem_graph.has_method("push_sample"):
		_telem_graph.push_sample(vc, I, F, x, vx, v_tgt)

	if _recorder and _recorder.has_method("push_row"):
		_recorder.push_row(_sim_time, x, vx, act, vc, I, F, L, T, v_tgt, ff, fd, fm)

## ── CSV telemetry file ────────────────────────────────────────────────────────

func _open_csv() -> void:
	var dir_path: String = ProjectSettings.globalize_path("res://") + "test_telemetry"
	DirAccess.make_dir_absolute(dir_path)
	var ts: String = Time.get_datetime_string_from_system(true).replace(":", "-")
	var file_path: String = dir_path + "/run_" + ts + ".csv"
	_csv_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _csv_file:
		_csv_file.store_line("time_s,x_m,vx_ms,stage,Vc_V,I_A,F_N,Ff_N,Fd_N,Fm_N,event")
		print("Telemetry → " + file_path)
	else:
		push_error("SimCtrl: cannot open CSV at " + file_path)

func _write_csv_row(x: float, vx: float, fx: float,
		ff: float, fd: float, fm: float, event: String) -> void:
	var act: int  = _active_stage()
	var pp:  Node = _pp[act]  if act < _pp.size()  else null
	var sol: Node = _sol[act] if act < _sol.size() else null
	var vc:  float = pp.get_voltage()        if pp  else 0.0
	var I:   float = pp.get_rms_current()    if pp  else 0.0
	var isq: float = pp.get_avg_current_sq() if pp  else 0.0
	var F:   float = sol.get_force(fx, isq)  if sol else 0.0
	_csv_file.store_line("%.4f,%.4f,%.4f,%d,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%s" \
		% [_sim_time, x, vx, act, vc, I, F, ff, fd, fm, event])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _csv_file:
			_csv_file.close()
			_csv_file = null
