class_name CoverPanel
extends StaticBody3D

## A wall to shoot the test range's dummy through: a panel standing across
## its lane just in front of it, made of one of CS2's surfaces at a
## thickness, and M steps through them. Its collision is named the way
## dust2's hull names its parts (physics_group_wood_plank), so a round
## meets it exactly as it would a wall on the map, and Hitscan decides
## from that name whether it gets through and what it keeps.
##
## The thicknesses are round numbers to feel the difference by, not
## measurements of dust2's doors and boxes, which live in Sid's extracted
## hull.

## What M steps through: off, then CS2 surfaces from what a round gets
## through easily to what it does not get through at all.
const CHOICES := [
	{"name": "no wall"},
	{"name": "wooden door", "surface": "wood_plank", "thickness": 4.0, "colour": Color(0.55, 0.38, 0.22)},
	{"name": "wooden crate", "surface": "wood_crate", "thickness": 12.0, "colour": Color(0.62, 0.46, 0.28)},
	{"name": "sheet metal", "surface": "metalpanel", "thickness": 2.0, "colour": Color(0.55, 0.58, 0.62)},
	{"name": "solid metal", "surface": "solidmetal", "thickness": 4.0, "colour": Color(0.35, 0.37, 0.40)},
	{"name": "plaster", "surface": "plaster", "thickness": 6.0, "colour": Color(0.86, 0.82, 0.72)},
	{"name": "thin concrete", "surface": "concrete", "thickness": 6.0, "colour": Color(0.62, 0.62, 0.60)},
	{"name": "concrete wall", "surface": "concrete", "thickness": 16.0, "colour": Color(0.50, 0.50, 0.49)},
]
## How wide and tall it stands: enough to hide a standing player.
const SIZE := Vector2(128.0, 160.0)
## How far in front of the dummy it stands.
const IN_FRONT := 64.0

var index: int = 0
var _mesh: MeshInstance3D
var _collision: CollisionShape3D
var _sign: Label3D


func _ready() -> void:
	collision_layer = Hitscan.WORLD_LAYER
	collision_mask = 0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = BoxMesh.new()
	_mesh.material_override = StandardMaterial3D.new()
	add_child(_mesh)
	_collision = CollisionShape3D.new()
	_collision.shape = BoxShape3D.new()
	add_child(_collision)
	_sign = Label3D.new()
	_sign.font_size = 32
	_sign.pixel_size = 0.25
	_sign.outline_size = 8
	_sign.shaded = false
	_sign.double_sided = false
	add_child(_sign)
	show_choice(0)


## Stands it in front of a spot, across a lane that runs down -Z.
func stand_before(target: Vector3) -> void:
	global_position = Vector3(target.x, SIZE.y * 0.5, target.z + IN_FRONT)


func next() -> void:
	show_choice((index + 1) % CHOICES.size())


func show_choice(at: int) -> void:
	index = at
	var choice: Dictionary = CHOICES[index]
	var up := choice.has("surface")
	visible = up
	# Off is no collision at all, so the lane is as it always was.
	_collision.disabled = not up
	if not up:
		return
	var thickness: float = choice["thickness"]
	var size := Vector3(SIZE.x, SIZE.y, thickness)
	(_mesh.mesh as BoxMesh).size = size
	(_mesh.material_override as StandardMaterial3D).albedo_color = choice["colour"]
	(_collision.shape as BoxShape3D).size = size
	_collision.name = "physics_group_%s" % choice["surface"]
	_sign.text = describe()
	_sign.position = Vector3(0.0, SIZE.y * 0.5 + 12.0, thickness * 0.5 + 0.2)


func standing() -> bool:
	return CHOICES[index].has("surface")


## What it is, for the sign and the readout: its name, its thickness and
## CS2's two numbers for its surface.
func describe() -> String:
	var choice: Dictionary = CHOICES[index]
	if not standing():
		return "no wall"
	var modifiers := Penetration.modifiers(choice["surface"])
	return "%s, %.0f u  (%s: reach %.2f, damage %.2f)" % [
		choice["name"], choice["thickness"], Penetration.display_name(choice["surface"]),
		modifiers.x, modifiers.y,
	]
