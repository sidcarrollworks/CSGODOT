extends "res://tests/check_suite.gd"

## Persistent motion values may be reused; consumed requests may not.
## Real AnimationTrees over synthetic clips keep this independent of assets.

class FixtureModel extends PlayerModel:
	func prepared_set(_weapon_set: String) -> Dictionary:
		return {}


## The previous unconditional parameter writer, kept as the comparison for
## rendered poses across changing inputs and different animation step sizes.
class UncachedModel extends FixtureModel:
	func _apply_locomotion(at: String) -> void:
		var path := "parameters/" + at
		for space_name in [&"stand", &"crouch", &"air_stand", &"air_crouch", &"jump_stand", &"jump_crouch"]:
			animation_tree.set(path + String(space_name) + "/blend_position", _speeds)
		animation_tree.set(path + "move/blend_amount", _crouch)
		animation_tree.set(path + "air/blend_amount", _crouch_eased)
		animation_tree.set(path + "jump/blend_amount", _crouch_eased)
		animation_tree.set(path + "cycle/scale", 1.0 / cycle_length(_rings[at], _speeds.length(), _crouch))
		for side: String in ["stand", "crouch"]:
			var curve: Array[Vector2] = _landing_curves.get(side, LANDING_CURVE)
			animation_tree.set(path + "land_hold_" + side + "/scale", 0.0)
			animation_tree.set(path + "land_pose_" + side + "/seek_request", landing_share(_height, curve) * float(_landing_seconds.get(at, LANDING_SECONDS)))
		if _air_action == PlayerBody.AIR_JUMP and int(_jump_started.get(at, -1)) != _air_action_usec:
			_jump_started[at] = _air_action_usec
			animation_tree.set(path + "jump_start/seek_request", 0.0)
		var air_wanted := air_state(_air_action, _air_action_usec, SimClock.now_usec(), float(_jump_seconds.get(at, JUMP_SECONDS)))
		if String(animation_tree.get(path + "air_state/current_state")) != air_wanted:
			animation_tree.set(path + "air_state/transition_request", air_wanted)
		var wanted := "ground" if _on_ground else "air"
		if String(animation_tree.get(path + "ground/current_state")) != wanted:
			var ground := _locomotion_node(at, &"ground") as AnimationNodeTransition
			ground.xfade_time = TO_GROUND if _on_ground else into_air_fade(_air_action)
			animation_tree.set(path + "ground/transition_request", wanted)

	func _apply(all: bool = false) -> void:
		super._apply(all)
		if has_weapon_layers:
			animation_tree.set("parameters/hold/add_amount", 1.0 if _has_hold else 0.0)
			animation_tree.set("parameters/hold_pose/blend_amount", _crouch)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_motion_and_variations()
	_test_consumed_requests()
	_test_replacement_tree()
	_test_pose_equivalence()
	_finish("animation_parameter")


func _fixture(varied: bool, uncached: bool = false) -> PlayerModel:
	var table := PlayerModel.read_locomotion()
	var library := AnimationLibrary.new()
	var names := {}
	for variation: String in ["rifle", "pistol", "knife"]:
		var prefix := "" if variation == "rifle" else variation + "_"
		for space: Dictionary in table.get("blend_spaces", []):
			for point: Dictionary in space.get("points", []):
				names[prefix + String(PlayerModel.clip_name(point, variation))] = true
		for fallback: String in ["idle", "jump_stand", "jump_crouch_stand", "inair_stand"]:
			names[prefix + fallback] = true
	for name: String in names:
		var jumping := name.contains("jump_")
		var airborne := name.contains("inair_")
		var ground_length := 0.7 if name.contains("run_") else (0.8 if name.contains("crouch_") else 1.0)
		var ground_pose := -10.0 if name.contains("crouch_") else -1.0
		_add_clip(library, name, 0.4 if jumping else (0.33 if airborne else ground_length), 100.0 if jumping else (0.0 if airborne else ground_pose), true)
	for action: String in ["idle", "idle_crouch", "draw", "shoot"]:
		_add_clip(library, "held_fixture_" + action, 0.3, 0.0, false)
	var model: PlayerModel = UncachedModel.new() if uncached else FixtureModel.new()
	var rig := Node3D.new()
	var bone := Node3D.new()
	bone.name = "Bone"
	rig.add_child(bone)
	var player := AnimationPlayer.new()
	player.add_animation_library(&"", library)
	rig.add_child(player)
	model.add_child(rig)
	model.animation_player = player
	model.character_rig = Skeleton3D.new()
	rig.add_child(model.character_rig)
	model.idle = &"idle"
	model.holds_items = varied
	root.add_child(model)
	model._build_tree(PackedStringArray())
	model.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model._landing_curves = {"stand": PlayerModel.LANDING_CURVE, "crouch": PlayerModel.LANDING_CURVE}
	return model


