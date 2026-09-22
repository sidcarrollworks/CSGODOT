class_name WeaponSounds
extends Node

## What is heard of a weapon: the shot, the reload in its parts, the draw;
## and, for the shooter, of a hit: kevlar, a headshot, a kill. The player's
## own plays flat, not in the world, the way the game plays your own gun;
## a bot's plays from where the bot stands (spatial).
##
## The sounds are the game's, by the weapon's model name (weapon_rif_ak47
## has the ak47 set). The reload's parts are spaced by ear to the game's
## clip: magazine out, magazine in, bolt. Volumes are set by ear too; the
## sound event definitions that carry the game's are not fetched.

## Sets by weapon, as stems under the sound bank. "fire" and the reload
## parts may be sets of variants; "bolt" is a list of stems in order, with
## the seconds into the reload at which each part sounds.
const SETS := {
	"ak47": {
		"fire": "weapons/ak47/ak47_0",
		"draw": "weapons/ak47/ak47_draw",
		"reload": [[0.45, "weapons/ak47/ak47_clipout_01"], [1.35, "weapons/ak47/ak47_addammo_02"], [2.0, "weapons/ak47/ak47_boltpull_0"]],
	},
	"m4a1_silencer": {
		"fire": "weapons/m4a1/m4a1_silencer_01",
		"draw": "weapons/m4a1/m4a1_draw",
		"reload": [[0.55, "weapons/m4a1/m4a1_clipout"], [1.6, "weapons/m4a1/m4a1_clipin"], [2.25, "weapons/m4a1/m4a1_silencer_boltback"], [2.6, "weapons/m4a1/m4a1_silencer_boltforward"]],
	},
}
const FIRE_DB := -6.0
const HANDLING_DB := -4.0
const HIT_DB := -3.0
## Godot's 3D audio is set out in metres; the map is in inches.
const METRE := 39.37

## In the world, from this node's place, rather than flat in the ears.
@export var spatial: bool = false

var weapon_set: Dictionary = {}
var _fire: Node
var _handling: Node
var _hits: Node
var _reload_serial: int = 0


func _ready() -> void:
	_fire = _make_player(4)
	_handling = _make_player(2)
	_hits = _make_player(2)


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


## Takes up a weapon's set, by its model, and plays its draw.
func equip(data: WeaponData) -> void:
	weapon_set = SETS.get(set_name_for(data.model_path), {})
	_reload_serial += 1
	_play(_handling, weapon_set.get("draw", ""), HANDLING_DB)


## The set's name from a model path: weapon_rif_ak47.gltf is "ak47".
static func set_name_for(model_path: String) -> String:
	return model_path.get_file().get_basename().trim_prefix("weapon_rif_").trim_prefix("weapon_")


func shot() -> void:
	_play(_fire, weapon_set.get("fire", ""), FIRE_DB)


## The reload's parts, timed from now. A new reload, or a new weapon, drops
## whatever was still to come of the last.
func reload() -> void:
	_reload_serial += 1
	var serial := _reload_serial
	for part: Array in weapon_set.get("reload", []):
		var at: float = part[0]
		var stem: String = part[1]
		get_tree().create_timer(at).timeout.connect(func() -> void:
			if serial == _reload_serial:
				_play(_handling, stem, HANDLING_DB))


## What the shooter hears of a round landing on someone: the target's
## armour, a headshot through or without a helmet, a kill.
func hit(zone: StringName, target: HitTarget, killed: bool) -> void:
	if killed and zone != &"head":
		_play(_hits, "player/bodyshot_kill_01", HIT_DB)
	elif zone == &"head":
		_play(_hits, "player/headshot_armor_01" if target.armor > 0.0 else "player/headshot_noarmor_0", HIT_DB)
	elif target.armor > 0.0 and zone != &"leg":
		_play(_hits, "player/kevlar", HIT_DB)


func _play(player: Node, stem: String, volume_db: float) -> void:
	if stem.is_empty() or not SoundBank.available():
		return
	var stream := SoundBank.randomizer(stem)
	if stream == null:
		return
	# Swapping the stream stops what is playing, so only when it is another
	# set: shots of one set overlap.
	if player.get("stream") != stream:
		player.set("stream", stream)
	player.set("volume_db", volume_db)
	player.call("play")
