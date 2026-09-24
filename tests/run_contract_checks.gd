extends "res://tests/check_suite.gd"

## Checks the three contracts every system meets through
## (reference/systems/contracts.md): the game's events, damage that knows who
## dealt it, and items and inventories by CS2 class name; and how entities
## and systems are stepped each tick.
##
##   godot --headless --path . --script tests/run_contract_checks.gd
##
## Needs nothing extracted: every number comes from the committed
## reference/weapons/vdata.csv, and the targets are HitTarget's standard
## boxes.

const SECOND := 1_000_000

const CONTRACT_FILES := [
	"res://src/game/game_event.gd",
	"res://src/game/game_events.gd",
	"res://src/game/damage_info.gd",
	"res://src/game/item_def.gd",
	"res://src/game/item_registry.gd",
	"res://src/game/inventory.gd",
	"res://src/game/sim_entity.gd",
	"res://src/game/sim_entities.gd",
	"res://src/game/roster.gd",
	"res://src/game/sim_tick.gd",
	"res://src/game/game_systems.gd",
]

var _world: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_contracts_read_only_the_simulation()
	_test_events_are_queued_and_handed_out_in_order()
	_test_events_keep_to_the_schema()
	_test_events_sent_while_handing_out()
	_test_the_other_threads_events_are_there()
	_test_round_end_reasons()
	_test_hit_groups()

	_world = Node3D.new()
	root.add_child(_world)
	await physics_frame

	await _test_damage_through_armour()
	await _test_damage_says_who_and_what()
	await _test_blasts_and_falls()
	await _test_the_dead_take_nothing()
	await _test_a_round_carries_its_shooter()

	_test_every_item_is_there()
	_test_items_are_cs2s()
	_test_sides_and_buying()
	_test_every_gun_is_built()
	_test_every_gun_s_first_round_at_a_run()
	_test_weapon_data_is_a_copy()

	_test_starting_items()
	_test_one_gun_a_slot()
	_test_grenade_limits()
	await _test_armour_and_the_kit()
	_test_switching_keeps_the_gun()
	_test_dropped_on_death()
	_test_saving_an_inventory()

	_test_entities_tick_in_order()
	_test_a_tick_runs_entities_systems_then_events()
	await _test_roster()
	_test_queries()
	_test_commands()
	await _test_a_grenade_kill_pays_its_award()
	await _test_dropping_and_picking_up()
	await _test_what_a_death_leaves()
	await _test_the_world_steps_the_game()
	await _test_the_range_s_game()
	_finish("contract")


# --- Events ---------------------------------------------------------------

## Like the rest of the simulation, nothing here keeps the wall clock or
## reads keys.
func _test_the_contracts_read_only_the_simulation() -> void:
	for path in CONTRACT_FILES:
		var text := FileAccess.get_file_as_string(path)
		_check(not text.is_empty(), "%s is there" % path)
		_check(
			not text.contains("Time.get_ticks") and not text.contains("Input."),
			"%s keeps no wall clock and reads no keys" % path.get_file()
		)


func _test_events_are_queued_and_handed_out_in_order() -> void:
	var events := GameEvents.new()
	var heard: Array[String] = []
	var everything: Array[String] = []
	events.listen(&"player_death", func(e: GameEvent) -> void: heard.append("death %d" % e.fields.userid))
	events.listen(&"player_hurt", func(e: GameEvent) -> void: heard.append("hurt %d" % e.fields.userid))
	events.listen_all(func(e: GameEvent) -> void: everything.append(String(e.name)))

	_check(events.send(&"player_hurt", {"userid": 1}), "a known event is taken")
	events.send(&"player_death", {"userid": 1})
	events.send(&"round_end", {"winner": "T"})
	_check(heard.is_empty(), "nothing is handed out before the tick ends")
	_check_equal(events.pending().size(), 3, "three are queued")
	_check_equal(events.flush(), 3, "the flush hands out all three")
	_check_equal(heard, ["hurt 1", "death 1"] as Array[String], "in the order they were sent")
	_check_equal(everything, ["player_hurt", "player_death", "round_end"] as Array[String], "and to whoever hears everything")
	_check(events.pending().is_empty(), "and none is left")
	_check_equal(events.flush(), 0, "a second flush has nothing to hand out")

	var one := func(_e: GameEvent) -> void: heard.append("again")
	events.listen(&"player_jump", one)
	events.unlisten(&"player_jump", one)
	events.send(&"player_jump", {"userid": 2})
	events.flush()
	_check(not heard.has("again"), "a listener that stopped hears nothing")

	events.muted = true
	events.send(&"player_jump", {"userid": 2})
	_check(events.pending().is_empty(), "a muted queue (a tick run again) keeps nothing")


func _test_events_keep_to_the_schema() -> void:
	var events := GameEvents.new()
	var got: Array[GameEvent] = []
	events.listen_all(func(e: GameEvent) -> void: got.append(e))
	events.send(&"player_death", {"userid": 3, "attacker": 1, "weapon": "weapon_ak47"}, 1234)
	events.flush()
	var death := got[0]
	_check_equal(death.fields.assister, GameEvents.NOBODY, "a key left out takes its default: no assister")
	_check_equal(death.fields.headshot, false, "and no headshot")
	_check_equal(death.at_usec, 1234, "an event keeps when in the tick it happened")
	_check_equal(death.fields.size(), (GameEvents.SCHEMA[&"player_death"] as Dictionary).size(), "and has every key the schema gives it")

	_check(not events.send(&"no_such_event"), "an event not in the schema is refused")
	_check(not events.send(&"player_death", {"killer": 1}), "and a key not in its event")
	_check(events.pending().is_empty(), "and neither is queued")

	var plain := true
	for event_name in GameEvents.SCHEMA:
		for key in GameEvents.SCHEMA[event_name]:
			var value = GameEvents.SCHEMA[event_name][key]
			plain = plain and (value is int or value is float or value is bool or value is String)
	_check(plain, "every key is plain data: an int, float, bool or string, never a node")


## A death, then the money for it: a listener's own event is handed out in
## the same flush, after what was already queued.
func _test_events_sent_while_handing_out() -> void:
	var events := GameEvents.new()
	var order: Array[String] = []
	events.listen(&"player_death", func(e: GameEvent) -> void:
		order.append("death")
		events.send(&"round_end", {"winner": "CT"}))
	events.listen(&"round_end", func(_e: GameEvent) -> void: order.append("round_end"))
	events.listen(&"player_hurt", func(_e: GameEvent) -> void: order.append("hurt"))
	events.send(&"player_death", {"userid": 1})
	events.send(&"player_hurt", {"userid": 2})
	_check_equal(events.flush(), 3, "one flush hands out what its listeners sent")
	_check_equal(order, ["death", "hurt", "round_end"] as Array[String], "after what was queued before")

	var endless := GameEvents.new()
	endless.listen(&"player_jump", func(_e: GameEvent) -> void: endless.send(&"player_jump", {"userid": 1}))
	endless.send(&"player_jump", {"userid": 1})
	_check_equal(endless.flush(), GameEvents.MOST_PASSES, "events sending themselves forever stop")


