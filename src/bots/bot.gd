class_name Bot
extends PlayerSim

## A player that is not you. The same simulation as the local player
## (PlayerSim: body, hull, movement solver, weapon), run by the same kind of
## command, except that the command comes from what the bot decides rather
## than from keys. It wears the third-person model. It walks its route round
## and round, facing the way it goes: over the map's nav mesh where it has
## one, the way pulled taut round corners, crouching where the floor is under
## a low ceiling and jumping up where it rises past a step; in straight lines
## between the route's points where it has none. It can be shot: it wears
## the model's own hitboxes on its bones, goes limp and falls the way the last round
## pushed it (a ragdoll), and comes back at the start of its route (in a
## match, not until the next round, at the spawn point it is given). It shoots
## back: when a player of the other side is in its sight, in the open and
## within its cone for long enough to react, it stops, turns, and holds the
## trigger in bursts, so its rounds go through the weapon's own rate, spread
## and recoil exactly as yours do (a pistol tapped), and it reloads when it
## runs dry. On a map it spawns as you do, with the knife and its side's
## pistol, buys in freeze time as CS2's bot does (BotBuying), and takes its
## best gun out. It does not flinch, take cover or think.
##
## The point of it being the same simulation is that it moves and shoots
## like a player. A bot that walked on rails and fired by its own rules
## would be a different thing to shoot at than the players it stands in for.
##
## Its model is part of what it is, not just how it looks: the hitboxes ride
## the model's bones, so the model animates whether anyone sees it or not,
## as CS2's server animates everyone for their hitboxes.

## Where the bot goes, in order, in world units. It turns for the first
## point on arriving at the last.
@export var route: PackedVector3Array = PackedVector3Array()

## The floor it finds its way over (SourceNavMesh.walk_path), shared by
## every bot on the map; null walks the route in straight lines.
var nav_mesh: SourceNavMesh

## Close enough to a point to head for the next, in units.
@export var arrive_distance: float = 24.0

## How fast the bot turns to face its way, in degrees per second.
@export var turn_rate: float = 540.0

## What it holds: the model to draw, and the gun it is handed at every
## spawn (its starting_gun), which arm() puts in its hand. With no model
## given, its body holds whatever is in its hand, changing with it (a map's
## bots, who spawn with a pistol and buy the rest).
@export var weapon_model: String = ""
@export var weapon_data: WeaponData

## Which of botprofile.db's weapon templates it buys by in freeze time
## (BotBuying), and takes its best gun in hand after; empty never buys (the
## range's shooter and dummy, which are handed their guns).
@export var buy_template: StringName = &""

## Sight: how far and how wide it sees, in units and degrees either side
## of where it faces, and how long a player has to be in sight before it
## acts. Then it fires in bursts, with a little error on top of the
## weapon's own, and turns at its turn rate.
const SIGHT_RANGE := 3000.0
const SIGHT_HALF_ANGLE := 75.0
const REACTION_SECONDS := 0.5
const BURST_SECONDS := 0.6
const PAUSE_SECONDS := 0.45
## A semi-automatic gun fires once a press, so it is tapped: CS2's bot at
## normal difficulty taps a pistol every half second
## (reference/research/round-hud-bots.md).
const TAP_SECONDS := 0.5
## When in freeze time it shops: this many ticks after it spawns, and up to
## SHOP_SPREAD_TICKS more, from its seed, so the bots' purchases (and the
## guns their bodies take up) do not all land on one tick. A choice: when
## CS2's bot buys in freeze time is in no file.
const SHOP_DELAY_TICKS := 16
const SHOP_SPREAD_TICKS := 48
const AIM_ERROR_DEGREES := 1.2
const FIRE_WITHIN_DEGREES := 6.0

