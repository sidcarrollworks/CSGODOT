extends Node3D

## The spray pattern range, and the place to check what a round does to a
## body.
##
## This is the tuning instrument for shooting, the way the movement course is
## for movement. Fire a magazine at the wall, look at the holes, compare
## against a reference image, and export what you got as a pattern file.
##
## The export is the important part. CS2's recoil data cannot be extracted, so
## patterns have to be measured, and a measurement is only useful if it can go
## straight back into the file the weapon reads. Press P and it does.
##
## Beside the wall is a lane with a dummy in it: a bot, the same body and
## hitboxes the bots on dust2 wear, that stands still and does not shoot
## back. Its hitboxes are drawn over it, each round says what it did where it
## landed, and the readout keeps a log of the hits and of each kill. Killed,
## it goes down, then stands up again where it was, whole.

## Distance from the firing line to the wall. Spray references are usually
## drawn at a fixed distance, so this needs to match whatever you compare
## against, and it is the first thing to change if the pattern looks the right
## shape but the wrong size.
const WALL_DISTANCE := 512.0
const WALL_THICKNESS := 32.0

const WALL_SIZE := Vector2(768.0, 512.0)

## The standing eye height the angle grid is drawn from (MovementConfig's).
const EYE_HEIGHT := 64.0
## The grid's spacing in degrees, and every how many lines one is bold.
const GRID_STEP_DEGREES := 1.0
const GRID_BOLD_EVERY := 5

## The dummy's lane runs parallel to the range beside the wall, so nothing
## stands between its firing spot and the dummy at any distance. The
## distances are measured from that spot, and N steps through them.
const LANE_X := 512.0
const DUMMY_DISTANCES := [256.0, 512.0, 1024.0, 2048.0]
const DUMMY_DISTANCE_START := 1
## How long the dummy stays down before it stands up again.
const DUMMY_RESPAWN_SECONDS := 2.5

## What the dummy wears, and K steps through it. An opponent in a rifle
## round has kevlar and a helmet, so that is where it starts.
const ARMOUR := [
	{"name": "kevlar + helmet", "armor": 100.0, "helmet": true},
	{"name": "kevlar, no helmet", "armor": 100.0, "helmet": false},
	{"name": "no armour", "armor": 0.0, "helmet": false},
]

## How many hits the readout keeps.
const LOG_LINES := 10

## The colour a damage number is drawn in: a head's stands out.
const NUMBER_COLOUR := Color(1.0, 1.0, 1.0)
const HEAD_NUMBER_COLOUR := Color(1.0, 0.3, 0.2)

var player: PlayerController
var dummy: Bot

var _impacts: Array = []
var _markers: Node3D
var _numbers: Node3D
var _label: Label
var _dummy_label: Label
var _crosshair: Crosshair

## What the dummy's hitboxes are, for the readout: the game's capsules, or
## the stand-in boxes and why.
var hitbox_source: String = ""

var _distance_index: int = DUMMY_DISTANCE_START
var _armour_index: int = 0
## The dummy's current life: its hits, in order, as dictionaries of what the
## readout shows.
var _life: Array[Dictionary] = []
var _log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_markers = Node3D.new()
	_markers.name = "Impacts"
	add_child(_markers)
	_numbers = Node3D.new()
	_numbers.name = "DamageNumbers"
	add_child(_numbers)

	_build_lighting()
	_build_floor()
	_build_wall()
	_build_angle_grid()
	_build_lane()
	_build_dummy()
	_build_player()
	_build_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"export_spray"):
		_export_spray()
	elif event.is_action_pressed(&"reset_range"):
		_reset()
	elif event.is_action_pressed(&"toggle_hitboxes"):
		toggle_hitboxes()
	elif event.is_action_pressed(&"dummy_armour"):
		next_armour()
	elif event.is_action_pressed(&"dummy_distance"):
		next_distance()
	elif event.is_action_pressed(&"dummy_immortal"):
		toggle_immortal()