## What the bomb, grenades and buying threads asked for.
func _test_the_other_threads_events_are_there() -> void:
	var wanted := {
		&"bomb_pickup": ["userid"], &"bomb_dropped": ["userid", "entindex"],
		&"bomb_beginplant": ["userid", "site"], &"bomb_abortplant": ["userid", "site"],
		&"bomb_planted": ["userid", "site"], &"bomb_begindefuse": ["userid", "haskit"],
		&"bomb_abortdefuse": ["userid"], &"bomb_defused": ["userid", "site"],
		&"bomb_exploded": ["userid", "site"],
		&"begin_new_match": [], &"round_start": [], &"round_freeze_end": [],
		&"round_end": ["winner", "reason"], &"player_death": ["userid", "attacker", "weapon"],
		&"announce_phase_end": [], &"item_purchase": ["userid", "team", "weapon"],
		&"hegrenade_detonate": ["userid", "entityid", "x", "y", "z"],
		&"flashbang_detonate": ["userid", "entityid"], &"smokegrenade_detonate": ["entityid"],
		&"smokegrenade_expired": ["entityid"], &"molotov_detonate": ["userid", "x"],
		&"inferno_startburn": ["entityid"], &"inferno_expire": ["entityid"],
		&"player_blind": ["userid", "attacker", "blind_duration"], &"grenade_thrown": ["userid", "weapon"],
		&"decoy_started": ["entityid"],
	}
	var missing: Array[String] = []
	for event_name in wanted:
		if not GameEvents.SCHEMA.has(event_name):
			missing.append(String(event_name))
			continue
		for key in wanted[event_name]:
			if not (GameEvents.SCHEMA[event_name] as Dictionary).has(key):
				missing.append("%s.%s" % [event_name, key])
	_check_equal(missing, [] as Array[String], "every event and key the bomb, grenades and money use is in the schema")


func _test_round_end_reasons() -> void:
	_check_equal(GameEvents.round_end_reason(MatchState.Reason.T_ELIMINATED), "CTsWin", "Ts wiped out: CTsWin")
	_check_equal(GameEvents.round_end_reason(MatchState.Reason.CT_ELIMINATED), "TerroristsWin", "CTs wiped out: TerroristsWin")
	_check_equal(GameEvents.round_end_reason(MatchState.Reason.TIME_RAN_OUT), "TargetSaved", "time out: TargetSaved")
	_check_equal(GameEvents.round_end_reason(MatchState.Reason.BOMB_EXPLODED), "TargetBombed", "the bomb: TargetBombed")
	_check_equal(GameEvents.round_end_reason(MatchState.Reason.BOMB_DEFUSED), "BombDefused", "a defuse: BombDefused")


func _test_hit_groups() -> void:
	_check_equal(DamageInfo.hitgroup_of(&"head"), 1, "the head is CS2's hit group 1")
	_check_equal(DamageInfo.hitgroup_of(&"chest"), 2, "the chest 2")
	_check_equal(DamageInfo.hitgroup_of(&"stomach"), 3, "the stomach 3")
	_check_equal(DamageInfo.hitgroup_of(&"arm", &"left"), 4, "the left arm 4")
	_check_equal(DamageInfo.hitgroup_of(&"arm", &"right"), 5, "the right arm 5")
	_check_equal(DamageInfo.hitgroup_of(&"leg", &"left"), 6, "the left leg 6")
	_check_equal(DamageInfo.hitgroup_of(&"leg", &"right"), 7, "the right leg 7")
	_check_equal(DamageInfo.hitgroup_of(&""), 0, "no zone (a blast) is generic, 0")


# --- Damage ---------------------------------------------------------------

func _new_target(at := Vector3.ZERO, team := "CT", armor := 100.0, helmet := true) -> HitTarget:
	var target := HitTarget.new()
	target.build_visual = false
	target.team = team
	_world.add_child(target)
	target.global_position = at
	target.wear(armor, helmet)
	await physics_frame
	return target


func _bullet(amount: float, zone: StringName, armor_penetration := 0.775) -> DamageInfo:
	var info := DamageInfo.new()
	info.damage = amount
	info.zone = zone
	info.damage_type = DamageInfo.DMG_BULLET
	info.armor_penetration = armor_penetration
	info.weapon = "weapon_ak47"
	info.inflictor = "weapon_ak47"
	return info


## The record takes armour exactly as apply_damage always has: an AK-47 to
## an armoured chest keeps 77.5% and wears the armour by half of the rest.
func _test_damage_through_armour() -> void:
	var by_record := await _new_target()
	var by_old_way := await _new_target()
	var info := _bullet(36.0, &"chest")
	var taken := by_record.take_damage(info)
	var old := by_old_way.apply_damage(36.0, &"chest", 0.775)
	_check_near(taken, old, "a record takes what apply_damage took (%.2f)" % old)
	_check_near(by_record.health, by_old_way.health, "and leaves the same health")
	_check_near(by_record.armor, by_old_way.armor, "and the same armour")
	_check_near(info.health_taken, 27.9, "36 through armour takes 27.9 health")
	_check_near(info.armor_taken, 4.05, "and 4.05 armour")
	_check(info.armored and not info.killed, "armour took part, and nobody died")
	_check(by_record.last_damage == info, "the target keeps the last record")

	var legs := await _new_target()
	var leg := _bullet(36.0, &"leg")
	legs.take_damage(leg)
	_check(not leg.armored and is_equal_approx(leg.health_taken, 36.0), "kevlar never covers a leg")

	var bare := await _new_target(Vector3.ZERO, "CT", 100.0, false)
	var head := _bullet(144.0, &"head")
	bare.take_damage(head)
	_check(not head.armored and head.killed, "a head without a helmet takes all of an AK's 144, and dies")
	_check_near(head.health_taken, 100.0, "which takes the 100 it had, not 144")
	for target in [by_record, by_old_way, legs, bare]:
		target.queue_free()


func _test_damage_says_who_and_what() -> void:
	var target := await _new_target(Vector3.ZERO, "CT", 0.0, false)
	target.userid = 7
	var events := GameEvents.new()
	var got: Array[GameEvent] = []
	events.listen_all(func(e: GameEvent) -> void: got.append(e))
	var died := [0]
	target.died.connect(func() -> void: died[0] += 1)

	var first := _bullet(40.0, &"chest")
	first.attacker = 2
	first.origin = Vector3(0.0, 64.0, 500.0)
	first.position = Vector3(0.0, 50.0, 0.0)
	DamageInfo.deal(target, first, events)
	var second := _bullet(144.0, &"head")
	second.attacker = 2
	second.walls = 1
	second.origin = Vector3(0.0, 64.0, 500.0)
	second.position = Vector3(0.0, 66.0, 0.0)
	DamageInfo.deal(target, second, events)
	events.flush()

	_check_equal(got.map(func(e: GameEvent) -> String: return String(e.name)),
		["player_hurt", "player_hurt", "player_death"], "two hurts and a death")
	var hurt := got[0].fields
	_check(hurt.userid == 7 and hurt.attacker == 2 and hurt.weapon == "weapon_ak47",
		"player_hurt says who was hurt, by whom, with what")
	_check(hurt.dmg_health == 40 and hurt.health == 60 and hurt.hitgroup == 2,
		"and how much, what is left and where")
	var death := got[2].fields
	_check(death.userid == 7 and death.attacker == 2 and death.weapon == "weapon_ak47",
		"player_death says who killed whom with what")
	_check(death.headshot and death.hitgroup == 1 and death.penetrated == 1,
		"through a wall, in the head")
	_check_equal(death.dmg_health, 60, "taking the 60 that was left")
	_check_near(death.distance, first.origin.distance_to(second.position), "from how far")
	_check(target.killing_damage == second, "the death keeps its killing record")
	_check_equal(died[0], 1, "and is announced once")
	target.queue_free()