func _add_clip(library: AnimationLibrary, clip_name: String, seconds: float, base: float, moving: bool) -> void:
	var clip := Animation.new()
	clip.length = seconds
	clip.loop_mode = Animation.LOOP_LINEAR if base < 0.0 else Animation.LOOP_NONE
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, NodePath("Bone:position:y"))
	clip.track_insert_key(track, 0.0, base)
	clip.track_insert_key(track, seconds, base + (seconds if moving else 0.0))
	library.add_animation(StringName(clip_name), clip)


func _check_motion(model: PlayerModel, at: String, speeds: Vector2, crouch: float, description: String) -> void:
	var tree := model.animation_tree
	var path := "parameters/" + at
	var matches := true
	for space: String in ["stand", "crouch", "air_stand", "air_crouch", "jump_stand", "jump_crouch"]:
		matches = matches and tree.get(path + space + "/blend_position") == speeds
	_check(matches and float(tree.get(path + "move/blend_amount")) == crouch, description)
	_check_near(float(tree.get(path + "cycle/scale")), 1.0 / PlayerModel.cycle_length(model._rings[at], speeds.length(), crouch), description + ": cycle rate")


func _test_motion_and_variations() -> void:
	var model := _fixture(true)
	var tree := model.animation_tree
	var velocity := Vector3(36, 0, -120)
	var speeds := PlayerModel.body_speeds(velocity, 0.0)
	model.hold("weapon_ak47", {"world_clip_set": "fixture"})
	model.update_motion(velocity, 0.0, 0.35, true)
	model.pose_now()
	_check_motion(model, "rifle/", speeds, 0.35, "motion reaches every rifle blend space")
	for frame in 4:
		tree.advance(0.02)
		model.update_motion(velocity, 0.0, 0.35, true)
	_check_motion(model, "rifle/", speeds, 0.35, "unchanged motion survives animation advances")
	_check_near(float(tree.get("parameters/rifle/air/blend_amount")), 0.35, "the eased air crouch is preserved")
	_check_near(float(tree.get("parameters/hold_pose/blend_amount")), 0.35, "the held pose follows crouch")
	_check_equal(float(tree.get("parameters/hold/add_amount")), 1.0, "taking a weapon enables its hold")
	model.hold("weapon_glock", {"world_clip_set": "fixture"})
	_check_equal(model._variation, "rifle", "the draw still delays the pistol's variation")
	for at: String in ["rifle/", "pistol/", "knife/"]:
		_check_motion(model, at, speeds, 0.35, "hold prepares the inactive " + at + "variation")
	model._switch_at_usec = SimClock.now_usec()
	model.update_motion(velocity, 0.0, 0.35, true)
	model.pose_now()
	_check_equal(String(tree.get("parameters/variation/current_state")), "pistol", "an unchanged motion update still completes the delayed draw switch")
	model.update_motion(Vector3(-120, 0, -36), 0.0, 0.35, true)
	_check_motion(model, "pistol/", Vector2(36, 120), 0.35, "a direction change at the same speed reaches every pistol space")
	model.hold("weapon_hegrenade")
	model.pose_now()
	_check_equal(String(tree.get("parameters/variation/current_state")), "knife", "a weapon without a draw switches immediately")
	_check_motion(model, "knife/", Vector2(36, 120), 0.35, "an inactive variation is refreshed before switching")
	_check_equal(float(tree.get("parameters/hold/add_amount")), 0.0, "an item without a hold disables the previous weapon's layer")
	model.free()


