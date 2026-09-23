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
## it goes down, then stands up again where it was, whole. M stands a wall
## in front of it, one of CS2's surfaces at a thickness, to shoot it
## through: the log says what the wall let through.
##
## And a shooter, to feel being shot: a bot off to the left of the wall
## that holds its fire until I, then fires at you in bursts like a dust2
## bot. U changes its weapon, among them an MP9 for a tag that stops you
## dead; Y changes your armour, J keeps you alive. The readout in the
## bottom left says what a hit did to you (your speed, the tag, the
## flinch), the arcs round the crosshair say where it came from, and T
## shows your own body and its hitboxes from the front or the side, in a
## window of their own, to check them against how you stand, crouch and
## jump.

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

## Where the shooter stands: left of the wall and back, clear of it and of
## the dummy's lane, about 780 units from the spawn, facing it.
const SHOOTER_POSITION := Vector3(-640.0, 0.0, -448.0)

## The hitbox window's views of you, and how far off it stands.
const HITBOX_VIEWS := ["off", "front", "side"]
const HITBOX_VIEW_DISTANCE := 110.0

## How many hits the readout keeps.
const LOG_LINES := 10

## The colour a damage number is drawn in: a head's stands out.
const NUMBER_COLOUR := Color(1.0, 1.0, 1.0)
const HEAD_NUMBER_COLOUR := Color(1.0, 0.3, 0.2)

## What runs the range's players every tick: the dummy, you, the shooter.
var world: GameWorld
## The range's shared game (world.game): its events, entities, roster and
## inventories, where grenades, the bomb and buying add their systems.
var game: GameSystems
var player: PlayerController
var dummy: Bot
var shooter: Bot
var damage_indicator: DamageIndicator
var hitbox_camera: Camera3D
var cover: CoverPanel

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

var _shooter_weapon_index: int = 0
var _player_armour_index: int = 0
var _hitbox_view_index: int = 0
var _you_label: Label
var _hitbox_window: SubViewportContainer
## The hits you have taken, newest first, as the readout shows them.
var _taken: PackedStringArray = PackedStringArray()


func _ready() -> void:
	world = GameWorld.new()
	world.name = "World"
	add_child(world)
	game = world.game
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
	_build_cover()
	_build_player()
	_build_shooter()
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
	elif event.is_action_pressed(&"shooter_fire"):
		toggle_shooter()
	elif event.is_action_pressed(&"shooter_weapon"):
		next_shooter_weapon()
	elif event.is_action_pressed(&"player_armour"):
		next_player_armour()
	elif event.is_action_pressed(&"player_immortal"):
		toggle_player_immortal()
	elif event.is_action_pressed(&"hitbox_camera"):
		next_hitbox_view()
	elif event.is_action_pressed(&"dummy_cover"):
		next_cover()


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
		"M      a wall in front of the dummy",
		"I      shooter fires    U  its weapon",
		"Y      your armour      J  you never die",
		"T      your hitboxes: front, side, off",
	])
	_dummy_label.text = dummy_readout()
	_you_label.text = you_readout()
	_place_hitbox_camera()


