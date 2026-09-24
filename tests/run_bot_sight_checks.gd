extends "res://tests/check_suite.gd"

## Checks what smoke and flashes do to a bot's sight: a smoke between it and
## a player hides them once the line runs through more than 200 units of it
## (bot_max_visible_smoke_length), and a line past its edge does not; a
## flash in its face blinds it by the same rules it blinds you, and blinded
## it sees nobody, fires where it last saw the one it was engaging, backs
## off when it was engaging nobody (out of its scope, at its gun's own
## speed), and sees again once the white fades.
##
##   godot --headless --path . --script tests/run_bot_sight_checks.gd
##
## Needs nothing extracted: bots without their model wear the standard
## boxes, and the ground is a box.

const WATCHER_AT := Vector3(0.0, 0.0, 0.0)
const TARGET_AT := Vector3(0.0, 0.0, -1000.0)
## Off to the side, so the line to it passes beside the smoke.
const TARGET_ASIDE := Vector3(600.0, 0.0, -1000.0)

var _stage: Node3D
var _world: GameWorld
var _grenades: GrenadeSystem


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_smoke()
	await _test_flash_while_engaging()
	await _test_flash_while_walking()
	await _test_flash_while_scoped()
	_finish("bot-sight")


## A world with a floor and the grenades, a T bot with an AK-47 (or the gun
## named) facing down -Z and a CT bot in front of it that never fires and
## never dies.
func _build(weapon_class: String = "weapon_ak47") -> Array[Bot]:
	_stage = Node3D.new()
	root.add_child(_stage)
	_world = GameWorld.new()
	_stage.add_child(_world)
	_world.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16384.0, 32.0, 16384.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	_stage.add_child(floor_body)
	_grenades = GrenadeSystem.new()
	_world.game.add_system(_grenades)
	var watcher := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	watcher.name = "Watcher"
	watcher.team = "T"
	watcher.weapon_data = WeaponLibrary.build(weapon_class)
	_stage.add_child(watcher)
	_world.add_player(watcher)
	watcher.place(WATCHER_AT, 0.0)
	var target := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	target.name = "Target"
	target.team = "CT"
	target.holds_fire = true
	_stage.add_child(target)
	_world.add_player(target)
	target.place(TARGET_AT, 180.0)
	target.hit_target.immortal = true
	_count_shots(watcher)
	await physics_frame
	return [watcher, target]


func _tear_down() -> void:
	_stage.queue_free()
	await physics_frame


func _step(seconds: float) -> void:
	for i in SimClock.ticks_in(seconds):
		_world.step()


## A grenade of a kind set off at a point, as if it had come to rest there
## past its fuse: it goes off on the next tick or two.
func _set_off(weapon_class: String, at: Vector3, thrower: int) -> void:
	var space := _stage.get_world_3d().direct_space_state
	var grenade := _grenades.throw_from(thrower, weapon_class, at, 0.0, -89.0, Vector3.ZERO, 0.0, space)
	grenade.flight.position = at
	grenade.flight.velocity = Vector3.ZERO
	grenade.flight.at_rest = weapon_class == GrenadeRules.SMOKE
	grenade.position = at
	grenade.thrown_usec = SimClock.now_usec() - 2_000_000 + SimClock.tick_usec()


# --- Smoke ------------------------------------------------------------------

func _test_smoke() -> void:
	var bots := await _build()
	var watcher: Bot = bots[0]
	var target: Bot = bots[1]
	watcher.holds_fire = true
	_check(watcher.can_see(target), "in the open, a bot sees a player in front of it")
	var eyes := watcher.global_position + Vector3.UP * watcher.eye_height()
	var theirs := target.global_position + Vector3.UP * target.eye_height()
	var halfway := eyes.lerp(theirs, 0.5)
	_set_off(GrenadeRules.SMOKE, Vector3(halfway.x, GrenadeRules.RADIUS, halfway.z), target.userid)
	_step(GrenadeRules.SMOKE_BLOOM_SECONDS + 0.25)
	var through := float(_world.game.query(&"smoke_length_between", [eyes, theirs], 0.0))
	_check(through > Bot.MAX_VISIBLE_SMOKE_LENGTH, "a smoke between them fills the line with %.0f units of smoke" % through)
	_check(not watcher.can_see(target), "and hides the player from the bot")
	watcher.holds_fire = false
	_step(Bot.REACTION_SECONDS + 0.25)
	_check(watcher.target == null, "so it engages nobody")
	target.place(TARGET_ASIDE, 180.0)
	_step(0.1)
	eyes = watcher.global_position + Vector3.UP * watcher.eye_height()
	theirs = target.global_position + Vector3.UP * target.eye_height()
	var beside := float(_world.game.query(&"smoke_length_between", [eyes, theirs], 0.0))
	_check(beside <= Bot.MAX_VISIBLE_SMOKE_LENGTH, "a line past the smoke's edge runs through %.0f units, no more than a bot sees through" % beside)
	_check(watcher.can_see(target), "and the bot sees the player there")
	_check(watcher.target == target, "and engages them")
	await _tear_down()


# --- Flashes ----------------------------------------------------------------