## A blast has no zone and is softened by armour wherever there is some; a
## fall never is.
func _test_blasts_and_falls() -> void:
	var target := await _new_target()
	var blast := DamageInfo.new()
	blast.damage = 60.0
	blast.damage_type = DamageInfo.DMG_BLAST
	blast.armor_penetration = 0.5
	blast.weapon = "weapon_hegrenade"
	blast.inflictor = "hegrenade_projectile"
	target.take_damage(blast)
	_check(blast.armored and is_equal_approx(blast.health_taken, 30.0), "an armoured player takes half an HE's 60")
	_check_equal(blast.hitgroup, 0, "on no hit group")

	var fall := DamageInfo.new()
	fall.damage = 20.0
	fall.damage_type = DamageInfo.DMG_FALL
	fall.inflictor = "worldspawn"
	var armor_before := target.armor
	target.take_damage(fall)
	_check(not fall.armored and is_equal_approx(fall.health_taken, 20.0), "a fall goes straight to health")
	_check_near(target.armor, armor_before, "and leaves the armour alone")
	_check_equal(fall.attacker, GameEvents.NOBODY, "and nobody did it")
	target.queue_free()


func _test_the_dead_take_nothing() -> void:
	var target := await _new_target()
	var events := GameEvents.new()
	DamageInfo.deal(target, _bullet(500.0, &"head", 1.0), events)
	events.flush()
	var after := DamageInfo.deal(target, _bullet(36.0, &"chest"), events)
	_check_equal(after, 0.0, "the dead take no more damage")
	_check(events.pending().is_empty(), "and nobody hears of it")

	var dummy := await _new_target()
	dummy.immortal = true
	var shot := _bullet(500.0, &"head", 1.0)
	DamageInfo.deal(dummy, shot, events)
	_check(not shot.killed and dummy.alive, "the range's dummy takes it all and does not die")
	target.queue_free()
	dummy.queue_free()


## A round goes through the record: fire_as knows who fired it, and says so
## in player_hurt, and says where it landed in bullet_impact. fire_at is the
## same round from nobody.
func _test_a_round_carries_its_shooter() -> void:
	var victim := await _new_target(Vector3(0.0, 0.0, -600.0), "CT", 100.0, true)
	victim.userid = 4
	var data := WeaponLibrary.ak47()
	var shot := Weapon.Shot.new()
	shot.origin = Vector3(0.0, 50.0, 0.0)
	shot.direction = Vector3.FORWARD
	shot.timestamp_usec = 5 * SECOND
	var events := GameEvents.new()
	var got: Array[GameEvent] = []
	events.listen_all(func(e: GameEvent) -> void: got.append(e))
	var space := _world.get_world_3d().direct_space_state
	var result := Hitscan.fire_as(space, shot, data, Hitscan.Shooter.new(1, "T", 1.0, [], events))
	events.flush()
	_check(result.hitbox != null and result.damage_info != null, "the round hits the chest, with a record")
	_check_equal(got.map(func(e: GameEvent) -> String: return String(e.name)),
		["bullet_impact", "player_hurt"], "where it landed, then who it hurt")
	if got.size() == 2:
		_check(got[0].fields.userid == 1 and is_equal_approx(got[0].fields.z, result.position.z),
			"bullet_impact is the shooter's, where the round stopped")
		_check_equal(got[0].at_usec, 5 * SECOND, "at the round's own instant")
		_check(got[1].fields.attacker == 1 and got[1].fields.userid == 4 and got[1].fields.weapon == "weapon_ak47",
			"player_hurt: the shooter hurt the victim with an AK-47")
	_check_equal(result.damage_info.inflictor, "weapon_ak47", "the record names the gun as CS2 does")
	_check(victim.last_hit_weapon == data and victim.last_hit_from == shot.origin,
		"the old last_hit fields are still filled for the player's tagging")

	victim.reset()
	var teammate := Hitscan.fire_as(space, shot, data, Hitscan.Shooter.new(1, "CT", 0.33, [], events))
	_check_near(teammate.damage_info.damage, result.damage_info.damage * 0.33, "a teammate's round does its third")

	victim.reset()
	var from_nobody := Hitscan.fire_at(space, shot, data)
	_check_equal(from_nobody.damage_info.attacker, GameEvents.NOBODY, "fire_at's round is from nobody")
	_check_near(from_nobody.damage, result.damage, "and does what fire_as's did")
	victim.queue_free()
	await physics_frame


# --- Items ----------------------------------------------------------------

func _test_every_item_is_there() -> void:
	_check_equal(ItemRegistry.guns().size(), 34, "all 34 of CS2's guns")
	_check_equal(ItemRegistry.all().size(), 46, "and the knife, the Zeus, six grenades, the C4, kevlar, the suit and the kit")
	var from_vdata := 0
	for weapon_class in WeaponVData.classes():
		if ItemRegistry.has(weapon_class):
			from_vdata += 1
	_check_equal(from_vdata, 43, "every class in weapons.vdata is an item")
	_check(ItemRegistry.item("weapon_ak47") == ItemRegistry.item("weapon_ak47"), "one ItemDef a class, shared")
	_check(ItemRegistry.item("weapon_nope") == null, "and none for a class that is not one")


