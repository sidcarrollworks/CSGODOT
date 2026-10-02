extends "res://tests/check_suite.gd"

## A player whose buttons the check holds.
class Commanded extends PlayerSim:
	var held := 0

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super.command_for(tick, dt)
		cmd.buttons = held
		return cmd

## Checks the shared sound groundwork (reference/playtest-2026-09-25.md,
## issues 19 to 21): the KV3 reader, the table of CS2's sound events
## generated from its .vsndevts text (reference/sounds/), the bus layout
## generated with it, and the SoundEvents player's rules, which it runs
## whether or not a file can be played.
##
##   godot --headless --path . --script tests/run_sound_event_checks.gd
##
## Needs nothing extracted: headless Godot hears nothing (the Dummy audio
## driver), so the checks are on what a start decides and what level it
## sets, not on what sounds. And issue 20, the low-ammo click on top of it:
## the provisional rule, and a WeaponSounds noting a click for each round
## past it, from the game's weapon_fire. And dry fire: one click a trigger
## pull on an empty magazine (Weapon.dry_fire), sent as weapon_fire_on_empty
## and heard as CS2's Default.ClipEmpty_Pistol or _Rifle. With the extraction, one check more: a start
## plays a file on its mixgroup's bus.


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_kv3()
	_test_the_table()
	_test_the_levels()
	_test_the_buses()
	await _test_the_player()
	_test_the_nearly_empty_rule()
	await _test_the_low_ammo_click()
	_test_the_dry_fire_rule()
	await _test_the_dry_fire_click()
	_finish("sounds")


func _test_kv3() -> void:
	var text := """<!-- kv3 encoding:text:version{e21c7f3c} format:generic:version{7412167c} -->
{
	Weapon_Test.Single =
	{
		type = "csgo_mega"
		volume = 1.1
		pitch_random_min = -0.02
		use_doppler = false
		sound = soundevent:"Other.Event"
		position_offset = [ 0.0, 0.0, 60.0 ]
		curve =
		[
			[
				25.0, 0.8, 0.04, 0.04,
				1.0, 1.0,
			],
		]
		// a comment
		metadata = [ "meta", "localplayeronly", ]
		nested = { a = "x\\"y" }
	}
}"""
	var parsed: Variant = KV3.parse(text)
	_check(parsed is Dictionary and parsed.has("Weapon_Test.Single"), "KV3 reads a dotted key past the header comment")
	if not parsed is Dictionary:
		return
	var event: Dictionary = parsed["Weapon_Test.Single"]
	_check_near(float(event.volume), 1.1, "KV3 reads a number")
	_check_near(float(event.pitch_random_min), -0.02, "KV3 reads a negative number")
	_check_equal(event.use_doppler, false, "KV3 reads a bool")
	_check_equal(event.sound, "Other.Event", "KV3 keeps a typed string's text")
	_check_equal(event.position_offset, [0.0, 0.0, 60.0], "KV3 reads an array with a trailing comma")
	_check_equal((event.curve as Array)[0].size(), 6, "KV3 reads a curve's points")
	_check_equal(event.metadata, ["meta", "localplayeronly"], "KV3 skips a // comment and reads a list of strings")
	_check_equal(event.nested.a, "x\"y", "KV3 reads an object and an escaped quote")


