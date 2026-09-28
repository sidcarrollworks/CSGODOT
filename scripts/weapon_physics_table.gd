extends RefCounted

## reference/weapons/physics.csv and physics.md: each item's body on the
## ground (ItemPhysics), from what scripts/extract_assets.sh extracted. For
## scripts/weapon_tables.gd, which writes them with the other weapon tables.
##
## Two sources, both the game's own:
##
## - The physics hull beside each world model, *_physics.gltf (the weapons
##   and equipment steps write it): its triangles give the hull's corners,
##   its volume, its centre of mass and its inertia, reckoned here.
## - The model's PHYS block, dumped as text by the weapon-physics step
##   (Source2Viewer-CLI -b PHYS over weapons/models/): the bone the hull is
##   bound to and that bone's bind pose, the mass, the damping, the surface,
##   and the game's own volume and centroid, which the hull's are checked
##   against. Only the start of each block is read: from m_pFeModel on it is
##   cloth data, tens of megabytes of it.
##
## Everything is written in the world model's own axes as DroppedItemView
## draws it (+Z the muzzle, +Y the top, +X the gun's left), in inches from
## the model's origin. The glTF is in metres with glTF x = Source y, y =
## Source z and z = Source x; the PHYS block is in Source's axes and inches.
## Whether the glTF's hull already sits where the bone's bind pose puts it
## is settled per model, by which of the two puts the average of the
## hull's corners on the game's centroid, which is that average (the
## hull_frame column says which); by the drawn model's bounds only where
## the game gives no centroid.

## The PHYS dump the weapon-physics step writes.
const DUMP := "res://assets/weapons/weapons/models/physics_data.txt"
const COLUMNS := [
	"item_class", "model", "bone", "surface", "mass", "linear_damping", "angular_damping",
	"volume", "centre_of_mass", "inertia", "held_bone", "points",
	"game_volume", "game_centre_of_mass", "hull_frame",
]
## The glTF's metres to inches: MapImporter.SOURCE2_VIEWER_SCALE.
const SCALE := 1.0 / 0.0254


