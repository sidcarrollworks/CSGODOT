class_name RoundSounds
extends Node

## What one player hears of the round and the match: the announcer, the
## music kit's cues, the freeze countdown's beeps and the match's stingers,
## as CS2's client plays them (reference/research/audio-round.md 1.2). All of
## it is the client's own, flat in the ears; nothing here is placed in the
## world.
##
## It reads the game's events as they are handed out at a tick's end and
## plays what they call for on the next frame drawn (cues_for), and reads
## the bomb once a frame for its last ten seconds, from the bomb's timer
## rather than an event, so a late or lost event cannot skip it
## (audio-round.md 6). Nothing is heard from inside the tick. Every cue is a
## sound event of CS2's own (SoundEvents): the kit's cues give way to each
## other by their priorities and stop flags (MusicRules), each scaled by
## its music volume (AudioSettings, CS2's competitive defaults: no music at
## round start or as it goes live, the bomb and ten-second cues low). The
## death camera's cue ducks everything else for a moment (its mix layer,
## applied to the buses here).
##
## The kit is CS2's default, valve_cs2_01, for every player: nobody has
## chosen another. The announcer is CS2's classic pack.

const KIT := "valve_cs2_01"
const ANNOUNCER := "CS2_Classic"
## The bomb's music switches to its ten-second cue this many seconds before
## it goes off (the client's m_bTenSecWarning, round-bomb-grenades.md 1.3).
const BOMB_TEN_SECONDS := 10.0
## The events it plays from.
const HEARS: Array[StringName] = [
	&"round_start", &"round_freeze_end", &"cs_round_start_beep", &"cs_round_final_beep",
	&"round_time_warning", &"round_end", &"round_mvp", &"bomb_planted",
	&"round_announce_match_start", &"round_announce_last_round_half",
	&"round_announce_match_point", &"round_announce_final", &"cs_win_panel_match",
	&"player_death",
]
## A voice line waits for the one before it to finish, and this much more.
const LINE_GAP := 0.1

## Whose ears: the player this machine plays as.
var listener_id: int = GameEvents.NOBODY
var game: GameSystems
## The round's bomb, for its last ten seconds; null on a map without one.
var bomb: C4
var settings: AudioSettings
## The player it plays through.
var events: SoundEvents

## [event name, fields] handed out and not yet played.
var _pending: Array = []
## The plant whose ten-second cue has played.
var _ten_seconds_for: int = C4.NEVER
## The buses' own levels, before any layer moved them, and those moved now.
static var _base_db := {}
var _moved := {}


## Listens to a game's round, for listener's ears, and to its bomb.
func watch(p_game: GameSystems, listener: int, p_bomb: C4 = null) -> void:
	_unlisten()
	game = p_game
	listener_id = listener
	bomb = p_bomb
	for event_name in HEARS:
		game.events.listen(event_name, _on_event)


func _ready() -> void:
	if settings == null:
		settings = AudioSettings.new()
	events = SoundEvents.new()
	events.name = "Events"
	events.convars = settings.convars()
	add_child(events)
	SoundEvents.load_events(all_events())


func _exit_tree() -> void:
	_unlisten()
	for bus: String in _moved.keys():
		_set_bus(bus, 1.0)


func _unlisten() -> void:
	if game == null:
		return
	for event_name in HEARS:
		game.events.unlisten(event_name, _on_event)
	game = null


func _on_event(event: GameEvent) -> void:
	_pending.append([event.name, event.fields.duplicate()])


func _process(_delta: float) -> void:
	events.convars = settings.convars()
	play_pending()
	check_bomb(SimClock.now_usec())
	_apply_layers()


## Plays what the events handed out since the last frame call for.
func play_pending() -> void:
	var side := game.roster.team_of(listener_id) if game != null else ""
	for heard: Array in _pending:
		var names := cues_for(heard[0], heard[1], side, listener_id)
		var delays := line_delays(names)
		for i in names.size():
			events.start(names[i], null, -1, {"delay": delays[i]})
	_pending.clear()


## The bomb's last ten seconds, once a plant: its ten-second music, which
## stops the bomb's own.
func check_bomb(now_usec: int) -> void:
	if bomb == null or not bomb.planted():
		return
	if bomb.planted_usec != _ten_seconds_for and bomb_ten_seconds(bomb.seconds_left(now_usec)):
		_ten_seconds_for = bomb.planted_usec
		events.start(music("BombTenSecCount"))


## The events handed out and not played yet, as a copy.
func pending() -> Array:
	return _pending.duplicate(true)


