extends "res://tests/check_suite.gd"

## Checks what is heard of the round and the bomb (playtest issue 21):
## which of CS2's sound events each game event calls for, by the listener's
## side (RoundSounds.cues_for); the music kit's cues giving way by their
## priorities and stop flags (MusicRules, through SoundEvents); CS2's
## default music volumes (AudioSettings); the death camera's duck of the
## other buses; the bomb's last ten seconds read from its timer; and the
## bomb's own sounds (C4View): A's beep or B's, their last-ten-seconds
## versions, and the plant, defuse and pickup from the game's events.
##
##   godot --headless --path . --script tests/run_round_sound_checks.gd
##
## Needs nothing extracted: headless Godot hears nothing, so the checks are
## on which events start, at what level, and which give way. Without the
## files a voice still starts and keeps its rules (SoundEvents.silent_length).

const SECOND := 1_000_000


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_cues()
	_test_the_settings()
	await _test_the_music_rules()
	await _test_the_duck()
	await _test_a_round_heard()
	await _test_the_bomb_ten_seconds()
	await _test_the_bombs_own_sounds()
	_finish("round-sounds")


func _test_the_cues() -> void:
	for name in RoundSounds.all_events():
		_check(SoundEvents.has_event(name), "%s is one of CS2's events" % name)
	for name in C4View.all_sounds():
		_check(SoundEvents.has_event(name), "the bomb's %s is one of CS2's events" % name)

	var ct_win := {"winner": "CT", "reason": "TargetSaved"}
	_check_equal(Array(RoundSounds.cues_for(&"round_end", ct_win, "CT")),
		["Announcer.CTWin.CS2_Classic", "Music.WonRound.valve_cs2_01"], "a round the CTs win, heard by a CT: the announcer, then the kit's won music")
	_check_equal(Array(RoundSounds.cues_for(&"round_end", ct_win, "T")),
		["Announcer.CTWin.CS2_Classic", "Music.LostRound.valve_cs2_01"], "and by a T: the lost music")
	_check_equal(Array(RoundSounds.cues_for(&"round_end", {"winner": "T", "reason": "TargetBombed"}, "T")),
		["Announcer.TWin.CS2_Classic", "Music.WonRound.valve_cs2_01"], "a round the Ts win: Terrorists win")
	var defused := RoundSounds.cues_for(&"round_end", {"winner": "CT", "reason": "BombDefused"}, "CT")
	_check_equal(Array(defused), ["Announcer.BombDefused.CS2_Classic", "Announcer.CTWin.CS2_Classic", "Music.WonRound.valve_cs2_01"],
		"a defuse: Bomb has been defused, then Counter-Terrorists win")
	var delays := RoundSounds.line_delays(defused)
	var bombdef := SoundEvents.find("Announcer.BombDefused.CS2_Classic")
	_check(delays[0] == 0.0 and absf(delays[1] - (bombdef.duration + RoundSounds.LINE_GAP)) < 0.001 and delays[2] == 0.0,
		"the second line waits for the first to finish (%s); the music does not" % [delays])
	_check_equal(Array(RoundSounds.cues_for(&"round_end", {"winner": "CT", "reason": "TargetSaved", "nomusic": 1}, "CT")),
		["Announcer.CTWin.CS2_Classic"], "nomusic: no round-end music, the action goes on")
	_check_equal(Array(RoundSounds.cues_for(&"round_end", {"winner": "", "reason": "RoundDraw"}, "CT")),
		["Announcer.RoundDraw.CS2_Classic"], "a draw: the announcer's round draw, no music")
	_check_equal(Array(RoundSounds.cues_for(&"round_end", ct_win, "")),
		["Announcer.CTWin.CS2_Classic"], "nobody's side hears no won or lost music")
	_check_equal(Array(RoundSounds.cues_for(&"bomb_planted", {"userid": 3, "site": "A"}, "CT")),
		["Announcer.BombPlanted.CS2_Classic", "Music.BombPlanted.valve_cs2_01"], "the plant: the announcer and the kit's bomb music")
	_check_equal(Array(RoundSounds.cues_for(&"round_time_warning", {}, "T")), ["Music.TenSecCount.valve_cs2_01"], "the round's ten seconds: the kit's cue")
	_check_equal(Array(RoundSounds.cues_for(&"cs_round_start_beep", {}, "T")), ["UI.CounterBeep"], "a countdown beep")
	_check_equal(Array(RoundSounds.cues_for(&"cs_round_final_beep", {}, "T")), ["UI.CounterDoneBeep"], "the countdown's last")
	_check_equal(Array(RoundSounds.cues_for(&"round_announce_match_point", {}, "T")), ["Music.Match.MatchPoint"], "the match point's stinger")
	_check_equal(Array(RoundSounds.cues_for(&"round_announce_last_round_half", {}, "T")), ["Music.Match.LastRoundHalf"], "the half's last round's stinger")
	_check_equal(Array(RoundSounds.cues_for(&"round_announce_final", {}, "T")), ["Music.Match.FinalRound"], "the final round's stinger")
	_check_equal(Array(RoundSounds.cues_for(&"cs_win_panel_match", {}, "T")),
		["Music.MatchEnd.valve_cs2_01", "UIPanorama.gameover_show"], "the match's end: its music and the panel's sound")
	_check_equal(Array(RoundSounds.cues_for(&"round_mvp", {"userid": 2}, "T")), ["Music.MVPAnthem.valve_cs2_01"], "an MVP: the anthem")
	_check(RoundSounds.cues_for(&"round_mvp", {"userid": 2, "nomusic": 1}, "T").is_empty(), "unless nomusic")
	_check_equal(Array(RoundSounds.cues_for(&"player_death", {"userid": 4}, "T", 4)), ["Music.DeathCam.valve_cs2_01"], "your own death: the death camera's cue")
	_check(RoundSounds.cues_for(&"player_death", {"userid": 5}, "T", 4).is_empty(), "someone else's: nothing of the round's")


