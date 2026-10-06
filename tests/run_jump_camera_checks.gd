extends "res://tests/check_suite.gd"

## First-person jump dip/recovery, independent of extracted models. Holds
## the camera integration as well as smoothness, clocks and drawing rates.

class BarePlayer extends PlayerController:
	func _ready() -> void:
		pass


func _initialize() -> void:
	_test_dip_and_recovery()
	_test_falls()
	_test_clocks_and_resets()
	_test_drawing_rates()
	_test_viewmodel_jump_strength()
	await process_frame
	_test_player_view()
	_test_view_of_a_bot_taken_over()
	_finish("jump-camera")


func _test_dip_and_recovery() -> void:
	var motion := JumpCameraMotion.new()
	_check(is_zero_approx(motion.update_at(0, PlayerBody.NO_AIR_ACTION, 0)), "a fresh view starts at the ordinary eyes")
	_check(is_zero_approx(motion.update_at(900000, PlayerBody.NO_AIR_ACTION, 0)), "walking on the ground adds no camera bob")
	_check(is_zero_approx(motion.update_at(1000000, PlayerBody.AIR_JUMP, 1000000)), "takeoff starts continuously, without changing camera height at once")
	var deepest := motion.update_at(1050000, PlayerBody.AIR_JUMP, 1000000)
	_check(deepest < -0.5 and deepest > -1.5, "takeoff adds a small visible vertical dip")
	_check_near(deepest, -55.0 * 0.05 * exp(-20.0 * 0.05), "halving the viewmodel jump movement keeps the accepted camera takeoff strength")
	var recovering := motion.update_at(1150000, PlayerBody.AIR_JUMP, 1000000)
	_check(recovering > deepest and recovering < 0.0, "the eyes rise smoothly from the takeoff dip")
	_check(absf(motion.update_at(1400000, PlayerBody.AIR_JUMP, 1000000)) < 0.01, "the takeoff dip settles during flight, without being retriggered each frame")
	var before_land := motion.update_at(1800000, PlayerBody.AIR_JUMP, 1000000)
	var landing := motion.update_at(1800000, PlayerBody.AIR_LAND, 1800000)
	_check(absf(landing - before_land) < 0.0001, "landing also starts without an instantaneous height change")
	var land_dip := motion.update_at(1850000, PlayerBody.AIR_LAND, 1800000)
	_check(land_dip < -0.7 and land_dip > -0.95, "a normal jump lands with about 0.8 units of camera dip, half the 1.6 it was (Sid, 2026-10-06)")
	var rise := motion.update_at(1950000, PlayerBody.AIR_LAND, 1800000)
	_check(rise > land_dip and rise <= 0.0, "landing rises toward the usual eyes without overshooting above them")
	for i in range(1, 51):
		var dip := motion.update_at(1950000 + i * 10000, PlayerBody.AIR_LAND, 1800000)
		_check(dip >= -JumpCameraMotion.MAX_DIP and dip <= 0.00001, "the recovery stays within the vertical camera bounds (%d)" % i)
	_check(is_zero_approx(motion.update_at(2500000, PlayerBody.AIR_LAND, 1800000)), "the eyes come completely to rest after a landing")


