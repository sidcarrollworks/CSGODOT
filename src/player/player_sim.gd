class_name PlayerSim
extends PlayerBody

## One player in the simulation, human or bot: the body, the weapon, health
## and armour, death and respawn, run forward one tick at a time by commands.
##
## This is the part a server runs. It takes a UserCmd per tick
## (run_command) and nothing else: no keys, no mouse, no wall clock, no
## camera, no sound. What a player sees and hears of it is drawn by a view
## that reads its state and listens to its signals (PlayerView for you, the
## bot's own model for a bot), so the same simulation runs the same way
## whether anyone is watching it or not. That is what lets a client later
## run its own player ahead of the server on the same code, and a server run
## everyone from the commands they send.
##
## Where the local player's keys become commands is PlayerInput; where a
## bot's decisions do is Bot.

## The side the player is on.
@export_enum("T", "CT") var team: String = "T"

## How long death lasts before the respawn.
@export var respawn_seconds: float = 3.0

## Where the player is looking, from the last command, in degrees.
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0

## The weapon held, and how the player was moving when it was last told:
## what its cone is judged by.
var weapon: Weapon
var shooter_state := Weapon.ShooterState.new()
var rounds_fired: int = 0

## Health and armour, and what a round can hit.
var hit_target: HitTarget
var alive: bool = true

## The last command run, for whatever draws the player.
var last_command := UserCmd.new()


## A round left the weapon and was traced to where it landed.
signal shot_traced(shot: Weapon.Shot, result: Hitscan.Result)
## The weapon started reloading.
signal reload_started
## A new weapon is in hand.
signal equipped(data: WeaponData)
## Health ran out; zone is where the last round landed.
signal killed(zone: StringName)
signal respawned

var _respawn_at_usec: int = 0
var _spawn_position: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"players")
	hit_target = _build_hit_target()
	hit_target.name = "HitTarget"
	add_child(hit_target)
	hit_target.died.connect(_on_hit_target_died)


## The player's hitboxes. The stand-in: HitTarget's own boxes, with no body
## drawn. A bot wears the model's capsules instead.
func _build_hit_target() -> HitTarget:
	var target := HitTarget.new()
	target.build_visual = false
	return target


## Swaps to a weapon, which also changes how fast you can run.
func equip(data: WeaponData) -> void:
	weapon = Weapon.new(data)
	weapon.trigger_held = false
	config.max_speed = data.max_player_speed
	equipped.emit(data)


## What a command's weapon_select asks for, until there is an inventory:
## 1 the AK-47, 2 the M4A1-S.
static func weapon_for_slot(slot: int) -> WeaponData:
	match slot:
		1:
			return WeaponLibrary.ak47()
		2:
			return WeaponLibrary.m4a1s()
	return null


## Where the map put the player, to come back to.
func place(spawn_position: Vector3, yaw: float) -> void:
	_spawn_position = spawn_position
	_spawn_yaw = yaw
	global_position = spawn_position
	previous_position = spawn_position
	yaw_degrees = yaw
	pitch_degrees = 0.0


func seconds_to_respawn() -> float:
	return maxf(0.0, float(_respawn_at_usec - SimClock.now_usec()) / 1_000_000.0)


## Runs the player forward one tick.
func run_command(cmd: UserCmd, dt: float) -> void:
	last_command = cmd
	wants_jump = false
	wants_duck = false
	jump_fraction = -1.0
	wish_dir = Vector3.ZERO
	wish_speed = 0.0

	if cmd.toggle_noclip:
		noclip = not noclip
		velocity = Vector3.ZERO

	if not alive:
		if SimClock.tick_end_usec(cmd.tick) >= _respawn_at_usec:
			respawn()
		return

	var selected := weapon_for_slot(cmd.weapon_select)
	if selected != null:
		equip(selected)

	yaw_degrees = cmd.yaw_degrees
	pitch_degrees = cmd.pitch_degrees

	var reload := cmd.first_press(UserCmd.RELOAD)
	if reload != null and weapon != null:
		if weapon.start_reload(SimClock.usec_at(cmd.tick, reload.when)):
			reload_started.emit()

	# A tap shorter than a tick still jumps: the press is in the command even
	# if the key is back up by its end. The earliest press is the one that
	# jumps, and the tick splits there (PlayerBody.simulate). A jump from a
	# held key has no transition to time, so it stays at the tick's start.
	var jump := cmd.first_press(UserCmd.JUMP)
	wants_jump = cmd.held(UserCmd.JUMP) or jump != null
	if jump != null:
		jump_fraction = jump.when
	wants_duck = cmd.held(UserCmd.DUCK)

	if noclip:
		wish_dir = _noclip_direction(cmd)
		simulate(dt)
		return

	wish_dir = cmd.wish_direction()
	if wish_dir.length_squared() > 0.0:
		wish_speed = _max_speed(cmd)

	simulate(dt)
	_update_weapon(cmd, dt)