func _test_items_are_cs2s() -> void:
	var ak := ItemRegistry.item("weapon_ak47")
	_check(ak.price == 2700 and ak.kill_award == 300 and ak.slot == ItemDef.Slot.PRIMARY and ak.type == "rifle",
		"the AK-47: $2,700, $300 a kill, a rifle in the primary slot")
	_check_equal(ak.name, "AK-47", "called the AK-47")
	var awp := ItemRegistry.item("weapon_awp")
	_check(awp.price == 4750 and awp.kill_award == 100 and awp.type == "sniper", "the AWP: $4,750, $100 a kill")
	_check_equal(ItemRegistry.item("weapon_mac10").kill_award, 600, "an SMG pays $600")
	_check_equal(ItemRegistry.item("weapon_p90").kill_award, 300, "but the P90 $300")
	_check_equal(ItemRegistry.item("weapon_nova").kill_award, 900, "a pump shotgun $900")
	_check_equal(ItemRegistry.item("weapon_knife").kill_award, 1500, "the knife $1,500")
	var zeus := ItemRegistry.item("weapon_taser")
	_check(zeus.price == 200 and zeus.slot == ItemDef.Slot.KNIFE and zeus.slot_position == 1 and zeus.buyable,
		"the Zeus: $200, beside the knife")
	var glock := ItemRegistry.item("weapon_glock")
	_check(glock.price == 200 and glock.slot == ItemDef.Slot.PISTOL, "the Glock-18: a $200 pistol")
	_check(ItemRegistry.item("weapon_flashbang").max_carried == 2 and ItemRegistry.item("weapon_hegrenade").max_carried == 1,
		"two flashbangs, one HE")
	_check(ItemRegistry.item("weapon_molotov").grenade_group == ItemRegistry.item("weapon_incgrenade").grenade_group
		and not ItemRegistry.item("weapon_molotov").grenade_group.is_empty(), "the molotov and incendiary share a place")
	var prices := [
		["weapon_hegrenade", 300], ["weapon_flashbang", 200], ["weapon_smokegrenade", 300],
		["weapon_molotov", 400], ["weapon_incgrenade", 500], ["weapon_decoy", 50],
		["item_kevlar", 650], ["item_assaultsuit", 1000], ["item_defuser", 400],
	]
	for pair in prices:
		_check_equal(ItemRegistry.item(pair[0]).price, pair[1], "%s costs $%d" % pair)
	var c4 := ItemRegistry.item("weapon_c4")
	_check(c4.slot == ItemDef.Slot.C4 and not c4.buyable and c4.droppable and c4.team == "T",
		"the C4: the fifth slot, not for sale, dropped, the Ts'")
	var knife := ItemRegistry.item("weapon_knife")
	_check(not knife.buyable and not knife.droppable, "the knife is neither bought nor dropped")
	_check(ItemRegistry.item("weapon_m4a1_silencer").silenced_by_default and ItemRegistry.item("weapon_usp_silencer").silenced_by_default,
		"the M4A1-S and USP-S come silenced")


func _test_sides_and_buying() -> void:
	var t_buys: Array[String] = []
	for def in ItemRegistry.buyable("T"):
		t_buys.append(def.item_class)
	var ct_buys: Array[String] = []
	for def in ItemRegistry.buyable("CT"):
		ct_buys.append(def.item_class)
	_check(t_buys.has("weapon_ak47") and not t_buys.has("weapon_m4a1"), "a T buys the AK-47, not the M4A4")
	_check(ct_buys.has("weapon_m4a1_silencer") and not ct_buys.has("weapon_galilar"), "a CT the M4A1-S, not the Galil")
	_check(t_buys.has("weapon_molotov") and not t_buys.has("weapon_incgrenade"), "a T the molotov")
	_check(ct_buys.has("weapon_incgrenade") and ct_buys.has("item_defuser") and not t_buys.has("item_defuser"),
		"a CT the incendiary and the kit")
	_check(t_buys.has("weapon_awp") and ct_buys.has("weapon_awp") and t_buys.has("weapon_deagle"), "both the AWP and the Deagle")
	_check(not t_buys.has("weapon_c4") and not t_buys.has("weapon_knife"), "nobody buys the C4 or a knife")
	_check_equal(ct_buys.size() - t_buys.size(), 3,
		"the CTs' list is three longer: their 12 against the Ts' 9 (nobody buys the C4)")


## Weapons TODO R1: every gun from the game's numbers, by class name.
func _test_every_gun_is_built() -> void:
	var wrong: Array[String] = []
	var semi := 0
	for def in ItemRegistry.guns():
		var data := ItemRegistry.weapon_data(def.item_class)
		var alternate := def.silenced_by_default
		var magazine := int(WeaponVData.number(def.item_class, "m_iMaxClip1", alternate))
		if (
			data == null or data.item_class != def.item_class or data.display_name.is_empty()
			or data.magazine_size != magazine
			or not is_equal_approx(data.base_damage, WeaponVData.number(def.item_class, "m_nDamage", alternate))
			or data.model_path.is_empty() or data.clip_set.is_empty() or data.world_clip_set.is_empty()
			or is_nan(data.inaccuracy_moving) or data.cycle_time <= 0.0
		):
			wrong.append(def.item_class)
		if data != null and not data.automatic:
			semi += 1
	_check_equal(wrong, [] as Array[String], "every gun is built with the game's damage and magazine, a name, a model and clips")
	_check_equal(semi, 13, "13 of them fire one round a click, as R2 found")
	var mp9 := ItemRegistry.weapon_data("weapon_mp9")
	_check(mp9.display_name == "MP9" and mp9.clip_set == "rifle/rifle_mp9", "the MP9 is its own gun, with its own clips")
	_check(WeaponLibrary.build("weapon_knife") == null, "the knife is not a gun")
	_check_equal(WeaponLibrary.all().size(), 34, "WeaponLibrary.all() is all 34")


## Weapons TODO R1: every gun's first round at a run lands in its running
## cone, never outside it.
func _test_every_gun_s_first_round_at_a_run() -> void:
	var outside: Array[String] = []
	for def in ItemRegistry.guns():
		var data := ItemRegistry.weapon_data(def.item_class)
		var running := Weapon.ShooterState.new(data.max_player_speed, true, false)
		for i in 20:
			var weapon := Weapon.new(data)
			weapon.spray_seed = i + 1
			var shot := weapon.fire(10 * SECOND + i * 7919, 0.0, Vector3.ZERO, 0.0, 0.0, running)
			if shot == null:
				outside.append("%s fired nothing" % def.item_class)
				break
			var off := rad_to_deg(PlayerInput.aim_direction(0.0, 0.0).angle_to(shot.direction))
			if off > shot.inaccuracy + 0.0001 or shot.inaccuracy <= data.inaccuracy_standing:
				outside.append("%s %.2f in %.2f" % [def.item_class, off, shot.inaccuracy])
				break
	_check_equal(outside, [] as Array[String],
		"every gun's first round at a run lands inside its running cone, which running has opened")


func _test_weapon_data_is_a_copy() -> void:
	var one := ItemRegistry.weapon_data("weapon_deagle")
	one.base_damage = 1.0
	var two := ItemRegistry.weapon_data("weapon_deagle")
	_check(two.base_damage > 1.0, "changing one WeaponData leaves the next one handed out alone")


# --- Inventories ----------------------------------------------------------

func _test_starting_items() -> void:
	var t := Inventory.new()
	t.give_starting_items("T")
	_check(t.has("weapon_knife") and t.has("weapon_glock"), "a T starts with the knife and the Glock-18")
	_check_equal(t.in_hand_class(), "weapon_glock", "with the Glock in hand")
	var ct := Inventory.new()
	ct.give_starting_items("CT")
	_check(ct.has("weapon_usp_silencer") and ct.in_hand_class() == "weapon_usp_silencer", "a CT with the USP-S")
	_check_equal(ct.in_hand().weapon.ammo, ct.in_hand().weapon.data.magazine_size, "loaded")


