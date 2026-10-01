extends "res://tests/check_suite.gd"

## Checks E on items on the ground (issue 3 of
## reference/playtest-2026-09-25.md): ItemDrops takes the item looked at,
## within reach and in clear sight, into a free slot or in place of the gun
## there, which is thrown down; refuses what there is no room for with
## item_pickup_failed; leaves the kit to CTs and the bomb to the bomb; and
## gives E to the bomb near it. Players stand on a floor and look where the
## checks turn them; E is the command each ran, as PlayerSim keeps it.
##
##   godot --headless --path . --script tests/run_pickup_checks.gd
##
## Needs nothing extracted.

## Where an item lies ahead of a player's feet: past the touch reach
## (ItemDrops.REACH_ACROSS 32) and within E's (80 across, UseSearch).
const AHEAD := 42.0

var _world: Node3D
var _game: GameSystems
var _bomb: BombSystem
var _drops: ItemDrops
var _tick: int = 10_000
var _heard: Array[GameEvent] = []


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_static_box(Vector3(32768.0, 16.0, 4096.0), Vector3(8192.0, -8.0, 0.0))
	await physics_frame
	_game = GameSystems.new()
	_bomb = BombSystem.new()
	_game.add_system(_bomb)
	for system in _game.systems():
		if system is ItemDrops:
			_drops = system
	_game.events.listen_all(func(event: GameEvent) -> void: _heard.append(event))
	_check(_drops.use_pressed.is_valid(), "by default E is read from the command each player ran")

	await _test_free_slot()
	await _test_swap_rifles()
	await _test_swap_pistols()
	await _test_out_of_reach()
	await _test_widens_up_close()
	await _test_through_a_wall()
	await _test_grenade_prompt()
	await _test_no_room_for_a_grenade()
	await _test_the_kit()
	await _test_held_takes_one()
	await _test_the_dropped_bomb()
	await _test_the_planted_bomb()
	await _test_pickup_prompt_waits()
	_finish("pickup")


# --- The cases ---------------------------------------------------------------