## Walking a path: close enough to a corner to turn for the next, in units.
## Tighter than arrive_distance, since cutting a corner early walks the hull
## into the wall the corner is there for.
const CORNER_REACHED := 8.0
## Crouches this far, in plan, before an area whose ceiling is too low to
## stand under, so it is down by the time it gets there.
const CROUCH_AHEAD := 100.0
## Held up this long without getting anywhere, it finds its way again from
## where it is, and jumps, in case what holds it is a lip the mesh steps over.
const STUCK_SECONDS := 0.75
const STUCK_SPEED := 20.0
## A landing counts as reached when the feet are this close to its height.
const STEP_UP_OR_DOWN := 18.0
## It jumps for a landing only this close to the take-off, in plan, so it
## does not hop again on arriving.
const TAKE_OFF_REACH := 24.0
# How many bots may find their way over the mesh in one tick is the world's
# to say (GameWorld.PATH_SEARCHES_PER_TICK).

## Its body falling, while it is dead; null otherwise.

## Armed but not shooting: it sees nobody, so it stands or walks its route.
## The test range's shooter waits like this until it is told to fire.
@export var holds_fire: bool = false

## What it hears of its weapon, in the world.
var weapon_sounds: WeaponSounds
## The player it is engaging, or null.
var target: Node3D

signal died(zone: StringName)

var _next: int = 0
## The way to route[_next] over the nav mesh, and the corner of it it is
## heading for; null to find it again.
var _path: SourceNavMesh.WalkPath
var _corner: int = 0
var _stuck_for: float = 0.0
## The point of the route it found no way to over the mesh, so the way is
## not asked for again every tick; -1 when there is none.
var _no_way_to: int = -1
var _deaths: int = 0
var _seen_for: float = 0.0
var _burst_clock: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO
## The error in the angles it last sent, so the next command turns from where
## it meant to face rather than from where the error put it.
var _sent_error: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## The tick it shops on this round; -1 once it has, or when it will not.
var _shop_tick: int = -1
## Time to the next tap of a semi-automatic gun's trigger.
var _tap_clock: float = 0.0


func _init() -> void:
	# A dead bot lies there this long before it is back on its route.
	respawn_seconds = 5.0


func _ready() -> void:
	super._ready()
	killed.connect(_on_killed)
	shot_traced.connect(_on_shot_traced)
	reload_started.connect(_on_reload_started)

	# The body, drawn, and its hitboxes are PlayerSim's (wear_body).
	if model != null:
		var footsteps := Footsteps.new()
		footsteps.name = "Footsteps"
		add_child(footsteps)
	# What it shoots with is the simulation's, model or no model, from its
	# inventory: its own gun is its starting gun, handed out with CS2's knife
	# and pistol at every spawn, and in its hand now.
	weapon_sounds = WeaponSounds.new()
	weapon_sounds.name = "WeaponSounds"
	weapon_sounds.spatial = true
	add_child(weapon_sounds)
	# Its shots, heard from the game's weapon_fire (WeaponSounds.watch).
	weapon_sounds.watch(self)
	equipped.connect(_on_equipped)
	if weapon_data != null:
		arm(weapon_data)


## Hands it another gun, loaded and in hand, and makes it the one it spawns
## with; it keeps the model it holds.
func arm(data: WeaponData) -> void:
	weapon_data = data
	starting_gun = data
	equip(data)


## Whatever is in hand now: a gun sounds as that gun.
func _on_equipped(entry: Inventory.Entry) -> void:
	if entry != null and entry.weapon != null:
		weapon_sounds.equip(entry.weapon.data)


## A bot's body is seen, holding its weapon. Without the model's capsules
## (not extracted, or a broken extraction) it wears the four standard boxes,
## with a grey body to see them by when there is no model either: a bot has
## to be something that can be shot.
func _body_weapon_model() -> String:
	return weapon_model


func _body_drawn() -> bool:
	return true


func _body_holds_items() -> bool:
	return weapon_model.is_empty()


func _body_weapon_set() -> String:
	return weapon_data.world_clip_set if weapon_data != null else ""


func command_for(tick: int, dt: float) -> UserCmd:
	return _think(tick, dt)


## The body as it is seen: drawn between the last two ticks, and lit, both
## following the frames drawn rather than the simulation's ticks.
func _process(_delta: float) -> void:
	if model == null:
		return
	# Drawn as far between its last two ticks as the frame falls.
	var alpha := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	model.show_between(previous_position, global_position, previous_yaw_degrees, yaw_degrees, alpha)
	model.show_held()
	if alive:
		model.light_from(global_position + Vector3.UP * 40.0)


