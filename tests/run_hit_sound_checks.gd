extends "res://tests/check_suite.gd"

## Hit feedback chooses the event's own damage/death and armour state,
## queues it outside the tick and lets the authored audio event decide
## children, delays, attenuation and shotgun voice limits.

func _initialize() -> void:
	await process_frame
	_test_recipients()
	_test_authored_parameters()
	await _test_delivery()
	_test_extracted_files()
	_finish("hit-sounds")


func _hurt(health: int = 70, armor_taken: int = 0, group: int = DamageInfo.HITGROUP_CHEST) -> Dictionary:
	return {"userid": 1, "attacker": 0, "weapon": "weapon_ak47", "health": health, "armor": 100, "dmg_armor": armor_taken, "hitgroup": group}


func _test_recipients() -> void:
	for fatal in [false, true]:
		for head in [false, true]:
			for armored in [false, true]:
				var hurt := _hurt(0 if fatal else 70, 3 if armored else 0, DamageInfo.HITGROUP_HEAD if head else DamageInfo.HITGROUP_CHEST)
				var kind := ("Death" if fatal else "Damage") + ("HeadShot" if head else "Body") + ("Armor" if armored else "")
				for listener in [0, 1, 2]:
					var sound := HitSounds.for_hit(hurt, listener)
					var role: String = ["AttackerFeedback", "Victim", "Onlooker"][listener]
					_check_equal(sound.get("event"), "Player.%s.%s" % [kind, role], "each hit selects %s for %s" % [kind, role])
					_check_equal(sound.get("flat"), listener == 1, "only the victim receives their own stereo damage event")
	var own := _hurt()
	own["attacker"] = 1
	_check_equal(HitSounds.for_hit(own, 1).get("role"), "Victim", "self damage cannot play attacker feedback on top of the victim sound")
	for knife in ["weapon_knife", "weapon_knife_karambit", "weapon_bayonet"]:
		var hurt := _hurt(70, 0, DamageInfo.HITGROUP_HEAD)
		hurt["weapon"] = knife
		_check(HitSounds.for_hit(hurt, 0).is_empty(), "a %s's attacker already hears its flesh impact" % knife)
		_check_equal(HitSounds.for_hit(hurt, 2).get("event"), "Player.DamageBody.Onlooker", "a knife cannot generate a headshot dink")
	var fire := _hurt()
	fire["weapon"] = "inferno"
	_check(HitSounds.for_hit(fire, 0).is_empty(), "a burn cannot generate bullet feedback")
	_check(HitSounds.for_hit({"userid": GameEvents.NOBODY}, 0).is_empty(), "no victim produces no hit sound")
	var leg := _hurt(70, 0, DamageInfo.HITGROUP_RIGHT_LEG)
	_check_equal(HitSounds.for_hit(leg, 0).get("event"), "Player.DamageBody.AttackerFeedback", "wearing armour does not make an exposed leg sound like kevlar")
	var broken_armor := _hurt(0, 8)
	broken_armor["armor"] = 0
	_check_equal(HitSounds.for_hit(broken_armor, 0).get("event"), "Player.DeathBodyArmor.AttackerFeedback", "the fatal event retains armour that broke on that hit")