func _test_free_slot() -> void:
	var p := _player("T", Vector3(0.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	var item := await _lay("weapon_ak47", p, 0.0)
	_check_equal(_prompt(p), "[E] Pick up AK-47", "a free rifle slot shows the item E will take")
	_check(not item.removed and not inventory.has("weapon_ak47"), "asking for the pickup prompt does not take the item")
	_heard.clear()
	_press(p)
	_check(inventory.has("weapon_ak47") and item.removed, "E takes a gun %d units ahead into a free slot" % AHEAD)
	_check(inventory.in_hand_class() == "weapon_knife", "and leaves the knife in hand (ItemDrops.USE_DRAWS)")
	_check_equal(_names_heard(), PackedStringArray(["item_pickup"]), "with one item_pickup")
	_check_equal(_prompt(p), "", "the pickup prompt disappears as soon as the item is taken")
	_leave(p)


func _test_swap_rifles() -> void:
	var p := _player("T", Vector3(1000.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	inventory.add("weapon_ak47")
	inventory.select("weapon_ak47")
	inventory.item_in(ItemDef.Slot.PRIMARY).weapon.ammo = 7
	var item := await _lay("weapon_ak47", p, 0.0)
	item.entry.weapon.ammo = 13
	_check_equal(_prompt(p), "[E] Swap for AK-47", "another copy of the rifle in hand still offers a swap")
	_heard.clear()
	_press(p)
	var held := inventory.in_hand()
	_check(held != null and held.item.item_class == "weapon_ak47" and held.weapon.ammo == 13,
		"E on another AK-47 swaps it for the one in hand, which comes into hand with its own 13 rounds")
	var thrown := _ground_items("weapon_ak47")
	_check(thrown.size() == 1 and thrown[0].entry.weapon.ammo == 7 and thrown[0].owner_id == _id(p),
		"and the old one is thrown down with its 7")
	_check_equal(_names_heard(), PackedStringArray(["item_remove", "item_pickup"]), "one item_remove and one item_pickup")
	_clear_ground()
	var m4 := await _lay("weapon_m4a1", p, 0.0)
	_check_equal(_prompt(p), "[E] Swap for M4A4", "a rifle swap names the rifle on the ground")
	_press(p)
	_check(inventory.in_hand_class() == "weapon_m4a1" and not inventory.has("weapon_ak47") and m4.removed,
		"and E on an M4A4 swaps the AK-47 for it")
	_clear_ground()
	_leave(p)


func _test_swap_pistols() -> void:
	var p := _player("CT", Vector3(2000.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	inventory.add("weapon_ak47")
	inventory.add("weapon_hkp2000")
	inventory.select("weapon_ak47")
	await _lay("weapon_deagle", p, 0.0)
	_check_equal(_prompt(p), "[E] Swap for Desert Eagle", "a pistol swap shows its display name with a rifle in hand")
	_press(p)
	_check(inventory.has("weapon_deagle") and not inventory.has("weapon_hkp2000") and inventory.in_hand_class() == "weapon_ak47",
		"E on a Desert Eagle swaps the pistol, the rifle staying in hand")
	_check(_ground_items("weapon_hkp2000").size() == 1, "and the P2000 goes to the ground")
	_clear_ground()
	_leave(p)


func _test_out_of_reach() -> void:
	var p := _player("T", Vector3(3000.0, 0.0, 0.0))
	var near := await _lay("weapon_glock", p, 0.0, 76.0)
	_check_equal(_pickup_class(p), "weapon_glock", "the prompt reaches the same Glock E takes 76 units across")
	_press(p)
	_check(near.removed, "E takes a Glock on the floor 76 units across, 99 from the eyes: the reach is across (UseSearch)")
	_clear_ground()
	var far := await _lay("weapon_glock", p, 0.0, 88.0)
	_check_equal(_prompt(p), "", "nothing out of E's reach offers a pickup")
	_press(p)
	_check(not far.removed, "but not one 88 across, past player_use_radius's 80")
	_clear_ground()
	_leave(p)


## Sid's playtest of 2026-09-30: the nearer the gun, the further off the
## crosshair it may be.
func _test_widens_up_close() -> void:
	var p := _player("T", Vector3(4000.0, 0.0, 0.0))
	var near := await _lay("weapon_ak47", p, 0.0)
	# Looking level, straight over it: 56 degrees off the aim, but the box
	# swept 45 degrees down finds it.
	p.pitch_degrees = 0.0
	_check_equal(_pickup_class(p), "weapon_ak47", "the nearby gun E finds below a level aim also has a prompt")
	_press(p)
	_check(near.removed, "E takes a gun %d units ahead with the aim level over it" % AHEAD)
	_clear_ground()
	var far := await _lay("weapon_glock", p, 0.0, 70.0)
	p.pitch_degrees += 3.0
	_check_equal(_prompt(p), "", "looking over the distant Glock does not offer a pickup")
	_press(p)
	_check(not far.removed, "but a Glock 70 across only under the crosshair: not with the aim 3 degrees over it")
	_look_at(p, far.position)
	var aside := await _lay("weapon_ak47", p, 30.0, 36.0)
	_look_at(p, far.position)
	_check_equal(_prompt(p), "[E] Pick up Glock-18", "the prompt chooses the aimed-at Glock before the nearer AK-47")
	_press(p)
	_check(far.removed and not aside.removed, "and with the aim on it, it is taken before a nearer gun off the aim")
	_clear_ground()
	_leave(p)


func _test_through_a_wall() -> void:
	var p := _player("T", Vector3(5000.0, 0.0, 0.0))
	var item := await _lay("weapon_ak47", p, 0.0)
	var wall := _static_box(Vector3(64.0, 128.0, 4.0), p.global_position + Vector3(0.0, 64.0, -20.0))
	await physics_frame
	_check_equal(_prompt(p), "", "a wall hides the pickup prompt as well as blocking E")
	_press(p)
	_check(not item.removed, "nothing through a wall")
	wall.queue_free()
	await physics_frame
	_clear_ground()
	_leave(p)


func _test_grenade_prompt() -> void:
	var p := _player("T", Vector3(5500.0, 0.0, 0.0))
	var item := await _lay("weapon_smokegrenade", p, 0.0)
	_check_equal(_prompt(p), "[E] Pick up Smoke Grenade", "a grenade with room to carry it shows its display name")
	_press(p)
	_check(item.removed and _game.inventory(_id(p)).has("weapon_smokegrenade"), "E takes the grenade the prompt names")
	_check_equal(_prompt(p), "", "the grenade prompt disappears after the pickup")
	var flash := await _lay("weapon_flashbang", p, 0.0)
	_check_equal(_prompt(p), "[E] Pick up Flashbang", "a flashbang on the ground has a pickup prompt too")
	flash.remove()
	_check_equal(_prompt(p), "", "an item removed between ticks immediately stops offering a pickup")
	_clear_ground()
	_leave(p)


func _test_no_room_for_a_grenade() -> void:
	var p := _player("T", Vector3(6000.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	for grenade in ["weapon_hegrenade", "weapon_smokegrenade", "weapon_flashbang", "weapon_flashbang"]:
		inventory.add(grenade)
	var item := await _lay("weapon_flashbang", p, 0.0)
	var gun := await _lay("weapon_ak47", p, 30.0, 36.0)
	_look_at(p, item.position)
	_check_equal(_pickup_class(p), "", "an aimed-at grenade with no room does not advertise an eligible gun off the aim")
	_check_equal(_prompt(p), "", "a full grenade inventory does not offer a pickup E will refuse")
	_heard.clear()
	_press(p)
	var failed := _heard_one(&"item_pickup_failed")
	_check(not item.removed and failed != null and failed.fields.item == "weapon_flashbang" and failed.fields.userid == _id(p),
		"with four grenades, E on a flashbang is refused with item_pickup_failed, as CS2 refuses it")
	_check(_heard_one(&"item_pickup") == null and inventory.grenade_count() == 4, "and nothing is taken")
	_check(not gun.removed and not inventory.has("weapon_ak47"), "E refuses the aimed-at grenade and leaves the eligible gun beside it")
	_clear_ground()
	_leave(p)


func _test_the_kit() -> void:
	var t := _player("T", Vector3(7000.0, 0.0, 0.0))
	var kit := await _lay("item_defuser", t, 0.0)
	_check_equal(_prompt(t), "", "a T is not offered a defuse kit they cannot take")
	_press(t)
	_check(not kit.removed and not _game.inventory(_id(t)).has_defuser, "a T cannot take the kit with E")
	_leave(t)
	var ct := _player("CT", Vector3(7000.0, 0.0, 0.0))
	_look_at(ct, kit.position)
	_check_equal(_prompt(ct), "[E] Pick up Defuse Kit", "a CT sees a pickup prompt for the same kit")
	_heard.clear()
	_press(ct)
	_check(kit.removed and _game.inventory(_id(ct)).has_defuser and _heard_one(&"defuser_pickup") != null, "a CT can")
	_leave(ct)


func _test_held_takes_one() -> void:
	var p := _player("T", Vector3(8000.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	var first := await _lay("weapon_ak47", p, 0.0)
	var second := await _lay("weapon_m4a1", p, 0.0)
	_heard.clear()
	_press(p)
	_hold(p)
	_hold(p)
	_check(first.removed != second.removed and _heard.filter(func(e: GameEvent) -> bool: return e.name == &"item_pickup").size() == 1,
		"holding E takes one item, not one a tick")
	_check(_ground_items("weapon_ak47").size() + _ground_items("weapon_m4a1").size() == 1 and inventory.item_in(ItemDef.Slot.PRIMARY) != null,
		"the other stays on the ground")
	_clear_ground()
	_leave(p)


func _test_the_dropped_bomb() -> void:
	var t := _player("T", Vector3(9000.0, 0.0, 0.0))
	var ct := _player("CT", Vector3(9000.0, 0.0, 0.0))
	_bomb.bomb.reset()
	_bomb.bomb.state = C4.State.DROPPED
	_bomb.bomb.position = t.global_position + Vector3(0.0, 1.0, -AHEAD)
	_look_at(ct, _bomb.bomb.position)
	_check_equal(_prompt(ct), "", "a CT is not offered the dropped bomb")
	_press(ct)
	_check(_bomb.bomb.state == C4.State.DROPPED, "a CT's E leaves the dropped bomb")
	_leave(ct)
	var gun := await _lay("weapon_ak47", t, 0.0)
	_look_at(t, _bomb.bomb.position)
	_check_equal(_pickup_class(t), "", "the dropped bomb suppresses the ground gun's pickup candidate")
	_check_equal(_prompt(t), "Press [E] to pick up bomb", "the bomb's prompt wins over the rifle underneath")
	_bomb.bomb.dropped_by = _id(t)
	_bomb.bomb.redrop_usec = _game.now_usec() + 1_000_000
	_check_equal(_prompt(t), "", "the player who just dropped the bomb is not offered it during their pickup delay")
	_bomb.bomb.dropped_by = C4.NOBODY
	_bomb.bomb.redrop_usec = C4.NEVER
	_heard.clear()
	_press(t)
	_check(_bomb.bomb.state == C4.State.CARRIED and _bomb.bomb.carrier == _id(t) and _heard_one(&"bomb_pickup") != null,
		"a T's E takes it from %d units, past its touch" % AHEAD)
	_check(not gun.removed, "and not the gun lying under it: near the bomb E is the bomb's")
	_bomb.bomb.reset()
	_game.inventory(_id(t)).remove("weapon_c4")
	_clear_ground()
	_leave(t)


func _test_the_planted_bomb() -> void:
	var ct := _player("CT", Vector3(10000.0, 0.0, 0.0))
	var gun := await _lay("weapon_ak47", ct, 0.0)
	_bomb.bomb.reset()
	_bomb.bomb.state = C4.State.PLANTED
	_bomb.bomb.position = gun.position + Vector3(4.0, 0.0, 0.0)
	_bomb.bomb.planted_usec = _game.now_usec()
	_bomb.bomb.explodes_usec = _game.now_usec() + 40_000_000
	_look_at(ct, _bomb.bomb.position)
	_check_equal(_pickup_class(ct), "", "defusing has priority over the gun's pickup candidate")
	_check_equal(_prompt(ct), "", "a planted bomb does not display a misleading gun pickup prompt")
	_heard.clear()
	_press(ct)
	_check(_heard_one(&"bomb_begindefuse") != null, "a CT's E beside the planted bomb defuses")
	_check(not gun.removed and _heard_one(&"item_pickup") == null, "and picks up nothing lying by it")
	_bomb.bomb.reset()
	_clear_ground()
	_leave(ct)


func _test_pickup_prompt_waits() -> void:
	var p := _player("T", Vector3(11000.0, 0.0, 0.0))
	var item := await _lay("weapon_ak47", p, 0.0)
	item.owner_id = _id(p)
	item.dropped_usec = _game.now_usec()
	_check_equal(_prompt(p), "", "the previous owner's pickup prompt waits after a fresh drop")
	_step_ticks(SimClock.ticks_in(1.3) + 1)
	_check_equal(_prompt(p), "", "the previous owner still waits after another player's 1.3-second delay")
	_step_ticks(SimClock.ticks_in(0.2) + 1)
	_check_equal(_prompt(p), "[E] Pick up AK-47", "the prompt appears when the previous owner's 1.5-second delay ends")
	p.alive = false
	_check_equal(_prompt(p), "", "a dead player is not offered the otherwise eligible rifle")
	p.alive = true
	_press(p)
	_check(item.removed, "E can take the rifle as soon as its delayed pickup prompt appears")
	_leave(p)
	_clear_ground()


# --- Helpers -------------------------------------------------------------------

func _player(team: String, at: Vector3) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	player.respawns = false
	_world.add_child(player)
	player.place(at, 0.0)
	player.on_ground = true
	player.set_meta(&"userid", _game.add_player(player, player.hit_target, player.inventory))
	player.userid = _id(player)
	return player


func _id(p: PlayerSim) -> int:
	return int(p.get_meta(&"userid"))


## The same read-only candidate the HUD asks for, then its displayed line.
func _pickup_class(p: PlayerSim) -> String:
	return String(_game.query(&"use_pickup_item", [_id(p)], ""))


func _prompt(p: PlayerSim) -> String:
	return UsePrompt.line_for(p, _bomb.bomb, null, _pickup_class(p), _game.now_usec())


## Drops an item and lets it come to rest ahead of the player (distance
## across from the feet, off to the side by aside), and turns the player
## to look at it; once anyone may take it.
func _lay(item_class: String, p: PlayerSim, aside: float, distance: float = AHEAD) -> DroppedItem:
	var def := ItemRegistry.item(item_class)
	var weapon := Weapon.new(ItemRegistry.weapon_data(item_class)) if def.is_gun else null
	var at := p.global_position + Vector3(aside, 6.0, -distance)
	var item := DroppedItem.drop_from(_game, GameEvents.NOBODY, Inventory.Entry.new(def, weapon, 1), Transform3D(Basis.IDENTITY, at))
	_step(2.0)
	_look_at(p, item.position)
	return item


func _look_at(p: PlayerSim, target: Vector3) -> void:
	var way := (target - (p.global_position + Vector3.UP * p.eye_height())).normalized()
	p.yaw_degrees = rad_to_deg(atan2(-way.x, -way.z))
	p.pitch_degrees = rad_to_deg(asin(way.y))


## A tick in which the player presses E where they look, then E let go.
func _press(p: PlayerSim) -> void:
	var cmd := UserCmd.new()
	cmd.buttons = UserCmd.USE
	cmd.yaw_degrees = p.yaw_degrees
	cmd.pitch_degrees = p.pitch_degrees
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.USE, true, 0.0, p.yaw_degrees, p.pitch_degrees))
	p.last_command = cmd
	_step_ticks(1)
	p.last_command = UserCmd.new()


## A tick with E held from before: no press.
func _hold(p: PlayerSim) -> void:
	var cmd := UserCmd.new()
	cmd.buttons = UserCmd.USE
	p.last_command = cmd
	_step_ticks(1)
	p.last_command = UserCmd.new()


func _leave(p: PlayerSim) -> void:
	p.alive = false
	p.global_position += Vector3(0.0, -10000.0, 0.0)


func _step(seconds: float) -> void:
	_step_ticks(SimClock.ticks_in(seconds))


func _step_ticks(count: int) -> void:
	for i in count:
		_tick += 1
		_game.step(_tick, _world.get_world_3d().direct_space_state)


func _ground_items(item_class: String) -> Array[DroppedItem]:
	var out: Array[DroppedItem] = []
	for entity in _game.entities.of_class(item_class):
		if entity is DroppedItem and not entity.removed:
			out.append(entity)
	return out


func _clear_ground() -> void:
	for entity in _game.entities.all():
		if entity is DroppedItem:
			entity.remove()
	_step_ticks(1)


func _names_heard() -> PackedStringArray:
	var names := PackedStringArray()
	for event in _heard:
		if event.name in [&"item_pickup", &"item_remove", &"item_pickup_failed", &"defuser_pickup"]:
			names.append(String(event.name))
	return names


func _heard_one(event_name: StringName) -> GameEvent:
	for event in _heard:
		if event.name == event_name:
			return event
	return null


func _static_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	_world.add_child(body)
	return body
