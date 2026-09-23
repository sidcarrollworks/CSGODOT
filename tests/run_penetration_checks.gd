extends "res://tests/check_suite.gd"

## Checks wall penetration: that CS2's surface numbers are read the way the
## game's file gives them, that a round goes through a thin wall of the
## right stuff and comes out with less damage, that a thick one or the wrong
## stuff stops it, that a weaker gun gets through less, and that the other
## side of a wall is found in both kinds of collision the game uses, boxes
## (the range) and triangle meshes (dust2's hull). Then the range: that M
## stands a wall in front of the dummy and a round through it says so.
##
##   godot --headless --path . --script tests/run_penetration_checks.gd
##
## Every wall here is a stand-in named the way dust2's hull names its parts.
## The real walls are only in the extracted hull; run_dust2_checks.gd lists
## what surface each of its parts is taken as.

const RANGE_SCENE := "res://maps/test_range/test_range.tscn"
## Where the target stands, and the walls go between it and the origin.
const TARGET_Z := -256.0
const ORIGIN := Vector3(0.0, 64.0, 0.0)

var _world: Node3D
var _target: HitTarget
var _walls: Array[Node] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_surfaces()
	_test_the_numbers()

	_world = Node3D.new()
	root.add_child(_world)
	_target = HitTarget.new()
	_target.position = Vector3(0.0, 0.0, TARGET_Z)
	_world.add_child(_target)
	await _settle()

	await _test_through_a_door()
	await _test_a_thick_wall_stops_it()
	await _test_a_weaker_gun_gets_through_less()
	await _test_two_walls_with_a_gap()
	await _test_the_most_walls()
	await _test_the_sky_stops_it()
	await _test_someone_in_the_wall()
	await _test_the_range()
	_report()


# --- The numbers ----------------------------------------------------------

func _test_surfaces() -> void:
	var names := {
		"physics_group_wood_plank": "wood_plank", "physics_group_concrete": "concrete",
		"physics_group_sand": "sand", "physics_group_metal_dumpster": "metal_dumpster",
		"physics_group_rubbertire": "rubbertire", "physics_group_solidmetal": "solidmetal",
		"physics_group_metal_dumpster_lid": "metal_dumpster", "physics_group_rubbertire_worn": "rubbertire",
		# As the hull reaches Hitscan: the export's hash for a surface it cannot
		# name, and Godot's number on a repeated part, after a hash too; but a
		# surface whose own name ends in a digit keeps it.
		"physics_group_vrf_unknown_key_2838185980": "metalrailing", "physics_group_vrf_unknown_key_28381859802": "metalrailing",
		"physics_group_wood_plank2": "wood_plank", "physics_group_wood2": "wood", "physics_group_weaponc4": "weaponc4",
		"physics_group_Wood_Crate": "wood_crate", "physics_group": "default",
		"CollisionShape3D": "default", "": "default",
	}
	for hull_name: String in names:
		var got := Penetration.surface_for(hull_name)
		_check(got == names[hull_name], "the hull part %s is CS2's %s (%s)" % [hull_name, names[hull_name], got])
	var in_game_file := 0
	var with_modifiers := 0
	for surface: String in SurfaceProperties.names():
		var row: Dictionary = SurfaceProperties.rows()[surface]
		var game_values := ""
		for column in ["gamematerial", "jumpfactor", "maxspeedfactor", "climbable", "penetration_distance", "penetration_damage", "smoke_through"]:
			game_values += String(row[column])
		if not game_values.is_empty():
			in_game_file += 1
		if not (String(row["penetration_distance"]).is_empty() and String(row["penetration_damage"]).is_empty()):
			with_modifiers += 1
	_check(
		SurfaceProperties.names().size() == 164 and in_game_file == 77 and with_modifiers == 56,
		"all 164 of the game's surfaces are there, the 77 its game file gives values for (and chain, which it names and gives none), 56 of them a round's modifiers (%d, %d, %d)"
			% [SurfaceProperties.names().size(), in_game_file, with_modifiers]
	)


