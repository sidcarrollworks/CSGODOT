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
## bot's decisions do is Bot. What runs it, one command a tick, in turn with
## everyone else, is the GameWorld it is in (command_for); it never runs
## itself.
##
## Being hit is part of the simulation too, since it changes how the player
## moves and where their rounds go: a hit slows the player down (tagging)
## and throws their aim (hit_punch), as CS2's server does to whoever it hits.

## The side the player is on.
@export_enum("T", "CT") var team: String = "T"

## The world that runs the player, and where everyone else in the game is
## found; null until one takes it (GameWorld.add_player).
var world: GameWorld

## How long death lasts before the respawn.
@export var respawn_seconds: float = 3.0

## Whether a player who dies comes back after respawn_seconds. Always, on
## its own; in a match, only in warmup (MatchState says).
var respawns: bool = true
## Held still by the match in freeze time: free to look round, duck,
## reload and change weapons, but not to move, jump or fire.
var frozen: bool = false
## The share of its damage a round from this player does to their own
## side: all of it on its own, CS2's third in a match (MatchRules).
var team_damage_scale: float = 1.0

## Dead in a round with no respawn: the living teammate being watched, or
## null while the camera is still on your own body (the first
## freeze_cam_seconds) or nobody on your side is left. Fire moves on to the
## next teammate, jump switches between their eyes and a camera behind them
## (observing_chase). Kept here, not in the view, as CS2's server keeps
## who each player watches: it goes by the commands the player sends.
var observing: PlayerSim
var observing_chase: bool = false
var freeze_cam_seconds: float = 2.0

## Where the player is looking, from the last command, in degrees.
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0

## How the tick before the last left the player, beside PlayerBody's
## previous_position: where they looked, and how far their view was kicked
## (view_punch()) and their gun (Weapon.viewmodel_punch()). A frame falls
## between two ticks, and whatever draws the player draws it that far
## between the two, as CS2 draws everyone: at 64 ticks a second the last
## tick alone would step the view and the bodies on a faster screen.
var previous_yaw_degrees: float = 0.0
var previous_pitch_degrees: float = 0.0
var previous_view_punch := Vector2.ZERO
var previous_viewmodel_punch := Vector2.ZERO

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

## The body the other players see, animated here whether anyone draws it or
## not, as CS2's server animates every player for their hitboxes: the
## third-person model with the game's own capsules on its bones. A bot's is
## drawn; yours is on UNSEEN_LAYER, which your camera leaves out, since your
## view draws a body of its own (without the head the camera sits in, set
## back from the eyes), but it is the one that bots' rounds hit. Null where the character has not been extracted,
## and then HitTarget's four standard boxes stand in (hitbox_source says so).
var model: PlayerModel
## The model's hitboxes, on its bones.
var hitboxes: SkinnedHitboxes

## Tagging: the share of their speed a player has, 1 being all of it. A
## hit drops it to what the shooter's weapon leaves them (its tagging
## power, from the game's weapons.vdata through WeaponVData: an AK-47 round
## leaves 40%, an SMG's none), and it
## climbs back from there at TAG_RECOVERY_PER_SECOND.
var velocity_modifier: float = 1.0

## The physics layer every player's hull is on. Hulls are solid to each
## other, teammates included, as in CS2 (mp_solid_teammates 1); a dead
## player's hull leaves it.
const PLAYER_LAYER := 2

## The visual layer your own body goes on, and nothing else: the body the
## bots' rounds hit, which your camera leaves out (your view draws its own)
## and a camera that is there to show you your hitboxes takes in. Layer 20.
const UNSEEN_LAYER := 1 << 19

## Where being hit has knocked the aim, in degrees, as (right, up). Unlike
## the recoil's view kick this is the aim itself: rounds fired while it is
## there go where it points, and the view shows exactly that. It is CS's
## aim punch, pushed by the hit and recovering the way a spray's does.
var hit_punch := RecoilState.new()

## A hit, after the damage: for whatever draws the player to say where it
## came from.
signal hurt(amount: float, zone: StringName, from: Vector3)


## A round left the weapon and was traced to where it landed.
signal shot_traced(shot: Weapon.Shot, result: Hitscan.Result)
## The weapon started reloading.
signal reload_started
## A new weapon is in hand.
signal equipped(data: WeaponData)
## Health ran out; zone is where the last round landed.
signal killed(zone: StringName)
signal respawned
## Now on the other side, wearing that side's body.
signal team_changed(team: String)