func _test_pose_equivalence() -> void:
	var old_world := GameWorld.current
	var clock := GameWorld.new()
	clock.tick = 1000
	GameWorld.current = clock
	var cached := _fixture(true)
	var uncached := _fixture(true, true)
	var cached_bone := cached.animation_player.get_parent().get_node("Bone") as Node3D
	var uncached_bone := uncached.animation_player.get_parent().get_node("Bone") as Node3D
	for model: PlayerModel in [cached, uncached]:
		model.hold("weapon_ak47", {"world_clip_set": "fixture"})
		model.pose_now()
	var sequence := [
		{"velocity": Vector3(0, 0, -225)},
		{"velocity": Vector3(0, 0, -225)},
		{"velocity": Vector3(-136, 0, 0), "crouch": 1.0},
		{"velocity": Vector3(-96, 0, 0), "crouch": 1.0},
		{"velocity": Vector3(10, 0, -150), "crouch": 0.0},
		{"velocity": Vector3(0, 0, -225), "action": PlayerBody.AIR_JUMP, "height": 35.0},
		{"velocity": Vector3(0, 0, -225), "action": PlayerBody.AIR_JUMP, "age": 500_000, "height": 27.9},
		{"velocity": Vector3(0, 0, -225), "action": PlayerBody.AIR_START_FALL, "height": 2.0, "crouch": 1.0},
		{"velocity": Vector3.ZERO, "action": PlayerBody.AIR_LAND},
		{"velocity": Vector3(36, 0, -120), "held": "weapon_glock"},
		{"velocity": Vector3(36, 0, -120), "held": "weapon_hegrenade", "crouch": 1.0},
		{"velocity": Vector3.ZERO, "held": "weapon_ak47"},
	]
	var max_pose_error := 0.0
	var parameters_match := true
	var states_match := true
	var eased_independently := false
	var samples := 0
	for command: Dictionary in sequence:
		var action: StringName = command.get("action", PlayerBody.NO_AIR_ACTION)
		var started := SimClock.now_usec() - int(command.get("age", 0))
		var grounded := action == PlayerBody.NO_AIR_ACTION or action == PlayerBody.AIR_LAND
		for model: PlayerModel in [cached, uncached]:
			if command.has("held"):
				var item_class: String = command["held"]
				model.hold(item_class, {} if item_class == "weapon_hegrenade" else {"world_clip_set": "fixture"})
		for tick in 12:
			clock.tick += 1
			for model: PlayerModel in [cached, uncached]:
				if tick == 6:
					model._switch_at_usec = SimClock.now_usec()
				model.update_motion(command["velocity"], 0.0, float(command.get("crouch", 0.0)), grounded, action, started, float(command.get("height", INF)))
			var path := "parameters/" + cached._variation + "/"
			for suffix: String in ["move/blend_amount", "air/blend_amount", "jump/blend_amount", "cycle/scale"]:
				parameters_match = parameters_match and cached.animation_tree.get(path + suffix) == uncached.animation_tree.get(path + suffix)
			parameters_match = parameters_match and cached.animation_tree.get("parameters/hold_pose/blend_amount") == uncached.animation_tree.get("parameters/hold_pose/blend_amount")
			eased_independently = eased_independently or cached._crouch_eased != cached._crouch
			# Include zero-time advances and a subsequent batched step,
			# as well as smaller visible-frame steps. Motion still updates each tick.
			var steps: Array = [0.0] if tick % 4 == 0 else ([2.0 / 64.0] if tick % 4 == 1 else [1.0 / 128.0, 1.0 / 128.0])
			for seconds: float in steps:
				cached.animation_tree.advance(seconds)
				uncached.animation_tree.advance(seconds)
				max_pose_error = maxf(max_pose_error, cached_bone.position.distance_to(uncached_bone.position))
				for suffix: String in ["ground/current_state", "air_state/current_state"]:
					states_match = states_match and cached.animation_tree.get(path + suffix) == uncached.animation_tree.get(path + suffix)
				states_match = states_match and cached.animation_tree.get("parameters/variation/current_state") == uncached.animation_tree.get("parameters/variation/current_state")
				samples += 1
	_check(parameters_match and eased_independently, "changing crouch preserves cycle, hold, and independently eased air/jump values")
	_check(states_match, "ground, air, and delayed held transitions match the original writer")
	_check(max_pose_error < 0.000001 and samples > 200, "%d rendered poses match the original writer through movement, crouch, air, held changes and batched advances (max error %.9f)" % [samples, max_pose_error])
	cached.free()
	uncached.free()
	GameWorld.current = old_world
	for system in clock.game.systems():
		if system is ItemDrops:
			system.game = null
	clock.free()


