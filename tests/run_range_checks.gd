extends SceneTree

## Checks the test range's dummy: that it stands in its lane wearing drawn
## hitboxes, that a round into it says what it did, that armour and the
## helmet change that the way CS does, and that a killed dummy comes back
## whole where it stood.
##
##   godot --headless --path . --script tests/run_range_checks.gd
##
## Without the extracted character the dummy wears the four standard boxes
## instead of the game's capsules; everything here holds for either.

const RANGE_SCENE := "res://maps/test_range/test_range.tscn"

var _failures: int = 0
var _checks: int = 0
var _range: Node3D
var _clock_usec: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_range = (load(RANGE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_range)
	for i in 8:
		await physics_frame

	var dummy: Bot = _range.dummy
	_check(dummy != null and dummy.weapon == null and dummy.route.is_empty(), "the dummy is a bot with nothing to shoot with and nowhere to go")
	if dummy == null:
		_report()
		return
	dummy.respawn_seconds = 0.05
	var hitboxes := dummy.hit_target.hitboxes()
	_check(hitboxes.size() == 4 or hitboxes.size() == 19, "it wears hitboxes (%d)" % hitboxes.size())
	_check(
		hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.is_drawn()),
		"every one of them is drawn"
	)
	_check(
		dummy.global_position.distance_to(_range.dummy_position()) < 1.0
			and absf(dummy.global_position.z + 512.0) < 1.0,
		"it stands down its lane, 512 units from the firing spot (%s)" % dummy.global_position
	)
	_check(
		dummy.hit_target.armor == 100.0 and dummy.hit_target.helmet,
		"it wears kevlar and a helmet, as in a rifle round"
	)
	var drawn := _find_drawn(hitboxes[0])
	_check(drawn != null and drawn.mesh != null, "a drawn hitbox has a mesh the shape of its collision")

	var data: WeaponData = _range.player.weapon.data
	# A round to the chest: through the kevlar, for the armour's share.
	var chest := _shoot(_zone_point(dummy, &"chest"))
	_check(chest.hitbox != null and chest.zone == &"chest", "a round at the chest hits the chest (%s)" % chest.zone)
	var raw := data.damage_at(chest.distance) * data.hitbox_multiplier(&"chest")
	_check(
		is_equal_approx(chest.damage, raw * data.armor_penetration)
			and is_equal_approx(dummy.hit_target.health, 100.0 - chest.damage),
		"through kevlar it does %.0f of %.0f, and the dummy has %.0f left" % [chest.damage, raw, dummy.hit_target.health]
	)
	var lines: PackedStringArray = _range.log_lines()
	_check(
		lines.size() == 1 and "chest" in lines[0] and ("before armour" in lines[0]),
		"the log says where it landed and what it carried before the armour (%s)" % (lines[0] if lines.size() > 0 else "")
	)
	await process_frame
	_check(
		_range.get_node("DamageNumbers").get_child_count() == 1
			and (_range.get_node("DamageNumbers").get_child(0) as Label3D).text == "%d" % roundi(chest.damage),
		"the damage rises from where the round landed"
	)

	# A round to the head through the helmet kills.
	var head := _shoot(_zone_point(dummy, &"head"))
	_check(
		head.zone == &"head" and head.damage > 100.0 - chest.damage and not dummy.alive,
		"a round to the head through the helmet finishes it (%.0f)" % head.damage
	)
	lines = _range.log_lines()
	_check(
		lines.size() >= 3 and lines[0].begins_with("KILLED  100 damage in 2 hits") and "1 to the head" in lines[0],
		"the kill is summed up: all its health in two hits, one to the head (%s)" % (lines[0] if lines.size() > 0 else "")
	)
	_check(
		hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.collision_layer == 0),
		"down, it cannot be shot"
	)

	for i in 30:
		await physics_frame
		if dummy.alive:
			break
	await physics_frame
	_check(
		dummy.alive and is_equal_approx(dummy.hit_target.health, 100.0) and dummy.hit_target.armor == 100.0
			and dummy.global_position.distance_to(_range.dummy_position()) < 1.0
			and hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.collision_layer == Hitbox.LAYER),
		"it stands up again where it was, whole, and can be shot"
	)

	# No helmet: the head takes the whole round, the chest still does not.
	_range.next_armour()
	_check(dummy.hit_target.armor == 100.0 and not dummy.hit_target.helmet, "K takes the helmet off")
	var bare_head := _shoot(_zone_point(dummy, &"head"))
	var bare_raw := data.damage_at(bare_head.distance) * data.hitbox_multiplier(&"head")
	_check(is_equal_approx(bare_head.damage, bare_raw), "without a helmet the head takes the whole round (%.0f)" % bare_head.damage)
	await _wait_for_respawn(dummy)

	# No armour at all: the chest takes it all.
	_range.next_armour()
	var bare_chest := _shoot(_zone_point(dummy, &"chest"))
	_check(
		dummy.hit_target.armor == 0.0
			and is_equal_approx(bare_chest.damage, data.damage_at(bare_chest.distance) * data.hitbox_multiplier(&"chest")),
		"with no armour the chest takes the whole round (%.0f)" % bare_chest.damage
	)
	_range.next_armour()
	_check(dummy.hit_target.armor == 100.0 and dummy.hit_target.helmet, "and K round again puts both back on")

	_range.next_distance()
	await physics_frame
	_check(absf(dummy.global_position.z + 1024.0) < 1.0, "N walks it back to 1024 units")

	_range.toggle_hitboxes()
	_check(hitboxes.all(func(hitbox: Hitbox) -> bool: return not hitbox.is_drawn()), "H hides the hitboxes")
	_range.toggle_hitboxes()
	_check(hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.is_drawn()), "and H again draws them")

	# Never dies: a whole spray registers, a kill is still counted.
	_range.toggle_immortal()
	var spray_hits := 0
	for i in 8:
		if _shoot(_zone_point(dummy, &"head")).hitbox != null:
			spray_hits += 1
	lines = _range.log_lines()
	_check(
		spray_hits == 8 and dummy.alive and dummy.hit_target.health > 0.0
			and lines.size() >= 2 and lines[0].begins_with("KILLED  100 damage in 1 hit"),
		"G keeps it standing: eight rounds to the head all register, each one counted as a kill (%d, %s)" % [spray_hits, lines[0] if lines.size() > 0 else ""]
	)
	_range.toggle_immortal()
	_check(not dummy.hit_target.immortal, "and G again lets it die")
	_check(
		_range.hitbox_source.contains("19 CS2 capsules") or _range.hitbox_source.contains("stand-in"),
		"the readout says which hitboxes it wears (%s)" % _range.hitbox_source
	)

	# The armour rules themselves, on a target of their own.
	var target := HitTarget.new()
	target.build_own_hitboxes = false
	root.add_child(target)
	_check(target.is_armored(&"head") and target.is_armored(&"arm") and not target.is_armored(&"leg"), "kevlar and helmet cover all but the legs")
	target.wear(100.0, false)
	_check(not target.is_armored(&"head") and target.is_armored(&"chest"), "kevlar alone leaves the head bare")
	target.armor = 30.0
	target.reset()
	_check(target.armor == 100.0, "a reset puts back what it was given to wear, not what is left of it")

	_report()


