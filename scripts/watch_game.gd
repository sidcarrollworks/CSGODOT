extends SceneTree

## The game as it is played, watched: it starts the project's own scene and
## says each second how the frames went, what the ticks and the frames'
## scripts took, what the drawing took, how many bodies were in view and
## posed, and what happened in the match. Every frame over SLOW_MS is said
## at once with what was in it. At the end, the whole run, and the frames
## set out by how many bodies were in view.
##
##   godot --path . --script scripts/watch_game.gd -- --mode competitive --window=1920x1080 --frames=frames.csv
##
## --window=WxH plays in a window of that size in the middle of the screen;
## --frames=path writes every frame's row (COLUMNS) when the game is quit;
## --seconds=N ends the run N seconds after the match appears (for runs
## nobody plays, headless or not). Run it from a shell, not from the editor,
## whose debugger works after every frame, and with the game alone on the
## machine: what else runs shows
## in every part of a frame, the watcher's own included (watcher_ms, about
## 0.07 ms a frame, is the sign). It prints a line a second as it goes,
## and its slow frames only at the end: a print costs about a millisecond
## on Sid's machine (2026-09-30), which the next frame would carry. The
## frames less its own work are given at the end too.
##
## A frame is its ticks, then its scripts, then its drawing. It is timed
## two ways. As drawn: from the end of one frame's drawing to the end of
## the next's, which is a frame's own ticks, scripts and drawing, and what
## the eye gets. As the HUD's frame meter counts: from the start of one
## frame's scripts to the start of the next's, which is one frame's scripts
## and drawing and the NEXT frame's ticks.
##
## Two nodes stamp the clock, one before every other node's callbacks and
## one after them all, on the tick and on the frame. Every body's skeleton
## is given one more modifier, first of them, that does nothing but stamp
## the clock, and the skeleton says when it has been posed: between the two
## is what its fitting costs (the feet, the hands, the twist bones).
## Nothing is taken over.
##
## The whole frame is also split, stamp to stamp, in the order Godot 4.7.2
## runs it (main/main.cpp Main::iteration, scene/main/scene_tree.cpp,
## servers/rendering/rendering_server_default.cpp):
## - the watcher's own work (its frame_post_draw handler and _process);
## - the wait: from the last frame's end to this one's first stamp, which
##   is the engine's tail after drawing, the frame cap's sleep, the window's
##   events and input (input_ms: from the first _input seen to the loop);
## - each tick: before its first node (physics_frame handlers), its nodes
##   (tick_ms), the flush after them to a call deferred from the last node
##   (the thread group's queue, deferred calls), and after that to the next
##   tick or the frame (timers, tweens, transforms, deletions, navigation,
##   the Jolt step): tick_before, tick_flush, tick_engine;
## - the frame's head (process_frame handlers) and its scripts;
## - after the scripts: the thread group's queue to a call queued from the
##   last node (the deferred skeleton updates), the deferred calls to a call
##   deferred from it (HUD redraws), and on to frame_pre_draw (transforms,
##   timers, tweens, deletions, navigation, RenderingServer sync);
## - the draw, frame_pre_draw to frame_post_draw, split by the render
##   device's own timestamps of the root viewport (vp_begin, vp_end), which
##   come back a frame later, so each frame is kept a frame after it is
##   drawn: setup (scene and canvas update, particles, probes, SubViewports),
##   the root's render, and its finish (acquiring the swapchain image, the
##   blit, recording the Vulkan commands, submit, present, the wait for the
##   frame before on the GPU, frees). The render device's GPU times of the
##   same frame come with them.
## Each frame also counts the pipelines compiled, the objects and nodes
## made less those freed, and the draw calls.

