class_name MapOccluders
extends RefCounted

## Lets the map's own walls hide what is behind them.
##
## Without occluders Godot culls by the camera's frustum alone, so every
## mesh in front of the camera is drawn: from B tunnels, the whole of long,
## mid and A with it. CS2 culls with visibility it precomputed when the map
## was compiled, which WorldVisibility reads: what the camera's cluster
## cannot see is not drawn, from anywhere in the cluster. Godot's own
## occlusion culling does it a frame at a time: it rasterises the occluders
## on the CPU at a low resolution and skips any mesh whose bounds are behind
## them from where the camera stands, so it also hides some of what the
## visibility leaves in. The two run together, and the profiler measures
## each (RenderVariants' no_visibility and no_occlusion). The occluders cull
## the camera's pass only, not the shadow maps.
##
## The occluders are the map's collision hull: the solid volumes the player
## walks against, which a player's eye can never be inside. They were first
## built from the drawn world's faces, and that went wrong on dust2 (Sid's
## machine, 2026-09-24): an occluder blocks from both sides where the face it
## came from is drawn from one, so a face seen from behind, invisible on
## screen, hid most of the map at long doors and the buildings down mid from
## top of mid.
##
## Left out: the parts that stop only players (player clips) or only
## grenades, parts named for something the eye sees through (glass, grates,
## fences, foliage), and parts that are never drawn (NOT_DRAWN). Triangles
## smaller than MIN_AREA are dropped: they hide next to nothing and cost the
## CPU as much as a large one.
##
## An occluder has to be something drawn and opaque. Godot shifts the
## occlusion buffer by a third or a sixth of a pixel each way, in a cycle of
## nine frames (raycast_occlusion_cull.cpp, jitter_projection), so a mesh
## whose box straddles an occluder's edge is culled on some frames and drawn
## on others, with the camera still. Along a drawn wall's edge the wall hides that; along
## an invisible one, the mesh flickers against the sky (Sid's dust2 playtest,
## 2026-09-25, issue 11).

## In square units, after the import's scale: a triangle smaller than an
## eight-inch square hides nothing worth the test.
const MIN_AREA := 64.0

## Hull part name fragments the eye sees through, beside the importer's own
## lists of parts that are not the world's walls.
const SEE_THROUGH := ["glass", "grate", "fence", "chain", "wire", "foliage", "passbullets"]

## Hull part name fragments for parts nobody sees. dust2's physics_sky is its
## sky brushes, 266 triangles, and not only an outer shell: slabs of it hang
## over mid, one of them just above the rooftops seen from top of mid, and
## what was behind them flickered. No CS2 surface name holds "sky"
## (reference/surfaces/surfaces.csv), so it matches only the sky's part.
const NOT_DRAWN := ["sky"]


## Builds one occluder from these hull meshes, in parent's space, and adds it
## under parent, leaving out any whose name holds one of skip, SEE_THROUGH or
## NOT_DRAWN.
## Returns how many triangles it holds; nothing is added when there are none.
static func build(parent: Node3D, hull: Array[MeshInstance3D], skip: PackedStringArray = PackedStringArray()) -> int:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for mesh_instance in hull:
		if mesh_instance.mesh == null or not occludes(mesh_instance.name, skip):
			continue
		var transform := relative_transform(parent, mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			_append(mesh_instance.mesh, surface, transform, vertices, indices)
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


## Whether a hull part by this name hides what is behind it.
static func occludes(part: String, skip: PackedStringArray = PackedStringArray()) -> bool:
	var lower := part.to_lower()
	for fragment in SEE_THROUGH + NOT_DRAWN + Array(skip):
		if lower.contains(String(fragment).to_lower()):
			return false
	return true


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
