class_name HitQuads
extends Node3D

## Animated hit particles in batches, with independent atlas rectangles for
## both frames and their motion texture. prepare() owns loading/allocation;
## card() only writes instance data. Existing shot quads keep their API.

const SHADERS := {
	"alpha": preload("res://src/effects/hit_mix.gdshader"),
	"add": preload("res://src/effects/hit_add.gdshader"),
	"premul": preload("res://src/effects/hit_premul.gdshader"),
}
const FIRST_CAPACITY := 64
const MOST_CARDS := 4096
const FLOATS := 20

class Batch:
	var node: MultiMeshInstance3D
	var mesh: MultiMesh
	var animation: SpriteSheet
	var material: ShaderMaterial
	var data := PackedFloat32Array()
	var count := 0
	var threshold := 0.0

var _batches := {}
var _quad := QuadMesh.new()


func _ready() -> void:
	for shader: Shader in SHADERS.values():
		shader.get_rid()


## Prepares each authored renderer while the map loads. Multiple renderers
## that share the same textures, motion scale, gradient and blend share a
## batch; threshold remains per particle, allowing distance-driven CP4.x.
func prepare(renderer: Dictionary) -> void:
	var key := _key(renderer)
	if _batches.has(key):
		return
	var sheet := SpriteSheet.named(String(renderer.get("tex", "")))
	if sheet == null:
		_batches[key] = null
		return
	var motion := SpriteSheet.named(String(renderer.get("tex_mv", ""))) if renderer.has("tex_mv") else null
	var batch := Batch.new()
	batch.animation = sheet if not sheet.sequences.is_empty() or motion == null else motion
	var color_metadata := sheet.frame_metadata()
	var flow_metadata := motion.frame_metadata() if motion != null else null
	if motion != null and not motion.sequences.is_empty() and _is_static(sheet):
		# The second forward-spray renderer pairs five static-smoke sequences
		# with three animated blood-flow sequences. Each has its own wrap;
		# expand a common timeline rather than reading frame 0 of flow forever.
		var pair := _static_overlay(sheet, motion)
		batch.animation = pair[0]
		color_metadata = pair[0].frame_metadata()
		flow_metadata = pair[1].frame_metadata()
	batch.mesh = MultiMesh.new()
	batch.mesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh.use_colors = true
	batch.mesh.use_custom_data = true
	batch.mesh.mesh = _quad
	batch.mesh.instance_count = FIRST_CAPACITY
	batch.mesh.visible_instance_count = 0
	batch.material = ShaderMaterial.new()
	batch.material.shader = SHADERS.get(String(renderer.get("blend", "alpha")), SHADERS["alpha"])
	batch.material.set_shader_parameter(&"effect_texture", sheet.texture)
	batch.material.set_shader_parameter(&"frame_rects", color_metadata)
	batch.material.set_shader_parameter(&"motion_enabled", motion != null)
	if motion != null:
		batch.material.set_shader_parameter(&"motion_texture", motion.texture)
		batch.material.set_shader_parameter(&"motion_rects", flow_metadata)
		# Source 2's texture header describes maximum displacement in pixels.
		# Treating the renderer's authored -8/-16 override as pixels in that
		# same atlas space is inferred; engine-side override units are closed.
		var scale := Vector2(float(renderer.get("motion_u", 1.0)), float(renderer.get("motion_v", 1.0)))
		scale /= Vector2(motion.texture.get_width(), motion.texture.get_height())
		batch.material.set_shader_parameter(&"motion_scale", scale)
	var stops: Array = renderer.get("gradient", [])
	batch.material.set_shader_parameter(&"gradient_enabled", not stops.is_empty())
	if not stops.is_empty():
		batch.material.set_shader_parameter(&"color_gradient", _gradient(stops))
		batch.material.set_shader_parameter(&"gradient_multiply", String(renderer.get("gradient_blend", "SPRITECARD_TEXTURE_BLEND_MULTIPLY")) == "SPRITECARD_TEXTURE_BLEND_MULTIPLY")
		# MIX_RGBA's ramp reads premultiplied input RGB; MIX_RGB reads RGB.
		batch.material.set_shader_parameter(&"gradient_premul_input", String(renderer.get("gradient_channels", "SPRITECARD_TEXTURE_CHANNEL_MIX_RGBA")) == "SPRITECARD_TEXTURE_CHANNEL_MIX_RGBA")
		var strength: Variant = renderer.get("gradient_strength", 1.0)
		batch.material.set_shader_parameter(&"gradient_strength", float(strength) if strength is float or strength is int else 1.0)
	var alpha: Variant = renderer.get("alpha_threshold", 0.0)
	batch.threshold = float(alpha[0]) if alpha is Array and not alpha.is_empty() else (float(alpha) if alpha is float or alpha is int else 0.0)
	batch.node = MultiMeshInstance3D.new()
	batch.node.multimesh = batch.mesh
	batch.node.material_override = batch.material
	batch.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.node.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	batch.node.visible = false
	add_child(batch.node)
	_batches[key] = batch