## Fires every round the command asks for, at the instant and the aim it
## asked for it: each press at its own fraction of the tick and its own look
## angles, then, while the trigger is held, the next round the moment the
## weapon is ready rather than on the tick after (on the tick, every gap
## rounds up to whole ticks and 600 rounds a minute comes out at 591).
func _update_weapon(cmd: UserCmd, dt: float) -> void:
	if weapon == null:
		return

	var now := SimClock.tick_end_usec(cmd.tick)
	weapon.finish_reload_if_due(now)
	# The weapon is told about the trigger rather than left to infer it from
	# the gap since the last round, so the crosshair starts coming home on the
	# tick the button comes up instead of a round and a quarter later. A press
	# that happened and ended inside the tick still counts as held for it.
	var presses := cmd.presses(UserCmd.ATTACK)
	weapon.trigger_held = cmd.held(UserCmd.ATTACK) or not presses.is_empty()
	shooter_state = Weapon.ShooterState.new(
		Vector2(velocity.x, velocity.z).length(), on_ground, is_ducked,
		cmd.held(UserCmd.WALK)
	)
	weapon.update(dt, now, shooter_state)

	for press in presses:
		_try_shoot(
			SimClock.usec_at(cmd.tick, press.when), press.when,
			press.yaw_degrees, press.pitch_degrees
		)

	if cmd.held(UserCmd.ATTACK):
		var began := SimClock.tick_start_usec(cmd.tick)
		var at := clampi(weapon.next_shot_usec(), began, now)
		_try_shoot(
			at, float(at - began) / float(SimClock.tick_usec()),
			cmd.yaw_degrees, cmd.pitch_degrees
		)


func _try_shoot(at_usec: int, tick_fraction: float, yaw: float, pitch: float) -> void:
	# The round leaves from where the player was at that instant, not from
	# where the tick left them. CS2 sends this as an explicit shoot_position.
	# At 250 u/s, skipping it puts the muzzle up to ~1.6 units from where it
	# belongs, which is exactly the strafe-and-tap case that hit registration
	# arguments are made of.
	var at := previous_position.lerp(global_position, clampf(tick_fraction, 0.0, 1.0))
	var origin := at + Vector3.UP * eye_height()
	var shot := weapon.fire(at_usec, tick_fraction, origin, yaw, pitch, shooter_state)
	if shot == null:
		return
	rounds_fired += 1

	# Your own hull and hitboxes are not targets.
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(hit_target.rids())
	var result := Hitscan.fire_at(get_world_3d().direct_space_state, shot, weapon.data, exclude)
	shot_traced.emit(shot, result)


## Noclip flies where you are looking, pitch included, with jump and duck for
## straight up and down.
func _noclip_direction(cmd: UserCmd) -> Vector3:
	var pitch := deg_to_rad(cmd.pitch_degrees)
	var yaw := deg_to_rad(cmd.yaw_degrees)
	var forward := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))

	var direction := forward * cmd.move.y + right * cmd.move.x
	if cmd.held(UserCmd.JUMP):
		direction += Vector3.UP
	if cmd.held(UserCmd.DUCK):
		direction += Vector3.DOWN
	if direction.length_squared() == 0.0:
		return Vector3.ZERO
	return direction.normalized()


func _max_speed(cmd: UserCmd) -> float:
	var speed := config.max_speed
	if is_ducked:
		speed *= config.duck_modifier
	elif cmd.held(UserCmd.WALK):
		speed *= config.walk_modifier
	return speed


## Dead: still, out of reach of rounds, until the respawn. Whatever answers
## `killed` still sees the velocity the player died with (a bot's ragdoll
## falls the way it was going).
func _on_hit_target_died() -> void:
	alive = false
	hit_target.set_active(false)
	_respawn_at_usec = SimClock.now_usec() + int(respawn_seconds * 1_000_000.0)
	var zone: StringName = hit_target.last_hitbox.zone if hit_target.last_hitbox != null else &"chest"
	killed.emit(zone)
	velocity = Vector3.ZERO


## Back where the map put the player, whole and reloaded.
func respawn() -> void:
	alive = true
	hit_target.reset()
	hit_target.set_active(true)
	place(_spawn_position, _spawn_yaw)
	velocity = Vector3.ZERO
	if weapon != null:
		equip(weapon.data)
	respawned.emit()
