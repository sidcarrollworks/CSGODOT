extends Node3D

## The dust2 scene.
##
## The map itself is not in this repository and never will be: it is Valve's
## geometry, extracted from your own CS2 install into the gitignored assets/
## directory. This scene finds whatever landed there and imports it, or tells
## you how to produce it if nothing has.
##
## The exported filenames depend on Source 2 Viewer's output layout, so
## nothing here hardcodes them; MapImporter searches the directories.

const MAP_DIR := "res://assets/maps/de_dust2"
const COLLISION_DIR := "res://assets/maps/de_dust2_physics"
const SKYBOX_DIR := "res://assets/maps/de_dust2_skybox"

## The entity lump and the sky panorama, relative to the directory the world
## glTF is in.
const ENTITIES_FILE := "entities/default_ents.vents"
const SKY_FILE := "../../materials/skybox/sky_de_dust2.exr"

## The floor the game's bots walk (scripts/extract_assets.sh nav).
const NAV_FILE := "res://assets/maps/de_dust2/maps/de_dust2.nav"

## Which side's spawn points to start at. They come from the map's entity
## lump; the glTF does not carry them.
@export_enum("T", "CT") var spawn_team: String = "T"

## Where to drop the player in if the entity lump was not extracted.
@export var spawn_position := Vector3.ZERO

## Without spawn points: start above the centre of the map's bounding box
## rather than at spawn_position. Noclip (V) from there.
@export var use_bounds_centre_as_spawn: bool = true

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

## How far round a side's spawn points the stand-in buy zone reaches, where
## the map's own zones have not been extracted.
const BUY_ZONE_STAND_IN_MARGIN := 128.0

var importer: MapImporter
var skybox: MapImporter
## What runs the game: you first, then the bots in the order they were
## placed, then the match, every tick.
var world: GameWorld
var player: PlayerBody
## The match being played: warmup, the rounds and the score.
var match_state: MatchState
## The game's systems in world.game, as a match has them: money and buying
## (with dust2's own buy zones), the bomb (its two sites, the map's own
## blast), grenades. Null without a match.
var economy: Economy
var bomb_system: BombSystem
var grenade_system: GrenadeSystem

## The map's entity lump, parsed once for whoever needs it.
var entities: Array[Dictionary] = []

## The map's nav mesh, read once for every bot; its `error` says why not.
var nav_mesh: SourceNavMesh
## The bomb sites' floors the bots walk to, A then B; empty when they walk
## their side's spawn points instead.
var _sites := PackedVector3Array()


func _ready() -> void:
	world = GameWorld.new()
	world.name = "World"
	add_child(world)
	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		MapLighting.build(self, {}, entities, "")
		_build_fallback()
		return
	entities = SourceEntities.parse(
		ProjectSettings.globalize_path(map_file.get_base_dir().path_join(ENTITIES_FILE))
	)

	importer = MapImporter.new()
	importer.source_path = map_file
	importer.collision_path = MapImporter.find_collision_file(COLLISION_DIR)
	importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	importer.layer_textures_dir = MAP_DIR
	importer.lightmaps_dir = "."
	add_child(importer)

	if importer.stats.has("error"):
		# Found but unreadable, which is what an interrupted extraction leaves.
		push_error("dust2 import failed: %s" % importer.stats["error"])
		MapLighting.build(self, {}, entities, "")
		_build_fallback(
			"dust2 is there but would not load:\n    %s\n\n" % importer.stats["error"]
			+ "An extraction that was interrupted leaves it like this.\n"
			+ "Run it again:\n"
			+ "    scripts/extract_assets.sh map"
		)
		return

	var lighting := MapLighting.build(
		self, importer.stats.get("sun", {}), entities,
		map_file.get_base_dir().path_join(SKY_FILE).simplify_path(),
		importer.stats.get("lightmaps", {}).get("ambient")
	)
	print("--- lighting: sun energy %.2f, exposure %.2f, sky from %s, fog %s, ambient from %s" % [
		lighting["sun_energy"], lighting["exposure"], lighting["sky"], "on" if lighting["fog"] else "off",
		lighting["ambient"],
	])
	_build_skybox()
	_place_player(map_file)
	_place_bots()
	_prepare_holding()
	_start_match()
	var hud := GameHud.new()
	hud.name = "Hud"
	hud.player = player as PlayerController
	hud.match_state = match_state
	hud.economy = economy
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