## CS2 holds off the slowdown for a couple of its 64 Hz ticks after the hit
## (sv_predictable_damage_tag_ticks 2), so a client predicting its own
## movement is not corrected for a hit it has not heard of yet.
const TAG_DELAY_SECONDS := 2.0 / 64.0
## How fast the speed comes back after a hit, as a share of full speed per
## second: from an AK-47's 40% to all of it in 1.5 s. CS:GO's rate as it
## is usually given; CS2 does not publish its own (roadmap item 4a measures
## it).
const TAG_RECOVERY_PER_SECOND := 0.4
## CS2's mp_tagging_scale: what every weapon's tag is multiplied by. Lower is
## harder tagging.
const TAGGING_SCALE := 1.0

## The push a hit gives the aim punch, in degrees a second, upwards: an
## unarmoured hit throws the aim about 2 degrees up within a tenth of a
## second, and 0.375 s on it is back within a twentieth of a degree; one
## that armour took a share of (kevlar on the body, a helmet on the head)
## about half a degree. CS2 runs
## its flinch at three times CS:GO's (mp_flinch_punch_scale 3) but publishes
## neither's base, so both sizes are estimates for Sid to judge against CS2.
const HIT_PUNCH_PUSH := 82.0
const HIT_PUNCH_PUSH_ARMORED := 52.0
## How far it leans to one side or the other, against the climb.
const HIT_PUNCH_SIDE := 0.3

## The slowdown a hit has in store, and how long until it lands; negative
## when none is coming.
var _tag_to: float = 1.0
var _tag_in: float = -1.0
var _hits_taken: int = 0
var _capsules: Array[Dictionary] = []

## The body lying limp where it died, while dead; null alive, or where there
## are no capsules to build one from. It only draws: the simulation goes on
## without it (CS2 ragdolls its dead on each client, not on the server).
var ragdoll: Ragdoll
var _respawn_at_usec: int = 0
var _died_at_usec: int = 0
var _spawn_position: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0
## Whether a match has put the player at a spawn point of its choosing
## (spawn_at), which a bot then comes back to rather than its route's start.
var _spawn_set: bool = false


func _ready() -> void:
	super._ready()
	collision_mask |= PLAYER_LAYER
	hit_target = _build_hit_target()
	hit_target.name = "HitTarget"
	hit_target.team = team
	add_child(hit_target)
	hit_target.died.connect(_on_hit_target_died)
	hit_target.damaged.connect(_on_hit)
	wear_body(_body_weapon_model(), _body_drawn())


## Out of the scene, out of the game: the world runs the player no more.
func _exit_tree() -> void:
	if is_instance_valid(world):
		world.remove_player(self)


## The command the player runs on this tick, which the world asks for: what
## drives the player decides it (PlayerController your keys, Bot its
## choices). On its own a player stands where it is, looking where it looked.
func command_for(tick: int, _dt: float) -> UserCmd:
	var cmd := UserCmd.new()
	cmd.tick = tick
	cmd.yaw_degrees = yaw_degrees
	cmd.pitch_degrees = pitch_degrees
	return cmd


## What takes the damage. Its hitboxes come from the body (wear_body).
func _build_hit_target() -> HitTarget:
	var target := HitTarget.new()
	target.build_own_hitboxes = false
	target.build_visual = false
	return target


## What the body holds, and whether anyone sees it: nothing and no for a
## player whose view draws its own (PlayerView), a bot's weapon and yes for
## a bot.
func _body_weapon_model() -> String:
	return ""


func _body_drawn() -> bool:
	return false


## The held weapon's own third-person clips (WeaponData.world_clip_set), for
## the body to hold, reload and fire it with: none for a body nobody sees.
func _body_weapon_set() -> String:
	return ""


