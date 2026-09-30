extends "res://tests/check_suite.gd"

## The knife (Knife, PlayerSim._update_knife): its two attacks through the
## commands that make them, what each reaches and does, backstabs, the run
## of slashes, the draw that holds them off, walls, teammates, the widened
## box, and what is sent and heard of a swing. Every number checked is
## Knife's own, so a K1 measurement that changes one changes the check with
## it. On Box3D where it is installed, and on Godot's own physics.
## godot --headless --path . --script tests/run_knife_checks.gd

var _host: Node3D
var _world: GameWorld
var _attacker: Scripted
var _hurts: Array[Dictionary] = []
var _deaths: Array[Dictionary] = []
var _fires: Array[Dictionary] = []
var _swings: Array[Knife.Swing] = []

## Where the wall a slash meets stands, away from the rest.
const WALL_AT := Vector3(1000.0, 0.0, 0.0)


## A player who presses what the check tells it to, looking where it is
## told.
class Scripted extends PlayerSim:
	var buttons := 0
	var presses := 0

	func command_for(tick: int, _dt: float) -> UserCmd:
		var cmd := standing(tick)
		cmd.buttons = buttons
		for button in [UserCmd.ATTACK, UserCmd.ATTACK2]:
			if presses & button:
				cmd.steps.append(UserCmd.SubtickStep.new(button, true, 0.0, yaw_degrees, pitch_degrees))
				cmd.buttons |= button
		presses = 0
		return cmd


func _initialize() -> void:
	await physics_frame
	_check_rules()
	var backends := ["legacy"]
	if Box3DDrops.available():
		backends.append("box3d")
	else:
		print("Box3D is not installed: the swings are checked on Godot's physics only")
	for backend in backends:
		await _check_swings(backend)
	_finish("knife")


