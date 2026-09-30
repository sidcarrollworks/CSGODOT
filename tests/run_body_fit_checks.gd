extends "res://tests/check_suite.gd"

## Checks when a body's skeleton is fitted, without the extracted models.
## Fitting is running its modifiers: the feet on the floor (FootPlant), the
## hands on the gun (HandGrip), the twist bones (TwistModifier). After it
## the skin is sent and skeleton_updated moves the hitboxes, the gun and the
## eyes to the bones. A stand-in body with one clip turning one bone, the
## game's FootPlant and HandGrip (with no legs or arms to fit, so they write
## nothing, but PlayerModel tells them every frame what the body does, as it
## tells every body's), and a modifier that writes down each time the
## skeleton is fitted and the time it is given.
##
## A skeleton's own default fits it in every frame, whether its pose changed
## or not. A body that steps its own animation (PlayerModel.step_off_tick_frames)
## is fitted in a frame it steps or its bones are set, by the time since it
## was last fitted, and in no other; where the frame before a tick went
## without its fit, as that tick begins (PlayerModel.fit_for_tick). A body
## nobody sees does not step in a frame that runs a tick, and each fit it
## skips there is about 80 us of that frame
## (reference/research/skeletons-when-stepped-2026-09-30.md).
##
##   godot --headless --path . --script tests/run_body_fit_checks.gd

## A frame's length, in seconds: about what the game runs at.
const FRAME := 0.005

const RECORDER := """extends SkeletonModifier3D
var deltas: Array[float] = []
var turned: Array[float] = []
func _process_modification_with_delta(delta: float) -> void:
	deltas.append(delta)
	var skeleton := get_skeleton()
	turned.append(skeleton.get_bone_pose_rotation(1).get_angle())
	# As the feet and the hands do where they have bones to fit: it writes one.
	skeleton.set_bone_pose_position(2, skeleton.get_bone_pose_position(2) + Vector3(0.0, 0.01, 0.0))
"""

var _recorder_script: GDScript
var _updates := 0


func _initialize() -> void:
	_recorder_script = GDScript.new()
	_recorder_script.source_code = RECORDER
	_recorder_script.reload()
	await process_frame
	await _test_the_default_fits_every_frame()
	await _test_fitted_when_it_steps()
	await _test_every_moment_given()
	await _test_fitted_for_the_tick()
	await _test_the_world_fits_for_the_tick()
	await _test_steps_on_the_tick()
	await _test_a_pose_set_otherwise()
	await _test_dying_and_at_rest()
	_finish("body-fit")


func _print_passes() -> bool:
	return true


## Times are compared to the float: each is a sum of the frames' times.
func _near_tolerance() -> float:
	return 0.000001


## A body on a three-bone rig whose clip turns the middle bone by a radian a
## second, with the game's feet and hands fits and a recorder after them.
func _stand_in() -> PlayerModel:
	var model := PlayerModel.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	model.add_child(skeleton)
	model.character_rig = skeleton
	for bone: Array in [["root", ""], ["spine", "root"], ["head", "spine"]]:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	skeleton.reset_bone_poses()
	var clip := Animation.new()
	clip.length = 4.0
	clip.loop_mode = Animation.LOOP_LINEAR
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Skeleton3D:spine"))
	clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	clip.rotation_track_insert_key(track, 2.0, Quaternion(Vector3.UP, 2.0))
	clip.rotation_track_insert_key(track, 4.0, Quaternion.IDENTITY)
	var library := AnimationLibrary.new()
	library.add_animation(&"turn", clip)
	model.animation_player = AnimationPlayer.new()
	model.add_child(model.animation_player)
	model.animation_player.add_animation_library(&"", library)
	# In the order setup puts them, the recorder last as the twist bones are.
	model.foot_plant = FootPlant.new()
	skeleton.add_child(model.foot_plant)
	model.hand_grip = HandGrip.new()
	skeleton.add_child(model.hand_grip)
	var recorder := SkeletonModifier3D.new()
	recorder.name = "Recorder"
	recorder.set_script(_recorder_script)
	skeleton.add_child(recorder)
	skeleton.skeleton_updated.connect(func() -> void: _updates += 1)
	return model


