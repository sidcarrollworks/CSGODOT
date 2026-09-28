class_name PlayScene
extends Node3D

## Plays one extracted CS2 map in a game mode: the map loaded by name
## (MapLoader), and a mode on it (Competitive, or Practice, which is
## Competitive with no bots and a warmup that does not end). Until there are
## menus (roadmap item 26), the map is chosen here:
##
##   - map_name, in the inspector: maps/play/play.tscn plays whichever it
##     names, and maps/de_dust2/de_dust2.tscn is this scene set to de_dust2;
##   - --map on the command line, which wins over map_name:
##       godot --path . maps/play/play.tscn -- --map de_mirage
##
## and the mode:
##
##   - game_mode, in the inspector: Ask (the default) shows a picker
##     (ModePicker) before the map loads when this is the scene being played
##     and there is a screen; otherwise it plays Competitive, so the
##     profilers and the checks that add the scene never wait on it;
##   - --mode competitive or --mode practice, which wins over game_mode:
##       godot --path . maps/de_dust2/de_dust2.tscn -- --mode practice
##
## Any map scripts/extract_assets.sh has taken (map <name>) plays, as far as
## it has been extracted; what is missing is said in the top left.

## The map to play, as CS2 names it.
@export var map_name: String = "de_dust2"
## The game mode: Competitive (you and bots, 5 a side), Practice (no bots,
## a warmup that lasts until F5), or Ask, a picker at start.
@export_enum("Ask", "Competitive", "Practice") var game_mode: String = "Ask"

@export_group("Competitive")
## Which side you play.
@export_enum("T", "CT") var spawn_team: String = "T"
## Players on each side, you among them; bots fill every other place.
@export var team_size: int = 5
## How long warmup lasts before the first round; F5 ends it early.
@export var warmup_seconds: float = 120.0
## Whether the bots walk to the bomb sites and back (over the nav mesh), or
## round their own spawn points.
@export var bots_walk_to_sites: bool = true

@export_group("Without spawn points")
## Where to drop the player in if the entity lump was not extracted.
@export var spawn_position := Vector3.ZERO
## Start above the centre of the map's bounding box rather than at
## spawn_position. Noclip (V) from there.
@export var use_bounds_centre_as_spawn: bool = true

var world: GameWorld
var map: MapLoader
var mode: Competitive
## The picker while it is open (game_mode Ask); null once a mode is chosen.
var picker: ModePicker


func _ready() -> void:
	var mode_name := mode_from_args(OS.get_cmdline_user_args(), mode_from_args(OS.get_cmdline_args(), game_mode))
	if mode_name == "Ask":
		if _can_ask():
			# Chosen before the map loads, which takes seconds on dust2 and
			# holds the frame while it does.
			picker = ModePicker.new()
			picker.name = "ModePicker"
			add_child(picker)
			mode_name = await picker.chosen
			picker = null
		else:
			mode_name = "Competitive"
	_play(mode_name)


## Whether to show the picker: only when this is the scene being played,
## on a screen. Added under something else (the profilers, the checks) or
## run headless, Ask plays Competitive.
func _can_ask() -> bool:
	return get_tree().current_scene == self and DisplayServer.get_name() != "headless"


## The world, the map, and the mode on it.
func _play(mode_name: String) -> void:
	world = GameWorld.new()
	world.name = "World"
	add_child(world)

	map = MapLoader.new()
	map.name = "Map"
	map.map_name = map_from_args(OS.get_cmdline_user_args(), map_from_args(OS.get_cmdline_args(), map_name))
	map.spawn_position = spawn_position
	map.use_bounds_centre_as_spawn = use_bounds_centre_as_spawn
	add_child(map)

	mode = Competitive.new()
	mode.name = mode_name
	if mode_name == "Practice":
		mode.practice()
	mode.spawn_team = spawn_team
	mode.team_size = team_size
	mode.warmup_seconds = warmup_seconds
	mode.bots_walk_to_sites = bots_walk_to_sites
	add_child(mode)
	mode.start(world, map.contents)

	var notes := PackedStringArray(map.contents.missing)
	notes.append_array(mode.notes)
	for i in notes.size():
		_show_note(notes[i], i)


## The map named by --map name or --map=name among a command line's
## arguments; otherwise the one given.
static func map_from_args(args: PackedStringArray, otherwise: String) -> String:
	for i in args.size():
		if args[i] == "--map" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--map="):
			return args[i].trim_prefix("--map=")
	return otherwise


## The mode named by --mode name or --mode=name among a command line's
## arguments (competitive or practice, in any case); otherwise the one given.
## A name that is not a mode leaves the one given, and says so.
static func mode_from_args(args: PackedStringArray, otherwise: String) -> String:
	for i in args.size():
		var named := ""
		if args[i] == "--mode" and i + 1 < args.size():
			named = args[i + 1]
		elif args[i].begins_with("--mode="):
			named = args[i].trim_prefix("--mode=")
		else:
			continue
		for known in ModePicker.MODES:
			if named.to_lower() == known.to_lower():
				return known
		push_warning("--mode %s is not a mode (%s); playing %s" % [named, ", ".join(ModePicker.MODES).to_lower(), otherwise])
	return otherwise


## A line in the top left, under the position readout, for something that
## is missing but leaves the map playable; line puts it lower down, so notes
## do not cover each other.
func _show_note(text: String, line: int) -> void:
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
