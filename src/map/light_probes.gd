class_name LightProbes
extends RefCounted

## The map's light probes: what CS2 lights everything without lightmap
## coordinates with, players and weapons and most props, from where they
## stand.
##
## CS2 bakes an ambient cube (the light arriving from the six axis
## directions) at every cell of a grid in each env_combined_light_probe_volume,
## a box of the map at a cell size the entity gives (24 units on dust2),
## and packs all the volumes into one 3D atlas whose depth is six bands, one
## per face: +X, +Y, +Z, -X, -Y, -Z in Source's axes. The entity says
## where in the atlas its cells are. Source 2 Viewer decompiles the atlas
## to one HDR image per depth slice; the first load packs those into one
## file of half floats beside them, and after that it is a read.
##
## A point is lit by the cube of the smallest volume that holds it, read
## with trilinear filtering, in the same units as the lightmaps (so at
## LightmapMaterials.ENERGY). The maths follows Source 2 Viewer's
## lighting.lpv.slang: local coordinates normalized to the volume's box,
## clamped half a texel in, then placed in the atlas.

## Where the extraction leaves the atlas slices and this writes its pack,
## relative to the directory the world glTF is in. A .gdignore keeps Godot
## from importing seven hundred tiny textures.
const PROBES_DIR := "lightmaps/probes"
const SLICE_STEM := "env_light_probe_volume_atlas_z"
const PACKED_FILE := "lightprobes.bin"
const ENTITIES_FILE := "entities/default_ents.vents"
const FACES := 6

var width: int = 0
var height: int = 0
## Depth of one face's band: the atlas holds FACES of them.
var band: int = 0
## Each volume: {"origin", "mins", "maxs" (Source axes, units, box
## relative to origin), "atlas" (texel offset), "size" (texels), "level"}.
var volumes: Array[Dictionary] = []

var _texels: PackedByteArray = PackedByteArray()  # RGB half floats


func is_loaded() -> bool:
	return band > 0 and not volumes.is_empty()


## An atlas given directly: width by height by FACES * band texels of RGB
## half floats, face band after face band. For tests and tools.
func set_atlas(atlas_width: int, atlas_height: int, face_band: int, texels: PackedByteArray) -> bool:
	if texels.size() != atlas_width * atlas_height * face_band * FACES * 6:
		return false
	width = atlas_width
	height = atlas_height
	band = face_band
	_texels = texels
	return true


## Loads a map's probes from its directory, or returns one that is not
## loaded when the atlas or the entity lump is not there.
static func load_for(map_dir: String) -> LightProbes:
	var probes := LightProbes.new()
	probes.volumes = read_volumes(map_dir.path_join(ENTITIES_FILE))
	if probes.volumes.is_empty():
		return probes
	var directory := ProjectSettings.globalize_path(map_dir.path_join(PROBES_DIR))
	if not probes._read_packed(directory.path_join(PACKED_FILE)):
		if probes._pack_slices(directory):
			probes._write_packed(directory.path_join(PACKED_FILE))
	return probes