func _test_the_numbers() -> void:
	# Straight from surfaceproperties_game.txt.
	_check(Penetration.modifiers("concrete") == Vector2(0.5, 0.25), "concrete: 0.5 reach, 0.25 damage, as the game gives")
	_check(Penetration.modifiers("wood") == Vector2(0.9, 0.6), "wood: 0.9 and 0.6")
	_check(Penetration.modifiers("default") == Vector2(0.5, 0.5), "default: 0.5 and 0.5")
	# Left out of the file, so taken from the parent.
	var plank := Penetration.modifiers("wood_plank")
	_check(is_equal_approx(plank.x, 0.85) and is_equal_approx(plank.y, 0.6), "a wood plank's own reach (0.85) and wood's damage (0.6): %s" % plank)
	var glass := Penetration.modifiers("glass")
	_check(is_equal_approx(glass.x, 0.99) and is_equal_approx(glass.y, 0.5), "glass's reach and default's damage: %s" % glass)
	# Parents as the game's surfaceproperties.vsurf sets them, where names
	# alone would guess wrong.
	var chain := Penetration.modifiers("chain")
	var dumpster := Penetration.modifiers("metal_dumpster")
	var tree := Penetration.modifiers("wood_tree")
	var stucco := Penetration.modifiers("stucco")
	_check(
		is_equal_approx(chain.y, 0.99) and is_equal_approx(dumpster.x, 0.01) and is_equal_approx(dumpster.y, 0.01)
			and tree == Vector2(0.5, 0.3) and stucco == Vector2(0.5, 0.25),
		"a chain lets through what chain-link does, a dumpster stops a round as a metal barrel does, a tree is dense wood, stucco is concrete (%s, %s, %s, %s)"
			% [chain, dumpster, tree, stucco]
	)
	_check(Penetration.cost(4.0, 0.0) == INF, "a surface the game gives no reach (plastic_solid) cannot be gone through")
	_check(
		is_equal_approx(Penetration.kept(0.0, 0.25, 2.0), 1.0 - Penetration.FLAT_LOSS),
		"even the thinnest wall costs a round its flat share"
	)
	_check(
		Penetration.kept(8.0, 0.6, 2.0) > Penetration.kept(8.0, 0.6, 1.0),
		"a stronger round keeps more through the same wall"
	)
	_check(
		Penetration.kept(4.0, 0.6, 2.0) > Penetration.kept(8.0, 0.6, 2.0),
		"and more through a thinner one"
	)


# --- Rounds through walls -------------------------------------------------

## An AK-47 round at the head through a 4-unit wooden door: through, and
## less damage, by exactly what the door keeps. The same through a door
## made of triangles, as dust2's are.
func _test_through_a_door() -> void:
	for kind in ["box", "mesh"]:
		_clear()
		_target.reset()
		_wall(kind, "physics_group_wood_plank", -128.0, 4.0)
		await _settle()
		var data := WeaponLibrary.ak47()
		var result := _fire(data, &"head")
		_check(result.walls.size() == 1, "%s: the round goes through the door (%d walls)" % [kind, result.walls.size()])
		_check(result.hitbox != null and result.zone == &"head", "%s: and hits the head behind it" % kind)
		if result.walls.is_empty() or result.hitbox == null:
			continue
		var wall := result.walls[0]
		_check(absf(wall.thickness - 4.0) < 0.1, "%s: the door measures 4 units through (%.2f)" % [kind, wall.thickness])
		_check(wall.material == "wood_plank", "%s: and is wood plank (%s)" % [kind, wall.material])
		_check(
			wall.entry.z > wall.exit.z and wall.entry_normal.z > 0.9 and wall.exit_normal.z < -0.9,
			"%s: it went in the near face and out the far one" % kind
		)
		var kept := Penetration.kept(4.0, 0.6, data.penetration_power)
		var clean := data.damage_at(result.distance) * data.head_multiplier * data.armor_penetration
		_check(
			absf(result.damage - clean * kept) < 0.5 and result.damage < clean,
			"%s: %.0f to the head through armour, of %.0f without the door" % [kind, result.damage, clean]
		)


