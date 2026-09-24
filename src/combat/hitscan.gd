class_name Hitscan
extends RefCounted

## Traces a bullet and works out what it hit and for how much.
##
## Hitboxes sit on their own physics layer so a trace can distinguish a wall
## from a person, and both are queried in one ray so the nearer one wins. That
## matters: a shot that clips the corner of a wall must not register on the
## enemy behind it, and it is the sort of thing that feels like broken hit
## registration when it goes wrong. What it does instead is try to go
## through the wall, which a rifle round gets through when the wall is thin
## enough and made of the right thing, as in CS2 (trace).

const WORLD_LAYER := 1


## One wall a round went through: where it went in and came out, what it
## was made of, and what it cost the round.
class Wall:
	var entry: Vector3
	var entry_normal: Vector3
	var exit: Vector3
	var exit_normal: Vector3
	## The hull part's names on the way in and out, and the CS2 surface each
	## is (SurfaceProperties, lower-case).
	var surface: String = ""
	var exit_surface: String = ""
	var material: String = "default"
	var thickness: float = 0.0
	## The share of the round's damage that came out the other side.
	var kept: float = 1.0


## The result of tracing one bullet.
class Result:
	var hit: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var distance: float = 0.0
	## Null when the bullet hit the world rather than a person.
	var hitbox: Hitbox = null
	var zone: StringName = &""
	var damage: float = 0.0
	## The name of the part of the world it hit, if it hit the world: the
	## collision hull names its parts by material (physics_group_sand).
	var surface: String = ""
	## The walls it went through first, in order. Where it ended up
	## (position, hitbox, surface) is past the last of them.
	var walls: Array[Wall] = []
	## The share of its damage that got through them: 1 with none.
	var kept: float = 1.0
	## What the round did to whoever it hit (fire_as), or null.
	var damage_info: DamageInfo

	## Whether it met anything: something it stopped at, or a wall it went
	## through on its way into nothing.
	func touched() -> bool:
		return hit or not walls.is_empty()

	## The first thing it met, where a hole in a wall it went through
	## counts: what a spray on a wall reads.
	func first_contact() -> Vector3:
		return walls[0].entry if not walls.is_empty() else position


## Traces a round through whatever it can get through.
##
## Each ray stops at the nearest wall or person. A person ends it. A wall
## is looked through for its far side (_find_exit); if the round has the
## power to get that far through what the wall is made of, it comes out
## there with less power and less damage (Penetration) and carries on, and
## if not it stops in the wall. A round never goes through more than
## Penetration.MOST_WALLS, nor into the sky.
static func trace(
	space: PhysicsDirectSpaceState3D,
	shot: Weapon.Shot,
	data: WeaponData,
	exclude: Array[RID] = []
) -> Result:
	var result := Result.new()
	var end := shot.origin + shot.direction * data.max_range
	var from := shot.origin
	var power := data.penetration_power
	while true:
		var query := PhysicsRayQueryParameters3D.create(from, end, WORLD_LAYER | Hitbox.LAYER, exclude)
		# Hitboxes are areas, so they have to be opted into explicitly.
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var collision := space.intersect_ray(query)
		if collision.is_empty():
			return result

		var collider = collision["collider"]
		if collider is Hitbox:
			_hit_person(result, shot, data, collider, collision["position"], collision["normal"])
			return result

		var surface := _surface_name(collision)
		var entry: Vector3 = collision["position"]
		var normal: Vector3 = collision["normal"]
		if (
			result.walls.size() >= Penetration.MOST_WALLS
			or surface.contains("sky")
			or not collider is CollisionObject3D
		):
			_stop(result, shot, entry, normal, surface)
			return result

		var exit := _find_exit(space, entry, shot.direction, Penetration.deepest(power), exclude)
		if exit.is_empty():
			_stop(result, shot, entry, normal, surface)
			return result
		var wall := Wall.new()
		wall.entry = entry
		wall.entry_normal = normal
		wall.exit = exit["position"]
		wall.exit_normal = exit["normal"]
		wall.surface = surface
		wall.exit_surface = _surface_name(exit)
		wall.material = Penetration.surface_for(surface)
		wall.thickness = entry.distance_to(wall.exit)
		# A wall that is one thing on the way in and another on the way
		# out is taken as half of each.
		var modifiers := (
			Penetration.modifiers(wall.material)
			+ Penetration.modifiers(Penetration.surface_for(wall.exit_surface))
		) * 0.5
		var cost := Penetration.cost(wall.thickness, modifiers.x)
		if cost > power:
			_stop(result, shot, entry, normal, surface)
			return result
		power -= cost
		wall.kept = Penetration.kept(wall.thickness, modifiers.y, data.penetration_power)
		result.walls.append(wall)
		result.kept *= wall.kept

		# Someone standing half in the wall, in a doorway, is hit in it.
		var inside := PhysicsRayQueryParameters3D.create(entry, wall.exit, Hitbox.LAYER, exclude)
		inside.collide_with_areas = true
		inside.collide_with_bodies = false
		var person := space.intersect_ray(inside)
		if not person.is_empty() and person["collider"] is Hitbox:
			_hit_person(result, shot, data, person["collider"], person["position"], person["normal"])
			return result

		var distance := shot.origin.distance_to(wall.exit)
		if distance >= data.max_range or data.damage_at(distance) * result.kept < Penetration.SPENT_BELOW:
			return result
		from = wall.exit + shot.direction * EXIT_GAP
	return result