## A stand-in in the tree, stepping itself as a worn body does, with its
## frames run by the check (_frame) and nothing yet recorded.
func _stepping() -> PlayerModel:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	model.step_off_tick_frames()
	model.set_process(false)
	await process_frame
	await process_frame
	model._unstepped = 0.0
	model._unfitted = 0.0
	_clear(model)
	return model


func _recorder(model: PlayerModel) -> SkeletonModifier3D:
	return model.character_rig.get_node("Recorder") as SkeletonModifier3D


## Forgets what the recorder and the skeleton have said so far.
func _clear(model: PlayerModel) -> void:
	(_recorder(model).get(&"deltas") as Array).clear()
	(_recorder(model).get(&"turned") as Array).clear()
	_updates = 0


func _fits(model: PlayerModel) -> Array:
	return _recorder(model).get(&"deltas") as Array


func _turned(model: PlayerModel) -> Array:
	return _recorder(model).get(&"turned") as Array


## One frame of the body's own, as the engine runs it (PlayerModel._process),
## said to have run a tick or not, and the frame's end, where the skeleton
## is fitted if it is to be.
func _frame(model: PlayerModel, ticked: bool) -> void:
	model._last_physics_frame = Engine.get_physics_frames() - (1 if ticked else 0)
	model._process(FRAME)
	await process_frame


## What the rest is measured against: a skeleton's own default fits it in
## every frame, pose changed or not. Your own drawn body keeps it
## (PlayerView._build_body steps nothing by hand), seen in every frame and
## bent as you look down.
func _test_the_default_fits_every_frame() -> void:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	for i in 2:
		await process_frame
	_clear(model)
	for i in 4:
		await process_frame
	_check(
		model.character_rig.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
			and _fits(model).size() >= 4,
		"the skeleton's own default, which a body not stepped by hand keeps: fitted in every frame (%d fits in 4 frames)" % _fits(model).size()
	)
	model.free()


## Stepped by hand, a body is fitted once in a frame it steps, by the time
## since it was last fitted, over the pose the step made; in a frame it does
## not, not at all, though the feet and the hands are told every frame what
## it does.
func _test_fitted_when_it_steps() -> void:
	var model := await _stepping()
	_check(
		model.stepped_by_hand
			and model.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			and model.character_rig.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL,
		"a body that steps its own animation fits its own skeleton too"
	)
	for i in 3:
		await _frame(model, true)
	_check(
		_fits(model).is_empty() and _updates == 0 and model.foot_plant.active and model.hand_grip.active,
		"three frames that each ran a tick, in which a body nobody sees does not step, fit it in none, its feet and hands told what it does in each (%d fits, %d updates)"
			% [_fits(model).size(), _updates]
	)
	await _frame(model, false)
	var fits := _fits(model)
	var turned := _turned(model)
	_check(
		fits.size() == 1 and absf(fits[0] - 4.0 * FRAME) < 0.000001 and _updates == 1,
		"the next frame, which ran none, steps it by the four frames' time and fits it once, by that time (%s s; %d updates)"
			% [str(fits), _updates]
	)
	_check(
		turned.size() == 1 and absf(turned[0] - 4.0 * FRAME) < 0.0005,
		"after the pose the step made: the clip's bone turned as far as four frames take it (%.4f rad, %.4f)"
			% [turned[0] if not turned.is_empty() else -1.0, 4.0 * FRAME]
	)
	model.free()