## Reads a Source2Viewer-CLI dump of PHYS blocks ("-b PHYS" over many
## .vmdl_c files): per model path (weapons/models/ak47/weapon_rif_ak47.vmdl_c),
## {bone, bind (Transform3D, the bone's bind pose in the model's axes and
## inches), mass, linear_damping, angular_damping, surface_hash (-1 if
## none), game_volume, game_centroid (the model's axes, in the bone's
## space)}. A model whose block lacks a field gets NAN, or an empty bone,
## and physics.md says so.
static func read_dump(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var header := RegEx.create_from_string("^\\[\\d+/\\d+\\] (\\S+\\.vmdl_c)$")
	var current := ""
	var lines := PackedStringArray()
	var skipping := false
	# Each model's section starts with the resource's own details, its
	# references and its list of blocks; the block itself follows its
	# '--- Data for block "PHYS" ---' line, and ends at the next '--- ' line.
	var in_block := false
	while not file.eof_reached():
		var line := file.get_line()
		var stripped := line.strip_edges()
		var found := header.search(stripped)
		if found != null:
			if not current.is_empty():
				out[current] = read_block("\n".join(lines))
			current = found.get_string(1)
			lines = PackedStringArray()
			skipping = false
			in_block = false
			continue
		if current.is_empty() or skipping:
			continue
		if stripped.begins_with("--- Data for block \"PHYS\""):
			lines = PackedStringArray()
			in_block = true
			continue
		if in_block and stripped.begins_with("--- "):
			skipping = true
			continue
		if stripped.begins_with("m_pFeModel"):
			skipping = true
			continue
		lines.append(line)
	if not current.is_empty():
		out[current] = read_block("\n".join(lines))
	return out


## One PHYS block's text, read as read_dump says.
static func read_block(text: String) -> Dictionary:
	var data = parse_kv3(text)
	var row := {
		"bone": "", "bind": Transform3D.IDENTITY, "mass": NAN, "linear_damping": NAN,
		"angular_damping": NAN, "surface_hash": -1, "game_volume": NAN, "game_centroid": Vector3(NAN, NAN, NAN),
	}
	if not data is Dictionary:
		return row
	var parts: Array = data.get("m_parts", []) if data.get("m_parts") is Array else []
	# The part with the biggest hull is the item's; guns have one.
	var best := -1
	var best_volume := -1.0
	for i in parts.size():
		var hull := _hull_of(parts[i])
		var volume := float(hull.get("m_flVolume", 0.0)) if not hull.is_empty() else 0.0
		if volume > best_volume:
			best_volume = volume
			best = i
	if best < 0:
		return row
	var part: Dictionary = parts[best]
	row["mass"] = _float(part.get("m_flMass"))
	row["linear_damping"] = _float(part.get("m_flLinearDamping"))
	row["angular_damping"] = _float(part.get("m_flAngularDamping"))
	var hull := _hull_of(part)
	row["game_volume"] = _float(hull.get("m_flVolume"))
	var centroid := _floats(hull.get("m_vCentroid"))
	if centroid.size() == 3:
		row["game_centroid"] = from_source(Vector3(centroid[0], centroid[1], centroid[2]))
	var names: Array = data.get("m_boneNames", []) if data.get("m_boneNames") is Array else []
	if best < names.size():
		row["bone"] = String(names[best])
	elif names.size() == 1:
		row["bone"] = String(names[0])
	var poses: Array = data.get("m_bindPose", []) if data.get("m_bindPose") is Array else []
	var pose_index := best if best < poses.size() else 0
	if pose_index < poses.size():
		var m := _floats(poses[pose_index])
		if m.size() == 12:
			row["bind"] = bind_from_source(m)
	var shape_hulls := _shape_hulls(part)
	var hashes: Array = data.get("m_surfacePropertyHashes", []) if data.get("m_surfacePropertyHashes") is Array else []
	if not shape_hulls.is_empty():
		var index := int(_float((shape_hulls[0] as Dictionary).get("m_nSurfacePropertyIndex"), 0.0))
		if index >= 0 and index < hashes.size():
			row["surface_hash"] = int(_float(hashes[index], -1.0))
	return row


## A Source point (x forward, y left, z up, inches) in the model's axes.
static func from_source(v: Vector3) -> Vector3:
	return Vector3(v.y, v.z, v.x)


## A matrix3x4 (rows: x, y, z, each three of the turn then the offset, as
## Source keeps them) as a transform in the model's axes.
static func bind_from_source(m: PackedFloat64Array) -> Transform3D:
	var columns: Array[Vector3] = []
	for axis in 3:
		# The model's axis in Source's axes, turned, and back.
		var e := Vector3.ZERO
		e[axis] = 1.0
		var source := Vector3(e.z, e.x, e.y)
		var turned := Vector3(
			m[0] * source.x + m[1] * source.y + m[2] * source.z,
			m[4] * source.x + m[5] * source.y + m[6] * source.z,
			m[8] * source.x + m[9] * source.y + m[10] * source.z
		)
		columns.append(from_source(turned))
	return Transform3D(Basis(columns[0], columns[1], columns[2]), from_source(Vector3(m[3], m[7], m[11])))


static func _shape_hulls(part: Variant) -> Array:
	if not part is Dictionary:
		return []
	var shape = (part as Dictionary).get("m_rnShape")
	if not shape is Dictionary:
		return []
	var hulls = (shape as Dictionary).get("m_hulls")
	return hulls if hulls is Array else []


static func _hull_of(part: Variant) -> Dictionary:
	var hulls := _shape_hulls(part)
	if hulls.is_empty() or not hulls[0] is Dictionary:
		return {}
	var hull = (hulls[0] as Dictionary).get("m_Hull")
	return hull if hull is Dictionary else {}


static func _float(value: Variant, fallback: float = NAN) -> float:
	if value is float or value is int:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return fallback


## Every number in a value, nested arrays flattened.
static func _floats(value: Variant) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if value is Array:
		for item in value:
			out.append_array(_floats(item))
	elif value is float or value is int:
		out.append(float(value))
	return out


## KV3 text as Source2Viewer-CLI writes it: { key = value ... } objects,
## [ a, b ] arrays, numbers, true and false, quoted strings (a resource:
## or other prefix dropped) and #[ .. ] binary, kept as text. Anything left
## open at the end (a block cut short) is closed there.
static func parse_kv3(text: String) -> Variant:
	var tokens := _tokens(text)
	var at := [0]
	return _value(tokens, at)


static func _tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r" or c == ",":
			i += 1
		elif c == "<" and text.substr(i, 4) == "<!--":
			var end := text.find("-->", i)
			i = n if end < 0 else end + 3
		elif c == "/" and text.substr(i, 2) == "//":
			var end := text.find("\n", i)
			i = n if end < 0 else end
		elif c == "{" or c == "}" or c == "[" or c == "]" or c == "=":
			out.append(c)
			i += 1
		elif c == "#" and text.substr(i, 2) == "#[":
			var end := text.find("]", i)
			out.append("\"" + text.substr(i, (n if end < 0 else end + 1) - i))
			i = n if end < 0 else end + 1
		elif c == "\"":
			var end := text.find("\"", i + 1)
			out.append("\"" + text.substr(i + 1, (n if end < 0 else end) - i - 1))
			i = n if end < 0 else end + 1
		else:
			var start := i
			while i < n and not text[i] in [" ", "\t", "\n", "\r", ",", "{", "}", "[", "]", "=", "\""]:
				i += 1
			var word := text.substr(start, i - start)
			if i < n and text[i] == "\"" and word.ends_with(":"):
				# resource:"path": the prefix is dropped.
				continue
			out.append(word)
	return out


static func _value(tokens: PackedStringArray, at: Array) -> Variant:
	if at[0] >= tokens.size():
		return null
	var token := tokens[at[0]]
	at[0] += 1
	if token == "{":
		var object := {}
		while at[0] < tokens.size() and tokens[at[0]] != "}":
			var key := tokens[at[0]]
			at[0] += 1
			if at[0] < tokens.size() and tokens[at[0]] == "=":
				at[0] += 1
			object[key.trim_prefix("\"")] = _value(tokens, at)
		at[0] += 1
		return object
	if token == "[":
		var array := []
		while at[0] < tokens.size() and tokens[at[0]] != "]":
			array.append(_value(tokens, at))
		at[0] += 1
		return array
	if token.begins_with("\""):
		return token.substr(1)
	if token == "true":
		return true
	if token == "false":
		return false
	if token.is_valid_int():
		return token.to_int()
	if token.is_valid_float():
		return token.to_float()
	return token


## The triangles of every mesh in a glTF scene, in the scene's own space
## scaled to inches: the model's axes.
static func triangles_of(scene: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mesh_node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh_node.mesh == null:
			continue
		var to_scene := Transform3D.IDENTITY
		var node: Node = mesh_node
		while node != scene and node is Node3D:
			to_scene = (node as Node3D).transform * to_scene
			node = node.get_parent()
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var order := PackedInt32Array(indices) if indices != null and (indices as PackedInt32Array).size() > 0 else PackedInt32Array(range(vertices.size()))
			for i in range(0, order.size() - 2, 3):
				for k in 3:
					out.append((to_scene * vertices[order[i + k]]) * SCALE)
	return out


## A closed mesh's volume, centroid and inertia for a mass of 1 about the
## centroid (xx yy zz xy xz yz), from its triangles, whichever way they
## wind: each triangle and the origin make a tetrahedron, signed.
static func mass_properties(triangles: PackedVector3Array) -> Dictionary:
	var volume := 0.0
	var first := Vector3.ZERO
	# The second moments about the origin: xx yy zz xy xz yz.
	var second := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in range(0, triangles.size() - 2, 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var det := a.dot(b.cross(c))
		volume += det / 6.0
		first += det / 24.0 * (a + b + c)
		var s := a + b + c
		var k := det / 120.0
		second[0] += k * (a.x * a.x + b.x * b.x + c.x * c.x + s.x * s.x)
		second[1] += k * (a.y * a.y + b.y * b.y + c.y * c.y + s.y * s.y)
		second[2] += k * (a.z * a.z + b.z * b.z + c.z * c.z + s.z * s.z)
		second[3] += k * (a.x * a.y + b.x * b.y + c.x * c.y + s.x * s.y)
		second[4] += k * (a.x * a.z + b.x * b.z + c.x * c.z + s.x * s.z)
		second[5] += k * (a.y * a.z + b.y * b.z + c.y * c.z + s.y * s.z)
	if absf(volume) < 1e-9:
		return {"volume": 0.0, "centroid": Vector3.ZERO, "inertia": PackedFloat64Array([0, 0, 0, 0, 0, 0])}
	var centroid := first / volume
	# Per unit volume, about the centroid.
	var xx := second[0] / volume - centroid.x * centroid.x
	var yy := second[1] / volume - centroid.y * centroid.y
	var zz := second[2] / volume - centroid.z * centroid.z
	var xy := second[3] / volume - centroid.x * centroid.y
	var xz := second[4] / volume - centroid.x * centroid.z
	var yz := second[5] / volume - centroid.y * centroid.z
	return {
		"volume": absf(volume), "centroid": centroid,
		"inertia": PackedFloat64Array([yy + zz, xx + zz, xx + yy, -xy, -xz, -yz]),
	}


## Each distinct point of a set, to a thousandth of an inch.
static func unique_points(points: PackedVector3Array) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for point in points:
		var key := point.snapped(Vector3.ONE * 0.001)
		if not seen.has(key):
			seen[key] = true
			out.append(key)
	return out


## The average of a hull's distinct corners: what the game's m_vCentroid
## is (not the centre of mass, which is the volume's).
static func corner_average(points: PackedVector3Array) -> Vector3:
	var corners := unique_points(points)
	var sum := Vector3.ZERO
	for point in corners:
		sum += point
	return sum / corners.size() if not corners.is_empty() else Vector3.ZERO


## The box round a set of points.
static func bounds_of(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box


## How far two boxes' corners are apart, all told.
static func misfit(a: AABB, b: AABB) -> float:
	return (a.position - b.position).length() + (a.end - b.end).length()


## One item's row: its class, model path, the dump's row for the model
## (read_block), the hull's triangles as exported, the drawn model's
## bounds (an empty box when there is none) and where its root bone rests
## (held_bone). Empty where the hull has no volume.
static func row(item_class: String, model: String, phys: Dictionary, triangles: PackedVector3Array, drawn: AABB, held_bone: Transform3D) -> Dictionary:
	var bind: Transform3D = phys.get("bind", Transform3D.IDENTITY)
	var centroid: Vector3 = phys.get("game_centroid", Vector3(NAN, NAN, NAN))
	if not is_nan(centroid.x):
		# The game's centroid is in the bone's space.
		centroid = bind * centroid
	var frame := "model"
	var placed := triangles
	if not bind.is_equal_approx(Transform3D.IDENTITY):
		var bound := bind * triangles
		# The game's centroid is the average of the hull's corners (it
		# matches ours to a thousandth of an inch on every hull placed
		# right), so it says where the hull sits; the drawn model's bounds,
		# which the thin parts a convex hull leaves out and a posed model's
		# parts throw off, only where the game gives none.
		if not is_nan(centroid.x):
			if corner_average(bound).distance_to(centroid) < corner_average(triangles).distance_to(centroid):
				placed = bound
				frame = "bone"
		elif drawn.size != Vector3.ZERO and misfit(bounds_of(bound), drawn) < misfit(bounds_of(triangles), drawn):
			placed = bound
			frame = "bone"
	var mass := mass_properties(placed)
	if float(mass["volume"]) <= 0.0:
		return {}
	var surface := SurfaceProperties.by_hash(int(phys.get("surface_hash", -1)))
	var q := held_bone.basis.get_rotation_quaternion()
	return {
		"item_class": item_class,
		"model": model,
		"bone": String(phys.get("bone", "")),
		"surface": SurfaceProperties.spelling(surface) if not surface.is_empty() else "",
		"mass": _cell(float(phys.get("mass", NAN))),
		"linear_damping": _cell(float(phys.get("linear_damping", NAN))),
		"angular_damping": _cell(float(phys.get("angular_damping", NAN))),
		"volume": _cell(float(mass["volume"])),
		"centre_of_mass": _vector(mass["centroid"]),
		"inertia": " ".join(Array(mass["inertia"]).map(func(v: float) -> String: return _cell(v))),
		"held_bone": "%s %s %s %s %s" % [_vector(held_bone.origin), _cell(q.x), _cell(q.y), _cell(q.z), _cell(q.w)],
		"points": ";".join(Array(unique_points(placed)).map(func(p: Vector3) -> String: return _vector(p))),
		"game_volume": _cell(float(phys.get("game_volume", NAN))),
		"game_centre_of_mass": _vector(centroid) if not is_nan(centroid.x) else "",
		"hull_frame": frame,
	}


## The rows as CSV, COLUMNS in order.
static func csv(rows: Array) -> String:
	var lines := PackedStringArray([",".join(COLUMNS)])
	for r: Dictionary in rows:
		lines.append(",".join(COLUMNS.map(func(c: String) -> String: return String(r.get(c, "")))))
	return "\n".join(lines) + "\n"


## The page beside the CSV: each row's numbers, and how the hull's own
## volume and centre of mass agree with the game's.
static func page(rows: Array, source: String, date: String, gaps: PackedStringArray) -> String:
	var lines := PackedStringArray([
		"# Each item's body on the ground",
		"",
		"Written by `scripts/weapon_tables.gd` (`scripts/weapon_physics_table.gd`) on %s from %s: the physics hull beside each world model (`*_physics.gltf`, from `scripts/extract_assets.sh weapons` and `equipment`) and the model's PHYS block (`scripts/extract_assets.sh weapon-physics`). Do not edit by hand. `physics.csv` beside it is what `ItemPhysics` reads; the hull's corners are there." % [date, source],
		"",
		"Positions are in the world model's axes (+Z the muzzle, +Y the top, +X the gun's left), in inches from the model's origin. The volume and centre of mass are reckoned from the hull's triangles; the game's volume is beside ours as a check, and its centroid beside our centre of mass, though the game's is the average of the hull's corners, not the centre of the volume. The inertia is for a mass of 1, about the centre of mass. The frame says whether the exported hull already sat on the model (model) or was placed by its bone's bind pose (bone), whichever puts the corners' average on the game's centroid.",
		"",
		"| Class | Bone | Surface | Mass | Angular damping | Volume (game's) | Centre of mass (game's) | Frame |",
		"|---|---|---|---|---|---|---|---|",
	])
	for r: Dictionary in rows:
		lines.append("| `%s` | %s | %s | %s | %s | %s (%s) | %s (%s) | %s |" % [
			r["item_class"], r["bone"], r["surface"], r["mass"], r["angular_damping"],
			r["volume"], r["game_volume"], r["centre_of_mass"], r["game_centre_of_mass"], r["hull_frame"],
		])
	if not gaps.is_empty():
		lines.append("")
		lines.append("## Missing")
		lines.append("")
		for gap in gaps:
			lines.append("- %s" % gap)
	return "\n".join(lines) + "\n"


static func _cell(value: float) -> String:
	if is_nan(value):
		return ""
	return String.num(0.0 if absf(value) < 5e-5 else value, 4)


static func _vector(v: Vector3) -> String:
	return "%s %s %s" % [_cell(v.x), _cell(v.y), _cell(v.z)]