## Bots in every place you do not take, on both sides, each walking its
## route (bot_route) from wherever the match spawns it. The nav mesh is read
## once for all of them; without it they walk straight lines between their
## side's spawn points.
func _place_bots() -> void:
	var spawns := SourceEntities.player_spawns(entities)
	nav_mesh = SourceNavMesh.load_file(NAV_FILE)
	if not nav_mesh.error.is_empty():
		push_warning("Bots walk straight lines between their spawn points: %s" % nav_mesh.error)
		_show_note("Bots walk straight lines between their spawn points:
%s" % nav_mesh.error)
		nav_mesh = null
	else:
		print("--- nav mesh: %s" % nav_mesh.summary())
	if nav_mesh != null and bots_walk_to_sites:
		_sites = _bomb_site_floors()
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	var number := 0
	for team: String in ["T", "CT"]:
		if (spawns[team] as Array).is_empty():
			continue
		for i in team_size - (1 if team == spawn_team else 0):
			number += 1
			var bot := scene.instantiate() as Bot
			bot.name = "Bot%d" % number
			bot.team = team
			# It spawns with the knife and its side's pistol, as you do, and
			# buys the rest in freeze time, by a profile's preferences.
			bot.buy_template = BotBuying.template_for(bot.name)
			bot.nav_mesh = nav_mesh
			bot.route = bot_route(spawns, team, i, _sites)
			add_child(bot)
			world.add_player(bot)
			bot.global_position = spawns[team][i % spawns[team].size()]["position"]


## What anyone may take in hand, read now rather than on the tick it is
## bought, picked up or drawn: every item on either side's menu, the knife
## and the bomb, whose clips every body takes up (the hitboxes ride them),
## and the models of what a bot's body shows.
func _prepare_holding() -> void:
	var body: PlayerModel = null
	for sim: PlayerSim in world.players:
		if sim.model != null:
			body = sim.model
			break
	if body == null:
		return
	for side: String in ["T", "CT"]:
		body.prepare_holding(BotBuying.may_hold(side), side)
		var anyone := PackedStringArray(Loadout.items(side))
		anyone.append_array(PackedStringArray(["weapon_knife", "weapon_c4"]))
		body.prepare_holding(anyone, side, false)


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


## The match: everyone in it, spawned for warmup, which counts down to the
## first round, and the game's systems it plays with. After a side swap each
## bot takes a route of its new side.
func _start_match() -> void:
	var spawns := SourceEntities.player_spawns(entities)
	if (spawns["T"] as Array).is_empty() or (spawns["CT"] as Array).is_empty():
		return
	match_state = MatchState.new()
	match_state.name = "Match"
	match_state.rules = MatchRules.new()
	match_state.rules.warmup_seconds = warmup_seconds
	match_state.spawns = spawns
	add_child(match_state)
	# Everyone in the world plays in it, and the world runs it after them.
	world.match_state = match_state
	match_state.sides_swapped.connect(func() -> void:
		var counts := {"T": 0, "CT": 0}
		for sim in match_state.players:
			if sim is Bot:
				(sim as Bot).route = bot_route(spawns, sim.team, counts[sim.team], _sites)
				counts[sim.team] += 1)
	_add_systems(spawns)
	match_state.start()


## The game's systems a match on dust2 plays with, in world.game, added
## before the match starts so they hear its first events.
func _add_systems(spawns: Dictionary) -> void:
	economy = Economy.new(MoneyRules.new(), _buy_zones(spawns))
	economy.match_rules = match_state.rules
	world.game.add_system(economy)
	var sites := BombSite.from_volumes(BrushVolume.bomb_sites(entities, MAP_DIR))
	if sites.is_empty():
		_show_note("No bomb sites: run scripts/extract_assets.sh volumes. There is no bomb.", 1)
	else:
		var rules := C4Rules.new()
		var radius := SourceEntities.bomb_radius(entities)
		if radius > 0.0:
			rules.bomb_damage = radius
		bomb_system = BombSystem.new(sites, rules)
		world.game.add_system(bomb_system)
	grenade_system = GrenadeSystem.new()
	# In a match a grenade does CS2's share to the thrower's own side.
	grenade_system.team_damage_scale = GrenadeRules.TEAM_DAMAGE_IN_MATCH
	world.game.add_system(grenade_system)


## Each side's func_buyzone (scripts/extract_assets.sh volumes). Without
## them, a stand-in box round each side's spawn points, and a note saying
## so; CS2 has no such fallback.
func _buy_zones(spawns: Dictionary) -> BuyZones:
	var zones := BuyZones.from_volumes(BrushVolume.buy_zones(entities, MAP_DIR))
	if not zones.zones["T"].is_empty() and not zones.zones["CT"].is_empty():
		return zones
	_show_note("No buy zones: run scripts/extract_assets.sh volumes. Buying is round each side's spawn points instead.", 2)
	var stand_in := BuyZones.new()
	for side: String in ["T", "CT"]:
		var box := AABB(spawns[side][0]["position"], Vector3.ZERO)
		for spawn: Dictionary in spawns[side]:
			box = box.expand(spawn["position"])
		stand_in.add_box(side, box.grow(BUY_ZONE_STAND_IN_MARGIN))
	return stand_in


## What is seen and heard of the systems: the grenades and their smoke and
## fire, the bomb on the ground and its blast, a flash's white-out over the
## HUD, as CS2's covers it, and the hits and deaths others hear.
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


## F5 ends warmup, as mp_warmup_end does, on the world's next tick.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F5 and match_state != null:
		match_state.end_warmup_on_next_tick()


## The floor at the middle of each bomb site, A then B, from the callouts
## (env_cs_place): a callout's origin is its brush's middle, over the floor,
## so it is taken down onto the nav mesh. Empty where either is missing.
func _bomb_site_floors() -> PackedVector3Array:
	var places := SourceEntities.places(entities)
	var floors := PackedVector3Array()
	for place in ["BombsiteA", "BombsiteB"]:
		if not places.has(place):
			return PackedVector3Array()
		var origin: Vector3 = places[place][0]
		var area := nav_mesh.area_at(origin, 300.0, 24.0, 0)
		if area == null:
			area = nav_mesh.nearest_area(origin, 256.0, 0)
		if area == null:
			return PackedVector3Array()
		var on := origin if area.covers(origin) else area.centre
		floors.append(Vector3(on.x, area.floor_at(on), on.z))
	return floors


## A line in the top left, under the position readout, for something that
## is missing but leaves the map playable; line puts it lower down, so notes
## do not cover each other.
func _show_note(text: String, line: int = 0) -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.position = Vector2(12, 36 + 22 * line)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


## The buildings and horizon beyond the playable map. Source builds them as
## a separate small map at a sixteenth of the scale, around a sky_camera, and
## draws that around the player. Scaling it up by sixteen about the camera's
## position puts the same buildings in the same places, a long way off, with
## the haze doing the rest. Nothing in it is solid.
func _build_skybox() -> void:
	skybox = make_skybox(SKYBOX_DIR)
	if skybox == null:
		return
	add_child(skybox)
	print("--- skybox: %d meshes at %.0fx" % [skybox.stats.get("meshes", 0), skybox.scale_factor / MapImporter.SOURCE2_VIEWER_SCALE])


## The skybox's importer, set up and placed but not yet in the scene; null
## when it has not been extracted. Static so the checks build the one the
## game does.
static func make_skybox(skybox_dir: String) -> MapImporter:
	var map_file := MapImporter.find_map_file(skybox_dir)
	if map_file.is_empty():
		return null
	var camera := Vector3.ZERO
	var sky_scale := 16.0
	for entity in SourceEntities.parse(
		ProjectSettings.globalize_path(map_file.get_base_dir().path_join(ENTITIES_FILE))
	):
		if entity.get("classname", "") == "sky_camera":
			camera = SourceEntities.to_game(SourceEntities.vector(entity.get("origin", "")))
			sky_scale = float(entity.get("scale", "16"))
			break

	var sky_importer := MapImporter.new()
	sky_importer.name = "Skybox"
	sky_importer.source_path = map_file
	sky_importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE * sky_scale
	sky_importer.collision_source = MapImporter.CollisionSource.NONE
	sky_importer.layer_textures_dir = skybox_dir
	# Its terrain sits at its own ground level, which is above some of the
	# map's floors; the map must win wherever they overlap.
	sky_importer.behind_everything = true
	# Scenery, not a caster: the game's skybox never shadows the map.
	sky_importer.cast_shadows = false
	sky_importer.report = false
	# The sky camera's point, scaled up about the map's origin, lands on it.
	sky_importer.position = -camera * sky_scale
	return sky_importer


func _place_player(map_file: String) -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	(player as PlayerController).team = spawn_team
	add_child(player)
	world.add_player(player as PlayerSim)

	var spawns: Array = SourceEntities.player_spawns(entities)[spawn_team]
	if not spawns.is_empty():
		# Any of the spawns the game would fill first. They sit a little above
		# the floor, as they do in the game, and the player drops onto it.
		var first_choice := spawns.filter(func(candidate: Dictionary) -> bool:
			return candidate["priority"] == spawns[0]["priority"])
		var spawn: Dictionary = first_choice.pick_random()
		(player as PlayerController).place(spawn["position"], spawn["yaw"])
		return

	push_warning(
		"No spawn points: %s is not there. Run scripts/extract_assets.sh entities."
		% map_file.get_base_dir().path_join(ENTITIES_FILE)
	)
	var drop_position := spawn_position
	if use_bounds_centre_as_spawn and importer.stats.has("bounds"):
		var bounds: AABB = importer.stats["bounds"]
		# Above the top of the map, so you fall in rather than starting inside
		# a wall. Noclip is bound to V if you land somewhere useless.
		drop_position = Vector3(
			bounds.get_center().x,
			bounds.position.y + bounds.size.y + 64.0,
			bounds.get_center().z
		)
	player.global_position = drop_position


## A floor to stand on and a message saying why there is no map. Without a
## message of its own, it is the one for a map that has not been extracted
## yet, which is the normal state of a fresh clone.
func _build_fallback(message: String = "") -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1024.0, 32.0, 1024.0)
	collision.shape = shape
	collision.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh_instance.mesh = box
	mesh_instance.position = collision.position
	floor_body.add_child(mesh_instance)
	add_child(floor_body)

	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	world.add_player(player as PlayerSim)
	player.global_position = Vector3(0.0, 8.0, 0.0)

	if not message.is_empty():
		_show_message(message)
		return
	_show_message(
		"dust2 has not been extracted yet.\n\n"
		+ "Run this on a machine with CS2 installed:\n"
		+ "    scripts/extract_assets.sh map\n\n"
		+ "It writes into assets/, which is gitignored on purpose:\n"
		+ "Valve's geometry does not go in the repository.\n\n"
		+ "Then reopen this scene.\n\n"
		+ "To check what the extraction produced, run:\n"
		+ "    scripts/inspect_assets.sh"
	)


func _show_message(text: String) -> void:
	# Three places, because each one fails for someone: the label is easy to
	# miss if you spawn looking at the sky, the console scrolls away, and a
	# double-clicked terminal closes before it can be read.
	print(text)
	var writer := MapImporter.new()
	writer.write_report(text)
	writer.free()

	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.position = Vector2(48, 120)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	add_child(layer)