## 16 units of concrete: no rifle round gets through it. The target is
## untouched and the round stops on the wall's face.
func _test_a_thick_wall_stops_it() -> void:
	for kind in ["box", "mesh"]:
		_clear()
		_target.reset()
		_wall(kind, "physics_group_concrete", -128.0, 16.0)
		await _settle()
		var result := _fire(WeaponLibrary.ak47(), &"head")
		_check(
			result.hit and result.hitbox == null and result.walls.is_empty()
				and result.surface == "physics_group_concrete" and absf(result.position.z + 120.0) < 0.1,
			"%s: 16 units of concrete stops an AK-47 round at its face (%s)" % [kind, result.position]
		)
		_check(is_equal_approx(_target.health, _target.max_health), "%s: and the target behind takes nothing" % kind)


## A 12-unit wooden crate: a rifle gets through, an SMG (penetration 1)
## does not.
func _test_a_weaker_gun_gets_through_less() -> void:
	_clear()
	_target.reset()
	_wall("box", "physics_group_wood_crate", -128.0, 12.0)
	await _settle()
	var rifle := _fire(WeaponLibrary.ak47(), &"chest")
	_check(rifle.hitbox != null and rifle.walls.size() == 1, "an AK-47 round gets through a 12-unit crate")
	var mp9 := WeaponLibrary.ak47()
	WeaponVData.apply(mp9, "weapon_mp9")
	_target.reset()
	var smg := _fire(mp9, &"chest")
	_check(
		mp9.penetration_power == 1.0 and smg.hitbox == null and smg.walls.is_empty(),
		"an MP9 round (the game's penetration %.1f) does not" % mp9.penetration_power
	)


## Two thin doors with a gap between them: two walls, each as thick as it
## is, not one wall as thick as both and the gap.
func _test_two_walls_with_a_gap() -> void:
	for kind in ["box", "mesh"]:
		_clear()
		_target.reset()
		_wall(kind, "physics_group_wood_plank", -100.0, 2.0)
		_wall(kind, "physics_group_wood_plank", -108.0, 2.0)
		await _settle()
		var result := _fire(WeaponLibrary.ak47(), &"chest")
		var thicknesses := result.walls.map(func(wall: Hitscan.Wall) -> float: return snappedf(wall.thickness, 0.01))
		_check(
			result.walls.size() == 2 and thicknesses == [2.0, 2.0] and result.hitbox != null,
			"%s: two 2-unit doors 6 units apart are two walls of 2 (%s)" % [kind, thicknesses]
		)
		_check(
			result.walls.size() == 2 and is_equal_approx(result.kept, result.walls[0].kept * result.walls[1].kept),
			"%s: and what gets through is what each lets through, one after the other" % kind
		)


## Five sheets of glass: the round goes through four and stops in the
## fifth.
func _test_the_most_walls() -> void:
	_clear()
	_target.reset()
	for i in 5:
		_wall("box", "physics_group_glass", -60.0 - i * 20.0, 1.0)
	await _settle()
	var result := _fire(WeaponLibrary.ak47(), &"chest")
	_check(
		result.walls.size() == Penetration.MOST_WALLS and result.hitbox == null
			and absf(result.position.z - (-140.0 + 0.5)) < 0.1,
		"a round goes through %d walls at most, and stops at the next (%d, %s)" % [Penetration.MOST_WALLS, result.walls.size(), result.position]
	)


func _test_the_sky_stops_it() -> void:
	_clear()
	_target.reset()
	_wall("box", "physics_group_sky", -128.0, 1.0)
	await _settle()
	var result := _fire(WeaponLibrary.ak47(), &"chest")
	_check(result.walls.is_empty() and result.hitbox == null, "nothing goes through the sky")


## Someone standing half inside a wall is hit inside it: the round does not
## skip the part of them the wall hides.
func _test_someone_in_the_wall() -> void:
	_clear()
	_target.reset()
	# The chest box is 20 deep round z = -256: a 4-unit wall at its middle.
	_wall("box", "physics_group_wood_plank", TARGET_Z, 4.0)
	await _settle()
	var result := _fire(WeaponLibrary.ak47(), &"chest")
	_check(
		result.walls.size() == 0 and result.hitbox != null,
		"the half of them in front of the wall is hit first, as it is nearer"
	)
	_clear()
	_target.reset()
	# A wall from the chest's front face to 2 units in: the round goes into
	# the wall before it meets the chest, and meets it inside.
	_wall("box", "physics_group_wood_plank", TARGET_Z + 12.0, 8.0)
	await _settle()
	result = _fire(WeaponLibrary.ak47(), &"chest")
	_check(
		result.walls.size() == 1 and result.hitbox != null and result.zone == &"chest",
		"one standing in the wall is hit in it (%d walls, %s)" % [result.walls.size(), result.zone]
	)


