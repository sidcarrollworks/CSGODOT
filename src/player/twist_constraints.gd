class_name TwistConstraints
extends RefCounted

## The twist bones' constraints as CS2 defines them, read from the decompiled
## model description that scripts/extract_assets.sh characters leaves beside
## the model's glTF (reference/research/twist-constraints.md).
##
## CS2's clips never key the twist bones (arm_lower_*_TWIST and TWIST1, the
## upper arms', the thighs' and head_0_TWIST): the model's AnimConstraintList
## poses them from the bones they follow, each AnimConstraintTiltTwist turning
## one bone about its own axis by a share of another's twist. The skin of a
## forearm is weighted mostly to its twist bones, so without them a wrist
## turned 80 degrees wrings the cuff.
##
## Each constraint here is one twist bone: {"bone", "weight", "target",
## "offset", "input_axis", "slave_axis"}. bone is the one turned (the
## AnimConstraintSlave), target the one whose twist it takes (the
## AnimConstraintBoneInput), both named as the file writes them (hand_l for
## the skeleton's hand_L), and offset the target's relative_angles as a
## quaternion.

## Each model description's constraints, read once (load_for()), for every
## body after; load_for hands out copies.
static var _loaded := {}

## The classes of the blocks inside a constraint; any other class ends it.
const PARTS := ["AnimConstraintSlave", "AnimConstraintBoneInput", "AnimConstraintAttachmentInput"]


## The tilt-twist constraints in a model description's text, one per bone
## turned, in the file's order: empty when it has none.
static func parse(text: String) -> Array[Dictionary]:
	var constraints: Array[Dictionary] = []
	var field := RegEx.create_from_string("(\\w+)\\s*=\\s*(\"[^\"]*\"|\\[[^\\]]*\\]|[-\\w.]+)")
	var blocks := text.split("_class = \"")
	var index := 1
	while index < blocks.size():
		if not blocks[index].begins_with("AnimConstraintTiltTwist\""):
			index += 1
			continue
		# The constraint's own fields (input_axis, slave_axis) follow its
		# children, so they land at the end of its last part's block.
		var slaves: Array[Dictionary] = []
		var inputs: Array[Dictionary] = []
		var own := _fields(field, blocks[index])
		index += 1
		while index < blocks.size():
			var block: String = blocks[index]
			var kind := block.substr(0, block.find("\""))
			if not kind in PARTS:
				break
			var closed := block.find("}")
			var part := _fields(field, block.substr(0, closed) if closed >= 0 else block)
			own.merge(_fields(field, block.substr(closed)) if closed >= 0 else {}, true)
			if kind == "AnimConstraintSlave":
				slaves.append(part)
			elif kind == "AnimConstraintBoneInput":
				inputs.append(part)
			index += 1
		if inputs.is_empty():
			continue
		var input: Dictionary = inputs[0]
		for slave in slaves:
			if not slave.has("parent_bone"):
				continue
			constraints.append({
				"bone": _unquote(slave["parent_bone"]),
				"weight": float(slave.get("weight", "1.0")),
				"target": _unquote(input.get("parent_bone", "")),
				"offset": qangle_quaternion(_vector(input.get("relative_angles", "[0, 0, 0]"))),
				"input_axis": clampi(int(own.get("input_axis", "0")), 0, 2),
				"slave_axis": clampi(int(own.get("slave_axis", "0")), 0, 2),
			})
	return constraints


## The constraints of the model description beside a model's glTF, or none.
static func load_for(model_path: String) -> Array[Dictionary]:
	var path := model_path.get_basename() + ".vmdl"
	if not _loaded.has(path):
		if not FileAccess.file_exists(path):
			return []
		_loaded[path] = parse(FileAccess.get_file_as_string(path))
	return (_loaded[path] as Array[Dictionary]).duplicate(true)


## A Source angle (pitch, yaw, roll, in degrees) as a quaternion: yaw about
## Z, then pitch about Y, then roll about X, each in the frame the one
## before left (Source's AngleQuaternion; Source 2 Viewer writes a
## constraint's m_qOffset out as these angles).
static func qangle_quaternion(angles: Vector3) -> Quaternion:
	var radians := angles * (PI / 180.0)
	return (Quaternion(Vector3(0, 0, 1), radians.y)
		* Quaternion(Vector3(0, 1, 0), radians.x)
		* Quaternion(Vector3(1, 0, 0), radians.z))


## How far a rotation turns about one of its own axes (0 X, 1 Y, 2 Z), in
## radians, leaving out the tilt of that axis: Source 2 Viewer's TwistAngle
## (Renderer/BoneConstraintSolver.cs), line for line.
##
## The rotation's axis is tilted back onto the original along the shortest
## arc, and what turn is left about it is the twist. A pure bend (the axis
## tilted, nothing turned about it) measures 0.
static func twist_angle(rotation: Quaternion, axis: int) -> float:
	var basis := Basis(rotation.normalized())
	var axis1 := (axis + 1) % 3
	var axis2 := (axis + 2) % 3
	const EPSILON := 0.0001
	var diagonal := clampf(floorf(basis[axis][axis] * 1e7 + 0.5) / 1e7, -1.0, 1.0)
	var tilt := acos(diagonal + 1.0) if diagonal < 0.0 else acos(1.0 - diagonal)
	if absf(tilt - PI / 2.0) > EPSILON:
		# The axis is tilted: where it now points, across the plane at
		# right angles to where it was, against where the other two now lie
		# along the original.
		var a: float = basis[axis][axis1]
		var b: float = basis[axis][axis2]
		var inverse_length := 1.0 / maxf(sqrt(a * a + b * b), 1e-30)
		a *= inverse_length
		b *= inverse_length
		var m1: float = basis[axis1][axis]
		var m2: float = basis[axis2][axis]
		return atan2(m2 * a - m1 * b, -m1 * a - m2 * b)
	# The axis stayed put (or turned right round): the turn is read off the
	# next axis alone.
	var diagonal1: float = basis[axis1][axis1]
	if absf(diagonal1 - 1.0) <= EPSILON:
		return 0.0
	return atan2(basis[axis1][axis2], diagonal1)


static func _fields(field: RegEx, block: String) -> Dictionary:
	var values := {}
	for found in field.search_all(block):
		if not values.has(found.get_string(1)):
			values[found.get_string(1)] = found.get_string(2)
	return values


static func _unquote(value: String) -> String:
	return value.trim_prefix("\"").trim_suffix("\"")


static func _vector(value: String) -> Vector3:
	var parts := value.trim_prefix("[").trim_suffix("]").split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
