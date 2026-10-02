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
## Whether a bot runs the player rather than a person: Bot sets it. The
## rules that treat people and bots apart read this, never `is Bot` (the
## player_team event's isbot).
var is_bot: bool = false
## Who the player is in their world's game: the userid its roster gave them,
## which events, damage and the inventories name them by;
## GameEvents.NOBODY out of a game.
var userid: int = GameEvents.NOBODY

## What the player carries and what is in their hand, as CS2's weapon
## services keep it on the pawn: every gun its own Weapon, so a gun keeps its
## rounds and its recoil through a switch, a drop and a pick-up. Their
## world's game names it by their userid (GameSystems.inventory).
var inventory := Inventory.new()
## The gun a player is handed at every spawn besides CS2's knife and pistol,
## until they buy their own: the match's side rifle, a bot's own, the
## range's AK-47. Null for CS2's plain loadout.
var starting_gun: WeaponData

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
## freeze_cam_seconds), nobody on your side is left, or the camera flies
## free. Fire moves on to the next teammate and the right button back to
## the one before, as CS2's spectator keys have it (PANOHUD_Spectate_
## Navigation_Arrows and _Arrows_Prev); jump goes round the camera's modes
## (observer_mode). Kept here, not in the view, as CS2's server keeps who
## each player watches and how: it goes by the commands the player sends.
var observing: PlayerSim
var freeze_cam_seconds: float = 2.0

## How a dead player watches, CS2's CSObserverMode (point_script.d.ts) less
## the two it has no key for (NONE, FIXED): from the eyes of the one
## watched, from behind them, or flying free round the map ("Free Look",
## Cstrike_TitlesTXT_OBS_ROAMING). Jump goes round them in that order, as
## spec_mode does.
enum ObserverMode { IN_EYE, CHASE, ROAMING }
var observer_mode := ObserverMode.IN_EYE
## Whether the camera is behind the one watched, rather than in their eyes.
var observing_chase: bool:
	get:
		return observer_mode == ObserverMode.CHASE
## Whether the dead may fly free (MatchRules.free_look).
var free_look: bool = true
## Flying free: where the camera is, where it was the tick before (to draw
## between the two), and how fast it is going. Through walls, as CS2's
## sv_specnoclip 1 has it.
var observer_position := Vector3.ZERO
var previous_observer_position := Vector3.ZERO
var observer_velocity := Vector3.ZERO
## Who was watched before the camera flew free, to go back to.
var _observed_before: PlayerSim

## Flying free, CS2's spectator movement convars (GameTracking-CS2's
## convars.txt, 2026-09-30): sv_specspeed 1200 units a second at most,
## sv_specaccelerate 5, slowed by sv_friction 5.2, half as fast with walk
## held. The shape is Source's FullObserverMove (Source SDK 2013, read as a
## spec): friction on a speed no less than a quarter of the top, then the
## acceleration toward where you look.
const SPEC_SPEED := 1200.0
const SPEC_ACCELERATE := 5.0
const SPEC_FRICTION := 5.2

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

## The gun in hand, the inventory's own Weapon; null holding anything else
## (the knife, a grenade, the bomb) or nothing. And how the player was
## moving when it was last told: what its cone is judged by.
var weapon: Weapon
## Owned current state, reused each update; callers needing history copy its fields.
var shooter_state := Weapon.ShooterState.new()
var rounds_fired: int = 0
## The knife's attacks and when the next may come: in hand whenever the
## inventory's knife is (_update_knife).
var knife := Knife.new()

## Health and armour, and what a round can hit.
var hit_target: HitTarget
var alive: bool = true
## The command thought of on a worker thread (think_apart), until the world
## takes it (thought).
var _thought: UserCmd
## How the player was moving when they died, which what they drop keeps
## (ItemDrops): velocity itself is zero from the death on.
var death_velocity: Vector3 = Vector3.ZERO

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


## A round left the weapon and was traced to where it landed: each of a
## shotgun's pellets is one (Weapon.Shot.pellet), the first being the shot.
signal shot_traced(shot: Weapon.Shot, result: Hitscan.Result)
## The weapon started reloading.
signal reload_started
## A shotgun's shell-by-shell reload stopped by a shot, part way.
signal reload_stopped
## Something else is in hand (the inventory's entry), or nothing (null):
## the gun, the knife, a grenade, the bomb. It is being drawn.
signal equipped(entry: Inventory.Entry)
## A grenade in hand: the pin is out, and then it is thrown, underhand when
## only the right button was held.
signal pin_pulled
signal grenade_released(underhand: bool)
## A knife swing, traced and its damage dealt: what it met, for whatever
## draws and sounds it (its clip, Knife.Swing.sound_events).
signal knife_swung(swing: Knife.Swing)
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
## The same body while alive: made ahead, its parts switched off, to fall
## at the death (prepare_to_fall). Null until it has been made, and while
## it lies as `ragdoll`.
var _ragdoll_ready: Ragdoll
## The body on now could not have one made (its capsules are on none of its
## bones): nobody asks again until another body is put on.
var _no_body_to_make: bool = false
var _respawn_at_usec: int = 0
var _died_at_usec: int = 0
var _spawn_position: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0
## Whether a match has put the player at a spawn point of its choosing
## (spawn_at), which a bot then comes back to rather than its route's start.
var _spawn_set: bool = false