func _test_the_settings() -> void:
	var convars := AudioSettings.new().convars()
	_check(
		convars["snd_roundstart_volume"] == 0.0 and convars["snd_roundaction_volume"] == 0.0,
		"CS2's competitive defaults: no music at round start or as the round goes live"
	)
	_check(
		is_equal_approx(convars["snd_roundend_volume"], 0.16) and is_equal_approx(convars["snd_mvp_volume"], 0.16)
			and is_equal_approx(convars["snd_deathcamera_volume"], 0.16),
		"round end, MVP and death camera at 0.16"
	)
	_check(
		is_equal_approx(convars["snd_mapobjective_volume"], 0.04) and is_equal_approx(convars["snd_tensecondwarning_volume"], 0.04)
			and is_equal_approx(convars["snd_menumusic_volume"], 0.04),
		"the bomb, the ten seconds and the menu music at 0.04"
	)
	var quieter := AudioSettings.new()
	quieter.music_volume = 0.5
	_check(is_equal_approx(quieter.convars()["snd_roundend_volume"], 0.08), "the master music volume scales each cue")


## The kit's cues in turn, with every music volume at 1 so the levels do
## not hide what plays.
func _test_the_music_rules() -> void:
	var sounds := SoundEvents.new()
	sounds.silent_length = 100.0
	sounds.convars = _all_music_at(1.0)
	root.add_child(sounds)
	var start_round := sounds.start(RoundSounds.music("StartRound"))
	_check(start_round != 0 and sounds.is_playing(start_round), "the start-round music starts")
	var bomb := sounds.start(RoundSounds.music("BombPlanted"))
	_check(bomb != 0 and not sounds.is_playing(start_round), "the bomb's music stops the start-round music (stop_start_round)")
	sounds.advance(60.0)
	_check(sounds.is_playing(bomb), "and loops while the bomb ticks (loop_track), a minute on")
	var ten := sounds.start(RoundSounds.music("BombTenSecCount"))
	_check(ten != 0 and not sounds.is_playing(bomb), "the bomb's ten seconds stop its music (stop_bomb_planted)")
	var death := sounds.start(RoundSounds.music("DeathCam"))
	_check(death != 0 and sounds.is_playing(ten), "the death camera's cue plays beside it: it is in no priority")
	var won := sounds.start(RoundSounds.music("WonRound"))
	_check(won != 0 and not sounds.is_playing(ten), "the won music stops the rest (stop_music_except_mvp)")
	var late_bomb := sounds.start(RoundSounds.music("BombPlanted"))
	_check(late_bomb == 0, "a lower cue does not start over a higher one (bomb 3 under won 4)")
	var anthem := sounds.start(RoundSounds.music("MVPAnthem"))
	_check(anthem != 0 and not sounds.is_playing(won), "the MVP anthem replaces the won music")
	_check(sounds.start(RoundSounds.music("LostRound")) == 0, "and blocks the won and lost music while it plays")
	var next_round := sounds.start(RoundSounds.music("StartRound"))
	_check(next_round != 0 and not sounds.is_playing(anthem), "the next round's music stops everything (stop_music)")
	var action := sounds.start(RoundSounds.music("StartAction"))
	_check(action != 0, "the action music starts as freeze ends")
	sounds.advance(9.9)
	_check(sounds.is_playing(action), "the action music plays on 9.9 s in")
	sounds.advance(0.15)
	_check(not sounds.is_playing(action), "and stops itself 10 s in (stop_at_time)")
	_check_near(SoundEvents.find(RoundSounds.music("StartAction")).fade_length(), 3.0,
		"fading out over 3 s (volume_fade_out_input_max; a voice with no file ends at once)")
	_check_near(SoundEvents.find(RoundSounds.music("WonRound")).fade_length(), 1.6, "the won music over 1.6 s")
	sounds.queue_free()

	# CS2's own volumes.
	var levels := SoundEvents.new()
	levels.silent_length = 100.0
	levels.convars = AudioSettings.new().convars()
	root.add_child(levels)
	var start_level := levels.start(RoundSounds.music("StartRound"))
	_check(start_level != 0 and levels.voices()[0]["gain"] == 0.0, "at CS2's defaults the start-round music starts at 0: silent, but it still stops what played")
	var won_level := levels.start(RoundSounds.music("WonRound"))
	var won_voice := levels.voices().filter(func(v: Dictionary) -> bool: return v["id"] == won_level)
	_check(won_voice.size() == 1 and is_equal_approx(float(won_voice[0]["gain"]), 0.16), "the won music at its volume 1 times 0.16")
	levels.queue_free()
	var muted := SoundEvents.new()
	muted.silent_length = 100.0
	var settings := AudioSettings.new()
	settings.round_end = 0.0
	muted.convars = settings.convars()
	root.add_child(muted)
	_check(muted.start(RoundSounds.music("WonRound")) == 0, "with the round-end volume at 0 the won music is not started at all (skip_if_muted)")
	muted.queue_free()
	await process_frame


