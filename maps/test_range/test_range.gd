extends Node3D

## The spray pattern range.
##
## This is the tuning instrument for shooting, the way the movement course is
## for movement. Fire a magazine at the wall, look at the holes, compare
## against a reference image, and export what you got as a pattern file.
##
## The export is the important part. CS2's recoil data cannot be extracted, so
## patterns have to be measured, and a measurement is only useful if it can go
## straight back into the file the weapon reads. Press P and it does.

## Distance from the firing line to the wall. Spray references are usually
## drawn at a fixed distance, so this needs to match whatever you compare
## against, and it is the first thing to change if the pattern looks the right
## shape but the wrong size.
const WALL_DISTANCE := 512.0

const WALL_SIZE := Vector2(768.0, 512.0)
const DUMMY_DISTANCE := 1024.0

var player: PlayerController
var dummy: HitTarget

var _impacts: Array = []
var _markers: Node3D
var _label: Label


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_build_wall()
	_build_dummy()
	_build_player()
	_build_hud()

	_markers = Node3D.new()
	_markers.name = "Impacts"
	add_child(_markers)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"export_spray"):
		_export_spray()
	elif event.is_action_pressed(&"reset_range"):
		_reset()


func _process(_delta: float) -> void:
	if player == null or player.weapon == null:
		return
	var weapon := player.weapon
	var state := Weapon.ShooterState.new(
		Vector2(player.velocity.x, player.velocity.z).length(),
		player.on_ground,
		player.is_ducked
	)
	_label.text = "\n".join([
		"%s" % weapon.data.display_name,
		"ammo       %d / %d" % [weapon.ammo, weapon.reserve],
		"shot       %d" % weapon.shot_index(),
		"cone       %.3f deg" % weapon.current_inaccuracy(state),
		"impacts    %d" % _impacts.size(),
		"",
		"1 / 2  weapon      R  reload",
		"P      export      O  clear",
	])


## Records every shot the player takes, and marks the ones that hit the wall.
func _on_shot(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	if not result.hit:
		return
	_impacts.append({"shot": shot, "position": result.position})
	_add_marker(result.position, result.hitbox != null)


func _add_marker(at: Vector3, on_target: bool) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	marker.mesh = sphere
	marker.position = at

	var material := StandardMaterial3D.new()
	material.albedo_color = (
		Color(0.95, 0.35, 0.25) if on_target else Color(0.15, 0.15, 0.18)
	)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	_markers.add_child(marker)


## Turns the recorded impacts back into angular offsets and writes them in the
## same format the weapon reads, so a measured spray can replace a guessed one
## without any conversion by hand.
func _export_spray() -> void:
	if _impacts.is_empty():
		print("Nothing to export: fire at the wall first.")
		return

	var first: Dictionary = _impacts[0]
	var first_shot: Weapon.Shot = first["shot"]
	var reference := Vector2(first_shot.base_yaw, first_shot.base_pitch)

	var pattern := PackedVector2Array()
	for impact in _impacts:
		var shot: Weapon.Shot = impact["shot"]
		var direction: Vector3 = (impact["position"] as Vector3) - shot.origin
		var angles := PlayerInput.angles_from_direction(direction)
		# x is degrees to the right, and yaw decreases rightward.
		pattern.append(Vector2(reference.x - angles.x, angles.y - reference.y))

	var weapon_name := player.weapon.data.display_name.to_lower().replace("-", "")
	var path := "user://spray_%s.csv" % weapon_name
	var error := RecoilPattern.save_to(
		path, pattern,
		"Measured in the test range at %.0f units on %s" % [
			WALL_DISTANCE, Time.get_datetime_string_from_system()
		]
	)
	if error != OK:
		printerr("Export failed: %d" % error)
		return

	print("Exported %d shots to %s" % [pattern.size(), path])
	print("Real path: %s" % ProjectSettings.globalize_path(path))
	print("To use it, copy it over reference/spray_patterns/<weapon>.csv")


func _reset() -> void:
	_impacts.clear()
	for marker in _markers.get_children():
		marker.queue_free()
	if dummy != null:
		dummy.reset()
	print("Range cleared.")


# --- Construction ---------------------------------------------------------

func _box(
	size: Vector3, centre: Vector3, colour: Color
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = centre

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


func _build_floor() -> void:
	_box(
		Vector3(2048.0, 32.0, 4096.0), Vector3(0.0, -16.0, -1024.0),
		Color(0.42, 0.42, 0.45)
	)


func _build_wall() -> void:
	# Pale, so bullet holes read clearly against it.
	_box(
		Vector3(WALL_SIZE.x, WALL_SIZE.y, 32.0),
		Vector3(0.0, WALL_SIZE.y * 0.5, -WALL_DISTANCE),
		Color(0.80, 0.78, 0.74)
	)
	# A line at eye height, to aim the first shot at.
	_box(
		Vector3(WALL_SIZE.x, 1.0, 1.0),
		Vector3(0.0, 64.0, -WALL_DISTANCE + 16.0),
		Color(0.25, 0.35, 0.50)
	)


func _build_dummy() -> void:
	dummy = HitTarget.new()
	dummy.name = "Dummy"
	dummy.position = Vector3(384.0, 0.0, -DUMMY_DISTANCE)
	add_child(dummy)


func _build_player() -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)
	player.shot_traced.connect(_on_shot)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)

	# A crosshair, since aiming at a wall without one is guesswork.
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.add_theme_color_override("font_outline_color", Color.BLACK)
	crosshair.add_theme_constant_override("outline_size", 4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(crosshair)

	add_child(layer)


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 20.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