func _process(_delta: float) -> void:
	if player == null or player.weapon == null:
		return
	var weapon := player.weapon
	var state := player.shooter_state
	var cone := weapon.current_inaccuracy(state)
	# The cone drawn round the crosshair, so moving, stopping and
	# counter-strafing can be watched opening and closing it.
	_crosshair.spread_degrees = cone
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_crosshair.fov_degrees = camera.fov
	_label.text = "\n".join([
		"%s" % weapon.data.display_name,
		"ammo       %d / %d" % [weapon.ammo, weapon.reserve],
		"shot       %d" % weapon.shot_index(),
		"cone       %.3f deg  %s" % [
			cone,
			"ready" if weapon.is_accuracy_reset() else "recovering",
		],
		# Moving costs nothing under a third of the weapon's top speed.
		"speed      %.0f u/s  %s" % [
			state.speed,
			"accurate" if state.speed <= weapon.data.max_player_speed * Weapon.MOVING_FROM
			else "moving, cone open",
		],
		# Side by side on purpose. The gun stops moving before the cone
		# closes, so these two disagree for a couple of hundred milliseconds
		# after every shot, which is what CS2 does and is why the animation
		# cannot be used to time a tap.
		"view       %.2f deg  %s" % [
			weapon.aim_punch.length(),
			"still" if weapon.aim_punch.length() < 0.01 else "moving",
		],
		"impacts    %d" % _impacts.size(),
		"",
		"1 / 2  weapon      R  reload",
		"P      export      O  clear",
		"H      hitboxes    K  armour",
		"N      dummy distance   G  dummy never dies",
	])
	_dummy_label.text = dummy_readout()


