extends SceneTree

## Controlled range view: baseline, eight body/world hit pairs per second,
## a 32/s stress case, then baseline again. The simulation keeps ticking;
## damage snapshots exercise draw-time effects without killing/moving the
## dummy. This is effects overhead, not a competitive-match FPS benchmark.
## godot --path . --script scripts/profile_hits.gd -- 1920x1080
## --script-particles after the size has the script draw the particles
## where the native code would (HitParticles.native_draws): its A/B.
const PHASES := [0.0, 8.0, 32.0, 0.0]
const SECONDS := 7.0
const WARMUP := 2.0
var _range: Node3D
var _effects: HitEffects
var _camera: Camera3D
var _phase := -1
var _start := 0
var _previous := 0
var _next_hit := 0
var _samples := {}
var _results: Array[Dictionary] = []
var _shot := 0
var _captured := false


func _initialize() -> void:
	call_deferred(&"_setup")


func _setup() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("profile_hits needs a GPU; omit --headless")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(1920,1080)
	if not args.is_empty() and args[0].contains("x"):
		size = Vector2i(int(args[0].get_slice("x",0)), int(args[0].get_slice("x",1)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_range = load("res://maps/test_range/test_range.tscn").instantiate()
	root.add_child(_range)
	await process_frame
	await process_frame
	_range.player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_range.dummy.hit_target.immortal = true
	_range.dummy.hit_target.set_hitboxes_drawn(false)
	for layer in _range.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	_effects = get_first_node_in_group(&"hit_effects") as HitEffects
	_effects.profile = true
	_camera = Camera3D.new()
	_camera.fov = ViewModelProjection.vertical_fov(ViewModelProjection.WORLD_FOV)
	_camera.near = ViewModelProjection.NEAR
	_camera.cull_mask &= ~PlayerSim.UNSEEN_LAYER
	root.add_child(_camera)
	var at: Vector3 = _range.dummy.global_position
	_camera.position = at + Vector3(0,60,256)
	_camera.look_at(at + Vector3(0,48,0))
	_camera.make_current()
	for mesh in RenderVariants.meshes_of(_range):
		if ViewModelProjection.claimed(mesh):
			mesh.visible = false
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await create_timer(3.0).timeout
	_next_phase()


func _process(_dt: float) -> bool:
	if _phase < 0:
		return false
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _start) / 1e6
	if PHASES[_phase] > 0 and now >= _next_hit:
		_hit()
		_next_hit = now + int(1e6 / PHASES[_phase])
	if elapsed >= WARMUP:
		_add("gpu", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		_add("render_cpu", RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		_add("frame", float(now - _previous) / 1000.0)
		_add("draws", RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		_add("particles", _effects.particles.live.size())
		for key in _effects.costs_usec:
			_add(key + "_ms", float(_effects.costs_usec[key]) / 1000.0)
	_previous = now
	if _phase == 1 and elapsed > 4.0 and not _captured:
		_captured = true
		_capture.call_deferred()
	if elapsed < SECONDS:
		return false
	var result := {"hits_per_second":PHASES[_phase]}
	for key in _samples:
		result[key] = median(_samples[key])
	_results.append(result)
	if _phase + 1 < PHASES.size():
		_next_phase()
	else:
		print("HIT_PROFILE %s %s" % [DisplayServer.window_get_size(), JSON.stringify(_results)])
		quit(0)
		return true
	return false


func _next_phase() -> void:
	_phase += 1
	_effects.particles.live.clear()
	_effects.particles.ground.clear()
	_effects._rays.clear()
	_effects.wounds.clear_player(_range.dummy.userid)
	for decal in _effects.splats():
		decal.visible = false
	_effects._splats.clear()
	_effects._splat_state.clear()
	_effects._next_splat = 0
	# Remove pooled decals as well as their bookkeeping before a baseline.
	for child in _effects.get_children():
		if child is Decal:
			child.queue_free()
	_samples.clear()
	_start = Time.get_ticks_usec()
	_previous = _start
	_next_hit = _start


func _hit() -> void:
	_shot += 1
	var dummy: Bot = _range.dummy
	var at := dummy.global_position + Vector3(0,50,0)
	var bone := &""
	for box in dummy.hit_target.hitboxes():
		if box.zone == &"chest" and box.bone_name != &"":
			bone = box.bone_name
			break
	var now := SimClock.now_usec()
	_range.game.events.send(&"player_hurt", {"userid":dummy.userid,"attacker":_range.player.userid,
		"health":100,"armor":100,"dmg_health":30,"dmg_armor":5,"hitgroup":2}, now)
	_range.game.events.send(&"bullet_damage", {"victim":dummy.userid,"attacker":_range.player.userid,
		"x":at.x,"y":at.y,"z":at.z,"normal_z":1.0,"damage_dir_z":-1.0,"health":100.0,
		"dmg_health":30.0,"dmg_armor":5.0,"zone":"chest","hitgroup":2,"bone":String(bone)}, now)
	_range.game.events.flush()
	_effects.queue_world("solidmetal" if _shot % 2 == 0 else "default", at + Vector3(32,0,-15), Vector3.BACK, Vector3.FORWARD, now)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/pr172-hit-profile-%d.png" % DisplayServer.window_get_size().x)


func _add(key: String, value: float) -> void:
	var values: PackedFloat64Array = _samples.get(key, PackedFloat64Array())
	values.append(value)
	_samples[key] = values


static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	return sorted[sorted.size() / 2]
