extends SceneTree

## Frame times on dust2 in play, out of combat and in it, to set beside
## Sid's CS2 (performance.md, "Against CS2"). It draws, so it needs the GPU
## and the extracted map, and runs on Sid's machine:
##
##   godot --path . --script scripts/profile_combat.gd -- [seconds] [as-played]
##
## The game starts in exclusive fullscreen (project.godot); Godot's
## --fullscreen would ask for plain fullscreen instead, so leave it off.
## seconds is how long it records (75). You ride along with a bot, at its
## eyes, looking where it looks and firing when it fires, so your own gun,
## flash, tracers and holes are in the frame with everyone else's; nothing
## collides with you or shoots you. The AK-47 is put in your hand two
## seconds in, as a first buy would. From 30 seconds on, every 8, every
## living bot is put on the T spawn points together: a fight at close
## range, as busy as a deathmatch, with deaths and dropped guns.
##
## A frame is in combat while anyone has fired in the last second. For each
## it prints the frames' times (mean, median, 95th and 99th percentiles,
## worst), the GPU's mean, and the median of the frames that ran a tick;
## then every frame over HITCH_MS, what was in it (its ticks, the frame's
## scripts, and the uninstrumented remainder) and pipelines the renderer
## compiled in it; then the tick. V-Sync is off and the frame rate
## unlimited, so what is measured is what a frame costs; with as-played
## after the seconds (-- 75 as-played) they are left as the game sets
## them, V-Sync on and frames held just under the screen's refresh
## (PlayerView.frame_cap), so what is measured is what is seen.
##
## Audit options after --: --physics box3d|legacy, immortal (required for
## legacy death-free comparisons), effects (HE/smoke/Molotov/flash at
## 12/17/22/27 seconds), round (leave warmup with no freeze time), natural
## (omit staged encounters), --team-size N, --variant NAME, --size WxH,
## --output PATH (CSV + metadata JSON, parent directory must exist).
## E.g. -- 45 immortal --physics box3d --output .godot/frame-audit/box3d
## split after the seconds (-- 75 split) takes the frame's scripts apart:
## every node that runs a frame callback when the recording is set up is
## given a stamp straight after it, in the order they already ran, and what
## each took is added up by its script (an engine node by its class and the
## script above it), in combat and out. Nodes made after the setup run
## first, together ("made since the setup"). The stamps add about half a
## microsecond a node to every frame.
## GPU/renderer counters are delayed. CPU and GPU times overlap: do not sum
## them or interpret the residual as GPU time. Window-focus flags distinguish
## game hitches from switching applications. This is not an OS present trace.

const RECORD_SECONDS := 75.0
const LOAD_MSEC := 8000
const GIVE_GUN_USEC := 2_000_000
const MELEE_FROM_USEC := 30_000_000
const MELEE_EVERY_USEC := 8_000_000
const COMBAT_USEC := 1_000_000
const HITCH_MS := 20.0
const PIPELINES := ["canvas", "mesh", "surface", "draw", "specialization"]


## Last in every tick: you where the bot is, and the tick's time, from
## TickStart's mark.
class Follow extends Node:
	var player: PlayerSim
	var bot: PlayerSim
	var tick_started := 0
	var tick_usec := PackedInt64Array()
	var frame_tick_usec := 0
	var recording := false

	func _physics_process(_delta: float) -> void:
		if tick_started > 0:
			var took := Time.get_ticks_usec() - tick_started
			if recording:
				tick_usec.append(took)
			frame_tick_usec += took
		if bot == null or not is_instance_valid(bot):
			return
		player.previous_position = bot.previous_position
		player.global_position = bot.global_position
		player.velocity = Vector3.ZERO


## First in every tick.
class TickStart extends Node:
	var follow: Follow

	func _physics_process(_delta: float) -> void:
		follow.tick_started = Time.get_ticks_usec()


## First in every frame's scripts.
class FrameStart extends Node:
	var at := 0

	func _process(_delta: float) -> void:
		at = Time.get_ticks_usec()


## A stamp after one node's frame callback (ScriptSplit).
class SplitStamp extends Node:
	var stamps: PackedInt64Array
	var slot := 0
	var split: ScriptSplit

	func _process(_delta: float) -> void:
		split.stamps[slot] = Time.get_ticks_usec()


