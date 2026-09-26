class_name Competitive
extends Node3D

## CS2's competitive, on whatever map is loaded: you and bots filling both
## sides, a match of MR12 rounds after warmup (MatchRules), and the game's
## systems a match plays with (money and buying in the map's buy zones, the
## bomb on its sites, grenades), with the HUD and what is seen and heard of
## them. F5 ends warmup, as mp_warmup_end does. practice() turns it into
## Practice: the same game with no bots and a warmup that does not end.
##
## It reads the map only through MapContents: spawn points, buy zones, bomb
## sites, callouts and the nav mesh. MapLoader fills that from an extracted
## map; the checks fill it by hand. Where a part is missing it plays on
## without it and says so in notes: no match without both sides' spawn
## points, a stand-in buy zone round each side's spawn points without the
## map's own, no bomb without sites, bots on straight lines without the nav
## mesh.

## Which side you play. It spawns you at one of the side's spawn points.
@export_enum("T", "CT") var spawn_team: String = "T"

## Players on each side, you among them; bots fill every other place. Over
## the map's nav mesh each walks from a spawn point to a bomb site and back,
## A and B in turn; without it, round its side's spawn points, the one part
## of the map it can be sure of. Each shoots whoever of the other side it sees.
@export var team_size: int = 5

## How long warmup lasts before the first round; CS2's is 120 s, and F5
## ends it early, as mp_warmup_end does. 0 goes straight to the first round.
@export var warmup_seconds: float = 120.0

## Whether the bots walk to the bomb sites and back, or round their own
## spawn points as they did before they had the nav mesh. Without the nav
## mesh they keep to their spawn points, where a straight line is safe.
@export var bots_walk_to_sites: bool = true

## Whether bots fill every place you do not take. Practice plays without
## them.
@export var with_bots: bool = true

## Whether warmup's clock stands still, so warmup lasts until F5 ends it
## (mp_warmup_pausetimer 1, MatchRules.warmup_paused). Practice pauses it.
@export var warmup_paused: bool = false

## The line Practice shows in the top left.
const PRACTICE_NOTE := "Practice: no bots; warmup does not end; F5 starts the rounds."

## How far round a side's spawn points the stand-in buy zone reaches, where
## the map's own zones have not been extracted.
const BUY_ZONE_STAND_IN_MARGIN := 128.0

## The callouts (env_cs_place) the bots walk to, A then B.
const SITE_CALLOUTS: Array[String] = ["BombsiteA", "BombsiteB"]

## What runs the game: you first, then the bots in the order they were
## placed, then the match, every tick.
var world: GameWorld
## The map being played on.
var map: MapContents
var player: PlayerBody
## The match being played: warmup, the rounds and the score. Null without
## both sides' spawn points.
var match_state: MatchState
## The game's systems in world.game, as a match has them: money and buying
## (with the map's own buy zones), the bomb (its sites, the map's own
## blast), grenades. Null without a match.
var economy: Economy
var bomb_system: BombSystem
var grenade_system: GrenadeSystem
var bots: Array[Bot] = []
var hud: GameHud
## What is missing from the game, one line each; the scene shows them.
var notes: PackedStringArray = []
## The bomb sites' floors the bots walk to, A then B; empty when they walk
## their side's spawn points instead.
var _sites := PackedVector3Array()


## Practice, a departure from CS2 (whose offline practice is a match with
## bots you choose): competitive's whole game, money, buying, the bomb and
## grenades, with no bots and a warmup that lasts until F5, which then starts
## the rounds as it does in competitive. Set before start.
func practice() -> void:
	with_bots = false
	warmup_paused = true


## Sets the game up on a map, in a world, once this node is in the scene.
func start(game_world: GameWorld, map_contents: MapContents) -> void:
	world = game_world
	map = map_contents
	if not with_bots and warmup_paused:
		notes.append(PRACTICE_NOTE)
	_place_player()
	_place_bots()
	_prepare_holding()
	_start_match()
	hud = GameHud.new()
	hud.name = "Hud"
	hud.player = player as PlayerController
	hud.match_state = match_state
	hud.economy = economy
	hud.bomb = bomb_system.bomb if bomb_system != null else null
	hud.userid = (player as PlayerSim).userid
	add_child(hud)
	_add_views()
	var impacts := BulletImpacts.new()
	impacts.name = "BulletImpacts"
	add_child(impacts)
	# The guns dropped (G) and left by the dead, on the ground.
	var dropped := DroppedItemView.new()
	dropped.name = "Dropped"
	add_child(dropped)
	dropped.watch(world.game)


