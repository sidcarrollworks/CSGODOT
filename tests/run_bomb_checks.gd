extends "res://tests/check_suite.gd"

## Checks the bomb: CS2's numbers, planting only on a site, on the ground,
## as a terrorist, held for the whole plant; the 40 s timer; the defuse, 10 s
## or 5 with a kit, started over when let go, lost to a timer that runs out
## first; dropping it, on death or by choice, and only a terrorist picking it
## up; the blast by distance; the game events each of those sends; and that
## the state saves and comes back whole.
##
##   godot --headless --path . --script tests/run_bomb_checks.gd
##
## Needs nothing extracted: the bomb is plain state, moved on by hand with
## simulation times the checks choose, so 40 s take no time at all. The
## last checks plant it on the test range, with its key held, in real time.

const SECOND := 1_000_000
const BOMB_FILES := [
	"res://src/bomb/c4.gd",
	"res://src/bomb/c4_rules.gd",
	"res://src/bomb/bomb_site.gd",
]

## Site A, 256 across, from the origin.
const SITE_BOX := AABB(Vector3(0.0, -8.0, 0.0), Vector3(256.0, 136.0, 256.0))
const ON_SITE := Vector3(128.0, 0.0, 128.0)
const OFF_SITE := Vector3(-512.0, 0.0, 128.0)

const T_ID := 0
const CT_ID := 1
const OTHER_T_ID := 2

var _sites: Array[BombSite] = []
var _now: int = 0


func _initialize() -> void:
	_sites = [BombSite.of_box("A", SITE_BOX)]
	_test_the_bomb_reads_only_the_simulation()
	_test_the_rules_are_cs2s()
	_test_the_blast()
	_test_the_beeps()
	_test_a_site()
	_test_planting_needs_a_site_the_ground_and_a_terrorist()
	_test_a_plant()
	_test_letting_go_of_a_plant()
	_test_dropped_on_death()
	_test_dropped_by_choice()
	_test_a_defuse()
	_test_a_defuse_with_a_kit()
	_test_letting_go_of_a_defuse()
	_test_who_can_defuse()
	_test_a_defuse_too_late()
	_test_the_explosion()
	_test_bomb_zones()
	_test_saved_and_put_back()
	await _test_on_the_range()
	_finish("bomb")


# --- Helpers ----------------------------------------------------------------

func _tick_usec() -> int:
	return SimClock.tick_usec()


func _actor(id: int, team: String, feet: Vector3) -> C4.Actor:
	var actor := C4.Actor.new()
	actor.id = id
	actor.team = team
	actor.feet = feet
	actor.eyes = feet + Vector3.UP * 64.0
	actor.aim = Vector3.FORWARD
	return actor


## A counter-terrorist standing next to the bomb and looking down at it.
func _defuser(bomb: C4, has_kit: bool = false) -> C4.Actor:
	var actor := _actor(CT_ID, "CT", bomb.position + Vector3(24.0, 0.0, 0.0))
	actor.aim = (bomb.position - actor.eyes).normalized()
	actor.use_held = true
	actor.has_kit = has_kit
	return actor


## Runs the bomb tick after tick for this long with the same actors.
func _run(bomb: C4, seconds: float, actors: Array[C4.Actor]) -> void:
	var until := _now + roundi(seconds * SECOND)
	while _now < until:
		_now += _tick_usec()
		bomb.tick(_now, actors, _sites)


func _one_tick(bomb: C4, actors: Array[C4.Actor]) -> void:
	_now += _tick_usec()
	bomb.tick(_now, actors, _sites)


func _names(events: Array[Dictionary]) -> PackedStringArray:
	var names := PackedStringArray()
	for event in events:
		if not String(event["name"]).ends_with("bombzone"):
			names.append(event["name"])
	return names


## A bomb planted on site A by T_ID, its events taken.
func _planted_bomb(rules: C4Rules = null) -> C4:
	var bomb := C4.new(rules)
	var planter := _actor(T_ID, "T", ON_SITE)
	bomb.give_to(T_ID, ON_SITE)
	planter.plant_held = true
	_run(bomb, bomb.rules.plant_seconds + 0.1, [planter])
	bomb.take_events()
	return bomb


# --- What the bomb may read -------------------------------------------------

