class_name EffectQuads
extends Node3D

## Draws the shots' effects (tracers, flashes, sparks, smoke) as flat cards,
## one MultiMesh a texture, blend and view, filled afresh every frame: a
## few hundred cards cost a few draw calls, not a few hundred nodes.
##
## Each frame, begin(), a quad() for every card, finish(). A card is placed
## and turned on the CPU (sprite() and streak() build its transform), and
## carries its texture rectangle (a sheet's frame) and its colour. A card
## drawn in first person goes in a batch with the view model's projection
## (ViewModelProjection), so it sits where the drawn gun is, at the arms'
## narrowing as it is this frame: a scope changes it.
##
## A batch's cards go to its MultiMesh whole, in one buffer at finish().
## Set a card at a time, a new or regrown MultiMesh first takes a copy of
## its instances from the GPU: the first cards of each new batch held a
## first shot's frame up 2 to 4 ms each (dust2, 4K;
## reference/godot/rendering.md, "MultiMesh").

const SHADERS := {
	&"add": preload("res://src/effects/effect_add.gdshader"),
	&"mix": preload("res://src/effects/effect_mix.gdshader"),
	&"premul": preload("res://src/effects/effect_premul.gdshader"),
	&"lit": preload("res://src/effects/effect_lit.gdshader"),
}
## The most cards one batch draws; past it a frame's extra cards are left out.
const MOST_CARDS := 4096
const FIRST_CAPACITY := 64
## A card's floats in the buffer: its transform (12, by rows), its colour
## (4) and its texture rectangle (4, the custom data).
const FLOATS := 20

var _batches := {}
var _quad := QuadMesh.new()
## The arms' narrowing the first-person batches are drawn at.
var _narrowing := ViewModelProjection.fov_narrowing()


class Batch:
	var node: MultiMeshInstance3D
	var multimesh: MultiMesh
	## This frame's cards, FLOATS each, as the MultiMesh takes them.
	var data := PackedFloat32Array()
	var count := 0
	var first_person := false


## Compiles the cards' shaders as the map loads. A shader is compiled the
## first time a material asks for it, and the first tracer and flash of a
## match did that inside their frame: 6.6 ms for add, 10.3 for lit.
func _ready() -> void:
	for shader: Shader in SHADERS.values():
		shader.get_rid()


## Starts a frame at the arms' narrowing (ViewModelProjection.narrowing_under):
## every batch empties.
func begin(narrowing: float = ViewModelProjection.fov_narrowing()) -> void:
	var narrowed := not is_equal_approx(narrowing, _narrowing)
	_narrowing = narrowing
	for batch: Batch in _batches.values():
		batch.count = 0
		batch.data.clear()
		if narrowed and batch.first_person:
			_project(batch)


## One card: texture's rectangle uv (UV, a frame of its sheet) on a unit
## quad placed by xform (sprite(), streak()), coloured by color, whose
## rgb may run past 1 (CS2's overbright), blended by blend (add, mix,
## premul, or lit: mixed and lit by the scene). color is linear, as Godot draws; ends, where given, [head,
## tail]: a streak's colour scale at its head (the card's top) and its tail,
## 0-255 as CS2's are (decoded in the shader). Nothing without a texture.
func quad(texture: Texture2D, blend: StringName, first_person: bool, xform: Transform3D, uv: Rect2, color: Color, ends: Array = []) -> void:
	if texture == null:
		return
	var batch := _batch(texture, blend, first_person, ends)
	if batch.count >= MOST_CARDS:
		return
	if batch.count >= batch.multimesh.instance_count:
		# More room, empty; the cards so far go in with the rest at finish().
		batch.multimesh.instance_count = mini(batch.multimesh.instance_count * 2, MOST_CARDS)
	var b := xform.basis
	var o := xform.origin
	batch.data.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		color.r, color.g, color.b, color.a, uv.position.x, uv.position.y, uv.end.x, uv.end.y,
	]))
	batch.count += 1


## Ends a frame: each batch draws what it was given, sent in one buffer
## (the rest of its room zeroes).
func finish() -> void:
	for batch: Batch in _batches.values():
		batch.node.visible = batch.count > 0
		if batch.count == 0:
			continue
		batch.data.resize(batch.multimesh.instance_count * FLOATS)
		batch.multimesh.buffer = batch.data
		batch.multimesh.visible_instance_count = batch.count


## How many cards were drawn this frame, over every batch.
func cards() -> int:
	var total := 0
	for batch: Batch in _batches.values():
		total += batch.count
	return total


## A card facing the camera (whose transform is eye) at centre, half its
## side across, turned roll radians in the view: a sprite.
static func sprite(centre: Vector3, half: float, roll: float, eye: Transform3D) -> Transform3D:
	var right := eye.basis.x.rotated(eye.basis.z, roll)
	var up := eye.basis.y.rotated(eye.basis.z, roll)
	return Transform3D(Basis(right * half * 2.0, up * half * 2.0, eye.basis.z), centre)


## A card from tail to head, half_width either side, turned about its length
## to face the camera at eye_position: a streak. The card's top (V 0) is
## the head.
static func streak(tail: Vector3, head: Vector3, half_width: float, eye_position: Vector3) -> Transform3D:
	var along := head - tail
	var middle := (head + tail) * 0.5
	var across := along.cross(eye_position - middle)
	if across.length_squared() < 1e-8:
		across = along.cross(Vector3.UP if absf(along.normalized().y) < 0.99 else Vector3.RIGHT)
	across = across.normalized() * half_width * 2.0
	var facing := across.cross(along)
	facing = facing.normalized() if facing.length_squared() > 1e-12 else Vector3.BACK
	return Transform3D(Basis(across, along, facing), middle)


func _batch(texture: Texture2D, blend: StringName, first_person: bool, ends: Array = []) -> Batch:
	var key := "%d:%s:%s:%s" % [texture.get_instance_id(), blend, first_person, ends]
	var batch: Batch = _batches.get(key)
	if batch != null:
		return batch
	batch = Batch.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = _quad
	batch.multimesh.instance_count = FIRST_CAPACITY
	batch.multimesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = SHADERS.get(blend, SHADERS[&"add"])
	material.set_shader_parameter(&"effect_texture", texture)
	if ends.size() == 2:
		material.set_shader_parameter(&"head_tint", ends[0])
		material.set_shader_parameter(&"tail_tint", ends[1])
	batch.node = MultiMeshInstance3D.new()
	batch.node.multimesh = batch.multimesh
	batch.node.material_override = material
	batch.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cards are anywhere on the map; nothing is gained by culling the batch.
	batch.node.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	batch.first_person = first_person
	if first_person:
		_project(batch)
	add_child(batch.node)
	_batches[key] = batch
	return batch


func _project(batch: Batch) -> void:
	batch.node.set_instance_shader_parameter(&"view_model_projection",
		Vector2(_narrowing, ViewModelProjection.DEPTH_SQUEEZE))