func begin() -> void:
	for batch: Batch in _batches.values():
		if batch != null:
			batch.count = 0
			batch.data.clear()


## frame is normalized sequence time, as SpriteSheet.frame() takes it.
## A caller resolves optional dynamic alpha_threshold from the hit's CPs;
## it changes coverage rather than allocating one material per distance.
func card(renderer: Dictionary, xform: Transform3D, sequence: int, frame: float, color: Color, alpha_threshold: float = -1.0) -> void:
	var batch: Batch = _batches.get(_key(renderer))
	if batch == null or batch.count >= MOST_CARDS:
		return
	if batch.count >= batch.mesh.instance_count:
		batch.mesh.instance_count = mini(batch.mesh.instance_count * 2, MOST_CARDS)
	var animation := batch.animation.interpolation_data(sequence, frame)
	var threshold := batch.threshold if alpha_threshold < 0.0 else clampf(alpha_threshold, 0.0, 0.99999)
	var b := xform.basis
	var o := xform.origin
	batch.data.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
		color.r, color.g, color.b, color.a, animation.x, animation.y, animation.z, threshold,
	]))
	batch.count += 1


func finish() -> void:
	for batch: Batch in _batches.values():
		if batch == null:
			continue
		batch.node.visible = batch.count > 0
		batch.mesh.visible_instance_count = batch.count
		if batch.count > 0:
			batch.data.resize(batch.mesh.instance_count * FLOATS)
			batch.mesh.buffer = batch.data


func cards() -> int:
	var count := 0
	for batch: Batch in _batches.values():
		if batch != null:
			count += batch.count
	return count


## Interned canonical keys cache their hash and still compare full identity,
## so hash collisions cannot make different authored materials share a batch.
## HitParticles stores this on its private renderer copies during startup.
static func key(renderer: Dictionary) -> StringName:
	if renderer.has("_hit_quad_key"):
		return renderer._hit_quad_key
	return StringName(JSON.stringify([renderer.get("tex", ""), renderer.get("tex_mv", ""), renderer.get("blend", "alpha"),
		renderer.get("motion_u", 1.0), renderer.get("motion_v", 1.0), renderer.get("gradient", []),
		renderer.get("gradient_blend", "SPRITECARD_TEXTURE_BLEND_MULTIPLY"),
		renderer.get("gradient_channels", "SPRITECARD_TEXTURE_CHANNEL_MIX_RGBA"), renderer.get("gradient_strength", 1.0)]))


static func _key(renderer: Dictionary) -> StringName:
	return key(renderer)


static func _gradient(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop: Array in stops:
		if stop.size() < 2 or not stop[1] is Array or stop[1].size() < 3:
			continue
		offsets.append(float(stop[0]))
		var rgb: Array = stop[1]
		colors.append(Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0).srgb_to_linear())
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.use_hdr = true
	texture.width = 256
	return texture


static func _is_static(sheet: SpriteSheet) -> bool:
	for frames: Array in sheet.sequences:
		if frames.size() > 1:
			return false
	return true


static func _static_overlay(color: SpriteSheet, flow: SpriteSheet) -> Array[SpriteSheet]:
	var color_count := maxi(1, color.sequences.size())
	var flow_count := flow.sequences.size()
	var a := color_count
	var b := flow_count
	while b > 0:
		var rest := a % b
		a = b
		b = rest
	@warning_ignore("integer_division")
	var sequence_count := color_count * flow_count / a
	var color_sequences := []
	var flow_sequences := []
	for sequence in sequence_count:
		var source := sequence % flow_count
		var rectangle := color.frame(sequence, 0.0)
		var color_frames := []
		var flow_frames := []
		for flow_rectangle: Rect2 in flow.sequences[source]:
			color_frames.append([rectangle.position.x,rectangle.position.y,rectangle.end.x,rectangle.end.y])
			flow_frames.append([flow_rectangle.position.x,flow_rectangle.position.y,flow_rectangle.end.x,flow_rectangle.end.y])
		var shown: PackedFloat32Array = flow.times[source]
		color_sequences.append({"frames":color_frames,"times":shown,"clamp":flow.clamped[source]})
		flow_sequences.append({"frames":flow_frames,"times":shown,"clamp":flow.clamped[source]})
	var color_sheet := SpriteSheet.new()
	var flow_sheet := SpriteSheet.new()
	color_sheet.read({"sequences":color_sequences})
	flow_sheet.read({"sequences":flow_sequences})
	return [color_sheet,flow_sheet]