func _test_the_bomb_reads_only_the_simulation() -> void:
	var keys := RegEx.create_from_string("(?<![A-Za-z_])Input\\.")
	var clock := RegEx.create_from_string("Time\\.get_ticks|Time\\.get_unix|SimClock\\.now")
	for path: String in BOMB_FILES:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		_check(not code.is_empty(), "%s is there to read" % path.get_file())
		_check(keys.search(code) == null, "%s never reads the keys" % path.get_file())
		_check(clock.search(code) == null, "%s never reads a clock, only the tick it is given" % path.get_file())


# --- CS2's numbers ----------------------------------------------------------

func _test_the_rules_are_cs2s() -> void:
	var rules := C4Rules.new()
	_check_equal(rules.timer_seconds, 40.0, "the timer is 40 s (mp_c4timer)")
	_check_equal(rules.defuse_seconds, 10.0, "a defuse takes 10 s")
	_check_equal(rules.kit_defuse_seconds, 5.0, "a defuse with a kit takes 5 s")
	_check_equal(rules.bomb_damage, 500.0, "the blast does 500 by default (bombradius)")
	_check_equal(rules.radius_scale, 3.5, "and reaches 3.5 times that")


func _test_the_blast() -> void:
	_check_near(C4.blast_damage(0.0, 500.0), 500.0, "the blast does all of its damage at the bomb")
	var sigma := 500.0 * 3.5 / 3.0
	_check_near(C4.blast_damage(sigma, 500.0), 500.0 * exp(-0.5),
		"a third of the way out it does e^-0.5 of it (a bell curve over the reach)")
	_check_equal(C4.blast_damage(1751.0, 500.0), 0.0, "and nothing past its reach, 1,750 units")
	_check(C4.blast_damage(1749.0, 500.0) > 0.0, "and a little just inside it")
	_check_near(C4.blast_damage(0.0, 700.0), 700.0, "dust2's bomb does 700 at the bomb")
	_check_equal(C4.blast_damage(2451.0, 700.0), 0.0, "and reaches 2,450 units")
	var falling := true
	for step in 24:
		if C4.blast_damage(step * 100.0 + 100.0, 700.0) > C4.blast_damage(step * 100.0, 700.0):
			falling = false
	_check(falling, "the blast only falls off with distance")


func _test_the_beeps() -> void:
	_check_near(C4.beep_interval(40.0, 40.0), 1.0, "a beep a second when it is planted")
	_check_near(C4.beep_interval(0.0, 40.0), 0.1, "ten a second at the end")
	_check(C4.beep_interval(10.0, 40.0) < C4.beep_interval(30.0, 40.0), "the beeps close in as it runs down")


func _test_a_site() -> void:
	var site: BombSite = _sites[0]
	_check(site.contains(ON_SITE), "a player standing on the site is on it")
	_check(not site.contains(OFF_SITE), "one off it is not")
	_check_equal(site.bounds(), SITE_BOX, "a box site's bounds are its box")


# --- Planting ---------------------------------------------------------------

func _test_planting_needs_a_site_the_ground_and_a_terrorist() -> void:
	var bomb := C4.new()
	var off := _actor(T_ID, "T", OFF_SITE)
	off.plant_held = true
	bomb.give_to(T_ID, OFF_SITE)
	_run(bomb, 4.0, [off])
	_check(not bomb.planting() and bomb.state == C4.State.CARRIED, "holding the plant off a site plants nothing")

	var air := _actor(T_ID, "T", ON_SITE)
	air.plant_held = true
	air.on_ground = false
	_run(bomb, 4.0, [air])
	_check(not bomb.planting() and bomb.state == C4.State.CARRIED, "nor in the air over one")

	var ct := _actor(T_ID, "CT", ON_SITE)
	ct.plant_held = true
	_run(bomb, 4.0, [ct])
	_check(not bomb.planting() and bomb.state == C4.State.CARRIED, "nor as a counter-terrorist")

	var idle := _actor(T_ID, "T", ON_SITE)
	_run(bomb, 4.0, [idle])
	_check(bomb.state == C4.State.CARRIED, "nor standing on one without holding it")
	_check(bomb.position.is_equal_approx(ON_SITE), "a carried bomb goes where its carrier goes")