func _test_authored_parameters() -> void:
	var body := SoundEvents.find("Player.DamageBody.AttackerFeedback")
	_check_near(body.volume, 1.0, "attacker body feedback is the authored 1.0")
	_check_near(body.pitch, 1.3, "attacker body feedback is pitched at 1.3")
	_check_near(body.delay, 0.0, "attacker feedback has no artificial delay")
	_check_equal(body.instance_limit, 3, "body feedback keeps the shipped three-voice limit")
	_check(not body.block_matching_events, "the body attacker's block flag permits separate fast hits")
	_check_equal(body.mixgroup, "PlayerAttackerFeedback", "attacker feedback uses its own mix bus")
	_check_near(body.gain(1065.895142), 0.214765, "the distant attacker hears the exact authored attenuation")
	var kevlar := SoundEvents.find("Player.DamageBodyArmor.AttackerFeedback")
	_check_equal(kevlar.files.size(), 8, "kevlar uses exactly the eight current authored variants")
	_check("Player.DamageBodyArmor.AttackerFeedbackFlesh" in kevlar.children, "the kevlar event includes its flesh child")
	_check_near(SoundEvents.find(kevlar.children[0]).delay, 0.1, "the attacker kevlar flesh follows by 0.1 seconds")
	var victim := SoundEvents.find("Player.DamageBody.Victim")
	_check_near(victim.delay, 0.05, "the victim's own body feedback retains its 0.05-second delay")
	_check_near(victim.stereo_at(64.0), 0.9, "the victim retains the authored stereo share")
	var onlooker := SoundEvents.find("Player.DamageBody.Onlooker")
	_check_near(onlooker.gain(1100.0), 0.0, "onlookers cannot hear body feedback beyond 1100 units")
	var helmet_kill := SoundEvents.find("Player.DeathHeadShotArmor.AttackerFeedback")
	_check_near(helmet_kill.volume, 0.0, "the helmeted kill's parent file remains silent")
	_check_equal(helmet_kill.children.size(), 2, "the audible helmet kill is its flesh and dink children")
	_check_near(SoundEvents.find("Player.DeathHeadShot.AttackerFeedback.Dink").pitch, 1.1, "a helmet kill uses the authored dink pitch")


func _test_delivery() -> void:
	# The rules must be testable without an audio driver or extracted files.
	var availability := SoundBank._available
	SoundBank._available = 0
	var game := GameSystems.new()
	var nodes: Array[Node3D] = []
	for i in 3:
		var node := Node3D.new()
		root.add_child(node)
		node.position = Vector3(300.0 * i, 0.0, 0.0)
		game.roster.add(node)
		nodes.append(node)
	var hits := HitSounds.new()
	root.add_child(hits)
	hits.set_process(false)
	hits.events.set_process(false)
	hits.events.silent_length = 100.0
	hits.events.listener = nodes[0]
	hits.watch(game, 0)
	var loads := SoundEvents.late_loads
	game.events.send(&"player_hurt", _hurt())
	game.events.send(&"bullet_damage", {"victim": 1, "attacker": 0, "x": 300.0})
	game.events.flush()
	_check(hits.events.voices().is_empty(), "flushing the tick cannot start audio")
	# A later movement cannot move the impact to the player's new feet.
	nodes[1].position.x = 500.0
	hits._process(0.0)
	var voices := hits.events.voices()
	_check_equal(voices.size(), 1, "player_hurt and bullet_damage together produce one attacker sound")
	_check_equal(voices[0]["event"], "Player.DamageBody.AttackerFeedback", "the attacker's authoritative event is delivered")
	_check_equal(voices[0]["position"], Vector3(300.0, 0.0, 0.0), "the hit source is captured when the event is handed out")
	_check_equal(voices[0]["bus"], &"PlayerAttackerFeedback", "the hit uses CS2's mix bus without a guessed -3 dB offset")
	hits.events.advance(0.2)
	for pellet in 12:
		game.events.send(&"player_hurt", _hurt())
	game.events.flush()
	hits._process(0.0)
	_check_equal(hits.events.voices().size(), 3, "a shotgun's body pellets obey the authored three-voice cap")
	game.events.send(&"player_hurt", _hurt(0, 8, DamageInfo.HITGROUP_HEAD))
	game.events.send(&"player_death", {"userid": 1, "attacker": 0, "weapon": "weapon_ak47"})
	game.events.flush()
	hits._process(0.0)
	voices = hits.events.voices()
	_check_equal(voices.filter(func(v: Dictionary) -> bool: return v["event"] == "Player.DeathHeadShotArmor.AttackerFeedback").size(), 1, "a fatal helmet hit selects its own death event")
	_check_equal(voices.filter(func(v: Dictionary) -> bool: return v["event"] == "Player.DeathHeadShot.AttackerFeedback.Dink").size(), 1, "the fatal helmet hit adds exactly one dink child")
	_check_equal(voices.filter(func(v: Dictionary) -> bool: return v["event"] == HitSounds.DEATH_EVENT).size(), 1, "player_death adds a groan rather than replaying hit feedback")
	_check_equal(SoundEvents.late_loads, loads, "handling hits reads no streams from disk")
	# Rewatch detaches the old source and discards its queued damage.
	game.events.send(&"player_hurt", _hurt())
	game.events.flush()
	var next_game := GameSystems.new()
	hits.watch(next_game, 1)
	_check(hits._pending.is_empty(), "rewatching another game clears old queued feedback")
	game.events.send(&"player_hurt", _hurt())
	game.events.flush()
	_check(hits._pending.is_empty(), "the old game no longer queues sounds")
	next_game.events.send(&"player_hurt", _hurt(70, 3, DamageInfo.HITGROUP_HEAD))
	next_game.events.flush()
	hits._process(0.0)
	voices = hits.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == "Player.DamageHeadShotArmor.Victim")
	_check_equal(voices.size(), 1, "the own victim sound survives a missing roster entry")
	_check_equal(voices[0]["bus"], &"PlayerVictim", "victim damage uses its own mixgroup")
	hits.free()
	next_game.events.send(&"player_hurt", _hurt())
	next_game.events.flush()
	for node in nodes:
		node.free()
	SoundBank._available = availability
	await process_frame