## You, at one of your side's spawn points the game would fill first, or
## where the map says to drop in without them.
func _place_player() -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	(player as PlayerController).team = spawn_team
	add_child(player)
	world.add_player(player as PlayerSim)

	var spawns: Array = map.spawns[spawn_team]
	if spawns.is_empty():
		player.global_position = map.drop_position
		return
	# They sit a little above the floor, as they do in the game, and the
	# player drops onto it.
	var first_choice := spawns.filter(func(candidate: Dictionary) -> bool:
		return candidate["priority"] == spawns[0]["priority"])
	var spawn: Dictionary = first_choice.pick_random()
	(player as PlayerController).place(spawn["position"], spawn["yaw"])


## Bots in every place you do not take, on both sides, each walking its
## route (bot_route) from wherever the match spawns it; without the nav mesh
## they walk straight lines between their side's spawn points.
func _place_bots() -> void:
	if not with_bots:
		return
	if map.nav_mesh != null and bots_walk_to_sites:
		_sites = site_floors(map.nav_mesh, map.places, map.bomb_sites)
		if _sites.is_empty():
			notes.append("Bots walk round their spawn points: the bomb sites are not on the nav mesh.")
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	var number := 0
	for team: String in MatchState.SIDES:
		var spawns: Array = map.spawns[team]
		if spawns.is_empty():
			continue
		for i in team_size - (1 if team == spawn_team else 0):
			number += 1
			var bot := scene.instantiate() as Bot
			bot.name = "Bot%d" % number
			bot.team = team
			# It spawns with the knife and its side's pistol, as you do, and
			# buys the rest in freeze time, by a profile's preferences.
			bot.buy_template = BotBuying.template_for(bot.name)
			bot.nav_mesh = map.nav_mesh
			bot.route = bot_route(map.spawns, team, i, _sites)
			add_child(bot)
			world.add_player(bot)
			bot.global_position = spawns[i % spawns.size()]["position"]
			bots.append(bot)
	if not bots.is_empty() and map.nav_mesh == null:
		notes.append("Bots walk straight lines between their spawn points: the map has no nav mesh.")


## What anyone may take in hand, read now rather than when it is bought,
## picked up or drawn: every item on either side's menu, the knife and the
## bomb, their clips, which every body takes up (the hitboxes ride them),
## and their models, which a bot's body shows and your own shadow casts.
## CS2 precaches every gun as the map loads
## (reference/research/weapon-preload.md); the guns no menu holds are
## left, since nobody can get one.
func _prepare_holding() -> void:
	var body: PlayerModel = null
	for sim: PlayerSim in world.players:
		if sim.model != null:
			body = sim.model
			break
	if body == null:
		return
	for side: String in MatchState.SIDES:
		var anyone := PackedStringArray(Loadout.items(side))
		anyone.append_array(PackedStringArray(["weapon_knife", "weapon_c4"]))
		body.prepare_holding(anyone, side)


## The route of a side's nth bot: from one of its side's spawn points to a
## bomb site and back, A and B in turn, when there are sites to go to (the
## nav mesh, and bots_walk_to_sites); round its side's spawn points when
## not. Where on it a bot sets off from is the match's (Bot.spawn_at).
static func bot_route(spawns: Dictionary, team: String, nth: int, sites: PackedVector3Array) -> PackedVector3Array:
	if sites.is_empty():
		return side_route(spawns, team)
	var points: Array = spawns[team]
	return PackedVector3Array([points[nth % points.size()]["position"], sites[nth % sites.size()]])


## A side's spawn points, in order, as a loop to walk.
static func side_route(spawns: Dictionary, team: String) -> PackedVector3Array:
	var route := PackedVector3Array()
	for spawn: Dictionary in spawns[team]:
		route.append(spawn["position"])
	return route


## The floor at the middle of each bomb site, A then B, for the bots to walk
## to. From the callouts named BombsiteA and BombsiteB (env_cs_place) where
## the map has both: a callout's origin is its brush's middle, over the
## floor, so it is taken down onto the nav mesh. Maps that name their
## callouts otherwise fall back to the bomb sites' own volumes
## (func_bomb_target), their middles taken down the same way. Empty where
## neither gives two sites on the mesh.
static func site_floors(nav_mesh: SourceNavMesh, places: Dictionary, bomb_sites: Array[BombSite]) -> PackedVector3Array:
	var floors := PackedVector3Array()
	for place in SITE_CALLOUTS:
		if not places.has(place):
			floors.clear()
			break
		var on: Variant = _floor_under(nav_mesh, places[place][0], 300.0)
		if on == null:
			floors.clear()
			break
		floors.append(on)
	if floors.size() == SITE_CALLOUTS.size() or bomb_sites.size() < 2:
		return floors
	for site in bomb_sites:
		var box := site.bounds()
		# From the middle of the volume down through its floor.
		var on: Variant = _floor_under(nav_mesh, box.get_center(), box.size.y * 0.5 + 64.0)
		if on == null:
			return PackedVector3Array()
		floors.append(on)
	return floors


