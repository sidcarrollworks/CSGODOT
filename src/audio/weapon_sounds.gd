class_name WeaponSounds
extends Node3D

## What is heard of a weapon: the shot, the reload in its parts, the draw;
## and, for the shooter, of a hit: CS2's own feedback for where the round
## landed, whether armour took it and whether it killed. The player's
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
##
## A shot is heard from the game's events, not from inside the tick: the
## shooter's weapon_fire, sent by the simulation for every round (one for a
## shotgun's pellets), is noted as it is handed out at the tick's end, and
## played on the next frame drawn (watch()). What is heard is the gun the
## event names, so a shot sounds as what fired it even if the hand has
## changed since.
## A scope going in or out is heard the same way, from weapon_zoom: the
## gun's zoom-in sound for each level up, its zoom-out coming out, except a
## sniper's, which CS2 has left silent since 22 September 2026
## (reference/research/audio-gameplay.md 1.3). Everyone near hears it, so a
## bot's is heard too.
## A gun's volumes are set by ear; its sound events (.vsndevts) are not read
## yet (reference/research/audio.md). The hit feedback's are CS2's (FEEDBACK).

const SOUNDS_PAGE := "res://reference/weapons/sounds.md"
const TIMINGS := "res://reference/weapons/timings.csv"
## The folder every gun's sounds are in, under the sound bank.
const WEAPONS_DIR := "weapons"
const FIRE_DB := -6.0
const HANDLING_DB := -4.0

## What the shooter hears of a round landing on someone (hit()): CS2's
## attacker feedback events, as its game_sounds_player.vsndevts has them
## (GameTracking-CS2; reference/research/audio-gameplay.md 3), by event:
## Damage or Death, Body or HeadShot, with Armor where armour took the round.
## Each is its layers, each [files, volume, pitch, delay in seconds, curve]:
## the curve is the event's share of its volume by the distance from the
## shooter to whoever was hit, [units, share] points, straight between them
## and held past either end. A body hit is the mud thud, through kevlar the
## kevlar with a little of it; a headshot the fleshy one, through a helmet
## the dink; a kill the same, fuller. The helmeted kill's own file
## (headshot_armor_01) plays at volume 0 in CS2, so only its dink and flesh
## are here; no event plays bodyshot_kill_01 or kevlar1 to 5.
const MUD := ["physics/surfaces/mud_impact_bullet1", "physics/surfaces/mud_impact_bullet2", "physics/surfaces/mud_impact_bullet3", "physics/surfaces/mud_impact_bullet4"]
const MUD_FLESH := ["physics/surfaces/mud_impact_bullet1", "physics/surfaces/mud_impact_bullet3", "physics/surfaces/mud_impact_bullet4"]
const KEVLAR := ["player/kevlar_0"]
const HEADSHOT := ["player/headshot_noarmor_0"]
const DINK := ["player/headshot_armor_e1"]
const HEAD_FLESH := ["player/headshot_armor_flesh"]
const BODY_CURVE := [[21.4, 1.0], [1065.9, 0.2148]]
const KILL_BODY_CURVE := [[21.4, 1.0], [1065.9, 0.5772]]
const HEAD_CURVE := [[104.4, 1.0], [1100.0, 0.7684]]
const FEEDBACK := {
	&"DamageBody": [[MUD, 1.0, 1.3, 0.0, BODY_CURVE]],
	&"DamageBodyArmor": [[KEVLAR, 1.2, 1.3, 0.0, BODY_CURVE], [MUD_FLESH, 0.3, 1.3, 0.1, BODY_CURVE]],
	&"DamageHeadShot": [[HEADSHOT, 0.5, 1.0, 0.0, HEAD_CURVE]],
	&"DamageHeadShotArmor": [[DINK, 0.5, 1.0, 0.0, HEAD_CURVE]],
	&"DeathBody": [[MUD, 1.0, 1.0, 0.0, KILL_BODY_CURVE]],
	&"DeathBodyArmor": [[KEVLAR, 1.0, 1.0, 0.0, KILL_BODY_CURVE], [MUD_FLESH, 0.5, 1.3, 0.0, KILL_BODY_CURVE]],
	&"DeathHeadShot": [[HEADSHOT, 0.4, 1.0, 0.0, [[104.4, 1.0], [738.6, 0.8051]]]],
	&"DeathHeadShotArmor": [
		[HEAD_FLESH, 0.3, 1.0, 0.0, [[15.7, 1.0], [1100.0, 0.7639]]],
		[DINK, 0.6, 1.1, 0.0, [[104.4, 1.0], [1100.0, 0.7743]]],
	],
}
## The feedback's level in the mix, by ear: CS2's PlayerAttackerFeedback
## mixgroup, whose own level is not read yet.
const FEEDBACK_DB := -3.0
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37