func _test_falls() -> void:
	var ledge := JumpCameraMotion.new()
	ledge.update_at(0, PlayerBody.NO_AIR_ACTION, 0)
	_check(is_zero_approx(ledge.update_at(1000000, PlayerBody.AIR_START_FALL, 1000000)), "walking off a ledge does not invent a jump takeoff")
	ledge.update_at(1040000, PlayerBody.AIR_LAND, 1040000)
	_check(is_zero_approx(ledge.update_at(1090000, PlayerBody.AIR_LAND, 1040000)), "a brief loss of ground on a step causes no landing shake")
	var falling := JumpCameraMotion.new()
	falling.update_at(0, PlayerBody.NO_AIR_ACTION, 0)
	falling.update_at(1000000, PlayerBody.AIR_START_FALL, 1000000)
	_check(is_zero_approx(falling.update_at(1250000, PlayerBody.AIR_START_FALL, 1000000)), "falling follows the physical height without an extra airborne wave")
	falling.update_at(1450000, PlayerBody.AIR_LAND, 1450000)
	var land_dip := falling.update_at(1500000, PlayerBody.AIR_LAND, 1450000)
	_check(land_dip < -0.7, "a longer fall gets a landing dip too")
	_check_near(land_dip, -JumpCameraMotion.LAND_PUSH * 0.05 * exp(-20.0 * 0.05), "the landing's dip is its push over the spring")
	var before_jump := falling.update_at(1500000, PlayerBody.AIR_LAND, 1450000)
	_check(absf(falling.update_at(1500000, PlayerBody.AIR_JUMP, 1500000) - before_jump) < 0.0001, "jumping during recovery preserves the height instead of snapping it to zero")


func _test_clocks_and_resets() -> void:
	var future := JumpCameraMotion.new()
	future.update_at(0, PlayerBody.NO_AIR_ACTION, 0)
	_check(is_zero_approx(future.update_at(999000, PlayerBody.AIR_JUMP, 1000000)), "a received takeoff waits until the drawn position reaches its tick")
	_check(future.update_at(1050000, PlayerBody.AIR_JUMP, 1000000) < -0.5, "a late drawn frame starts at the correct age of the takeoff")
	var paused := future.height
	_check(is_equal_approx(future.update_at(1050000, PlayerBody.AIR_JUMP, 1000000), paused), "a stopped draw clock neither advances nor repeats the impulse")
	future.reset()
	_check(is_zero_approx(future.update_at(1100000, PlayerBody.AIR_JUMP, 1000000)), "reset clears the dip and does not replay the old takeoff")
	_check(future.update_at(1250000, PlayerBody.AIR_JUMP, 1200000) < -0.5, "a new jump works after a reset")
	_check(is_zero_approx(future.update_at(0, PlayerBody.NO_AIR_ACTION, 0)), "a restarted simulation clock clears the old spring")
	var first_future := JumpCameraMotion.new()
	first_future.update_at(990000, PlayerBody.AIR_JUMP, 1000000)
	_check(first_future.update_at(1050000, PlayerBody.AIR_JUMP, 1000000) < -0.5, "even a view's first frame preserves a future jump until its tick is drawn")


func _at_rate(rate: int) -> float:
	var motion := JumpCameraMotion.new()
	motion.update_at(0, PlayerBody.NO_AIR_ACTION, 0)
	for frame in range(1, ceili(2.05 * rate) + 1):
		var now := mini(roundi(float(frame) / rate * 1000000.0), 2050000)
		var action := PlayerBody.NO_AIR_ACTION
		var at := 0
		if now >= 1900000:
			action = PlayerBody.AIR_JUMP
			at = 1900000
		elif now >= 1800000:
			action = PlayerBody.AIR_LAND
			at = 1800000
		elif now >= 1000000:
			action = PlayerBody.AIR_JUMP
			at = 1000000
		motion.update_at(now, action, at)
	return motion.height


func _test_drawing_rates() -> void:
	var reference := _at_rate(240)
	for rate in [30, 60, 144, 224]:
		_check(absf(_at_rate(rate) - reference) < 0.00001, "jump/landing/repeated-jump motion has the same height at %d and 240 FPS" % rate)


