extends SceneTree

## What dust2's frames cost to draw, taken apart by feature. Where
## profile_dust2.gd times the script headless, this draws, so it needs the
## GPU and the extracted map, and runs on Sid's machine:
##
##   godot --path . --script scripts/profile_render.gd -- [team size] [frames] [size]
##
## Team size 5 is ten players (you and nine bots), 1 is you alone; frames is
## how many are measured at each view (60). Without a size it draws as the
## game does, fullscreen at the screen's own size (3840x2160 on Sid's); with
## one, such as 1920x1080, in a window that size. Godot's --resolution does
## nothing here, as the project starts in exclusive fullscreen. The size
## actually drawn is printed with the results.
##
## A camera of its own looks from both sides' first spawn points at eye
## height, four ways each (eight views, the same every run), so the map is
## seen along its long sight lines as it is played. Every variant in
## RenderVariants is switched on in turn, measured at all eight views, and
## put back. For each it prints the GPU's time to draw a frame (the
## renderer's own measurement, the median over every frame at every view),
## the renderer's CPU time, the whole frame's time as the clock saw it, and
## the draw calls and triangles, in the camera's pass and the shadow passes
## apart. Vsync is off and the frame rate unlimited throughout.
##
## Read the GPU column against the baseline: a variant that takes 3 ms off
## is 3 ms that feature costs. Half resolution says whether the frame is
## bound by pixels (it halves) or by geometry and draw calls (it barely
## moves). The bots run through warmup meanwhile, so the players' share
## wanders a little between runs.

const LOAD_FRAMES := 150
const WARM_FRAMES := 20
const EYE_HEIGHT := 64.0

