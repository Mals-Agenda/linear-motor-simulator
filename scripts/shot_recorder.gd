extends Node

## Records telemetry for one shot and exports to CSV.
## Triggered by MCU signals: starts on mcu_stage_fired(0), stops when all stages SAFE.
##
## Output path (Android): user://shots/shot_NNN.csv

@export var max_frames_per_shot: int = 4000

var _recording:  bool   = false
var _rows:       Array  = []
var _shot_index: int    = 0

const HEADER := "t,x,vx,stage,Vc,I,F,L,T,v_target,Ff,Fd,Fm"

func _ready() -> void:
	var mcu: Node = get_node_or_null("../MCU")
	if mcu:
		mcu.mcu_stage_fired.connect(_on_stage_fired)
		mcu.mcu_stage_safe.connect(_on_stage_safe)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://shots/"))

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
	print("ShotRecorder: saved %d rows → %s" \
		% [_rows.size(), ProjectSettings.globalize_path(path)])

func push_row(t: float, x: float, vx: float,
		stage: int,
		vc: float, i_rms: float, f: float, l: float, temp: float,
		v_target: float,
		ff: float, fd: float, fm: float) -> void:
	if not _recording: return
	if _rows.size() >= max_frames_per_shot:
		stop_and_save(); return
	_rows.append(
		"%.5f,%.4f,%.4f,%d,%.3f,%.4f,%.3f,%.6f,%.2f,%.4f,%.4f,%.4f,%.4f" \
		% [t, x, vx, stage, vc, i_rms, f, l, temp, v_target, ff, fd, fm])

func _on_stage_fired(stage: int) -> void:
	if stage == 0:
		start_recording()

var _safe_count: int = 0

func _on_stage_safe(_stage: int) -> void:
	var mcu: Node = get_node_or_null("../MCU")
	if not mcu: stop_and_save(); return
	var n: int = mcu.stage_count if "stage_count" in mcu else 2
	for i in range(n):
		if mcu.get_stage_state_name(i) != "SAFE": return
	stop_and_save()
