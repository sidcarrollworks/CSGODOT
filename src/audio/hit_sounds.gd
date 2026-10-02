class_name HitSounds
extends Node3D

## CS2's hit feedback, selected from the authoritative player_hurt rather
## than a target's final state after the tick. The attacker hears only
## .AttackerFeedback, the victim .Victim, and everyone else .Onlooker.
## One player_hurt makes one start: bullet_damage adds no second sound.
##
## SoundEvents reads the shipped files, mixgroups, child flesh/dink layers,
## pitch variation, delays, distance/stereo curves and burst blocks. These
## match the installed September 30 build (audio-gameplay.md 3.1); no guessed
## mix offset or overlapping manual WeaponSounds feedback is needed.
## Victim events are nearly plain stereo by their authored curves; the
## source remains the victim's feet so a spatial child keeps its own offset.
##
## Everything is queued when the tick hands out events and starts on the
## next drawn frame. Files are preloaded when this view enters the tree.

const KINDS := ["DamageBody", "DamageBodyArmor", "DamageHeadShot", "DamageHeadShotArmor", "DeathBody", "DeathBodyArmor", "DeathHeadShot", "DeathHeadShotArmor"]
const ROLES := ["AttackerFeedback", "Victim", "Onlooker"]
const DEATH_EVENT := "Player.Death"
const BURN_EVENT := "Player.BurnDamage"
const BURN_KEVLAR_EVENT := "Player.BurnDamageKevlar"
const SILENT_WEAPONS := ["weapon_molotov", "weapon_incgrenade", "inferno"]

var listener_id: int = GameEvents.NOBODY
var game: GameSystems
## [event name, snapshot of source position (or null), victim userid].
var _pending: Array = []
var events: SoundEvents


func watch(p_game: GameSystems, listener: int) -> void:
	_unwatch()
	_pending.clear()
	game = p_game
	listener_id = listener
	game.events.listen(&"player_hurt", _on_hurt)
	game.events.listen(&"player_death", _on_death)


func _ready() -> void:
	events = SoundEvents.new()
	events.name = "Events"
	add_child(events)
	SoundEvents.load_events(all_events())


func _exit_tree() -> void:
	_unwatch()
	_pending.clear()


func _unwatch() -> void:
	if game != null:
		game.events.unlisten(&"player_hurt", _on_hurt)
		game.events.unlisten(&"player_death", _on_death)
	game = null


## The authored event and recipient for one player's ears. Knife swings
## already supply the attacker's flesh sound; their victim/onlooker sound
## is still a body hit. Fire uses burn_event instead.
static func for_hit(hurt: Dictionary, listener: int) -> Dictionary:
	var weapon := String(hurt.get("weapon", ""))
	if weapon in SILENT_WEAPONS:
		return {}
	var victim: int = hurt.get("userid", GameEvents.NOBODY)
	var attacker: int = hurt.get("attacker", GameEvents.NOBODY)
	if victim == GameEvents.NOBODY:
		return {}
	var role := "Victim" if listener == victim else ("AttackerFeedback" if listener == attacker and attacker != GameEvents.NOBODY else "Onlooker")
	var knife := weapon.begins_with("weapon_knife") or weapon == "weapon_bayonet"
	if knife and role == "AttackerFeedback":
		return {}
	var head := int(hurt.get("hitgroup", 0)) == DamageInfo.HITGROUP_HEAD and not knife
	var kind := WeaponSounds.feedback_for(&"head" if head else &"chest", int(hurt.get("dmg_armor", 0)) > 0, int(hurt.get("health", 1)) <= 0)
	return {"event": "Player.%s.%s" % [kind, role], "flat": role == "Victim", "role": role}


static func burn_event(hurt: Dictionary) -> String:
	if String(hurt.get("weapon", "")) not in SILENT_WEAPONS:
		return ""
	return BURN_KEVLAR_EVENT if int(hurt.get("armor", 0)) > 0 else BURN_EVENT


func _on_hurt(event: GameEvent) -> void:
	var victim: int = event.fields["userid"]
	var burn := burn_event(event.fields)
	if not burn.is_empty():
		_queue(burn, victim)
		return
	var sound := for_hit(event.fields, listener_id)
	if not sound.is_empty():
		_queue(sound["event"], victim)


func _on_death(event: GameEvent) -> void:
	_queue(DEATH_EVENT, event.fields["userid"])


func _queue(event_name: String, userid: int) -> void:
	var source := game.roster.player(userid) if game != null else null
	if is_instance_valid(source) and source.is_inside_tree():
		_pending.append([event_name, source.global_position, userid])
	elif userid == listener_id:
		# The own victim sound can still play if a view was handed the event
		# after its player's node left the roster.
		_pending.append([event_name, null, userid])


func _process(_delta: float) -> void:
	for sound: Array in _pending:
		events.start(sound[0], sound[1], sound[2], {"local": int(sound[2]) == listener_id})
	_pending.clear()


## Every top-level event this view can select; load_events adds children.
static func all_events() -> PackedStringArray:
	var names := PackedStringArray([DEATH_EVENT, BURN_EVENT, BURN_KEVLAR_EVENT])
	for kind: String in KINDS:
		for role: String in ROLES:
			names.append("Player.%s.%s" % [kind, role])
	return names


## Exact extracted stems, for the shared extraction/preload checks.
static func all_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for name in SoundEvents.with_children(all_events()):
		for file in SoundEvents.find(name).files:
			var stem := file.get_basename().trim_prefix("sounds/")
			if stem not in stems:
				stems.append(stem)
	return stems
