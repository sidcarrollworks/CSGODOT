extends "res://tests/check_suite.gd"

## Jump heights against CS2's movement (server.dll 1.41.8.8; Sid's dust2
## playtest of 2026-10-05, reference/playtest-2026-10-05.md issue 8):
## the standing jump; a duck in the air lifting the feet half the hulls'
## difference (FinishDuck 180abdbe0), the eyes held by the duck root offset
## and brought down by the eye update (180ae23e0); the whole impulse ducked
## (180adf830); and a jump soon after a landing scaled down (180ab21a0),
## the landing timed within its interval (180ad3840). On a flat Box3D floor,
## every step run by the script and the native code alike where the native
## code is built.
##
##   godot --headless --path . --script tests/run_jump_height_checks.gd

var _host: Node3D
var _world: GameWorld
var DT := SimClock.tick_seconds()


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("jump-height", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	await _check_standing_and_crouch_jumps()
	await _check_ducked_jump()
	await _check_the_eyes_through_a_crouch_jump()
	await _check_a_jump_after_a_landing()
	_finish("jump-height")


## The highest the feet go over the floor from a jump taken on this tick,
## a duck pressed after takeoff when duck_after is not negative.
func _jump(player: PlayerBody, duck_after: int = -1) -> float:
	var start_y := player.position.y
	var peak := start_y
	player.wants_jump = true
	player.simulate(DT)
	player.wants_jump = false
	for tick in 70:
		if tick == duck_after:
			player.wants_duck = true
		player.simulate(DT)
		peak = maxf(peak, player.position.y)
	player.wants_duck = false
	for tick in 30:
		player.simulate(DT)
	return peak - start_y


func _check_standing_and_crouch_jumps() -> void:
	var player := await _start()
	var standing := _jump(player)
	_check(absf(standing - 55.8255) < 0.02 and player.on_ground,
		"a standing jump's feet rise CS2's 55.83 (sampled at 64 Hz: %.4f)" % standing)
	for tick in 30:
		player.simulate(DT)
	var crouched := _jump(player, 2)
	_check(absf(crouched - standing - 9.0) < 0.02,
		"a duck in the air lifts the feet half the hulls' difference, 9 over the standing jump, as CS2's FinishDuck, where Source lifted 18 (%.4f)" % crouched)
	_close()
	await process_frame


func _check_ducked_jump() -> void:
	var player := await _start()
	player.wants_duck = true
	for tick in 40:
		player.simulate(DT)
	_check(player.is_ducked and player.on_ground, "held long enough, the duck is finished on the ground")
	var start_y := player.position.y
	var peak := start_y
	player.wants_jump = true
	player.simulate(DT)
	player.wants_jump = false
	for tick in 70:
		player.simulate(DT)
		peak = maxf(peak, player.position.y)
	_check(absf(peak - start_y - 57.0) < 0.03,
		"ducked, the jump is the whole impulse without CS2's half-tick of gravity taken off: 57.00 where standing is 55.83 (%.4f)" % (peak - start_y))
	_close()
	await process_frame


## A crouch jump's eyes: where they were at the duck, held for 0.1 s as the
## root offset eases back while the view offset comes down, then 9 lower by
## 0.2 s, at the crouched 46 over feet that are 9 higher.
func _check_the_eyes_through_a_crouch_jump() -> void:
	var plain := await _start()
	var eyes := PackedFloat32Array()
	plain.wants_jump = true
	plain.simulate(DT)
	plain.wants_jump = false
	for tick in 16:
		plain.simulate(DT)
		eyes.append(plain.position.y + plain.eye_height())
	_close()
	await process_frame
	var ducking := await _start()
	ducking.wants_jump = true
	ducking.simulate(DT)
	ducking.wants_jump = false
	var held := true
	var at_duck := 0.0
	for tick in 16:
		if tick == 3:
			ducking.wants_duck = true
		ducking.simulate(DT)
		var eye := ducking.position.y + ducking.eye_height()
		if tick == 3:
			at_duck = eye - eyes[tick]
		if tick >= 3 and tick < 3 + 6:
			held = held and absf(eye - eyes[tick]) < 0.02
	_check(absf(at_duck) < 0.02 and held,
		"the eyes do not move at the duck, and follow the standing jump's for 0.1 s (%.4f at the duck)" % at_duck)
	_check(absf(ducking.duck_root_offset) < 0.0001 and absf(ducking.duck_view_offset + 18.0) < 0.0001,
		"by 0.2 s the root offset is back to 0 and the view offset at the crouched -18")
	var last := ducking.position.y + ducking.eye_height()
	_check(absf(last - (eyes[15] - 9.0)) < 0.02,
		"and the eyes are 9 below the standing jump's: the crouched 46 over feet 9 higher (%.4f)" % (last - eyes[15]))
	_close()
	await process_frame


## CS2 lowers a jump taken soon after a landing: from a flat landing at
## about -302 u/s, taken again at once it rises as fast times
## 1 - 0.0005 * 302 plus 0.6 of the time since, and whole after about
## 0.24 s.
func _check_a_jump_after_a_landing() -> void:
	var player := await _start()
	player.wants_jump = true
	player.simulate(DT)
	player.wants_jump = false
	var landed := false
	for tick in 70:
		player.simulate(DT)
		if player.on_ground:
			landed = true
			break
	_check(landed and player.landed_speed < -290.0 and player.landed_speed > -310.0,
		"a standing jump's landing is recorded, coming down at about the impulse (%.2f u/s)" % player.landed_speed)
	var start_y := player.position.y
	var peak := start_y
	# Pressed again: the next tick jumps at once.
	player.wants_jump = true
	player.simulate(DT)
	player.wants_jump = false
	for tick in 70:
		player.simulate(DT)
		peak = maxf(peak, player.position.y)
	var again := peak - start_y
	_check(again > 38.0 and again < 45.0,
		"jumping again at once rises far lower, CS2's scale for a jump soon after a landing (%.4f)" % again)
	for tick in 30:
		player.simulate(DT)
	var rested := _jump(player)
	_check(absf(rested - 55.8255) < 0.02, "a jump taken well after the landing rises whole (%.4f)" % rested)
	_close()
	await process_frame


func _start() -> PlayerBody:
	_host = Node3D.new()
	root.add_child(_host)
	var floor := StaticBody3D.new()
	floor.position = Vector3(0.0, -8.0, 0.0)
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2048.0, 16.0, 2048.0)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	_host.add_child(floor)
	var player := PlayerBody.new()
	player.collision_layer = 2
	player.collision_mask = 1 | 2 | MapImporter.PLAYER_CLIP_LAYER
	var collision := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(32.0, 72.0, 32.0)
	collision.shape = hull
	collision.position.y = 36.0
	player.add_child(collision)
	_host.add_child(player)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, "box3d")
	await physics_frame
	for tick in 24:
		player.simulate(DT)
	return player


func _close() -> void:
	_host.free()
