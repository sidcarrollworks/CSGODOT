class_name GrenadeSounds
extends Node3D

## What one player hears of the grenades: the throws, the bounces, the
## burning bottle in flight, every detonation with its distant layer, the
## smoke clearing, the fires from their first flame to their end, the
## decoy's fake gunfire, and a flash in their own ears (the ring and the
## muffle). Every sound is a sound event of CS2's own, with its volume,
## curves, limits and children (SoundEvents), as
## reference/research/audio-gameplay.md 4 lists them.
##
## It only reads. The game's events are noted as they are handed out at a
## tick's end, with what the view knows then of the grenade they are about
## (cues_for's grenade), and played on the next frame drawn; the grenades
## and fires themselves are read once a frame, for what has no event: the
## bottle's flight, which its loop follows, and each new flame's ignite.
## Nothing is heard from inside the tick, and every file is read when the
## view is made.
##
## - grenade_thrown: the grenade's Throw (with the gear's rustle), from the
##   thrower; plain stereo in the thrower's own ears. The jump-throw's grunt
##   is not played: nothing tells a jump-throw yet.
## - grenade_bounce: the grenade's own Bounce, one a grenade and not one a
##   surface, as CS2's (the decoy has none). The event names only the
##   thrower and the point, so it goes to that thrower's grenade nearest it.
## - A molotov or incendiary in flight: Molotov.Throw.Loop (with its flare)
##   or IncGrenade.Throw.Loop, following the bottle, until it breaks.
## - hegrenade_detonate, flashbang_detonate, smokegrenade_detonate:
##   BaseGrenade.Explode, Flashbang.Explode, BaseSmokeEffect.Sound, each with
##   its distant layer. smokegrenade_expired: SmokeGrenade.Clear.
## - molotov_detonate: Molotov.Start (with the smash) or IncGrenade.Start
##   (with the pop) when a fire starts there, else StartFailed, the air burst
##   or the bottle breaking in smoke. The event names no class, so it is read
##   off the fire it lit or the bottle that broke.
## - A fire: Inferno.Loop from inferno_startburn until it ends, then
##   Inferno.FadeOut, or Molotov.Extinguish when smoke puts it out; and
##   Inferno.Fire.Ignite at each new flame, as its own limits allow (three at
##   once, one per 3 s within 15 units).
## - decoy_firing: the shot of the gun the decoy imitates (DECOY_SHOTS),
##   with its distant layer, from the decoy. decoy_detonate has no sound of
##   its own in CS2's files.
## - player_blind of the listener: FlashMuffle's ring and muffle, cleared
##   when the listener dies or a round starts.