func _test_a_plant() -> void:
	var bomb := C4.new()
	bomb.give_to(T_ID, ON_SITE)
	_check_equal(_names(bomb.take_events()), PackedStringArray(["player_given_c4"]),
		"handing it out sends player_given_c4")
	var planter := _actor(T_ID, "T", ON_SITE)
	planter.plant_held = true
	_one_tick(bomb, [planter])
	var began := _now
	_check(bomb.planting(), "holding it on the site, on the ground, begins the plant")
	_check(bomb.holds_still(T_ID), "which holds the planter still")
	_check(not bomb.holds_still(CT_ID), "and nobody else")
	var events := bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_beginplant"]), "and sends bomb_beginplant")
	_check_equal(events[-1].get("site"), "A", "with the site's letter")
	_check_equal(events[-1].get("userid"), T_ID, "and the planter")

	var plant_usec := roundi(bomb.rules.plant_seconds * SECOND)
	while _now + _tick_usec() < began + plant_usec:
		_one_tick(bomb, [planter])
	_check(bomb.planting(), "a tick short of %.1f s it is still being planted" % bomb.rules.plant_seconds)
	_check(bomb.plant_progress(_now) > 0.98 and bomb.plant_progress(_now) < 1.0, "and nearly done")
	_one_tick(bomb, [planter])
	_check(bomb.planted(), "at %.1f s it is planted" % bomb.rules.plant_seconds)
	_check_equal(bomb.planted_usec - began, plant_usec, "exactly then, to the tick")
	_check(not bomb.holds_still(T_ID), "and the planter is free to move")
	_check_equal(bomb.planter, T_ID, "planted by its carrier")
	_check_equal(bomb.carrier, C4.NOBODY, "carried by nobody now")
	_check_equal(bomb.explodes_usec - bomb.planted_usec, 40 * SECOND, "going off 40 s later")
	_check_near(bomb.seconds_left(_now), 40.0, "with 40 s on the clock")
	events = bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_planted"]), "and sends bomb_planted")
	_check_equal(events[-1].get("site"), "A", "on site A")
	_check(bomb.position.is_equal_approx(ON_SITE), "it lies where it was planted")


func _test_letting_go_of_a_plant() -> void:
	var bomb := C4.new()
	bomb.give_to(T_ID, ON_SITE)
	var planter := _actor(T_ID, "T", ON_SITE)
	planter.plant_held = true
	_run(bomb, 2.0, [planter])
	bomb.take_events()
	planter.plant_held = false
	_one_tick(bomb, [planter])
	_check(not bomb.planting() and bomb.state == C4.State.CARRIED, "letting go stops the plant")
	_check_equal(bomb.plant_progress(_now), 0.0, "and it is lost")
	_check_equal(_names(bomb.take_events()), PackedStringArray(["bomb_abortplant"]), "which sends bomb_abortplant")
	planter.plant_held = true
	_run(bomb, 2.0, [planter])
	_check(bomb.planting() and not bomb.planted(), "holding again starts over")


# --- Dropping and picking up --------------------------------------------------

func _test_dropped_on_death() -> void:
	var bomb := C4.new()
	bomb.give_to(T_ID, OFF_SITE)
	var carrier := _actor(T_ID, "T", OFF_SITE)
	_one_tick(bomb, [carrier])
	bomb.take_events()
	carrier.alive = false
	_one_tick(bomb, [carrier])
	_check_equal(bomb.state, C4.State.DROPPED, "its carrier dying drops it")
	_check(bomb.position.is_equal_approx(OFF_SITE), "where they fell")
	var events := bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_dropped"]), "and sends bomb_dropped")
	_check_equal(events[-1].get("userid"), T_ID, "saying whose it was")
	_check(events[-1].has("entindex"), "with CS2's entindex")

	var ct := _actor(CT_ID, "CT", OFF_SITE)
	_run(bomb, 0.5, [carrier, ct])
	_check_equal(bomb.state, C4.State.DROPPED, "a counter-terrorist standing on it leaves it")
	var far := _actor(OTHER_T_ID, "T", OFF_SITE + Vector3(64.0, 0.0, 0.0))
	_run(bomb, 0.5, [carrier, ct, far])
	_check_equal(bomb.state, C4.State.DROPPED, "a terrorist 64 units off does not reach it")
	far.feet = OFF_SITE + Vector3(12.0, 0.0, 0.0)
	_one_tick(bomb, [carrier, ct, far])
	_check_equal(bomb.state, C4.State.CARRIED, "a terrorist walking over it picks it up")
	_check_equal(bomb.carrier, OTHER_T_ID, "and carries it")
	_check_equal(_names(bomb.take_events()), PackedStringArray(["bomb_pickup"]), "which sends bomb_pickup")