func _test_the_table() -> void:
	var source: Dictionary = SoundEvents.table().get("source", {})
	_check(not String(source.get("build", "")).is_empty(), "the table says which CS2 build it came from (%s)" % source.get("build", ""))
	var events: Dictionary = SoundEvents.table().get("events", {})
	_check(events.size() > 1500, "the table holds CS2's events (%d)" % events.size())
	# What issues 19, 20 and 21 play, by the names their plans give.
	var wanted := [
		"Default.NearlyEmpty", "Default.ClipEmpty_Rifle",
		"HEGrenade.Throw", "BaseGrenade.JumpThrow", "Molotov.Throw.Loop", "BaseGrenade.Explode", "Flashbang.Explode",
		"Flashbang.Ring.Short", "Flashbang.Ring.Long", "BaseSmokeEffect.Sound", "SmokeGrenade.Clear", "Inferno.Loop",
		"Molotov.Extinguish", "Player.BurnDamage",
		"Announcer.CTWin.CS2_Classic", "Announcer.BombPlanted.CS2_Classic", "Music.WonRound.valve_cs2_01",
		"Music.BombTenSecCount.valve_cs2_01", "UI.CounterBeep", "UI.CounterDoneBeep", "C4.PlantSound", "C4.PlantSoundB",
		"c4.plant", "c4.disarmstart",
	]
	var missing := wanted.filter(func(name): return not SoundEvents.has_event(name))
	_check(missing.is_empty(), "every event issues 19 to 21 name is in the table (missing: %s)" % ", ".join(missing))
	_check(SoundEvents.find("default.nearlyempty") == SoundEvents.find("Default.NearlyEmpty"), "an event is found in any case, as vdata spells Default.nearlyempty")
	_check(SoundEvents.find("No.Such.Event") == null, "an unknown event is null")
	var dangling := PackedStringArray()
	var odd_files := PackedStringArray()
	for name in events:
		var event := SoundEvents.find(name)
		for child in event.children:
			if not SoundEvents.has_event(child):
				dangling.append("%s -> %s" % [name, child])
		for file in event.files:
			if not (file.begins_with("sounds/") and file.ends_with(".vsnd")):
				odd_files.append(file)
	_check(dangling.is_empty(), "every child event is in the table (%s)" % ", ".join(dangling.slice(0, 5)))
	_check(odd_files.is_empty(), "every file is a sounds/ .vsnd path (%s)" % ", ".join(odd_files.slice(0, 5)))
	var ak := SoundEvents.find("Weapon_AK47.Single")
	_check_equal(ak.files.size(), 3, "the AK-47's shot picks from three files, _03 left out as its event does")
	_check_equal(ak.mixgroup, "Weapons", "the AK-47's shot is in Weapons")
	_check_equal(ak.instance_limit, 1, "an AK-47 plays one shot at a time")
	_check_equal(ak.children, PackedStringArray(["Weapon_AK47.SingleDistant"]), "the AK-47's shot starts its distant layer")
	_check_equal(ak.position_offset, Vector3(0, 60, 0), "CS2's Z-up offset becomes Godot's Y")
	_check(SoundEvents.find("Weapon_AK47.Draw").local_player_only, "a draw is heard by its player only")
	_check(not SoundEvents.find("Default.NearlyEmpty").local_player_only, "the low-ammo click is heard by everyone near")
	# The types' defaults fill in what an event leaves out.
	var click := SoundEvents.find("Default.NearlyEmpty")
	_check_near(click.pitch, 1.0, "an event without a pitch gets the stack's 1.0")
	_check_near(click.delay, 0.05, "the low-ammo click waits 0.05 s")
	_check_near(click.voice_fade_out_time, 0.2, "a stop fades over the stack's 0.2 s")