## Over a run of frames, a third of them running a tick as at the game's
## rate, each fit is given the time since the one before it, to the float:
## all the time that passed, none of it twice. The feet and the hands ease
## by the time they are given, by the same amounts whether it comes as one
## fit or as several.
func _test_every_moment_given() -> void:
	var model := await _stepping()
	var frames := 60
	var owed := 0.0
	var expected: Array[float] = []
	for i in frames:
		var ticked := i % 3 == 0
		owed += FRAME
		if not ticked:
			expected.append(owed)
			owed = 0.0
		await _frame(model, ticked)
	var fits := _fits(model)
	var alike := fits.size() == expected.size()
	var given := 0.0
	for i in fits.size():
		given += fits[i]
		alike = alike and i < expected.size() and absf(fits[i] - expected[i]) < 0.000001
	_check(
		alike and _updates == expected.size(),
		"%d frames, one in three running a tick: fitted in the %d that stepped and no other, each by the time since the last fit (%d fits, %d updates)"
			% [frames, expected.size(), fits.size(), _updates]
	)
	_check_near(given, frames * FRAME, "and given all the time that passed, none of it twice (%.6f s of %.6f)" % [given, frames * FRAME])
	model.free()


## A frame that runs a tick and fits nothing, then a tick at once, with no
## frame between: the fit that frame used to make is made as the tick
## begins, where it would have put the body, by the time since the last
## fit; not again for a second tick in the same frame, as a fit at a
## frame's end never was; and not for a body that has not moved or turned
## since it was last fitted, whose fit stands.
func _test_fitted_for_the_tick() -> void:
	var model := await _stepping()
	await _frame(model, false)
	_clear(model)
	model.fit_for_tick()
	_check(_fits(model).is_empty(), "a tick after a frame that fitted the body fits nothing more (%d fits)" % _fits(model).size())
	await _frame(model, true)
	# Drawn a little further on, as a bot is between its ticks, or turned by
	# the tick, as your own body is.
	model.position += Vector3(3.0, 0.0, 0.0)
	model.fit_for_tick()
	var at_tick := _fits(model).duplicate()
	var updates_at_tick := _updates
	var turned_at_tick := _turned(model).duplicate()
	model.fit_for_tick()
	var again := _fits(model).size() - at_tick.size()
	_check(
		at_tick.size() == 1 and absf(at_tick[0] - FRAME) < 0.000001 and updates_at_tick == 1 and again == 0,
		"after a frame with a tick that fitted nothing, the next tick fits the body as it begins, by that frame's time (%s s), there and then (%d updates), and a second tick in the frame fits nothing more (%d)"
			% [str(at_tick), updates_at_tick, again]
	)
	_check(
		turned_at_tick.size() == 1 and absf(turned_at_tick[0] - FRAME) < 0.0005,
		"to the pose the body has, which that frame did not step (%.4f rad, as the step before left it)" % (turned_at_tick[0] if not turned_at_tick.is_empty() else -1.0)
	)
	_clear(model)
	await _frame(model, true)
	model.fit_for_tick()
	_check(
		_fits(model).is_empty() and _updates == 0,
		"another frame with a tick, the body not moved or turned since it was fitted: its fit stands, and the tick fits nothing (%d fits)" % _fits(model).size()
	)
	await _frame(model, false)
	var fits := _fits(model)
	var turned := _turned(model)
	_check(
		fits.size() == 1 and absf(fits[0] - 2.0 * FRAME) < 0.000001 and turned.size() == 1 and absf(turned[0] - 4.0 * FRAME) < 0.0005,
		"the next frame without one steps it by the time since it last stepped (to %.4f rad, %.4f) and fits it by the time since it was last fitted (%s s)"
			% [turned[0] if not turned.is_empty() else -1.0, 4.0 * FRAME, str(fits)]
	)
	model.free()


## The world asks every player's body, as each tick begins, before anyone
## runs (GameWorld.begin_tick).
func _test_the_world_fits_for_the_tick() -> void:
	var model := await _stepping()
	var world := GameWorld.new()
	var player := PlayerSim.new()
	player.model = model
	world.players.append(player)
	await _frame(model, true)
	model.position += Vector3(0.0, 0.0, 3.0)
	var tick := world.tick
	world.begin_tick()
	_check(
		world.tick == tick + 1 and _fits(model).size() == 1 and _updates == 1,
		"a tick the world begins fits a body that went its last frame without its fit (%d fits)" % _fits(model).size()
	)
	world.players.clear()
	player.model = null
	player.free()
	world.free()
	model.free()


