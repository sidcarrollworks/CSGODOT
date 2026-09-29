extends "res://tests/check_suite.gd"

## Checks that a round in a tick meets a body's hitboxes where they are,
## whatever has happened to them since the bridge last put them, now that
## it brings a body's set up to date only for a ray that could meet it
## (Box3DQueries._sync_sets; reference/research/hitboxes-for-shots-2026-09-28.md).
## Bodies made here of a hull, a skeleton of two bones and a capsule on
## each, as a player's are hung: under the body, beside the skeleton.
##
## Every check is inside an open tick, where the bridge goes by what a set
## says of itself: a body that walked off, one left alone, a death and a
## revival, bones followed, a side swap's new set, the shooter's own set,
## the world scanned again.
## The last shows that the rule is kept by the oracle every check file has
## on: a capsule moved with its set not told is met where it was, and that
## is caught.
##
##   godot --headless --path . --script tests/run_hitbox_set_checks.gd
##
## Needs nothing extracted, and the Box3D addon.

const CHEST_HEIGHT := 40.0
const HEAD_HEIGHT := 64.0
const CAPSULES: Array[Dictionary] = [
	{"bone": "spine", "name": "chest", "zone": &"chest", "side": &"", "point0": Vector3(0, -5, 0), "point1": Vector3(0, 5, 0), "radius": 6.0},
	{"bone": "head", "name": "head", "zone": &"head", "side": &"", "point0": Vector3(0, -2, 0), "point1": Vector3(0, 2, 0), "radius": 4.0},
]


class Body:
	extends RefCounted
	var hull: CharacterBody3D
	var skeleton: Skeleton3D
	var target: HitTarget
	var skin: SkinnedHitboxes

	func chest() -> Hitbox:
		return skin.hitboxes[0]

	func head() -> Hitbox:
		return skin.hitboxes[1]


