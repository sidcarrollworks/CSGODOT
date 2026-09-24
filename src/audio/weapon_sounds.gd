class_name WeaponSounds
extends Node3D

## What is heard of a weapon: the shot, the reload in its parts, the draw;
## and, for the shooter, of a hit: kevlar, a headshot, a kill. The player's
## own plays flat, not in the world, the way the game plays your own gun;
## a bot's plays from where the bot stands (spatial). It is a Node3D so that
## its 3D players go where it is: under a plain Node they would sit at the
## world's origin, and a bot's shots would sound from there.
##
## Every gun's sounds are the game's, from its own files as the extraction
## tables them, read once (sets()): which files it fires, draws and reloads
## with (reference/weapons/sounds.md), and when in its reload each part
## sounds, the reload clip's own sound events (reference/weapons/timings.csv).
## A draw is heard only by whoever draws, as CS2's draws are localplayeronly
## (reference/research/audio-gameplay.md 1.3): a bot's draw is not heard.
## Volumes are set by ear; the sound events that carry the game's
## (.vsndevts) are not read yet (reference/research/audio.md).

const SOUNDS_PAGE := "res://reference/weapons/sounds.md"
const TIMINGS := "res://reference/weapons/timings.csv"
## The folder every gun's sounds are in, under the sound bank.
const WEAPONS_DIR := "weapons"
## What the shooter hears of a hit (hit()): a kill, a headshot through a
## helmet and without one, kevlar.
const HIT_SETS := ["player/bodyshot_kill_01", "player/headshot_armor_01", "player/headshot_noarmor_0", "player/kevlar"]
const FIRE_DB := -6.0
const HANDLING_DB := -4.0
const HIT_DB := -3.0
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37

## In the world, from this node's place, rather than flat in the ears.
@export var spatial: bool = false

## The gun taken up: {fire, draw: stems; reload: [[seconds, stems], ...]}.
var weapon_set: Dictionary = {}
var _fire: Node
var _handling: Node
var _hits: Node
var _reload_serial: int = 0
## Every gun's set, by class, read once (sets()).
static var _sets := {}
## Every set's files read (all_stems()), once for every player: a gun is
## taken up on the tick (a bot's purchase), which must not read the disk.
static var _loaded_all := false


func _ready() -> void:
	_fire = _make_player(4)
	_handling = _make_player(2)
	_hits = _make_player(2)
	if not _loaded_all:
		_loaded_all = true
		_load_all()


func _make_player(polyphony: int) -> Node:
	if spatial:
		var placed := AudioStreamPlayer3D.new()
		placed.max_polyphony = polyphony
		placed.unit_size = 20.0 * METRE
		placed.max_distance = 300.0 * METRE
		placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(placed)
		return placed
	var player := AudioStreamPlayer.new()
	player.max_polyphony = polyphony
	add_child(player)
	return player


## Takes up a weapon's set, and plays its draw for whoever draws it; a
## bot's (spatial) is not heard.
func equip(data: WeaponData) -> void:
	weapon_set = set_for(data.item_class)
	_reload_serial += 1
	if not spatial:
		_play(_handling, weapon_set.get("draw", PackedStringArray()), HANDLING_DB)


func shot() -> void:
	_play(_fire, weapon_set.get("fire", PackedStringArray()), FIRE_DB)


## The reload's parts, timed from now. A new reload, or a new weapon, drops
## whatever was still to come of the last.
func reload() -> void:
	_reload_serial += 1
	var serial := _reload_serial
	for part: Array in weapon_set.get("reload", []):
		var at: float = part[0]
		var stems: PackedStringArray = part[1]
		get_tree().create_timer(at).timeout.connect(func() -> void:
			if serial == _reload_serial:
				_play(_handling, stems, HANDLING_DB))


## What the shooter hears of a round landing on someone: the target's
## armour, a headshot through or without a helmet, a kill.
func hit(zone: StringName, target: HitTarget, killed: bool) -> void:
	if killed and zone != &"head":
		_play(_hits, PackedStringArray([HIT_SETS[0]]), HIT_DB)
	elif zone == &"head":
		_play(_hits, PackedStringArray([HIT_SETS[1] if target.is_armored(zone) else HIT_SETS[2]]), HIT_DB)
	elif target.is_armored(zone):
		_play(_hits, PackedStringArray([HIT_SETS[3]]), HIT_DB)


func _play(player: Node, stems: PackedStringArray, volume_db: float) -> void:
	if stems.is_empty() or not SoundBank.available():
		return
	var stream := SoundBank.randomizer_of(stems)
	if stream == null:
		return
	# Swapping the stream stops what is playing, so only when it is another
	# set: shots of one set overlap.
	if player.get("stream") != stream:
		player.set("stream", stream)
	player.set("volume_db", volume_db)
	player.call("play")


## A gun's set, by class, as a copy: empty for what has none.
static func set_for(item_class: String) -> Dictionary:
	return (sets().get(item_class, {}) as Dictionary).duplicate(true)