## Puts the body on: the third-person model holding weapon_model, with the
## game's capsules on its bones, and HitTarget's four standard boxes where
## either has not been extracted, with a grey body to see them by when the
## body is drawn and there is no model to draw.
func wear_body(weapon_model: String, drawn: bool) -> void:
	model = PlayerModel.new()
	model.name = "Model"
	# A model nobody sees needs no lighting.
	model.probe_lit = drawn
	add_child(model)
	if not model.setup(team, weapon_model, _body_weapon_set()):
		model.queue_free()
		model = null
	elif not drawn:
		# Put where only a camera that asks for it sees it, rather than
		# hidden: the skeleton the hitboxes ride keeps posing either way, and
		# the test range shows it to you to check your hitboxes against.
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).layers = UNSEEN_LAYER
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if model != null:
		# Posed now rather than at the next animation step, so the capsules
		# start where the idle puts them and not on the bind pose, whose head
		# stands seven units higher.
		model.pose_now()
		hitboxes = SkinnedHitboxes.new()
		hitboxes.name = "Hitboxes"
		add_child(hitboxes)
		_capsules = HitboxSet.load_for(PlayerModel.AGENTS.get(team, PlayerModel.AGENTS["T"]))
		hitboxes.build(model.character_rig, _capsules, hit_target, MapImporter.SOURCE2_VIEWER_SCALE)
	if hit_target.hitboxes().is_empty():
		hit_target.build_standard_body(drawn and model == null)
	if not drawn:
		for hitbox in hit_target.hitboxes():
			hitbox.drawn_layers = UNSEEN_LAYER


## Which hitboxes the player wears, and when they are the stand-in boxes,
## why: the game's capsules come from the character's model description,
## and each way of not getting them has its own fix.
func hitbox_source() -> String:
	var built := hitboxes.hitboxes.size() if hitboxes != null else 0
	if built > 0:
		return "%d CS2 capsules on the skeleton" % built
	var model_path: String = PlayerModel.AGENTS.get(team, PlayerModel.AGENTS["T"])
	if model == null:
		return "4 stand-in boxes: the character has not been extracted (scripts/extract_assets.sh characters)"
	var description := model_path.get_basename() + ".vmdl"
	if not FileAccess.file_exists(description):
		return "4 stand-in boxes, NOT the game's: no hitbox set at %s (rerun scripts/extract_assets.sh characters)" % description
	var capsules := HitboxSet.load_for(model_path)
	if capsules.is_empty():
		return "4 stand-in boxes, NOT the game's: %s has no HitboxCapsule in it" % description.get_file()
	return "4 stand-in boxes, NOT the game's: none of %d capsules' bones (%s...) are on the skeleton" % [
		capsules.size(), capsules[0]["bone"],
	]


## Whether the model is there but its capsules are not: a broken
## extraction rather than a fresh clone, worth saying where it will be seen.
func hitboxes_missing() -> bool:
	return model != null and (hitboxes == null or hitboxes.hitboxes.is_empty())


## To the other side: that side's body and its hitboxes in place of this
## one's. What draws the player hears it from team_changed.
func change_team(new_team: String) -> void:
	if new_team == team:
		return
	team = new_team
	hit_target.team = team
	if ragdoll != null:
		ragdoll.queue_free()
		ragdoll = null
	# Out of the tree now, so no round meets the old hitboxes on this tick.
	for part: Node in [model, hitboxes]:
		if part != null:
			remove_child(part)
			part.queue_free()
	model = null
	hitboxes = null
	hit_target.drop_hitboxes()
	wear_body(_body_weapon_model(), _body_drawn())
	hit_target.set_active(alive)
	team_changed.emit(team)


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
	previous_yaw_degrees = yaw
	previous_pitch_degrees = 0.0


## The match puts the player at a spawn point for a round. Fresh (the
## first round, or after the sides swap), or dead, they come back as a
## respawn brings them: whole, armoured as they started, reloaded. Someone
## who lived through the last round keeps their armour and weapon, rounds
## in it and all, and is healed.
func spawn_at(spawn_position: Vector3, yaw: float, fresh: bool = false) -> void:
	_spawn_set = true
	_spawn_position = spawn_position
	_spawn_yaw = yaw
	if fresh or not alive:
		respawn()
		return
	place(spawn_position, yaw)
	velocity = Vector3.ZERO
	hit_target.health = hit_target.max_health
	_forget_hits()


func seconds_to_respawn() -> float:
	return maxf(0.0, float(_respawn_at_usec - SimClock.now_usec()) / 1_000_000.0)


## Runs the player forward one tick, and poses the body for it: the
## hitboxes stand where the body did this tick.
func run_command(cmd: UserCmd, dt: float) -> void:
	previous_yaw_degrees = yaw_degrees
	previous_pitch_degrees = pitch_degrees
	previous_view_punch = view_punch()
	previous_viewmodel_punch = weapon.viewmodel_punch() if weapon != null else Vector2.ZERO
	_run(cmd, dt)
	if alive and model != null:
		model.update_motion(velocity, yaw_degrees, duck_progress, on_ground)