## The numbers and names, without a world.
func _check_rules() -> void:
	var data := Knife.data()
	_check_near(data.armor_penetration, 0.85, "the knife's armour ratio 1.7 lets 85% through kevlar (vdata)")
	_check_near(data.tagging_power, 0.7, "a knife hit leaves the victim 30% of their speed (vdata's flinch modifier 0.3)")
	_check_equal(Knife.damage_for(false, true, false), Knife.LIGHT_FIRST_DAMAGE, "a slash that starts a run")
	_check_equal(Knife.damage_for(false, false, false), Knife.LIGHT_DAMAGE, "a slash in a run")
	_check_equal(Knife.damage_for(true, false, false), Knife.HEAVY_DAMAGE, "a stab")
	_check_equal(Knife.damage_for(false, false, true), Knife.LIGHT_BACKSTAB_DAMAGE, "a slash in the back, first or not")
	_check_equal(Knife.damage_for(true, false, true), Knife.HEAVY_BACKSTAB_DAMAGE, "a stab in the back")

	var victim := Vector3(0.0, 0.0, -40.0)
	_check(Knife.is_behind(Vector3.ZERO, victim, Vector3.FORWARD), "straight behind someone looking away is behind them")
	_check(not Knife.is_behind(Vector3.ZERO, victim, Vector3.BACK), "in front of someone looking at you is not")
	_check(not Knife.is_behind(Vector3.ZERO, victim, Vector3.RIGHT), "beside someone is not")
	var inside := deg_to_rad(rad_to_deg(acos(Knife.BACKSTAB_COS)) - 5.0)
	var outside := deg_to_rad(rad_to_deg(acos(Knife.BACKSTAB_COS)) + 5.0)
	_check(Knife.is_behind(Vector3.ZERO, victim, Vector3(sin(inside), 0.0, -cos(inside))), "5 degrees inside the backstab's angle is behind")
	_check(not Knife.is_behind(Vector3.ZERO, victim, Vector3(sin(outside), 0.0, -cos(outside))), "5 degrees outside it is not")
	_check(Knife.is_behind(Vector3(0.0, 30.0, 0.0), victim, Vector3(0.0, -0.9, -0.1)), "height and a facing looking down do not change behind")

	var knife := Knife.new()
	knife.draw(0, 1.0)
	_check(not knife.is_ready(999_999) and knife.is_ready(1_000_000), "nothing swings until the 1.0 s draw is over (vdata)")
	var first := knife.begin(false, 1_000_000)
	var second := knife.begin(false, 1_400_000)
	var third := knife.begin(false, 1_800_000)
	var late := knife.begin(false, 1_800_000 + int(Knife.RUN_WITHIN * 1_000_000.0) + 1)
	_check(first.first and not second.first and not third.first and late.first,
		"a slash starts a run, the next within %.1f s carry it on, and one after that starts another" % Knife.RUN_WITHIN)
	_check(knife.ready_usec == late.at_usec + int(Knife.LIGHT_CYCLE * 1_000_000.0), "a slash readies the next after its cycle")
	_check_equal(String(first.clip()), "light_miss1", "slashes alternate their clips (1)")
	_check_equal(String(second.clip()), "light_miss2", "slashes alternate their clips (2)")
	var stab := knife.begin(true, 3_000_000)
	_check(knife.ready_usec == 3_000_000 + int(Knife.HEAVY_CYCLE * 1_000_000.0), "a stab readies the next after its own cycle")
	stab.outcome = Knife.Outcome.PLAYER
	_check_equal(String(stab.clip()), "heavy_hit1", "a stab that meets someone plays heavy_hit1")
	stab.backstab = true
	_check_equal(String(stab.clip()), "heavy_backstab", "one in the back heavy_backstab")
	second.outcome = Knife.Outcome.PLAYER
	second.backstab = true
	_check_equal(String(second.clip()), "light_backstab2", "the second slash's backstab light_backstab2")
	_check_equal(stab.met(), "backstab", "its third-person attack is the backstab")

	var names := Knife.all_sound_events()
	_check(names.size() == 8, "eight sound events for the knife's swings (%d)" % names.size())
	var missing := PackedStringArray()
	for event_name in names:
		if not SoundEvents.has_event(event_name):
			missing.append(event_name)
	_check(missing.is_empty(), "every one is CS2's own, in sound_events.json (missing: %s)" % ", ".join(missing))

	var clips := PackedStringArray(["idle", "light_hit_attack", "heavy_miss_attack", "heavy_hit_attack", "heavy_backstab_attack", "light_backstab_crouch"])
	_check_equal(PlayerModel.knife_clip_for(clips, true, "backstab"), "heavy_backstab_attack", "the third person's backstab is found by name")
	_check_equal(PlayerModel.knife_clip_for(clips, false, "backstab"), "light_hit_attack", "without one, an attack of the kind; a crouched one is passed over")
	_check_equal(PlayerModel.knife_clip_for(PackedStringArray(["idle", "draw"]), false, "hit"), "", "a set without attacks has none")