## Where to aim for a zone: the middle of that zone's first hitbox.
func _zone_point(dummy: Bot, zone: StringName) -> Vector3:
	for hitbox in dummy.hit_target.hitboxes():
		if hitbox.zone == zone:
			return hitbox.global_position
	return dummy.global_position + Vector3.UP * 40.0


## Fires one round with no spread from the lane's firing spot at a point, as
## the player's weapon does, and tells the range about it as the player would.
func _shoot(at: Vector3) -> Hitscan.Result:
	var player: PlayerController = _range.player
	var data: WeaponData = player.weapon.data.duplicate()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(_range.dummy_position().x, 64.0, 0.0)
	var angles := PlayerInput.angles_from_direction(at - origin)
	_clock_usec += 1_000_000
	var shot := weapon.fire(_clock_usec, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(_range.get_world_3d().direct_space_state, shot, data, player.hit_target.rids())
	player.shot_traced.emit(shot, result)
	return result


func _wait_for_respawn(dummy: Bot) -> void:
	for i in 30:
		await physics_frame
		if dummy.alive:
			break
	await physics_frame


func _find_drawn(hitbox: Hitbox) -> MeshInstance3D:
	for child in hitbox.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		_failures += 1
		print("  FAIL %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d range checks passed." % _checks)
		quit(0)
	else:
		print("%d of %d range checks failed." % [_failures, _checks])
		quit(1)