func _test_dropped_by_choice() -> void:
	var bomb := C4.new()
	bomb.give_to(T_ID, OFF_SITE)
	var carrier := _actor(T_ID, "T", OFF_SITE)
	carrier.drop = true
	_one_tick(bomb, [carrier])
	_check_equal(bomb.state, C4.State.DROPPED, "asking to drop it drops it")
	carrier.drop = false
	_run(bomb, bomb.rules.redrop_seconds * 0.5, [carrier])
	_check_equal(bomb.state, C4.State.DROPPED, "its dropper does not pick it straight back up")
	_run(bomb, bomb.rules.redrop_seconds, [carrier])
	_check_equal(bomb.state, C4.State.CARRIED, "but does a moment later")

	var planter := _actor(T_ID, "T", ON_SITE)
	planter.plant_held = true
	bomb.give_to(T_ID, ON_SITE)
	_run(bomb, 1.0, [planter])
	planter.drop = true
	_one_tick(bomb, [planter])
	_check(bomb.planting(), "it cannot be dropped in the middle of a plant")


# --- Defusing ----------------------------------------------------------------

func _test_a_defuse() -> void:
	var bomb := _planted_bomb()
	var ct := _defuser(bomb)
	_one_tick(bomb, [ct])
	var began := _now
	_check(bomb.defusing(), "a counter-terrorist next to it, looking at it, holding use, defuses it")
	_check(bomb.holds_still(CT_ID), "which holds them still")
	var events := bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_begindefuse"]), "and sends bomb_begindefuse")
	_check_equal(events[-1].get("haskit"), false, "without a kit")
	_check_equal(bomb.defuse_ends_usec - began, 10 * SECOND, "for 10 s")
	while _now + _tick_usec() < began + 10 * SECOND:
		_one_tick(bomb, [ct])
	_check(bomb.defusing() and bomb.planted(), "a tick short of 10 s it is still being defused")
	_one_tick(bomb, [ct])
	_check_equal(bomb.state, C4.State.DEFUSED, "at 10 s it is defused")
	events = bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_defused"]), "and sends bomb_defused")
	_check_equal(events[-1].get("userid"), CT_ID, "by the defuser")
	_check_equal(events[-1].get("site"), "A", "on site A")
	_run(bomb, 40.0, [ct])
	_check_equal(bomb.state, C4.State.DEFUSED, "and a defused bomb never goes off")
	_check(bomb.take_blast().is_empty(), "or hurts anyone")


func _test_a_defuse_with_a_kit() -> void:
	var bomb := _planted_bomb()
	var ct := _defuser(bomb, true)
	_one_tick(bomb, [ct])
	var began := _now
	_check_equal(bomb.take_events()[-1].get("haskit"), true, "bomb_begindefuse says there is a kit")
	_check_equal(bomb.defuse_ends_usec - began, 5 * SECOND, "and the defuse takes 5 s")
	_run(bomb, 5.0, [ct])
	_check_equal(bomb.state, C4.State.DEFUSED, "and is done in 5 s")


func _test_letting_go_of_a_defuse() -> void:
	var bomb := _planted_bomb()
	var ct := _defuser(bomb)
	_run(bomb, 6.0, [ct])
	bomb.take_events()
	ct.use_held = false
	_one_tick(bomb, [ct])
	_check(not bomb.defusing(), "letting go stops the defuse")
	_check_equal(_names(bomb.take_events()), PackedStringArray(["bomb_abortdefuse"]), "and sends bomb_abortdefuse")
	ct.use_held = true
	_run(bomb, 6.0, [ct])
	_check(bomb.defusing() and bomb.planted(), "holding again starts it over: 6 s more is not enough")
	_run(bomb, 4.1, [ct])
	_check_equal(bomb.state, C4.State.DEFUSED, "10 s is")

	bomb = _planted_bomb()
	ct = _defuser(bomb)
	_run(bomb, 2.0, [ct])
	ct.on_ground = false
	_one_tick(bomb, [ct])
	_check(not bomb.defusing(), "jumping stops a defuse")
	ct.on_ground = true
	ct.alive = false
	_one_tick(bomb, [ct])
	_check(not bomb.defusing(), "a dead player defuses nothing")


