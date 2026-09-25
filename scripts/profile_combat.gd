extends SceneTree

## Frame times on dust2 as it is played, out of combat and in it, to set
## beside Sid's CS2 (performance.md, "Against CS2"). It draws, so it needs
## the GPU and the extracted map, and runs on Sid's machine:
##
##   godot --path . --fullscreen --script scripts/profile_combat.gd -- [seconds]
##
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
## scripts, and the rest: drawing and input) and the pipelines the renderer
## compiled in it; then the tick. V-Sync is off and the frame rate
## unlimited, so what is measured is what a frame costs.

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

	func _physics_process(_delta: float) -> void:
		if tick_started > 0:
			var took := Time.get_ticks_usec() - tick_started
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
		if total != shots:
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
			if frame_ms > HITCH_MS:
				var in_ticks := follow.frame_tick_usec / 1000.0
				var scripts := (now - frame_start.at) / 1000.0
				hitches.append("%.1f s: %.1f ms, %d rounds fired so far; ticks %.1f ms (%d), scripts %.1f, drawing and input %.1f; pipelines compiled:%s" % [
					(now - started) / 1_000_000.0, frame_ms, shots, in_ticks, ticks - frame_ticks, scripts,
					frame_ms - in_ticks - scripts, new_pipelines if not new_pipelines.is_empty() else " none"])
		frame_ticks = ticks
		last = now
		follow.frame_tick_usec = 0


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


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		_record_usec = int(args[0].to_float() * 1_000_000.0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		root.add_child((load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate())
		_loaded_at = Time.get_ticks_msec()
		return false
	if _player == null:
		if Time.get_ticks_msec() - _loaded_at < LOAD_MSEC:
			return false
		_set_up()
		return false
	_ride_along()
	var since := Time.get_ticks_usec() - _started
	if since < 0:
		return false
	if not _recorder.recording and _recorder.intervals.is_empty():
		_recorder.started = Time.get_ticks_usec()
		_recorder.recording = true
	if since > GIVE_GUN_USEC and not _player.inventory.has("weapon_ak47"):
		_player.inventory.add("weapon_ak47")
		_player.inventory.select("weapon_ak47")
	if since > _next_melee and not _spawns.is_empty():
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
	for node in root.find_children("*", "", true, false):
		if node is PlayerController:
			_player = node as PlayerSim
		elif node is Competitive:
			_spawns = (node as Competitive).map.spawns["T"]
	_player.hit_target.immortal = true
	# Nothing collides with you or shoots you, or the bot's hull meets yours
	# and is pushed out through the floor.
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.hit_target.set_active(false)
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
	_recorder.process_priority = 100000
	_recorder.follow = _follow
	_recorder.frame_start = frame_start
	root.add_child(_recorder)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("window mode %d at %s, V-Sync %d, frame cap %d, %d players" % [
		DisplayServer.window_get_mode(), str(DisplayServer.window_get_size()),
		DisplayServer.window_get_vsync_mode(), Engine.max_fps, GameWorld.current.players.size()])
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