func _test_viewmodel_jump_strength() -> void:
	var camera_motion := JumpCameraMotion.new()
	camera_motion.update_at(0, PlayerBody.NO_AIR_ACTION, 0)
	var with_jump := ViewModelMotion.new()
	var without_jump := ViewModelMotion.new()
	var previous := 0
	for now: int in [1000000, 1050000, 1150000, 1400000, 1800000, 1850000, 1950000, 2500000]:
		var on_ground := now >= 1800000
		var action := PlayerBody.AIR_LAND if on_ground else PlayerBody.AIR_JUMP
		var action_usec := 1800000 if on_ground else 1000000
		var dip := camera_motion.update_at(now, action, action_usec)
		var delta := float(now - previous) / 1000000.0
		var velocity := Vector3(0.0, 0.0, -250.0)
		var look := Vector2(37.0, -20.0)
		var drawn := with_jump.update(delta, velocity, on_ground, look, dip)
		var base := without_jump.update(delta, velocity, on_ground, look)
		# The previous model scale was 1.0: assert the new strength against
		# that baseline through takeoff, flight, landing and both recoveries.
		_check_near(drawn.origin.y - base.origin.y, dip * 0.5, "the current viewmodel jump movement is exactly half strength at %d usec" % now)
		_check(is_equal_approx(drawn.origin.x, base.origin.x) and is_equal_approx(drawn.origin.z, base.origin.z)
			and drawn.basis.is_equal_approx(base.basis), "halving the jump dip preserves the running bob, settle and sway at %d usec" % now)
		previous = now


func _test_player_view() -> void:
	# A controller without models, audio or a live world. Exercise the real
	# PlayerView placement while the draw fraction is held at the tick's end.
	var world := GameWorld.new()
	GameWorld.current = world
	world.tick = 64
	var old_tick_clock := DrawClock._tick_clock_usec
	DrawClock._tick_clock_usec = Time.get_ticks_usec() - 1000000
	var player := BarePlayer.new()
	player.config = MovementConfig.new()
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.top_level = true
	player.global_position = Vector3(10, 20, 30)
	player.previous_position = player.global_position
	player.input.yaw_degrees = 37.0
	player.input.pitch_degrees = -20.0
	player.view = PlayerView.new(player)
	player.view.camera = player.camera
	var arms := Node3D.new()
	arms.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)).scaled(Vector3.ONE * 39.37), Vector3(1, 2, 3))
	player.camera.add_child(arms)
	player.view.viewmodel = arms
	player.view._read_for_team = player.team
	_test_eye_interpolation(player)
	player.view._process(1.0 / 224.0)
	var usual_eyes := player.camera.global_position
	var usual_basis := player.camera.global_basis
	var arms_rest := arms.transform
	_check(arms_rest.origin == Vector3(1, 2, 3), "at rest the viewmodel keeps its clip placement")
	player.on_ground = false
	player.air_action = PlayerBody.AIR_JUMP
	player.air_action_usec = SimClock.tick_end_usec(65)
	world.tick = 65
	player.view._process(1.0 / 224.0)
	world.tick = 68
	player.view._process(1.0 / 224.0)
	var shifted := player.camera.global_position
	_check(shifted.y < usual_eyes.y - 0.5 and shifted.y > usual_eyes.y - 1.5, "PlayerView applies the takeoff dip to the camera, not just the weapon")
	_check_near(arms.position.y - arms_rest.origin.y, (shifted.y - usual_eyes.y) * 0.5,
		"the arms takeoff movement relative to the camera is half its previous strength")
	_check(is_equal_approx(arms.position.x, arms_rest.origin.x) and is_equal_approx(arms.position.z, arms_rest.origin.z)
		and arms.basis.is_equal_approx(arms_rest.basis), "jump motion keeps the model's scale, rotation and sideways/forward placement")
	_check(is_equal_approx(shifted.x, usual_eyes.x) and is_equal_approx(shifted.z, usual_eyes.z)
		and player.camera.global_basis.is_equal_approx(usual_basis), "the dip moves only world height, without pitching or shifting aim sideways")
	_check(player.global_position == Vector3(10, 20, 30) and player.velocity == Vector3.ZERO
		and player.input.yaw_degrees == 37.0 and player.input.pitch_degrees == -20.0,
		"camera motion changes no player position, velocity or look input")
	player.duck_progress = 0.5
	# This fixture changes the state directly, without running movement.
	# Both completed tick endpoints are already at this crouched height.
	player.previous_eye_height = player.eye_height()
	player.view._process(1.0 / 224.0)
	_check(absf(player.camera.global_position.y - (20.0 + player.eye_height() + player.view.camera_motion.height)) < 0.0001, "the same dip is relative to the crouched eyes")
	player.on_ground = true
	player.air_action = PlayerBody.AIR_LAND
	player.air_action_usec = SimClock.tick_end_usec(113)
	world.tick = 113
	player.view._process(1.0 / 224.0)
	world.tick = 116
	player.view._process(1.0 / 224.0)
	_check_near(arms.position.y - arms_rest.origin.y, player.view.camera_motion.height * 0.5,
		"landing dips the arms at half their previous strength, including while crouched")
	world.tick = 157
	player.view._process(1.0 / 224.0)
	_check(arms.transform.is_equal_approx(arms_rest), "the arms return fully to their clip placement after landing")
	player.view.camera_motion.update_at(2700000, PlayerBody.AIR_JUMP, 2650000)
	player.noclip = true
	player.view._process(1.0 / 224.0)
	_check(is_equal_approx(player.camera.global_position.y, 20.0 + player.eye_height())
		and is_zero_approx(player.view.camera_motion.height), "noclip clears the dip and uses the usual eyes")
	_check(arms.transform.is_equal_approx(arms_rest), "noclip clears the viewmodel dip too")
	player.noclip = false
	player.view._process(1.0 / 224.0)
	_check(is_zero_approx(player.view.camera_motion.height), "leaving noclip does not replay an old jump")
	player.view.camera_motion.update_at(2700000, PlayerBody.AIR_JUMP, 2650000)
	_check(player.view.camera_motion.height < -0.5, "placement reset is checked during an active dip")
	player.place(Vector3(40, 20, 0), 120.0)
	_check(is_zero_approx(player.view.camera_motion.height), "place resets the camera for teleports and surviving players at round spawns")
	player.view.camera_motion.update_at(2800000, PlayerBody.NO_AIR_ACTION, 0)
	player.view.camera_motion.update_at(2950000, PlayerBody.AIR_JUMP, 2900000)
	_check(player.view.camera_motion.height < -0.5, "death reset is checked during an active dip")
	player.view._on_killed(&"head")
	_check(is_zero_approx(player.view.camera_motion.height), "death clears the first-person motion before the death/spectator camera")
	player.view._on_respawned()
	_check(is_zero_approx(player.view.camera_motion.height), "respawning starts at the ordinary eyes")
	player.view.free()
	player.view = null
	player.free()
	GameWorld.current = null
	world.free()
	DrawClock._tick_clock_usec = old_tick_clock


