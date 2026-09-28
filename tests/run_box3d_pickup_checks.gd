extends "res://tests/check_suite.gd"

## E on items on the ground in a match's physics: a full Box3D world, as
## GameWorld builds (issue 3 of reference/playtest-2026-09-25.md, over
## #125). ItemDrops' sight test goes through PhysicsQueries, so a wall hides
## the gun behind it, and a gun at rest on the Box3D floor in plain view is
## taken. The gun E swaps out is thrown from its own hold, barrel along the
## aim, tumbling about its lateral axis, whatever is in hand.
## tests/run_pickup_checks.gd checks the rest of E, on Godot's own physics,
## which a bare fixture falls back to.
##
##   godot --headless --path . --script tests/run_box3d_pickup_checks.gd
##
## Needs the Box3D addon (scripts/install_box3d.sh or install_box3d.ps1) and
## nothing extracted.

## Where the gun lies ahead of the feet: past the touch reach and within E's.
const AHEAD := 42.0

var _host: Node3D
var _geometry: Node3D
var _game: GameSystems
var _tick: int = 10_000


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-pickup", "Box3D native addon is not installed; run scripts/install_box3d.sh or scripts/install_box3d.ps1")
		return
	await physics_frame
	ItemPhysics.use_table(ItemPhysics.PATH)
	_host = Node3D.new()
	root.add_child(_host)
	_geometry = Node3D.new()
	_host.add_child(_geometry)
	_box(Vector3(8192.0, 16.0, 8192.0), Vector3(0.0, -8.0, 0.0))
	# A wall between the first player and the gun ahead of them.
	_box(Vector3(64.0, 128.0, 4.0), Vector3(0.0, 64.0, -20.0))
	_game = GameSystems.new()
	_game.last_tick = SimTick.new(_game, 0)
	var adapter := Box3DDrops.new()
	_host.add_child(adapter)
	for frame in 3:
		await physics_frame
	var bound := adapter.initialize(_game, _geometry, true)
	_check(bound and PhysicsQueries.for_space(_space()) != null, "a full Box3D world binds the fixture's space, as a match does")
	if not bound:
		_host.free()
		_finish("box3d-pickup")
		return

	var legacy_before := PhysicsQueries.legacy_queries
	_test_through_a_wall()
	_test_in_plain_view()
	_test_swap_throw()
	_check(PhysicsQueries.legacy_queries == legacy_before, "E asked Box3D, never Godot's own space, which has no walls in it here")

	_game.entities.clear()
	_host.free()
	for system in _game.systems():
		if system is ItemDrops:
			system.game = null
	_finish("box3d-pickup")


func _test_through_a_wall() -> void:
	var p := _player(Vector3.ZERO)
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	var item := _lay("weapon_ak47", p)
	_press(p)
	_check(not item.removed and not inventory.has("weapon_ak47"), "nothing through a wall")
	_leave(p)


func _test_in_plain_view() -> void:
	var p := _player(Vector3(500.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	var item := _lay("weapon_ak47", p)
	_press(p)
	_check(item.removed and inventory.has("weapon_ak47"),
		"a gun at rest on the floor in plain view is taken: its own body does not block the sight ray (at %s)" % item.position)
	_leave(p)


func _test_swap_throw() -> void:
	var p := _player(Vector3(1000.0, 0.0, 0.0))
	var inventory := _game.inventory(_id(p))
	inventory.add("weapon_knife")
	inventory.add("weapon_m4a1")
	inventory.select("weapon_knife")
	var item := _lay("weapon_ak47", p)
	var released: Array[Dictionary] = []
	var watch := func(entity: SimEntity) -> void:
		var thrown := entity as DroppedItem
		if thrown != null and thrown.entry != null and thrown.entry.item.item_class == "weapon_m4a1":
			released.append({"model": thrown.model_transform(), "spin": thrown.angular_velocity})
	_game.entities.spawned.connect(watch)
	# Looking down at the gun: the swapped gun is thrown along that aim.
	var pitch := p.pitch_degrees
	_press(p)
	_game.entities.spawned.disconnect(watch)
	_check(item.removed and inventory.has("weapon_ak47") and not inventory.has("weapon_m4a1") and released.size() == 1,
		"E on an AK-47 with the knife in hand swaps out the M4A4 in the slot")
	if released.size() == 1:
		var model: Transform3D = released[0]["model"]
		var spin: Vector3 = released[0]["spin"]
		var aim := PlayerInput.aim_direction(p.yaw_degrees, pitch)
		var level_forward := PlayerInput.aim_direction(p.yaw_degrees, 0.0)
		_check(model.basis.z.dot(aim) > 0.9999,
			"the M4A4 goes barrel-first along the aim, from its own hold, not the knife's (%.4f)" % model.basis.z.dot(aim))
		_check(spin.dot(model.basis.x) >= ItemDrops.THROW_TUMBLE * 0.5 - 0.001 and absf(spin.dot(level_forward)) < 0.001,
			"and tumbles about its lateral axis, as a thrown gun does")
	_leave(p)


func _player(at: Vector3) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = "T"
	player.respawns = false
	_geometry.add_child(player)
	player.place(at, 0.0)
	player.on_ground = true
	player.set_meta(&"userid", _game.add_player(player, player.hit_target))
	return player


func _id(p: PlayerSim) -> int:
	return int(p.get_meta(&"userid"))


## Drops a gun a little above the floor ahead of the player, lets Box3D lay
## it down, and turns the player to look at it.
func _lay(item_class: String, p: PlayerSim) -> DroppedItem:
	var def := ItemRegistry.item(item_class)
	var entry := Inventory.Entry.new(def, Weapon.new(ItemRegistry.weapon_data(item_class)), 1)
	var item := DroppedItem.drop_from(_game, GameEvents.NOBODY, entry, Transform3D(Basis.IDENTITY, p.global_position + Vector3(0.0, 6.0, -AHEAD)))
	_step_ticks(SimClock.ticks_in(2.0))
	_look_at(p, item.position)
	return item


func _look_at(p: PlayerSim, target: Vector3) -> void:
	var way := (target - (p.global_position + Vector3.UP * p.eye_height())).normalized()
	p.yaw_degrees = rad_to_deg(atan2(-way.x, -way.z))
	p.pitch_degrees = rad_to_deg(asin(way.y))


## A tick in which the player presses E where they look.
func _press(p: PlayerSim) -> void:
	var cmd := UserCmd.new()
	cmd.buttons = UserCmd.USE
	cmd.yaw_degrees = p.yaw_degrees
	cmd.pitch_degrees = p.pitch_degrees
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.USE, true, 0.0, p.yaw_degrees, p.pitch_degrees))
	p.last_command = cmd
	_step_ticks(1)
	p.last_command = UserCmd.new()


func _leave(p: PlayerSim) -> void:
	p.alive = false
	p.global_position += Vector3(0.0, -10000.0, 0.0)


func _step_ticks(count: int) -> void:
	for i in count:
		_tick += 1
		_game.step(_tick, _space())


func _space() -> PhysicsDirectSpaceState3D:
	return _host.get_world_3d().direct_space_state


func _box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape3D.new()
	collision.name = "physics_group_concrete"
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	_geometry.add_child(body)
