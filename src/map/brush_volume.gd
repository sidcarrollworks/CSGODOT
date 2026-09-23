class_name BrushVolume
extends RefCounted

## A brush entity that is a volume rather than something seen: a buy zone
## (func_buyzone), a bomb site (func_bomb_target), a callout's place
## (env_cs_place). The entity lump names its model, maps/<map>/entities/*.vmdl,
## and the model's physics, as Source 2 Viewer exports it
## (scripts/extract_assets.sh volumes), is the volume: the brushes it was
## built from, each a closed convex solid, in Source's axes and inches about
## the entity's origin. The world's glTF and its collision hull leave brush
## entities out. The world export's world_physics.gltf does hold them, one
## node per entity, but names them only by class, without the model or the
## keys (teamnum, bomb_site_designation) that say which is which, so each is
## read from its own model.
##
## Everything here is in game space (SourceEntities.to_game).

var classname: String
## The entity it came from, as SourceEntities.parse() gives it: the keys a
## system needs (teamnum, bomb_damage_power, place_name) are on it.
var entity: Dictionary
## The solids, each as its corners.
var pieces: Array[PackedVector3Array] = []
var bounds: AABB

## Each solid's faces as planes facing out.
var _faces: Array[Array] = []


## Whether a point is inside one of the solids, counting `margin` units past
## its faces as in.
func contains(point: Vector3, margin: float = 0.0) -> bool:
	for faces in _faces:
		var inside := true
		for face: Plane in faces:
			if face.distance_to(point) > margin:
				inside = false
				break
		if inside:
			return true
	return false


## The solids as shapes, one per brush, for an Area3D to find players in.
func shapes() -> Array[ConvexPolygonShape3D]:
	var out: Array[ConvexPolygonShape3D] = []
	for piece in pieces:
		var shape := ConvexPolygonShape3D.new()
		shape.points = piece
		out.append(shape)
	return out


## Every entity of a class whose model has been extracted, as a volume. `root`
## is the map's extraction folder, the one maps/<map>/entities/ is under.
static func of_class(entities: Array[Dictionary], entity_class: String, root: String) -> Array[BrushVolume]:
	var out: Array[BrushVolume] = []
	for candidate in entities:
		if candidate.get("classname", "") != entity_class or candidate.get("enabled", "true") == "false":
			continue
		var volume := from_entity(candidate, root)
		if volume != null:
			out.append(volume)
	return out


## The buy zones by team, {"T": [...], "CT": [...]}: func_buyzone's teamnum is
## 2 for T and 3 for CT.
static func buy_zones(entities: Array[Dictionary], root: String) -> Dictionary:
	var zones := {"T": [], "CT": []}
	for volume in of_class(entities, "func_buyzone", root):
		match int(volume.entity.get("teamnum", "0")):
			2:
				zones["T"].append(volume)
			3:
				zones["CT"].append(volume)
	return zones


## The bomb sites by letter, {"A": volume, "B": volume}: func_bomb_target's
## bomb_site_designation is 0 for A and 1 for B. Each keeps its
## bomb_damage_power on its entity.
static func bomb_sites(entities: Array[Dictionary], root: String) -> Dictionary:
	var sites := {}
	for volume in of_class(entities, "func_bomb_target", root):
		sites["AB"[clampi(int(volume.entity.get("bomb_site_designation", "0")), 0, 1)]] = volume
	return sites


## An entity's volume: its model's solids placed by its origin, angles and
## scales. Null when the entity names no model or the model is not there.
static func from_entity(source_entity: Dictionary, root: String) -> BrushVolume:
	var model := model_path(source_entity)
	if model.is_empty():
		return null
	var gltf := root.path_join(model.get_basename() + "_physics.gltf")
	if not FileAccess.file_exists(gltf):
		return null
	var volume := BrushVolume.new()
	volume.classname = source_entity.get("classname", "")
	volume.entity = source_entity
	var origin := SourceEntities.vector(source_entity.get("origin", "[ 0 0 0 ]"))
	var turn := source_basis(SourceEntities.vector(source_entity.get("angles", "[ 0 0 0 ]")))
	var scales := SourceEntities.vector(source_entity.get("scales", "[ 1 1 1 ]"))
	var first := true
	for solid in read_solids(gltf):
		var corners := PackedVector3Array()
		var triangles := PackedVector3Array()
		for local in solid:
			var point := SourceEntities.to_game(origin + turn * (local * scales))
			triangles.append(point)
			if not corners.has(point):
				corners.append(point)
		volume.pieces.append(corners)
		volume._faces.append(_faces_of(triangles, corners))
		for corner in corners:
			volume.bounds = AABB(corner, Vector3.ZERO) if first else volume.bounds.expand(corner)
			first = false
	return volume