## In the world, from this node's place, rather than flat in the ears.
@export var spatial: bool = false

## The gun taken up: {fire, draw: stems; reload: [[seconds, stems], ...]}.
var weapon_set: Dictionary = {}
var _fire: Node
var _handling: Node
## A player for each feedback layer, at the layer's pitch, by "event:layer";
## only the shooter's own (flat) sounds have them.
var _feedback := {}
var _reload_serial: int = 0
## Whose shots these are (watch()), and the game whose events say so.
var shooter: PlayerSim
var _game: GameSystems
## The guns fired since the last frame drawn, by weapon_fire.
var _fired := PackedStringArray()
## The zoom sounds to play on the next frame, by weapon_zoom, as stems.
var _zooms: Array[PackedStringArray] = []
## Every gun's set, by class, read once (sets()).
static var _sets := {}
## Every set's files read (all_stems()), once for every player: a gun is
## taken up on the tick (a bot's purchase), which must not read the disk.
static var _loaded_all := false


func _ready() -> void:
	_fire = _make_player(4)
	_handling = _make_player(2)
	if not spatial:
		for event: StringName in FEEDBACK:
			var layers: Array = FEEDBACK[event]
			for i in layers.size():
				# CS2 plays three of a body hit's at once at most.
				var player := _make_player(3) as AudioStreamPlayer
				player.pitch_scale = float(layers[i][2])
				_feedback["%s:%d" % [event, i]] = player
	if not _loaded_all:
		_loaded_all = true
		_load_all()


## Hears p_shooter's shots from the game they are in, whichever that is:
## a player can join a world, or another, after this is made.
func watch(p_shooter: PlayerSim) -> void:
	shooter = p_shooter
	_follow_game()


func _exit_tree() -> void:
	if _game != null:
		_game.events.unlisten(&"weapon_fire", _on_weapon_fire)
		_game.events.unlisten(&"weapon_zoom", _on_weapon_zoom)
		_game = null


func _process(_delta: float) -> void:
	_follow_game()
	for item_class in _fired:
		shot(item_class)
	_fired.clear()
	for stems in _zooms:
		_play(_handling, stems, HANDLING_DB)
	_zooms.clear()


## Listens to the shooter's game's weapon_fire, the one it is in now.
func _follow_game() -> void:
	var game: GameSystems = null
	if is_instance_valid(shooter) and is_instance_valid(shooter.world):
		game = shooter.world.game
	if game == _game:
		return
	if _game != null:
		_game.events.unlisten(&"weapon_fire", _on_weapon_fire)
		_game.events.unlisten(&"weapon_zoom", _on_weapon_zoom)
	_game = game
	if _game != null:
		_game.events.listen(&"weapon_fire", _on_weapon_fire)
		_game.events.listen(&"weapon_zoom", _on_weapon_zoom)


## Handed out at the tick's end: noted, and heard on the next frame.
func _on_weapon_fire(event: GameEvent) -> void:
	var userid: int = event.fields["userid"]
	if is_instance_valid(shooter) and userid == shooter.userid and userid != GameEvents.NOBODY:
		_fired.append(String(event.fields["weapon"]))


## Handed out at the tick's end, when the scope has moved: what it sounds
## like, by the gun in hand and where its scope is now, noted for the next
## frame.
func _on_weapon_zoom(event: GameEvent) -> void:
	var userid: int = event.fields["userid"]
	if not is_instance_valid(shooter) or userid != shooter.userid or userid == GameEvents.NOBODY:
		return
	var weapon := shooter.weapon
	if weapon == null:
		return
	var stems := zoom_stems(weapon.data, weapon.zoom_level > 0)
	if not stems.is_empty():
		_zooms.append(stems)


## A gun's zoom sound: going in (to either level) or coming out; nothing
## coming out of a sniper's scope, which hides the arms
## (WeaponData.hides_view_model_when_zoomed): CS2's four snipers, silent
## unscoping since 22 September 2026.
static func zoom_stems(data: WeaponData, going_in: bool) -> PackedStringArray:
	if not going_in and data.hides_view_model_when_zoomed:
		return PackedStringArray()
	var gun: Dictionary = sets().get(data.item_class, {})
	return (gun.get("zoom_in" if going_in else "zoom_out", PackedStringArray()) as PackedStringArray).duplicate()