## A gap left between a wall's far side and where the round carries on, so
## the next ray does not find the face it has just come out of.
const EXIT_GAP := 0.01


static func _hit_person(
	result: Result, shot: Weapon.Shot, data: WeaponData,
	hitbox: Hitbox, at: Vector3, normal: Vector3
) -> void:
	result.hit = true
	result.position = at
	result.normal = normal
	result.distance = shot.origin.distance_to(at)
	result.hitbox = hitbox
	result.zone = hitbox.zone
	result.damage = (
		data.damage_at(result.distance) * data.hitbox_multiplier(hitbox.zone) * result.kept
	)


static func _stop(result: Result, shot: Weapon.Shot, at: Vector3, normal: Vector3, surface: String) -> void:
	result.hit = true
	result.position = at
	result.normal = normal
	result.distance = shot.origin.distance_to(at)
	result.surface = surface


## The name of the hull part a ray met: its collision shape's node name.
static func _surface_name(collision: Dictionary) -> String:
	var collider = collision.get("collider")
	if collider is CollisionObject3D and not collider is Hitbox and collision.has("shape"):
		var owner_id: int = (collider as CollisionObject3D).shape_find_owner(collision["shape"])
		var shape_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if shape_node != null:
			return shape_node.name
	return ""


## The far side of the wall a round went into at entry, going along
## direction, no deeper than depth: its position, normal and shape, as
## intersect_ray gives them, or empty if the wall goes on further than
## that (or has no far side, like the sky).
##
## Found by looking back from depth into the wall: the first face met that
## faces that way is the wall's far side. Faces turned the other way, and a
## ray that starts inside a solid, are not hits, so another wall that depth
## reaches into is looked straight through. One that depth reaches past,
## beyond a gap, would be found instead; so the way back from there is
## checked for a face turned towards the round, and if there is one the
## look back starts again from just in front of it.
static func _find_exit(
	space: PhysicsDirectSpaceState3D, entry: Vector3, direction: Vector3,
	depth: float, exclude: Array[RID]
) -> Dictionary:
	var near := entry + direction * EXIT_GAP
	var far := entry + direction * depth
	for i in 8:
		if far.distance_to(entry) <= EXIT_GAP * 2.0:
			return {}
		var back := PhysicsRayQueryParameters3D.create(far, near, WORLD_LAYER, exclude)
		back.hit_back_faces = false
		back.hit_from_inside = false
		var exit := space.intersect_ray(back)
		if exit.is_empty():
			return {}
		var ahead := PhysicsRayQueryParameters3D.create(
			near, (exit["position"] as Vector3) - direction * EXIT_GAP, WORLD_LAYER, exclude
		)
		ahead.hit_back_faces = false
		ahead.hit_from_inside = false
		var between := space.intersect_ray(ahead)
		if between.is_empty():
			return exit
		far = (between["position"] as Vector3) - direction * EXIT_GAP
	return {}


