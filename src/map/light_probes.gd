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
## LightmapMaterials.energy()). The maths follows Source 2 Viewer's
## lighting.lpv.slang: local coordinates normalized to the volume's box,
## clamped half a texel in, then placed in the atlas.
##
## Beside it the atlas has a page of shadows (_dlshd): at every cell, how
## much of each light CS2 bakes a shadow for is blocked there, one channel a
## light as in the lightmaps' direct_light_shadows (MapShadows), one slice
## for each band's. Only the sun's channel is kept, turned into how much of
## the sun gets through, and drawn from a 3D texture (sun_texture) at every
## fragment of what the probes light, each instance told where its volume's
## cells are (shadow_placement).

## Where the extraction leaves the atlas slices and this writes its pack,
## relative to the directory the world glTF is in. A .gdignore keeps Godot
## from importing seven hundred tiny textures.
const PROBES_DIR := "lightmaps/probes"
const SLICE_STEM := "env_light_probe_volume_atlas_z"
const PACKED_FILE := "lightprobes.bin"
const SHADOW_STEM := "env_light_probe_volume_atlas_dlshd_z"
const PACKED_SHADOWS := "lightprobe_sun.bin"
const ENTITIES_FILE := "entities/default_ents.vents"
const FACES := 6
## The global shader uniform the sun's texture is handed to (project.godot,
## probe_lit.gdshaderinc).
const SUN_UNIFORM := &"probe_sun_visibility"

var width: int = 0
var height: int = 0
## Depth of one face's band: the atlas holds FACES of them.
var band: int = 0
## Each volume: {"origin", "mins", "maxs" (Source axes, units, box
## relative to origin), "atlas" (texel offset), "size" (texels), "level"}.
var volumes: Array[Dictionary] = []:
	set(value):
		volumes = value
		_origins.clear()

## Source's faces, +X +Y +Z -X -Y -Z, in the order of the game's: Source X
## is game Z, Source Y is game X, Source Z is game Y.
const FACE_ORDER := [1, 4, 2, 5, 0, 3]

var _texels: PackedByteArray = PackedByteArray()  # RGB half floats
## The sun's channel of the shadow page (MapShadows), or -1; and how much of
## the sun reaches each cell, a byte each (255 all of it), one band deep:
## empty without the page.
var sun_channel: int = -1
var _sun: PackedByteArray = PackedByteArray()
var _sun_texture: ImageTexture3D
## The volumes' boxes and sizes, packed for volume_at, which is asked for
## every model every frame: out of a dictionary each, the search took
## longer than the light.
var _origins := PackedVector3Array()
var _mins := PackedVector3Array()
var _maxs := PackedVector3Array()
var _extents := PackedFloat64Array()


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
## loaded when the atlas or the entity lump is not there. With the sun's
## channel of the shadow page (MapShadows.sun_channel_at), its shadows too.
static func load_for(map_dir: String, sun: int = -1) -> LightProbes:
	var probes := LightProbes.new()
	probes.volumes = read_volumes(map_dir.path_join(ENTITIES_FILE))
	if probes.volumes.is_empty():
		return probes
	var directory := ProjectSettings.globalize_path(map_dir.path_join(PROBES_DIR))
	if not probes._read_packed(directory.path_join(PACKED_FILE)):
		if probes._pack_slices(directory):
			probes._write_packed(directory.path_join(PACKED_FILE))
	if sun >= 0 and probes.band > 0:
		probes.sun_channel = sun
		if not probes._read_packed_sun(directory.path_join(PACKED_SHADOWS)):
			if probes._pack_sun_slices(directory):
				probes._write_packed_sun(directory.path_join(PACKED_SHADOWS))
		if probes._sun.is_empty():
			probes.sun_channel = -1
	return probes


## Whether the sun's baked shadow came with the probes.
func has_sun_shadows() -> bool:
	return sun_channel >= 0 and band > 0 and _sun.size() == width * height * band


## The sun's shadow given directly: width by height by band bytes, how much
## of the sun reaches each cell (255 all of it). For tests and tools.
func set_sun(channel: int, visibility: PackedByteArray) -> bool:
	if band == 0 or visibility.size() != width * height * band:
		return false
	sun_channel = channel
	_sun = visibility
	_sun_texture = null
	return true


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
	if _origins.size() != volumes.size():
		_pack_volumes()
	var source := Vector3(position.z, position.x, position.y)
	var best := -1
	var best_extent := INF
	for index in _origins.size():
		var local := source - _origins[index]
		var mins := _mins[index]
		var maxs := _maxs[index]
		if local.x < mins.x or local.y < mins.y or local.z < mins.z or local.x > maxs.x or local.y > maxs.y or local.z > maxs.z:
			continue
		var extent := _extents[index]
		if extent < best_extent:
			best = index
			best_extent = extent
	return best


