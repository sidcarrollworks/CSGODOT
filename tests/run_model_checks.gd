extends SceneTree

## Checks the extracted weapons and player models, if there are any.
##
##   godot --headless --path . --script tests/run_model_checks.gd
##
## Like the dust2 checks, this passes without checking anything on a machine
## where scripts/extract_assets.sh has not been run. Where it has, it is the
## test that what Godot made of the exports is what the game will need: a
## skeleton to animate, the first-person arm meshes to draw, the weapon's own
## animations, and the first-person clips as animations of their own; and
## that the view model puts them together, with the weapon in the hands.

const WEAPONS_DIR := "res://assets/weapons"
const CHARACTERS_DIR := "res://assets/characters"

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _view_model: ViewModel
var _player_model: PlayerModel
var _bot: Bot
var _bot_world: Node3D
var _bot_started_frame: int = 0
var _bot_phase: int = 0
var _bot_died_usec: int = 0
var _bot_events: Array[String] = []
var _victim: PlayerController
var _victim_events: Array[String] = []
var _victim_at_respawn: Dictionary = {}
var _combat_started_usec: int = 0


func _init() -> void:
	# CS2's field of view numbers are horizontal at 4:3; Godot's are vertical.
	_check(
		absf(ViewModelOverlay.vertical_fov(90.0) - 73.74) < 0.05
			and absf(ViewModelOverlay.vertical_fov(68.0) - 53.64) < 0.05,
		"CS2's fov 90 and viewmodel_fov 68 convert to 73.7 and 53.6 vertical"
	)

	# Which locomotion clip a movement gets, from the body's speed along its
	# facing and to its right. No assets needed.
	_check(
		PlayerModel.clip_for(250.0, 0.0, false, true) == &"run_n"
			and PlayerModel.clip_for(0.0, 250.0, false, true) == &"run_e"
			and PlayerModel.clip_for(-180.0, -180.0, false, true) == &"run_sw"
			and PlayerModel.clip_for(0.0, -250.0, false, true) == &"run_w",
		"running picks the compass clip for the way the body moves relative to its facing"
	)
	_check(
		PlayerModel.clip_for(130.0, 0.0, false, true) == &"walk_n"
			and PlayerModel.clip_for(60.0, 60.0, true, true) == &"crouch_ne"
			and PlayerModel.clip_for(0.0, 0.0, false, true) == &"idle"
			and PlayerModel.clip_for(2.0, 0.0, true, true) == &"idle_crouch"
			and PlayerModel.clip_for(250.0, 0.0, false, false) == &"inair_stand",
		"walking, crouching, standing and being in the air each have their own"
	)

	_test_view_model_motion()
	_test_hitbox_set_parsing()
	_test_sound_sets()

	var weapons := _find(WEAPONS_DIR, "weapon_rif_")
	var agents := _find(CHARACTERS_DIR.path_join("agents"), "")
	var clips := _find(CHARACTERS_DIR.path_join("animation/anims"), "")
	if weapons.is_empty() and agents.is_empty():
		print("no weapons or characters have been extracted; only the arithmetic was checked.")
		_report()
		return

	_check(weapons.size() >= 2, "both weapons are there (%d found; scripts/extract_assets.sh weapons)" % weapons.size())
	for path in weapons:
		if path.get_file().ends_with("_mag.gltf"):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var player := scene.find_children("*", "AnimationPlayer", true, false)
		var animations: PackedStringArray = (player[0] as AnimationPlayer).get_animation_list() if not player.is_empty() else PackedStringArray()
		_check(
			not scene.find_children("*", "Skeleton3D", true, false).is_empty(),
			"%s has a skeleton" % path.get_file()
		)
		_check(
			_has(animations, "shoot") and _has(animations, "reload"),
			"%s has its shoot and reload animations (%s)" % [path.get_file(), ", ".join(animations)]
		)
		scene.free()

	_check(agents.size() >= 2, "both player models are there (%d found; scripts/extract_assets.sh characters)" % agents.size())
	for path in agents:
		var scene := _instantiate(path)
		if scene == null:
			continue
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		_check(
			not skeletons.is_empty() and (skeletons[0] as Skeleton3D).get_bone_count() >= 80,
			"%s has a full skeleton (%d bones)" % [path.get_file(), (skeletons[0] as Skeleton3D).get_bone_count() if not skeletons.is_empty() else 0]
		)
		for part in ["firstperson_default_gloves_arms", "firstperson_sleeves", "thirdperson_body"]:
			var found := scene.find_children("*%s*" % part, "MeshInstance3D", true, false)
			_check(
				not found.is_empty() and (found[0] as MeshInstance3D).mesh != null,
				"%s has its %s mesh" % [path.get_file(), part]
			)
		scene.free()

	_check(clips.size() >= 20, "the first-person rifle animations are there (%d found)" % clips.size())
	var checked := 0
	for path in clips:
		if not ("shoot" in path.get_file() or "draw" in path.get_file() or "reload" in path.get_file()):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		var ok := false
		if not players.is_empty():
			var list := (players[0] as AnimationPlayer).get_animation_list()
			if list.size() == 1:
				var animation := (players[0] as AnimationPlayer).get_animation(list[0])
				# One track per bone of the 69-bone view-model skeleton.
				ok = animation.get_track_count() >= 50 and animation.length > 0.1
		_check(ok, "%s is one animation over the view-model skeleton" % path.get_file())
		scene.free()
		checked += 1
		if checked >= 4:
			break

	# The rest needs frames: the rigs only pose once the tree has processed.
	_view_model = ViewModel.new()
	root.add_child(_view_model)
	var data := WeaponLibrary.ak47()
	_check(_view_model.setup("T", data.model_path, data.clip_set), "the view model builds for the AK-47 and a T")
	ViewModelOverlay.claim(_view_model)

	_player_model = PlayerModel.new()
	root.add_child(_player_model)
	_check(_player_model.setup("CT", WeaponLibrary.m4a1s().model_path), "the third-person model builds for the M4A1-S and a CT")


