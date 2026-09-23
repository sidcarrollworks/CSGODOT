class_name Hitbox
extends Area3D

## One damage zone on a target.
##
## Separate areas rather than one capsule, because where you hit decides the
## damage and that is most of what makes CS shooting feel fair: a head is worth
## four chests, and the player has to believe the game agreed with them about
## which one they hit.

## The physics layer hitboxes live on. Kept off the world layer so a trace can
## tell the difference between hitting a wall and hitting a person.
const LAYER := 4

@export var zone: StringName = &"chest"

## Which side of the body, for a limb: &"left", &"right", or nothing.
@export var side: StringName = &""

## The thing that takes the damage. Set by whoever builds the hitboxes.
var target: HitTarget


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


## Zone colours for a drawn hitbox, the way a hitbox viewer paints them:
## the head stands out, the limbs sit back.
const ZONE_COLOURS := {
	&"head": Color(1.0, 0.25, 0.2),
	&"chest": Color(0.25, 0.75, 1.0),
	&"stomach": Color(0.3, 1.0, 0.55),
	&"arm": Color(1.0, 0.85, 0.25),
	&"leg": Color(0.8, 0.45, 1.0),
}
const DRAWN_ALPHA := 0.3
const FLASH_ALPHA := 0.85
const FLASH_SECONDS := 0.25

## The visual layers the drawing goes on: the world's, unless the hitbox
## belongs to a body only some cameras may see (PlayerSim.UNSEEN_LAYER).
var drawn_layers: int = 1

var _drawn: MeshInstance3D
var _flash: Tween


## Draws the hitbox's own shape over whatever it sits on, seen through the
## body, so where a round can land is visible rather than guessed. Off,
## nothing is drawn. The drawing is the collision shape, not a copy of its
## numbers, so it cannot disagree with what the trace hits.
func set_drawn(on: bool) -> void:
	if not on:
		if _drawn != null:
			_drawn.queue_free()
			_drawn = null
		return
	if _drawn != null:
		return
	var mesh := drawn_mesh()
	if mesh == null:
		return
	_drawn = MeshInstance3D.new()
	_drawn.name = "Drawn"
	_drawn.mesh = mesh
	_drawn.transform = _collision().transform
	_drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drawn.layers = drawn_layers
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.render_priority = 1
	var colour: Color = ZONE_COLOURS.get(zone, Color.WHITE)
	colour.a = DRAWN_ALPHA
	material.albedo_color = colour
	_drawn.material_override = material
	add_child(_drawn)


func is_drawn() -> bool:
	return _drawn != null


## A mesh the shape of this hitbox's collision shape, or null for a shape
## it does not know how to draw.
func drawn_mesh() -> Mesh:
	var collision := _collision()
	if collision != null:
		var shape := collision.shape
		if shape is CapsuleShape3D:
			var capsule := CapsuleMesh.new()
			capsule.radius = (shape as CapsuleShape3D).radius
			capsule.height = (shape as CapsuleShape3D).height
			capsule.radial_segments = 16
			capsule.rings = 4
			return capsule
		if shape is BoxShape3D:
			var box := BoxMesh.new()
			box.size = (shape as BoxShape3D).size
			return box
		if shape is SphereShape3D:
			var sphere := SphereMesh.new()
			sphere.radius = (shape as SphereShape3D).radius
			sphere.height = sphere.radius * 2.0
			return sphere
	return null


func _collision() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


## Lights the drawn hitbox up for a moment: the one a round just went into.
func flash() -> void:
	if _drawn == null or not is_inside_tree():
		return
	var material := _drawn.material_override as StandardMaterial3D
	if _flash != null:
		_flash.kill()
	material.albedo_color.a = FLASH_ALPHA
	_flash = create_tween()
	_flash.tween_property(material, "albedo_color:a", DRAWN_ALPHA, FLASH_SECONDS)