## The volume holding the most of these game-space points, the smallest of
## those holding as many, so the one round them all where there is one; or
## -1 when none holds any. For a mesh the export merged from copies all over
## the map, which one point cannot stand for (ProbeMaterials.shadow_for).
func volume_holding(points: PackedVector3Array) -> int:
	if _origins.size() != volumes.size():
		_pack_volumes()
	var best := -1
	var best_count := 0
	var best_extent := INF
	for index in _origins.size():
		var mins := _mins[index]
		var maxs := _maxs[index]
		var count := 0
		for point in points:
			var local := Vector3(point.z, point.x, point.y) - _origins[index]
			if local.x >= mins.x and local.y >= mins.y and local.z >= mins.z \
					and local.x <= maxs.x and local.y <= maxs.y and local.z <= maxs.z:
				count += 1
		if count > best_count or (count == best_count and count > 0 and _extents[index] < best_extent):
			best = index
			best_count = count
			best_extent = _extents[index]
	return best


func _pack_volumes() -> void:
	_origins.clear()
	_mins.clear()
	_maxs.clear()
	_extents.clear()
	for volume in volumes:
		var mins: Vector3 = volume["mins"]
		var maxs: Vector3 = volume["maxs"]
		_origins.append(volume["origin"])
		_mins.append(mins)
		_maxs.append(maxs)
		_extents.append((maxs - mins).length_squared())


## The ambient cube at a game-space point, in game axes: the light from
## +X, -X, +Y, -Y, +Z, -Z, six colours. Black everywhere when not loaded
## or outside every volume.
func cube_at(position: Vector3) -> PackedColorArray:
	var cube := PackedColorArray()
	cube.resize(FACES)
	var index := volume_at(position)
	if index < 0 or band == 0:
		return cube
	# A trilinear read of each face's band: the eight texels round the point
	# and their weights are the same for every face, which is only a band
	# further into the atlas, so they are worked out once.
	var cells := _cells_around(index, position)
	var offsets: PackedInt64Array = cells[0]
	var weights: PackedFloat64Array = cells[1]
	var band_bytes := band * height * width * 6
	for face in FACES:
		var shift: int = FACE_ORDER[face] * band_bytes
		var light := Color(0, 0, 0, 1)
		for i in offsets.size():
			var byte := offsets[i] * 6 + shift
			light.r += _texels.decode_half(byte) * weights[i]
			light.g += _texels.decode_half(byte + 2) * weights[i]
			light.b += _texels.decode_half(byte + 4) * weights[i]
		cube[face] = light
	return cube


## How much of the sun reaches a game-space point past the static map, as
## the probes hold it, read as the shaders read sun_texture: 1 without the
## shadow page or outside every volume.
func sun_at(position: Vector3) -> float:
	var index := volume_at(position)
	if index < 0 or not has_sun_shadows():
		return 1.0
	var cells := _cells_around(index, position)
	var offsets: PackedInt64Array = cells[0]
	var weights: PackedFloat64Array = cells[1]
	var sun := 0.0
	for i in offsets.size():
		sun += _sun[offsets[i]] / 255.0 * weights[i]
	return sun


## Where the cells of the volume holding a game-space point lie in
## sun_texture, for a shader to read it at any point near there:
## [scale, offset, least, most], so that a point in Source's axes times the
## scale plus the offset is where to read the texture, kept between least
## and most, half a cell inside the volume's block. The scale's w is 1.
## Empty without the shadow page or outside every volume.
func shadow_placement(position: Vector3) -> Array:
	return volume_placement(volume_at(position))


## The same for a volume by its index (volume_at, volume_holding): empty for
## -1, or without the page.
func volume_placement(index: int) -> Array:
	if index < 0 or index >= volumes.size() or not has_sun_shadows():
		return []
	var volume := volumes[index]
	var box_min: Vector3 = volume["origin"] + volume["mins"]
	var box_size: Vector3 = (volume["maxs"] as Vector3) - (volume["mins"] as Vector3)
	var texels: Vector3 = volume["size"]
	var atlas: Vector3 = volume["atlas"]
	var dims := Vector3(width, height, band)
	var per_unit := texels / box_size.max(Vector3.ONE * 1e-6)
	var scale := per_unit / dims
	return [
		Vector4(scale.x, scale.y, scale.z, 1.0),
		(atlas - box_min * per_unit) / dims,
		(atlas + Vector3.ONE * 0.5) / dims,
		(atlas + texels - Vector3.ONE * 0.5) / dims,
	]