## What is in hand, by class, as last followed from the inventory; and until
## when it is being drawn, in simulation time (nothing fires or throws
## before).
var _held_class: String = ""
var _drawn_until_usec: int = 0
## R pressed while the gun was being drawn: the reload starts as the draw
## ends, as CS2's does (Sid, 2026-09-26), and a switch drops it.
var _reload_after_draw: bool = false
## A grenade in hand with its pin out, and the attack buttons held while it
## is: which of them say how hard it goes when they are let go.
var _pin_pulled: bool = false
var _throw_left: bool = false
var _throw_right: bool = false
## A grenade thrown: the hand throwing it until then, in simulation time,
## and only after it drawing what is in hand next.
var _throwing: bool = false
var _throwing_until_usec: int = 0
## Set while several changes are made to the inventory together, so what is
## in hand is followed once, after them.
var _changing_inventory: bool = false

## Held still by the game on the last tick: planting or defusing the bomb
## (the holds_still query), for whatever draws the player. frozen is the
## match's.
var held_still: bool = false

## How long a throw keeps the hand before what is next in it is drawn: the
## first-person throw clips' lengths, overhand and underhand
## (reference/weapons/equipment.md, from the clips' own data). The grenade
## itself leaves at the release, as CS2 throws it at the release's instant.
const THROW_OVERHAND_SECONDS := 0.77
const THROW_UNDERHAND_SECONDS := 0.50
## Speed with nothing in hand, as with the knife.
const EMPTY_HANDED_SPEED := 250.0


func _ready() -> void:
	super._ready()
	collision_mask |= PLAYER_LAYER
	hit_target = _build_hit_target()
	hit_target.name = "HitTarget"
	hit_target.team = team
	add_child(hit_target)
	hit_target.died.connect(_on_hit_target_died)
	hit_target.damaged.connect(_on_hit)
	# Armour is worn on the hit target, which the inventory reads and sets.
	inventory.body = hit_target
	inventory.changed.connect(_follow_hand)
	wear_body(_body_weapon_model(), _body_drawn())


## Out of the scene, out of the game: the world runs the player no more.
func _exit_tree() -> void:
	if is_instance_valid(world):
		world.remove_player(self)


## The command the player runs on this tick, which the world asks for: what
## drives the player decides it (PlayerController your keys, Bot its
## choices). On its own a player stands where it is, looking where it looked.
func command_for(tick: int, _dt: float) -> UserCmd:
	return standing(tick)


## The command of someone who does nothing: standing where they are,
## looking where they looked.
func standing(tick: int) -> UserCmd:
	var cmd := UserCmd.new()
	cmd.tick = tick
	cmd.yaw_degrees = yaw_degrees
	cmd.pitch_degrees = pitch_degrees
	return cmd


## Whether the world may have this player think on a worker thread, beside
## the others who can (GameWorld.commands_for): a bot can, whose thinking
## is prepare_to_think and think. Whoever reads the keyboard cannot.
func thinks_apart() -> bool:
	return false


## What of its thinking touches what the players share, done in its turn on
## the thread that runs the tick, before anyone thinks.
func prepare_to_think(_tick: int) -> void:
	pass


## Its command, thought of with nothing shared written: prepare_to_think
## has been called for the tick.
func think(tick: int, dt: float) -> UserCmd:
	return command_for(tick, dt)


## think, on a worker thread: the command is kept for thought() to hand
## over, and what it counted with it.
func think_apart(tick: int, dt: float) -> void:
	_thought = think(tick, dt)


## The command think_apart thought of, handed over on the thread that runs
## the tick.
func thought() -> UserCmd:
	var cmd := _thought
	_thought = null
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


## Whether the body holds whatever is in the hand, changing with it
## (PlayerModel.hold), rather than the one gun _body_weapon_model() gives it
## for life. Every body does, seen or not: CS2's server poses every player's
## hitboxes with what they hold (reference/research/hitboxes-aim.md 1). A
## body nobody sees takes the item's clips and locomotion, never its model.
func _body_holds_items() -> bool:
	return true


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
	if not model.setup(team, weapon_model, _body_weapon_set(), _body_holds_items()):
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
		# Every frame while a camera draws it, otherwise between the ticks,
		# out of the frames the tick holds up (PlayerModel.step_off_tick_frames).
		model.step_off_tick_frames()
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
	# The body it dies into is made on a frame soon (GameWorld._process).
	_no_body_to_make = false
	if is_instance_valid(world):
		world.bodies_to_make = true


## Whether the body it dies into is still to be made: alive or dead with
## none lying, a model and its capsules on, and none made yet.
func wants_body_made() -> bool:
	return _ragdoll_ready == null and ragdoll == null and not _no_body_to_make and model != null \
		and model.character_rig != null and not _capsules.is_empty() and is_inside_tree()