func _all_music_at(level: float) -> Dictionary:
	var settings := AudioSettings.new()
	for field in ["round_start", "round_action", "round_end", "mvp", "map_objective", "ten_second_warning", "death_camera", "menu_music"]:
		settings.set(field, level)
	return settings.convars()


## The death camera's cue ducks the rest for a moment: its mix layer, from
## all the way down to none over 1.5 s.
func _test_the_duck() -> void:
	var sounds := SoundEvents.new()
	sounds.silent_length = 100.0
	sounds.convars = AudioSettings.new().convars()
	root.add_child(sounds)
	sounds.start(RoundSounds.music("DeathCam"))
	var amounts := sounds.layer_amounts()
	_check_near(float(amounts.get("DuckingMusicLayer", 0.0)), 1.0, "the death camera's duck is full as it starts")
	var scales := SoundEvents.bus_scales(amounts)
	_check(is_equal_approx(float(scales.get("Weapons", 1.0)), 0.5) and is_equal_approx(float(scales.get("Music", 1.0)), 0.1),
		"it halves the weapons and takes the other music to a tenth (%s)" % [scales])
	sounds.advance(0.75)
	_check_near(float(sounds.layer_amounts().get("DuckingMusicLayer", 0.0)), 0.5, "half way through its 1.5 s, half")
	sounds.advance(0.8)
	_check_near(float(sounds.layer_amounts().get("DuckingMusicLayer", 0.0)), 0.0, "and gone after it")
	sounds.queue_free()

	# RoundSounds puts it on the buses, and takes it off.
	var round_sounds := RoundSounds.new()
	root.add_child(round_sounds)
	round_sounds.events.silent_length = 100.0
	var index := AudioServer.get_bus_index("Weapons")
	_check(index > 0, "the layout has the Weapons bus")
	if index <= 0:
		round_sounds.queue_free()
		return
	var before := AudioServer.get_bus_volume_db(index)
	round_sounds.events.start(RoundSounds.music("DeathCam"))
	round_sounds._apply_layers()
	_check_near(AudioServer.get_bus_volume_db(index) - before, linear_to_db(0.5), "the Weapons bus drops by half as the duck starts")
	round_sounds.events.advance(1.6)
	round_sounds._apply_layers()
	_check_near(AudioServer.get_bus_volume_db(index), before, "and is back at its own level after it")
	round_sounds.queue_free()
	await process_frame


