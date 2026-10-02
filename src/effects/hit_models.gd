class_name HitModels
extends Node3D

## Actual extracted flecks and the Rush Hour impact_puff mesh, pooled by
## mesh group. No packed scenes are instantiated while a hit is drawn.
const CAPACITY := 64
const PUFF_SHADER := preload("res://src/effects/hit_puff.gdshader")
var _groups := {}


func prepare(renderer: Dictionary) -> void:
	var path := String(renderer.get("model", ""))
	if path.is_empty() or _groups.has(path):
		return
	_groups[path] = []
	var file := "res://assets/effects/impacts/" + path.get_basename() + ".glb"
	if not ResourceLoader.exists(file):
		return
	var scene := load(file) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate()
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	for part: MeshInstance3D in meshes:
		var mesh := part.mesh
		if mesh == null:
			continue
		# glTF model groups are surfaces; each authored variant is one group.
		for surface in mesh.get_surface_count():
			var group_mesh := ArrayMesh.new()
			group_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), mesh.surface_get_arrays(surface))
			var batch := {"node": MultiMeshInstance3D.new(), "mm": MultiMesh.new(), "data": PackedFloat32Array(), "count": 0}
			batch.mm.transform_format = MultiMesh.TRANSFORM_3D
			batch.mm.use_colors = true
			batch.mm.mesh = group_mesh
			batch.mm.instance_count = CAPACITY
			batch.mm.visible_instance_count = 0
			batch.node.multimesh = batch.mm
			batch.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.node.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
			if path.contains("impact_puff"):
				var material := ShaderMaterial.new()
				material.shader = PUFF_SHADER
				var def: Dictionary = HitEffectTable.MATERIALS.get("materials/effects/smoke_puff_dirt.vmat", {})
				var textures: Dictionary = def.get("textures", {})
				var color := SpriteSheet.named(String(textures.get("g_tColor", "")))
				var mask := SpriteSheet.named(String(textures.get("g_tMask1", "")))
				if color != null:
					material.set_shader_parameter(&"puff_color", color.texture)
				if mask != null:
					material.set_shader_parameter(&"puff_mask", mask.texture)
				batch.node.material_override = material
			else:
				var material := StandardMaterial3D.new()
				material.vertex_color_use_as_albedo = true
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color(0.55, 0.48, 0.4)
				material.roughness = 1.0
				batch.node.material_override = material
			add_child(batch.node)
			(_groups[path] as Array).append(batch)
	model.free()


func begin() -> void:
	for groups: Array in _groups.values():
		for b: Dictionary in groups:
			b.count = 0
			b.data = PackedFloat32Array()


func card(renderer: Dictionary, xform: Transform3D, variant: int, color: Color) -> void:
	var groups: Array = _groups.get(String(renderer.get("model", "")), [])
	if groups.is_empty():
		return
	var batch: Dictionary = groups[posmod(variant, groups.size())]
	if int(batch.count) >= CAPACITY:
		return
	var b := xform.basis
	var o := xform.origin
	var data: PackedFloat32Array = batch.data
	data.append_array(PackedFloat32Array([
		b.x.x,b.y.x,b.z.x,o.x,b.x.y,b.y.y,b.z.y,o.y,b.x.z,b.y.z,b.z.z,o.z,
		color.r,color.g,color.b,color.a]))
	batch.data = data
	batch.count += 1


func finish() -> void:
	for groups: Array in _groups.values():
		for b: Dictionary in groups:
			b.node.visible = int(b.count) > 0
			if int(b.count) == 0:
				continue
			var data: PackedFloat32Array = b.data
			data.resize(CAPACITY * 16)
			b.mm.buffer = data
			b.mm.visible_instance_count = b.count