func _test_one_gun_a_slot() -> void:
	var inv := Inventory.new()
	inv.give_starting_items("T")
	_check_equal(inv.can_add("weapon_ak47"), Inventory.Can.OK, "an empty primary slot takes an AK-47")
	_check(inv.add("weapon_ak47").is_empty(), "replacing nothing")
	_check_equal(inv.can_add("weapon_ak47"), Inventory.Can.FULL, "nobody carries two of a gun")
	_check_equal(inv.can_add("weapon_awp"), Inventory.Can.REPLACES, "an AWP would replace it")
	inv.select("weapon_ak47")
	inv.in_hand().weapon.ammo = 7
	var replaced := inv.add("weapon_awp")
	_check(replaced.size() == 1 and replaced[0].item.item_class == "weapon_ak47" and replaced[0].weapon.ammo == 7,
		"and hands back the AK-47, with its 7 rounds, to be dropped")
	_check_equal(inv.in_hand_class(), "weapon_awp", "the AWP takes the AK's place in hand")
	_check_equal(inv.add("weapon_deagle").map(func(e: Inventory.Entry) -> String: return e.item_class()),
		["weapon_glock"], "a Deagle replaces the Glock")
	_check_equal(inv.can_add("weapon_c4"), Inventory.Can.OK, "the C4 goes in its own slot")
	inv.add("weapon_c4")
	_check_equal(inv.can_add("weapon_c4"), Inventory.Can.FULL, "one C4")
	_check_equal(inv.can_add("weapon_nope"), Inventory.Can.UNKNOWN, "no such item")
	var picked_up := Weapon.new(ItemRegistry.weapon_data("weapon_mp9"))
	picked_up.ammo = 3
	var inv2 := Inventory.new()
	inv2.add("weapon_mp9", picked_up)
	_check(inv2.item_in(ItemDef.Slot.PRIMARY).weapon == picked_up, "a picked-up gun is the same gun, 3 rounds and all")


func _test_grenade_limits() -> void:
	var inv := Inventory.new()
	inv.add("weapon_flashbang")
	inv.add("weapon_flashbang")
	_check_equal(inv.count("weapon_flashbang"), 2, "two flashbangs")
	_check_equal(inv.can_add("weapon_flashbang"), Inventory.Can.FULL, "not three")
	inv.add("weapon_molotov")
	_check_equal(inv.can_add("weapon_incgrenade"), Inventory.Can.FULL, "a molotov leaves no room for an incendiary")
	inv.add("weapon_hegrenade")
	_check_equal(inv.grenade_count(), 4, "four grenades")
	_check_equal(inv.can_add("weapon_smokegrenade"), Inventory.Can.FULL, "and a fifth is one too many")
	_check(inv.take_one("weapon_flashbang") and inv.count("weapon_flashbang") == 1, "a throw takes one")
	_check_equal(inv.can_add("weapon_smokegrenade"), Inventory.Can.OK, "which makes room")
	_check(inv.take_one("weapon_hegrenade") and not inv.has("weapon_hegrenade"), "the last HE thrown is gone")
	_check(not inv.take_one("weapon_hegrenade"), "and none is left to throw")

	inv.add("weapon_smokegrenade")
	inv.select("weapon_flashbang")
	_check(inv.select_slot(ItemDef.Slot.GRENADE) and inv.in_hand_class() != "weapon_flashbang",
		"4 again moves on to the next grenade (%s)" % inv.in_hand_class())
	var seen := {}
	for i in 3:
		seen[inv.in_hand_class()] = true
		inv.select_slot(ItemDef.Slot.GRENADE)
	_check_equal(seen.size(), 3, "and cycles through all three kinds")


func _test_armour_and_the_kit() -> void:
	var bare := Inventory.new()
	_check_equal(bare.can_add("item_kevlar"), Inventory.Can.OK, "no armour: kevlar")
	bare.add("item_kevlar")
	_check(is_equal_approx(bare.armor, 100.0) and not bare.helmet, "kevlar is 100 armour and no helmet")
	_check_equal(bare.can_add("item_kevlar"), Inventory.Can.FULL, "full kevlar takes no more")
	_check_equal(bare.can_add("item_assaultsuit"), Inventory.Can.OK, "but the suit adds the helmet")
	bare.add("item_assaultsuit")
	_check(bare.helmet and bare.has("item_assaultsuit"), "and does")
	_check(bare.entries().is_empty(), "armour is worn, not carried in a slot")

	var body := await _new_target(Vector3.ZERO, "CT", 0.0, false)
	var inv := Inventory.new(3, body)
	inv.add("item_assaultsuit")
	_check(is_equal_approx(body.armor, 100.0) and body.helmet, "the armour bought is the armour on the player's body")
	body.take_damage(_bullet(36.0, &"chest"))
	_check_near(inv.armor, body.armor, "and damage wears the one value both read (%.2f)" % inv.armor)
	_check_equal(inv.can_add("item_kevlar"), Inventory.Can.OK, "worn armour can be topped up")

	_check_equal(inv.can_add("item_defuser"), Inventory.Can.OK, "a kit")
	inv.add("item_defuser")
	_check(inv.has_defuser and inv.can_add("item_defuser") == Inventory.Can.FULL, "one kit")
	_check(inv.remove("item_defuser") != null and not inv.has_defuser, "undone, it is gone")
	body.queue_free()


func _test_switching_keeps_the_gun() -> void:
	var inv := Inventory.new()
	inv.give_starting_items("CT")
	inv.add("weapon_m4a1_silencer")
	inv.select("weapon_m4a1_silencer")
	var m4 := inv.in_hand().weapon
	m4.ammo = 11
	_check(inv.select_slot(ItemDef.Slot.PISTOL) and inv.in_hand_class() == "weapon_usp_silencer", "2 takes the pistol")
	_check(inv.select_last() and inv.in_hand().weapon == m4 and m4.ammo == 11, "Q takes back the same M4, 11 rounds in it")
	_check(inv.select_slot(ItemDef.Slot.KNIFE) and inv.in_hand_class() == "weapon_knife", "3 the knife")
	_check(not inv.select("weapon_awp"), "a gun not carried cannot be taken out")
	inv.select("weapon_m4a1_silencer")
	inv.remove("weapon_m4a1_silencer")
	_check_equal(inv.in_hand_class(), "weapon_knife", "dropping what is in hand goes back to what was before it")


func _test_dropped_on_death() -> void:
	var inv := Inventory.new()
	inv.give_starting_items("T")
	for item_class in ["weapon_ak47", "weapon_flashbang", "weapon_smokegrenade", "weapon_hegrenade", "weapon_taser", "weapon_c4", "item_assaultsuit"]:
		inv.add(item_class)
	var dropped := inv.drops_on_death().map(func(e: Inventory.Entry) -> String: return e.item_class())
	_check_equal(dropped, ["weapon_ak47", "weapon_hegrenade", "weapon_taser"],
		"a death drops the best gun, the best grenade and the Zeus")
	_check(inv.has("weapon_c4"), "but leaves the C4 for the bomb to drop")
	_check(inv.has("weapon_glock") and inv.has("weapon_flashbang"), "the pistol and the rest stay, to go with strip()")

	var holding := Inventory.new()
	holding.add("weapon_flashbang")
	holding.add("weapon_hegrenade")
	holding.add("item_defuser")
	holding.select("weapon_flashbang")
	_check_equal(holding.drops_on_death().map(func(e: Inventory.Entry) -> String: return e.item_class()),
		["weapon_flashbang", "item_defuser"], "the grenade in hand falls rather than the best, and the kit")
	inv.strip()
	_check(inv.entries().is_empty() and inv.armor == 0.0 and not inv.helmet and inv.in_hand() == null,
		"stripped, nothing is left")