## The nav mesh's floor under a point, looking this far below it; else the
## nearest area's. Null where there is none within reach.
static func _floor_under(nav_mesh: SourceNavMesh, origin: Vector3, below: float) -> Variant:
	var area := nav_mesh.area_at(origin, below, 24.0, 0)
	if area == null:
		area = nav_mesh.nearest_area(origin, 256.0, 0)
	if area == null:
		return null
	var on := origin if area.covers(origin) else area.centre
	return Vector3(on.x, area.floor_at(on), on.z)


## The match: everyone in it, spawned for warmup, which counts down to the
## first round, and the game's systems it plays with. After a side swap each
## bot takes a route of its new side.
func _start_match() -> void:
	if not map.has_both_sides():
		notes.append("No match: the map needs spawn points for both sides.")
		return
	match_state = MatchState.new()
	match_state.name = "Match"
	match_state.rules = MatchRules.new()
	match_state.rules.warmup_seconds = warmup_seconds
	match_state.rules.warmup_paused = warmup_paused
	match_state.spawns = map.spawns
	add_child(match_state)
	# Everyone in the world plays in it, and the world runs it after them.
	world.match_state = match_state
	match_state.sides_swapped.connect(_route_bots_again)
	_add_systems()
	match_state.start()


func _route_bots_again() -> void:
	var counts := {"T": 0, "CT": 0}
	for sim in match_state.players:
		if sim is Bot:
			(sim as Bot).route = bot_route(map.spawns, sim.team, counts[sim.team], _sites)
			counts[sim.team] += 1


## The game's systems a match plays with, in world.game, added before the
## match starts so they hear its first events.
func _add_systems() -> void:
	economy = Economy.new(MoneyRules.new(), _buy_zones())
	economy.match_rules = match_state.rules
	world.game.add_system(economy)
	if not map.bomb_sites.is_empty():
		var rules := C4Rules.new()
		if map.bomb_radius > 0.0:
			rules.bomb_damage = map.bomb_radius
		bomb_system = BombSystem.new(map.bomb_sites, rules)
		world.game.add_system(bomb_system)
	grenade_system = GrenadeSystem.new()
	# In a match a grenade does CS2's share to the thrower's own side.
	grenade_system.team_damage_scale = GrenadeRules.TEAM_DAMAGE_IN_MATCH
	world.game.add_system(grenade_system)


## The map's buy zones. Without them, a stand-in box round each side's spawn
## points, and a note saying so; CS2 has no such fallback.
func _buy_zones() -> BuyZones:
	if map.buy_zones != null:
		return map.buy_zones
	notes.append("Buying is round each side's spawn points instead of the map's buy zones.")
	return stand_in_buy_zones(map.spawns)


static func stand_in_buy_zones(spawns: Dictionary) -> BuyZones:
	var stand_in := BuyZones.new()
	for side: String in MatchState.SIDES:
		var box := AABB(spawns[side][0]["position"], Vector3.ZERO)
		for spawn: Dictionary in spawns[side]:
			box = box.expand(spawn["position"])
		stand_in.add_box(side, box.grow(BUY_ZONE_STAND_IN_MARGIN))
	return stand_in


## What is seen and heard of the systems: the grenades and their smoke and
## fire, the bomb on the ground and its blast, a flash's white-out over the
## HUD, as CS2's covers it, the hits and deaths others hear, and the
## rounds' tracers and the guns' muzzle flashes.
func _add_views() -> void:
	if grenade_system != null:
		var grenade_view := GrenadeView.new()
		grenade_view.name = "Grenades"
		add_child(grenade_view)
		grenade_view.watch(world.game)
		var canvas := CanvasLayer.new()
		canvas.layer = 2
		add_child(canvas)
		var overlay := FlashOverlay.new()
		overlay.game = world.game
		overlay.viewer_id = (player as PlayerSim).userid
		canvas.add_child(overlay)
	if bomb_system != null:
		var bomb_view := C4View.new()
		bomb_view.name = "Bomb"
		bomb_view.bomb = bomb_system.bomb
		add_child(bomb_view)
	# What the one hit and those near hear of a hit, and the death groan.
	var hit_sounds := HitSounds.new()
	hit_sounds.name = "HitSounds"
	add_child(hit_sounds)
	hit_sounds.watch(world.game, (player as PlayerSim).userid)
	# The rounds' tracers and the guns' muzzle flashes.
	var shot_effects := ShotEffects.new()
	shot_effects.name = "ShotEffects"
	add_child(shot_effects)
	shot_effects.watch(world.game, (player as PlayerSim).userid, player as PlayerController)


## F5 ends warmup, as mp_warmup_end does, on the world's next tick.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F5 and match_state != null:
		match_state.end_warmup_on_next_tick()