func _test_who_can_defuse() -> void:
	var bomb := _planted_bomb()
	var t := _defuser(bomb)
	t.team = "T"
	_run(bomb, 1.0, [t])
	_check(not bomb.defusing(), "a terrorist cannot defuse it")

	var away := _defuser(bomb)
	away.aim = -away.aim
	_run(bomb, 1.0, [away])
	_check(not bomb.defusing(), "nor a counter-terrorist looking away from it")

	var far := _defuser(bomb)
	far.feet = bomb.position + Vector3(200.0, 0.0, 0.0)
	far.eyes = far.feet + Vector3.UP * 64.0
	far.aim = (bomb.position - far.eyes).normalized()
	_run(bomb, 1.0, [far])
	_check(not bomb.defusing(), "nor one looking at it from 200 units off")

	var first := _defuser(bomb)
	var second := _defuser(bomb)
	second.id = 7
	second.feet = bomb.position + Vector3(-40.0, 0.0, 0.0)
	second.eyes = second.feet + Vector3.UP * 64.0
	second.aim = (bomb.position - second.eyes).normalized()
	_one_tick(bomb, [second, first])
	_check_equal(bomb.defuser, CT_ID, "of two holding use at once, the nearer defuses it")
	_run(bomb, 1.0, [second, first])
	_check_equal(bomb.defuser, CT_ID, "and only one does at a time")


func _test_a_defuse_too_late() -> void:
	var bomb := _planted_bomb()
	var t := _actor(T_ID, "T", ON_SITE)
	_run(bomb, 31.0, [t])
	var ct := _defuser(bomb)
	_one_tick(bomb, [t, ct])
	_check(bomb.defusing() and bomb.defuse_ends_usec > bomb.explodes_usec,
		"a defuse begun with 9 s left and no kit would end after the bomb")
	_run(bomb, 9.5, [t, ct])
	_check_equal(bomb.state, C4.State.EXPLODED, "so the bomb goes off")
	_check(_names(bomb.take_events()).has("bomb_exploded"), "and sends bomb_exploded")

	bomb = _planted_bomb()
	_run(bomb, 34.0, [t])
	ct = _defuser(bomb, true)
	_one_tick(bomb, [t, ct])
	_run(bomb, 5.0, [t, ct])
	_check_equal(bomb.state, C4.State.DEFUSED, "with a kit, 6 s left is enough")


# --- The explosion -------------------------------------------------------------

func _test_the_explosion() -> void:
	var rules := C4Rules.new()
	rules.bomb_damage = 700.0
	var bomb := _planted_bomb(rules)
	var planter := _actor(T_ID, "T", bomb.position)
	var near := _actor(CT_ID, "CT", bomb.position + Vector3(500.0, 0.0, 0.0))
	var far := _actor(OTHER_T_ID, "T", bomb.position + Vector3(3000.0, 0.0, 0.0))
	var dead := _actor(9, "CT", bomb.position)
	dead.alive = false
	var everyone: Array[C4.Actor] = [planter, near, far, dead]
	while _now + _tick_usec() < bomb.explodes_usec:
		_one_tick(bomb, everyone)
	_check(bomb.planted(), "a tick short of 40 s it has not gone off")
	_check(bomb.take_blast().is_empty(), "and hurt nobody")
	_one_tick(bomb, everyone)
	_check_equal(bomb.state, C4.State.EXPLODED, "at 40 s it goes off")
	var events := bomb.take_events()
	_check_equal(_names(events), PackedStringArray(["bomb_exploded"]), "sending bomb_exploded")
	_check_equal(events[-1].get("userid"), T_ID, "with the planter")
	var blast := bomb.take_blast()
	var by_victim := {}
	for record in blast:
		by_victim[record["victim"]] = record
	_check(by_victim.has(T_ID), "the blast reaches its own planter")
	_check(by_victim.has(CT_ID), "and a player 500 units off")
	_check(not by_victim.has(OTHER_T_ID), "not one 3,000 units off, past its 2,450")
	_check(not by_victim.has(9), "and not the dead")
	if by_victim.has(CT_ID):
		var record: Dictionary = by_victim[CT_ID]
		var middle := near.feet + Vector3.UP * 36.0
		_check_near(record["amount"], C4.blast_damage(middle.distance_to(bomb.position), 700.0),
			"doing the blast's damage at their distance, measured to the middle of the body")
		_check_equal(record["attacker"], T_ID, "credited to the planter")
		_check_equal(record["weapon"], "weapon_c4", "with the bomb")
	_run(bomb, 5.0, everyone)
	_check(bomb.take_blast().is_empty(), "it goes off once")