const SLOW_MS := 10.0
## The first seconds after the match appears are the map settling.
const SETTLE_SECONDS := 5.0
## Events too common to name in a slow frame.
const UNTOLD := [&"player_footstep", &"bullet_impact", &"fire_bullets", &"player_hurt"]
## How many frames a frame waits for its render timestamps before it is
## kept without them.
const TIMESTAMP_PATIENCE := 4
## The frames file's columns, in the order of a row.
const COLUMNS := [
	"frame_ms", "in_view", "ticks", "tick_ms", "scripts_ms", "fitting_ms", "draw_cpu_ms", "gpu_ms",
	"animated", "posed", "in_view_dead", "hud_frame_ms", "after_scripts_ms",
	"watcher_ms", "wait_ms", "input_ms", "tick_before_ms", "tick_flush_ms", "tick_engine_ms",
	"head_ms", "skeletons_ms", "deferred_ms", "to_draw_ms", "draw_ms",
	"draw_setup_ms", "scene_update_ms", "draw_render_ms", "draw_finish_ms", "gpu_root_ms", "gpu_frame_ms",
	"pipelines", "pipelines_waited", "objects_delta", "nodes_delta", "draw_calls", "shadow_draw_calls", "aligned",
]
const COUNT_COLUMNS := [
	"in_view", "ticks", "animated", "posed", "in_view_dead",
	"pipelines", "pipelines_waited", "objects_delta", "nodes_delta", "draw_calls", "shadow_draw_calls", "aligned",
]
enum {
	FRAME, IN_VIEW, TICKS, TICK, SCRIPTS, FITTING, DRAW_CPU, GPU, ANIMATED, POSED, IN_VIEW_DEAD, HUD, AFTER,
	WATCHER, WAIT, INPUT, TICK_BEFORE, TICK_FLUSH, TICK_ENGINE, HEAD, SKELETONS, DEFERRED, TO_DRAW, DRAW,
	DRAW_SETUP, SCENE_UPDATE, DRAW_RENDER, DRAW_FINISH, GPU_ROOT, GPU_FRAME,
	PIPELINES, PIPELINES_WAITED, OBJECTS, NODES, DRAW_CALLS, SHADOW_CALLS, ALIGNED,
}
## The pipeline counters, the canvas's and the draw's first: those two a
## frame waits for.
const PIPELINE_INFOS := [
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
	RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
]
const MARKER := """extends Node
var first: Node
var tick_at := 0
var frame_at := 0
var ticks := PackedInt32Array()
var tick_firsts := PackedInt64Array()
var tick_lasts := PackedInt64Array()
var tick_flushed := PackedInt64Array()
var last_scripts := 0
var grouped_at := 0
var deferred_at := 0
var input_at := 0
var done := Callable()

func _physics_process(_d: float) -> void:
	tick_at = Time.get_ticks_usec()
	if first != null:
		var began := int(first.get(&"tick_at"))
		ticks.append(tick_at - began)
		tick_firsts.append(began)
		tick_lasts.append(tick_at)
		_tick_flushed.call_deferred()

func _tick_flushed() -> void:
	tick_flushed.append(Time.get_ticks_usec())

func _process(_d: float) -> void:
	frame_at = Time.get_ticks_usec()
	if first != null:
		last_scripts = frame_at - int(first.get(&"frame_at"))
		grouped_at = 0
		deferred_at = 0
		call_deferred_thread_group(&"_grouped")
		_deferred.call_deferred()

func _grouped() -> void:
	grouped_at = Time.get_ticks_usec()

func _deferred() -> void:
	deferred_at = Time.get_ticks_usec()
	if done.is_valid():
		done.call()

func _input(_event: InputEvent) -> void:
	if input_at == 0:
		input_at = Time.get_ticks_usec()

func take() -> PackedInt32Array:
	var taken := ticks.duplicate()
	ticks.clear()
	return taken

func take_ticks() -> Array:
	var taken := [tick_firsts.duplicate(), tick_lasts.duplicate(), tick_flushed.duplicate()]
	tick_firsts.clear()
	tick_lasts.clear()
	tick_flushed.clear()
	return taken
"""
const STAMP := """extends SkeletonModifier3D
var at := 0

func _process_modification_with_delta(_delta: float) -> void:
	at = Time.get_ticks_usec()
"""

var _first: Node
var _last: Node
var _stamp_script: GDScript
var _world: GameWorld
var _world_seen_usec := -1
var _started_usec := 0
var _end_after_usec := 0
var _last_scripts_usec := -1
var _last_drawn_usec := -1
var _second_start_usec := -1
var _second := 0

## Skeleton -> its stamp.
var _stamps := {}
## Of the frame being run: its ticks, skeletons posed and what their
## fitting took, and how the HUD's meter would time it.
var _frame_ticks := PackedInt32Array()
var _posed := 0
var _fitting_usec := 0
var _as_the_hud_ms := 0.0

## The split's stamps of the frame being run.
var _rd: RenderingDevice
var _root_id := ""
var _serial := 0
var _pre_at := -1
var _own_end := -1
var _process_start := -1
var _process_end := -1
var _tick_mains := PackedInt64Array()
var _frame_tick_mains := PackedInt64Array()
var _frame_tick_firsts := PackedInt64Array()
var _frame_tick_lasts := PackedInt64Array()
var _frame_tick_flushed := PackedInt64Array()
var _frame_input_at := 0
var _pipelines_before := PackedInt64Array()
var _objects_before := -1
var _nodes_before := -1
var _timestamps_said := false
## Serial -> a frame drawn and waiting for its render timestamps.
var _pending := {}

var _frames := PackedFloat32Array()
var _hud_frames := PackedFloat32Array()
var _ticks := PackedFloat32Array()
var _scripts := PackedFloat32Array()
var _draw_cpu := 0.0
var _draw_gpu := 0.0
var _seen_sum := 0
var _stepped_sum := 0
var _posed_sum := 0
var _fitting_sum := 0.0
## Of the second: watcher, wait, the ticks' engine, after the scripts, the
## draw's setup, render and finish, frames with the draw split, pipelines.
var _split_sums := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var _counts := {}
var _in_frame := PackedStringArray()
var _held := ""
var _things := -1
var _menu_open := false
var _menu: Node

var _all_frames := PackedFloat32Array()
var _all_hud_frames := PackedFloat32Array()
var _all_ticks := PackedFloat32Array()
var _all_scripts := PackedFloat32Array()
var _slowest_by_second := PackedFloat32Array()
var _hud_slowest_by_second := PackedFloat32Array()
var _slow_frames := 0
var _deaths := 0
## Slow frames said at the end, not as they come.
var _slow_lines := PackedStringArray()
## Frames less the watcher's own work: of the second, of the run, and the
## slowest of each second.
var _net_frames := PackedFloat32Array()
var _all_net_frames := PackedFloat32Array()
var _net_slowest_by_second := PackedFloat32Array()
## Every settled frame, for the tables at the end and the frames file, in
## the order of COLUMNS.
var _rows: Array[PackedFloat32Array] = []