func _test_the_levels() -> void:
	var ak := SoundEvents.find("Weapon_AK47.Single")
	_check_near(ak.gain(100.0), 1.1, "an AK-47 at 100 units is at its full 1.1")
	_check_near(ak.gain(440.0), 1.1 * 0.735294, "an AK-47 at 440 units is at its curve's 0.735")
	_check_near(ak.gain(864.0), 1.1 * lerpf(0.735294, 0.330882, (864.0 - 440.0) / (1288.0 - 440.0)), "between points the curve is straight")
	_check_near(ak.gain(5000.0), 1.1 * 0.014706, "past its last point the curve holds its end")
	_check_near(ak.gain(20.0), 1.1 * 0.8, "before its first point the curve holds its start")
	_check(is_inf(ak.silent_beyond()), "the AK-47's near layer never ends at 0")
	var distant := SoundEvents.find("Weapon_AK47.SingleDistant")
	_check_near(distant.gain(500.0), 0.0, "the distant layer is silent close by")
	_check_near(distant.gain(2335.836914), 0.5 * 0.540441, "the distant layer peaks at 2336 units")
	var click := SoundEvents.find("Default.NearlyEmpty")
	_check_near(click.silent_beyond(), 1100.0, "the low-ammo click is silent from 1100 units")
	_check_near(click.gain(34.57143), 1.5, "the low-ammo click is at its 1.5 close by")
	_check_near(click.stereo_at(10.0), 1.0, "your own click plays as plain stereo")
	_check_near(click.stereo_at(100.0), 0.0, "someone else's click is placed")
	var clip_out := SoundEvents.find("Weapon_AK47.Clipout")
	_check(clip_out.suppression_enable, "a reload part can be held silent")
	_check_near(clip_out.gain(200.0, 0.0, 0.0, true), 0.07 * clip_out.gain(200.0 / 0.2), "a silent reload is 0.07 as loud, its curve reached five times sooner")
	var won := SoundEvents.find("Music.WonRound.valve_cs2_01")
	_check_equal(won.volume_convar, "snd_roundend_volume", "the round-won music follows snd_roundend_volume")
	_check_near(won.gain(0.0, 0.0, 0.0, false, 0.16), won.volume * 0.16, "a convar scales its music")
	_check(won.distance_curve.is_empty(), "music does not fall off with distance")
	_check_near(clip_out.fade_at(0.1), 0.5, "a plain stop is halfway down after 0.1 s")
	_check_near(SoundEvent.curve_at([[0.0, 1.0], [1.0, 0.0]], 0.25), 0.75, "curve_at is straight between points")


func _test_the_buses() -> void:
	var groups: Dictionary = SoundEvents.table().get("mixgroups", {})
	var used := {}
	for name in SoundEvents.table().get("events", {}):
		used[SoundEvents.find(name).mixgroup] = true
	var without_bus := PackedStringArray()
	var wrong_level := PackedStringArray()
	for group in used:
		if group == "All":
			continue
		var index := AudioServer.get_bus_index(group)
		if index <= 0:
			without_bus.append(group)
			continue
		var vol := float(groups.get(group, {}).get("vol", 1.0))
		var expected := -80.0 if vol <= 0.0001 else linear_to_db(vol)
		if absf(AudioServer.get_bus_volume_db(index) - expected) > 0.01 or AudioServer.get_bus_send(index) != &"Master":
			wrong_level.append(group)
	_check(without_bus.is_empty(), "every mixgroup an event uses has its bus in default_bus_layout.tres (missing: %s)" % ", ".join(without_bus))
	_check(wrong_level.is_empty(), "every bus is at Default_Mix's vol and sends to Master (wrong: %s)" % ", ".join(wrong_level))
	_check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Weapons")), linear_to_db(0.6), "Weapons is at CS2's 0.6")
	_check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("VO")), linear_to_db(0.34), "VO is at CS2's 0.34")
	_check_equal(SoundEvents.bus_for("Weapons"), &"Weapons", "a mixgroup plays on its own bus")
	_check_equal(SoundEvents.bus_for("All"), &"Master", "All plays on Master")


