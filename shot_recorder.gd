extends Node
class_name ShotRecorder

## Records telemetry for one shot and exports to CSV.
## Triggered by MCU signals: starts on mcu_stage_fired(0), stops when all stages SAFE.
##
## Output path (Android): user://shots/shot_NNN.csv
## Access via:  adb pull /sdcard/Android/data/org.godotengine.<project>/files/shots/
## Or in Godot: OS.shell_open(ProjectSettings.globalize_path("user://shots/"))

@export var max_frames_per_shot: int = 4000   ## safety cap (~67s at 60Hz)

var _recording:  bool   = false
var _rows:       Array  = []
var _shot_index: int    = 0

## Column header — must match push_row() argument order
const HEADER := "t,x,vx,Vc0,I0,F0,L0,T0,Vc1,I1,F1,L1,T1,Ff,Fd,Fm"

func _ready() -> void:
	## Wire to MCU
	var mcu: Node = get_node_or_null("../MCU")
	if mcu:
		mcu.mcu_stage_fired.connect(_on_stage_fired)
		mcu.mcu_stage_safe.connect(_on_stage_safe)
	## Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://shots/"))

## ── Recording control ─────────────────────────────────────────────────────────

func start_recording() -> void:
	_rows.clear()
	_recording = true

func stop_and_save() -> void:
	_recording = false
	if _rows.is_empty(): return
	_shot_index += 1
	var path: String = "user://shots/shot_%03d.csv" % _shot_index
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_error("ShotRecorder: cannot write %s" % path); return
	f.store_line(HEADER)
	for row in _rows:
		f.store_line(row)
	f.close()
	var abs_path: String = ProjectSettings.globalize_path(path)
	print("ShotRecorder: saved %d rows → %s" % [_rows.size(), abs_path])

## ── Data push (called by SimCtrl each physics frame) ─────────────────────────

func push_row(t: float, x: float, vx: float,
			  vc0: float, i0: float, f0: float, l0: float, t0: float,
			  vc1: float, i1: float, f1: float, l1: float, t1: float,
			  ff: float,  fd: float, fm: float) -> void:
	if not _recording: return
	if _rows.size() >= max_frames_per_shot:
		stop_and_save(); return
	_rows.append("%.5f,%.4f,%.4f,%.3f,%.4f,%.3f,%.6f,%.2f,%.3f,%.4f,%.3f,%.6f,%.2f,%.4f,%.4f,%.4f" \
		% [t, x, vx, vc0, i0, f0, l0, t0, vc1, i1, f1, l1, t1, ff, fd, fm])

## ── MCU signal handlers ───────────────────────────────────────────────────────

func _on_stage_fired(stage: int) -> void:
	if stage == 0:
		start_recording()

var _safe_count: int = 0

func _on_stage_safe(_stage: int) -> void:
	## Wait until all stages are safe, then flush
	var mcu: Node = get_node_or_null("../MCU")
	if not mcu: stop_and_save(); return
	var n: int = mcu.stage_count if "stage_count" in mcu else 2
	for i in range(n):
		if mcu.get_stage_state_name(i) != "SAFE": return
	stop_and_save()