func _initialize() -> void:
	_started_usec = Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds=") and argument.trim_prefix("--seconds=").is_valid_float():
			_end_after_usec = int(float(argument.trim_prefix("--seconds=")) * 1_000_000.0)
	var stamp := GDScript.new()
	stamp.source_code = MARKER
	stamp.reload()
	_stamp_script = GDScript.new()
	_stamp_script.source_code = STAMP
	_stamp_script.reload()
	_first = Node.new()
	_first.set_script(stamp)
	_first.name = "WatchFirst"
	_first.process_priority = -(1 << 30)
	_first.process_physics_priority = -(1 << 30)
	_first.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_first)
	_last = Node.new()
	_last.set_script(stamp)
	_last.name = "WatchLast"
	_last.set(&"first", _first)
	_last.process_priority = 1 << 30
	_last.process_physics_priority = 1 << 30
	_last.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_last)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_root_id = str(root.get_viewport_rid().get_id())
	# Headless nothing is drawn and nothing says so: the frame's end is what
	# is deferred from the last of its scripts, which is enough to try the
	# watcher by.
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
		RenderingServer.frame_post_draw.connect(_on_drawn)
		_rd = RenderingServer.get_rendering_device()
	else:
		_last.set(&"done", _on_drawn)
	# --window=1920x1080: a window of that size in the middle of the screen,
	# in place of the project's exclusive fullscreen, which Godot's own
	# --windowed and --resolution did not change.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--window="):
			var asked := argument.trim_prefix("--window=").split("x")
			if asked.size() == 2 and asked[0].is_valid_int() and asked[1].is_valid_int():
				var size := Vector2i(int(asked[0]), int(asked[1]))
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(size)
				var screen := DisplayServer.window_get_current_screen()
				DisplayServer.window_set_position(
					DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - size) / 2)
	var scene := String(ProjectSettings.get_setting("application/run/main_scene"))
	print("WATCH starting %s with %s" % [scene, OS.get_cmdline_user_args()])
	change_scene_to_file(scene)


## A tick is about to run its nodes.
func _physics_process(_delta: float) -> bool:
	_tick_mains.append(Time.get_ticks_usec())
	return false


## The frame's scripts are about to run; its ticks have.
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	_process_start = now
	# --seconds=N: the run ends by itself N seconds after the match appears.
	if _world_seen_usec >= 0 and _end_after_usec > 0 and now - _world_seen_usec >= _end_after_usec:
		_process_end = now
		return true
	_find_world(now)
	_stamp_the_bodies()
	_look_at_you()
	_frame_ticks = _last.call(&"take")
	var taken: Array = _last.call(&"take_ticks")
	_frame_tick_firsts = taken[0]
	_frame_tick_lasts = taken[1]
	_frame_tick_flushed = taken[2]
	_frame_tick_mains = _tick_mains.duplicate()
	_tick_mains.clear()
	var inputs := PackedInt64Array()
	for marker: Node in [_first, _last]:
		var at := int(marker.get(&"input_at"))
		if at > 0:
			inputs.append(at)
		marker.set(&"input_at", 0)
	inputs.sort()
	_frame_input_at = inputs[0] if not inputs.is_empty() else 0
	_as_the_hud_ms = (now - _last_scripts_usec) / 1000.0 if _last_scripts_usec >= 0 else 0.0
	_last_scripts_usec = now
	_process_end = Time.get_ticks_usec()
	return false


## The draw is starting: marked on the render device too, to find this
## frame's timestamps by when they come back.
func _on_pre_draw() -> void:
	_pre_at = Time.get_ticks_usec()
	if _rd != null:
		_rd.capture_timestamp("w_pre_%d" % _serial)


## The frame has been drawn: all of it is known but its render timestamps,
## which come back with the next frame's.
func _on_drawn() -> void:
	var now := Time.get_ticks_usec()
	var serial := _serial
	_serial += 1
	if _last_drawn_usec >= 0 and _world_seen_usec >= 0 and _as_the_hud_ms > 0.0:
		_pending[serial] = _record(now)
	_read_timestamps()
	_keep_ready(serial)
	if _rd != null:
		_rd.capture_timestamp("w_post_%d" % serial)
	_in_frame.clear()
	_posed = 0
	_fitting_usec = 0
	_last_drawn_usec = now
	_own_end = Time.get_ticks_usec()