func _process(_delta: float) -> bool:
	_frames += 1
	if _bot != null:
		# The view model's checks are done and freed; the bot's run on.
		return _bot_step()
	if _view_model == null:
		return _frames > 1
	if _frames < 3:
		return false

	var player: AnimationPlayer = _view_model.animation_player
	_check(
		player != null and player.has_animation(&"draw") and player.has_animation(&"idle")
			and player.has_animation(&"shoot1") and player.has_animation(&"reload"),
		"draw, idle, shoot1 and reload are there under their short names"
	)
	_check(
		player != null and player.get_animation(&"idle").loop_mode == Animation.LOOP_LINEAR
			and player.current_animation == &"draw",
		"idle loops, and the draw is what plays first"
	)
	var meshes := _view_model.find_children("*", "MeshInstance3D", true, false)
	var arms := 0
	var weapon := 0
	var on_layer := 0
	for mesh in meshes:
		if mesh.name.contains("firstperson"):
			arms += 1
		if mesh.name.contains("weapon_rif"):
			weapon += 1
		if (mesh as MeshInstance3D).layers == 1 << (ViewModelOverlay.LAYER - 1) \
				and (mesh as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			on_layer += 1
	_check(arms == 2 and weapon >= 1, "the arm meshes and the weapon are on the rigs (%d arms, %d weapon)" % [arms, weapon])
	_check(on_layer == meshes.size(), "and every mesh is on the overlay's layer, casting no shadow")

	var arm_rig: Skeleton3D = _view_model.character_rig
	var weapon_rig: Skeleton3D = _view_model.weapon_rig
	_check(
		arm_rig != null and arm_rig.find_bone("arm_lower_L_TWIST") >= 0
			and arm_rig.get_bone_parent(arm_rig.find_bone("arm_lower_L_TWIST")) == arm_rig.find_bone("arm_lower_L"),
		"a twist bone the rig lacked was added under its parent"
	)
	if arm_rig != null and weapon_rig != null:
		var wpn: Vector3 = (arm_rig.global_transform * arm_rig.get_bone_global_pose(arm_rig.find_bone("wpn"))).origin
		var weapon_root: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(0)).origin
		_check(
			wpn.distance_to(weapon_root) < 0.01,
			"the weapon's root sits on the wpn bone (%.3f apart)" % wpn.distance_to(weapon_root)
		)
		var muzzle: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(weapon_rig.find_bone("muzzle"))).origin
		_check(
			muzzle.z < wpn.z - 10.0,
			"and the muzzle is well ahead of it, down the camera's -Z (%.1f)" % (muzzle.z - wpn.z)
		)

	_view_model.play(&"shoot1")
	_check(player.current_animation == &"shoot1", "a shot plays the shoot clip")
	_view_model.play(&"not_a_clip")
	_check(player.current_animation == &"idle", "an unknown clip falls back to idle")
	_view_model.free()
	_view_model = null

	_test_player_model()
	_test_player_composes_kick_and_bob()
	if _bot == null:
		_start_bot()
		return false
	return _bot_step()