## Who fired a round, for the damage it does to say so: their userid
## (Roster), their side and the share a round of theirs does to it, what a
## trace leaves out (their own hull and hitboxes), and the game's events,
## which hear of every surface the round meets (bullet_impact) and of the
## damage (player_hurt, player_death). Null events for none.
class Shooter:
	var userid: int = GameEvents.NOBODY
	var team: String = ""
	var team_damage_scale: float = 1.0
	var exclude: Array[RID] = []
	var events: GameEvents

	func _init(
		p_userid: int = GameEvents.NOBODY, p_team: String = "", p_team_damage_scale: float = 1.0,
		p_exclude: Array[RID] = [], p_events: GameEvents = null
	) -> void:
		userid = p_userid
		team = p_team
		team_damage_scale = p_team_damage_scale
		exclude = p_exclude
		events = p_events


## Traces and applies the damage in one step, from nobody in particular.
static func fire_at(
	space: PhysicsDirectSpaceState3D,
	shot: Weapon.Shot,
	data: WeaponData,
	exclude: Array[RID] = [],
	shooter_team: String = "",
	team_damage_scale: float = 1.0
) -> Result:
	return fire_as(space, shot, data, Shooter.new(
		GameEvents.NOBODY, shooter_team, team_damage_scale, exclude
	))


## Traces a round fired by shooter and deals its damage through a
## DamageInfo, so the victim knows who hit them with what: the gun's CS2
## class (WeaponData.item_class), the walls it went through, where from.
## Each wall's way in and the round's end are bullet_impacts, as CS2 sends
## one for every surface a round meets (whether CS2 also sends a wall's way
## out is not checked).
static func fire_as(
	space: PhysicsDirectSpaceState3D,
	shot: Weapon.Shot,
	data: WeaponData,
	shooter: Shooter
) -> Result:
	var result := trace(space, shot, data, shooter.exclude)
	if shooter.events != null:
		for wall in result.walls:
			_send_impact(shooter, wall.entry, shot)
		if result.hit:
			_send_impact(shooter, result.position, shot)
	if result.hitbox != null and result.hitbox.target != null:
		var target := result.hitbox.target
		var same_side := not shooter.team.is_empty() and target.team == shooter.team
		# A teammate's round does its share (friendly fire), before armour.
		if same_side:
			result.damage *= shooter.team_damage_scale
		target.last_hit_direction = shot.direction
		target.last_hit_from = shot.origin
		target.last_hit_weapon = data
		var info := DamageInfo.new()
		info.attacker = shooter.userid
		info.inflictor = data.item_class
		info.weapon = data.item_class
		info.damage = result.damage
		info.damage_type = DamageInfo.DMG_BULLET
		info.zone = result.zone
		info.side = result.hitbox.side
		info.hitbox = result.hitbox
		info.origin = shot.origin
		info.position = result.position
		info.direction = shot.direction
		info.at_usec = shot.timestamp_usec
		info.armor_penetration = data.armor_penetration
		info.walls = result.walls.size()
		info.noscope = shot.noscope
		result.damage = DamageInfo.deal(target, info, shooter.events)
		result.damage_info = info
	return result


static func _send_impact(shooter: Shooter, at: Vector3, shot: Weapon.Shot) -> void:
	shooter.events.send(&"bullet_impact", {
		"userid": shooter.userid, "x": at.x, "y": at.y, "z": at.z,
	}, shot.timestamp_usec)