## This frame as far as it is known at its end.
func _record(now: int) -> Dictionary:
	var frame_ms := (now - _last_drawn_usec) / 1000.0
	var tick_ms := 0.0
	for tick in _frame_ticks:
		tick_ms += tick / 1000.0
	var scripts_ms := int(_last.get(&"last_scripts")) / 1000.0
	var fitting_ms := _fitting_usec / 1000.0
	var first_at := int(_first.get(&"frame_at"))
	var last_at := int(_last.get(&"frame_at"))
	# From the end of the last node's _process to now: headless, the
	# frame's deferred work, which the skeletons' updates are part of.
	var after_ms := (now - last_at) / 1000.0
	var rid := root.get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var bodies := _count_the_bodies()
	# The split, stamp to stamp.
	var own_end := _own_end if _own_end >= _last_drawn_usec else _last_drawn_usec
	var loop_at := _frame_tick_mains[0] if not _frame_tick_mains.is_empty() else _process_start
	var watcher_ms := ((own_end - _last_drawn_usec) + (_process_end - _process_start)) / 1000.0
	var wait_ms := (loop_at - own_end) / 1000.0
	var input_ms := 0.0
	if _frame_input_at >= own_end and _frame_input_at <= loop_at:
		input_ms = (loop_at - _frame_input_at) / 1000.0
	var before := 0
	var flush := 0
	var engine := 0
	var n := _frame_tick_mains.size()
	if n == _frame_tick_firsts.size() and n == _frame_tick_lasts.size() and n == _frame_tick_flushed.size():
		for i in n:
			var next_at := _frame_tick_mains[i + 1] if i + 1 < n else _process_start
			before += _frame_tick_firsts[i] - _frame_tick_mains[i]
			flush += _frame_tick_flushed[i] - _frame_tick_lasts[i]
			engine += next_at - _frame_tick_flushed[i]
	else:
		before = -1000
		flush = -1000
		engine = -1000
	var grouped_at := int(_last.get(&"grouped_at"))
	var deferred_at := int(_last.get(&"deferred_at"))
	var head_ms := (first_at - _process_end) / 1000.0
	var skeletons_ms := -1.0
	var deferred_ms := -1.0
	var to_draw_ms := -1.0
	var drew := _rd != null and _pre_at >= last_at and _pre_at <= now
	if grouped_at >= last_at and deferred_at >= grouped_at and (not drew or _pre_at >= deferred_at):
		skeletons_ms = (grouped_at - last_at) / 1000.0
		deferred_ms = (deferred_at - grouped_at) / 1000.0
		to_draw_ms = (_pre_at - deferred_at) / 1000.0 if drew else maxf((now - deferred_at) / 1000.0, 0.0)
	var draw_ms := (now - _pre_at) / 1000.0 if drew else 0.0
	# What the frame made, freed, compiled and drew.
	var pipelines := PackedInt64Array()
	for info: int in PIPELINE_INFOS:
		pipelines.append(RenderingServer.get_rendering_info(info))
	var compiled := 0
	var waited := 0
	if pipelines.size() == _pipelines_before.size():
		for i in pipelines.size():
			compiled += pipelines[i] - _pipelines_before[i]
			if i < 2:
				waited += pipelines[i] - _pipelines_before[i]
	_pipelines_before = pipelines
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_delta := objects - _objects_before if _objects_before >= 0 else 0
	var nodes_delta := nodes - _nodes_before if _nodes_before >= 0 else 0
	_objects_before = objects
	_nodes_before = nodes
	var calls := RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var shadow_calls := RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var row := PackedFloat32Array([
		frame_ms, bodies.x, _frame_ticks.size(), tick_ms, scripts_ms, fitting_ms, cpu, gpu, bodies.z, _posed, bodies.y,
		_as_the_hud_ms, after_ms,
		watcher_ms, wait_ms, input_ms, before / 1000.0, flush / 1000.0, engine / 1000.0,
		head_ms, skeletons_ms, deferred_ms, to_draw_ms, draw_ms,
		-1.0, RenderingServer.get_frame_setup_time_cpu() if drew else 0.0, -1.0, -1.0, -1.0, -1.0,
		compiled, waited, objects_delta, nodes_delta, calls, shadow_calls, 0,
	])
	return {
		"row": row,
		"post": now,
		"pre": _pre_at if drew else -1,
		"ticks": _frame_ticks.duplicate(),
		"events": _in_frame.duplicate(),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"calls_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"focused": DisplayServer.get_name() == "headless" or DisplayServer.window_is_focused(),
		"aligned": false,
	}


## The render device's timestamps, which are the frame before's: its root
## viewport's begin and end, on the same clock as the stamps, and on the GPU.
func _read_timestamps() -> void:
	if _rd == null:
		return
	var count := _rd.get_captured_timestamps_count()
	var times := {}
	var begins: Array[String] = []
	var ends: Array[String] = []
	for i in count:
		var name := _rd.get_captured_timestamp_name(i)
		if name.begins_with("w_") or name.begins_with("vp_begin_") or name.begins_with("vp_end_"):
			times[name] = [_rd.get_captured_timestamp_cpu_time(i), _rd.get_captured_timestamp_gpu_time(i)]
			if name.begins_with("vp_begin_"):
				begins.append(name)
			elif name.begins_with("vp_end_"):
				ends.append(name)
	if not _timestamps_said and _second >= 3:
		_timestamps_said = true
		var names := PackedStringArray()
		for i in count:
			names.append(_rd.get_captured_timestamp_name(i))
		print("WATCH the render device's timestamps (%d; the root viewport is %s): %s" % [count, _root_id, ", ".join(names)])
	var begin_name := "vp_begin_" + _root_id
	var end_name := "vp_end_" + _root_id
	if not times.has(begin_name) and begins.size() == 1:
		begin_name = begins[0]
	if not times.has(end_name) and ends.size() == 1:
		end_name = ends[0]
	if not times.has(begin_name) or not times.has(end_name):
		return
	for name: String in times:
		if not name.begins_with("w_pre_"):
			continue
		var serial := int(name.trim_prefix("w_pre_"))
		if _pending.has(serial):
			_align(_pending[serial], times[begin_name], times[end_name], times.get("w_post_%d" % (serial - 1), []))


## The draw of a frame split by its root viewport's timestamps.
func _align(record: Dictionary, begin: Array, end: Array, post_before: Array) -> void:
	var pre: int = record["pre"]
	var post: int = record["post"]
	var began: int = begin[0]
	var ended: int = end[0]
	if pre < 0 or began < pre or ended < began or post < ended:
		return
	# A packed array is a value: changed, and put back.
	var row: PackedFloat32Array = record["row"]
	row[DRAW_SETUP] = (began - pre) / 1000.0
	row[DRAW_RENDER] = (ended - began) / 1000.0
	row[DRAW_FINISH] = (post - ended) / 1000.0
	# The GPU's clock is in nanoseconds.
	row[GPU_ROOT] = (int(end[1]) - int(begin[1])) / 1_000_000.0
	if not post_before.is_empty():
		row[GPU_FRAME] = (int(end[1]) - int(post_before[1])) / 1_000_000.0
	row[ALIGNED] = 1
	record["row"] = row
	record["aligned"] = true