## The frame's scripts by node (split): what ran between one stamp and the
## next, added up by the script that ran it, in combat and out.
class ScriptSplit extends RefCounted:
	var keys := PackedStringArray()
	var stamps := PackedInt64Array()
	## By state (0 out of combat, 1 in it): key -> microseconds.
	var sums: Array[Dictionary] = [{}, {}]
	var frames := PackedInt64Array([0, 0])
	## The views that time their own parts (HitEffects.profile), whose parts
	## are added up too, under their name.
	var timed: Array[Node] = []

	## Gives every node that runs a frame callback a stamp straight after
	## it, keeping the order they ran in: by priority, then in the tree.
	func take_apart(root_node: Node) -> int:
		var ranked: Array = []
		var order := 0
		for node in root_node.find_children("*", "", true, false):
			order += 1
			if absi(node.process_priority) >= 100000 or node is SplitStamp:
				continue
			if node.is_processing() or node.is_processing_internal():
				ranked.append([node.process_priority, order, node])
		ranked.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for node in root_node.get_tree().get_nodes_in_group(&"hit_effects"):
			if &"profile" in node:
				node.set(&"profile", true)
				timed.append(node)
		keys.append("made since the setup")
		stamps.resize(ranked.size() + 1)
		_stamp(root_node, 0, 1)
		for i in ranked.size():
			var node: Node = ranked[i][2]
			node.process_priority = 2 + 2 * i
			keys.append(key_of(node))
			_stamp(root_node, i + 1, 3 + 2 * i)
		return ranked.size()

	func _stamp(root_node: Node, slot: int, priority: int) -> void:
		var stamp := SplitStamp.new()
		stamp.split = self
		stamp.slot = slot
		stamp.process_priority = priority
		root_node.add_child(stamp)

	static func key_of(node: Node) -> String:
		var script: Script = node.get_script()
		if script != null:
			var named := String(script.get_global_name())
			return named if not named.is_empty() else script.resource_path.get_file()
		var above := node.get_parent()
		while above != null and above.get_script() == null:
			above = above.get_parent()
		var under := ""
		if above != null:
			var named := String((above.get_script() as Script).get_global_name())
			under = " under " + (named if not named.is_empty() else (above.get_script() as Script).resource_path.get_file())
		return node.get_class() + under

	## This frame's parts, from the first stamp of the frame's scripts to
	## the last.
	func add_frame(state: int, started: int) -> void:
		var previous := started
		var sum: Dictionary = sums[state]
		for slot in stamps.size():
			var at := stamps[slot]
			if at < previous:
				continue
			sum[keys[slot]] = int(sum.get(keys[slot], 0)) + (at - previous)
			previous = at
		for node in timed:
			if not is_instance_valid(node):
				continue
			var costs: Dictionary = node.get(&"costs_usec")
			for part: String in costs:
				var key := "  %s: %s" % [key_of(node), part]
				sum[key] = int(sum.get(key, 0)) + int(costs[part])
		frames[state] += 1

	func report() -> void:
		var by_combat: Array = []
		for key: String in sums[1]:
			by_combat.append(key)
		for key: String in sums[0]:
			if not sums[1].has(key):
				by_combat.append(key)
		var mean := func(state: int, key: String) -> float:
			return float(sums[state].get(key, 0)) / maxi(frames[state], 1) / 1000.0
		by_combat.sort_custom(func(a: String, b: String) -> bool:
			return mean.call(1, a) - mean.call(0, a) > mean.call(1, b) - mean.call(0, b))
		var totals := [0.0, 0.0]
		for key: String in by_combat:
			if key.begins_with("  "):
				continue
			totals[0] += mean.call(0, key)
			totals[1] += mean.call(1, key)
		print("SPLIT the frame's scripts by node, ms a frame: out of combat %.3f over %d frames, in combat %.3f over %d" % [
			totals[0], frames[0], totals[1], frames[1]])
		for i in mini(30, by_combat.size()):
			var key: String = by_combat[i]
			print("SPLIT %8.3f in combat %8.3f out, %+8.3f  %s" % [mean.call(1, key), mean.call(0, key), mean.call(1, key) - mean.call(0, key), key])