## The zoom sounds noted and not heard yet, as a copy.
func pending_zooms() -> Array[PackedStringArray]:
	return _zooms.duplicate()


## The shots noted and not heard yet, as a copy.
func pending_shots() -> PackedStringArray:
	return _fired.duplicate()


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


## A round of that gun fired, heard now.
func shot(item_class: String) -> void:
	var fired: Dictionary = sets().get(item_class, {})
	_play(_fire, fired.get("fire", PackedStringArray()), FIRE_DB)


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


## What the shooter hears of a round landing on someone: CS2's feedback
## for where it landed, whether armour took it (the round's own, as the
## target judged it) and whether it killed, softer the further off they are.
func hit(zone: StringName, target: HitTarget, killed: bool) -> void:
	if _feedback.is_empty() or target == null:
		return
	var event := feedback_for(zone, target.last_hit_armored, killed)
	var layers: Array = FEEDBACK[event]
	var distance := global_position.distance_to(target.global_position) if is_inside_tree() and target.is_inside_tree() else 0.0
	for i in layers.size():
		var layer: Array = layers[i]
		var player: Node = _feedback["%s:%d" % [event, i]]
		var stems := PackedStringArray(layer[0])
		var volume_db := FEEDBACK_DB + linear_to_db(float(layer[1]) * curve_share(layer[4], distance))
		var delay := float(layer[3])
		if delay <= 0.0:
			_play(player, stems, volume_db)
		else:
			get_tree().create_timer(delay).timeout.connect(func() -> void: _play(player, stems, volume_db))


## CS2's feedback event for a hit: DamageBody, DeathHeadShotArmor and so on.
static func feedback_for(zone: StringName, armored: bool, killed: bool) -> StringName:
	return StringName(("Death" if killed else "Damage") + ("HeadShot" if zone == &"head" else "Body") + ("Armor" if armored else ""))


## A distance curve's share at a distance: straight between its points,
## held past either end.
static func curve_share(curve: Array, distance: float) -> float:
	if curve.is_empty():
		return 1.0
	if distance <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		if distance <= float(curve[i][0]):
			var from: Array = curve[i - 1]
			var to: Array = curve[i]
			return lerpf(float(from[1]), float(to[1]), (distance - float(from[0])) / (float(to[0]) - float(from[0])))
	return float(curve[-1][1])


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
		var zooms := _zooms_of(_names(cells[7]))
		out[item_class] = {
			"fire": _in(folder, _shots(item_class, _names(cells[2]))),
			"draw": _in(folder, _names(cells[4])),
			"zoom_in": _in(folder, zooms[0]),
			"zoom_out": _in(folder, zooms[1]),
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
## reload parts, and the hit feedback.
static func all_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for event: StringName in FEEDBACK:
		for layer: Array in FEEDBACK[event]:
			stems.append_array(PackedStringArray(layer[0]))
	for gun: Dictionary in sets().values():
		stems.append_array(gun["fire"])
		stems.append_array(gun["draw"])
		stems.append_array(gun["zoom_in"])
		stems.append_array(gun["zoom_out"])
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
		SoundBank.randomizer_of(gun["zoom_in"])
		SoundBank.randomizer_of(gun["zoom_out"])
		for part: Array in gun["reload"]:
			SoundBank.randomizer_of(part[1])
	for event: StringName in FEEDBACK:
		for layer: Array in FEEDBACK[event]:
			SoundBank.randomizer_of(PackedStringArray(layer[0]))


## The file names in a cell: "glock_01, glock_02", or none for "-".
static func _names(cell: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in cell.split(","):
		var trimmed := name.strip_edges()
		if not trimmed.is_empty() and trimmed != "-":
			out.append(trimmed)
	return out


## A gun's zoom files, as [in, out]: the ones named zoom_in (the AUG's,
## the G3SG1's), or else the one named plain zoom (the AWP's, which CS2's
## Weapon_AWP.Zoom plays going in); and the ones named zoom_out.
static func _zooms_of(names: PackedStringArray) -> Array[PackedStringArray]:
	var going_in := PackedStringArray()
	var coming_out := PackedStringArray()
	for file_name in names:
		if file_name.contains("zoom_in"):
			going_in.append(file_name)
		elif file_name.contains("zoom_out"):
			coming_out.append(file_name)
	if going_in.is_empty() and names.has("zoom"):
		going_in.append("zoom")
	return [going_in, coming_out]


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