## Makes the body it dies into ahead of the death, its parts and joints,
## and leaves it switched off (Ragdoll.prepare). A death then only puts the
## parts where the bones are. Made at the death it was 2 ms of the 3 the
## death cost the run it happened in; here it is on a frame, off the tick,
## where the world asks for it (GameWorld._process), one body a frame.
## Whether it is made after this. Without the world's physics yet, or the
## model, it is not, and the death makes it as it always did.
func prepare_to_fall() -> bool:
	if not wants_body_made():
		return _ragdoll_ready != null
	var physics := PhysicsQueries.adapter_for_node(self)
	if not is_instance_valid(physics) or not physics.initialized:
		# Not yet: whoever asks may ask again.
		return false
	var made := Ragdoll.new()
	made.name = "Ragdoll"
	add_child(made)
	if made.prepare(
		model.character_rig, _capsules, MapImporter.SOURCE2_VIEWER_SCALE, _model_faces(), physics, true
	) == 0:
		# With the world's physics there, it is this body that none can be
		# made for, and asking again would find the same.
		_no_body_to_make = true
		remove_child(made)
		made.free()
		return false
	_ragdoll_ready = made
	return true


## The way the body's model faces, flat: where the player looks, as the
## model is turned to (PlayerModel turns it to the yaw and half a turn).
func _model_faces() -> Vector3:
	var faces := model.global_basis.z if model != null and model.is_inside_tree() else Vector3.ZERO
	faces.y = 0.0
	if faces.length_squared() < 1e-6:
		return Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	return faces.normalized()


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
	# The body it lies as or would die into is the old side's.
	for body: Ragdoll in [ragdoll, _ragdoll_ready]:
		if body != null:
			body.let_go()
	ragdoll = null
	_ragdoll_ready = null
	# Out of the tree now, so no round meets the old hitboxes on this tick.
	for part: Node in [model, hitboxes]:
		if part != null:
			remove_child(part)
			part.queue_free()
	model = null
	hitboxes = null
	hit_target.drop_hitboxes()
	wear_body(_body_weapon_model(), _body_drawn())
	if alive:
		_body_holds(inventory.in_hand())
	hit_target.set_active(alive)
	team_changed.emit(team)


## Hands the player a gun and puts it in their hand: a new one, loaded, in
## place of whatever gun was in its slot. What the match, the range and the
## checks hand out; buying, picking up and dropping go through the
## inventory itself (the economy, ItemDrops).
func equip(data: WeaponData) -> void:
	if not ItemRegistry.has(data.item_class):
		push_error("%s has no item class the registry knows (%s)" % [data.display_name, data.item_class])
		return
	_changing_inventory = true
	inventory.remove(data.item_class)
	inventory.add(data.item_class, Weapon.new(data))
	inventory.select(data.item_class)
	_changing_inventory = false
	_follow_hand()


## What a player spawns with: CS2's knife and their side's pistol, and
## starting_gun in hand where there is one, drawn. Everything else they
## carried is gone (CS2 strips a player at their next spawn).
func _loadout() -> void:
	_changing_inventory = true
	# The strip takes the armour off with the rest; what a player wears at a
	# spawn is the body's (HitTarget.wear and reset), so it is put back as it
	# was.
	var armor := inventory.armor
	var helmet := inventory.helmet
	inventory.strip()
	inventory.armor = armor
	inventory.helmet = helmet
	inventory.give_starting_items(team)
	if starting_gun != null and ItemRegistry.has(starting_gun.item_class):
		inventory.add(starting_gun.item_class, Weapon.new(starting_gun))
		inventory.select(starting_gun.item_class)
	_changing_inventory = false
	_throwing = false
	_draw(inventory.in_hand())


## Draws what is in hand afresh, from now: for a player joining a world,
## whose clock times the draw (one armed before it was timed by the
## engine's).
func draw_again() -> void:
	_throwing = false
	_draw(inventory.in_hand())


## Follows what the inventory has in hand, whatever changed it (a switch, a
## purchase, a pick-up, a drop): once something else is in it, that is
## drawn. A throw keeps the hand until it is over (_update_grenade).
func _follow_hand() -> void:
	if _changing_inventory or _throwing:
		return
	var entry := inventory.in_hand()
	var item_class := entry.item.item_class if entry != null else ""
	if item_class == _held_class and (entry.weapon if entry != null else null) == weapon:
		return
	_draw(entry)


## Takes entry in hand (null: nothing) and draws it, from now: the Weapon to
## fire, how fast the player runs with it, and the draw, which holds off
## firing and throwing for the item's deploy time (CS2's
## m_flDeployDuration). A gun put away loses a reload under way.
func _draw(entry: Inventory.Entry) -> void:
	var held_weapon := entry.weapon if entry != null else null
	if weapon != null and weapon != held_weapon:
		weapon.holster()
	_held_class = entry.item.item_class if entry != null else ""
	weapon = held_weapon
	_pin_pulled = false
	_reload_after_draw = false
	if held_weapon != null:
		config.max_speed = held_weapon.data.max_player_speed
	else:
		config.max_speed = entry.item.max_speed if entry != null else EMPTY_HANDED_SPEED
	var now := SimClock.now_usec()
	var deploy := entry.item.deploy_seconds if entry != null else 0.0
	_drawn_until_usec = now + int(roundf(deploy * 1_000_000.0))
	if held_weapon != null:
		held_weapon.trigger_held = false
		held_weapon.draw(now, deploy)
	elif _held_class == Knife.ITEM_CLASS:
		knife.draw(now, deploy)
	# A dead player's hand empties as what they drop goes; the body lets go
	# at the death, and takes up what is in hand again when it gets up.
	if alive:
		_body_holds(entry)
	equipped.emit(entry)