func _test_the_player() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ears := Node3D.new()
	world.add_child(ears)
	var sounds := SoundEvents.new()
	sounds.listener = ears
	sounds.silent_length = 1.0
	sounds.rng.seed = 7
	world.add_child(sounds)
	await process_frame
	var loads_before := SoundEvents.late_loads
	SoundEvents.load_events(PackedStringArray(["Weapon_AK47.Single", "Weapon_AWP.Single", "Weapon_AK47.Draw",
		"Default.NearlyEmpty", "Molotov.Throw.Loop", "Music.WonRound.valve_cs2_01"]))

	# A shot starts its distant layer; the next from the same gun stops the
	# last; another gun's is its own.
	var far := Vector3(1000, 0, 0)
	var first := sounds.start("Weapon_AK47.Single", far, 3)
	_check(first > 0, "a shot starts")
	_check_equal(_count(sounds, "Weapon_AK47.SingleDistant", 3), 1, "a shot starts its distant layer")
	sounds.advance(0.1)
	sounds.start("Weapon_AK47.Single", far, 3)
	_check_equal(_count(sounds, "Weapon_AK47.Single", 3), 1, "a second shot stops the first (instance_limit 1)")
	_check(not sounds.is_playing(first), "the first shot is stopped")
	sounds.advance(0.1)
	sounds.start("Weapon_AK47.Single", far, 3)
	_check_equal(_count(sounds, "Weapon_AK47.SingleDistant", 3), 2, "the distant layer keeps two (instance_limit 2)")
	sounds.start("Weapon_AK47.Single", far, 4)
	_check_equal(_count(sounds, "Weapon_AK47.Single", 4), 1, "another shooter's shot does not stop this one's")
	var shot: Dictionary = _voice(sounds, "Weapon_AK47.Single", 3)
	var ak := SoundEvents.find("Weapon_AK47.Single")
	_check_near(float(shot.get("gain", 0.0)), ak.gain(Vector3(1000, 60, 0).length()), "a shot's level is its curve at the listener's distance, from 60 units up")
	_check_equal(shot.get("bus"), &"Weapons", "a shot plays on Weapons")

	# A block refuses the same event from the same source for its time.
	var awp := SoundEvents.find("Weapon_AWP.Single")
	_check(awp.block_matching_events and awp.block_duration > 0.2, "the AWP's shot blocks for %.1f s" % awp.block_duration)
	_check(sounds.start("Weapon_AWP.Single", far, 5) > 0, "an AWP shot starts")
	_check_equal(sounds.start("Weapon_AWP.Single", far, 5), 0, "a second within its block is refused")
	_check(sounds.start("Weapon_AWP.Single", far, 6) > 0, "another AWP's is not")
	sounds.advance(awp.block_duration + 0.01)
	_check(sounds.start("Weapon_AWP.Single", far, 5) > 0, "after the block it starts again")

	# Who hears it.
	_check_equal(sounds.start("Weapon_AK47.Draw", Vector3.ZERO, 3), 0, "someone else's draw is not heard")
	_check(sounds.start("Weapon_AK47.Draw", Vector3.ZERO, 3, {"local": true}) > 0, "your own draw is")

	# A delay: the click sounds 0.05 s after the shot.
	var click := sounds.start("Default.NearlyEmpty", Vector3(200, 0, 0), 3)
	_check(not bool(_by_id(sounds, click).get("started", true)), "the low-ammo click waits for its delay")
	sounds.advance(0.03)
	_check(not bool(_by_id(sounds, click).get("started", true)), "and is still waiting at 0.03 s")
	sounds.advance(0.03)
	_check(bool(_by_id(sounds, click).get("started", false)), "and starts by 0.06 s")

	# Out of reach: started and gone, with no player.
	var out_of_reach := sounds.start("Default.NearlyEmpty", Vector3(3000, 0, 0), 8)
	sounds.advance(0.06)
	sounds.advance(0.01)
	_check(_by_id(sounds, out_of_reach).is_empty(), "a click past 1100 units is dropped once it starts")

	# A sound at a node follows it.
	var grenade := Node3D.new()
	world.add_child(grenade)
	var loop := sounds.start("Molotov.Throw.Loop", grenade, 9)
	grenade.position = Vector3(0, 0, 250)
	sounds.advance(0.02)
	_check_equal(_by_id(sounds, loop).get("position"), Vector3(0, 0, 250), "a sound started at a node follows it")
	grenade.queue_free()
	await process_frame
	sounds.advance(0.02)
	_check(not _by_id(sounds, loop).is_empty(), "and stays where the node was last when it is freed")

	# Convars.
	sounds.convars["snd_roundend_volume"] = 0.16
	var won := sounds.start("Music.WonRound.valve_cs2_01")
	var won_event := SoundEvents.find("Music.WonRound.valve_cs2_01")
	sounds.advance(0.0)
	_check_near(float(_by_id(sounds, won).get("gain", 0.0)), won_event.volume * 0.16, "music is scaled by its convar")

	# Nothing is read at a start, and without the extraction nothing plays.
	_check_equal(SoundEvents.late_loads, loads_before, "a start reads no file its view did not load beforehand")
	if SoundBank.available():
		var played := sounds.start("Weapon_AK47.Single", Vector3(100, 0, 0), 11)
		var voice := _by_id(sounds, played)
		_check(bool(voice.get("has_player", false)), "with the extraction a shot has a player")
		# The voice's own player: the shot's distant layer has one too, on
		# WeaponsDistant.
		var player: Node = voice.get("player")
		_check(player != null and player.get("bus") == &"Weapons", "on its mixgroup's bus")
	else:
		_check_equal(sounds.get_child_count(), 0, "without the extraction nothing plays, and the rules still run")
		print("The sounds are not extracted (scripts/extract_assets.sh sounds): the check of a played file is left out.")
	# Past the longest file actually playing (or kept without one), only
	# loops are left.
	var longest := 0.0
	for voice in sounds.voices():
		if not is_inf(float(voice.remaining)):
			longest = maxf(longest, float(voice.remaining))
	sounds.advance(longest + 0.01)
	sounds.advance(0.01)
	_check(sounds.voices().all(func(v): return is_inf(float(v.remaining))), "short sounds are gone after their time (%.2f s), loops left" % longest)
	world.queue_free()
	await process_frame