const THROWS := {
	GrenadeRules.HE: "HEGrenade.Throw",
	GrenadeRules.FLASHBANG: "Flashbang.Throw",
	GrenadeRules.SMOKE: "SmokeGrenade.Throw",
	GrenadeRules.MOLOTOV: "Molotov.Throw",
	GrenadeRules.INCENDIARY: "IncGrenade.Throw",
	GrenadeRules.DECOY: "Decoy.Throw",
}
const BOUNCES := {
	GrenadeRules.HE: "HEGrenade.Bounce",
	GrenadeRules.FLASHBANG: "Flashbang.Bounce",
	GrenadeRules.SMOKE: "SmokeGrenade.Bounce",
	GrenadeRules.MOLOTOV: "Molotov.Bounce",
	GrenadeRules.INCENDIARY: "IncGrenade.Bounce",
}
const FLIGHT_LOOPS := {
	GrenadeRules.MOLOTOV: "Molotov.Throw.Loop",
	GrenadeRules.INCENDIARY: "IncGrenade.Throw.Loop",
}
## A bottle breaking: [lit, fizzled].
const FIRE_STARTS := {
	GrenadeRules.MOLOTOV: ["Molotov.Start", "Molotov.StartFailed"],
	GrenadeRules.INCENDIARY: ["IncGrenade.Start", "IncGrenade.StartFailed"],
}
## The events that sound the same whatever threw them.
const DETONATIONS := {
	&"hegrenade_detonate": "BaseGrenade.Explode",
	&"flashbang_detonate": "Flashbang.Explode",
	&"smokegrenade_detonate": "BaseSmokeEffect.Sound",
	&"smokegrenade_expired": "SmokeGrenade.Clear",
	&"inferno_startburn": "Inferno.Loop",
	&"inferno_expire": "Inferno.FadeOut",
	&"inferno_extinguish": "Molotov.Extinguish",
}
const FIRE_LOOP := "Inferno.Loop"
const FIRE_IGNITE := "Inferno.Fire.Ignite"
## The shot a decoy fires for each gun it can imitate: the gun's
## WEAPON_SOUND_SINGLE. vdata.csv does not carry the gun's sound names, so
## this is matched by the events' names and files in the table (the M4A4 is
## weapon_m4a1; the silenced guns fire their silenced shot, inferred).
const DECOY_SHOTS := {
	"weapon_glock": "Weapon_Glock.Single",
	"weapon_hkp2000": "Weapon_hkp2000.Single",
	"weapon_usp_silencer": "Weapon_USP.SilencedShot",
	"weapon_elite": "Weapon_ELITE.Single",
	"weapon_p250": "Weapon_P250.Single",
	"weapon_tec9": "Weapon_tec9.Single",
	"weapon_fiveseven": "Weapon_FiveSeven.Single",
	"weapon_cz75a": "Weapon_CZ75A.Single",
	"weapon_deagle": "Weapon_DEagle.Single",
	"weapon_revolver": "Weapon_Revolver.Single",
	"weapon_nova": "Weapon_Nova.Single",
	"weapon_xm1014": "Weapon_XM1014.Single",
	"weapon_sawedoff": "Weapon_Sawedoff.Single",
	"weapon_mag7": "Weapon_Mag7.Single",
	"weapon_m249": "Weapon_M249.Single",
	"weapon_negev": "Weapon_Negev.Single",
	"weapon_mac10": "Weapon_MAC10.Single",
	"weapon_mp9": "Weapon_MP9.Single",
	"weapon_mp7": "Weapon_MP7.Single",
	"weapon_mp5sd": "Weapon_MP5.Single",
	"weapon_ump45": "Weapon_UMP45.Single",
	"weapon_p90": "Weapon_P90.Single",
	"weapon_bizon": "Weapon_bizon.Single",
	"weapon_galilar": "Weapon_GalilAR.Single",
	"weapon_famas": "Weapon_FAMAS.Single",
	"weapon_ak47": "Weapon_AK47.Single",
	"weapon_m4a1": "Weapon_M4A4.Single",
	"weapon_m4a1_silencer": "Weapon_M4A1.Silenced",
	"weapon_ssg08": "Weapon_SSG08.Single",
	"weapon_sg556": "Weapon_sg556.Single",
	"weapon_aug": "Weapon_AUG.Single",
	"weapon_awp": "Weapon_AWP.Single",
	"weapon_g3sg1": "Weapon_G3SG1.Single",
	"weapon_scar20": "Weapon_SCAR20.Single",
}
## The events it plays from.
const HEARS: Array[StringName] = [
	&"grenade_thrown", &"grenade_bounce", &"hegrenade_detonate", &"flashbang_detonate",
	&"smokegrenade_detonate", &"smokegrenade_expired", &"molotov_detonate",
	&"inferno_startburn", &"inferno_expire", &"inferno_extinguish", &"decoy_firing",
	&"player_blind", &"player_death", &"round_start",
]
## How near a fire's origin must be to where a bottle broke to be its fire.
const SAME_POINT := 1.0

## Whose ears: the player this machine plays as.
var listener_id: int = GameEvents.NOBODY
var game: GameSystems
## The player it plays through.
var events: SoundEvents
var muffle := FlashMuffle.new()

## By entity id: every grenade and fire the game has handed out, kept a
## frame past its removal so its last events can still be matched to it.
var _known := {}
var _removed: Array[int] = []
## [event name, fields, grenade, where (Vector3, a Node3D or null), source]
## handed out and not yet played.
var _pending: Array = []
## By grenade id: [loop voice, the node it follows].
var _flights := {}
## By fire id: its loop's voice, and how many of its flames have ignited.
var _fire_loops := {}
var _flames_heard := {}
## The ring playing, and the seconds this view has run (the muffle's clock).
var _ring := 0
var _clock := 0.0


## Listens to a game's grenades, for listener's ears.
func watch(p_game: GameSystems, listener: int) -> void:
	_unlisten()
	game = p_game
	listener_id = listener
	for event_name in HEARS:
		game.events.listen(event_name, _on_event)
	game.entities.spawned.connect(_on_spawned)
	game.entities.removed.connect(_on_removed)
	for entity in game.entities.all():
		_on_spawned(entity)


func _ready() -> void:
	events = SoundEvents.new()
	events.name = "Events"
	add_child(events)
	SoundEvents.load_events(all_events())


func _exit_tree() -> void:
	_unlisten()
	muffle.remove()