var _team_size := 5
var _measure_frames := 60
var _window_size := Vector2i.ZERO
var _dust2: Node
var _reflections: MapReflections
var _camera: Camera3D
var _views: Array[Transform3D] = []
var _variants := RenderVariants.names()
var _variant := -1
var _view := 0
var _frame := 0
var _undo := Callable()
var _last_usec := 0
var _samples := {}  # what -> Array of numbers, this variant
var _results: Array[Dictionary] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_team_size = int(args[0])
	if args.size() >= 2:
		_measure_frames = maxi(1, int(args[1]))
	if args.size() >= 3 and args[2].contains("x"):
		_window_size = Vector2i(int(args[2].get_slice("x", 0)), int(args[2].get_slice("x", 1)))
	if DisplayServer.get_name() == "headless":
		printerr("profile_render draws, so it cannot run headless. Leave out --headless.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _window_size != Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(_window_size)
	_dust2 = (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate()
	_dust2.set("team_size", _team_size)
	_dust2.set("game_mode", "Competitive")
	root.add_child(_dust2)


func _process(_delta: float) -> bool:
	if _dust2 == null:
		return false
	if Engine.get_process_frames() < LOAD_FRAMES:
		return false
	if _variant < 0:
		# The map's reflection probes are drawn one a frame as it starts, the
		# whole map with them (MapReflections): measured once they are done.
		if _reflections == null:
			_reflections = RenderVariants.reflections_of(_dust2)
		if _reflections != null and _reflections.is_capturing():
			return false
		_begin()
		_next_variant()
		return false

	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if _frame >= WARM_FRAMES:
		_sample(frame_ms)
	_frame += 1
	if _frame < WARM_FRAMES + _measure_frames:
		return false
	_frame = 0
	_view += 1
	if _view < _views.size():
		_look(_view)
		return false
	_finish_variant()
	_view = 0
	if _variant + 1 < _variants.size():
		_next_variant()
		return false
	_report()
	quit(0)
	return true


## A camera of its own, and the views it takes.
func _begin() -> void:
	# The game's view caps the frame rate under the refresh (PlayerView);
	# measured, nothing is held back.
	Engine.max_fps = 0
	var viewport := root
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)

	var entities: Array = _find_entities(_dust2)
	var spawns := SourceEntities.player_spawns(entities) if not entities.is_empty() else {"T": [], "CT": []}
	for team in ["T", "CT"]:
		if (spawns[team] as Array).is_empty():
			continue
		var spawn: Dictionary = spawns[team][0]
		for quarter in 4:
			var basis := Basis(Vector3.UP, deg_to_rad(float(spawn["yaw"]) + 90.0 * quarter))
			_views.append(Transform3D(basis, (spawn["position"] as Vector3) + Vector3.UP * EYE_HEIGHT))
	var playing := viewport.get_camera_3d()
	if _views.is_empty():
		# No spawn points extracted: the player's own camera, four ways.
		push_warning("No spawn points, so the views are the player's; runs will not compare.")
		var from := playing.global_transform if playing != null else Transform3D.IDENTITY
		for quarter in 4:
			_views.append(Transform3D(from.basis.rotated(Vector3.UP, PI * 0.5 * quarter), from.origin))

	_camera = Camera3D.new()
	_camera.name = "ProfileCamera"
	_camera.fov = ViewModelProjection.vertical_fov(ViewModelProjection.WORLD_FOV)
	_camera.near = ViewModelProjection.NEAR
	if playing != null:
		_camera.far = playing.far
	_camera.cull_mask &= ~PlayerSim.UNSEEN_LAYER
	root.add_child(_camera)
	_camera.make_current()


func _find_entities(node: Node) -> Array:
	var found: Variant = node.get("entities")
	if found is Array and not (found as Array).is_empty():
		return found
	for child in node.get_children():
		var inside := _find_entities(child)
		if not inside.is_empty():
			return inside
	return []


func _look(view: int) -> void:
	_camera.global_transform = _views[view]
	# The player's arms draw through any camera (ViewModelProjection): out.
	for mesh in RenderVariants.meshes_of(_dust2):
		if ViewModelProjection.claimed(mesh):
			mesh.visible = false


func _next_variant() -> void:
	_variant += 1
	_samples = {}
	_undo = RenderVariants.apply(_variants[_variant], _dust2, root)
	_look(0)
	_last_usec = Time.get_ticks_usec()


func _sample(frame_ms: float) -> void:
	var viewport := root.get_viewport_rid()
	_add("gpu", RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	_add("cpu", RenderingServer.viewport_get_measured_render_time_cpu(viewport))
	_add("frame", frame_ms)
	for pass_kind in [RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]:
		var prefix := "view" if pass_kind == RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE else "shadow"
		_add(prefix + "_draws", RenderingServer.viewport_get_render_info(
			viewport, pass_kind, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		_add(prefix + "_triangles", RenderingServer.viewport_get_render_info(
			viewport, pass_kind, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		_add(prefix + "_objects", RenderingServer.viewport_get_render_info(
			viewport, pass_kind, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))


func _add(what: String, value: float) -> void:
	# A packed array comes out of a dictionary as a copy: append to it, then
	# put it back.
	var values: PackedFloat64Array = _samples.get(what, PackedFloat64Array())
	values.append(value)
	_samples[what] = values


func _finish_variant() -> void:
	var result := {"variant": _variants[_variant]}
	for what: String in _samples:
		result[what] = _median(_samples[what])
	_results.append(result)
	_undo.call()


static func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	return sorted[sorted.size() / 2]


func _report() -> void:
	var viewport := root
	var stats := RenderVariants.scene_stats(_dust2)
	print("")
	print("## dust2 drawn, %s" % Time.get_datetime_string_from_system(false, true))
	print("")
	print("- GPU: %s (%s), %s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")])
	print("- Drawn at %dx%d, %d players, %d views of %d frames each" % [
		# The window's own size: the viewport's visible rect is the stretch
		# base (1920x1080), whatever the window is.
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		_team_size * 2, _views.size(), _measure_frames])
	print("- Scene: %d mesh instances, %d surfaces, %d triangles, %d materials; %d instances cast shadows (%d from both faces, %d triangles), %d of them into the sun's; the 3D skybox %d instances, %d triangles" % [
		stats["instances"], stats["surfaces"], stats["triangles"], stats["materials"],
		stats["casting_instances"], stats["double_sided_casters"], stats["casting_triangles"], stats["sun_casting_instances"],
		stats["skybox_instances"], stats["skybox_triangles"]])
	print("- Materials by shader: %s" % stats["shaders"])
	print("- Memory: video %.0f MB, of it textures %.0f MB and buffers %.0f MB" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	print("")
	print("Medians over every measured frame. GPU and CPU are the renderer's own times; frame is the clock's, ticks included.")
	print("")
	print("| Variant | GPU ms | GPU saved | Render CPU ms | Frame ms | fps | Draws (view / shadow) | Triangles (view / shadow) |")
	print("|---|---|---|---|---|---|---|---|")
	var baseline: float = _results[0].get("gpu", 0.0)
	for result in _results:
		var frame: float = result.get("frame", 0.0)
		print("| %s | %.2f | %s | %.2f | %.2f | %.0f | %d / %d | %s / %s |" % [
			result["variant"], result.get("gpu", 0.0),
			"" if result["variant"] == "baseline" else "%.2f" % (baseline - float(result.get("gpu", 0.0))),
			result.get("cpu", 0.0), frame, 1000.0 / frame if frame > 0.0 else 0.0,
			result.get("view_draws", 0), result.get("shadow_draws", 0),
			_thousands(result.get("view_triangles", 0)), _thousands(result.get("shadow_triangles", 0))])
	print("")
	for variant in RenderVariants.VARIANTS:
		print("- %s: %s" % [variant, RenderVariants.VARIANTS[variant]])


static func _thousands(value: float) -> String:
	if value >= 1_000_000.0:
		return "%.1fM" % (value / 1_000_000.0)
	return "%.0fk" % (value / 1000.0)