func _count(sounds: SoundEvents, event: String, source: int) -> int:
	return sounds.voices().filter(func(v): return v.event == event and v.source == source and not v.stopped).size()


func _voice(sounds: SoundEvents, event: String, source: int) -> Dictionary:
	for voice in sounds.voices():
		if voice.event == event and voice.source == source and not voice.stopped:
			return voice
	return {}


func _by_id(sounds: SoundEvents, id: int) -> Dictionary:
	for voice in sounds.voices():
		if voice.id == id:
			return voice
	return {}


## The provisional rule (WeaponData.nearly_empty): at or under a fifth of
## the magazine, rounded down, a shotgun's under three tenths, the emptying
## round included.
func _test_the_nearly_empty_rule() -> void:
	# Magazine, rounds left at the last round that clicks, per plan step 4.
	var guns := {
		"weapon_ak47": [30, 6], "weapon_m4a1_silencer": [20, 4], "weapon_deagle": [7, 1],
		"weapon_awp": [5, 1], "weapon_nova": [8, 2], "weapon_negev": [150, 30],
	}
	for weapon_class: String in guns:
		var data := WeaponLibrary.build(weapon_class)
		var want: Array = guns[weapon_class]
		_check_equal(data.magazine_size, want[0], "%s holds %d" % [weapon_class, want[0]])
		var last := int(want[1])
		_check(data.nearly_empty(last) and not data.nearly_empty(last + 1) and data.nearly_empty(0),
			"%s clicks from %d rounds left down to the empty one, not at %d" % [weapon_class, last, last + 1])
	_check(not WeaponLibrary.build("weapon_ak47").nearly_empty(-1), "no rounds counted, no click")
	var knife := WeaponData.new()
	knife.magazine_size = 0
	_check(not knife.nearly_empty(0), "a weapon with no magazine never clicks")