## Engaging a player when a flash goes off in its face: blind, it sees
## nobody, keeps firing where it last saw them, and sees them again once
## the white fades below the share.
func _test_flash_while_engaging() -> void:
	var bots := await _build()
	var watcher: Bot = bots[0]
	var target: Bot = bots[1]
	_step(Bot.REACTION_SECONDS + 0.3)
	_check(watcher.target == target, "a bot engages a player in front of it")
	var last_seen := target.global_position + Vector3.UP * 48.0
	var eyes := watcher.global_position + Vector3.UP * watcher.eye_height()
	var forward := PlayerInput.aim_direction(watcher.yaw_degrees, watcher.pitch_degrees)
	_set_off(GrenadeRules.FLASHBANG, eyes + forward * 100.0, target.userid)
	_step(0.1)
	var share := float(_world.game.query(&"blind_share", [watcher.userid], 0.0))
	_check(share > Bot.BLIND_SHARE and watcher.is_blind(), "a flash in its face blinds it (%.2f white)" % share)
	_check(watcher.target == null, "blinded, it engages nobody")
	# It moves the player away: a bot that could see would turn after them.
	target.place(TARGET_ASIDE, 180.0)
	var fired_before := _shots(watcher)
	var yaw_before := watcher.yaw_degrees
	_step(1.0)
	_check(watcher.target == null, "and does not see the player move")
	_check(_shots(watcher) > fired_before, "but keeps firing where it last saw them (%d rounds)" % (_shots(watcher) - fired_before))
	_check(absf(angle_difference(deg_to_rad(watcher.yaw_degrees), deg_to_rad(yaw_before))) < deg_to_rad(Bot.AIM_ERROR_DEGREES * 2.0 + 0.1),
		"still facing that spot, not the player")
	_check((watcher.global_position - WATCHER_AT).length() < 8.0, "standing its ground to fire")
	var blind := _grenades.blind_of(watcher.userid)
	var clears := float(blind.ends_usec() - SimClock.now_usec()) / 1_000_000.0 + Bot.REACTION_SECONDS + 0.5
	_step(clears)
	_check(not watcher.is_blind(), "the white fades")
	_check(watcher.target == target, "and it sees the player where they are now")
	_check(last_seen != target.global_position + Vector3.UP * 48.0, "(which is not where it last saw them)")
	await _tear_down()


## Walking, engaging nobody, when a flash goes off in its face: it backs off
## until it can see.
func _test_flash_while_walking() -> void:
	var bots := await _build()
	var watcher: Bot = bots[0]
	var target: Bot = bots[1]
	watcher.holds_fire = true
	target.place(Vector3(0.0, 0.0, 3000.0), 0.0)
	_step(0.1)
	var eyes := watcher.global_position + Vector3.UP * watcher.eye_height()
	var forward := PlayerInput.aim_direction(watcher.yaw_degrees, watcher.pitch_degrees)
	_set_off(GrenadeRules.FLASHBANG, eyes + forward * 100.0, target.userid)
	var start := watcher.global_position
	_step(1.0)
	_check(watcher.is_blind(), "a flash in its face blinds a bot engaging nobody")
	var moved := watcher.global_position - start
	var back := Vector3(sin(deg_to_rad(watcher.yaw_degrees)), 0.0, cos(deg_to_rad(watcher.yaw_degrees)))
	_check(moved.dot(back) > 50.0, "and it backs off (%.0f units back)" % moved.dot(back))
	_check(_shots(watcher) == 0, "without firing, having nobody to fire at")
	await _tear_down()


## Scoped with an AWP, engaging nobody, when a flash goes off in its face:
## backing off is walking, so the scope comes down and it backs off at the
## AWP's own speed rather than the scoped one.
func _test_flash_while_scoped() -> void:
	var bots := await _build("weapon_awp")
	var watcher: Bot = bots[0]
	var target: Bot = bots[1]
	watcher.holds_fire = true
	target.place(Vector3(0.0, 0.0, 3000.0), 0.0)
	# Drawn, then scoped by hand: holding its fire, it never scopes itself.
	_step(2.0)
	watcher.weapon.press_zoom(SimClock.now_usec())
	_step(0.1)
	_check_equal(watcher.weapon.zoom_level, 1, "an AWP bot standing scoped in")
	var eyes := watcher.global_position + Vector3.UP * watcher.eye_height()
	var forward := PlayerInput.aim_direction(watcher.yaw_degrees, watcher.pitch_degrees)
	_set_off(GrenadeRules.FLASHBANG, eyes + forward * 100.0, target.userid)
	var fastest := 0.0
	for i in SimClock.ticks_in(1.5):
		_world.step()
		fastest = maxf(fastest, Vector2(watcher.velocity.x, watcher.velocity.z).length())
	_check(watcher.is_blind(), "a flash in its face blinds it")
	_check_equal(watcher.weapon.zoom_level, 0, "backing off, it comes out of the scope")
	var scoped_speed := watcher.weapon.data.scoped.max_player_speed
	_check(fastest > scoped_speed + 20.0,
		"and backs off faster than it could scoped (%.0f u/s against %.0f)" % [fastest, scoped_speed])
	await _tear_down()


## How many rounds a bot has fired, as it traces them.
func _shots(bot: Bot) -> int:
	return int(bot.get_meta(&"shots", 0))


func _count_shots(bot: Bot) -> void:
	bot.shot_traced.connect(func(_shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		bot.set_meta(&"shots", int(bot.get_meta(&"shots", 0)) + 1))