## The model an entity names, as the path of its .vmdl: the lump writes it
## as resource_name:"maps/de_dust2/entities/unnamed_2_23316.vmdl". Names can
## have spaces in them (de_mirage's sites are "a site_2_60263.vmdl").
static func model_path(source_entity: Dictionary) -> String:
	var found := RegEx.create_from_string("[^\":]+\\.vmdl").search(String(source_entity.get("model", "")))
	return found.get_string() if found != null else ""


## Source's angles (pitch, yaw, roll, in degrees) as the rotation they make in
## Source's axes: yaw about Z, from +X towards +Y, then pitch, then roll, as
## Source's AngleMatrix builds it.
static func source_basis(angles: Vector3) -> Basis:
	var pitch := deg_to_rad(angles.x)
	var yaw := deg_to_rad(angles.y)
	var roll := deg_to_rad(angles.z)
	var sp := sin(pitch)
	var cp := cos(pitch)
	var sy := sin(yaw)
	var cy := cos(yaw)
	var sr := sin(roll)
	var cr := cos(roll)
	return Basis(
		Vector3(cp * cy, cp * sy, -sp),
		Vector3(sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, sr * cp),
		Vector3(cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp)
	)


## The solids in a physics glTF, each as its triangles' corners, three to a
## triangle, in the model's own space. The export writes them all as one
## soup of triangles, a solid's in a run, so a solid ends where every edge
## so far has been used twice.
static func read_solids(gltf_path: String) -> Array[PackedVector3Array]:
	var solids: Array[PackedVector3Array] = []
	var gltf: Variant = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	if not gltf is Dictionary or not gltf.has("meshes") or not gltf.has("buffers"):
		return solids
	var buffer := FileAccess.get_file_as_bytes(gltf_path.get_base_dir().path_join(gltf["buffers"][0]["uri"]))
	var current := PackedVector3Array()
	var edges := {}
	for mesh: Dictionary in gltf["meshes"]:
		for primitive: Dictionary in mesh["primitives"]:
			var positions := _read_vectors(gltf, buffer, int(primitive["attributes"]["POSITION"]))
			var indices := _read_indices(gltf, buffer, int(primitive.get("indices", -1)), positions.size())
			for i in range(0, indices.size() - 2, 3):
				for k in 3:
					var a := positions[indices[i + k]]
					var b := positions[indices[i + (k + 1) % 3]]
					current.append(a)
					var key := [a.snapped(Vector3.ONE * 0.01), b.snapped(Vector3.ONE * 0.01)]
					key.sort()
					edges[key] = int(edges.get(key, 0)) + 1
				var closed := true
				for count: int in edges.values():
					if count % 2 != 0:
						closed = false
						break
				if closed:
					solids.append(current)
					current = PackedVector3Array()
					edges.clear()
	return solids


## A solid's faces, one plane per triangle, turned to face away from its
## middle: the export's winding is not relied on.
static func _faces_of(triangles: PackedVector3Array, corners: PackedVector3Array) -> Array[Plane]:
	var middle := Vector3.ZERO
	for corner in corners:
		middle += corner
	middle /= maxf(corners.size(), 1)
	var faces: Array[Plane] = []
	for i in range(0, triangles.size() - 2, 3):
		var normal := (triangles[i + 1] - triangles[i]).cross(triangles[i + 2] - triangles[i])
		if normal.length_squared() < 1e-6:
			continue
		var face := Plane(normal.normalized(), triangles[i])
		faces.append(-face if face.distance_to(middle) > 0.0 else face)
	return faces


static func _read_vectors(gltf: Dictionary, buffer: PackedByteArray, accessor_index: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var accessor: Dictionary = gltf["accessors"][accessor_index]
	var view: Dictionary = gltf["bufferViews"][int(accessor["bufferView"])]
	var start := int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var stride := int(view.get("byteStride", 12))
	for i in int(accessor["count"]):
		var at := start + i * stride
		out.append(Vector3(buffer.decode_float(at), buffer.decode_float(at + 4), buffer.decode_float(at + 8)))
	return out


static func _read_indices(gltf: Dictionary, buffer: PackedByteArray, accessor_index: int, vertex_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if accessor_index < 0:
		for i in vertex_count:
			out.append(i)
		return out
	var accessor: Dictionary = gltf["accessors"][accessor_index]
	var view: Dictionary = gltf["bufferViews"][int(accessor["bufferView"])]
	var start := int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var size: int = {5121: 1, 5123: 2, 5125: 4}.get(int(accessor["componentType"]), 4)
	for i in int(accessor["count"]):
		var at := start + i * size
		match size:
			1:
				out.append(buffer[at])
			2:
				out.append(buffer.decode_u16(at))
			_:
				out.append(buffer.decode_u32(at))
	return out