## Last in every frame's scripts: the time since the last frame's, and what
## the frame was.
class Recorder extends Node:
	var frame_start: FrameStart
	var follow: Follow
	var recording := false
	var started := 0
	var last := 0
	var intervals := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	var combat := PackedByteArray()
	var ticked := PackedByteArray()
	var last_shot_usec := -10_000_000
	var shots := 0
	var frame_ticks := -1
	var hitches: Array[String] = []
	var compiled: Array[int] = []
	var compiled_while_recording: Array[int] = [0, 0, 0, 0, 0]
	## Raw rows stay in memory; writing files happens after recording stops.
	var rows: Array[PackedFloat64Array] = []
	var audit := false
	var overhead_usec := 0
	var split: ScriptSplit

	static func pipelines() -> Array[int]:
		return [
			int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)),
			int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)),
			int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)),
			int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)),
			int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)),
		]

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var total := 0
		for player in GameWorld.current.players:
			total += player.rounds_fired
		if total > shots:
			shots = total
			last_shot_usec = now
		var ticks := Engine.get_physics_frames()
		var now_compiled := pipelines()
		var new_pipelines := ""
		if not compiled.is_empty():
			for k in PIPELINES.size():
				if now_compiled[k] != compiled[k]:
					new_pipelines += " %s +%d" % [PIPELINES[k], now_compiled[k] - compiled[k]]
					if recording:
						compiled_while_recording[k] += now_compiled[k] - compiled[k]
		compiled = now_compiled
		if recording and last > 0:
			var frame_ms := (now - last) / 1000.0
			intervals.append(frame_ms)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			combat.append(1 if now - last_shot_usec < COMBAT_USEC else 0)
			ticked.append(1 if ticks != frame_ticks else 0)
			if split != null:
				split.add_frame(combat[-1], frame_start.at)
			if audit:
				var alive := 0
				for player in GameWorld.current.players:
					alive += int(player.alive)
				var vp := get_viewport().get_viewport_rid()
				rows.append(PackedFloat64Array([
					(now - started) / 1000000.0, frame_ms, gpu[-1],
					RenderingServer.viewport_get_measured_render_time_cpu(vp),
					RenderingServer.get_frame_setup_time_cpu(),
					follow.frame_tick_usec / 1000.0, (now - frame_start.at) / 1000.0,
					ticks - frame_ticks, combat[-1], shots, alive,
					int(get_window().has_focus()),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
					now_compiled[0], now_compiled[1], now_compiled[2], now_compiled[3], now_compiled[4],
				]))
			if frame_ms > HITCH_MS:
				var in_ticks := follow.frame_tick_usec / 1000.0
				var scripts := (now - frame_start.at) / 1000.0
				hitches.append("%.1f s: %.1f ms, %d rounds fired so far; ticks %.1f ms (%d), scripts %.1f, uninstrumented remainder %.1f; pipelines compiled:%s" % [
					(now - started) / 1_000_000.0, frame_ms, shots, in_ticks, ticks - frame_ticks, scripts,
					frame_ms - in_ticks - scripts, new_pipelines if not new_pipelines.is_empty() else " none"])
		frame_ticks = ticks
		last = now
		follow.frame_tick_usec = 0
		if recording:
			overhead_usec += Time.get_ticks_usec() - now