## Frames kept in order: each once its timestamps are in, or given up on.
func _keep_ready(current: int) -> void:
	var serials := _pending.keys()
	serials.sort()
	for serial: int in serials:
		var record: Dictionary = _pending[serial]
		if _rd == null or record["aligned"] or serial <= current - TIMESTAMP_PATIENCE:
			_keep(record)
			_pending.erase(serial)
		else:
			break


## A frame counted: in its second, in the run, and said if slow.
func _keep(record: Dictionary) -> void:
	var row: PackedFloat32Array = record["row"]
	var now: int = record["post"]
	var ticks: PackedInt32Array = record["ticks"]
	var frame_ms := row[FRAME]
	for tick in ticks:
		_ticks.append(tick / 1000.0)
	_frames.append(frame_ms)
	_hud_frames.append(row[HUD])
	_scripts.append(row[SCRIPTS])
	_draw_cpu += row[DRAW_CPU]
	_draw_gpu += row[GPU]
	_seen_sum += int(row[IN_VIEW])
	_stepped_sum += int(row[ANIMATED])
	_posed_sum += int(row[POSED])
	_fitting_sum += row[FITTING]
	_split_sums[0] += row[WATCHER]
	_split_sums[1] += row[WAIT]
	_split_sums[2] += maxf(row[TICK_BEFORE], 0.0) + maxf(row[TICK_FLUSH], 0.0) + maxf(row[TICK_ENGINE], 0.0)
	_split_sums[3] += maxf(row[SKELETONS], 0.0) + maxf(row[DEFERRED], 0.0) + maxf(row[TO_DRAW], 0.0)
	if row[ALIGNED] > 0.0:
		_split_sums[4] += row[DRAW_SETUP]
		_split_sums[5] += row[DRAW_RENDER]
		_split_sums[6] += row[DRAW_FINISH]
		_split_sums[7] += 1
	_split_sums[8] += row[PIPELINES]
	var settled := now - _world_seen_usec >= int(SETTLE_SECONDS * 1_000_000.0)
	var focused: bool = record["focused"]
	if settled and focused:
		_all_frames.append(frame_ms)
		_all_hud_frames.append(row[HUD])
		_all_scripts.append(row[SCRIPTS])
		for tick in ticks:
			_all_ticks.append(tick / 1000.0)
		_rows.append(row)
	if frame_ms >= SLOW_MS and settled:
		_slow_frames += 1
		var events: PackedStringArray = record["events"]
		# Kept to say at the end: a print here costs a millisecond or more
		# (2026-09-30), which the next frame would carry.
		_slow_lines.append("SLOW  %6.1f s: a frame of %.1f ms as drawn (%.1f as the HUD counts): %d tick%s %.1f ms, its scripts %.1f (of them the skeletons' fitting %.1f), drawing cpu %.1f gpu %.1f, the rest %.1f; %d bodies in view (%d of them dead), %d animated, %d skeletons posed; %d objects drawn in %d calls%s%s" % [
			(now - _world_seen_usec) / 1_000_000.0, frame_ms, row[HUD], ticks.size(), "" if ticks.size() == 1 else "s",
			row[TICK], row[SCRIPTS], row[FITTING], row[DRAW_CPU], row[GPU], maxf(frame_ms - row[TICK] - row[SCRIPTS] - row[DRAW_CPU], 0.0),
			int(row[IN_VIEW]), int(row[IN_VIEW_DEAD]), int(row[ANIMATED]), int(row[POSED]),
			int(record["objects_drawn"]), int(record["calls_drawn"]),
			"; in it: " + ", ".join(events) if not events.is_empty() else "",
			"" if focused else "; the window not in focus",
		])
		_slow_lines.append("SPLIT %6.1f s: %s" % [(now - _world_seen_usec) / 1_000_000.0, _split_text(row)])
	# The frame less the watcher's own work in it (its handlers and prints).
	var net := frame_ms - row[WATCHER]
	_net_frames.append(net)
	if settled and focused:
		_all_net_frames.append(net)
	if _second_start_usec < 0:
		_second_start_usec = now
	elif now - _second_start_usec >= 1_000_000:
		_say_second(now)


## One frame's split, in the order it ran.
static func _split_text(row: PackedFloat32Array) -> String:
	var draw := "draw %.2f unsplit" % row[DRAW]
	if row[ALIGNED] > 0.0:
		draw = "draw %.2f: setup %.2f (scene update %.2f), render %.2f, finish %.2f; gpu %.2f root, %.2f the frame" % [
			row[DRAW], row[DRAW_SETUP], row[SCENE_UPDATE], row[DRAW_RENDER], row[DRAW_FINISH], row[GPU_ROOT], row[GPU_FRAME]]
	var parts := row[WATCHER] + row[WAIT] + row[TICK_BEFORE] + row[TICK] + row[TICK_FLUSH] + row[TICK_ENGINE] \
		+ row[HEAD] + row[SCRIPTS] + maxf(row[SKELETONS], 0.0) + maxf(row[DEFERRED], 0.0) + maxf(row[TO_DRAW], 0.0) + row[DRAW]
	return "watcher %.2f | wait %.2f (after input %.2f) | %d tick%s: before %.2f, nodes %.2f, flush %.2f, engine %.2f | head %.2f, scripts %.2f | skeletons %.2f, deferred %.2f, to the draw %.2f | %s | pipelines %d (%d waited on), objects %+d, nodes %+d, draw calls %d, shadow %d | the parts less the frame %.2f" % [
		row[WATCHER], row[WAIT], row[INPUT], int(row[TICKS]), "" if int(row[TICKS]) == 1 else "s",
		row[TICK_BEFORE], row[TICK], row[TICK_FLUSH], row[TICK_ENGINE], row[HEAD], row[SCRIPTS],
		row[SKELETONS], row[DEFERRED], row[TO_DRAW], draw,
		int(row[PIPELINES]), int(row[PIPELINES_WAITED]), int(row[OBJECTS]), int(row[NODES]), int(row[DRAW_CALLS]), int(row[SHADOW_CALLS]),
		parts - row[FRAME]]