## How far the view is kicked from where the player aims, in degrees, as
## (right, up): the recoil's punch and a hit's.
func view_punch() -> Vector2:
	return (weapon.aim_punch if weapon != null else Vector2.ZERO) + hit_punch.value


func _run(cmd: UserCmd, dt: float) -> void:
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
		if not respawns:
			_observe(cmd)
		elif SimClock.tick_end_usec(cmd.tick) >= _respawn_at_usec:
			respawn()
		return

	var selected := weapon_for_slot(cmd.weapon_select)
	if selected != null:
		equip(selected)

	yaw_degrees = cmd.yaw_degrees
	pitch_degrees = cmd.pitch_degrees
	_recover_from_hits(dt)

	var reload := cmd.first_press(UserCmd.RELOAD)
	if reload != null and weapon != null:
		if weapon.start_reload(SimClock.usec_at(cmd.tick, reload.when)):
			reload_started.emit()

	# A tap shorter than a tick still jumps: the press is in the command even
	# if the key is back up by its end. The earliest press is the one that
	# jumps, and the tick splits there (PlayerBody.simulate). A jump from a
	# held key has no transition to time, so it stays at the tick's start.
	var jump := cmd.first_press(UserCmd.JUMP)
	wants_jump = not frozen and (cmd.held(UserCmd.JUMP) or jump != null)
	if jump != null and wants_jump:
		jump_fraction = jump.when
	wants_duck = cmd.held(UserCmd.DUCK)

	if frozen:
		# Still, but falling if there is anywhere to fall, and the weapon
		# still reloads.
		simulate(dt)
		_update_weapon(cmd, dt)
		return

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
	if frozen:
		presses.clear()
	weapon.trigger_held = not frozen and (cmd.held(UserCmd.ATTACK) or not presses.is_empty())
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

	if weapon.trigger_held and cmd.held(UserCmd.ATTACK):
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
	# A hit's flinch throws the round as far as it throws the view.
	var thrown := hit_punch.value
	var shot := weapon.fire(
		at_usec, tick_fraction, origin, yaw - thrown.x, pitch + thrown.y, shooter_state
	)
	if shot == null:
		return
	rounds_fired += 1

	# Your own hull and hitboxes are not targets.
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(hit_target.rids())
	var result := Hitscan.fire_at(
		get_world_3d().direct_space_state, shot, weapon.data, exclude, team, team_damage_scale
	)
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


## How fast the player may go this tick. Tagging takes its share off the
## top, and friction brings a running player down to it: the slowdown is in
## what the player can reach, not a kick to the velocity.
func _max_speed(cmd: UserCmd) -> float:
	var speed := config.max_speed * velocity_modifier
	if is_ducked:
		speed *= config.duck_modifier
	elif cmd.held(UserCmd.WALK):
		speed *= config.walk_modifier
	return speed


## A round, or anything else, did damage: the tag is set to land shortly and
## the aim is thrown. The weapon that fired decides the tag; what armour
## took a share of it decides how far the aim goes.
func _on_hit(amount: float, zone: StringName, _remaining: float) -> void:
	_hits_taken += 1
	var data := hit_target.last_hit_weapon
	if data != null:
		_tag_to = minf(_tag_to, clampf((1.0 - data.tagging_power) * TAGGING_SCALE, 0.0, 1.0))
		if _tag_in < 0.0:
			_tag_in = TAG_DELAY_SECONDS
	var push := HIT_PUNCH_PUSH_ARMORED if hit_target.last_hit_armored else HIT_PUNCH_PUSH
	# Which way it leans is the one random part, seeded from the hit rather
	# than a live generator so a server and a client agree on it.
	var lean := 1.0 if hash([_hits_taken, hit_target.last_hit_from]) % 2 == 0 else -1.0
	hit_punch.velocity += Vector2(lean * HIT_PUNCH_SIDE, 1.0) * push
	hurt.emit(amount, zone, hit_target.last_hit_from)


## A tick's worth of getting over being hit: the speed comes back, and a
## tag that was waiting lands; the thrown aim recovers.
func _recover_from_hits(dt: float) -> void:
	velocity_modifier = minf(velocity_modifier + TAG_RECOVERY_PER_SECOND * dt, 1.0)
	if _tag_in >= 0.0:
		_tag_in -= dt
		# A hair under zero is zero: the delay is a whole number of ticks.
		if _tag_in <= 1e-6:
			velocity_modifier = minf(velocity_modifier, _tag_to)
			_tag_to = 1.0
			_tag_in = -1.0
	hit_punch.advance(dt)