func _test_bomb_zones() -> void:
	var bomb := C4.new()
	bomb.give_to(T_ID, OFF_SITE)
	bomb.take_events()
	var carrier := _actor(T_ID, "T", OFF_SITE)
	_one_tick(bomb, [carrier])
	_check(bomb.take_events().is_empty(), "standing off a site sends nothing")
	carrier.feet = ON_SITE
	_one_tick(bomb, [carrier])
	var events := bomb.take_events()
	_check(events.size() == 1 and events[0]["name"] == "enter_bombzone", "stepping on sends enter_bombzone")
	_check_equal(events[0].get("hasbomb"), true, "saying they carry the bomb")
	_one_tick(bomb, [carrier])
	_check(bomb.take_events().is_empty(), "staying on sends nothing more")
	carrier.feet = OFF_SITE
	_one_tick(bomb, [carrier])
	events = bomb.take_events()
	_check(events.size() == 1 and events[0]["name"] == "exit_bombzone", "stepping off sends exit_bombzone")


# --- Saving and putting back ----------------------------------------------------

func _test_saved_and_put_back() -> void:
	var bomb := _planted_bomb()
	var t := _actor(T_ID, "T", ON_SITE)
	var ct := _defuser(bomb, true)
	_run(bomb, 2.0, [t, ct])
	bomb.take_events()
	var saved := bomb.save_state()
	var saved_at := _now
	_run(bomb, 3.5, [t, ct])
	var first := bomb.state
	var first_events := _names(bomb.take_events())

	var copy := C4.new()
	copy.load_state(saved)
	_check_equal(copy.save_state(), saved, "a saved bomb put back is the bomb that was saved")
	_now = saved_at
	_run(copy, 3.5, [t, ct])
	_check_equal(copy.state, first, "and runs on the same (%s)" % C4.State.keys()[first])
	_check_equal(_names(copy.take_events()), first_events, "sending the same events")


# --- On the range -----------------------------------------------------------------

func _test_on_the_range() -> void:
	var range_map := (load("res://maps/test_range/test_range.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(range_map)
	for i in 4:
		await physics_frame
	var bomb: C4 = range_map.bomb
	var player: PlayerSim = range_map.player
	_check(bomb != null and bomb.state == C4.State.CARRIED and bomb.carrier == range_map.PLAYER_ID,
		"on the range you carry the bomb")
	_check(not range_map.bomb_view.visible, "and it is not drawn on the ground")

	player.place(range_map.BOMB_SITE_BOX.get_center() * Vector3(1.0, 0.0, 1.0) + Vector3.UP * 2.0, 180.0)
	for i in 8:
		await physics_frame
	_check(range_map.bomb_sites[0].contains(player.global_position), "site A is behind the spawn")
	var press := InputEventKey.new()
	press.physical_keycode = range_map.BOMB_PLANT_KEY
	press.pressed = true
	Input.parse_input_event(press)
	var waited := 0
	while not bomb.planted() and waited < SimClock.ticks_in(bomb.rules.plant_seconds + 1.0):
		await physics_frame
		waited += 1
		if waited == 16:
			_check(bomb.planting() and player.frozen, "holding 5 on it plants, holding you still")
	_check(bomb.planted(), "and in %.1f s it is down" % bomb.rules.plant_seconds)
	var release := InputEventKey.new()
	release.physical_keycode = range_map.BOMB_PLANT_KEY
	release.pressed = false
	Input.parse_input_event(release)
	await physics_frame
	await process_frame
	_check(not player.frozen, "and you are free to move")
	_check(range_map.bomb_view.visible, "it is drawn where it was planted")
	_check("planted on A" in range_map.bomb_readout(), "and the readout counts it down (%s)" % range_map.bomb_readout())
	_check(range_map.log_lines().size() >= 2 and "bomb_planted" in range_map.log_lines()[0],
		"the log has the plant's events")
	range_map.queue_free()
	await process_frame