var _host: Node3D
var _game: GameSystems
var _adapter: Box3DDrops
var _queries: Box3DQueries


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("hitbox-sets", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	_check_walked_off()
	_check_death_and_revival()
	_check_bones_followed()
	_check_side_swap()
	_check_shooters_own()
	_check_rescanned()
	_check_untold_is_caught()
	_finish("hitbox-sets")


func _print_passes() -> bool:
	return true


## A body moved by hand in a tick, as the range moves its dummy: a round
## along where it stood meets nothing, one along where it stands meets it.
## And a body nowhere near either line is left as the bridge last put it,
## which is the saving, until a round comes its way.
func _check_walked_off() -> void:
	_open()
	var near := _body("Near", Vector3(0, 0, 0))
	var far := _body("Far", Vector3(0, 0, 600))
	_queries.begin_tick()
	_check(_along(0.0).get("collider") == near.chest(),
		"a round along a body's chest meets it")
	near.hull.position.z = 300.0
	far.hull.position.z = 900.0
	_check(_along(0.0).is_empty(),
		"the body moved by hand in the tick, a round along where it stood meets nothing")
	_check(_put_at(far.chest()) != far.chest().global_transform,
		"a body no round has come near is left as it was put, 300 units from where it stands")
	_check(_along(300.0).get("collider") == near.chest() and _along(300.0, HEAD_HEIGHT).get("collider") == near.head(),
		"and one along where it stands meets it, chest and head")
	_check(_along(900.0).get("collider") == far.chest() and _put_at(far.chest()) == far.chest().global_transform,
		"the other is met where it stands by the first round that comes its way, and is put there then")
	_check(_along(600.0).is_empty(), "and not where it stood")
	_queries.end_tick()
	_close()


## Someone killed earlier in a tick is met by no round after, which goes on
## to whoever stands behind; revived, they are met again.
func _check_death_and_revival() -> void:
	_open()
	var front := _body("Front", Vector3(0, 0, 0))
	var behind := _body("Behind", Vector3(100, 0, 0))
	_queries.begin_tick()
	_check(_along(0.0).get("collider") == front.chest(), "of two in a line a round meets the one in front")
	front.target.set_active(false)
	_check(front.skin.on_layer == 0 and _along(0.0).get("collider") == behind.chest(),
		"the one in front killed in the tick, the next round meets the one behind")
	_check(_along(0.0, HEAD_HEIGHT).get("collider") == behind.head(), "at the head as at the chest")
	front.target.set_active(true)
	_check(front.skin.on_layer == 2 and _along(0.0).get("collider") == front.chest(),
		"revived in the tick, the one in front is met again")
	_queries.end_tick()
	_close()


## Bones followed in a tick (a body built, or posed by hand as the checks
## pose them): the capsules are met where the bones put them.
func _check_bones_followed() -> void:
	_open()
	var body := _body("Posed", Vector3(0, 0, 0))
	_queries.begin_tick()
	_check(_along(0.0).get("collider") == body.chest(), "a round meets the chest where the bone is")
	body.skeleton.set_bone_pose_position(0, Vector3(0, CHEST_HEIGHT, 120))
	body.skin.follow()
	_check(_along(0.0).is_empty() and _along(120.0).get("collider") == body.chest(),
		"the bone moved and followed in the tick, the chest is met where the bone is now and not where it was")
	_check(_along(0.0, HEAD_HEIGHT).get("collider") == body.head(), "and the head, whose bone did not move, where it was")
	_queries.end_tick()
	_close()


## A side swap at a tick's end: the body's set taken out of the tree and
## another built in its place (PlayerSim.change_team). A round meets the
## new set's capsules, and none of the old.
func _check_side_swap() -> void:
	_open()
	var body := _body("Swapped", Vector3(0, 0, 0))
	_queries.begin_tick()
	var old_chest := body.chest()
	_check(_along(0.0).get("collider") == old_chest, "a round meets the body's chest")
	body.hull.remove_child(body.skin)
	body.skin.queue_free()
	body.target.drop_hitboxes()
	body.skin = SkinnedHitboxes.new()
	body.skin.name = "Hitboxes"
	body.hull.add_child(body.skin)
	body.skin.build(body.skeleton, CAPSULES, body.target, 1.0)
	body.target.set_active(true)
	var met := _along(0.0)
	_check(met.get("collider") == body.chest() and body.chest() != old_chest,
		"its set dropped and another built in the tick, a round meets the new chest")
	body.hull.position.z = 200.0
	_check(_along(0.0).is_empty() and _along(200.0).get("collider") == body.chest(),
		"which goes with the body when it moves")
	_queries.end_tick()
	_close()


## A round leaves its shooter's own hitboxes out. They are not brought up
## to date for it, and it meets whoever is in front; the next shooter's
## round meets them where they are.
func _check_shooters_own() -> void:
	_open()
	var shooter := _body("Shooter", Vector3(-100, 0, 0))
	var other := _body("Other", Vector3(100, 0, 0))
	_queries.begin_tick()
	# Both put once, as a round from somewhere else would have left them.
	_check(_along(0.0, HEAD_HEIGHT).get("collider") == shooter.head(), "a round from behind meets the first of two")
	shooter.hull.position.z = 50.0
	other.hull.position.z = 50.0
	var own: Array[RID] = [shooter.hull.get_rid()]
	own.append_array(shooter.target.rids())
	var from_its_head := Vector3(-100, HEAD_HEIGHT, 50)
	var met := _shot(from_its_head, from_its_head + Vector3.RIGHT * 400, own)
	_check(met.get("collider") == other.head(),
		"both moved, a round from the first's own head, its own left out, meets the other where it stands")
	_check(_put_at(shooter.head()) != shooter.head().global_transform,
		"and leaves its own as they were put: nothing of them can be met by it")
	_check(_along(50.0, HEAD_HEIGHT).get("collider") == shooter.head() and _along(0.0, HEAD_HEIGHT).is_empty(),
		"the next round, from someone else, meets the shooter where it stands")
	_queries.end_tick()
	_close()


## The world's statics taken in again in a tick, as the range does when its
## cover changes (Box3DDrops.capture_world): every hitbox is put where it
## stands by the scan, not by its set. What was put of the set is no longer
## known, and the next round brings it up to date whatever its line.
func _check_rescanned() -> void:
	_open()
	var body := _body("Rescanned", Vector3(0, 0, 0))
	_queries.begin_tick()
	_check(_along(0.0).get("collider") == body.chest(), "a round meets the chest")
	body.hull.position.z = 250.0
	_queries.refresh_statics()
	_check(_put_at(body.chest()) == body.chest().global_transform,
		"the body moved and the world scanned again, the scan has put its hitboxes where it stands")
	body.hull.position.z = 500.0
	_check(_along(250.0).is_empty(),
		"moved again, a round along where the scan put them meets nothing: the set was not known, and was put")
	_check(_along(500.0).get("collider") == body.chest() and _along(0.0).is_empty(),
		"and one along where it stands meets it")
	_queries.end_tick()
	_close()


## The rule the bridge goes by is that a set is told of every change. A
## capsule moved with its set not told, in a tick, is met where it was:
## and the oracle every check has on says so, which is what holds the
## rule. Its fault is taken back out here, having been looked for.
func _check_untold_is_caught() -> void:
	_open()
	var body := _body("Untold", Vector3(0, 0, 0))
	_queries.begin_tick()
	_check(_along(0.0).get("collider") == body.chest(), "a round meets the chest")
	var faults_before := Box3DQueries.set_faults.size()
	body.chest().global_position += Vector3(0, 0, 150)
	var met := _along(0.0)
	var caught := Box3DQueries.set_faults.size() - faults_before
	_check(met.get("collider") == body.chest() and caught == 1,
		"a capsule moved with its set not told is met where it was, and the oracle counts it (%d)" % caught)
	met = _along(150.0)
	caught = Box3DQueries.set_faults.size() - faults_before
	_check(met.is_empty() and caught == 2,
		"and passed where it is, which the oracle counts too (%d)" % caught)
	body.skin.changes += 1
	_check(_along(150.0).get("collider") == body.chest() and _along(0.0).is_empty()
		and Box3DQueries.set_faults.size() - faults_before == 2,
		"its set told, it is met where it is and nothing more is counted")
	_queries.end_tick()
	# Looked for, and found: not this file's faults.
	Box3DQueries.set_faults.resize(faults_before)
	_close()


## A round along +x at a height, across the line z: from 200 units before
## the bodies to 400 past them.
func _along(z: float, height: float = CHEST_HEIGHT) -> Dictionary:
	return _shot(Vector3(-300, height, z), Vector3(500, height, z), [])


func _shot(from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Hitscan.WORLD_LAYER | Hitbox.LAYER, exclude)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return PhysicsQueries.intersect_ray(_host.get_world_3d().direct_space_state, query)


## Where the bridge last put a hitbox.
func _put_at(hitbox: Hitbox) -> Transform3D:
	var objects: Dictionary = _queries.get("_objects")
	return (objects[hitbox.get_instance_id()] as Dictionary).get("at", Transform3D())


func _body(named: String, at: Vector3) -> Body:
	var body := Body.new()
	body.hull = CharacterBody3D.new()
	body.hull.name = named
	body.hull.collision_layer = 2
	body.hull.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(32, 72, 32)
	collision.shape = box
	collision.position.y = 36.0
	body.hull.add_child(collision)
	body.hull.position = at
	_host.add_child(body.hull)
	body.skeleton = Skeleton3D.new()
	body.skeleton.add_bone("spine")
	body.skeleton.add_bone("head")
	body.skeleton.set_bone_pose_position(0, Vector3(0, CHEST_HEIGHT, 0))
	body.skeleton.set_bone_pose_position(1, Vector3(0, HEAD_HEIGHT, 0))
	body.hull.add_child(body.skeleton)
	body.target = HitTarget.new()
	body.target.build_own_hitboxes = false
	body.target.build_visual = false
	body.hull.add_child(body.target)
	body.skin = SkinnedHitboxes.new()
	body.skin.name = "Hitboxes"
	body.hull.add_child(body.skin)
	body.skin.build(body.skeleton, CAPSULES, body.target, 1.0)
	return body


func _open() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_game = GameSystems.new()
	_adapter = Box3DDrops.new()
	_host.add_child(_adapter)
	_check(_adapter.initialize(_game, _host, true), "the native world of the checks is made")
	_queries = _adapter.queries


func _close() -> void:
	_host.free()
	for system in _game.systems():
		if system is ItemDrops:
			system.game = null
	_game.last_tick = null
