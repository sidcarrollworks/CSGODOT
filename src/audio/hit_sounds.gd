class_name HitSounds
extends Node3D

## What is heard of a hit by everyone but the shooter, and of a death, as
## CS2's server names them (reference/research/audio-gameplay.md 3): the
## one hit hears their own (Player.Damage*.Victim, flat in the ears), those
## near hear it from where it landed (.Onlooker, to about 1100 units), and a
## death is the groan everyone near hears, the one who died too
## (Player.Death, to 1400). The shooter's own feedback is WeaponSounds' (the
## client's, CS2's .AttackerFeedback), so the shooter hears no onlooker
## version on top (inferred: the server names the victim's and the
## onlookers', the attacker's client its own).
##
## Every event is CS2's own, as its game_sounds_player.vsndevts has it
## (GameTracking-CS2): files, volume, pitch, delay, how far up the body it
## sounds from, and its distance curve. It reads the game's events,
## player_hurt and player_death, as they are handed out, and plays what they
## say on the next frame drawn: nothing is heard from inside the tick. A
## hit by fire plays none of these (CS2 has Player.BurnDamage for it, not
## built), and a knife's is a body hit wherever it lands.

const MUD := ["physics/surfaces/mud_impact_bullet1", "physics/surfaces/mud_impact_bullet2", "physics/surfaces/mud_impact_bullet3", "physics/surfaces/mud_impact_bullet4"]
const BODY := ["player/player_damagebody_04", "player/player_damagebody_05", "player/player_damagebody_06", "player/player_damagebody_07", "player/player_damagebody_08"]
const BODY_HEAD := ["player/player_damagebody_05", "player/player_damagebody_06", "player/player_damagebody_07"]
const KEVLAR := ["player/kevlar_0"]
const HEADSHOT := ["player/headshot_noarmor_0"]
const HEADSHOT_KILL := ["player/headshot_noarmor_02", "player/headshot_noarmor_04", "player/headshot_noarmor_05"]
const DINK := ["player/headshot_armor_e1"]
const HEAD_FLESH := ["player/headshot_armor_flesh"]
const GROAN := ["player/death1", "player/death2", "player/death3", "player/death4", "player/death5", "player/death6"]
## The distance curves, [units, share] points (WeaponSounds.curve_share).
const FLAT := [[0.0, 1.0]]
const BODY_NEAR := [[0.0, 1.0], [35.31, 1.0], [1100.0, 0.0]]
const HEAD_NEAR := [[22.0, 1.0], [298.29, 0.4292], [1070.0, 0.0]]
const KILL_NEAR := [[51.97, 1.0], [400.49, 0.4485], [1070.0, 0.0]]
const KILL_FLESH := [[45.99, 1.0], [187.01, 0.3056], [1073.0, 0.0]]
const DINK_NEAR := [[22.0, 1.0], [298.29, 0.4292], [1200.0, 0.0]]
## Each event's layers for the one hit and for those near, each [files,
## volume, pitch, delay in seconds, curve, units up from the feet], by
## WeaponSounds.feedback_for's names.
const EVENTS := {
	&"DamageBody": {
		"victim": [[BODY, 1.5, 1.0, 0.05, FLAT, 0.0], [MUD, 1.0, 1.3, 0.05, FLAT, 0.0]],
		"onlooker": [[MUD, 1.0, 1.3, 0.0, BODY_NEAR, 0.0]],
	},
	&"DamageBodyArmor": {
		"victim": [[KEVLAR, 1.5, 1.0, 0.05, FLAT, 0.0]],
		"onlooker": [[KEVLAR, 0.7, 1.3, 0.05, BODY_NEAR, 60.0], [MUD, 0.3, 1.1, 0.05, BODY_NEAR, 60.0]],
	},
	&"DamageHeadShot": {
		"victim": [[HEADSHOT, 0.49, 1.0, 0.0, FLAT, 60.0]],
		"onlooker": [[HEADSHOT, 0.5, 1.0, 0.0, HEAD_NEAR, 60.0]],
	},
	&"DamageHeadShotArmor": {
		"victim": [[DINK, 0.75, 1.0, 0.0, FLAT, 60.0]],
		"onlooker": [[DINK, 0.5, 1.0, 0.0, HEAD_NEAR, 60.0]],
	},
	&"DeathBody": {
		"victim": [[BODY, 2.0, 0.8, 0.0, FLAT, 60.0], [MUD, 2.0, 1.3, 0.1, KILL_FLESH, 0.0]],
		"onlooker": [[BODY, 2.0, 0.8, 0.0, KILL_NEAR, 60.0], [MUD, 2.0, 1.3, 0.1, KILL_FLESH, 0.0]],
	},
	&"DeathBodyArmor": {
		"victim": [[BODY, 2.0, 0.8, 0.0, FLAT, 60.0], [MUD, 2.0, 1.3, 0.1, KILL_FLESH, 0.0]],
		"onlooker": [[BODY, 2.0, 0.8, 0.0, KILL_NEAR, 60.0], [MUD, 2.0, 1.3, 0.1, KILL_FLESH, 0.0]],
	},
	&"DeathHeadShot": {
		"victim": [[HEADSHOT_KILL, 0.55, 1.0, 0.0, FLAT, 60.0]],
		"onlooker": [[HEADSHOT, 0.5, 1.0, 0.0, HEAD_NEAR, 60.0]],
	},
	&"DeathHeadShotArmor": {
		"victim": [[BODY_HEAD, 0.7, 1.0, 0.0, FLAT, 60.0], [HEAD_FLESH, 0.2, 1.0, 0.0, FLAT, 60.0], [DINK, 0.7, 1.0, 0.0, FLAT, 60.0]],
		"onlooker": [[BODY_HEAD, 0.5, 1.0, 0.0, HEAD_NEAR, 60.0], [HEAD_FLESH, 0.2, 1.0, 0.0, DINK_NEAR, 60.0], [DINK, 0.7, 1.0, 0.0, DINK_NEAR, 60.0]],
	},
}
## Player.Death: the groan, heard by everyone near, from the body.
const DEATH := [[GROAN, 0.5, 1.0, 0.0, [[0.0, 1.0], [113.91, 0.5931], [1400.0, 0.0]], 60.0]]
## The level of these in the mix, by ear, as the shooter's feedback's
## (WeaponSounds.FEEDBACK_DB): CS2's PlayerVictim and PlayerDamage
## mixgroups' own levels are not read yet.
const MIX_DB := -3.0
## The weapons whose damage plays none of these: fire.
const SILENT_WEAPONS := ["weapon_molotov", "weapon_incgrenade", "inferno"]
## How many hits and deaths can sound at once, those near.
const VOICES := 12