func _check_swings(backend: String) -> void:
	var label := "(%s) " % backend
	_setup(backend)
	var victim := _add_player("CT", Vector3(0.0, 0.0, -44.0), 180.0)
	var mate := _add_player("T", Vector3(200.0, 0.0, 0.0), 0.0)
	await physics_frame
	_attacker.inventory.select("weapon_knife")
	_check_equal(_attacker.in_hand_class(), "weapon_knife", label + "the knife is in hand")

	# Pressed during the draw: nothing.
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK
	_step(1)
	_check(_swings.is_empty(), label + "a slash pressed while the knife is drawn does nothing")
	_step(SimClock.ticks_in(1.0))

	# A slash in reach, from the front: the first of a run.
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK
	_step(1)
	_check(_swings.size() == 1 and _swings[0].outcome == Knife.Outcome.PLAYER and not _swings[0].backstab,
		label + "a slash 44 units away meets them from the front")
	_check_near(100.0 - victim.hit_target.health, Knife.LIGHT_FIRST_DAMAGE, label + "and does the first slash's damage, unarmoured")
	_check(_fires.size() == 1 and _fires[0]["weapon"] == "weapon_knife", label + "weapon_fire is sent for the swing, as CS2 sends it")
	_check(_hurts.size() == 1 and _hurts[0]["weapon"] == "weapon_knife" and _hurts[0]["attacker"] == _attacker.userid,
		label + "player_hurt names the knife and who swung it")

	# Held: the next comes a cycle later, carrying the run on.
	_attacker.buttons = UserCmd.ATTACK
	_step(SimClock.ticks_in(Knife.LIGHT_CYCLE) + 1)
	_attacker.buttons = 0
	_check(_swings.size() == 2, label + "held, the next slash comes a cycle later (%d)" % _swings.size())
	_check_near(100.0 - victim.hit_target.health, Knife.LIGHT_FIRST_DAMAGE + Knife.LIGHT_DAMAGE, label + "and does the run's damage")

	# Too far for a stab.
	_step(SimClock.ticks_in(1.0))
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK2
	var health := victim.hit_target.health
	_step(1)
	_check(_swings.size() == 3 and _swings[2].heavy and _swings[2].outcome == Knife.Outcome.MISS and victim.hit_target.health == health,
		label + "a stab at 44 units misses: it reaches %.0f" % Knife.HEAVY_REACH)

	# Armoured, close, from the front: a stab through kevlar.
	victim.hit_target.health = 100.0
	victim.hit_target.wear(100.0, true)
	_place(victim, Vector3(0.0, 0.0, -36.0), 180.0)
	await _settle()
	_step(SimClock.ticks_in(Knife.HEAVY_CYCLE))
	_aim_at(victim, 50.0)
	_attacker.presses = UserCmd.ATTACK2
	_step(1)
	_check(_swings.size() == 4 and _swings[3].outcome == Knife.Outcome.PLAYER, label + "a stab at 36 units meets them")
	_check_near(100.0 - victim.hit_target.health, Knife.HEAVY_DAMAGE * 0.85, label + "85% of it through kevlar")

	# From behind: a stab in the back kills through kevlar.
	victim.hit_target.health = 100.0
	_place(victim, Vector3(0.0, 0.0, -36.0), 0.0)
	await _settle()
	_step(SimClock.ticks_in(Knife.HEAVY_CYCLE))
	_aim_at(victim, 50.0)
	_attacker.presses = UserCmd.ATTACK2
	_step(1)
	_check(_swings.size() == 5 and _swings[4].backstab, label + "a stab from behind is a backstab")
	_check(not victim.alive and _deaths.size() == 1 and _deaths[0]["weapon"] == "weapon_knife",
		label + "which kills through kevlar, player_death naming the knife")
	victim.respawn()
	_place(victim, Vector3(0.0, 0.0, -44.0), 180.0)
	await _settle()

	# Wide of the line, inside the box: the ring finds them.
	victim.hit_target.wear(0.0, false)
	_place(victim, Vector3(0.0, 0.0, -40.0), 180.0)
	await _settle()
	_step(SimClock.ticks_in(1.0))
	_attacker.yaw_degrees = rad_to_deg(atan2(28.0, 40.0))
	_attacker.pitch_degrees = -10.0
	_attacker.presses = UserCmd.ATTACK
	health = victim.hit_target.health
	_step(1)
	_check(_swings.size() == 6 and _swings[5].outcome == Knife.Outcome.PLAYER and victim.hit_target.health < health,
		label + "a slash just wide of them still meets them, as the hull trace does")

	# Out of reach.
	_place(victim, Vector3(0.0, 0.0, -80.0), 180.0)
	await _settle()
	_step(SimClock.ticks_in(1.0))
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK
	health = victim.hit_target.health
	_step(1)
	_check(_swings.size() == 7 and _swings[6].outcome == Knife.Outcome.MISS and victim.hit_target.health == health,
		label + "a slash at 80 units misses")

	# A wall between (the one _setup put out at WALL_AT, where Box3D took
	# it in with the floor).
	_place(_attacker, WALL_AT + Vector3(0.0, 0.0, 20.0), 0.0)
	_place(victim, WALL_AT + Vector3(0.0, 0.0, -24.0), 180.0)
	await _settle()
	_step(SimClock.ticks_in(1.0))
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK
	health = victim.hit_target.health
	_step(1)
	_check(_swings.size() == 8 and _swings[7].outcome == Knife.Outcome.WALL and victim.hit_target.health == health,
		label + "a wall between takes the slash, and it hits the wall")
	_place(_attacker, Vector3.ZERO, 0.0)
	await _settle()

	# A teammate in the way: the enemy behind them is hit.
	_place(mate, Vector3(0.0, 0.0, -24.0), 180.0)
	_place(victim, Vector3(0.0, 0.0, -44.0), 180.0)
	await _settle()
	_step(SimClock.ticks_in(1.0))
	_aim_at(victim)
	_attacker.presses = UserCmd.ATTACK
	health = victim.hit_target.health
	var mate_health := mate.hit_target.health
	_step(1)
	_check(victim.hit_target.health < health and mate.hit_target.health == mate_health,
		label + "a slash passes a teammate in the way for the enemy behind them")
	# No enemy in reach: the teammate, at the team's share.
	_place(victim, Vector3(0.0, 0.0, -300.0), 180.0)
	await _settle()
	_attacker.team_damage_scale = 0.33
	_step(SimClock.ticks_in(1.0))
	_aim_at(mate)
	_attacker.presses = UserCmd.ATTACK
	_step(1)
	_check_near(mate_health - mate.hit_target.health, Knife.LIGHT_FIRST_DAMAGE * 0.33,
		label + "with no enemy in reach it hits the teammate, at the team's share")

	# Heard: the swing's events, played the frame after.
	var sounds := WeaponSounds.new()
	_host.add_child(sounds)
	sounds.watch(_attacker)
	_step(SimClock.ticks_in(1.0))
	_attacker.presses = UserCmd.ATTACK
	_step(1)
	_check(sounds.pending_swings().size() == 1, label + "a swing is noted for the next frame, not heard inside the tick")
	var ids := sounds.knife_sounds(sounds.pending_swings()[0])
	_check(ids.size() == 2 and ids[0] != 0 and ids[1] != 0, label + "and starts the swish and what it met (%s)" % ids)
	_host.free()
	await process_frame