func _find_world(now: int) -> void:
	var current := GameWorld.current
	if current == _world or not is_instance_valid(current) or current.game == null:
		return
	_world = current
	_world.game.events.listen_all(_on_event)
	if _world_seen_usec < 0:
		_world_seen_usec = now
		print("WATCH the match is there %.1f s after starting; %d players" % [(now - _started_usec) / 1_000_000.0, _world.players.size()])
		print("WATCH the movement: asked for %s; the native code %s" % [
			"native" if PlayerBody.native_steps else "script",
			"is built from the sources here" if PlayerBody.native_built() else "does not run (%s)" % PlayerBody.native_missing])


## Every body's skeleton stamped and listened to.
func _stamp_the_bodies() -> void:
	if not is_instance_valid(_world):
		return
	for player in _world.players:
		if not is_instance_valid(player) or player.model == null or not is_instance_valid(player.model):
			continue
		var rig := player.model.character_rig
		if rig != null and not _stamps.has(rig):
			_stamp(rig)


## The bots' bodies counted: x in view as the frame drew them, y of those
## dead, z animated in the frame.
func _count_the_bodies() -> Vector3i:
	var seen := 0
	var seen_dead := 0
	var stepped := 0
	if not is_instance_valid(_world):
		return Vector3i.ZERO
	for player in _world.players:
		if not is_instance_valid(player) or player is PlayerController:
			continue
		var model := player.model
		if model == null or not is_instance_valid(model):
			continue
		if model.is_seen():
			seen += 1
			if not player.alive:
				seen_dead += 1
		if model.is_animating() and model.stepped_by_hand and model._unstepped == 0.0:
			stepped += 1
	return Vector3i(seen, seen_dead, stepped)


func _stamp(rig: Skeleton3D) -> void:
	# The ones whose bodies have gone are forgotten.
	for known: Variant in _stamps.keys():
		if not is_instance_valid(known):
			_stamps.erase(known)
	var stamp := SkeletonModifier3D.new()
	stamp.set_script(_stamp_script)
	stamp.name = "WatchStamp"
	rig.add_child(stamp)
	rig.move_child(stamp, 0)
	_stamps[rig] = stamp
	rig.skeleton_updated.connect(_on_posed.bind(rig))


func _on_posed(rig: Skeleton3D) -> void:
	var now := Time.get_ticks_usec()
	_posed += 1
	var stamp: Variant = _stamps.get(rig)
	if stamp != null and is_instance_valid(stamp):
		var at := int(stamp.get(&"at"))
		if at > 0 and at <= now:
			_fitting_usec += now - at
		stamp.set(&"at", 0)


## What changed since the last frame that no event says: what is in your
## hand, how many things (dropped guns, grenades, the bomb) there are, and
## whether the buy menu is up.
func _look_at_you() -> void:
	if not is_instance_valid(_world):
		return
	for player in _world.players:
		if is_instance_valid(player) and player is PlayerController:
			var held := player.inventory.in_hand_class() if player.inventory != null else ""
			if held != _held:
				_in_frame.append("you took %s in hand" % (held if not held.is_empty() else "nothing"))
				_held = held
			break
	var things := _world.game.entities.all().size()
	if _things >= 0 and things != _things:
		_in_frame.append("things in the world %d to %d" % [_things, things])
	_things = things
	if not is_instance_valid(_menu):
		var menus := root.find_children("BuyMenu", "", true, false)
		_menu = menus[0] if not menus.is_empty() else null
	var open := is_instance_valid(_menu) and _menu.has_method(&"is_open") and bool(_menu.call(&"is_open"))
	if open != _menu_open:
		_in_frame.append("the buy menu %s" % ("opened" if open else "closed"))
		_menu_open = open


func _on_event(event: GameEvent) -> void:
	_counts[event.name] = int(_counts.get(event.name, 0)) + 1
	if event.name == &"player_death":
		_deaths += 1
	if not UNTOLD.has(event.name) and not _in_frame.has(String(event.name)):
		_in_frame.append(String(event.name))