## Stepped on the tick with its update forced, as the match checks and the
## profilers pose bodies: fitted there, by the step's time, and not again at
## the frame's end. Two steps in one frame are one fit, by both steps' time.
func _test_steps_on_the_tick() -> void:
	var model := await _stepping()
	model.step(0.0156)
	model.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	var forced := _fits(model).duplicate()
	await process_frame
	_check(
		forced.size() == 1 and absf(forced[0] - 0.0156) < 0.000001 and _fits(model).size() == 1 and _updates == 1,
		"a step on the tick with the update forced is fitted there, by the step's time, and not again at the frame's end (%s, then %d fits)"
			% [str(forced), _fits(model).size()]
	)
	_clear(model)
	model.step(0.01)
	model.step(0.02)
	await process_frame
	_check(
		_fits(model).size() == 1 and absf(float(_fits(model)[0]) - 0.03) < 0.000001,
		"two steps in one frame are one fit, by both steps' time (%s s)" % str(_fits(model))
	)
	model.free()


## A pose set by anything but a step is fitted in its frame all the same,
## given no time, which the feet and the hands take as a fit to make at
## once: a body posed at once where it spawns (pose_now) or comes back
## (pose_again), with its feet and hands told first what it does now, and
## the bones a ragdoll writes, whose twist bones follow.
func _test_a_pose_set_otherwise() -> void:
	var model := await _stepping()
	# Back on the ground where it respawns, having lain dead: its feet were
	# told nothing while it lay.
	model._on_ground = true
	model.foot_plant.planting = false
	model.pose_again()
	var planting := model.foot_plant.planting
	await process_frame
	var again := _fits(model).duplicate()
	var updates_again := _updates
	_clear(model)
	var skeleton := model.character_rig
	skeleton.set_bone_global_pose(1, Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.0, 0.3, 0.0)))
	await process_frame
	_check(
		again == [0.0] and updates_again == 1 and _fits(model) == [0.0] and _updates == 1,
		"a pose set without a step is fitted in its frame, given no time: posed at once as it comes back (%s), and a bone a ragdoll wrote (%s)"
			% [str(again), str(_fits(model))]
	)
	_check(planting, "posed at once, its feet are told first what it does now: on the ground, they plant")
	model.free()


## A death switches the feet and the hands off: fitted once there, the
## other modifiers running by no time. A body that has stopped animating,
## whose bones nothing moves (a ragdoll at rest), is fitted in no frame and
## for no tick; the skeleton's own default fitted it in every frame for the
## rest of the round. Getting up switches them on: fitted once, at once.
func _test_dying_and_at_rest() -> void:
	var model := await _stepping()
	model.set_animating(false)
	await process_frame
	var died := _fits(model).duplicate()
	var updates_died := _updates
	_clear(model)
	for i in 6:
		await _frame(model, i % 2 == 0)
		model.position += Vector3(1.0, 0.0, 0.0)
		model.fit_for_tick()
	_check(
		died == [0.0] and updates_died == 1 and not model.foot_plant.active and not model.hand_grip.active,
		"switching the feet and the hands off as it dies fits it once, the other modifiers by no time (%s)" % str(died)
	)
	_check(
		_fits(model).is_empty() and _updates == 0,
		"a body not animating whose bones nothing moves, as a ragdoll at rest, is fitted in no frame and for no tick, moved or not (%d fits in 6)" % _fits(model).size()
	)
	model.set_animating(true)
	await process_frame
	_check(
		_fits(model) == [0.0] and _updates == 1 and model.foot_plant.active and model.hand_grip.active,
		"switching them on as it gets up fits it once, at once (%s)" % str(_fits(model))
	)
	model.character_rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	model.set_animating(false)
	await process_frame
	_clear(model)
	for i in 6:
		await process_frame
	_check(
		_fits(model).size() >= 6,
		"where the skeleton's own default fits a body at rest in every frame all the same (%d in 6)" % _fits(model).size()
	)
	model.free()
