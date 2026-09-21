class_name ExportOffsetFix
extends RefCounted

## Puts overlays and depth-biased geometry back where the map has them.
##
## glTF has no depth bias, so Source 2 Viewer's exporter moves geometry that
## relies on one out along its vertex normals, to stop it z-fighting with the
## surface it lies on. As of version 20 it moves it 0.3937 metres, which is
## 15.5 inches: 0.01 multiplied by the inches in a metre, where a hundredth of
## an inch was evidently meant. Measured on dust2: every overlay on the map
## floats 15.50 units off the surface behind it, to the second decimal place,
## and a window inset compared with its own source model fits
## "position + 15.48 x normal" to within a twentieth of a unit.
##
## On a flat overlay that is a sign hanging in the air a foot off its wall. On
## a solid shape it is worse, because pushing every vertex along its own normal
## inflates the shape: dust2's window insets come out as flared boxes standing
## proud of the holes they are meant to sit in.
##
## The fix is the same arithmetic backwards, on the exported .bin. Only
## POSITION is rewritten, and only for the vertices a qualifying primitive
## actually indexes. Nothing is decided from names: what qualifies is the three
## things found displaced, and nothing else on the map was.

## What the exporter adds, in the glTF's metres.
const EXPORTED_PUSH := 0.01 / 0.0254

## What is left in place, in metres: a quarter of an inch, which is how far
## Valve's own non-overlay signage on dust2 stands off its wall, and plenty for
## a reversed floating point depth buffer.
const KEPT_PUSH := 0.25 * 0.0254

const FLOAT := 5126
const INDEX_SIZES := {5121: 1, 5123: 2, 5125: 4}

## A file next to the .bin recording that it has been corrected, so that a
## second run does not correct it twice. A fresh export is newer than the
## marker and gets corrected again.
const MARKER_SUFFIX := ".offsets-fixed"


## Whether a glTF material, as a parsed dictionary, is one the exporter pushes.
static func is_pushed(material: Dictionary) -> bool:
	var extras: Variant = material.get("extras", {})
	if not extras is Dictionary:
		return false
	var vmat: Variant = (extras as Dictionary).get("vmat", {})
	if not vmat is Dictionary:
		return false
	if String((vmat as Dictionary).get("ShaderName", "")).contains("static_overlay"):
		return true
	var flags: Variant = (vmat as Dictionary).get("IntParams", {})
	if not flags is Dictionary:
		return false
	return (
		int((flags as Dictionary).get("F_OVERLAY", 0)) == 1
		or int((flags as Dictionary).get("F_DEPTH_BIAS", 0)) == 1
	)


## Corrects one glTF's .bin in place. Returns the number of vertices moved: 0
## if there was nothing to do or it had been done already, -1 if the file could
## not be handled, having said why.
static func fix_file(gltf_path: String) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	if not parsed is Dictionary:
		push_warning("Could not read %s as JSON." % gltf_path)
		return -1
	var gltf: Dictionary = parsed
	var materials: Array = gltf.get("materials", [])
	var accessors: Array = gltf.get("accessors", [])
	var views: Array = gltf.get("bufferViews", [])
	var buffers: Array = gltf.get("buffers", [])

	var primitives: Array[Dictionary] = []
	for mesh: Dictionary in gltf.get("meshes", []):
		for primitive: Dictionary in mesh.get("primitives", []):
			var material_index := int(primitive.get("material", -1))
			if material_index < 0 or material_index >= materials.size():
				continue
			if is_pushed(materials[material_index]):
				primitives.append(primitive)
	if primitives.is_empty():
		return 0

	if buffers.size() != 1 or String(buffers[0].get("uri", "")).begins_with("data:"):
		push_warning("%s: expected one external buffer; left alone." % gltf_path)
		return -1
	var bin_path := gltf_path.get_base_dir().path_join(String(buffers[0]["uri"]).uri_decode())
	var marker_path := bin_path + MARKER_SUFFIX
	if (
		FileAccess.file_exists(marker_path)
		and FileAccess.get_modified_time(marker_path) >= FileAccess.get_modified_time(bin_path)
	):
		return 0

	var file := FileAccess.open(bin_path, FileAccess.READ_WRITE)
	if file == null:
		push_warning("Could not open %s for writing." % bin_path)
		return -1

	var shift := EXPORTED_PUSH - KEPT_PUSH
	# By position in the file, in case two primitives share a POSITION accessor.
	var moved := {}
	for primitive in primitives:
		var attributes: Dictionary = primitive.get("attributes", {})
		if not (attributes.has("POSITION") and attributes.has("NORMAL") and primitive.has("indices")):
			continue
		var positions := _layout(accessors[int(attributes["POSITION"])], views)
		var normals := _layout(accessors[int(attributes["NORMAL"])], views)
		var index_accessor: Dictionary = accessors[int(primitive["indices"])]
		var indices := _layout(index_accessor, views)
		var index_size: int = INDEX_SIZES.get(int(index_accessor.get("componentType", 0)), 0)
		if positions.is_empty() or normals.is_empty() or indices.is_empty() or index_size == 0:
			push_warning("%s: a primitive is not laid out as expected; left alone." % gltf_path)
			continue

		file.seek(indices["offset"])
		var index_bytes := file.get_buffer(int(index_accessor["count"]) * index_size)
		for i in int(index_accessor["count"]):
			var vertex: int
			match index_size:
				1: vertex = index_bytes.decode_u8(i)
				2: vertex = index_bytes.decode_u16(i * 2)
				_: vertex = index_bytes.decode_u32(i * 4)
			var at: int = positions["offset"] + vertex * positions["stride"]
			if moved.has(at):
				continue
			moved[at] = true

			file.seek(normals["offset"] + vertex * normals["stride"])
			var normal := Vector3(file.get_float(), file.get_float(), file.get_float())
			if normal.is_zero_approx():
				continue
			file.seek(at)
			var position := Vector3(file.get_float(), file.get_float(), file.get_float())
			position -= normal.normalized() * shift
			file.seek(at)
			file.store_float(position.x)
			file.store_float(position.y)
			file.store_float(position.z)
	file.close()

	# Godot decides whether to reimport a glTF by the .gltf alone, and that has
	# not changed. Trailing whitespace is still valid JSON, and changes it.
	var text := FileAccess.open(gltf_path, FileAccess.READ_WRITE)
	if text != null:
		text.seek_end()
		text.store_string("\n")
		text.close()

	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(
			"%d vertices moved back %.4f m along their normals by ExportOffsetFix.\n"
			% [moved.size(), shift]
		)
		marker.close()
	return moved.size()


## Where an accessor's elements are in the file: {"offset", "stride"} in bytes,
## or empty if it is not something this reads (sparse, or without a view).
static func _layout(accessor: Dictionary, views: Array) -> Dictionary:
	if not accessor.has("bufferView") or accessor.has("sparse"):
		return {}
	var view: Dictionary = views[int(accessor["bufferView"])]
	var component_size := 4 if int(accessor.get("componentType", 0)) == FLOAT else int(
		INDEX_SIZES.get(int(accessor.get("componentType", 0)), 0)
	)
	var components: int = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}.get(accessor.get("type", ""), 0)
	if component_size == 0 or components == 0:
		return {}
	var stride := int(view.get("byteStride", 0))
	return {
		"offset": int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0)),
		"stride": stride if stride > 0 else component_size * components,
	}