var _record_usec := int(RECORD_SECONDS * 1_000_000.0)
var _loaded_at := 0
var _player: PlayerSim
var _follow: Follow
var _recorder: Recorder
var _started := -1
var _frames := 0
var _switches := 0
var _said := -1
var _spawns: Array = []
var _next_melee := MELEE_FROM_USEC
var _melees := 0
## V-Sync and the frame cap left as the project has them (as-played).
var _as_played := false
var _team_size := 5
var _immortal := false
var _size := Vector2i.ZERO
var _output := ""
var _variant := "baseline"
var _variant_undo := Callable()
var _scene: Node
var _effects := false
var _next_effect := 0
var _record_start_unix := 0.0
var _round := false
var _natural := false
var _split := false
var _audit_events: Array[Dictionary] = []
var _ghost_faults := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		_record_usec = int(args[0].to_float() * 1_000_000.0)
	_as_played = args.has("as-played")
	_immortal = args.has("immortal")
	_effects = args.has("effects")
	_round = args.has("round")
	_natural = args.has("natural")
	_split = args.has("split")
	if GameWorld.configured_drop_physics() == "legacy" and not _immortal:
		printerr("The converted ragdolls require Box3D; use immortal for legacy comparisons.")
		quit(2)
		return
	for i in args.size() - 1:
		match args[i]:
			"--team-size": _team_size = maxi(1, int(args[i + 1]))
			"--output": _output = args[i + 1]
			"--variant": _variant = args[i + 1]
			"--size": _size = Vector2i(int(args[i + 1].get_slice("x", 0)), int(args[i + 1].get_slice("x", 1)))
	if not RenderVariants.VARIANTS.has(_variant):
		printerr("Unknown render variant: " + _variant)
		quit(2)
		return
	seed(20260926)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		if DisplayServer.get_name() == "headless":
			printerr("profile_combat measures rendered frames; omit --headless")
			quit(1)
			return true
		if _size != Vector2i.ZERO:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(_size)
		if not _as_played:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		var dust2 := (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate()
		dust2.set("game_mode", "Competitive")
		dust2.set("team_size", _team_size)
		root.add_child(dust2)
		_scene = dust2
		if _immortal:
			for player in GameWorld.current.players:
				player.hit_target.immortal = true
		_loaded_at = Time.get_ticks_msec()
		return false
	if _player == null:
		if Time.get_ticks_msec() - _loaded_at < LOAD_MSEC:
			return false
		_set_up()
		return false
	_ride_along()
	if _player.collision_layer != 0:
		_ghost_faults += 1
	var since := Time.get_ticks_usec() - _started
	if since < 0:
		return false
	if not _recorder.recording and _recorder.intervals.is_empty():
		_recorder.started = Time.get_ticks_usec()
		_record_start_unix = Time.get_unix_time_from_system()
		_recorder.recording = true
		_follow.recording = true
	if since > GIVE_GUN_USEC and not _player.inventory.has("weapon_ak47"):
		_player.inventory.add("weapon_ak47")
		_player.inventory.select("weapon_ak47")
	if _effects and _next_effect < 4 and since > (12 + _next_effect * 5) * 1000000:
		var kind: String = [GrenadeRules.HE, GrenadeRules.SMOKE, GrenadeRules.MOLOTOV, GrenadeRules.FLASHBANG][_next_effect]
		_player.inventory.add(kind)
		GameWorld.current.game.command(_player.userid, "throw %s 1" % kind)
		_next_effect += 1
	if not _natural and since > _next_melee and not _spawns.is_empty():
		_next_melee += MELEE_EVERY_USEC
		_melees += 1
		var i := 0
		for player in GameWorld.current.players:
			if player is Bot and player.alive:
				var spawn: Dictionary = _spawns[i % _spawns.size()]
				player.place(spawn["position"], spawn["yaw"])
				i += 1
	@warning_ignore("integer_division")
	var seconds := since / 1_000_000
	if seconds != _said and seconds % 10 == 0:
		print("recording %d s, %d frames, %d rounds fired" % [seconds, _recorder.intervals.size(), _recorder.shots])
	_said = seconds
	if since > _record_usec:
		_recorder.recording = false
		_report()
		return true
	return false


## You, a ghost at a bot's eyes, and the nodes that time the ticks and
## frames; the recording starts a second later, past the frames the setup
## itself holds up (the mouse captured, V-Sync set).
func _set_up() -> void:
	if _round:
		GameWorld.current.match_state.rules.freeze_seconds = 0.0
		GameWorld.current.match_state.end_warmup_on_next_tick()
	if not _output.is_empty():
		for event_name in [&"grenade_thrown", &"hegrenade_detonate", &"smokegrenade_detonate", &"inferno_startburn", &"flashbang_detonate", &"player_death", &"round_start"]:
			GameWorld.current.game.events.listen(event_name, _record_event)
	for node in root.find_children("*", "", true, false):
		if node is PlayerController:
			_player = node as PlayerSim
		elif node is Competitive:
			_spawns = (node as Competitive).map.spawns["T"]
	# Nothing collides with you or shoots you, or the bot's hull meets yours
	# and is pushed out through the floor.
	_player.respawned.connect(_make_ghost)
	_make_ghost()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_follow = Follow.new()
	_follow.player = _player
	_follow.process_physics_priority = 100000
	root.add_child(_follow)
	var tick_start := TickStart.new()
	tick_start.follow = _follow
	tick_start.process_physics_priority = -100000
	root.add_child(tick_start)
	var frame_start := FrameStart.new()
	frame_start.process_priority = -100000
	root.add_child(frame_start)
	_recorder = Recorder.new()
	_recorder.audit = not _output.is_empty()
	_recorder.process_priority = 100000
	_recorder.follow = _follow
	_recorder.frame_start = frame_start
	root.add_child(_recorder)
	if _split:
		_recorder.split = ScriptSplit.new()
		print("split: %d nodes run a frame callback, each given a stamp" % _recorder.split.take_apart(root))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Your view held the frames under the refresh as it started
	# (PlayerView.frame_cap); what a frame costs is measured without that.
	if not _as_played:
		Engine.max_fps = 0
	_variant_undo = RenderVariants.apply(_variant, _scene, root)
	# Request foreground once before the setup grace period. Never reclaim
	# focus during recording; those intervals are flagged for analysis.
	root.grab_focus()
	print("window mode %d at %s, V-Sync %d, frame cap %d, %d players" % [
		DisplayServer.window_get_mode(), str(DisplayServer.window_get_size()),
		DisplayServer.window_get_vsync_mode(), Engine.max_fps, GameWorld.current.players.size()])
	print("audit backend=%s immortal=%s variant=%s GPU=%s engine=%s" % [GameWorld.current.drop_physics_backend, _immortal, _variant, RenderingServer.get_video_adapter_name(), Engine.get_version_info().string])
	_started = Time.get_ticks_usec() + 1_000_000


## Stay with a living bot, look where it looks, and fire when it fires.
func _ride_along() -> void:
	var bot := _follow.bot
	if bot == null or not is_instance_valid(bot) or not bot.alive:
		bot = null
		for player in GameWorld.current.players:
			if player is Bot and player.alive:
				bot = player
				break
		if bot != _follow.bot:
			_switches += 1
		_follow.bot = bot
	if bot == null:
		Input.action_release(&"attack")
		return
	_player.input.yaw_degrees = bot.yaw_degrees
	_player.input.pitch_degrees = bot.pitch_degrees
	if bot.last_command.buttons & UserCmd.ATTACK:
		Input.action_press(&"attack")
	else:
		Input.action_release(&"attack")
	if _player.weapon != null and _player.weapon.ammo == 0:
		Input.action_press(&"reload")
	else:
		Input.action_release(&"reload")


func _report() -> void:
	var r := _recorder
	print("rode with %d bots in turn; your rounds %d, everyone's %d; %d melees" % [_switches, _player.rounds_fired, r.shots, _melees])
	for state in [0, 1]:
		var times := PackedFloat64Array()
		var gpu_sum := 0.0
		var tick_frames := PackedFloat64Array()
		for i in r.intervals.size():
			if r.combat[i] != state:
				continue
			times.append(r.intervals[i])
			gpu_sum += r.gpu[i]
			if r.ticked[i]:
				tick_frames.append(r.intervals[i])
		var label := "in combat" if state == 1 else "out of combat"
		if times.is_empty():
			print("%s: no frames" % label)
			continue
		var sorted := times.duplicate()
		sorted.sort()
		tick_frames.sort()
		var mean := 0.0
		for t in times:
			mean += t
		mean /= times.size()
		print("%s: %d frames, mean %.2f ms (%.0f a second), median %.2f, 95th %.2f, 99th %.2f, worst %.2f; GPU mean %.2f ms; frames that ran a tick, median %.2f" % [
			label, times.size(), mean, 1000.0 / mean, sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)],
			sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1], gpu_sum / times.size(),
			tick_frames[tick_frames.size() / 2] if not tick_frames.is_empty() else 0.0])
	for hitch in r.hitches:
		print("hitch at " + hitch)
	if r.hitches.is_empty():
		print("no frame over %.0f ms" % HITCH_MS)
	var compiled := PackedStringArray()
	for k in PIPELINES.size():
		compiled.append("%s %d" % [PIPELINES[k], r.compiled_while_recording[k]])
	print("pipelines compiled while recording: " + ", ".join(compiled))
	var ticks := _follow.tick_usec.duplicate()
	ticks.sort()
	if not ticks.is_empty():
		var mean := 0.0
		for t in ticks:
			mean += t
		print("the tick (every physics callback): mean %.2f ms, median %.2f, 95th %.2f, worst %.2f" % [
			mean / ticks.size() / 1000.0, ticks[ticks.size() / 2] / 1000.0,
			ticks[int(ticks.size() * 0.95)] / 1000.0, ticks[ticks.size() - 1] / 1000.0])
	if r.split != null:
		r.split.report()
	if not _output.is_empty():
		_write_audit()
	if _variant_undo.is_valid():
		_variant_undo.call()