## A round as a listener hears it: the events handed out at a tick's end,
## played on the next frame, by the listener's side.
func _test_a_round_heard() -> void:
	var game := GameSystems.new()
	var me := PlayerSim.new()
	me.team = "T"
	root.add_child(me)
	var userid := game.add_player(me)
	var round_sounds := RoundSounds.new()
	root.add_child(round_sounds)
	round_sounds.events.silent_length = 100.0
	round_sounds.watch(game, userid)
	game.events.send(&"round_end", {"winner": "T", "reason": "TargetBombed"})
	game.events.flush()
	_check(round_sounds.events.voices().is_empty() and round_sounds.pending().size() == 1,
		"handed out at the tick's end, the round's end is noted, not played")
	round_sounds._process(0.0)
	var names := round_sounds.events.voices().map(func(v: Dictionary) -> String: return v["event"])
	_check(names.has("Announcer.TWin.CS2_Classic") and names.has("Music.WonRound.valve_cs2_01"),
		"on the next frame: Terrorists win, and the won music for a T (%s)" % [names])
	var won: Array = round_sounds.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == "Music.WonRound.valve_cs2_01")
	_check(won.size() == 1 and is_equal_approx(float(won[0]["gain"]), 0.16), "the won music at CS2's round-end volume, 0.16")
	var line: Array = round_sounds.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == "Announcer.TWin.CS2_Classic")
	_check(line.size() == 1 and line[0]["bus"] == &"UI", "the announcer on the UI bus")
	game.events.send(&"round_start", {})
	game.events.flush()
	round_sounds._process(0.0)
	var music := round_sounds.events.voices().filter(func(v: Dictionary) -> bool: return String(v["event"]).begins_with("Music.") and not v["stopped"])
	_check(music.size() == 1 and music[0]["event"] == "Music.StartRound.valve_cs2_01" and music[0]["gain"] == 0.0,
		"the next round's start stops the won music and plays its own, silent at CS2's default (%s)" % [music.map(func(v): return [v["event"], v["gain"]])])
	round_sounds.queue_free()
	me.queue_free()
	await process_frame