## Dead and taking over a bot, the view goes into the bot's eyes and looks
## the way it looked, and draws the bot's hand; the bot dying under you,
## the death camera goes to its body.
func _test_view_of_a_bot_taken_over() -> void:
	var world := GameWorld.new()
	GameWorld.current = world
	world.tick = 64
	var old_tick_clock := DrawClock._tick_clock_usec
	DrawClock._tick_clock_usec = Time.get_ticks_usec() - 1000000
	var player := BarePlayer.new()
	player.config = MovementConfig.new()
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.camera.top_level = true
	player.global_position = Vector3(10, 20, 30)
	player.previous_position = player.global_position
	player.view = PlayerView.new(player)
	player.view.camera = player.camera
	player.view._read_for_team = player.team
	var bot := PlayerSim.new()
	bot.is_bot = true
	bot.team = player.team
	root.add_child(bot)
	bot.set_physics_process(false)
	bot.global_position = Vector3(500, 0, 500)
	bot.previous_position = bot.global_position
	bot.yaw_degrees = 75.0
	bot.pitch_degrees = 5.0
	player.userid = 1
	bot.userid = 2
	var mode := Competitive.new()
	mode.player = player
	var sounds := HitSounds.new()
	var flash := FlashOverlay.new()
	mode._follow_recipient(sounds, &"listener_id")
	mode._follow_recipient(flash, &"viewer_id")
	var shots := ShotEffects.new()
	shots.you = player
	shots.listener_id = player.userid
	var hud := GameHud.new()
	hud.player = player
	hud.damage_indicator = DamageIndicator.new()
	hud.kill_feed = KillFeed.new()
	hud.kill_feed.watch(world.game, player.userid)
	player.control_changed.connect(hud._follow_damage_pawn)
	hud._follow_damage_pawn()

	player.alive = false
	player.respawns = false
	player.view._on_killed(&"head")
	_check(player.can_control(bot), "dead, a bot on your side may be taken over")
	player.take_control(bot)
	_check(shots._in_first_person(bot.userid) and not shots._in_first_person(player.userid),
		"taken over, the bot's muzzle is first person even though the controller is dead")
	_check(sounds.listener_id == bot.userid and flash.viewer_id == bot.userid,
		"hit audio and flash overlays follow the controlled bot's recipient")
	world.game.events.send(&"player_death", {"userid": 3, "attacker": bot.userid, "weapon": "weapon_ak47"})
	world.game.events.flush()
	_check(hud.kill_feed.notices()[0].yours == KillFeed.Yours.KILLER,
		"a controlled bot's kill receives the local-player kill-feed highlight")
	bot.hurt.emit(10.0, &"chest", Vector3(500, 0, 450))
	player.hurt.emit(10.0, &"chest", Vector3.ZERO)
	_check(hud.damage_indicator.showing() == 1,
		"damage directions listen to the bot, without also listening to the old body")
	player._on_control_changed()
	player.view._on_control_changed()
	_check(player.view._in_hand_due and player.view._in_hand_entry == bot.inventory.in_hand(), "its hand to be shown")
	player.view._process(1.0 / 224.0)
	_check(player.view.pawn == bot, "the view draws the bot from the inside")
	var eyes := bot.global_position + Vector3.UP * bot.eye_height()
	_check(player.camera.global_position.distance_to(eyes) < 0.01, "from its eyes (%s)" % player.camera.global_position)
	_check(is_equal_approx(player.input.yaw_degrees, 75.0) and is_equal_approx(player.input.pitch_degrees, 5.0)
		and absf(rad_to_deg(player.camera.global_rotation.y) - 75.0) < 0.01, "looking the way it looked")
	# The spectator's former gun must not drive the bot's drawn recoil.
	var arms := Node3D.new()
	player.camera.add_child(arms)
	player.view.viewmodel = arms
	player.view._viewmodel_rest = Transform3D.IDENTITY
	player.view._viewmodel_rest_captured = true
	bot.weapon = Weapon.new(WeaponLibrary.ak47())
	bot.weapon._model_aim_recoil.value = Vector2(2.0, -6.0)
	bot.previous_viewmodel_punch = bot.viewmodel_punch()
	player.view.viewmodel_motion = ViewModelMotion.new()
	player.view._update_viewmodel(0.0)
	var kick := bot.viewmodel_punch()
	_check(arms.basis.is_equal_approx(Basis.from_euler(Vector3(deg_to_rad(kick.y), deg_to_rad(-kick.x), 0.0))),
		"the controlled bot supplies the new aim-recoil follow channel to its drawn arms")

	bot.alive = false
	player._lose_control()
	_check(sounds.listener_id == player.userid and flash.viewer_id == player.userid
		and not shots._in_first_person(bot.userid) and hud.damage_indicator.showing() == 0,
		"given back, the recipient returns to the controller and clears the former pawn's damage arcs")
	world.game.events.send(&"player_death", {"userid": 3, "attacker": bot.userid, "weapon": "weapon_ak47"})
	world.game.events.flush()
	_check(hud.kill_feed.notices()[1].yours == KillFeed.Yours.NONE,
		"after returning control, another bot kill is no longer highlighted as yours")
	player.view._on_control_changed()
	player.view._process(1.0)
	var centre := bot.body_centre()
	_check(player.view.pawn == player and player.camera.global_position.distance_to(centre) > 60.0
		and player.camera.global_position.distance_to(centre) < PlayerView.DEATH_CAM_DISTANCE + 1.0,
		"it dies under you: the death camera on its body (%.0f units off)" % player.camera.global_position.distance_to(centre))
	player.view.free()
	player.view = null
	player.free()
	bot.free()
	GameWorld.current = null
	world.free()
	DrawClock._tick_clock_usec = old_tick_clock
	hud.damage_indicator.free()
	hud.kill_feed.free()
	hud.free()
	shots.free()
	flash.free()
	sounds.free()
	mode.free()