## Records every shot the player takes, and marks the ones that hit the wall.
## A round into the dummy also says what it did, where it landed and in the
## log.
func _on_shot(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	if not result.hit:
		return
	_impacts.append({"shot": shot, "position": result.position})
	_add_marker(result.position, result.hitbox != null)
	if dummy != null and result.hitbox != null and result.hitbox.target == dummy.hit_target:
		_on_dummy_hit(shot, result)


func _on_dummy_hit(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	var target := dummy.hit_target
	var data := player.weapon.data
	# What the round carried before armour: the weapon's damage at that
	# range, times the zone's. What it did is what the target took.
	var raw := data.damage_at(result.distance) * data.hitbox_multiplier(result.zone)
	# Health can only go down so far: what the round took is what there was
	# before it, less what is left.
	var health_before: float = _life[-1]["remaining"] if not _life.is_empty() else target.max_health
	var hit := {
		"zone": result.zone,
		"side": result.hitbox.side,
		"dealt": result.damage,
		"raw": raw,
		"given": health_before - target.health,
		"remaining": target.health,
		"distance": result.distance,
		"weapon": data.display_name,
		"usec": shot.timestamp_usec,
	}
	_life.append(hit)
	result.hitbox.flash()
	_add_number(result.position, result.damage, result.zone)
	_push_log(_hit_line(hit))
	if target.health <= 0.0:
		_push_log(_kill_line())
		if target.immortal:
			# Would have died: counted, and whole again for the rest of the
			# spray.
			target.reset()
			_life.clear()


## The dummy's state and the log, for the readout.
func dummy_readout() -> String:
	if dummy == null:
		return ""
	var target := dummy.hit_target
	var lines := PackedStringArray([
		"DUMMY   lane %.0f u, %.0f u from you   %s" % [
			DUMMY_DISTANCES[_distance_index],
			player.global_position.distance_to(dummy.global_position) if player != null else 0.0,
			ARMOUR[_armour_index]["name"],
		],
		("health  %d    armour  %d" % [roundi(target.health), roundi(target.armor)]) if dummy.alive
			else "down, up again in %.1f s" % dummy.seconds_to_respawn(),
		"%s, %s" % [hitbox_source, "drawn" if target.hitboxes_drawn() else "hidden"],
		"never dies: a kill refills it" if target.immortal else "dies, and is back in %.1f s" % DUMMY_RESPAWN_SECONDS,
		"",
	])
	lines.append_array(_log)
	return "\n".join(lines)


func _hit_line(hit: Dictionary) -> String:
	var zone := String(hit["zone"])
	if hit["side"] != &"":
		zone = "%s %s" % [hit["side"], zone]
	var through := ""
	if absf(hit["raw"] - hit["dealt"]) > 0.01:
		through = "  (%.0f before armour)" % hit["raw"]
	return "%3d  %-10s %s %4.0f u%s  -> %d" % [
		roundi(hit["dealt"]), zone, hit["weapon"], hit["distance"], through, roundi(hit["remaining"]),
	]


## A kill's summary: how many rounds it took, how much of its health they
## took, and the time from the first of them to the last.
func _kill_line() -> String:
	var given := 0.0
	var heads := 0
	for hit in _life:
		given += hit["given"]
		if hit["zone"] == &"head":
			heads += 1
	var milliseconds := float(_life[-1]["usec"] - _life[0]["usec"]) / 1000.0
	return "KILLED  %d damage in %d hit%s%s, %.0f ms first to last" % [
		roundi(given), _life.size(), "" if _life.size() == 1 else "s",
		(", %d to the head" % heads) if heads > 0 else "", milliseconds,
	]


func _push_log(line: String) -> void:
	_log.insert(0, line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)


func log_lines() -> PackedStringArray:
	return _log


## The damage a round did, beside where it landed, rising and fading. It is
## drawn the same size at any distance and beside the hit rather than on it,
## so it never covers the body being shot at.
func _add_number(at: Vector3, amount: float, zone: StringName) -> void:
	var label := Label3D.new()
	label.text = "%d" % roundi(amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0008
	label.font_size = 40
	label.outline_size = 10
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = HEAD_NUMBER_COLOUR if zone == &"head" else NUMBER_COLOUR
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.render_priority = 2
	label.outline_render_priority = 1
	# Numbers from one spray would sit on each other; each starts a little
	# higher than the last, in a short cycle.
	var step := _numbers.get_child_count() % 4
	label.position = at
	label.offset = Vector2(40.0 + step * 16.0, step * 44.0)
	_numbers.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "offset:y", label.offset.y + 60.0, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.6).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


func toggle_hitboxes() -> void:
	if dummy != null:
		dummy.hit_target.set_hitboxes_drawn(not dummy.hit_target.hitboxes_drawn())


## Whether the dummy dies or takes a whole spray: a kill still shows in
## the log either way.
func toggle_immortal() -> void:
	dummy.hit_target.immortal = not dummy.hit_target.immortal
	_push_log("-- %s" % ("never dies" if dummy.hit_target.immortal else "dies again"))


func next_armour() -> void:
	_armour_index = (_armour_index + 1) % ARMOUR.size()
	_wear_armour()
	_push_log("-- now wearing %s" % ARMOUR[_armour_index]["name"])


func next_distance() -> void:
	_distance_index = (_distance_index + 1) % DUMMY_DISTANCES.size()
	_place_dummy()
	_push_log("-- moved to %.0f u" % DUMMY_DISTANCES[_distance_index])


func _wear_armour() -> void:
	var armour: Dictionary = ARMOUR[_armour_index]
	dummy.hit_target.wear(armour["armor"], armour["helmet"])


## Where the dummy stands: down its lane at the current distance, facing the
## firing spot.
func dummy_position() -> Vector3:
	return Vector3(LANE_X, 0.0, -DUMMY_DISTANCES[_distance_index])


func _place_dummy() -> void:
	dummy.global_position = dummy_position()
	dummy.previous_position = dummy.global_position
	dummy.velocity = Vector3.ZERO
	# The game's yaw 0 looks down -Z; 180 looks back up the lane.
	dummy.yaw_degrees = 180.0


func _on_dummy_respawned() -> void:
	_place_dummy()
	_life.clear()


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
	for number in _numbers.get_children():
		number.queue_free()
	_log.clear()
	if dummy != null:
		dummy.respawn()
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


## Something to see with nothing to hit: a mark on a surface.
func _mark(size: Vector3, centre: Vector3, colour: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = centre
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance


## Words in the world, eight units tall, facing back down the range.
func _text(words: String, at: Vector3, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = 32
	label.pixel_size = 0.25
	label.modulate = colour
	label.outline_size = 0
	label.position = at
	label.shaded = false
	label.double_sided = false
	add_child(label)
	return label


func _build_floor() -> void:
	_box(
		Vector3(2048.0, 32.0, 4096.0), Vector3(0.0, -16.0, -1024.0),
		Color(0.42, 0.42, 0.45)
	)


func _build_wall() -> void:
	# Pale, so bullet holes read clearly against it.
	_box(
		Vector3(WALL_SIZE.x, WALL_SIZE.y, WALL_THICKNESS),
		Vector3(0.0, WALL_SIZE.y * 0.5, -WALL_DISTANCE),
		Color(0.80, 0.78, 0.74)
	)
	# The line at eye height to aim the first shot at is the angle grid's
	# zero (_build_angle_grid).


## Lines on the wall at every degree from the spawn's eye, bold every five
## and numbered: up and down from the aim line, left and right from the
## centre. A spray fired from the spawn reads off in degrees, and so does a
## CS2 spray fired at a wall from the same distance, so the two can be put
## side by side without knowing either's scale.
func _build_angle_grid() -> void:
	var face := WALL_DISTANCE - WALL_THICKNESS * 0.5
	var z := -face + 0.3
	var half_width := WALL_SIZE.x * 0.5 - 4.0
	var top := WALL_SIZE.y - 4.0
	var faint := Color(0.45, 0.50, 0.58)
	var bold := Color(0.20, 0.28, 0.42)

	var step := 0
	while true:
		var degrees := step * GRID_STEP_DEGREES
		var x := face * tan(deg_to_rad(degrees))
		if x > half_width:
			break
		var is_bold := step % GRID_BOLD_EVERY == 0
		for side in ([1.0] if step == 0 else [1.0, -1.0]):
			_mark(
				Vector3(1.2 if is_bold else 0.5, WALL_SIZE.y, 0.2),
				Vector3(side * x, WALL_SIZE.y * 0.5, z), bold if is_bold else faint
			)
			if is_bold and step > 0:
				_text("%d" % roundi(degrees), Vector3(side * x + 4.0, 12.0, z + 0.1), bold)
		step += 1

	step = 0
	while true:
		var degrees := step * GRID_STEP_DEGREES
		var up := EYE_HEIGHT + face * tan(deg_to_rad(degrees))
		var down := EYE_HEIGHT - face * tan(deg_to_rad(degrees))
		if up > top and down < 4.0:
			break
		var is_bold := step % GRID_BOLD_EVERY == 0
		for y in ([up] if step == 0 else [up, down]):
			if y > top or y < 4.0:
				continue
			_mark(
				Vector3(WALL_SIZE.x, 1.2 if is_bold else 0.5, 0.2),
				Vector3(0.0, y, z), bold if is_bold else faint
			)
			if is_bold and step > 0:
				_text("%d" % roundi(degrees if y > EYE_HEIGHT else -degrees), Vector3(-half_width + 10.0, y + 4.0, z + 0.1), bold)
		step += 1
	_text("degrees from the spawn's eye, %.0f u" % face, Vector3(0.0, top - 10.0, z + 0.1), bold)


## The dummy's lane: a spot to fire from, and a line across the floor at
## each distance it can stand at, with the distance on a sign beside it.
func _build_lane() -> void:
	var colour := Color(0.85, 0.75, 0.30)
	_mark(Vector3(48.0, 0.2, 48.0), Vector3(LANE_X, 0.1, 0.0), colour)
	_text("fire from here for the dummy", Vector3(LANE_X + 96.0, 24.0, -32.0), colour)
	for distance: float in DUMMY_DISTANCES:
		_mark(Vector3(96.0, 0.2, 2.0), Vector3(LANE_X, 0.1, -distance), colour)
		var sign_text := _text(
			"%.0f u\n%.1f m" % [distance, distance * 0.0254],
			Vector3(LANE_X + 160.0, 16.0, -distance), colour
		)
		# Farther signs are bigger, so each reads from the firing spot.
		sign_text.pixel_size *= clampf(distance / 512.0, 1.0, 3.0)


## A bot with nothing to shoot with and no route: it stands where it is put
## and faces the way it is turned. It wears the character model and the
## game's own hitboxes on its bones where they have been extracted, and the
## four standard boxes with a grey body where they have not.
func _build_dummy() -> void:
	dummy = (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	dummy.name = "Dummy"
	dummy.team = "CT"
	dummy.weapon_model = WeaponLibrary.m4a1s().model_path
	dummy.respawn_seconds = DUMMY_RESPAWN_SECONDS
	dummy.position = dummy_position()
	dummy.yaw_degrees = 180.0
	add_child(dummy)
	hitbox_source = dummy.hitbox_source()
	# Without the capsules the bot wears the four standard boxes (PlayerSim).
	if dummy.hitboxes_missing():
		# A model without its hitboxes is a broken extraction, not a fresh
		# clone: say so where it will be seen.
		push_warning("Test range dummy: %s" % hitbox_source)
	_wear_armour()
	dummy.hit_target.set_hitboxes_drawn(true)
	dummy.respawned.connect(_on_dummy_respawned)


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

	# A crosshair, since aiming at a wall without one is guesswork. The centre
	# dot is on here because this is the range where the question being asked
	# is whether a bullet went exactly where it was aimed.
	_crosshair = Crosshair.new()
	_crosshair.centre_dot = true
	layer.add_child(_crosshair)

	_dummy_label = Label.new()
	_dummy_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_dummy_label.offset_left = -620.0
	_dummy_label.offset_right = -24.0
	_dummy_label.offset_top = 24.0
	_dummy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dummy_label.add_theme_font_size_override("font_size", 18)
	_dummy_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_dummy_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_dummy_label)

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
