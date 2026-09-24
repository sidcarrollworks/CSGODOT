class_name HeldPose
extends RefCounted

## Where a player holds what is in hand, and which way it points, from the
## game's own state: where they stand, look and crouch. What a drop throws
## from (ItemDrops), so it leaves as it was held. No animated bone is read:
## the bodies animate per frame, and a server and a client would not agree on
## a bone's pose at a tick.
##
## The offsets are CS2's, measured from its third-person clips: the gun's wpn
## bone in frame 0 of each set's idle, from the eye (64 standing, 46
## crouched), forward, to the right and up; that is the hold looking level,
## barrel forward and top up. It is turned with the view's pitch as CS2's
## third-person AimCS bends the upper body, and the gun, with the aim, on the
## server (reference/research/hitboxes-aim.md 1). How far CS2 turns it, and
## about what point, is in Valve's code and no file: the whole pitch about
## the eye is a stand-in until that page's section 7 measures it. The bodies
## drawn here do not bend with the aim yet, so a death looking far up or
## down lets the gun go from where the drawn body did not hold it. The pose
## is in the world models' own axes: +Z the muzzle, +Y the top, +X the gun's
## left side. It follows the body's crouch as PlayerBody moves it
## (duck_progress), so an eased duck in the air comes with the movement's.

## rifle/rifle_ak, standing and crouched; every long gun is held so.
const RIFLE_STAND := Vector3(13.7, 4.7, -3.7)
const RIFLE_CROUCH := Vector3(10.4, 3.1, -7.7)
## pistol/_default_pistol (pistol_glock the same): pistols and the Zeus.
const PISTOL_STAND := Vector3(21.3, 1.6, -6.3)
const PISTOL_CROUCH := Vector3(21.0, 0.8, -6.3)
## grenade/_default_grenade: held low at the hip.
const GRENADE_STAND := Vector3(0.8, 12.6, -17.3)
const GRENADE_CROUCH := Vector3(-1.0, 9.7, -16.5)


## The pose of item_class in node's hand. node is read by duck typing (a
## check's stand-in player has only a position): its yaw and pitch, its
## eye height and how far down it is crouched, where it has them.
static func of(node: Node3D, item_class: String) -> Transform3D:
	var yaw := _number(node, &"yaw_degrees", 0.0)
	var pitch := _number(node, &"pitch_degrees", 0.0)
	var crouch := MovementSolver.simple_spline(_number(node, &"duck_progress", 0.0))
	var eye_height := float(node.call(&"eye_height")) if node.has_method(&"eye_height") else 64.0
	var aim := PlayerInput.aim_direction(yaw, pitch)
	var right := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
	var view := Basis(-right, aim.cross(-right), aim)
	var offsets := offsets_for(item_class)
	var off: Vector3 = (offsets[0] as Vector3).lerp(offsets[1], crouch)
	var eye := node.global_position + Vector3.UP * eye_height
	return Transform3D(view, eye + aim * off.x + right * off.y + view.y * off.z)


## [standing, crouched] offsets from the eye for an item: forward, right, up.
static func offsets_for(item_class: String) -> Array:
	var item := ItemRegistry.item(item_class)
	if item != null and item.is_grenade():
		return [GRENADE_STAND, GRENADE_CROUCH]
	if item != null and (item.slot == ItemDef.Slot.PISTOL or item.type == "taser"):
		return [PISTOL_STAND, PISTOL_CROUCH]
	return [RIFLE_STAND, RIFLE_CROUCH]


static func _number(node: Node3D, property: StringName, fallback: float) -> float:
	var value = node.get(property)
	return float(value) if value is float or value is int else fallback