func _test_eye_interpolation(player: PlayerController) -> void:
	var position_before := player.global_position
	player.previous_position = Vector3(10.0, 12.0, 30.0)
	player.global_position = Vector3(30.0, 20.0, 40.0)
	player.previous_eye_height = 64.0
	# Fully crouched, the duck view offset at rest at the hulls' difference.
	player.duck_progress = 1.0
	player.duck_view_offset = -18.0
	_check_near(player.interpolated_eye_height(0.0), 64.0, "the previous tick's standing eye remains the interpolation start")
	_check_near(player.interpolated_eye_height(0.5), 55.0, "a halfway frame blends standing and crouched simulation eyes")
	_check_near(player.interpolated_eye_height(1.0), 46.0, "the current tick's crouched eye is the interpolation end")
	_check_near(player.interpolated_eye_height(-1.0), 64.0, "an early sample holds the previous simulation eyes")
	_check_near(player.interpolated_eye_height(2.0), 46.0, "a late sample holds the latest simulation eyes")
	for wanted: float in [0.0, 0.5, 1.0]:
		# Endpoints are clamped; the midpoint uses the real draw clock. Bound
		# its sample by the fractions just before and after camera placement,
		# so scheduler time does not turn this into a frame-duration test.
		var clock_offset := int(SimClock.tick_usec() * wanted)
		if wanted == 0.0:
			clock_offset = -1000000
		elif wanted == 1.0:
			clock_offset = 1000000
		DrawClock._tick_clock_usec = Time.get_ticks_usec() - clock_offset
		var before := DrawClock.fraction()
		player.view._process(1.0 / 224.0)
		var after := DrawClock.fraction()
		var from := player.previous_position.lerp(player.global_position, before) + Vector3.UP * player.interpolated_eye_height(before)
		var to := player.previous_position.lerp(player.global_position, after) + Vector3.UP * player.interpolated_eye_height(after)
		var drawn := player.camera.global_position
		var low := from.min(to) - Vector3.ONE * 0.001
		var high := from.max(to) + Vector3.ONE * 0.001
		_check(drawn.x >= low.x and drawn.x <= high.x and drawn.y >= low.y and drawn.y <= high.y
			and drawn.z >= low.z and drawn.z <= high.z,
			"the camera samples feet and eye height at the same draw fraction (%.1f)" % wanted)
		player.view._spectate(player)
		var spectator_fraction := DrawClock.fraction()
		var spectator_to := player.previous_position.lerp(player.global_position, spectator_fraction) \
			+ Vector3.UP * player.interpolated_eye_height(spectator_fraction)
		low = to.min(spectator_to) - Vector3.ONE * 0.001
		high = to.max(spectator_to) + Vector3.ONE * 0.001
		drawn = player.camera.global_position
		_check(drawn.x >= low.x and drawn.x <= high.x and drawn.y >= low.y and drawn.y <= high.y
			and drawn.z >= low.z and drawn.z <= high.z,
			"the spectator camera uses the same interpolated simulation eyes (%.1f)" % wanted)
	player.view._watch(null)
	player.global_position = position_before
	player.previous_position = position_before
	player.duck_progress = 0.0
	player.duck_view_offset = 0.0
	player.previous_eye_height = player.eye_height()
	DrawClock._tick_clock_usec = Time.get_ticks_usec() - 1000000