## CS2's hitbox set is text; the test is that the fields come out of it and
## the groups become the zones the weapon data prices. No assets needed.
func _test_hitbox_set_parsing() -> void:
	var text := """
		{
			_class = "HitboxCapsule"
			radius = 4.3
			point0 = [ -1.0, 1.8, 0.0 ]
			point1 = [ 3.5, 0.2, 0.0 ]
			name = "head_0"
			parent_bone = "head_0"
			surface_property = "playerflesh"
			translation_only = false
			group_id = 8
		},
		{
			_class = "HitboxCapsule"
			radius = 3.0
			point0 = [ 0.0, 0.0, 0.0 ]
			point1 = [ -10.0, 0.0, -0.5 ]
			name = "arm_lower_r"
			parent_bone = "arm_lower_r"
			group_id = 5
		},
		{
			_class = "HitboxSphere"
			radius = 1.0
		}
	"""
	var capsules := HitboxSet.parse(text)
	_check(capsules.size() == 2, "two capsules parse out of a set with a sphere in it (%d)" % capsules.size())
	if capsules.size() == 2:
		_check(
			capsules[0]["bone"] == "head_0" and is_equal_approx(capsules[0]["radius"], 4.3)
				and (capsules[0]["point0"] as Vector3).is_equal_approx(Vector3(-1.0, 1.8, 0.0))
				and (capsules[0]["point1"] as Vector3).is_equal_approx(Vector3(3.5, 0.2, 0.0))
				and capsules[0]["zone"] == &"head" and capsules[0]["side"] == &"",
			"the neck's group is priced as the head, with its bone, radius and points"
		)
		_check(
			capsules[1]["zone"] == &"arm" and capsules[1]["side"] == &"right" and capsules[1]["group"] == 5,
			"the right forearm is an arm on the right"
		)
	_check(HitboxSet.parse("nothing here") .is_empty(), "no capsules in text without any")

	var placed := SkinnedHitboxes.capsule_transform(Vector3(0, 10, 0), Vector3(0, 30, 0))
	var slanted := SkinnedHitboxes.capsule_transform(Vector3(0, 0, 0), Vector3(3, 0, 4))
	_check(
		placed.origin.is_equal_approx(Vector3(0, 20, 0)) and placed.basis.y.is_equal_approx(Vector3.UP)
			and slanted.basis.y.is_equal_approx(Vector3(0.6, 0.0, 0.8))
			and slanted.basis.is_equal_approx(slanted.basis.orthonormalized()),
		"a capsule stands between its two points with its own Y along them"
	)
	_check(
		PlayerModel.death_for(&"stomach", 0) == &"death_gut_a"
			and PlayerModel.death_for(&"stomach", 1) == &"death_gut_b"
			and PlayerModel.death_for(&"head", 4) == &"death_chest_a"
			and PlayerModel.death_for(&"arm", 0) == &"death_rshoulder"
			and PlayerModel.death_for(&"leg", 3) == &"death_rknee_b",
		"a death falls the way the last round said, from the game's own pair where it has one"
	)


## The sound bank and the surface mapping; the bank's checks need the
## sounds extracted, the mapping's do not.
func _test_sound_sets() -> void:
	_check(
		Footsteps.set_for("physics_group_sand") == "sand" and Footsteps.set_for("physics_group_wood_plank") == "wood"
			and Footsteps.set_for("physics_group_metalvent") == "metal_vent"
			and Footsteps.set_for("physics_group_solidmetal") == "metal_solid"
			and Footsteps.set_for("physics_group_metal_dumpster") == "metal_solid"
			and Footsteps.set_for("physics_group") == "concrete_ct" and Footsteps.set_for("CollisionShape3D") == "concrete_ct",
		"the hull's material names map to the game's footstep sets, concrete when unknown"
	)
	_check(
		WeaponSounds.set_name_for(WeaponLibrary.ak47().model_path) == "ak47"
			and WeaponSounds.set_name_for(WeaponLibrary.m4a1s().model_path) == "m4a1_silencer"
			and WeaponSounds.SETS.has("ak47") and WeaponSounds.SETS.has("m4a1_silencer"),
		"each weapon's model names its sound set, and both sets are known"
	)
	if not SoundBank.available():
		print("sounds not extracted; skipping the bank's checks (scripts/extract_assets.sh sounds)")
		return
	_check(
		SoundBank.variants("weapons/ak47/ak47_0").size() == 4
			and SoundBank.variants("player/footsteps/sand_").size() == 12
			and SoundBank.variants("player/footsteps/land_concrete").size() == 1
			and SoundBank.variants("player/kevlar").size() >= 5
			and SoundBank.variants("nothing/here_").is_empty(),
		"the bank finds a set's variants by their shared stem: four AK shots, twelve sand steps, one concrete landing"
	)
	var random := SoundBank.randomizer("weapons/ak47/ak47_0")
	_check(
		random != null and random.streams_count == 4 and SoundBank.randomizer("weapons/ak47/ak47_0") == random
			and SoundBank.randomizer("nothing/here_") == null,
		"a set plays through one randomizer, made once, and an empty set has none"
	)
	for part: Array in WeaponSounds.SETS["ak47"]["reload"] + WeaponSounds.SETS["m4a1_silencer"]["reload"]:
		_check(not SoundBank.variants(part[1]).is_empty(), "the reload part %s is there" % part[1])