## The body holds what is in the hand: its own hold, draw, reload and shots
## and the locomotion for it (PlayerModel.hold), which the hitboxes ride, and
## for those who see it, its model. A body built with one gun holds it
## whenever anything is in hand.
func _body_holds(entry: Inventory.Entry) -> void:
	if model == null or not (model.holds_items or _body_drawn()):
		return
	var item_class := entry.item.item_class if entry != null else ""
	model.hold(item_class, WeaponLibrary.look(item_class, team) if not item_class.is_empty() else {})


## The item in hand, by class ("weapon_ak47", "weapon_knife"); "" for none.
func in_hand_class() -> String:
	return _held_class


## Whether what is in hand is out and ready: its draw over, and no throw
## under way. The bomb waits for it before a plant.
func hand_ready() -> bool:
	return not _throwing and SimClock.now_usec() >= _drawn_until_usec


## The item's attachment-bone frame at the hand, in the world: CS2's hold
## from where the player stands and looks (HeldPose). Converting through
## ItemPhysics.Hull.model_held_at gives the model's +Z muzzle and +Y top.
## What a drop throws from (ItemDrops).
func held_transform() -> Transform3D:
	return HeldPose.of(self, _held_class)


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
	PhysicsQueries.sync_object(self)
	if model != null:
		model.put_at_once()


## The match puts the player at a spawn point for a round. Fresh (the
## first round, or after the sides swap), or dead, they come back as a
## respawn brings them: whole, armoured as they started, with a spawn's
## loadout. Someone who lived through the last round keeps their armour and
## everything they carry, rounds in it and all, and is healed.
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
	_send(&"player_spawn", {"userid": userid})


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
		model.update_motion(velocity, yaw_degrees, duck_progress, on_ground, air_action, air_action_usec, height_above_ground)


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
	acceleration_speed = 0.0

	if cmd.toggle_noclip:
		noclip = not noclip
		velocity = Vector3.ZERO

	if not alive:
		if not respawns:
			_observe(cmd, dt)
		elif SimClock.tick_end_usec(cmd.tick) >= _respawn_at_usec:
			respawn()
		return

	# A throw over: what is in hand now is drawn (the next grenade of the
	# kind, or the last thing held).
	if _throwing and SimClock.tick_end_usec(cmd.tick) >= _throwing_until_usec:
		_throwing = false
		_draw(inventory.in_hand())

	# A number key takes that slot in hand, pressed again going on to the
	# next thing in it (the grenades, the knife and the Zeus); Q the last
	# thing held. What is in hand already, asked for again, stays as it is,
	# as Source has it (CBasePlayer::Weapon_ShouldSelectItem): no draw.
	if cmd.weapon_select == UserCmd.SELECT_LAST:
		inventory.select_last()
	elif cmd.weapon_select > 0:
		inventory.select_slot((cmd.weapon_select - 1) as ItemDef.Slot)
	# The wheel (invnext): a step through what is carried for each notch,
	# and only where it stops is drawn, with its deploy time. More notches
	# than things carried go round again, no further than once.
	if cmd.weapon_cycle != 0:
		var notches := signi(cmd.weapon_cycle) * mini(absi(cmd.weapon_cycle), inventory.entries().size())
		_changing_inventory = true
		for i in absi(notches):
			if notches > 0:
				inventory.select_next()
			else:
				inventory.select_prev()
		_changing_inventory = false
		_follow_hand()

	yaw_degrees = cmd.yaw_degrees
	pitch_degrees = cmd.pitch_degrees
	_recover_from_hits(dt)

	# R during the draw is kept, and the reload starts the moment the draw
	# is over: CS2 finishes the pull-out first.
	var reload := cmd.first_press(UserCmd.RELOAD)
	if weapon != null:
		var reload_at := -1
		if reload != null:
			reload_at = SimClock.usec_at(cmd.tick, reload.when)
			if weapon.is_drawing(reload_at):
				_reload_after_draw = true
				reload_at = -1
		if reload_at < 0 and _reload_after_draw and not weapon.is_drawing(SimClock.tick_end_usec(cmd.tick)):
			_reload_after_draw = false
			reload_at = weapon.drawn_usec()
		if reload_at >= 0 and weapon.start_reload(reload_at):
			reload_started.emit()
			_send(&"weapon_reload", {"userid": userid})

	# Held still: by the match in freeze time, or by the bomb while planting
	# or defusing (the game's holds_still query).
	held_still = _held_by_the_game()
	var still := frozen or held_still

	# A tap shorter than a tick still jumps: the press is in the command even
	# if the key is back up by its end. The earliest press is the one that
	# jumps, and the tick splits there (PlayerBody.simulate). A jump from a
	# held key has no transition to time, so it stays at the tick's start.
	var jump := cmd.first_press(UserCmd.JUMP)
	wants_jump = not still and (cmd.held(UserCmd.JUMP) or jump != null)
	if jump != null and wants_jump:
		jump_fraction = jump.when
	wants_duck = cmd.held(UserCmd.DUCK) or _crouched_by_the_game()

	if still:
		# Still, but falling if there is anywhere to fall, and the weapon
		# still reloads.
		simulate(dt)
		_update_weapon(cmd, dt, true)
		return

	if noclip:
		wish_dir = _noclip_direction(cmd)
		simulate(dt)
		return

	wish_dir = cmd.wish_direction()
	if wish_dir.length_squared() > 0.0:
		wish_speed = _max_speed(cmd)
		acceleration_speed = _uncrouched_speed(cmd)

	simulate(dt)
	_update_weapon(cmd, dt, false)