## The probe volumes in an entity lump, in Source's axes.
static func read_volumes(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	for entity in SourceEntities.parse(path):
		if entity.get("classname", "") != "env_combined_light_probe_volume" and entity.get("classname", "") != "env_light_probe_volume":
			continue
		if not entity.has("light_probe_atlas_x"):
			continue
		out.append({
			"origin": SourceEntities.vector(entity.get("origin", "[ 0, 0, 0 ]")),
			"mins": SourceEntities.vector(entity.get("box_mins", "[ 0, 0, 0 ]")),
			"maxs": SourceEntities.vector(entity.get("box_maxs", "[ 0, 0, 0 ]")),
			"atlas": Vector3(
				float(entity.get("light_probe_atlas_x", "0")), float(entity.get("light_probe_atlas_y", "0")),
				float(entity.get("light_probe_atlas_z", "0"))
			),
			"size": Vector3(
				float(entity.get("light_probe_size_x", "1")), float(entity.get("light_probe_size_y", "1")),
				float(entity.get("light_probe_size_z", "1"))
			),
			"level": int(entity.get("indoor_outdoor_level", "0")),
			"voxel": float(entity.get("voxel_size", "24")),
		})
	return out


## The volume holding a game-space point, or -1: the smallest, since the
## map nests small rooms inside large volumes.
func volume_at(position: Vector3) -> int:
	var source := Vector3(position.z, position.x, position.y)
	var best := -1
	var best_extent := INF
	for index in volumes.size():
		var volume := volumes[index]
		var local: Vector3 = source - volume["origin"]
		var mins: Vector3 = volume["mins"]
		var maxs: Vector3 = volume["maxs"]
		if local.x < mins.x or local.y < mins.y or local.z < mins.z or local.x > maxs.x or local.y > maxs.y or local.z > maxs.z:
			continue
		var extent := (maxs - mins).length_squared()
		if extent < best_extent:
			best = index
			best_extent = extent
	return best


## The ambient cube at a game-space point, in game axes: the light from
## +X, -X, +Y, -Y, +Z, -Z, six colours. Black everywhere when not loaded
## or outside every volume.
func cube_at(position: Vector3) -> PackedColorArray:
	var cube := PackedColorArray()
	cube.resize(FACES)
	var index := volume_at(position)
	if index < 0 or band == 0:
		return cube
	var volume := volumes[index]
	var source: Vector3 = Vector3(position.z, position.x, position.y) - volume["origin"]
	var mins: Vector3 = volume["mins"]
	var size: Vector3 = volume["maxs"] - mins
	var normalized := Vector3(
		(source.x - mins.x) / maxf(size.x, 1e-6), (source.y - mins.y) / maxf(size.y, 1e-6), (source.z - mins.z) / maxf(size.z, 1e-6)
	)
	var texels: Vector3 = volume["size"]
	# Half a texel in from the box's edges, as the game clamps, then into
	# the atlas.
	var half := Vector3(0.5 / texels.x, 0.5 / texels.y, 0.5 / texels.z)
	normalized = normalized.clamp(half, Vector3.ONE - half)
	# Rows as the decompiled slices hold them: checked against the lightmap
	# at 379 world triangles (correlation 0.82 this way, 0.41 with the rows
	# flipped within the volume, 0.11 flipped over the image).
	var at: Vector3 = volume["atlas"] + normalized * texels - Vector3.ONE * 0.5
	# Source's faces, +X +Y +Z -X -Y -Z, to the game's: Source X is game
	# Z, Source Y is game X, Source Z is game Y.
	var faces := [1, 4, 2, 5, 0, 3]
	for face in FACES:
		cube[face] = _sample(at, faces[face])
	return cube


## The ambient light on a surface facing a game-space direction, from the
## cube: each face's light by the square of the normal's part along it.
static func shade(cube: PackedColorArray, normal: Vector3) -> Color:
	var n := normal.normalized()
	var weights := n * n
	var light := Color(0, 0, 0, 1)
	light += (cube[0] if n.x >= 0.0 else cube[1]) * weights.x
	light += (cube[2] if n.y >= 0.0 else cube[3]) * weights.y
	light += (cube[4] if n.z >= 0.0 else cube[5]) * weights.z
	light.a = 1.0
	return light


## Trilinear read of one face's band at a texel position.
func _sample(at: Vector3, face: int) -> Color:
	var base := Vector3i(floori(at.x), floori(at.y), floori(at.z))
	var fraction := at - Vector3(base)
	var result := Color(0, 0, 0, 1)
	for corner in 8:
		var offset := Vector3i(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
		var weight := (fraction.x if offset.x == 1 else 1.0 - fraction.x) \
			* (fraction.y if offset.y == 1 else 1.0 - fraction.y) \
			* (fraction.z if offset.z == 1 else 1.0 - fraction.z)
		if weight <= 0.0:
			continue
		var texel := _texel(
			clampi(base.x + offset.x, 0, width - 1), clampi(base.y + offset.y, 0, height - 1),
			clampi(base.z + offset.z, 0, band - 1) + face * band
		)
		result.r += texel.r * weight
		result.g += texel.g * weight
		result.b += texel.b * weight
	return result


func _texel(x: int, y: int, z: int) -> Color:
	var offset := ((z * height + y) * width + x) * 6
	return Color(_texels.decode_half(offset), _texels.decode_half(offset + 2), _texels.decode_half(offset + 4), 1.0)


## Packs the decompiled slices into memory: RGB half floats, slice by
## slice. Returns false without them.
func _pack_slices(directory: String) -> bool:
	var slices := PackedStringArray()
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	for file in dir.get_files():
		if file.begins_with(SLICE_STEM) and file.get_extension().to_lower() == "exr":
			slices.append(file)
	if slices.is_empty() or slices.size() % FACES != 0:
		return false
	slices.sort()
	var first := Image.load_from_file(directory.path_join(slices[0]))
	if first == null:
		return false
	width = first.get_width()
	height = first.get_height()
	@warning_ignore("integer_division")
	band = slices.size() / FACES
	_texels = PackedByteArray()
	for z in slices.size():
		var image := first if z == 0 else Image.load_from_file(directory.path_join(slices[z]))
		if image == null or image.get_width() != width or image.get_height() != height:
			band = 0
			return false
		# RGB half floats, which is the layout _texel reads.
		image.convert(Image.FORMAT_RGBH)
		_texels.append_array(image.get_data())
	return true


func _write_packed(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("LPV1")
	file.store_32(width)
	file.store_32(height)
	file.store_32(band)
	file.store_buffer(_texels)


func _read_packed(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != "LPV1":
		return false
	width = file.get_32()
	height = file.get_32()
	band = file.get_32()
	_texels = file.get_buffer(width * height * band * FACES * 6)
	if _texels.size() != width * height * band * FACES * 6:
		band = 0
		return false
	return true