func _test_saving_an_inventory() -> void:
	var inv := Inventory.new()
	inv.give_starting_items("CT")
	inv.add("weapon_awp")
	inv.add("weapon_flashbang")
	inv.add("weapon_flashbang")
	inv.add("item_defuser")
	inv.add("item_kevlar")
	inv.select("weapon_awp")
	inv.in_hand().weapon.ammo = 2
	inv.select("weapon_knife")
	var saved := inv.save_state()
	var back := Inventory.new()
	back.load_state(saved)
	_check_equal(back.save_state(), saved, "an inventory saved and loaded is the same inventory")
	_check(back.item_in(ItemDef.Slot.PRIMARY).weapon.ammo == 2 and back.count("weapon_flashbang") == 2,
		"the AWP with its 2 rounds, both flashbangs")
	_check(back.in_hand_class() == "weapon_knife" and back.select_last() and back.in_hand_class() == "weapon_awp",
		"the knife in hand, and the AWP before it")
	var bought_first := Inventory.new()
	bought_first.add("weapon_flashbang")
	bought_first.add("weapon_knife")
	bought_first.add("weapon_awp")
	_check_equal(bought_first.entries().map(func(e: Inventory.Entry) -> String: return e.item_class()),
		["weapon_awp", "weapon_knife", "weapon_flashbang"], "entries are in slot order, whatever order they came in")


# --- Entities and systems -------------------------------------------------

## A thing that counts its ticks and writes them down, for the order.
class Counter:
	extends SimEntity
	var record: Array
	var ticks: int = 0
	var spawns_child: SimEntities

	func tick(_t: SimTick) -> void:
		ticks += 1
		position += Vector3.RIGHT
		record.append("%s %d" % [entity_class, id])
		if spawns_child != null:
			spawns_child.spawn(Counter.new("child"))
			spawns_child = null


func _test_entities_tick_in_order() -> void:
	var game := GameSystems.new()
	var order := []
	var a := Counter.new("a")
	a.record = order
	var b := Counter.new("b")
	b.record = order
	b.spawns_child = game.entities
	var gone := [] as Array[int]
	game.entities.removed.connect(func(e: SimEntity) -> void: gone.append(e.id))
	_check_equal(game.entities.spawn(a), 1, "the first entity is 1")
	_check_equal(game.entities.spawn(b), 2, "the next 2")
	game.step(10)
	_check_equal(order, ["a 1", "b 2"], "they run in the order they were spawned")
	_check_equal(game.entities.size(), 3, "one spawned in a tick is there after it")
	var child: Counter = game.entities.of_class("child")[0]
	_check_equal(child.ticks, 0, "but first runs on the next tick")
	child.record = order
	a.remove()
	_check(game.entities.find(1) == null, "one removed is not found")
	game.step(11)
	_check_equal(order.slice(2), ["b 2", "child 3"], "and does not run")
	_check_equal(gone, [1] as Array[int], "and is let go, which presenters hear")
	_check(b.previous_position == Vector3.RIGHT and b.position == Vector3.RIGHT * 2.0,
		"each keeps where the tick before left it, for drawing between")
	game.entities.clear()
	_check_equal(game.entities.size(), 0, "a round's start clears them all")

	var saved := b.save_state()
	var copy := Counter.new()
	copy.load_state(saved)
	_check(copy.id == b.id and copy.position == b.position and copy.entity_class == "b", "an entity saves and loads as plain data")


## A system that listens for deaths and writes down what it hears.
class Listener:
	var heard: Array = []
	var ticked: Array = []
	var game: GameSystems

	func attach(p_game: GameSystems) -> void:
		game = p_game
		game.events.listen(&"player_death", func(e: GameEvent) -> void: heard.append(e.fields.userid))

	func tick(t: SimTick) -> void:
		ticked.append(t.tick)
		heard.append("tick")


## A thing that sends a death on its first tick.
class Killer:
	extends SimEntity
	func tick(t: SimTick) -> void:
		if t.tick == 20:
			t.events.send(&"player_death", {"userid": 9})


func _test_a_tick_runs_entities_systems_then_events() -> void:
	var game := GameSystems.new()
	var listener := Listener.new()
	game.add_system(listener)
	game.entities.spawn(Killer.new("killer"))
	var t := game.step(20)
	_check_equal(listener.heard, ["tick", 9], "a step runs the entities, then the systems, then hands out the events")
	_check(t.now_usec == SimClock.tick_end_usec(20) and t.start_usec == SimClock.tick_start_usec(20),
		"the tick covers its own stretch of simulation time")
	_check(game.events.pending().is_empty(), "and leaves nothing queued")
	_check_equal(game.systems().size(), 2, "the items' own system and this one")


func _test_roster() -> void:
	var game := GameSystems.new()
	var t_player := Node3D.new()
	t_player.set_meta(&"x", 1)
	var t_body := await _new_target(Vector3.ZERO, "T")
	var ct_player := _Sided.new()
	ct_player.team = "CT"
	var ct_body := await _new_target(Vector3.ZERO, "CT")
	var first := game.add_player(t_player, t_body)
	var second := game.add_player(ct_player, ct_body)
	_check(first == 0 and second == 1, "players are 0 and 1 in the order they join")
	_check(t_body.userid == 0 and ct_body.userid == 1, "and their hit targets know it")
	_check_equal(game.add_player(t_player, t_body), 0, "adding someone twice keeps their userid")
	_check(game.roster.player(1) == ct_player and game.roster.userid_of(ct_player) == 1, "found either way")
	_check_equal(game.roster.team_of(1), "CT", "their side comes from them")
	_check_equal(game.roster.on_team("CT"), [1] as Array[int], "and a side's players")
	_check(game.inventory(1) != null and game.inventory(1).body == ct_body, "each has an inventory, wearing their armour")
	_check(game.inventory(5) == null, "nobody else does")
	t_player.free()
	ct_player.free()
	t_body.queue_free()
	ct_body.queue_free()


class _Sided:
	extends Node3D
	var team: String = ""


func _test_queries() -> void:
	var game := GameSystems.new()
	_check_equal(game.query(&"smoke_length_between", [Vector3.ZERO, Vector3.ONE], 0.0), 0.0,
		"with no grenades, nothing is smoked")
	_check(not game.provides(&"smoke_length_between"), "and nothing answers")
	game.provide(&"smoke_length_between", func(from: Vector3, to: Vector3) -> float: return from.distance_to(to) * 0.5)
	_check_near(game.query(&"smoke_length_between", [Vector3.ZERO, Vector3(0, 0, 100)], 0.0), 50.0,
		"the one who knows answers")


## The contracts together: an HE thrown by a T kills a CT through a
## DamageInfo, and a money system that knows nothing of grenades pays the
## thrower the HE's kill award from the registry.
class Blast:
	extends SimEntity
	var target_id: int

	func tick(t: SimTick) -> void:
		var info := DamageInfo.new()
		info.attacker = owner_id
		info.inflictor = entity_class
		info.weapon = "weapon_hegrenade"
		info.damage = 200.0
		info.damage_type = DamageInfo.DMG_BLAST
		info.armor_penetration = 0.5
		info.origin = position
		info.position = t.roster.hit_target(target_id).global_position
		t.events.send(&"hegrenade_detonate", {"userid": owner_id, "entityid": id})
		DamageInfo.deal(t.roster.hit_target(target_id), info, t.events)
		remove()