## Whether the game holds the player still: planting or defusing the bomb,
## which the bomb says (the holds_still query). Never out of a game.
func _held_by_the_game() -> bool:
	if not is_instance_valid(world):
		return false
	return bool(world.game.query(&"holds_still", [userid], false))


## Whether the game makes the player crouch whatever their duck key says:
## planting the bomb, which the bomb says (the crouches query).
func _crouched_by_the_game() -> bool:
	if not is_instance_valid(world):
		return false
	return bool(world.game.query(&"crouches", [userid], false))


## Fires every round the command asks for, at the instant and the aim it
## asked for it: each press at its own fraction of the tick and its own look
## angles, then, while the trigger is held, the next round the moment the
## weapon is ready rather than on the tick after (on the tick, every gap
## rounds up to whole ticks and 600 rounds a minute comes out at 591). With
## a grenade in hand, the buttons throw it instead (_update_grenade).
func _update_weapon(cmd: UserCmd, dt: float, still: bool) -> void:
	if weapon == null:
		if _held_class == Knife.ITEM_CLASS:
			_update_knife(cmd, still)
		else:
			_update_grenade(cmd, still)
		return

	var now := SimClock.tick_end_usec(cmd.tick)
	# A magazine is in by the tick's end, ready for a press inside it. A
	# shotgun's shells go in after the tick's presses, which stop its reload
	# with only the shells in by their own instant (Weapon.fire).
	var by_shell := weapon.data.reloads_single_shells
	if not by_shell:
		weapon.finish_reload_if_due(now)
	# The weapon is told about the trigger rather than left to infer it from
	# the gap since the last round, so the crosshair starts coming home on the
	# tick the button comes up instead of a round and a quarter later. A press
	# that happened and ended inside the tick still counts as held for it.
	var presses := cmd.presses(UserCmd.ATTACK)
	if still:
		presses.clear()
	weapon.trigger_held = not still and (cmd.held(UserCmd.ATTACK) or not presses.is_empty())
	shooter_state.speed = Vector2(velocity.x, velocity.z).length()
	shooter_state.on_ground = on_ground
	shooter_state.ducked = is_ducked
	shooter_state.walking = cmd.held(UserCmd.WALK)
	weapon.update(dt, now, shooter_state)

	# Right clicks step a scope through its zoom levels and the trigger's
	# presses fire, each at its own instant and in the order they came, so a
	# round goes out at the zoom it was fired at (_zoom_by).
	var zooms := cmd.presses(UserCmd.ATTACK2)
	var zoomed := 0
	for press in presses:
		zoomed = _zoom_by(cmd, zooms, zoomed, press.when)
		# Every press is the trigger going down afresh, which a
		# semi-automatic gun waits for (Weapon.press_trigger).
		weapon.press_trigger()
		_try_shoot(
			SimClock.usec_at(cmd.tick, press.when), press.when,
			press.yaw_degrees, press.pitch_degrees
		)

	if weapon.trigger_held and cmd.held(UserCmd.ATTACK):
		var began := SimClock.tick_start_usec(cmd.tick)
		var at := clampi(weapon.next_shot_usec(), began, now)
		var fraction := float(at - began) / float(SimClock.tick_usec())
		zoomed = _zoom_by(cmd, zooms, zoomed, fraction)
		_try_shoot(at, fraction, cmd.yaw_degrees, cmd.pitch_degrees)
	_zoom_by(cmd, zooms, zoomed, 1.0)
	if by_shell:
		weapon.finish_reload_if_due(now)


## The right clicks of zooms from the from-th on that came by until (a
## fraction of the tick), each stepping the scope at its own instant
## (Weapon.press_zoom); the index of the first left.
func _zoom_by(cmd: UserCmd, zooms: Array[UserCmd.SubtickStep], from: int, until: float) -> int:
	while from < zooms.size() and zooms[from].when <= until:
		var at := SimClock.usec_at(cmd.tick, zooms[from].when)
		if weapon.press_zoom(at):
			_send(&"weapon_zoom", {"userid": userid}, at)
		from += 1
	return from


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
	var reloading := weapon.is_reloading(at_usec)
	var shot := weapon.fire(
		at_usec, tick_fraction, origin, yaw - thrown.x, pitch + thrown.y, shooter_state
	)
	if shot == null:
		# Nothing in the magazine: the trigger clicks, once a pull.
		if weapon.dry_fire(at_usec):
			_send(&"weapon_fire_on_empty", {"userid": userid, "weapon": weapon.data.item_class}, at_usec)
		return
	if reloading:
		reload_stopped.emit()
	rounds_fired += 1
	var item := ItemRegistry.item(weapon.data.item_class)
	var silenced := item != null and item.silenced_by_default
	_send(&"weapon_fire", {
		"userid": userid, "weapon": weapon.data.item_class, "silenced": silenced,
	}, at_usec)

	# The round is the player's: who fired it and from which side goes with
	# its damage (Hitscan.fire_as), and every surface it meets and the hurt it
	# does are the game's events. Your own hull and hitboxes are not targets.
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(hit_target.rids())
	var shooter := Hitscan.Shooter.new(
		userid, team, team_damage_scale, exclude,
		world.game.events if is_instance_valid(world) else null
	)
	if is_instance_valid(world) and is_instance_valid(world.game.drop_physics):
		shooter.on_free_segment = world.game.drop_physics.push_bullet_segment.bind(weapon.data, shot.origin)
	# A shotgun's pellets are each traced and do their damage on their own.
	for i in shot.pellets():
		var pellet := shot.pellet_shot(i)
		# Where it left and which way, for whoever draws its tracer, before
		# the impacts it ends at.
		var angles := PlayerInput.angles_from_direction(pellet.direction)
		_send(&"fire_bullets", {
			"userid": userid, "weapon": weapon.data.item_class,
			"mode": 1 if silenced or shot.zoom_level > 0 else 0,
			"x": shot.origin.x, "y": shot.origin.y, "z": shot.origin.z,
			"pitch": angles.y, "yaw": angles.x, "inaccuracy": tan(deg_to_rad(shot.inaccuracy)), "pellet": i,
		}, at_usec)
		var result := Hitscan.fire_as(get_world_3d().direct_space_state, pellet, weapon.data, shooter)
		shot_traced.emit(pellet, result)