## A WeaponSounds watching a player notes a click for every round that
## leaves the magazine past the threshold, from the game's weapon_fire as
## the tick hands it out, and starts the event on the next frame: 0.05 s
## later, on Foley. Another gun's weapon_fire, or another player's, clicks
## nothing.
func _test_the_low_ammo_click() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var world := GameWorld.new()
	holder.add_child(world)
	world.set_physics_process(false)
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.ak47()
	player.team = "T"
	player.collision_layer = 2
	holder.add_child(player)
	player.place(Vector3(0, 0, 0), 0.0)
	player.respawn()
	world.add_player(player)
	var sounds := WeaponSounds.new()
	player.add_child(sounds)
	sounds.set_process(false)
	sounds.watch(player)
	await process_frame
	_check(player.weapon != null and player.weapon.data.item_class == "weapon_ak47", "the player holds the AK-47")
	if player.weapon == null:
		holder.queue_free()
		return
	player.weapon.ammo = 9
	var left: Array[int] = []
	world.game.events.listen(&"weapon_fire", func(_event: GameEvent) -> void: left.append(player.weapon.ammo))
	player.held = UserCmd.ATTACK
	for i in SimClock.ticks_in(ItemRegistry.item("weapon_ak47").deploy_seconds + 0.75):
		world.step()
	player.held = 0
	var clicking := left.filter(func(rounds: int) -> bool: return rounds <= 6).size()
	_check(left.size() >= 4 and left.any(func(rounds: int) -> bool: return rounds > 6) and clicking > 0,
		"the AK-47 fired rounds either side of the threshold (%s left after each)" % [left])
	_check_equal(sounds.pending_low_ammo(), clicking, "a click is noted for each round that left 6 or fewer, none before")
	world.game.events.send(&"weapon_fire", {"userid": player.userid, "weapon": "weapon_glock"})
	world.game.events.send(&"weapon_fire", {"userid": player.userid + 100, "weapon": "weapon_ak47"})
	world.game.events.flush()
	_check_equal(sounds.pending_low_ammo(), clicking, "another gun's round, or another player's, clicks nothing")
	sounds._process(0.0)
	_check_equal(sounds.pending_low_ammo(), 0, "the next frame starts what was noted")
	var clicks := sounds.events.voices().filter(func(v: Dictionary) -> bool: return v.event == WeaponSounds.NEARLY_EMPTY_EVENT)
	_check(not clicks.is_empty() and clicks.all(func(v: Dictionary) -> bool: return not v.started and v.bus == &"Foley"),
		"as CS2's Default.NearlyEmpty, waiting its 0.05 s, on Foley (%d)" % clicks.size())
	_check(not SoundEvents.find(WeaponSounds.NEARLY_EMPTY_EVENT).local_player_only, "and a bot's is heard by those near it")
	world.remove_player(player)
	holder.queue_free()
	await process_frame


## Weapon.dry_fire: one click a pull on an empty magazine, once the gun
## would have been ready; a press or a let-go arms it again; nothing while
## it reloads or is drawn, or with rounds left. And which event each gun
## clicks with.
func _test_the_dry_fire_rule() -> void:
	var weapon := Weapon.new(ItemRegistry.weapon_data("weapon_glock"))
	var now := 10_000_000
	weapon.ammo = 1
	_check(not weapon.dry_fire(now), "a gun with a round in it does not click")
	weapon.ammo = 0
	_check(weapon.dry_fire(now), "an empty gun clicks as the trigger is pulled")
	_check(not weapon.dry_fire(now + 500_000), "and once only while the pull lasts")
	weapon.press_trigger()
	_check(weapon.dry_fire(now + 600_000), "a new press clicks again")
	weapon.trigger_held = false
	weapon.trigger_held = true
	_check(weapon.dry_fire(now + 700_000), "and so does letting go and pulling again")
	weapon.reserve = 20
	_check(weapon.start_reload(now + 800_000), "the reload starts")
	weapon.press_trigger()
	_check(not weapon.dry_fire(now + 900_000), "an empty gun reloading does not click")
	var fresh := Weapon.new(ItemRegistry.weapon_data("weapon_ak47"))
	fresh.draw(now, 1.0)
	fresh.ammo = 0
	_check(not fresh.dry_fire(now + 500_000), "nor one being drawn")
	_check(fresh.dry_fire(now + 1_000_000), "which clicks once it is out")

	var expected := {
		"weapon_glock": WeaponSounds.CLIP_EMPTY_PISTOL,
		"weapon_deagle": WeaponSounds.CLIP_EMPTY_PISTOL,
		"weapon_usp_silencer": WeaponSounds.CLIP_EMPTY_PISTOL,
		"weapon_ak47": WeaponSounds.CLIP_EMPTY_RIFLE,
		"weapon_mp9": WeaponSounds.CLIP_EMPTY_RIFLE,
		"weapon_nova": WeaponSounds.CLIP_EMPTY_RIFLE,
		"weapon_awp": WeaponSounds.CLIP_EMPTY_RIFLE,
		"weapon_negev": WeaponSounds.CLIP_EMPTY_RIFLE,
		"weapon_knife": "",
		"weapon_taser": "",
		"weapon_hegrenade": "",
	}
	for item_class: String in expected:
		_check_equal(WeaponSounds.dry_fire_event(item_class), expected[item_class], "%s clicks with %s" % [item_class, expected[item_class]])
	for event_name: String in [WeaponSounds.CLIP_EMPTY_PISTOL, WeaponSounds.CLIP_EMPTY_RIFLE]:
		var event := SoundEvents.find(event_name)
		_check(event != null and not event.local_player_only and event.mixgroup == "Foley",
			"%s is in CS2's table, on Foley, heard by everyone near" % event_name)
	var gun_count := 0
	for item: ItemDef in ItemRegistry.guns():
		if item.type != "taser":
			gun_count += 1
			if WeaponSounds.dry_fire_event(item.item_class) == "":
				_check(false, "%s has a dry fire" % item.item_class)
	_check(gun_count > 20, "every gun has a dry fire (%d guns)" % gun_count)