## What an event calls for, for a listener on side (T, CT, or "" for
## nobody's) whose userid is listener: the sound events, in order.
##
## - round_end: the announcer names the winner (CTWin, TWin, RoundDraw),
##   after "Bomb has been defused" on a defuse (whether CS2 plays both is
##   a Local check); and, unless nomusic, the kit's WonRound or LostRound
##   by the listener's side (none for a draw or nobody's side).
## - round_mvp: the kit's anthem, unless nomusic (a bot's kit is the
##   default one; audio-round.md Local check 5).
## - bomb_planted: the announcer's "Bomb has been planted" and the kit's
##   bomb music.
## - round_time_warning: the kit's round ten-second cue.
## - cs_round_start_beep, cs_round_final_beep: UI.CounterBeep and
##   UI.CounterDoneBeep (inferred from the names, audio-round.md 1.2).
## - round_start, round_freeze_end: the kit's start-round and action music,
##   at 0 by CS2's defaults.
## - The announcements: the match's start music, the stingers for the last
##   round of a half, a match point and the final round.
## - cs_win_panel_match: the match's end music and the game-over panel's
##   sound.
## - player_death of the listener: the death camera's cue.
static func cues_for(event_name: StringName, fields: Dictionary, side: String, listener: int = GameEvents.NOBODY) -> PackedStringArray:
	var cues := PackedStringArray()
	match event_name:
		&"round_end":
			var winner := String(fields.get("winner", ""))
			if String(fields.get("reason", "")) == "BombDefused":
				cues.append(announcer("BombDefused"))
			match winner:
				"CT":
					cues.append(announcer("CTWin"))
				"T":
					cues.append(announcer("TWin"))
				_:
					cues.append(announcer("RoundDraw"))
			if int(fields.get("nomusic", 0)) == 0 and winner in MatchState.SIDES and side in MatchState.SIDES:
				cues.append(music("WonRound" if side == winner else "LostRound"))
		&"round_mvp":
			if int(fields.get("nomusic", 0)) == 0:
				cues.append(music("MVPAnthem"))
		&"bomb_planted":
			cues.append(announcer("BombPlanted"))
			cues.append(music("BombPlanted"))
		&"round_time_warning":
			cues.append(music("TenSecCount"))
		&"cs_round_start_beep":
			cues.append("UI.CounterBeep")
		&"cs_round_final_beep":
			cues.append("UI.CounterDoneBeep")
		&"round_start":
			cues.append(music("StartRound"))
		&"round_freeze_end":
			cues.append(music("StartAction"))
		&"round_announce_match_start":
			cues.append(music("MatchStart"))
		&"round_announce_last_round_half":
			cues.append("Music.Match.LastRoundHalf")
		&"round_announce_match_point":
			cues.append("Music.Match.MatchPoint")
		&"round_announce_final":
			cues.append("Music.Match.FinalRound")
		&"cs_win_panel_match":
			cues.append(music("MatchEnd"))
			cues.append("UIPanorama.gameover_show")
		&"player_death":
			if listener != GameEvents.NOBODY and int(fields.get("userid", GameEvents.NOBODY)) == listener:
				cues.append(music("DeathCam"))
	return cues


## Seconds each cue waits beyond its own delay: an announcer line after
## another waits for it to finish (its event's own delay, its file's length
## and LINE_GAP), so two lines never talk over each other.
static func line_delays(names: PackedStringArray) -> Array[float]:
	var delays: Array[float] = []
	var free_at := 0.0
	for cue in names:
		var wait := 0.0
		if cue.begins_with("Announcer."):
			wait = free_at
			var event := SoundEvents.find(cue)
			if event != null:
				free_at = wait + event.delay + event.duration + LINE_GAP
		delays.append(wait)
	return delays


## Whether the bomb, this many seconds from going off, is in its last ten.
static func bomb_ten_seconds(seconds_left: float) -> bool:
	return seconds_left > 0.0 and seconds_left <= BOMB_TEN_SECONDS


static func music(cue: String) -> String:
	return "Music.%s.%s" % [cue, KIT]


static func announcer(line: String) -> String:
	return "Announcer.%s.%s" % [line, ANNOUNCER]


## Every event it can play, to read their files when it is made.
static func all_events() -> PackedStringArray:
	var names := PackedStringArray()
	for cue in ["WonRound", "LostRound", "MVPAnthem", "BombPlanted", "BombTenSecCount", "TenSecCount", "StartRound", "StartAction", "MatchStart", "MatchEnd", "DeathCam"]:
		names.append(music(cue))
	for line in ["BombDefused", "CTWin", "TWin", "RoundDraw", "BombPlanted"]:
		names.append(announcer(line))
	names.append_array(["UI.CounterBeep", "UI.CounterDoneBeep", "Music.Match.LastRoundHalf", "Music.Match.MatchPoint", "Music.Match.FinalRound", "UIPanorama.gameover_show"])
	return names


## The mix layers the voices trigger (the death camera's duck), on the
## buses, from their own levels.
func _apply_layers() -> void:
	var scales := SoundEvents.bus_scales(events.layer_amounts())
	for bus: String in _moved.keys():
		if not scales.has(bus):
			_set_bus(bus, 1.0)
	for bus: String in scales:
		_set_bus(bus, float(scales[bus]))


func _set_bus(bus: String, scale: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index <= 0:
		return
	if not _base_db.has(bus):
		_base_db[bus] = AudioServer.get_bus_volume_db(index)
	if is_equal_approx(scale, 1.0):
		_moved.erase(bus)
	else:
		_moved[bus] = scale
	var level := float(_base_db[bus]) + (linear_to_db(scale) if scale > 0.0001 else SoundEvents.SILENT_DB)
	AudioServer.set_bus_volume_db(index, level)