## Over being hit altogether: full speed, the aim where it is held.
func _forget_hits() -> void:
	velocity_modifier = 1.0
	_tag_to = 1.0
	_tag_in = -1.0
	hit_punch.reset()


## Dead: still, out of reach of rounds, until the respawn. Whatever answers
## `killed` still sees the velocity the player died with (a bot's ragdoll
## falls the way it was going).
func _on_hit_target_died() -> void:
	alive = false
	hit_target.set_active(false)
	# Nobody walks into a body that is not there.
	collision_layer = 0
	_died_at_usec = SimClock.now_usec()
	_respawn_at_usec = _died_at_usec + int(respawn_seconds * 1_000_000.0)
	var zone: StringName = hit_target.last_hitbox.zone if hit_target.last_hitbox != null else &"chest"
	_fall()
	killed.emit(zone)
	velocity = Vector3.ZERO
	_forget_hits()


## The body goes limp and falls where it died, pushed the way the killing
## round was going, as a ragdoll made from the hitbox capsules. Nothing is
## done without the capsules or the model.
func _fall() -> void:
	if model == null or _capsules.is_empty() or model.character_rig == null:
		return
	ragdoll = Ragdoll.new()
	ragdoll.name = "Ragdoll"
	add_child(ragdoll)
	var forward := Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	var hit_bone := -1
	if hit_target.last_hitbox != null:
		hit_bone = hitboxes.bone_of(hit_target.last_hitbox)
	if ragdoll.build(
		model.character_rig, _capsules, MapImporter.SOURCE2_VIEWER_SCALE,
		velocity, forward, hit_target.last_hit_direction, hit_bone
	) == 0:
		ragdoll.queue_free()
		ragdoll = null
		return
	# The animation would pose the bones over the bodies' every frame.
	model.set_animating(false)


## Up off the floor: the ragdoll gone and the model animated again.
func _get_up() -> void:
	if ragdoll != null:
		ragdoll.queue_free()
		ragdoll = null
		if model != null:
			model.character_rig.reset_bone_poses()
			model.set_animating(true)
	if model != null:
		model.play(model.idle)


## Where the body is: the middle of the ragdoll while there is one, or
## where the player stands.
func body_centre() -> Vector3:
	if ragdoll == null or ragdoll.bodies.is_empty():
		return global_position + Vector3.UP * 36.0
	var sum := Vector3.ZERO
	for body: RigidBody3D in ragdoll.bodies.values():
		sum += body.global_position
	return sum / ragdoll.bodies.size()


## Dead with no respawn coming: after the freeze cam, watching a living
## teammate, the next one on a press of fire, from their eyes or from
## behind them on a press of jump. Only your own side.
func _observe(cmd: UserCmd) -> void:
	var now := SimClock.tick_end_usec(cmd.tick)
	if now < _died_at_usec + int(freeze_cam_seconds * 1_000_000.0):
		return
	var watching := observing != null and is_instance_valid(observing) \
		and observing.alive and observing.team == team
	if not watching or cmd.first_press(UserCmd.ATTACK) != null:
		observing = _next_teammate(observing if watching else null)
	elif cmd.first_press(UserCmd.JUMP) != null:
		observing_chase = not observing_chase


## The living teammate after this one, round and round; the first when
## there is none to follow. Only in the player's world: nobody else is in
## the game.
func _next_teammate(after: PlayerSim) -> PlayerSim:
	if not is_instance_valid(world):
		return null
	var living: Array[PlayerSim] = []
	for other in world.players:
		if other != self and other.alive and other.team == team:
			living.append(other)
	if living.is_empty():
		return null
	return living[(living.find(after) + 1) % living.size()]


## Up again: whole, solid, able to be shot, watching nobody.
func _revive() -> void:
	alive = true
	hit_target.reset()
	hit_target.set_active(true)
	collision_layer = PLAYER_LAYER
	observing = null
	observing_chase = false


## Back where the map put the player, whole and reloaded.
func respawn() -> void:
	_revive()
	place(_spawn_position, _spawn_yaw)
	velocity = Vector3.ZERO
	_forget_hits()
	_get_up()
	if weapon != null:
		equip(weapon.data)
	respawned.emit()