func _unlisten() -> void:
	if game == null:
		return
	for event_name in HEARS:
		game.events.unlisten(event_name, _on_event)
	if game.entities.spawned.is_connected(_on_spawned):
		game.entities.spawned.disconnect(_on_spawned)
	if game.entities.removed.is_connected(_on_removed):
		game.entities.removed.disconnect(_on_removed)
	game = null


func _on_spawned(entity: SimEntity) -> void:
	if entity is GrenadeEntity or entity is InfernoEntity:
		_known[entity.id] = entity


func _on_removed(entity: SimEntity) -> void:
	if _known.has(entity.id):
		_removed.append(entity.id)


## Notes an event with what is known of its grenade now, at the tick's end.
func _on_event(event: GameEvent) -> void:
	var fields := event.fields.duplicate()
	var grenade := {}
	var where: Variant = null
	var source := int(fields.get("entityid", fields.get("userid", -1)))
	if fields.has("x"):
		where = GrenadeSystem.position_of(fields)
	match event.name:
		&"grenade_thrown":
			var thrower := game.roster.player(int(fields["userid"])) as Node3D
			if thrower == null:
				return
			where = null if int(fields["userid"]) == listener_id else thrower.global_position
		&"grenade_bounce":
			var bouncing := nearest(_grenades(), int(fields["userid"]), where, THROWS.keys())
			if bouncing == null:
				return
			grenade = {"weapon_class": bouncing.weapon_class}
			source = bouncing.id
		&"molotov_detonate":
			grenade = _fire_start(int(fields["userid"]), where)
		&"decoy_firing":
			var decoy := _known.get(int(fields["entityid"])) as GrenadeEntity
			grenade = {"decoy_weapon": decoy.decoy_weapon if decoy != null else ""}
	_pending.append([event.name, fields, grenade, where, source])


## The grenades known, as candidates for nearest.
func _grenades() -> Array[GrenadeEntity]:
	var result: Array[GrenadeEntity] = []
	for entity: SimEntity in _known.values():
		if entity is GrenadeEntity:
			result.append(entity as GrenadeEntity)
	return result


## What a bottle breaking at a point was: the class of the fire it lit
## there, or of the thrower's bottle nearest it when none was lit.
func _fire_start(thrower: int, at: Vector3) -> Dictionary:
	for entity: SimEntity in _known.values():
		if entity is InfernoEntity and entity.owner_id == thrower and entity.position.distance_to(at) <= SAME_POINT:
			return {"weapon_class": (entity as InfernoEntity).weapon_class, "lit": true}
	var bottle := nearest(_grenades(), thrower, at, FIRE_STARTS.keys())
	return {"weapon_class": bottle.weapon_class if bottle != null else GrenadeRules.MOLOTOV, "lit": false}


## Of these grenades, the one thrown by thrower, of one of these classes,
## nearest a point; null if they threw none.
static func nearest(grenades: Array[GrenadeEntity], thrower: int, at: Vector3, classes: Array) -> GrenadeEntity:
	var best: GrenadeEntity = null
	var best_distance := INF
	for grenade in grenades:
		if grenade.owner_id != thrower or grenade.weapon_class not in classes:
			continue
		var distance := grenade.position.distance_to(at)
		if distance < best_distance:
			best = grenade
			best_distance = distance
	return best


func _process(delta: float) -> void:
	_clock += delta
	_follow_flights()
	play_pending()
	_ignite_flames()
	muffle.apply(_clock)
	_forget_removed()


## Plays what the events handed out since the last frame call for.
func play_pending() -> void:
	for pending: Array in _pending:
		var event_name: StringName = pending[0]
		var fields: Dictionary = pending[1]
		match event_name:
			&"inferno_expire", &"inferno_extinguish":
				_stop_fire(int(fields["entityid"]))
			&"player_death":
				if int(fields.get("userid", GameEvents.NOBODY)) == listener_id:
					_clear_flash()
			&"round_start":
				_clear_flash()
			&"player_blind":
				if int(fields.get("userid", GameEvents.NOBODY)) == listener_id:
					muffle.flash(FlashMuffle.ring_for(float(fields.get("blind_duration", 0.0))), _clock)
					events.stop(_ring)
		for cue in cues_for(event_name, fields, pending[2], listener_id):
			var local: bool = pending[3] == null and event_name == &"grenade_thrown"
			var options := {"local": true} if local or event_name == &"player_blind" else {}
			if cue == FIRE_LOOP:
				options["loop"] = true
			var id := events.start(cue, pending[3], int(pending[4]), options)
			if cue == FIRE_LOOP:
				_fire_loops[int(fields["entityid"])] = id
			elif event_name == &"player_blind":
				_ring = id
	_pending.clear()


