class_name PlayScene
extends Node3D

## Plays one extracted CS2 map in a game mode: the map loaded by name
## (MapLoader), and competitive on it (Competitive). Until there are menus
## (roadmap item 26), the map is chosen here:
##
##   - map_name, in the inspector: maps/play/play.tscn plays whichever it
##     names, and maps/de_dust2/de_dust2.tscn is this scene set to de_dust2;
##   - --map on the command line, which wins over map_name:
##       godot --path . maps/play/play.tscn -- --map de_mirage
##
## Any map scripts/extract_assets.sh has taken (map <name>) plays, as far as
## it has been extracted; what is missing is said in the top left.

## The map to play, as CS2 names it.
@export var map_name: String = "de_dust2"

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


func _ready() -> void:
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
	mode.name = "Competitive"
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