## Every gun's set, by class, from the game's own tables, read once:
## {fire: stems, draw: stems, reload: [[seconds, stems], ...]}, each stem a
## file under the sound bank without its extension.
static func sets() -> Dictionary:
	if _sets.is_empty():
		_sets = read_sets(FileAccess.get_file_as_string(SOUNDS_PAGE), FileAccess.get_file_as_string(TIMINGS))
	return _sets


## The sets from sounds.md's table and timings.csv's rows, as they are
## written. A gun's shot is its numbered variants (ak47_01 to _04; the old
## ak47-1 left out where there are numbered ones), silenced where the gun
## starts silenced (the M4A1-S, the USP-S). Each of its reload clip's sound
## events is the files of the gun's handling whose names hold the event's
## part (Weapon_AK47.BoltPull: ak47_boltpull and its variants); an event
## with no such file is left out.
static func read_sets(page: String, timings: String) -> Dictionary:
	var out := {}
	for line in page.split("\n"):
		var cells := line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
		if cells.size() < 10 or not cells[0].strip_edges().begins_with("`weapon_"):
			continue
		var item_class := cells[0].strip_edges().trim_prefix("`").trim_suffix("`")
		var folder := WEAPONS_DIR.path_join(cells[1].strip_edges().trim_prefix("`").trim_suffix("`"))
		var handling := PackedStringArray()
		for column in [5, 6, 9]:
			handling.append_array(_names(cells[column]))
		out[item_class] = {
			"fire": _in(folder, _shots(item_class, _names(cells[2]))),
			"draw": _in(folder, _names(cells[4])),
			"reload": [],
			"_handling": handling,
			"_folder": folder,
		}
	var seen := {}
	for row in timings.split("\n"):
		var fields := row.strip_edges().split(",")
		if fields.size() < 7 or fields[1] != "reload" or fields[3] != "Sound" or not out.has(fields[0]):
			continue
		var key := "%s|%s|%s" % [fields[0], fields[4], fields[5]]
		if seen.has(key):
			continue
		seen[key] = true
		var gun: Dictionary = out[fields[0]]
		var event := fields[4]
		var part := event.substr(event.find(".") + 1).to_lower().trim_suffix("_q")
		# The files named for the part as a word of their own (elites_clipin_07,
		# not elite_leftclipin) where there are any; else any that hold it.
		var files := PackedStringArray()
		var worded := PackedStringArray()
		for file_name in gun["_handling"]:
			var lower: String = file_name.to_lower()
			if not part.is_empty() and lower.contains(part):
				files.append(file_name)
				if lower.contains("_" + part):
					worded.append(file_name)
		if not worded.is_empty():
			files = worded
		if not files.is_empty():
			(gun["reload"] as Array).append([float(fields[5]), _in(gun["_folder"], files)])
	for gun: Dictionary in out.values():
		(gun["reload"] as Array).sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		gun.erase("_handling")
		gun.erase("_folder")
	return out


## Every sound a weapon plays here, as stems: each gun's shot, draw and
## reload parts, and the hits.
static func all_stems() -> PackedStringArray:
	var stems := PackedStringArray(HIT_SETS)
	for gun: Dictionary in sets().values():
		stems.append_array(gun["fire"])
		stems.append_array(gun["draw"])
		for part: Array in gun["reload"]:
			stems.append_array(part[1])
	return stems


## Reads every set's files now, and makes each set's stream, so nothing is
## read or built when a gun is taken up or fired.
static func _load_all() -> void:
	if not SoundBank.available():
		return
	SoundBank.load_sets(all_stems())
	for gun: Dictionary in sets().values():
		SoundBank.randomizer_of(gun["fire"])
		SoundBank.randomizer_of(gun["draw"])
		for part: Array in gun["reload"]:
			SoundBank.randomizer_of(part[1])
	for stem: String in HIT_SETS:
		SoundBank.randomizer_of(PackedStringArray([stem]))


## The file names in a cell: "glock_01, glock_02", or none for "-".
static func _names(cell: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in cell.split(","):
		var trimmed := name.strip_edges()
		if not trimmed.is_empty() and trimmed != "-":
			out.append(trimmed)
	return out


## Which of a gun's fire files are its shot: silenced for a gun that starts
## silenced, and the numbered ones where there are any.
static func _shots(item_class: String, names: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for file_name in names:
		if item_class == "weapon_m4a1_silencer" and not file_name.begins_with("m4a1_silencer"):
			continue
		if item_class == "weapon_usp_silencer" and file_name.contains("unsilenced"):
			continue
		kept.append(file_name)
	var numbered := PackedStringArray()
	var ends_numbered := RegEx.create_from_string("_\\d+$")
	for file_name in kept:
		if ends_numbered.search(file_name) != null:
			numbered.append(file_name)
	return numbered if not numbered.is_empty() else kept


static func _in(folder: String, names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for file_name in names:
		out.append(folder.path_join(file_name))
	return out