## Whose ears: the player this machine plays as.
var listener_id: int = GameEvents.NOBODY
var game: GameSystems
## What to play on the next frame: [layers, where (Vector3, or null for flat)].
var _pending: Array = []
var _flat: Array[AudioStreamPlayer] = []
var _placed: Array[AudioStreamPlayer3D] = []
var _next_flat := 0
var _next_placed := 0


## Listens to a game's hits and deaths, for listener's ears.
func watch(p_game: GameSystems, listener: int) -> void:
	game = p_game
	listener_id = listener
	game.events.listen(&"player_hurt", _on_hurt)
	game.events.listen(&"player_death", _on_death)


func _ready() -> void:
	for i in 4:
		var flat := AudioStreamPlayer.new()
		add_child(flat)
		_flat.append(flat)
	for i in VOICES:
		var placed := AudioStreamPlayer3D.new()
		# The event's own curve sets the level (_play); the player only pans.
		placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		add_child(placed)
		_placed.append(placed)
	SoundBank.load_sets(all_stems())
	for stems in _layer_stems():
		SoundBank.randomizer_of(stems)


func _exit_tree() -> void:
	if game != null:
		game.events.unlisten(&"player_hurt", _on_hurt)
		game.events.unlisten(&"player_death", _on_death)


## What a hit sounds like to listener: the victim's layers flat when they
## are the one hit, the onlookers' from the body otherwise, nothing for the
## shooter (their own feedback is WeaponSounds') or for fire. hurt is
## player_hurt's fields.
static func for_hit(hurt: Dictionary, listener: int) -> Dictionary:
	var weapon := String(hurt.get("weapon", ""))
	if weapon in SILENT_WEAPONS:
		return {}
	var victim: int = hurt.get("userid", GameEvents.NOBODY)
	var attacker: int = hurt.get("attacker", GameEvents.NOBODY)
	if listener == attacker and listener != victim:
		return {}
	var head := int(hurt.get("hitgroup", 0)) == DamageInfo.HITGROUP_HEAD and not weapon.begins_with("weapon_knife")
	var event := WeaponSounds.feedback_for(&"head" if head else &"chest", int(hurt.get("dmg_armor", 0)) > 0, int(hurt.get("health", 1)) <= 0)
	var who := "victim" if listener == victim else "onlooker"
	return {"layers": EVENTS[event][who], "flat": who == "victim"}


func _on_hurt(event: GameEvent) -> void:
	var sound := for_hit(event.fields, listener_id)
	if sound.is_empty():
		return
	if sound["flat"]:
		_pending.append([sound["layers"], null])
		return
	var where: Variant = _where(event.fields["userid"])
	if where != null:
		_pending.append([sound["layers"], where])


func _on_death(event: GameEvent) -> void:
	var where: Variant = _where(event.fields["userid"])
	if where != null:
		_pending.append([DEATH, where])


## Where a player's hit is heard from: their feet, as the events' offsets
## are from the feet.
func _where(userid: int) -> Variant:
	var node := game.roster.player(userid) if game != null else null
	return node.global_position if node != null else null


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var ears := _ears()
	for sound: Array in _pending:
		for layer: Array in sound[0]:
			var delay := float(layer[3])
			if delay <= 0.0:
				_play(layer, sound[1], ears)
			else:
				get_tree().create_timer(delay).timeout.connect(_play.bind(layer, sound[1], ears))
	_pending.clear()


## Where the listener hears from: the camera drawing the frame.
func _ears() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.ZERO


func _play(layer: Array, where: Variant, ears: Vector3) -> void:
	if not SoundBank.available():
		return
	var stream := SoundBank.randomizer_of(PackedStringArray(layer[0]))
	if stream == null:
		return
	var player: Node
	var share := 1.0
	if where == null:
		player = _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
	else:
		var at: Vector3 = (where as Vector3) + Vector3.UP * float(layer[5])
		share = WeaponSounds.curve_share(layer[4], at.distance_to(ears))
		if share <= 0.0:
			return
		var placed := _placed[_next_placed]
		_next_placed = (_next_placed + 1) % _placed.size()
		placed.global_position = at
		player = placed
	player.set("stream", stream)
	player.set("pitch_scale", float(layer[2]))
	player.set("volume_db", MIX_DB + linear_to_db(float(layer[1]) * share))
	player.call("play")


## Every file stem these play, to read before play.
static func all_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for layer_stems in _layer_stems():
		stems.append_array(layer_stems)
	return stems


static func _layer_stems() -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for event: StringName in EVENTS:
		for who: String in ["victim", "onlooker"]:
			for layer: Array in EVENTS[event][who]:
				out.append(PackedStringArray(layer[0]))
	for layer: Array in DEATH:
		out.append(PackedStringArray(layer[0]))
	return out