class Money:
	var accounts := {}

	func attach(game: GameSystems) -> void:
		game.events.listen(&"player_death", func(e: GameEvent) -> void:
			var item := ItemRegistry.item(e.fields.weapon)
			accounts[e.fields.attacker] = accounts.get(e.fields.attacker, 800) + (item.kill_award if item != null else 0))

	func tick(_t: SimTick) -> void:
		pass


func _test_a_grenade_kill_pays_its_award() -> void:
	var game := GameSystems.new()
	var money := Money.new()
	game.add_system(money)
	var thrower := _Sided.new()
	thrower.team = "T"
	var victim := _Sided.new()
	victim.team = "CT"
	var victim_body := await _new_target(Vector3(0.0, 0.0, -100.0), "CT")
	var thrower_id := game.add_player(thrower, null)
	var victim_id := game.add_player(victim, victim_body)
	var heard: Array[String] = []
	game.events.listen_all(func(e: GameEvent) -> void: heard.append(String(e.name)))
	var blast := Blast.new("hegrenade_projectile", thrower_id, Vector3.ZERO)
	blast.target_id = victim_id
	game.entities.spawn(blast)
	game.step(30)
	_check_equal(heard, ["hegrenade_detonate", "player_hurt", "player_death"], "the HE goes off, hurts and kills")
	_check_equal(money.accounts.get(thrower_id, 0), 800 + 300, "and the thrower is paid the HE's $300")
	_check(victim_body.killing_damage.attacker == thrower_id and victim_body.killing_damage.weapon == "weapon_hegrenade",
		"the dead CT knows who threw it")
	_check_equal(game.entities.size(), 0, "and the grenade is gone")
	thrower.free()
	victim.free()
	victim_body.queue_free()


func _test_commands() -> void:
	var game := GameSystems.new()
	var taken: Array[String] = []
	game.on_command(&"buy", func(userid: int, args: PackedStringArray, _t: SimTick) -> bool:
		taken.append("%d buys %s" % [userid, " ".join(args)])
		return true)
	game.on_command(&"buy", func(_u: int, _a: PackedStringArray, _t: SimTick) -> bool:
		taken.append("second")
		return true)
	game.command(3, "buy ak47")
	game.command(3, "nonsense")
	_check(taken.is_empty(), "a command waits for the next tick")
	game.step(40)
	_check_equal(taken, ["3 buys ak47"] as Array[String], "and is run by the first handler that takes it, and only it")
	game.step(41)
	_check_equal(taken.size(), 1, "once")


## A floor on the world's layer, for things to fall onto.
func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4096.0, 16.0, 4096.0)
	shape.shape = box
	shape.position = Vector3(0.0, -8.0, 0.0)
	body.add_child(shape)
	_world.add_child(body)
	return body


class _Player:
	extends Node3D
	var team: String = "T"
	var alive: bool = true
	var yaw_degrees: float = 0.0
	var velocity := Vector3.ZERO


func _new_player(game: GameSystems, team: String, at: Vector3) -> int:
	var node := _Player.new()
	node.team = team
	_world.add_child(node)
	node.global_position = at
	var body := await _new_target(at, team)
	return game.add_player(node, body)


## Steps game until nothing is falling, at most a few seconds' worth.
func _settle(game: GameSystems, tick: int) -> int:
	var space := _world.get_world_3d().direct_space_state
	for i in 64 * 3:
		game.step(tick, space)
		tick += 1
		var falling := false
		for entity in game.entities.all():
			if entity is DroppedItem and not (entity as DroppedItem).resting:
				falling = true
		if not falling:
			break
	return tick


func _test_dropping_and_picking_up() -> void:
	var floor_body := _floor()
	await physics_frame
	var game := GameSystems.new()
	var heard: Array[String] = []
	game.events.listen_all(func(e: GameEvent) -> void: heard.append(String(e.name)))
	var dropper := await _new_player(game, "T", Vector3.ZERO)
	var taker := await _new_player(game, "CT", Vector3(0.0, 0.0, 2000.0))
	var inv := game.inventory(dropper)
	inv.give_starting_items("T")
	inv.add("weapon_ak47")
	inv.select("weapon_ak47")
	var ak := inv.in_hand().weapon
	ak.ammo = 13
	var tick := 1000

	game.command(dropper, "drop")
	tick = _settle(game, tick)
	var lying := game.entities.of_class("weapon_ak47")
	_check_equal(lying.size(), 1, "drop throws the gun in hand to the ground")
	_check(not inv.has("weapon_ak47") and inv.in_hand_class() == "weapon_glock", "and the pistol comes out")
	_check(heard.has("item_remove"), "item_remove says so")
	if lying.is_empty():
		floor_body.queue_free()
		return
	var gun := lying[0] as DroppedItem
	_check(gun.resting and absf(gun.position.y) < 0.5, "it falls to the floor and lies there")
	_check(gun.position.z < -40.0, "thrown forward, the way the player faced (%.0f units)" % -gun.position.z)

	# The dropper stands on it; the other player too. Nobody takes it until
	# CS2's 1.3 s have passed, and then the other player does, at the first
	# pickup check.
	var space := _world.get_world_3d().direct_space_state
	game.roster.player(dropper).global_position = gun.position
	game.roster.player(taker).global_position = gun.position
	var taker_inv := game.inventory(taker)
	while SimClock.tick_end_usec(tick) < gun.dropped_usec + DroppedItem.NEXT_OWNER_TOUCH_USEC:
		game.step(tick, space)
		tick += 1
	_check(not taker_inv.has("weapon_ak47") and not inv.has("weapon_ak47"),
		"nobody takes it in its first 1.3 s (mp_weapon_next_owner_touch_time)")
	game.step(tick, space)
	tick += 1
	_check(not inv.has("weapon_ak47"), "whoever dropped it does not take it straight back")
	_check(taker_inv.has("weapon_ak47") and taker_inv.item_in(ItemDef.Slot.PRIMARY).weapon == ak,
		"someone walking over it takes it once 1.3 s have passed, the same gun")
	_check_equal(ak.ammo, 13, "with the 13 rounds it had")
	_check(heard.has("item_pickup") and game.entities.of_class("weapon_ak47").is_empty(), "item_pickup, and it is gone from the ground")

	game.roster.player(dropper).global_position = Vector3(0.0, 0.0, 3000.0)
	var full := game.inventory(taker)
	full.select("weapon_ak47")
	game.command(taker, "drop")
	tick = _settle(game, tick)
	var again := game.entities.of_class("weapon_ak47")[0] as DroppedItem
	full.add("weapon_awp")
	game.roster.player(taker).global_position = again.position
	for i in 70:
		game.step(tick, _world.get_world_3d().direct_space_state)
		tick += 1
	_check(not full.has("weapon_ak47") and game.entities.of_class("weapon_ak47").size() == 1,
		"walking over a gun whose slot is full leaves it lying")

	# Alone on what they dropped, the dropper takes it back after 1.5 s, at
	# the next pickup check, 0.25 s after the first.
	game.roster.player(taker).global_position = Vector3(0.0, 0.0, 2000.0)
	game.roster.player(dropper).global_position = Vector3.ZERO
	inv.select("weapon_glock")
	game.command(dropper, "drop")
	tick = _settle(game, tick)
	var pistol := game.entities.of_class("weapon_glock")[0] as DroppedItem
	game.roster.player(dropper).global_position = pistol.position
	while SimClock.tick_end_usec(tick) < pistol.dropped_usec + DroppedItem.PREV_OWNER_TOUCH_USEC:
		game.step(tick, space)
		tick += 1
	_check(not inv.has("weapon_glock"), "whoever dropped it waits 1.5 s (mp_weapon_prev_owner_touch_time)")
	var checks_after := 0
	while not inv.has("weapon_glock") and checks_after < 64:
		game.step(tick, space)
		tick += 1
		checks_after += 1
	_check(inv.has("weapon_glock") and SimClock.tick_end_usec(tick - 1) - pistol.dropped_usec
			<= DroppedItem.NEXT_OWNER_TOUCH_USEC + 2 * ItemDrops.PICKUP_CHECK_PERIOD_USEC,
		"and then takes it back at a pickup check, every 0.25 s (pickup_check_period)")

	inv.add("weapon_flashbang")
	inv.select("weapon_flashbang")
	game.command(dropper, "drop")
	game.step(tick)
	tick += 1
	_check(not inv.has("weapon_flashbang") and game.entities.of_class("weapon_flashbang").size() == 1,
		"a grenade in hand can be dropped (mp_drop_grenade_enable)")

	inv.select("weapon_knife")
	game.command(dropper, "drop")
	game.step(tick)
	tick += 1
	_check(inv.has("weapon_knife"), "the knife is never dropped (mp_drop_knife_enable)")

	inv.add("weapon_c4")
	inv.select("weapon_c4")
	var bomb_took := [false]
	game.on_command(&"drop", func(userid: int, _a: PackedStringArray, _t: SimTick) -> bool:
		if game.inventory(userid).in_hand_class() != "weapon_c4":
			return false
		bomb_took[0] = true
		return true)
	game.command(dropper, "drop")
	game.step(tick)
	_check(bomb_took[0] and inv.has("weapon_c4") and game.entities.of_class("weapon_c4").is_empty(),
		"with the C4 in hand, drop is the bomb's, not the items'")
	for userid in game.roster.ids():
		game.roster.player(userid).queue_free()
		game.roster.hit_target(userid).queue_free()
	floor_body.queue_free()
	await physics_frame