## Looks at their chest, or at `height` up their body.
func _aim_at(target: PlayerSim, height: float = 50.0) -> void:
	var eye := _attacker.global_position + Vector3.UP * _attacker.eye_height()
	var angles := PlayerInput.angles_from_direction(target.global_position + Vector3.UP * height - eye)
	_attacker.yaw_degrees = angles.x
	_attacker.pitch_degrees = angles.y


func _step(ticks: int) -> void:
	for tick in ticks:
		_world.step()


## Godot's own physics takes a moved hitbox in at its next step.
func _settle() -> void:
	await physics_frame
	await physics_frame


func _place(player: PlayerSim, at: Vector3, yaw: float) -> void:
	player.place(at, yaw)
	player.velocity = Vector3.ZERO


func _setup(backend: String) -> void:
	_hurts.clear()
	_deaths.clear()
	_fires.clear()
	_swings.clear()
	_host = Node3D.new()
	root.add_child(_host)
	_box(Vector3(0.0, -8.0, 0.0), Vector3(4096.0, 16.0, 4096.0))
	_box(WALL_AT + Vector3(0.0, 36.0, 0.0), Vector3(128.0, 72.0, 4.0))
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, backend)
	_world.game.events.listen(&"player_hurt", func(event: GameEvent) -> void: _hurts.append(event.fields))
	_world.game.events.listen(&"player_death", func(event: GameEvent) -> void: _deaths.append(event.fields))
	_world.game.events.listen(&"weapon_fire", func(event: GameEvent) -> void: _fires.append(event.fields))
	_attacker = Scripted.new()
	_attacker.team = "T"
	_hull(_attacker)
	_host.add_child(_attacker)
	_attacker.place(Vector3.ZERO, 0.0)
	_world.add_player(_attacker)
	_attacker.inventory.give_starting_items("T")
	_attacker.knife_swung.connect(func(swing: Knife.Swing) -> void: _swings.append(swing))


func _add_player(team: String, at: Vector3, yaw: float) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	_hull(player)
	_host.add_child(player)
	player.hit_target.wear(0.0, false)
	player.place(at, yaw)
	_world.add_player(player)
	return player


static func _hull(player: PlayerSim) -> void:
	player.collision_layer = PlayerSim.PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(32.0, 72.0, 32.0)
	shape.shape = box
	shape.position = Vector3(0.0, 36.0, 0.0)
	player.add_child(shape)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_host.add_child(body)
	return body