## What it does this tick, as a command: the way it faces, the way it walks,
## and whether the trigger is down.
func _think(tick: int, delta: float) -> UserCmd:
	var cmd := UserCmd.new()
	cmd.tick = tick
	# Where it meant to face last tick, the aim error taken back out.
	var yaw := yaw_degrees - _sent_error.x
	var pitch := pitch_degrees - _sent_error.y
	var error := Vector2.ZERO

	if not alive:
		cmd.yaw_degrees = yaw
		cmd.pitch_degrees = pitch
		_sent_error = Vector2.ZERO
		return cmd

	if not buy_template.is_empty():
		_shop(tick)
		_take_best_gun(cmd)

	# Nothing to shoot with, nothing to stop for: an unarmed bot just walks.
	target = _look_for_target() if weapon != null and not holds_fire else null
	if target != null:
		_seen_for += delta
	else:
		_seen_for = 0.0
		_burst_clock = 0.0
		_tap_clock = 0.0

	if target != null and _seen_for >= REACTION_SECONDS:
		# Stops, turns to face the target, and fires in bursts once facing it.
		var eyes := global_position + Vector3.UP * eye_height()
		var aim: Vector3 = target.global_position + Vector3.UP * 48.0
		var angles := PlayerInput.angles_from_direction(aim - eyes)
		yaw = rad_to_deg(rotate_toward(deg_to_rad(yaw), deg_to_rad(angles.x), deg_to_rad(turn_rate) * delta))
		pitch = angles.y
		var facing := absf(angle_difference(deg_to_rad(yaw), deg_to_rad(angles.x))) < deg_to_rad(FIRE_WITHIN_DEGREES)
		if facing:
			if weapon.ammo <= 0:
				cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.RELOAD, true, 0.0, yaw, pitch))
				_burst_clock = 0.0
			# A burst, a pause, a burst: the clock runs round both.
			_burst_clock = fmod(_burst_clock + delta, BURST_SECONDS + PAUSE_SECONDS)
			if _burst_clock < delta:
				_aim_error = Vector2(
					_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES),
					_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES)
				)
			error = _aim_error
			if not weapon.data.automatic:
				# Tapped: a press every TAP_SECONDS, the trigger up between.
				_tap_clock -= delta
				if _tap_clock <= 0.0:
					_tap_clock = TAP_SECONDS
					cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.0, yaw + error.x, pitch + error.y))
			elif _burst_clock < BURST_SECONDS:
				cmd.buttons |= UserCmd.ATTACK
	elif not route.is_empty():
		var way := _way_on(cmd, delta)
		if way.length_squared() > 0.0:
			# The game's yaw 0 looks down -Z, and yaw grows towards -X.
			var wanted := rad_to_deg(atan2(-way.x, -way.z))
			yaw = rad_to_deg(rotate_toward(deg_to_rad(yaw), deg_to_rad(wanted), deg_to_rad(turn_rate) * delta))
			cmd.move = UserCmd.move_toward(way, yaw)

	cmd.yaw_degrees = yaw + error.x
	cmd.pitch_degrees = pitch + error.y
	_sent_error = error
	return cmd


