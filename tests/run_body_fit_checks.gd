extends "res://tests/check_suite.gd"

## Checks when a body's skeleton is fitted, without the extracted models.
## Fitting is running its modifiers: the feet on the floor (FootPlant), the
## hands on the gun (HandGrip), the twist bones (TwistModifier). After it
## the skin is sent and skeleton_updated moves the hitboxes, the gun and the
## eyes to the bones. A stand-in body with one clip turning one bone, and a
## modifier that writes down each time it runs and the time it is given.
##
## A skeleton's own default fits it in every frame, whether its pose changed
## or not. A body that steps its own animation (PlayerModel.step_off_tick_frames)
## is fitted in a frame whose pose changed and in no other, by the time its
## animation moved on (PlayerModel.step). Nine bodies nobody sees skip every
## frame that runs a tick; each fit skipped was 0.07 ms of that frame
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
	# As the feet and the hands do: it writes a bone.
	skeleton.set_bone_pose_position(2, skeleton.get_bone_pose_position(2) + Vector3(0.0, 0.01, 0.0))
"""

var _recorder_script: GDScript
var _updates := 0


func _initialize() -> void:
	_recorder_script = GDScript.new()
	_recorder_script.source_code = RECORDER
	_recorder_script.reload()
	await process_frame
	await _test_a_body_not_stepped_by_hand()
	await _test_fitted_when_it_steps()
	await _test_every_moment_given()
	await _test_a_pose_set_otherwise()
	await _test_at_rest()
	_finish("body-fit")


func _print_passes() -> bool:
	return true


## A body on a three-bone rig whose clip turns the middle bone by a radian a
## second, and a recorder as its skeleton's last modifier.
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
	var recorder := SkeletonModifier3D.new()
	recorder.name = "Recorder"
	recorder.set_script(_recorder_script)
	skeleton.add_child(recorder)
	skeleton.skeleton_updated.connect(func() -> void: _updates += 1)
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


## One frame of the body's own, as the engine runs it (PlayerModel._process),
## said to have run a tick or not, and the frame's end, where the skeleton
## is fitted if it is to be.
func _frame(model: PlayerModel, ticked: bool) -> void:
	model._last_physics_frame = Engine.get_physics_frames() - (1 if ticked else 0)
	model._process(FRAME)
	await process_frame


## A body not stepped by hand (your own, seen every frame and bent as you
## look down) keeps the skeleton's own way: fitted every frame.
func _test_a_body_not_stepped_by_hand() -> void:
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
		"a body not stepped by hand, as your own is, keeps the skeleton's own way: fitted in every frame (%d fits in 4 frames)" % _fits(model).size()
	)
	model.free()


## Stepped by hand, a body is fitted once in a frame it steps, by the time
## it stepped, over the pose the step made; in a frame it does not, not at
## all.
func _test_fitted_when_it_steps() -> void:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	model.step_off_tick_frames()
	model.set_process(false)
	await process_frame
	await process_frame
	_check(
		model.stepped_by_hand
			and model.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			and model.character_rig.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL,
		"a body that steps its own animation fits its own skeleton too"
	)
	_clear(model)
	model._unstepped = 0.0
	for i in 3:
		await _frame(model, true)
	_check(
		_fits(model).is_empty() and _updates == 0,
		"three frames that each ran a tick, in which a body nobody sees does not step, fit it in none (%d fits, %d updates): nothing is fitted again to the pose it had, sent to the skin, or moved to the bones"
			% [_fits(model).size(), _updates]
	)
	await _frame(model, false)
	var fits := _fits(model)
	var turned := _recorder(model).get(&"turned") as Array
	_check(
		fits.size() == 1 and is_equal_approx(fits[0], 4.0 * FRAME) and _updates == 1,
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
## rate, the fits are given all the time that passed, none of it twice.
## The feet and the hands ease by the time they are given, by the same
## amounts whether that comes as one fit or as several.
func _test_every_moment_given() -> void:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	model.step_off_tick_frames()
	model.set_process(false)
	await process_frame
	_clear(model)
	model._unstepped = 0.0
	var frames := 60
	var stepping := 0
	for i in frames:
		var ticked := i % 3 == 0
		if not ticked:
			stepping += 1
		await _frame(model, ticked)
	var given := 0.0
	for delta: float in _fits(model):
		given += delta
	_check(
		_fits(model).size() == stepping and _updates == stepping,
		"%d frames, one in three running a tick: fitted in the %d that stepped and no other (%d fits, %d updates)"
			% [frames, stepping, _fits(model).size(), _updates]
	)
	_check_near(
		given + model._unstepped, frames * FRAME,
		"and given all the time that passed, none of it twice (%.4f s given and %.4f still to step, of %.4f)"
			% [given, model._unstepped, frames * FRAME]
	)
	model.free()


## A pose set by anything but a step is fitted in its frame all the same,
## given no time, which the feet and the hands take as a fit to make at
## once: a body posed at once where it spawns (pose_now) or comes back
## (pose_again), and the bones a ragdoll writes, whose twist bones follow.
func _test_a_pose_set_otherwise() -> void:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	model.step_off_tick_frames()
	model.set_process(false)
	await process_frame
	await process_frame
	_clear(model)
	model.pose_again()
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
	model.free()


## A body that has stopped animating, whose bones nothing moves (a ragdoll
## at rest), is fitted in no frame; the skeleton's own default fitted it in
## every one, for the rest of the round.
func _test_at_rest() -> void:
	var model := _stand_in()
	root.add_child(model)
	model.animation_player.play(&"turn")
	model.step_off_tick_frames()
	model.set_process(false)
	await process_frame
	model.set_animating(false)
	await process_frame
	_clear(model)
	for i in 6:
		await _frame(model, i % 2 == 0)
	_check(
		_fits(model).is_empty() and _updates == 0,
		"a body not animating whose bones nothing moves, as a ragdoll at rest, is fitted in no frame (%d fits in 6)" % _fits(model).size()
	)
	model.character_rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	_clear(model)
	for i in 6:
		await process_frame
	_check(
		_fits(model).size() >= 6,
		"where the skeleton's own default fits it in every one all the same (%d in 6)" % _fits(model).size()
	)
	model.free()