## The sun's shadow as a 3D texture, one byte a cell, how much of the sun
## gets through; made once. Null without the shadow page.
func sun_texture() -> ImageTexture3D:
	if not has_sun_shadows():
		return null
	if _sun_texture == null:
		var slices: Array[Image] = []
		var slice_bytes := width * height
		for z in band:
			slices.append(Image.create_from_data(width, height, false, Image.FORMAT_R8, _sun.slice(z * slice_bytes, (z + 1) * slice_bytes)))
		_sun_texture = ImageTexture3D.new()
		_sun_texture.create(Image.FORMAT_R8, width, height, band, false, slices)
	return _sun_texture


## The texels round a game-space point in a volume, for a trilinear read of
## one band: [their indices in it, their weights].
func _cells_around(index: int, position: Vector3) -> Array:
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
	var base := Vector3i(floori(at.x), floori(at.y), floori(at.z))
	var fraction := at - Vector3(base)
	var offsets := PackedInt64Array()
	var weights := PackedFloat64Array()
	for corner in 8:
		var offset := Vector3i(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
		var weight := (fraction.x if offset.x == 1 else 1.0 - fraction.x) \
			* (fraction.y if offset.y == 1 else 1.0 - fraction.y) \
			* (fraction.z if offset.z == 1 else 1.0 - fraction.z)
		if weight <= 0.0:
			continue
		var x := clampi(base.x + offset.x, 0, width - 1)
		var y := clampi(base.y + offset.y, 0, height - 1)
		var z := clampi(base.z + offset.z, 0, band - 1)
		offsets.append((z * height + y) * width + x)
		weights.append(weight)
	return [offsets, weights]


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
		# RGB half floats, which is the layout cube_at reads.
		image.convert(Image.FORMAT_RGBH)
		_texels.append_array(image.get_data())
	return true


## Packs the decompiled shadow slices into memory: the sun's channel of
## each cell, turned into how much of the sun gets through. One slice a
## band, the size of the atlas's; returns false without them, or when they
## do not match it.
func _pack_sun_slices(directory: String) -> bool:
	var slices := PackedStringArray()
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	for file in dir.get_files():
		if file.begins_with(SHADOW_STEM) and file.get_extension().to_lower() in ["png", "exr"]:
			slices.append(file)
	if slices.size() != band:
		if not slices.is_empty():
			push_warning("%d probe shadow slices for %d probe slices a face: the shadows are left out." % [slices.size(), band])
		return false
	slices.sort()
	var sun := PackedByteArray()
	for file in slices:
		var image := Image.load_from_file(directory.path_join(file))
		if image == null or image.get_width() != width or image.get_height() != height:
			return false
		sun.append_array(visibility_of(image, sun_channel))
	_sun = sun
	return true


## One channel of a shadow slice, 1 where the light is blocked, as bytes of
## how much of it gets through (255 for all). The red channel is taken
## by a conversion; any other, a byte at a time.
static func visibility_of(image: Image, channel: int) -> PackedByteArray:
	var copy := image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	var out: PackedByteArray
	if channel == 0:
		copy.convert(Image.FORMAT_R8)
		out = copy.get_data()
	else:
		copy.convert(Image.FORMAT_RGBA8)
		var data := copy.get_data()
		out = PackedByteArray()
		@warning_ignore("integer_division")
		out.resize(data.size() / 4)
		for i in out.size():
			out[i] = data[i * 4 + channel]
	for i in out.size():
		out[i] = 255 - out[i]
	return out


func _write_packed_sun(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("LPS1")
	file.store_32(width)
	file.store_32(height)
	file.store_32(band)
	file.store_32(sun_channel)
	file.store_buffer(_sun)


## The pack from an earlier load, if it is of this atlas and the sun's
## channel is still the same.
func _read_packed_sun(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != "LPS1":
		return false
	if file.get_32() != width or file.get_32() != height or file.get_32() != band or file.get_32() != sun_channel:
		return false
	var sun := file.get_buffer(width * height * band)
	if sun.size() != width * height * band:
		return false
	_sun = sun
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