func _test_consumed_requests() -> void:
	var model := _fixture(false)
	var tree := model.animation_tree
	var bone := model.animation_player.get_parent().get_node("Bone") as Node3D
	var now := SimClock.now_usec()
	var run := Vector3(0, 0, -240)
	model.update_motion(run, 0.0, 0.0, false, PlayerBody.AIR_START_FALL, now, 27.9)
	model.pose_now()
	for frame in 40:
		tree.advance(0.01)
	_check_near(bone.position.y, 0.165, "the landing poses the bone at the height's clip time")
	_check_equal(float(tree.get("parameters/land_pose_stand/seek_request")), -1.0, "advance consumes the landing seek")
	model.update_motion(run, 0.0, 0.0, false, PlayerBody.AIR_START_FALL, now, 27.9)
	_check_near(float(tree.get("parameters/land_pose_stand/seek_request")), 0.165, "the same height reissues the consumed seek")
	tree.advance(0.0)
	_check_near(bone.position.y, 0.165, "reissuing an identical seek preserves the rendered pose")
	model.update_motion(run, 0.0, 0.0, false, PlayerBody.AIR_JUMP, now, 27.9)
	_check_equal(float(tree.get("parameters/jump_start/seek_request")), 0.0, "a jump requests the take-off from its start")
	tree.advance(0.0)
	tree.advance(0.15)
	model.update_motion(run, 0.0, 0.0, false, PlayerBody.AIR_JUMP, now, 27.9)
	_check_equal(float(tree.get("parameters/jump_start/seek_request")), -1.0, "an unchanged jump does not rewind its take-off")
	model.update_motion(run, 0.0, 0.0, false, PlayerBody.AIR_JUMP, now + 1, 27.9)
	_check_equal(float(tree.get("parameters/jump_start/seek_request")), 0.0, "another jump reissues zero even though the earlier request had the same value")
	model.free()
	model = _fixture(true)
	tree = model.animation_tree
	model.hold("weapon_ak47", {"world_clip_set": "fixture"})
	model.pose_now()
	for shot in 2:
		model.fire()
		_check_equal(int(tree.get("parameters/shoot/request")), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE, "each shot requests the same one-shot value")
		tree.advance(0.0)
		tree.advance(0.4)
		_check_equal(int(tree.get("parameters/shoot/request")), AnimationNodeOneShot.ONE_SHOT_REQUEST_NONE, "the engine consumes each shot request")
	model.free()


func _test_replacement_tree() -> void:
	var model := _fixture(true)
	var velocity := Vector3(36, 0, -120)
	model.hold("weapon_ak47", {"world_clip_set": "fixture"})
	model.update_motion(velocity, 0.0, 0.4, true)
	model.pose_now()
	var tree := model.animation_tree
	# Replacing the whole tree starts with engine defaults at the same paths.
	model._build_tree(PackedStringArray())
	var replacement := model.animation_tree
	replacement.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.free()
	model.update_motion(velocity, 0.0, 0.4, true)
	_check_motion(model, "rifle/", Vector2(120, -36), 0.4, "a replacement AnimationTree receives unchanged motion")
	_check_equal(float(replacement.get("parameters/hold/add_amount")), 1.0, "a replacement AnimationTree receives the held layer")
	# A new root resource in the same tree also invalidates its bindings.
	var donor := _fixture(true)
	replacement.tree_root = donor.animation_tree.tree_root
	donor.free()
	replacement.set("parameters/rifle/stand/blend_position", Vector2.ZERO)
	replacement.set("parameters/hold/add_amount", 0.0)
	model.update_motion(velocity, 0.0, 0.4, true)
	_check_motion(model, "rifle/", Vector2(120, -36), 0.4, "a replacement root receives unchanged motion")
	_check_equal(float(replacement.get("parameters/hold/add_amount")), 1.0, "a replacement root receives the held layer")
	model.free()