func _test_what_a_death_leaves() -> void:
	var floor_body := _floor()
	await physics_frame
	var game := GameSystems.new()
	var heard: Array[String] = []
	game.events.listen_all(func(e: GameEvent) -> void: heard.append(String(e.name)))
	var ct := await _new_player(game, "CT", Vector3.ZERO)
	var t_player := await _new_player(game, "T", Vector3(0.0, 0.0, 3000.0))
	var inv := game.inventory(ct)
	inv.give_starting_items("CT")
	inv.add("weapon_m4a1")
	inv.add("weapon_smokegrenade")
	inv.add("item_defuser")
	var killing := _bullet(500.0, &"head", 1.0)
	killing.attacker = t_player
	game.roster.player(ct).alive = false
	DamageInfo.deal(game.roster.hit_target(ct), killing, game.events)
	var tick := _settle(game, 2000)
	var left: Array[String] = []
	for entity in game.entities.all():
		left.append(entity.entity_class)
	left.sort()
	_check_equal(left, ["item_defuser", "weapon_m4a1", "weapon_smokegrenade"] as Array[String],
		"a dead CT leaves the M4A4, the smoke and the kit on the ground")
	_check(heard.has("defuser_dropped"), "and defuser_dropped says so")

	var space := _world.get_world_3d().direct_space_state
	var kit := game.entities.of_class("item_defuser")[0] as DroppedItem
	game.roster.player(t_player).global_position = kit.position
	for i in 64 * 2:
		game.step(tick, space)
		tick += 1
	_check(not game.inventory(t_player).has_defuser and game.entities.of_class("item_defuser").size() == 1,
		"a T walks over the kit and leaves it")
	var other_ct := await _new_player(game, "CT", kit.position)
	game.roster.player(t_player).global_position = Vector3(0.0, 0.0, 3000.0)
	@warning_ignore("integer_division")
	for i in ItemDrops.PICKUP_CHECK_PERIOD_USEC / SimClock.tick_usec() + 1:
		game.step(tick, space)
		tick += 1
	_check(game.inventory(other_ct).has_defuser and game.entities.of_class("item_defuser").is_empty()
			and heard.has("defuser_pickup"),
		"a CT walks over it and has a kit (defuser_pickup)")
	game.events.send(&"round_prestart", {})
	game.step(tick, space)
	var lying := 0
	for entity in game.entities.all():
		if entity is DroppedItem:
			lying += 1
	_check_equal(lying, 0, "and the next round's round_prestart clears the ground")
	for userid in game.roster.ids():
		game.roster.player(userid).queue_free()
		game.roster.hit_target(userid).queue_free()
	floor_body.queue_free()
	await physics_frame


## The GameWorld owns the game: its players are on the roster, and every
## tick it runs the players, the match, then the game's systems and events.
func _test_the_world_steps_the_game() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	var listener := Listener.new()
	world.game.add_system(listener)
	var player := (load("res://src/player/player_sim.gd") as GDScript).new() as PlayerSim
	_world.add_child(player)
	world.add_player(player)
	await physics_frame
	_check_equal(world.game.roster.ids(), [0] as Array[int], "a player the world takes is on its roster")
	_check(world.game.roster.hit_target(0) == player.hit_target and player.hit_target.userid == 0,
		"with their own hit target, which knows their userid")
	_check(world.game.inventory(0) != null and world.game.inventory(0).body == player.hit_target,
		"and an inventory wearing their armour")
	var before := listener.ticked.size()
	world.step()
	_check_equal(listener.ticked.slice(before).back(), world.tick, "each world tick steps the game on the same tick")
	_check_equal(SimClock.current_tick(), world.tick, "and events are stamped with the world's tick")
	world.remove_player(player)
	_check(world.game.roster.ids().is_empty(), "a player who leaves the world leaves the roster")
	player.queue_free()
	world.queue_free()
	await physics_frame


func _test_the_range_s_game() -> void:
	var range_node := (load("res://maps/test_range/test_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(range_node)
	await physics_frame
	await physics_frame
	var game: GameSystems = range_node.get(&"game")
	var world: GameWorld = range_node.get(&"world")
	_check(game != null and game == world.game, "the range has one game, its world's")
	var dummy: PlayerSim = range_node.get(&"dummy")
	var you: PlayerSim = range_node.get(&"player")
	var shooter: PlayerSim = range_node.get(&"shooter")
	var ids := [game.roster.userid_of(dummy), game.roster.userid_of(you), game.roster.userid_of(shooter)]
	_check(not ids.has(GameEvents.NOBODY) and game.roster.ids().size() == 3,
		"the dummy, you and the shooter are on its roster (%s)" % [ids])
	_check(game.roster.hit_target(ids[1]) == you.hit_target, "you by your own hit target")
	range_node.queue_free()
	await physics_frame