func _test_extracted_files() -> void:
	if not SoundBank.available():
		print("Hit audio extraction absent; skipping playable-stream checks.")
		return
	SoundEvents.load_events(HitSounds.all_events())
	var missing := PackedStringArray()
	for name in SoundEvents.with_children(HitSounds.all_events()):
		for file in SoundEvents.find(name).files:
			if SoundEvents._stream(file) == null and file not in missing:
				missing.append(file)
	_check(missing.is_empty(), "every authored hit/death/burn audio file is extracted: %s" % ", ".join(missing))
	var game := GameSystems.new()
	var source := Node3D.new()
	root.add_child(source)
	game.roster.add(source)
	source.position = Vector3(100.0, 0.0, 0.0)
	var hits := HitSounds.new()
	root.add_child(hits)
	hits.set_process(false)
	hits.events.set_process(false)
	hits.events.listener = source
	hits.watch(game, 0)
	var loads := SoundEvents.late_loads
	var hurt := _hurt()
	hurt["userid"] = 0
	hurt["attacker"] = 1
	game.events.send(&"player_hurt", hurt)
	game.events.flush()
	hits._process(0.0)
	var voices := hits.events.voices()
	_check_equal(voices.size(), 2, "the own body hit includes its authored flesh child")
	_check(voices.all(func(v: Dictionary) -> bool: return not v["started"]), "the victim's 0.05-second delay is scheduled before audio starts")
	hits.events.advance(0.05)
	voices = hits.events.voices()
	_check(voices.all(func(v: Dictionary) -> bool: return v["has_player"] and v["player"] is AudioStreamPlayer3D), "both body layers use the preloaded real streams")
	var victim: Dictionary = voices.filter(func(v: Dictionary) -> bool: return v["event"] == "Player.DamageBody.Victim")[0]
	var player := victim["player"] as AudioStreamPlayer3D
	_check_equal(player.bus, &"PlayerVictim", "real victim audio is on the authored victim bus")
	_check_near(player.panning_strength, 0.1, "the own body hit preserves its authored 90-percent unfiltered stereo")
	_check_near(player.volume_db, linear_to_db(1.5), "there is no extra guessed gain reduction over the authored body hit")
	_check_near(player.attenuation_filter_cutoff_hz, 20500.0, "hit audio does not acquire Godot's default distance low-pass")
	_check_equal(SoundEvents.late_loads, loads, "starting both real layers performs no late disk reads")
	hits.free()
	source.free()