## Buys in freeze time, once a round, on the tick it was given at its spawn:
## what BotBuying plans for its side, its money and what it carries, sent as
## the buy commands a player's menu sends, which the economy prices and
## refuses as it does anyone's. It waits while it may not buy yet and the
## round is frozen; once it could not buy, it gives up for the round. With
## no economy it never can.
func _shop(tick: int) -> void:
	if _shop_tick < 0 or tick < _shop_tick or not is_instance_valid(world):
		return
	if not bool(world.game.query(&"can_buy", [userid], false)):
		if not frozen:
			_shop_tick = -1
		return
	_shop_tick = -1
	var money := int(world.game.query(&"money", [userid], 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["bot_buy", userid, tick])
	for item_class in BotBuying.plan(team, money, inventory, buy_template, rng):
		world.game.command(userid, "buy " + item_class)


## Its best gun in hand, a primary over a pistol, once the hand is ready: a
## gun bought or picked up is taken out on the next tick.
func _take_best_gun(cmd: UserCmd) -> void:
	var best := inventory.best_gun()
	if best != null and best.item.item_class != in_hand_class() and hand_ready():
		cmd.weapon_select = int(best.item.slot) + 1


## When in freeze time it shops, from a spawn on this tick: none for a bot
## that does not buy.
func _plan_shopping() -> void:
	if buy_template.is_empty():
		_shop_tick = -1
		return
	var now := SimClock.current_tick()
	_shop_tick = now + SHOP_DELAY_TICKS + posmod(hash(["bot_buy_delay", userid, now]), SHOP_SPREAD_TICKS + 1)


## Which way it walks this tick, flat, towards route[_next]: along the path
## over the nav mesh where there is one, straight at it where there is not.
## Sets the command's crouch and jump as the floor asks. Zero when it has
## arrived, and it heads for the next point of the route from the next tick.
func _way_on(cmd: UserCmd, delta: float) -> Vector3:
	var goal := route[_next]
	if nav_mesh != null and _path == null and _no_way_to != _next:
		if is_instance_valid(world) and not world.may_search_path():
			return Vector3.ZERO
		_path = nav_mesh.walk_path(global_position, goal)
		_corner = 1
		if _path.is_empty():
			_path = null
			_no_way_to = _next
			push_warning("%s: no way over the nav mesh from %s to %s; walking straight at it" % [name, global_position, goal])

	if _path == null:
		var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
		if to_goal.length() < arrive_distance:
			_arrive()
			return Vector3.ZERO
		return to_goal.normalized()

	# The corners it has passed: reached, or gone by (the leg from the corner
	# before now points back at it). The last is the goal, reached as before.
	while _corner < _path.points.size():
		var point := _path.points[_corner]
		var to_corner := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
		var last := _corner == _path.points.size() - 1
		var landing := _path.jumps_from(_corner - 1)
		var height_ok := not landing or (on_ground and absf(point.y - global_position.y) < STEP_UP_OR_DOWN)
		var from := _path.points[_corner - 1]
		var leg := Vector3(point.x - from.x, 0.0, point.z - from.z)
		var passed := not last and leg.length_squared() > 1.0 and leg.dot(to_corner) <= 0.0
		if height_ok and (to_corner.length() < (arrive_distance if last else CORNER_REACHED) or passed):
			_corner += 1
			continue
		break
	if _corner >= _path.points.size():
		_arrive()
		return Vector3.ZERO

	var corner := _path.points[_corner]
	var way := Vector3(corner.x - global_position.x, 0.0, corner.z - global_position.z)
	if _path.jumps_from(_corner - 1):
		# Heading for a landing up a ledge or across a gap: it jumps from the
		# take-off, and crouches in the air, which lifts the feet (the crouch
		# jump) for the ledges a standing jump does not clear.
		var take_off := _path.points[_corner - 1]
		var near_take_off := Vector2(take_off.x - global_position.x, take_off.z - global_position.z).length() < TAKE_OFF_REACH
		var at_take_off := near_take_off and absf(global_position.y - take_off.y) < STEP_UP_OR_DOWN
		if on_ground and at_take_off:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.0, yaw_degrees, pitch_degrees))
		elif not on_ground:
			cmd.buttons |= UserCmd.DUCK
	if _under_low_ceiling():
		cmd.buttons |= UserCmd.DUCK
	if _note_progress(delta):
		cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.0, yaw_degrees, pitch_degrees))
	return way.normalized() if way.length_squared() > 0.0 else Vector3.ZERO


## On to the next point of the route, to find the way there afresh.
func _arrive() -> void:
	_next = (_next + 1) % route.size()
	_path = null
	_no_way_to = -1
	_stuck_for = 0.0


## Whether it has been walking for STUCK_SECONDS without getting anywhere;
## if so it finds its way again from where it is from the next tick.
func _note_progress(delta: float) -> bool:
	if Vector2(velocity.x, velocity.z).length() >= STUCK_SPEED or not on_ground:
		_stuck_for = 0.0
		return false
	_stuck_for += delta
	if _stuck_for < STUCK_SECONDS:
		return false
	_stuck_for = 0.0
	_path = null
	_no_way_to = -1
	return true