## A player emptying a gun hears the trigger click once it is empty: an
## automatic held past its last round clicks once, a pistol once a press;
## the game sends weapon_fire_on_empty at the tick, and a WeaponSounds
## watching the player starts CS2's dry fire on the next frame.
func _test_the_dry_fire_click() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var world := GameWorld.new()
	holder.add_child(world)
	world.set_physics_process(false)
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.ak47()
	player.team = "T"
	player.collision_layer = 2
	holder.add_child(player)
	player.place(Vector3(0, 0, 0), 0.0)
	player.respawn()
	world.add_player(player)
	var sounds := WeaponSounds.new()
	player.add_child(sounds)
	sounds.set_process(false)
	sounds.watch(player)
	await process_frame
	if player.weapon == null:
		_check(false, "the player holds the AK-47")
		holder.queue_free()
		return
	player.weapon.ammo = 2
	player.weapon.reserve = 0
	var fired: Array[String] = []
	var dry: Array[String] = []
	world.game.events.listen(&"weapon_fire", func(event: GameEvent) -> void: fired.append(String(event.fields["weapon"])))
	world.game.events.listen(&"weapon_fire_on_empty", func(event: GameEvent) -> void: dry.append(String(event.fields["weapon"])))
	player.held = UserCmd.ATTACK
	for i in SimClock.ticks_in(ItemRegistry.item("weapon_ak47").deploy_seconds + 1.0):
		world.step()
	player.held = 0
	world.step()
	_check_equal(fired.size(), 2, "the AK-47 fires its last two rounds")
	_check_equal(dry, ["weapon_ak47"] as Array[String], "then, held, the trigger clicks once")
	_check_equal(sounds.pending_dry_fire(), PackedStringArray(["weapon_ak47"]), "which the view notes")
	sounds._process(0.0)
	_check(sounds.pending_dry_fire().is_empty(), "and starts on the next frame")
	var clicks := sounds.events.voices().filter(func(v: Dictionary) -> bool: return v.event == WeaponSounds.CLIP_EMPTY_RIFLE)
	_check(clicks.size() == 1 and clicks.all(func(v: Dictionary) -> bool: return v.bus == &"Foley"),
		"as CS2's Default.ClipEmpty_Rifle, on Foley (%d)" % clicks.size())
	player.held = UserCmd.ATTACK
	for i in 3:
		world.step()
	player.held = 0
	world.step()
	player.held = UserCmd.ATTACK
	world.step()
	player.held = 0
	world.step()
	_check_equal(dry.size(), 3, "each new pull clicks once more (%s)" % [dry])
	world.game.events.send(&"weapon_fire_on_empty", {"userid": player.userid + 100, "weapon": "weapon_ak47"})
	world.game.events.flush()
	_check_equal(sounds.pending_dry_fire().size(), 2, "another player's click is not this view's")
	world.remove_player(player)
	holder.queue_free()
	await process_frame