## Records every shot the player takes, and marks the ones that hit the wall.
## A round into the dummy also says what it did, where it landed and in the
## log.
func _on_shot(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	if not result.touched():
		return
	# The spray reads where each round first met the wall, even one that
	# went through it.
	_impacts.append({"shot": shot, "position": result.first_contact()})
	for wall in result.walls:
		_add_marker(wall.entry, false)
	if result.hit:
		_add_marker(result.position, result.hitbox != null)
	if dummy != null and result.hitbox != null and result.hitbox.target == dummy.hit_target:
		_on_dummy_hit(shot, result)


func _on_dummy_hit(shot: Weapon.Shot, result: Hitscan.Result) -> void:
	var target := dummy.hit_target
	var data := player.weapon.data
	# What the round carried before armour: the weapon's damage at that
	# range, times the zone's, less what any wall on the way took. What it
	# did is what the target took.
	var raw := data.damage_at(result.distance) * data.hitbox_multiplier(result.zone) * result.kept
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
		"through": _walls_text(result),
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
		"wall in front: %s" % (cover.describe() if cover != null else "no wall"),
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
	var walls: String = hit.get("through", "")
	return "%3d  %-10s %s %4.0f u%s  -> %d%s" % [
		roundi(hit["dealt"]), zone, hit["weapon"], hit["distance"], through, roundi(hit["remaining"]),
		("\n       " + walls) if not walls.is_empty() else "",
	]


## The walls a round went through, and what each let through: "through
## Wood_Plank 4 u, kept 70%".
static func _walls_text(result: Hitscan.Result) -> String:
	var parts := PackedStringArray()
	for wall in result.walls:
		parts.append("%s %.0f u, kept %d%%" % [
			Penetration.display_name(wall.material), wall.thickness, roundi(wall.kept * 100.0),
		])
	return ("through " + ", then ".join(parts)) if not parts.is_empty() else ""


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


# --- Being shot ------------------------------------------------------------

## The shooter's choices: both rifles, and an MP9 for an SMG's tag. The MP9
## is every number the game has for it (damage, rate, 100% tagging, its
## reload), with the sheet's landing and ladder as the rifles have, on the
## AK-47's spray, since its own pattern has not been measured, in the
## AK-47's model.
static func shooter_weapons() -> Array[WeaponData]:
	var mp9 := WeaponLibrary.ak47()
	WeaponSheet.apply(mp9, "MP9")
	WeaponVData.apply(mp9, "weapon_mp9")
	mp9.display_name = "MP9"
	return [WeaponLibrary.ak47(), WeaponLibrary.m4a1s(), mp9]


## What being hit does to you, and who is shooting.
func you_readout() -> String:
	if player == null:
		return ""
	var target := player.hit_target
	var lines := PackedStringArray([
		"YOU   %s   %s" % [
			ARMOUR[_player_armour_index]["name"],
			"never die: a kill refills you" if target.immortal else "you can die",
		],
		("health %d    armour %d" % [roundi(target.health), roundi(target.armor)]) if player.alive
			else "dead, back in %.1f s" % player.seconds_to_respawn(),
		# The tag: how much of your top speed you may have, and have.
		"tag    %3d%% of top speed  %s   (moving %.0f of %.0f u/s)" % [
			roundi(player.velocity_modifier * 100.0),
			"slowed" if player.velocity_modifier < 1.0 else "free",
			Vector2(player.velocity.x, player.velocity.z).length(), player.config.max_speed,
		],
		"flinch %.2f deg up, %.2f aside" % [player.hit_punch.value.y, -player.hit_punch.value.x],
		"SHOOTER  %s, %s" % [
			shooter.weapon_data.display_name if shooter != null else "-",
			"holding fire" if shooter == null or shooter.holds_fire
				else ("dead" if not shooter.alive else ("firing at you" if shooter.target == player else "looking for you")),
		],
		"",
	])
	lines.append_array(_taken)
	return "\n".join(lines)


## A bot in the corner, armed, facing the spawn, that holds its fire until
## told.
func _build_shooter() -> void:
	shooter = (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	shooter.name = "Shooter"
	shooter.team = "CT" if player.team == "T" else "T"
	shooter.holds_fire = true
	shooter.weapon_data = shooter_weapons()[_shooter_weapon_index]
	shooter.weapon_model = shooter.weapon_data.model_path
	shooter.position = SHOOTER_POSITION
	var to_spawn := -SHOOTER_POSITION
	# The game's yaw 0 looks down -Z, and yaw grows towards -X.
	shooter.yaw_degrees = rad_to_deg(atan2(-to_spawn.x, -to_spawn.z))
	add_child(shooter)
	world.add_player(shooter)
	shooter.place(SHOOTER_POSITION, shooter.yaw_degrees)
	var colour := Color(0.9, 0.3, 0.25)
	_mark(Vector3(48.0, 0.2, 48.0), SHOOTER_POSITION + Vector3(0.0, 0.1, 0.0), colour)
	_text("shooter: I to fire, U its weapon", SHOOTER_POSITION + Vector3(0.0, 96.0, 0.0), colour)


func toggle_shooter() -> void:
	shooter.holds_fire = not shooter.holds_fire
	if shooter.holds_fire:
		# Stops mid-burst, and turns back to where it waits.
		shooter.target = null


func next_shooter_weapon() -> void:
	_shooter_weapon_index = (_shooter_weapon_index + 1) % shooter_weapons().size()
	shooter.arm(shooter_weapons()[_shooter_weapon_index])


func next_player_armour() -> void:
	_player_armour_index = (_player_armour_index + 1) % ARMOUR.size()
	var armour: Dictionary = ARMOUR[_player_armour_index]
	player.hit_target.wear(armour["armor"], armour["helmet"])


func toggle_player_immortal() -> void:
	player.hit_target.immortal = not player.hit_target.immortal


## A hit on you: an arc on the side it came from, a line in the readout,
## and whole again if you are not to die.
func _on_player_hurt(amount: float, zone: StringName, from: Vector3) -> void:
	damage_indicator.hit_from(from)
	var data := player.hit_target.last_hit_weapon
	_taken.insert(0, "%3d  %-8s %s %4.0f u%s  -> %d, tagged to %d%%" % [
		roundi(amount), zone, data.display_name if data != null else "?",
		player.global_position.distance_to(from),
		"  through armour" if player.hit_target.last_hit_armored else "",
		roundi(player.hit_target.health),
		roundi(clampf(1.0 - data.tagging_power, 0.0, 1.0) * 100.0) if data != null else 100,
	])
	if _taken.size() > 6:
		_taken.resize(6)
	if player.hit_target.immortal and player.hit_target.health <= 0.0:
		player.hit_target.reset()


## Off, a view of you from the front, or from your side: your body and its
## hitboxes as the bots' rounds meet them, which your own camera leaves out.
func next_hitbox_view() -> void:
	_hitbox_view_index = (_hitbox_view_index + 1) % HITBOX_VIEWS.size()
	_hitbox_window.visible = _hitbox_view_index != 0
	_place_hitbox_camera()


func hitbox_view() -> String:
	return HITBOX_VIEWS[_hitbox_view_index]


func _place_hitbox_camera() -> void:
	if hitbox_camera == null or _hitbox_view_index == 0 or player == null:
		return
	var yaw := deg_to_rad(player.yaw_degrees)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var feet := player.global_position
	var side := forward if hitbox_view() == "front" else right
	hitbox_camera.global_position = feet + side * HITBOX_VIEW_DISTANCE + Vector3.UP * 44.0
	hitbox_camera.look_at(feet + Vector3.UP * 36.0, Vector3.UP)


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
	if cover != null:
		cover.stand_before(dummy_position())
	dummy.previous_position = dummy.global_position
	dummy.velocity = Vector3.ZERO
	# The game's yaw 0 looks down -Z; 180 looks back up the lane.
	dummy.yaw_degrees = 180.0


## The wall that M stands in front of the dummy, down its lane with it.
func _build_cover() -> void:
	cover = CoverPanel.new()
	cover.name = "Cover"
	add_child(cover)
	cover.stand_before(dummy_position())


func next_cover() -> void:
	cover.next()
	_push_log("-- wall in front: %s" % cover.describe())


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
	world.add_player(dummy)
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
	world.add_player(player)
	player.place(Vector3(0.0, 8.0, 0.0), 0.0)
	player.shot_traced.connect(_on_shot)
	player.hurt.connect(_on_player_hurt)
	# Your hitboxes are drawn, on the layer only the hitbox window sees.
	player.hit_target.set_hitboxes_drawn(true)


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

	_you_label = Label.new()
	_you_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_you_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_you_label.offset_left = 24.0
	_you_label.offset_bottom = -24.0
	_you_label.add_theme_font_size_override("font_size", 18)
	_you_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_you_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_you_label)

	damage_indicator = DamageIndicator.new()
	damage_indicator.player = player
	layer.add_child(damage_indicator)

	# Your body and hitboxes, from outside, in the bottom right: the world
	# and the layer only this camera takes in, and not the bodies the view
	# and the bots draw.
	_hitbox_window = SubViewportContainer.new()
	_hitbox_window.stretch = true
	_hitbox_window.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hitbox_window.offset_left = -344.0
	_hitbox_window.offset_top = -444.0
	_hitbox_window.offset_right = -24.0
	_hitbox_window.offset_bottom = -24.0
	_hitbox_window.visible = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 420)
	_hitbox_window.add_child(viewport)
	hitbox_camera = Camera3D.new()
	hitbox_camera.cull_mask = 1 | PlayerSim.UNSEEN_LAYER
	hitbox_camera.fov = 50.0
	hitbox_camera.near = 1.0
	hitbox_camera.far = 8192.0
	viewport.add_child(hitbox_camera)
	layer.add_child(_hitbox_window)

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