## Whether an area whose ceiling is too low to stand under is on its path
## and within CROUCH_AHEAD of it, about as high as its feet.
func _under_low_ceiling() -> bool:
	for area in _path.areas:
		if (area.flags & SourceNavMesh.FLAG_CROUCH) == 0:
			continue
		if absf(area.floor_at(global_position) - global_position.y) < 36.0 \
				and area.distance_in_plan(global_position) < CROUCH_AHEAD:
			return true
	return false


## The nearest living player of the other side in sight: within range,
## within the cone, and in the open between its eyes and theirs. Only in its
## world: nobody else is in the game.
func _look_for_target() -> Node3D:
	if not is_instance_valid(world):
		return null
	var best: Node3D = null
	var best_distance := SIGHT_RANGE
	for candidate in world.players:
		if candidate == self or not candidate.alive or candidate.team == team:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance >= best_distance:
			continue
		if not can_see(candidate):
			continue
		best = candidate
		best_distance = distance
	return best


## Whether a body is within the cone the bot faces and nothing of the map
## stands between its eyes and theirs.
func can_see(other: Node3D) -> bool:
	var eyes := global_position + Vector3.UP * eye_height()
	var theirs: Vector3 = other.global_position + Vector3.UP * 60.0
	if other is PlayerBody:
		theirs = other.global_position + Vector3.UP * (other as PlayerBody).eye_height()
	var to_them := theirs - eyes
	if to_them.length() > SIGHT_RANGE:
		return false
	var forward := Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	var flat := Vector3(to_them.x, 0.0, to_them.z)
	if flat.length_squared() > 1e-6 and rad_to_deg(forward.angle_to(flat.normalized())) > SIGHT_HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eyes, theirs, Hitscan.WORLD_LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_shot_traced(_shot: Weapon.Shot, result: Hitscan.Result) -> void:
	BulletImpacts.mark_in(get_tree(), result)
	# The gun's shot, added over the upper body. (CS2's third-person shoot
	# clips are additive; played whole, as they once were, they folded the
	# body over, and a firing bot fell as if dead with every round.)
	if model != null:
		model.fire()


func _on_reload_started() -> void:
	if model != null:
		model.play(&"reload", 0.1)
	# Heard by those near, as CS2's reloads are (to 1100 units,
	# reference/research/audio.md).
	if weapon_sounds != null:
		weapon_sounds.reload()


## Dies where the last round landed: the body has gone limp and fallen
## (PlayerSim._fall) and stays down; the hull and the hitboxes go, and the
## route waits. Without the hitbox set to build a ragdoll from, the model
## plays the game's death clip for where the round landed instead.
func _on_killed(zone: StringName) -> void:
	_deaths += 1
	if model != null and ragdoll == null:
		model.play(PlayerModel.death_for(zone, _deaths), 0.05)
	died.emit(zone)


## Back at the spawn point a match gave it, or else at the start of the
## route, whole; with neither, where it fell.
func respawn() -> void:
	# A spawn's loadout (PlayerSim.respawn): stripped, then armoured again.
	_loadout()
	_revive()
	_seen_for = 0.0
	target = null
	if _spawn_set:
		place(_spawn_position, _spawn_yaw)
	elif not route.is_empty():
		global_position = route[0]
		_next = 1 % route.size()
	_path = null
	_no_way_to = -1
	_stuck_for = 0.0
	velocity = Vector3.ZERO
	_forget_hits()
	_get_up()
	_plan_shopping()
	respawned.emit()
	_send(&"player_spawn", {"userid": userid})


## At a spawn point for a round: it sets off for the point of its route
## after the one nearest, and forgets whoever it was facing.
func spawn_at(spawn_position: Vector3, yaw: float, fresh: bool = false) -> void:
	super.spawn_at(spawn_position, yaw, fresh)
	_sent_error = Vector2.ZERO
	_seen_for = 0.0
	target = null
	_plan_shopping()
	# The way it was finding over the nav mesh is from where it was.
	_path = null
	_no_way_to = -1
	_stuck_for = 0.0
	if route.is_empty():
		return
	var nearest := 0
	for i in route.size():
		if route[i].distance_squared_to(spawn_position) < route[nearest].distance_squared_to(spawn_position):
			nearest = i
	_next = (nearest + 1) % route.size()