## A grenade in hand: either attack button pulls the pin once the draw is
## over, and letting go of both throws it, as hard as the buttons held just
## before say (GrenadeRules.strength_for: the left alone overhand, the right
## alone a lob, both between). The throw is the game's own (the throw
## command, which takes the grenade from the inventory and sends
## grenade_thrown); the hand throws for the throw clip's length, and then
## draws the next of the kind or goes back to the last thing held.
func _update_grenade(cmd: UserCmd, still: bool) -> void:
	var entry := inventory.in_hand()
	if entry == null or not entry.item.is_grenade() or still or _throwing:
		_pin_pulled = false
		return
	var left := cmd.held(UserCmd.ATTACK) or cmd.pressed_during(UserCmd.ATTACK)
	var right := cmd.held(UserCmd.ATTACK2) or cmd.pressed_during(UserCmd.ATTACK2)
	if not _pin_pulled:
		if (left or right) and SimClock.tick_end_usec(cmd.tick) >= _drawn_until_usec:
			_pin_pulled = true
			_throw_left = left
			_throw_right = right
			pin_pulled.emit()
		return
	if cmd.held(UserCmd.ATTACK) or cmd.held(UserCmd.ATTACK2):
		# Still held: whichever are down now say how hard.
		_throw_left = cmd.held(UserCmd.ATTACK)
		_throw_right = cmd.held(UserCmd.ATTACK2)
		return
	_pin_pulled = false
	var underhand := _throw_right and not _throw_left
	_throwing = true
	_throwing_until_usec = SimClock.tick_end_usec(cmd.tick) + int(roundf(
		(THROW_UNDERHAND_SECONDS if underhand else THROW_OVERHAND_SECONDS) * 1_000_000.0
	))
	grenade_released.emit(underhand)
	if is_instance_valid(world):
		var strength := GrenadeRules.strength_for(_throw_left, _throw_right)
		world.game.command(userid, "throw %s %s" % [entry.item.item_class, strength])


## The knife in hand: each press of either button swings at its own
## instant and aim, the left a slash and the right a stab, and while a
## button stays down the next swing starts the moment the knife is ready,
## as the guns fire (Knife). The left wins when both are down together.
func _update_knife(cmd: UserCmd, still: bool) -> void:
	if still:
		return
	var presses: Array[UserCmd.SubtickStep] = []
	presses.append_array(cmd.presses(UserCmd.ATTACK))
	presses.append_array(cmd.presses(UserCmd.ATTACK2))
	presses.sort_custom(func(a: UserCmd.SubtickStep, b: UserCmd.SubtickStep) -> bool: return a.when < b.when)
	for press in presses:
		var at := SimClock.usec_at(cmd.tick, press.when)
		if knife.is_ready(at):
			_swing(press.button == UserCmd.ATTACK2, at, press.when, press.yaw_degrees, press.pitch_degrees)
	var light := cmd.held(UserCmd.ATTACK)
	if light or cmd.held(UserCmd.ATTACK2):
		var began := SimClock.tick_start_usec(cmd.tick)
		var now := SimClock.tick_end_usec(cmd.tick)
		var at := maxi(knife.ready_usec, began)
		if at <= now:
			var fraction := float(at - began) / float(SimClock.tick_usec())
			_swing(not light, at, fraction, cmd.yaw_degrees, cmd.pitch_degrees)


## A swing of the knife at at_usec, from where the player was at that
## instant (as a round leaves: _try_shoot) and the aim of that instant, a
## hit's flinch in it: traced, its damage dealt, weapon_fire sent as CS2
## sends it for a swing, and knife_swung for whoever draws it.
func _swing(heavy: bool, at_usec: int, tick_fraction: float, yaw: float, pitch: float) -> void:
	var begun := knife.begin(heavy, at_usec)
	var at := previous_position.lerp(global_position, clampf(tick_fraction, 0.0, 1.0))
	var origin := at + Vector3.UP * eye_height()
	var thrown := hit_punch.value
	var aim_yaw := deg_to_rad(yaw - thrown.x)
	var aim_pitch := deg_to_rad(pitch + thrown.y)
	var direction := Vector3(
		-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch)
	)
	_send(&"weapon_fire", {"userid": userid, "weapon": Knife.ITEM_CLASS, "silenced": false}, at_usec)
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(hit_target.rids())
	var teammates: Array[RID] = []
	if is_instance_valid(world):
		for other in world.players:
			if other != self and other.team == team and other.alive:
				teammates.append_array(other.hit_target.rids())
	var swing := Knife.swing(
		get_world_3d().direct_space_state, begun, origin, direction, userid, team,
		team_damage_scale, exclude, teammates, world.game.events if is_instance_valid(world) else null
	)
	knife_swung.emit(swing)


