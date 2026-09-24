class_name MapOccluders
extends RefCounted

## Lets the map's own walls hide what is behind them.
##
## Without occluders Godot culls by the camera's frustum alone, so every
## mesh in front of the camera is drawn, and drawn again into every shadow
## split that sees it: from B tunnels, the whole of long, mid and A with it.
## CS2 culls with visibility it precomputed when the map was compiled.
## Godot's own occlusion culling does the same thing a frame at a time: it
## rasterises the occluders on the CPU at a low resolution and skips any
## mesh whose bounds are behind them.
##
## The occluders are the world's own opaque surfaces (the lightmapped brush
## work: walls, floors, roofs), as one ArrayOccluder3D under the importer.
## Props are left out (a crate or a car hides little and is often cut out
## with alpha), and so is anything with an alpha edge, an overlay or a
## translucent layer, which the eye sees through. Triangles smaller than
## MIN_AREA are dropped: they hide next to nothing and cost the CPU as much
## as a large one.
##
## How much this saves depends on how the export splits the world into
## meshes, since a mesh is culled only when all of its bounds are hidden:
## scripts/profile_render.gd counts both (no_occlusion).

## The world's shader, which is what a wall, floor or roof is drawn with.
const WORLD_SHADER := "csgo_lightmappedgeneric.vfx"

## In square units, after the import's scale: a triangle smaller than an
## eight-inch square hides nothing worth the test.
const MIN_AREA := 64.0

## The flags that make a surface something the eye sees through.
const SEE_THROUGH_FLAGS := ["F_ALPHA_TEST", "F_TRANSLUCENT", "F_OVERLAY", "F_BLEND"]


## Builds one occluder from these meshes' opaque world surfaces, in parent's
## space, and adds it under parent. Returns how many triangles it holds;
## nothing is added when there are none.
static func build(parent: Node3D, meshes: Array[MeshInstance3D]) -> int:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var transform := relative_transform(parent, mesh_instance)
		for surface in mesh.get_surface_count():
			if not occludes(mesh_instance.get_active_material(surface)):
				continue
			_append(mesh, surface, transform, vertices, indices)
	if indices.is_empty():
		return 0
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(vertices, indices)
	var instance := OccluderInstance3D.new()
	instance.name = "Occluders"
	instance.occluder = occluder
	parent.add_child(instance)
	@warning_ignore("integer_division")
	return indices.size() / 3


## node's transform in parent's space, whether or not either is in the tree
## yet. node has to be under parent.
static func relative_transform(parent: Node, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != parent:
		if at is Node3D:
			transform = (at as Node3D).transform * transform
		at = at.get_parent()
	return transform


## Whether a surface with this material hides what is behind it: the
## world's shader, and nothing the eye sees through.
static func occludes(material: Material) -> bool:
	if material == null:
		return false
	var description := BlendMaterials.vmat(material)
	if String(description.get("ShaderName", "")) != WORLD_SHADER:
		return false
	var flags: Variant = description.get("IntParams", {})
	if flags is Dictionary:
		for flag in SEE_THROUGH_FLAGS:
			if int((flags as Dictionary).get(flag, 0)) != 0:
				return false
	if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	return true


static func _append(
	mesh: Mesh, surface: int, transform: Transform3D, vertices: PackedVector3Array, indices: PackedInt32Array
) -> void:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var source_index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var base := vertices.size()
	for vertex in source:
		vertices.append(transform * vertex)
	var count := source_index.size() if not source_index.is_empty() else source.size()
	for corner in range(0, count - 2, 3):
		var i0 := source_index[corner] if not source_index.is_empty() else corner
		var i1 := source_index[corner + 1] if not source_index.is_empty() else corner + 1
		var i2 := source_index[corner + 2] if not source_index.is_empty() else corner + 2
		var a := vertices[base + i0]
		var area := (vertices[base + i1] - a).cross(vertices[base + i2] - a).length() * 0.5
		if area < MIN_AREA:
			continue
		indices.append(base + i0)
		indices.append(base + i1)
		indices.append(base + i2)