## What an event sounds like to a listener (their userid): the sound
## events, in order. grenade is what the view knew of the grenade then:
## weapon_class (a bounce's, a bottle's), lit (whether the bottle started a
## fire), decoy_weapon (the gun a decoy imitates).
static func cues_for(event_name: StringName, fields: Dictionary, grenade := {}, listener: int = GameEvents.NOBODY) -> PackedStringArray:
	var cues := PackedStringArray()
	var weapon_class := String(grenade.get("weapon_class", ""))
	match event_name:
		&"grenade_thrown":
			if THROWS.has(String(fields.get("weapon", ""))):
				cues.append(THROWS[String(fields["weapon"])])
		&"grenade_bounce":
			if BOUNCES.has(weapon_class):
				cues.append(BOUNCES[weapon_class])
		&"molotov_detonate":
			var starts: Array = FIRE_STARTS.get(weapon_class, FIRE_STARTS[GrenadeRules.MOLOTOV])
			cues.append(starts[0] if bool(grenade.get("lit", false)) else starts[1])
		&"decoy_firing":
			var gun := String(grenade.get("decoy_weapon", ""))
			if DECOY_SHOTS.has(gun):
				cues.append(DECOY_SHOTS[gun])
		&"player_blind":
			if listener != GameEvents.NOBODY and int(fields.get("userid", GameEvents.NOBODY)) == listener:
				cues.append(FlashMuffle.RINGS[FlashMuffle.ring_for(float(fields.get("blind_duration", 0.0)))])
		_:
			if DETONATIONS.has(event_name):
				cues.append(DETONATIONS[event_name])
	return cues


## Every event it can play, to read their files when it is made.
static func all_events() -> PackedStringArray:
	var names := PackedStringArray()
	for table: Dictionary in [THROWS, BOUNCES, FLIGHT_LOOPS, DETONATIONS, DECOY_SHOTS, FlashMuffle.RINGS]:
		for event_name: String in table.values():
			if event_name not in names:
				names.append(event_name)
	for starts: Array in FIRE_STARTS.values():
		names.append_array(PackedStringArray(starts))
	names.append(FIRE_IGNITE)
	return names


## The events noted and not played yet, as a copy.
func pending() -> Array:
	return _pending.duplicate(true)


## Starts each burning bottle's loop, moves it with the bottle drawn, and
## stops it when the bottle breaks.
func _follow_flights() -> void:
	var fraction := DrawClock.fraction()
	for id: int in _known:
		var grenade := _known[id] as GrenadeEntity
		if grenade == null or _flights.has(id) or not FLIGHT_LOOPS.has(grenade.weapon_class):
			continue
		if grenade.removed or grenade.phase != GrenadeEntity.Phase.FLYING:
			continue
		var marker := Node3D.new()
		add_child(marker)
		marker.global_position = grenade.position
		_flights[id] = [events.start(FLIGHT_LOOPS[grenade.weapon_class], marker, id, {"loop": true}), marker]
	for id: int in _flights.keys():
		var grenade := _known.get(id) as GrenadeEntity
		var flight: Array = _flights[id]
		if grenade == null or grenade.removed or grenade.phase != GrenadeEntity.Phase.FLYING:
			events.stop(int(flight[0]))
			(flight[1] as Node3D).queue_free()
			_flights.erase(id)
			continue
		(flight[1] as Node3D).global_position = grenade.previous_position.lerp(grenade.position, fraction)


## Plays an ignite at each flame a fire has added since the last frame.
func _ignite_flames() -> void:
	for id: int in _known:
		var fire := _known[id] as InfernoEntity
		if fire == null or fire.removed or fire.fire == null:
			continue
		var flames := fire.fire.flames
		var heard := int(_flames_heard.get(id, 0))
		for i in range(heard, flames.size()):
			events.start(FIRE_IGNITE, flames[i], id)
		_flames_heard[id] = flames.size()


func _stop_fire(id: int) -> void:
	if _fire_loops.has(id):
		events.stop(int(_fire_loops[id]))
		_fire_loops.erase(id)


func _clear_flash() -> void:
	muffle.clear()
	events.stop(_ring)
	_ring = 0


## Lets go of what was removed before this frame; a fire gone without its
## last event (a round's reset) stops its loop.
func _forget_removed() -> void:
	for id in _removed:
		_known.erase(id)
		_flames_heard.erase(id)
		_stop_fire(id)
	_removed.clear()