## Sends a game event, when the player is in a game.
func _send(event_name: StringName, fields: Dictionary, at_usec: int = -1) -> void:
	if is_instance_valid(world):
		world.game.events.send(event_name, fields, at_usec)


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
##
## Crouched on the ground, the top is duck_modifier (0.34) of the held
## item's, eased in and out with the duck itself, so a crouch always walks at
## the same speed and a half crouch at a speed between: the AK-47's 215 gives
## 73, the knife's 250 gives 85. It was once full speed until the duck
## finished 0.4 s after the press, then a third of it, and full speed again
## the tick the key came up. The duck is read as the last tick left it, as
## Source's CheckParameters reads it before Duck, and only on the ground, as
## there: in the air the duck leaves the air's acceleration alone. Walking
## crouched is no slower than crouching.
func _max_speed(cmd: UserCmd) -> float:
	var speed := _uncrouched_speed(cmd)
	if not on_ground:
		return speed
	var top := _top_speed() * lerpf(1.0, config.duck_modifier, duck_progress)
	return minf(speed, top)


## The top without the duck: what the held item and a tag allow, walking
## if the walk key is held. The ground's acceleration works from it
## (PlayerBody.acceleration_speed), crouched or not.
func _uncrouched_speed(cmd: UserCmd) -> float:
	var speed := _top_speed()
	if cmd.held(UserCmd.WALK):
		speed *= config.walk_modifier
	return speed


## What the held item lets the player run at, less a tag's share.
func _top_speed() -> float:
	# Scoped, the gun's scoped speed (the AWP's 100 against 200).
	var top := weapon.max_speed() if weapon != null and weapon.zoom_level > 0 else config.max_speed
	return top * velocity_modifier


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
	# Nobody walks into a body that is not there, from this moment: whoever
	# moves after it in this tick meets nothing (the hulls are looked over
	# once a tick, so what changes one in a tick says so).
	collision_layer = 0
	PhysicsQueries.sync_object(self, false)
	_died_at_usec = SimClock.now_usec()
	_respawn_at_usec = _died_at_usec + int(respawn_seconds * 1_000_000.0)
	var zone: StringName = hit_target.last_hitbox.zone if hit_target.last_hitbox != null else &"chest"
	_fall()
	# The gun leaves the hand: it falls as an item of its own (ItemDrops),
	# from where the hand held it.
	if model != null:
		model.let_go()
	killed.emit(zone)
	# What the death drops is let go at the end of the tick, moving as the
	# body was.
	death_velocity = velocity
	velocity = Vector3.ZERO
	_forget_hits()


## The body goes limp and falls where it died, pushed the way the killing
## round was going, as a ragdoll made from the hitbox capsules: the one
## made ahead (prepare_to_fall), or one made now where there is none.
## Nothing is done without the capsules or the model.
func _fall() -> void:
	if model == null or _capsules.is_empty() or model.character_rig == null:
		return
	var hit_bone := -1
	if hit_target.last_hitbox != null:
		hit_bone = hitboxes.bone_of(hit_target.last_hitbox)
	var fell := 0
	ragdoll = _ragdoll_ready
	_ragdoll_ready = null
	if ragdoll != null and ragdoll.prepared_for(model.character_rig):
		fell = ragdoll.drop(velocity, hit_target.last_hit_direction, hit_bone)
	else:
		if ragdoll == null:
			ragdoll = Ragdoll.new()
			ragdoll.name = "Ragdoll"
			add_child(ragdoll)
		fell = ragdoll.build(
			model.character_rig, _capsules, MapImporter.SOURCE2_VIEWER_SCALE,
			velocity, _model_faces(), hit_target.last_hit_direction, hit_bone
		)
	if fell == 0:
		ragdoll.let_go()
		ragdoll = null
		return
	# The animation would pose the bones over the bodies' every frame.
	model.set_animating(false)


## Up off the floor: the ragdoll parked for the next death and the model
## animated again.
func _get_up() -> void:
	if ragdoll != null:
		ragdoll.park()
		_ragdoll_ready = ragdoll
		ragdoll = null
		if model != null:
			model.character_rig.reset_bone_poses()
			model.set_animating(true)
	if model != null:
		# Up somewhere else, as often as not (a bot back at its route's start
		# is moved by hand, not placed).
		model.put_at_once()
		model.play(model.idle)
		if model.holds_items and not _held_class.is_empty() and model.holding == _held_class:
			# Alive and spawned fresh, the body took what is in hand a moment
			# ago and the idle ended its draw: it draws again.
			model.play(&"draw")
		else:
			_body_holds(inventory.in_hand())
		# Posed now. Its bones were put back at rest, and until its animation
		# next stepped, a frame or two on, it stood so: arms out, and the gun
		# two feet from its hands.
		model.pose_again()


