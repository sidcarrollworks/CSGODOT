class_name Hitscan
extends RefCounted

## Traces a bullet and works out what it hit and for how much.
##
## Hitboxes sit on their own physics layer so a trace can distinguish a wall
## from a person, and both are queried in one ray so the nearer one wins. That
## matters: a shot that clips the corner of a wall must not register on the
## enemy behind it, and it is the sort of thing that feels like broken hit
## registration when it goes wrong.

const WORLD_LAYER := 1


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


static func trace(
	space: PhysicsDirectSpaceState3D,
	shot: Weapon.Shot,
	data: WeaponData,
	exclude: Array[RID] = []
) -> Result:
	var query := PhysicsRayQueryParameters3D.create(
		shot.origin,
		shot.origin + shot.direction * data.max_range,
		WORLD_LAYER | Hitbox.LAYER,
		exclude
	)
	# Hitboxes are areas, so they have to be opted into explicitly.
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result := Result.new()
	var collision := space.intersect_ray(query)
	if collision.is_empty():
		return result

	result.hit = true
	result.position = collision["position"]
	result.normal = collision["normal"]
	result.distance = shot.origin.distance_to(result.position)

	var collider = collision["collider"]
	if collider is CollisionObject3D and not collider is Hitbox and collision.has("shape"):
		var owner_id: int = (collider as CollisionObject3D).shape_find_owner(collision["shape"])
		var shape_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if shape_node != null:
			result.surface = shape_node.name
	if collider is Hitbox:
		var hitbox := collider as Hitbox
		result.hitbox = hitbox
		result.zone = hitbox.zone
		result.damage = (
			data.damage_at(result.distance) * data.hitbox_multiplier(hitbox.zone)
		)
	return result


## Traces and applies the damage in one step.
static func fire_at(
	space: PhysicsDirectSpaceState3D,
	shot: Weapon.Shot,
	data: WeaponData,
	exclude: Array[RID] = []
) -> Result:
	var result := trace(space, shot, data, exclude)
	if result.hitbox != null and result.hitbox.target != null:
		result.damage = result.hitbox.target.apply_damage(
			result.damage, result.zone, data.armor_penetration, result.hitbox
		)
	return result