## A bot on a floor, to be shot. The hitboxes are areas, so the physics
## space has to see a frame before a trace finds them.
func _start_bot() -> void:
	_bot_world = Node3D.new()
	root.add_child(_bot_world)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(1000, 2, 1000)
	floor.add_child(shape)
	floor.position.y = -1.0
	_bot_world.add_child(floor)
	_bot = (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	_bot.team = "CT"
	_bot.weapon_data = WeaponLibrary.ak47()
	_bot.weapon_data.inaccuracy_standing = 0.0
	_bot.weapon_data.inaccuracy_per_shot = 0.0
	_bot.weapon_model = _bot.weapon_data.model_path
	_bot.respawn_seconds = 0.05
	_bot.position = Vector3(0, 0, -200)
	_bot.route = PackedVector3Array([Vector3(0, 0, -200)])
	_bot_world.add_child(_bot)
	_bot.died.connect(func(zone: StringName) -> void:
		_bot_events.append("died:" + zone)
		_bot_died_usec = Time.get_ticks_usec())
	_bot.respawned.connect(func() -> void: _bot_events.append("respawned"))
	_bot_started_frame = _frames


## Returns true when the bot's checks are done. Each step waits for the
## bot to be still: a clip moves the head, and the physics space sees a
## hitbox where it was at the last tick, so a shot is only aimed at a body
## that has settled. Headless frames can outrun the physics ticks, so the
## waits are on the clock and the animation, not the frame count.
func _bot_step() -> bool:
	var since := _frames - _bot_started_frame
	var settled: bool = _bot.model != null and _bot.model.animation_player.current_animation == &"idle" 		and not _bot.model.playing_one_shot()
	match _bot_phase:
		0:
			if since >= 3:
				_test_bot_sounds()
				_test_bot_wears_hitboxes()
				_test_bot_is_hit_where_aimed()
				_bot_phase = 1
		1:
			if (settled and since >= 6) or since > 4000:
				_test_bot_dies_where_shot()
				_bot_phase = 2
		2:
			if Time.get_ticks_usec() >= _bot_died_usec + 400_000 or since > 8000:
				_test_bot_comes_back()
				_start_combat()
				_bot_phase = 3
		3:
			# Reaction time, then a burst; on the clock, with a limit.
			if _bot.rounds_fired >= 3 or Time.get_ticks_usec() >= _combat_started_usec + 4_000_000:
				_test_bot_shoots_back()
				_bot_phase = 4
		4:
			if _victim_events.has("respawned") or Time.get_ticks_usec() >= _combat_started_usec + 12_000_000:
				_test_victim_dies_and_returns()
				_bot_world.free()
				_report()
				return true
	return false


## A player in front of the bot, in its sight, doing nothing.
func _start_combat() -> void:
	_victim = (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	_victim.respawn_seconds = 0.3
	_bot_world.add_child(_victim)
	_victim.place(Vector3(0, 0, 0), 180.0)
	_victim.died.connect(func() -> void: _victim_events.append("died"))
	_victim.respawned.connect(func() -> void:
		# Its state the instant it is back, before the bot's next burst.
		_victim_events.append("respawned")
		_victim_at_respawn = {
			"alive": _victim.alive, "health": _victim.hit_target.health, "position": _victim.global_position,
			"layer": _victim.hit_target.hitboxes()[0].collision_layer, "ammo": _victim.weapon.ammo,
		})
	_bot.yaw_degrees = 180.0
	_combat_started_usec = Time.get_ticks_usec()
	_check(
		_bot.weapon != null and _bot.weapon_sounds != null and _bot.weapon_sounds.spatial
			and _bot.can_see(_victim) and _victim.hit_target != null and _victim.hit_target.hitboxes().size() == 4,
		"the bot has a weapon that sounds from where it stands, sees the player in front of it, and the player can be hit"
	)


func _test_bot_shoots_back() -> void:
	_check(
		_bot.target == _victim and _bot.rounds_fired > 0 and _bot.weapon.ammo < _bot.weapon.data.magazine_size,
		"after its reaction time the bot turns on the player and fires (%d rounds)" % _bot.rounds_fired
	)
	_check(
		_victim.hit_target.health < 100.0 or _victim_events.has("died"),
		"and its rounds land: the player's health is %.0f" % _victim.hit_target.health
	)
	_check(
		absf(angle_difference(deg_to_rad(_bot.yaw_degrees), deg_to_rad(180.0))) < deg_to_rad(Bot.FIRE_WITHIN_DEGREES + 1.0),
		"facing the player (yaw %.0f)" % _bot.yaw_degrees
	)


func _test_victim_dies_and_returns() -> void:
	_check(
		_victim_events.has("died"),
		"the player dies to the bot's fire"
	)
	var back := _victim_at_respawn
	_check(
		_victim_events.has("respawned") and bool(back.get("alive", false))
			and is_equal_approx(float(back.get("health", 0.0)), 100.0)
			and (back.get("position", Vector3.ONE * 99.0) as Vector3).distance_to(Vector3.ZERO) < 4.0
			and int(back.get("layer", 0)) == Hitbox.LAYER
			and int(back.get("ammo", 0)) == _victim.weapon.data.magazine_size,
		"and is back where the map put it, whole and reloaded, to be shot again (%s)" % back
	)


func _test_bot_sounds() -> void:
	var footsteps := _bot.get_node_or_null("Footsteps") as Footsteps
	_check(footsteps != null and footsteps.body == _bot, "the bot has feet that sound")
	if footsteps == null or not SoundBank.available():
		return
	var on_floor := footsteps.surface_below()
	var floor_shape := _bot_world.get_child(0).get_child(0) as CollisionShape3D
	floor_shape.name = "physics_group_sand"
	var on_sand := footsteps.surface_below()
	floor_shape.name = "CollisionShape3D"
	_check(
		on_floor == "concrete_ct" and on_sand == "sand",
		"the surface under its feet is read off the hull part's name (%s, then %s)" % [on_floor, on_sand]
	)
	footsteps.step()
	footsteps.land()
	_check(
		footsteps.steps == 1 and footsteps.landings == 1
			and (footsteps.get_child(0) as AudioStreamPlayer3D).playing,
		"a step and a landing play from the feet"
	)


func _test_bot_wears_hitboxes() -> void:
	_check(
		_bot.hitboxes != null and _bot.hitboxes.hitboxes.size() == 19,
		"the bot wears CS2's nineteen capsules (%d)" % (_bot.hitboxes.hitboxes.size() if _bot.hitboxes else 0)
	)
	if _bot.hitboxes == null:
		return
	var zones := {}
	var head: Hitbox = null
	for hitbox in _bot.hitboxes.hitboxes:
		zones[hitbox.zone] = zones.get(hitbox.zone, 0) + 1
		if hitbox.name == "Hitbox_head_0":
			head = hitbox
	_check(
		zones.get(&"head", 0) == 2 and zones.get(&"chest", 0) == 3 and zones.get(&"stomach", 0) == 2
			and zones.get(&"arm", 0) == 6 and zones.get(&"leg", 0) == 6,
		"head and neck, three of chest, two of stomach, six each of arm and leg"
	)
	var head_height := head.global_position.y - _bot.global_position.y if head != null else 0.0
	_check(
		head != null and head_height > 58.0 and head_height < 70.0 and head.target == _bot.hit_target,
		"the head capsule rides the head bone, %.1f up, and reports to the bot's target" % head_height
	)
	_check(
		(head.get_child(0) as CollisionShape3D).shape is CapsuleShape3D
			and is_equal_approx(((head.get_child(0) as CollisionShape3D).shape as CapsuleShape3D).radius, 4.3),
		"with the game's own radius"
	)


func _test_bot_is_hit_where_aimed() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(0.0, 64.0, 0.0)
	var space := _bot_world.get_world_3d().direct_space_state
	var shin: Hitbox = null
	for hitbox in _bot.hitboxes.hitboxes:
		if hitbox.name == "Hitbox_leg_lower_l":
			shin = hitbox
	var angles := PlayerInput.angles_from_direction(shin.global_position - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(space, shot, data)
	_check(
		result.hit and result.hitbox != null and result.zone == &"leg"
			and is_equal_approx(result.damage, data.damage_at(result.distance) * data.leg_multiplier)
			and is_equal_approx(_bot.hit_target.health, 100.0 - result.damage) and _bot.alive,
		"a shot at the shin hits a leg capsule ahead of the hull, for three quarters and no armour (%s, %.0f damage, %.0f left)"
			% [result.zone, result.damage, _bot.hit_target.health]
	)
	_check(
		result.hitbox != null and result.hitbox.side == &"left"
			and _bot.hit_target.last_hitbox == result.hitbox
			and _bot.model.animation_player.current_animation == &"idle",
		"the target remembers which capsule, on which side, and the body carries on standing"
	)
	# The hull is not what bullets hit: a shot at the hips passes the box and lands on a capsule.
	var hips := _bot.global_position + Vector3(0, 36, 0)
	angles = PlayerInput.angles_from_direction(hips - origin)
	shot = weapon.fire(200_000, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	result = Hitscan.trace(space, shot, data)
	_check(
		result.hit and result.hitbox != null and result.zone in [&"stomach", &"chest", &"arm", &"leg"],
		"a shot at the hips lands on a capsule (%s), not the movement hull" % result.zone
	)


func _test_bot_dies_where_shot() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(0.0, 64.0, 0.0)
	var space := _bot_world.get_world_3d().direct_space_state
	var head := _bot.hitboxes.hitboxes[0]
	var angles := PlayerInput.angles_from_direction(head.global_position - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(space, shot, data)
	_check(
		result.zone == &"head" and result.damage > 100.0 and not _bot.alive and _bot_events.has("died:head"),
		"one round to the head kills through the helmet (%.0f), and it says where it landed" % result.damage
	)
	_check(
		_bot.model.animation_player.current_animation.begins_with("death_chest")
			and _bot.collision_layer == 0 and head.collision_layer == 0,
		"dead, it falls (a head has no fall of its own; the chest's), and neither its hull nor its hitboxes are there to hit (%s)"
			% _bot.model.animation_player.current_animation
	)
	shot = weapon.fire(300_000, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	_check(not Hitscan.trace(space, shot, data).hit, "a shot at the body now passes through")


func _test_bot_comes_back() -> void:
	_check(
		_bot.alive and _bot_events.has("respawned") and is_equal_approx(_bot.hit_target.health, 100.0)
			and _bot.collision_layer == 2 and _bot.hitboxes.hitboxes[0].collision_layer == Hitbox.LAYER
			and _bot.global_position.distance_to(Vector3(0, 0, -200)) < 2.0
			and _bot.model.animation_player.current_animation == &"idle",
		"after its respawn time it is back at the start of its route, whole, standing (%s)"
			% [_bot.model.animation_player.current_animation]
	)


## The controller writes the weapon model's whole transform every frame:
## the bob and sway in the camera's frame, the recoil kick in the model's.
## Standing still and looking steadily, that must leave the kick exactly as
## the weapon gives it, or the recoil work would be undone here.
func _test_player_composes_kick_and_bob() -> void:
	var player := (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	root.add_child(player)
	if player.view_model == null:
		_check(false, "the player builds its view model")
		player.free()
		return
	_check(player.body_model != null and player.body_model.character_rig != null, "the player builds its own body")
	_check(
		player.weapon_sounds != null and player.footsteps != null
			and (not SoundBank.available() or player.weapon_sounds.weapon_set.has("fire")),
		"and its weapon and footstep sounds, the AK's set taken up on equip"
	)
	if SoundBank.available():
		player.weapon_sounds.shot()
		_check(
			(player.weapon_sounds.get_child(0) as AudioStreamPlayer).playing
				and (player.weapon_sounds.get_child(0) as AudioStreamPlayer).stream is AudioStreamRandomizer,
			"a shot plays one of the AK's four through the randomizer"
		)
	if player.body_model != null:
		var rig: Skeleton3D = player.body_model.character_rig
		_check(
			rig.get_bone_pose_scale(rig.find_bone("head_0")).is_equal_approx(Vector3.ONE * RigModel.FOLDED)
				and rig.get_bone_pose_scale(rig.find_bone("arm_upper_R")).is_equal_approx(Vector3.ONE * RigModel.FOLDED)
				and rig.get_bone_pose_scale(rig.find_bone("pelvis")).is_equal_approx(Vector3.ONE),
			"with its head and arms folded and the rest whole"
		)

	# Frame one captures the rest pose; then a kick from a real shot.
	player.velocity = Vector3.ZERO
	player.on_ground = true
	player._update_viewmodel(1.0 / 60.0)
	var rest := player.view_model.transform
	var now := Time.get_ticks_usec()
	player.weapon.fire(now, 0.5, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new())
	player.weapon.update(1.0 / 128.0, now + 7813)
	var kick := player.weapon.viewmodel_punch()
	player._update_viewmodel(1.0 / 60.0)
	var expected := rest.basis * Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))
	_check(
		kick.length() > 0.01 and player.view_model.transform.basis.is_equal_approx(expected)
			and player.view_model.transform.origin.is_equal_approx(rest.origin),
		"standing still, a round's kick reaches the weapon model exactly as the weapon gives it (%.2f, %.2f degrees)" % [kick.x, kick.y]
	)

	# Running: the same kick, on top of the bob's offset.
	player.velocity = Vector3(0.0, 0.0, -250.0)
	for frame in 20:
		player._update_viewmodel(1.0 / 60.0)
	kick = player.weapon.viewmodel_punch()
	var moved := player.view_model.transform
	var motion_only := player.viewmodel_motion.update(0.0, Vector3(0.0, 0.0, -250.0), true, Vector2.ZERO)
	_check(
		not moved.origin.is_equal_approx(rest.origin)
			and moved.basis.is_equal_approx(
				motion_only.basis * rest.basis * Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))
			),
		"running, the bob moves the model and the kick still sits inside it"
	)
	player.free()


## The bob and sway need no assets: a clock, a speed and a look.
func _test_view_model_motion() -> void:
	_check(
		ViewModelMotion.bob_at(0.37, 0.0) == Vector2.ZERO
			and ViewModelMotion.bob_at(0.0, 320.0).is_equal_approx(Vector2(0.96 * 0.3, 1.6 * 0.3)),
		"standing still there is no bob; at full speed it starts at three tenths of its amounts"
	)
	var peak := ViewModelMotion.bob_at(ViewModelMotion.BOB_CYCLE * ViewModelMotion.BOB_UP * 0.5, 320.0)
	var trough := ViewModelMotion.bob_at(ViewModelMotion.BOB_CYCLE * (ViewModelMotion.BOB_UP + (1.0 - ViewModelMotion.BOB_UP) * 0.5), 320.0)
	_check(
		is_equal_approx(peak.x, 0.96) and is_equal_approx(trough.x, -0.96 * 0.4)
			and is_equal_approx(peak.y, 1.6 * 0.3 + 1.6 * 0.7 * sin(PI * 0.25)),
		"the vertical bob peaks a quarter cycle in and troughs at three quarters; the lateral runs at half the rate"
	)

	var motion := ViewModelMotion.new()
	var still := motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(90.0, 0.0))
	_check(
		still.origin.is_zero_approx() and still.basis.is_equal_approx(Basis.IDENTITY),
		"standing still and looking steadily, the weapon is where the clip put it"
	)
	var running := Transform3D.IDENTITY
	for frame in 30:
		running = motion.update(1.0 / 60.0, Vector3(0.0, 0.0, -250.0), true, Vector2(90.0, 0.0))
	_check(
		running.origin.z > 1.0 and running.origin.y < 0.0 and absf(running.origin.x) <= 1.6 * 0.8 + 0.001,
		"running settles the weapon back and down, and bobs it sideways within its amount (%s)" % running.origin
	)
	var airborne := motion.update(1.0 / 60.0, Vector3(0.0, 0.0, -250.0), false, Vector2(90.0, 0.0))
	_check(
		is_zero_approx(motion.vertical_bob) and airborne.origin.z < 0.001,
		"in the air there is no bob and nothing to settle"
	)
	var turned := motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(95.0, 0.0))
	_check(
		motion.sway.x < 0.0 and motion.sway.x >= -ViewModelMotion.SWAY_MAX
			and turned.basis.get_euler().y < 0.0,
		"turning left, the weapon lags to the right, within its limit (%.2f degrees)" % motion.sway.x
	)
	for frame in 120:
		motion.update(1.0 / 60.0, Vector3.ZERO, true, Vector2(95.0, 0.0))
	_check(absf(motion.sway.x) < 0.01, "and settles back once the turn stops")


func _test_player_model() -> void:
	var model := _player_model
	if model == null:
		return
	var animations := model.animation_player
	_check(
		animations != null and animations.has_animation(&"run_n") and animations.has_animation(&"walk_sw")
			and animations.has_animation(&"crouch_e") and animations.has_animation(&"idle")
			and animations.has_animation(&"inair_stand"),
		"the eight-way run, walk and crouch clips, the idles and the in-air clip are there"
	)
	var body := model.find_children("*thirdperson_body", "MeshInstance3D", true, false)
	var arms := model.find_children("*firstperson*", "MeshInstance3D", true, false)
	_check(not body.is_empty() and arms.is_empty(), "the third-person body is on the rig and the first-person arms are not")
	var rig: Skeleton3D = model.character_rig
	_check(
		rig != null and rig.find_bone("arm_lower_R_TWIST") >= 0,
		"the twist bones the body is skinned to were added to the rig"
	)
	var weapon_root: Node3D = null
	for child in rig.get_parent().get_children():
		if child.name.contains("weapon_rif"):
			weapon_root = child
	var skeleton: Skeleton3D = weapon_root.find_children("*", "Skeleton3D", true, false)[0] if weapon_root != null else null
	if rig != null and skeleton != null:
		var wpn: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("wpn"))).origin
		var root: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(0)).origin
		_check(wpn.distance_to(root) < 0.01, "the weapon's root bone sits on the hand's wpn bone (%.3f apart)" % wpn.distance_to(root))
	var head: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("head_0"))).origin
	_check(
		head.y > 60.0 and head.y < 72.0 and (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("root_motion"))).origin.y < 0.5,
		"the model stands on its origin with its head about five and a half feet up (%.1f)" % head.y
	)

	# Facing +Z at yaw 180 (the game's forward is -Z at yaw 0), running forward.
	model.update_motion(Vector3(0, 0, 240), 180.0, false, true)
	_check(
		animations.current_animation == &"run_n" and absf(animations.speed_scale - 0.96) < 0.01,
		"running forward at 240 plays run_n at 0.96 of the clip's speed (%s at %.2f)" % [animations.current_animation, animations.speed_scale]
	)
	model.update_motion(Vector3(-100, 0, 0), 180.0, false, true)
	_check(animations.current_animation == &"walk_e", "sidestepping to the right at walking pace plays walk_e (%s)" % animations.current_animation)

	# The first-person body: the head and arms folded away, and staying so
	# under the clips, which animate every bone's scale.
	model.update_motion(Vector3.ZERO, 180.0, false, true)
	model.fold_bones(PackedStringArray(["head_0", "arm_upper_L"]))
	var folded_head := rig.get_bone_pose_scale(rig.find_bone("head_0"))
	var idle: Animation = animations.get_animation(&"idle")
	var head_scale_tracks := 0
	var head_tracks := 0
	for track in idle.get_track_count():
		if String(idle.track_get_path(track).get_subname(0)) == "head_0":
			head_tracks += 1
			head_scale_tracks += 1 if idle.track_get_type(track) == Animation.TYPE_SCALE_3D else 0
	_check(
		folded_head.is_equal_approx(Vector3.ONE * RigModel.FOLDED)
			and head_scale_tracks == 0 and head_tracks > 0
			and animations.current_animation == &"idle" and animations.is_playing(),
		"folding a bone shrinks it to nothing and takes its scale track, and only that, out of the clips, which keep playing"
	)
	model.free()
	_player_model = null


func _find(dir_path: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".gltf") and not file.ends_with("_physics.gltf") and file.begins_with(prefix):
			out.append(dir_path.path_join(file))
	for subdirectory in dir.get_directories():
		out.append_array(_find(dir_path.path_join(subdirectory), prefix))
	return out


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	_check(packed != null, "%s imports as a scene" % path.get_file())
	if packed == null:
		return null
	return packed.instantiate()


func _has(names: PackedStringArray, fragment: String) -> bool:
	for name in names:
		if name.contains(fragment):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d model checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d model checks failed." % [_failures, _checks])
		quit(1)
