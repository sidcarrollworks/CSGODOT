extends "res://tests/check_suite.gd"

## The render profiler's variants (RenderVariants) on a small stand-in for a
## map: a sun, an environment, a mesh casting from both faces and a skybox
## mesh. Each variant has to change what it says it does, and its undo has to
## put every one of those things back, since the profiler runs them one after
## another on the same scene. Headless there is nothing drawn, so the frame
## times themselves are for scripts/profile_render.gd on a real GPU.

var _scene: Node3D
var _sun: DirectionalLight3D
var _environment: Environment
var _wall: MeshInstance3D
var _sky: MeshInstance3D


func _initialize() -> void:
	_build()
	_check_stats()
	_check_variants()
	_finish("render")


func _build() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.light_angular_distance = 0.5
	_sun.directional_shadow_max_distance = 8192.0
	_scene.add_child(_sun)

	_environment = Environment.new()
	_environment.ssao_enabled = true
	_environment.glow_enabled = true
	_environment.fog_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_scene.add_child(world_environment)

	_wall = MeshInstance3D.new()
	_wall.mesh = BoxMesh.new()
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_scene.add_child(_wall)

	_sky = MeshInstance3D.new()
	_sky.mesh = BoxMesh.new()
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.material_override = FarMaterials.build(StandardMaterial3D.new(), FarMaterials.far_plane_depth())
	_scene.add_child(_sky)

	root.msaa_3d = Viewport.MSAA_2X


func _check_stats() -> void:
	_check_equal(RenderVariants.sun_of(_scene), _sun, "the sun is found")
	_check_equal(RenderVariants.environment_of(_scene), _environment, "the environment is found")
	_check_equal(RenderVariants.far_meshes(_scene), [_sky] as Array[MeshInstance3D], "only the skybox's mesh is drawn behind everything")
	var stats := RenderVariants.scene_stats(_scene)
	_check_equal(stats["instances"], 2, "two mesh instances counted")
	_check_equal(stats["triangles"], 24, "a box is twelve triangles, two boxes 24")
	_check_equal(stats["casting_instances"], 1, "the wall casts, the skybox does not")
	_check_equal(stats["double_sided_casters"], 1, "the wall casts from both faces")
	_check_equal(stats["skybox_instances"], 1, "the skybox's mesh is counted as the skybox")
	_check_equal(stats["skybox_triangles"], 12, "the skybox's triangles")


## Everything a variant may touch, as it stands.
func _state() -> Dictionary:
	var viewport := root
	return {
		"shadows": _sun.shadow_enabled,
		"angular": _sun.light_angular_distance,
		"distance": _sun.directional_shadow_max_distance,
		"casting": _wall.cast_shadow,
		"msaa": viewport.msaa_3d,
		"ssao": _environment.ssao_enabled,
		"glow": _environment.glow_enabled,
		"fog": _environment.fog_enabled,
		"sky": _sky.visible,
		"scale": viewport.scaling_3d_scale,
	}


func _check_variants() -> void:
	var expected := {
		"no_sun_shadows": {"shadows": false},
		"sun_hard_edges": {"angular": 0.0},
		"sun_filter_low": {},
		"sun_atlas_4096": {},
		"sun_distance_2048": {"distance": 2048.0},
		"one_sided_casters": {"casting": GeometryInstance3D.SHADOW_CASTING_SETTING_ON},
		"no_msaa": {"msaa": Viewport.MSAA_DISABLED},
		"no_ssao": {"ssao": false},
		"no_glow": {"glow": false},
		"no_fog": {"fog": false},
		"no_skybox": {"sky": false},
		"no_players": {},
		"half_resolution": {"scale": 0.5},
		"all_off": {
			"shadows": false, "angular": 0.0, "distance": 2048.0,
			"casting": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "msaa": Viewport.MSAA_DISABLED,
			"ssao": false, "glow": false, "fog": false, "sky": false,
		},
	}
	var before := _state()
	for variant in RenderVariants.names():
		_check(RenderVariants.VARIANTS[variant] is String, "%s says what it tells" % variant)
		if variant == "baseline":
			continue
		_check(expected.has(variant), "%s is checked here" % variant)
		var undo := RenderVariants.apply(variant, _scene, root)
		var during := _state()
		var changes: Dictionary = expected.get(variant, {})
		for what: String in before:
			var wanted: Variant = changes.get(what, before[what])
			_check_equal(during[what], wanted, "%s: %s" % [variant, what])
		undo.call()
		_check_equal(_state(), before, "%s is put back" % variant)