## Where the body is: the middle of the ragdoll while there is one, or
## where the player stands.
func body_centre() -> Vector3:
	if ragdoll == null or ragdoll.bodies.is_empty():
		return global_position + Vector3.UP * 36.0
	var sum := Vector3.ZERO
	for body: Ragdoll.Part in ragdoll.bodies.values():
		sum += body.global_position
	return sum / ragdoll.bodies.size()


## Dead with no respawn coming: after the freeze cam, watching a living
## teammate, the next one on a press of fire and the one before on the
## right button; jump goes from their eyes to behind them, then, where the
## match allows it, to flying free, and back to their eyes. Only your own
## side is watched.
func _observe(cmd: UserCmd, dt: float) -> void:
	var now := SimClock.tick_end_usec(cmd.tick)
	if now < _died_at_usec + int(freeze_cam_seconds * 1_000_000.0):
		return
	if observer_mode == ObserverMode.ROAMING:
		if cmd.first_press(UserCmd.JUMP) != null or cmd.first_press(UserCmd.ATTACK) != null \
				or cmd.first_press(UserCmd.ATTACK2) != null or not free_look:
			# Back to someone's eyes: the one watched before, if they live.
			observer_mode = ObserverMode.IN_EYE
			observing = _observed_before if _can_watch(_observed_before) else _next_teammate(null)
			_observed_before = null
			return
		_roam(cmd, dt)
		return
	var watching := _can_watch(observing)
	if cmd.first_press(UserCmd.JUMP) != null:
		if observer_mode == ObserverMode.IN_EYE and watching:
			observer_mode = ObserverMode.CHASE
		elif free_look:
			_start_roaming(observing if watching else null)
			return
		else:
			observer_mode = ObserverMode.IN_EYE
	if not watching or cmd.first_press(UserCmd.ATTACK) != null:
		observing = _next_teammate(observing if watching else null)
	elif cmd.first_press(UserCmd.ATTACK2) != null:
		observing = _next_teammate(observing, -1)


## Whether a player is one a dead player can watch: alive, on their side.
func _can_watch(other: PlayerSim) -> bool:
	return other != null and is_instance_valid(other) and other.alive and other.team == team


## The camera leaves the one watched and flies free from where it was:
## their eyes, or over your own body with nobody to watch.
func _start_roaming(watched: PlayerSim) -> void:
	observer_mode = ObserverMode.ROAMING
	_observed_before = watched
	if watched != null:
		observer_position = watched.global_position + Vector3.UP * watched.eye_height()
	else:
		observer_position = body_centre() + Vector3.UP * 64.0
	previous_observer_position = observer_position
	observer_velocity = Vector3.ZERO
	observing = null


## Flies the free camera one tick: toward where you look with the move
## keys, pitch and all, through anything in the way.
func _roam(cmd: UserCmd, dt: float) -> void:
	previous_observer_position = observer_position
	var top := SPEC_SPEED * (0.5 if cmd.held(UserCmd.WALK) else 1.0)
	var pitch := deg_to_rad(cmd.pitch_degrees)
	var yaw := deg_to_rad(cmd.yaw_degrees)
	var forward := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var keys := cmd.move.limit_length(1.0)
	var wish := forward * keys.y + right * keys.x
	observer_velocity = observer_step(observer_velocity, wish, top, dt)
	observer_position += observer_velocity * dt


## One tick of the free camera's speed (FullObserverMove's shape): wish is
## the way the keys ask for, as long as how much of top they ask.
static func observer_step(velocity_now: Vector3, wish: Vector3, top: float, dt: float) -> Vector3:
	var out := velocity_now
	var speed := out.length()
	if speed < 1.0:
		out = Vector3.ZERO
	else:
		var drop := maxf(speed, top / 4.0) * SPEC_FRICTION * dt
		out *= maxf(speed - drop, 0.0) / speed
	var wish_speed := minf(wish.length(), 1.0) * top
	if wish_speed <= 0.0:
		return out
	var wish_dir := wish.normalized()
	var add := wish_speed - out.dot(wish_dir)
	if add > 0.0:
		out += wish_dir * minf(SPEC_ACCELERATE * dt * wish_speed, add)
	return out


## The living teammate after this one (step 1) or before it (step -1),
## round and round; the first when there is none to follow. Only in the player's world: nobody else is in
## the game.
func _next_teammate(after: PlayerSim, step: int = 1) -> PlayerSim:
	if not is_instance_valid(world):
		return null
	var living: Array[PlayerSim] = []
	for other in world.players:
		if other != self and other.alive and other.team == team:
			living.append(other)
	if living.is_empty():
		return null
	var at := living.find(after)
	if at < 0:
		return living[0]
	return living[posmod(at + step, living.size())]


## Up again: whole, solid, able to be shot, watching nobody.
func _revive() -> void:
	alive = true
	hit_target.reset()
	hit_target.set_active(true)
	collision_layer = PLAYER_LAYER
	PhysicsQueries.sync_object(self, false)
	observing = null
	observer_mode = ObserverMode.IN_EYE
	_observed_before = null


## Back where the map put the player, whole, armoured as they started, with
## a spawn's loadout: CS2's knife and pistol, and starting_gun.
func respawn() -> void:
	# The loadout strips the player, armour and all, before the revive puts
	# the starting armour back.
	_loadout()
	_revive()
	place(_spawn_position, _spawn_yaw)
	velocity = Vector3.ZERO
	_forget_hits()
	_get_up()
	respawned.emit()
	_send(&"player_spawn", {"userid": userid})