func _write_audit() -> void:
	var r := _recorder
	var csv := FileAccess.open(_output + ".csv", FileAccess.WRITE)
	if csv == null:
		push_error("Cannot write audit to " + _output)
		return
	csv.store_csv_line(PackedStringArray(["seconds", "frame_ms", "gpu_ms", "render_cpu_ms", "render_setup_cpu_ms", "tick_callbacks_ms", "frame_callbacks_ms", "ticks", "combat", "shots", "alive", "focused", "draw_calls", "triangles", "video_mib", "pipeline_canvas", "pipeline_mesh", "pipeline_surface", "pipeline_draw", "pipeline_specialization"]))
	for row in r.rows:
		var fields := PackedStringArray()
		for value in row:
			fields.append(str(value))
		csv.store_csv_line(fields)
	csv.close()
	var metadata := {
		"utc": Time.get_datetime_string_from_system(true),
		"record_start_unix": _record_start_unix,
		"engine": Engine.get_version_info(), "debug_build": OS.is_debug_build(),
		"gpu": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"window": str(DisplayServer.window_get_size()), "window_mode": DisplayServer.window_get_mode(),
		"vsync": DisplayServer.window_get_vsync_mode(), "frame_cap": Engine.max_fps,
		"backend": GameWorld.current.drop_physics_backend, "players": GameWorld.current.players.size(),
		"immortal": _immortal, "variant": _variant, "effects": _effects,
		"round": _round, "natural": _natural, "events": _audit_events,
		"ghost_collision_faults": _ghost_faults,
		"seed": 20260926, "seconds": _record_usec / 1000000.0, "load_grace_ms": LOAD_MSEC,
		"samples": r.rows.size(), "recorder_mean_ms": float(r.overhead_usec) / maxi(1, r.rows.size()) / 1000.0,
		"pipelines": r.compiled_while_recording,
		"tick_callbacks_us": _follow.tick_usec,
		"notes": "End-of-process wall intervals, not OS presentation or input latency. GPU/render CPU counters are delayed viewport samples, not additive components. Tick callbacks exclude automatic PhysicsServer work; frame callbacks exclude deferred work. The uninstrumented remainder includes rendering, waits, engine work and OS scheduling. Warmup/setup excluded; first-use gameplay remains. Follow-camera scenario, seeded but not a deterministic input replay."
	}
	var json := FileAccess.open(_output + ".json", FileAccess.WRITE)
	json.store_string(JSON.stringify(metadata, "\t"))
	json.close()
	print("AUDIT saved %s.csv and .json; recorder mean %.4f ms/frame" % [_output, metadata.recorder_mean_ms])


func _record_event(event: GameEvent) -> void:
	if _recorder != null and _recorder.recording:
		_audit_events.append({"seconds": (Time.get_ticks_usec() - _recorder.started) / 1000000.0, "name": event.name, "fields": event.fields.duplicate()})


func _make_ghost() -> void:
	# A fresh competitive round restores the player's hull and hitboxes.
	# Keep the recording camera from physically obstructing its followed bot.
	_player.hit_target.immortal = true
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.hit_target.set_active(false)
	PhysicsQueries.sync_object(_player)