## The bomb's last ten seconds, read from its timer once a frame: the kit's
## cue once a plant, stopping the bomb's music.
func _test_the_bomb_ten_seconds() -> void:
	_check(not RoundSounds.bomb_ten_seconds(10.5) and RoundSounds.bomb_ten_seconds(10.0) and RoundSounds.bomb_ten_seconds(0.1)
		and not RoundSounds.bomb_ten_seconds(0.0), "the last ten seconds: at 10 s left and under, not once it has gone off")
	var bomb := C4.new()
	bomb.state = C4.State.PLANTED
	bomb.site = "A"
	bomb.planted_usec = 100 * SECOND
	bomb.explodes_usec = 140 * SECOND
	var round_sounds := RoundSounds.new()
	root.add_child(round_sounds)
	round_sounds.events.silent_length = 100.0
	round_sounds.bomb = bomb
	var bomb_music := round_sounds.events.start(RoundSounds.music("BombPlanted"))
	round_sounds.check_bomb(129 * SECOND)
	var tens := func() -> Array: return round_sounds.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == "Music.BombTenSecCount.valve_cs2_01")
	_check(tens.call().is_empty(), "nothing at 11 s left")
	round_sounds.check_bomb(130 * SECOND + 1000)
	_check(tens.call().size() == 1, "the ten-second cue at 10 s left")
	_check(not round_sounds.events.is_playing(bomb_music), "and the bomb's music stops for it")
	round_sounds.check_bomb(131 * SECOND)
	_check(tens.call().size() == 1, "once a plant")
	round_sounds.queue_free()
	await process_frame


func _test_the_bombs_own_sounds() -> void:
	_check_equal(C4View.beep_event("A", 30.0), "C4.PlantSound", "on A the beep is C4.PlantSound (c4_beep2)")
	_check_equal(C4View.beep_event("B", 30.0), "C4.PlantSoundB", "on B, C4.PlantSoundB (c4_beep3)")
	_check_equal(C4View.beep_event("A", 10.0), "C4.PlantSound_10sec", "A's in the last ten seconds")
	_check_equal(C4View.beep_event("B", 4.0), "C4.PlantSoundB_10sec", "B's too")
	var b := SoundEvents.find("C4.PlantSoundB")
	_check(is_equal_approx(b.pitch, 0.9) and is_equal_approx(b.volume, 0.5), "B's is lower and quieter (pitch 0.9, volume 0.5)")
	for name in ["C4.PlantSound", "C4.PlantSoundB", "C4.PlantSound_10sec", "C4.PlantSoundB_10sec"]:
		_check_near(SoundEvents.find(name).silent_beyond(), 1300.0, "%s is silent past 1300 units" % name)
	_check_near(SoundEvents.find("c4.plant").silent_beyond(), 4100.0, "the plant is heard to 4100 units")
	_check_near(SoundEvents.find("c4.disarmstart").silent_beyond(), 2000.0, "a defuse starting to 2000")

	var game := GameSystems.new()
	var bomb := C4.new()
	bomb.position = Vector3(100.0, 0.0, 200.0)
	var view := C4View.new()
	view.bomb = bomb
	root.add_child(view)
	view.sounds.silent_length = 100.0
	view.watch(game)
	game.events.send(&"bomb_planted", {"userid": 1, "site": "A"})
	game.events.send(&"bomb_begindefuse", {"userid": 2, "haskit": false})
	game.events.flush()
	_check(view.sounds.voices().is_empty() and view.pending().size() == 2, "the bomb's events are noted, not played in the tick")
	view._process(0.0)
	var names := view.sounds.voices().map(func(v: Dictionary) -> String: return v["event"])
	_check(names.has("c4.plant") and names.has("c4.disarmstart"), "then the plant and the defuse's start are heard (%s)" % [names])
	var at: Array = view.sounds.voices().filter(func(v: Dictionary) -> bool: return v["event"] == "c4.plant")
	_check(at.size() == 1 and (at[0]["position"] as Vector3).is_equal_approx(bomb.position), "from where the bomb is")
	view.queue_free()
	await process_frame