func _say_second(now: int) -> void:
	_second += 1
	var elapsed := (now - _second_start_usec) / 1_000_000.0
	var phase := "-"
	var alive := 0
	if is_instance_valid(_world):
		for player in _world.players:
			if is_instance_valid(player) and player.alive:
				alive += 1
		if is_instance_valid(_world.match_state):
			phase = String(MatchState.Phase.keys()[_world.match_state.phase]).to_lower()
	var slowest := _most(_frames)
	var hud_slowest := _most(_hud_frames)
	if now - _world_seen_usec >= int(SETTLE_SECONDS * 1_000_000.0):
		_slowest_by_second.append(slowest)
		_hud_slowest_by_second.append(hud_slowest)
		_net_slowest_by_second.append(_most(_net_frames))
	_net_frames.clear()
	var frames := maxf(_frames.size(), 1.0)
	var split := maxf(_split_sums[7], 1.0)
	print("WATCH %4d s %-8s alive %2d | %3.0f fps, a frame %.1f ms, slowest %.1f as drawn, %.1f as the HUD counts | %2d ticks, %.2f ms, slowest %.2f | frame scripts %.2f, slowest %.2f | drawing: cpu %.2f gpu %.2f | in view %.1f, animated %.1f, posed %.1f, fitting %.2f ms | deaths %d shots %d spawns %d bought %d | rest: watcher %.2f, wait %.2f, the ticks' engine %.2f, after the scripts %.2f, draw setup %.2f render %.2f finish %.2f, pipelines %d" % [
		_second, phase, alive, _frames.size() / elapsed, _mean(_frames), slowest, hud_slowest,
		_ticks.size(), _mean(_ticks), _most(_ticks), _mean(_scripts), _most(_scripts),
		_draw_cpu / frames, _draw_gpu / frames,
		_seen_sum / frames, _stepped_sum / frames, _posed_sum / frames, _fitting_sum / frames,
		int(_counts.get(&"player_death", 0)), int(_counts.get(&"weapon_fire", 0)), int(_counts.get(&"player_spawn", 0)),
		int(_counts.get(&"item_purchase", 0)),
		_split_sums[0] / frames, _split_sums[1] / frames, _split_sums[2] / frames, _split_sums[3] / frames,
		_split_sums[4] / split, _split_sums[5] / split, _split_sums[6] / split, int(_split_sums[8]),
	])
	if _second == 3:
		# By now the view has set the window and the frame cap as it plays.
		print("WATCH the window: %s, mode %d, on a screen of %s at %.0f Hz; frames capped at %d a second, V-Sync mode %d; 3D scale %.2f" % [
			DisplayServer.window_get_size(), DisplayServer.window_get_mode(), DisplayServer.screen_get_size(),
			DisplayServer.screen_get_refresh_rate(), Engine.max_fps, DisplayServer.window_get_vsync_mode(),
			root.scaling_3d_scale])
	_frames.clear()
	_hud_frames.clear()
	_ticks.clear()
	_scripts.clear()
	_draw_cpu = 0.0
	_draw_gpu = 0.0
	_seen_sum = 0
	_stepped_sum = 0
	_posed_sum = 0
	_fitting_sum = 0.0
	_split_sums = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	_counts.clear()
	_second_start_usec = now


func _finalize() -> void:
	# The last frames, kept without their timestamps.
	var serials := _pending.keys()
	serials.sort()
	for serial: int in serials:
		_keep(_pending[serial])
	_pending.clear()
	for line in _slow_lines:
		print(line)
	print("WATCH the run: %d frames and %d ticks in %d s of play, %d deaths" % [_all_frames.size(), _all_ticks.size(), _slowest_by_second.size(), _deaths])
	print("WATCH frames less the watcher's own work: mean %.2f ms, median %.2f, 95th %.2f, 99th %.2f, worst %.2f; %d of %.1f ms or more; the slowest of each second: median %.1f, 95th %.1f; seconds under 6 ms %d, over 8 ms %d, over 10 ms %d, of %d" % [
		_mean(_all_net_frames), _at(_all_net_frames, 0.5), _at(_all_net_frames, 0.95), _at(_all_net_frames, 0.99), _most(_all_net_frames),
		_count_at_least(_all_net_frames, SLOW_MS), SLOW_MS,
		_at(_net_slowest_by_second, 0.5), _at(_net_slowest_by_second, 0.95),
		_net_slowest_by_second.size() - _over(_net_slowest_by_second, 6.0), _over(_net_slowest_by_second, 8.0), _over(_net_slowest_by_second, 10.0),
		_net_slowest_by_second.size()])
	if is_instance_valid(_world):
		var stepped_natively := 0
		for player in _world.players:
			if is_instance_valid(player) and player.get(&"_mover") != null:
				stepped_natively += 1
		print("WATCH the movement: %d of %d players were stepped by the native code" % [stepped_natively, _world.players.size()])
	print("WATCH frames as drawn: mean %.2f ms, median %.2f, 95th %.2f, 99th %.2f, worst %.2f; %d of %.1f ms or more" % [
		_mean(_all_frames), _at(_all_frames, 0.5), _at(_all_frames, 0.95), _at(_all_frames, 0.99), _most(_all_frames), _slow_frames, SLOW_MS])
	print("WATCH frames as the HUD counts: mean %.2f ms, median %.2f, 95th %.2f, 99th %.2f, worst %.2f" % [
		_mean(_all_hud_frames), _at(_all_hud_frames, 0.5), _at(_all_hud_frames, 0.95), _at(_all_hud_frames, 0.99), _most(_all_hud_frames)])
	print("WATCH the slowest frame of each second as drawn: median %.1f ms, 95th %.1f, worst %.1f; seconds under 6 ms %d, over 8 ms %d, over 10 ms %d, of %d" % [
		_at(_slowest_by_second, 0.5), _at(_slowest_by_second, 0.95), _most(_slowest_by_second),
		_slowest_by_second.size() - _over(_slowest_by_second, 6.0), _over(_slowest_by_second, 8.0), _over(_slowest_by_second, 10.0), _slowest_by_second.size()])
	print("WATCH the slowest frame of each second as the HUD shows it: median %.1f ms, 95th %.1f, worst %.1f; seconds under 6 ms %d, over 8 ms %d, over 10 ms %d, of %d" % [
		_at(_hud_slowest_by_second, 0.5), _at(_hud_slowest_by_second, 0.95), _most(_hud_slowest_by_second),
		_hud_slowest_by_second.size() - _over(_hud_slowest_by_second, 6.0), _over(_hud_slowest_by_second, 8.0), _over(_hud_slowest_by_second, 10.0),
		_hud_slowest_by_second.size()])
	print("WATCH ticks: mean %.2f ms, median %.2f, 95th %.2f, 99th %.2f, worst %.2f; over 4 ms %d, over 6 ms %d" % [
		_mean(_all_ticks), _at(_all_ticks, 0.5), _at(_all_ticks, 0.95), _at(_all_ticks, 0.99), _most(_all_ticks),
		_over(_all_ticks, 4.0), _over(_all_ticks, 6.0)])
	print("WATCH the frames' scripts: mean %.2f ms, 95th %.2f, 99th %.2f, worst %.2f" % [
		_mean(_all_scripts), _at(_all_scripts, 0.95), _at(_all_scripts, 0.99), _most(_all_scripts)])
	# The frames by how many bodies were in view, those that held a tick
	# and those that held none.
	for ticked: bool in [false, true]:
		for seen in range(0, 11):
			var frames := PackedFloat32Array()
			var sums := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
			for row in _rows:
				if int(row[IN_VIEW]) != seen or (row[TICKS] > 0.0) != ticked:
					continue
				frames.append(row[FRAME])
				sums[0] += row[TICK]
				sums[1] += row[SCRIPTS]
				sums[2] += row[FITTING]
				sums[3] += row[DRAW_CPU]
				sums[4] += row[GPU]
				sums[5] += row[ANIMATED]
				sums[6] += row[POSED]
			if frames.size() < 20:
				continue
			var n := float(frames.size())
			print("TABLE %s, %2d in view: %6d frames; a frame %.2f ms, median %.2f, 95th %.2f, 99th %.2f; tick %.2f, scripts %.2f (fitting %.2f), drawing cpu %.2f gpu %.2f; animated %.1f, posed %.1f" % [
				"a tick in it" if ticked else "no tick    ", seen, frames.size(), _mean(frames), _at(frames, 0.5), _at(frames, 0.95), _at(frames, 0.99),
				sums[0] / n, sums[1] / n, sums[2] / n, sums[3] / n, sums[4] / n, sums[5] / n, sums[6] / n])
	_say_the_split()
	# And every frame, for whoever reads the run after.
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			path = argument.trim_prefix("--frames=")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_line(",".join(PackedStringArray(COLUMNS)))
			var counted := PackedByteArray()
			for column: String in COLUMNS:
				counted.append(1 if COUNT_COLUMNS.has(column) else 0)
			for row in _rows:
				var cells := PackedStringArray()
				for i in COLUMNS.size():
					cells.append(str(int(row[i])) if counted[i] == 1 else "%.3f" % row[i])
				file.store_line(",".join(cells))
			file.close()
			print("WATCH every frame written to %s (%d)" % [path, _rows.size()])