# --- The range ------------------------------------------------------------

func _test_the_range() -> void:
	_clear()
	_world.queue_free()
	await _settle()
	var range_node := (load(RANGE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(range_node)
	for i in 8:
		await physics_frame
	var cover: CoverPanel = range_node.cover
	var dummy: Bot = range_node.dummy
	_check(cover != null and not cover.standing() and not cover.visible, "the range's dummy has no wall in front of it to begin with")
	range_node.next_cover()
	await _settle()
	_check(cover.standing() and cover.visible and "wooden door" in cover.describe(), "M stands a wooden door in front of it (%s)" % cover.describe())
	_check(
		absf(cover.global_position.z - (dummy.global_position.z + CoverPanel.IN_FRONT)) < 0.1
			and absf(cover.global_position.x - dummy.global_position.x) < 0.1,
		"between it and the firing spot"
	)
	_check("wall in front: wooden door" in range_node.dummy_readout(), "the readout says what the wall is")

	var player: PlayerController = range_node.player
	var data: WeaponData = player.weapon.data.duplicate()
	var origin := Vector3(range_node.dummy_position().x, 64.0, 0.0)
	var aim := dummy.global_position + Vector3.UP * 50.0
	for hitbox in dummy.hit_target.hitboxes():
		if hitbox.zone == &"chest":
			aim = hitbox.global_position
			break
	var shot := Weapon.Shot.new()
	shot.origin = origin
	shot.direction = (aim - origin).normalized()
	var result := Hitscan.fire_at(range_node.get_world_3d().direct_space_state, shot, data, player.hit_target.rids())
	player.shot_traced.emit(shot, result)
	_check(result.walls.size() == 1 and result.hitbox != null, "a round at the dummy's chest goes through the door into it")
	var lines: PackedStringArray = range_node.log_lines()
	_check(
		lines.size() >= 1 and "through Wood_Plank 4 u, kept" in lines[0],
		"the log says what it went through and what that let through (%s)" % (lines[0] if lines.size() > 0 else "")
	)

	# Round to the concrete wall at the end of the list, which stops it.
	while "concrete wall" not in cover.describe():
		range_node.next_cover()
	await _settle()
	var before: float = dummy.hit_target.health
	result = Hitscan.fire_at(range_node.get_world_3d().direct_space_state, shot, data, player.hit_target.rids())
	_check(result.hitbox == null and dummy.hit_target.health == before, "16 units of concrete keeps the dummy safe")
	range_node.next_cover()
	await _settle()
	_check(not cover.standing(), "and M once more takes the wall away")
	range_node.queue_free()


# --- Harness --------------------------------------------------------------

## A wall across the line of fire, its middle at z, so many units thick,
## with its collision named as a hull part is. A box, as the range builds them, or a triangle mesh, as dust2's
## hull is.
func _wall(kind: String, hull_name: String, z: float, thickness: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 64.0, z)
	var collision := CollisionShape3D.new()
	collision.name = hull_name
	var size := Vector3(256.0, 256.0, thickness)
	if kind == "box":
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	_walls.append(body)


func _clear() -> void:
	for wall in _walls:
		wall.queue_free()
	_walls.clear()


func _settle() -> void:
	for i in 3:
		await physics_frame


## A round with no spread from the origin at the middle of a zone.
func _fire(data: WeaponData, zone: StringName) -> Hitscan.Result:
	var at := _target.global_position + Vector3(0.0, HitTarget.ZONES[zone]["centre"], 0.0)
	var shot := Weapon.Shot.new()
	shot.origin = ORIGIN
	shot.direction = (at - ORIGIN).normalized()
	return Hitscan.fire_at(_world.get_world_3d().direct_space_state, shot, data)


func _report() -> void:
	_finish("penetration")


func _print_passes() -> bool:
	return true