## The frames by how long they were, with and without a tick, each part of
## them on average, in the order they ran.
func _say_the_split() -> void:
	var aligned := 0
	var worst_gap := 0.0
	for row in _rows:
		if row[ALIGNED] > 0.0:
			aligned += 1
	print("WATCH the draw split by the render device's timestamps in %d of %d frames" % [aligned, _rows.size()])
	var bands := [[0.0, 5.0], [5.0, 6.0], [6.0, 8.0], [8.0, 10.0], [10.0, 1000.0]]
	for ticked: bool in [false, true]:
		for band: Array in bands:
			var picked: Array[PackedFloat32Array] = []
			for row in _rows:
				if (_rd != null and row[ALIGNED] <= 0.0) or (row[TICKS] > 0.0) != ticked:
					continue
				if row[FRAME] < band[0] or row[FRAME] >= band[1]:
					continue
				if row[TICK_BEFORE] < 0.0 or row[SKELETONS] < 0.0 or row[TO_DRAW] < 0.0:
					continue
				picked.append(row)
			if picked.is_empty():
				continue
			var mean := PackedFloat32Array()
			mean.resize(COLUMNS.size())
			for row in picked:
				for i in COLUMNS.size():
					mean[i] += row[i] / picked.size()
			for row in picked:
				var parts := row[WATCHER] + row[WAIT] + row[TICK_BEFORE] + row[TICK] + row[TICK_FLUSH] + row[TICK_ENGINE] \
					+ row[HEAD] + row[SCRIPTS] + row[SKELETONS] + row[DEFERRED] + row[TO_DRAW] + row[DRAW]
				worst_gap = maxf(worst_gap, absf(parts - row[FRAME]))
			print("SPLIT %s, %4.0f to %4.0f ms: %6d frames, a frame %.2f | %s" % [
				"a tick in it" if ticked else "no tick    ", band[0], minf(band[1], 99.0), picked.size(), mean[FRAME], _split_text(mean)])
	print("WATCH the parts add up to each frame within %.3f ms" % worst_gap)


static func _mean(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value
	return sum / maxf(values.size(), 1.0)


static func _most(values: PackedFloat32Array) -> float:
	var most := 0.0
	for value in values:
		most = maxf(most, value)
	return most


static func _count_at_least(values: PackedFloat32Array, limit: float) -> int:
	var count := 0
	for value in values:
		if value >= limit:
			count += 1
	return count


static func _over(values: PackedFloat32Array, limit: float) -> int:
	var count := 0
	for value in values:
		if value > limit:
			count += 1
	return count


static func _at(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(share * sorted.size())) - 1, 0, sorted.size() - 1)]
