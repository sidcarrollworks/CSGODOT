class_name ItemPhysics
extends RefCounted

## Each item's body on the ground, from the game's own files:
## reference/weapons/physics.csv, written by scripts/weapon_tables.gd from
## the physics hull CS2 ships beside each world model (the *_physics.gltf
## that scripts/extract_assets.sh weapons writes) and the model's PHYS block
## (scripts/extract_assets.sh weapon-physics). One convex hull per item,
## bound to one bone (weapon_offset on the guns), with its mass, its damping
## and the surface it is made of; the centre of mass, the volume and the
## inertia are the hull's own, reckoned from its triangles, and cross-checked
## there against the game's. Everything is in the world model's own axes
## (+Z the muzzle, +Y the top, +X the gun's left), in inches, from the
## model's origin: the same space DroppedItemView draws the model in.
##
## DroppedItem simulates the item as this body, turning about its centre of
## mass (issue 2 of reference/playtest-2026-09-25.md). An item without a
## row, which is every item until the table is generated on a machine with
## CS2, is a box the size of DroppedItemView's stand-in, centred on the
## origin.
##
## The table is read once, before play (GameSystems' load_all), never in a
## tick; what a class hands out is shared and never changed after.

const PATH := "res://reference/weapons/physics.csv"
## The stand-in's size where an item has no row: DroppedItemView.STAND_IN.
const STAND_IN := Vector3(4.0, 3.0, 24.0)
## The stand-in's mass: a rifle's, as CS2's PHYS blocks give them (pistols
## 3, SMGs 3.5, rifles 4 to 4.5, snipers 5, machine guns 6).
const STAND_IN_MASS := 4.0
## What an item without a surface of its own is made of: CS2's weapon
## surface (elasticity 0.95, friction 0.8, reference/surfaces/surfaces.csv).
const STAND_IN_SURFACE := "weapon"


## One item's body.
class Hull:
	extends RefCounted
	var item_class := ""
	## Whether it came from the table rather than being the stand-in.
	var from_table := false
	## The hull's corners in the model's space.
	var points := PackedVector3Array()
	## The query shape: the hull about its centre of mass, so a body's
	## transform places it directly.
	var shape: ConvexPolygonShape3D
	var centre_of_mass := Vector3.ZERO
	## The inertia for a mass of 1, about the centre of mass, in the model's
	## axes, and its inverse.
	var inertia := Basis.IDENTITY
	var inverse_inertia := Basis.IDENTITY
	var mass := STAND_IN_MASS
	var volume := 0.0
	var linear_damping := 0.0
	var angular_damping := 0.0
	var surface := STAND_IN_SURFACE
	## The bone the hull is bound to (weapon_offset), for the record.
	var bone := ""
	## Where the model's root bone rests, in the model's space: the bone a
	## hand holds a gun by (PlayerModel.attach_weapon pins it on the hand's
	## wpn bone), which HeldPose gives. The model's origin is this much
	## back from the hand.
	var held_bone := Transform3D.IDENTITY

	## Where the body is, centre of mass and turn, for a model placed at
	## model_transform.
	func body_of(model_transform: Transform3D) -> Transform3D:
		return Transform3D(model_transform.basis, model_transform * centre_of_mass)

	## Where the model is for a body at body.
	func model_of(body: Transform3D) -> Transform3D:
		return body * Transform3D(Basis.IDENTITY, -centre_of_mass)

	## The model's transform when its root bone is held at held.
	func model_held_at(held: Transform3D) -> Transform3D:
		return held * held_bone.affine_inverse()


static var _rows := {}
static var _hulls := {}
static var _path := PATH
static var _loaded := false


## Reads the table and builds every row's shape: once, before play.
static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = read_table(_path)
	for item_class: String in _rows:
		_hulls[item_class] = _hull_from_row(item_class, _rows[item_class])


## Reads another table in place of reference/weapons/physics.csv (the
## checks' fixture), or the real one again with PATH.
static func use_table(path: String) -> void:
	_path = path
	_loaded = false
	_rows = {}
	_hulls = {}
	load_all()


## Whether the table has a row for the class.
static func has(item_class: String) -> bool:
	load_all()
	return _hulls.has(item_class)


## The classes the table has rows for.
static func classes() -> PackedStringArray:
	load_all()
	return PackedStringArray(_hulls.keys())


## The body of an item class: its row's, or the stand-in box.
static func of(item_class: String) -> Hull:
	load_all()
	var hull: Hull = _hulls.get(item_class)
	if hull == null:
		hull = stand_in(item_class)
		_hulls[item_class] = hull
	return hull


## The box an item without a row is, centred on its origin.
static func stand_in(item_class: String) -> Hull:
	var hull := Hull.new()
	hull.item_class = item_class
	var half := STAND_IN * 0.5
	for corner in 8:
		hull.points.append(Vector3(
			half.x if corner & 1 else -half.x,
			half.y if corner & 2 else -half.y,
			half.z if corner & 4 else -half.z
		))
	hull.volume = STAND_IN.x * STAND_IN.y * STAND_IN.z
	var s := STAND_IN * STAND_IN / 12.0
	hull.inertia = Basis(Vector3(s.y + s.z, 0.0, 0.0), Vector3(0.0, s.x + s.z, 0.0), Vector3(0.0, 0.0, s.x + s.y))
	_finish(hull)
	return hull


## A table's rows by class, each the columns as strings.
static func read_table(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var columns := file.get_csv_line()
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() != columns.size():
			continue
		var row := {}
		for i in columns.size():
			row[columns[i]] = cells[i]
		out[String(row["item_class"])] = row
	return out


static func _hull_from_row(item_class: String, row: Dictionary) -> Hull:
	var hull := Hull.new()
	hull.item_class = item_class
	hull.from_table = true
	hull.points = points_of(String(row.get("points", "")))
	hull.centre_of_mass = vector_of(String(row.get("centre_of_mass", "")))
	var i := numbers_of(String(row.get("inertia", "")))
	if i.size() == 6:
		# xx yy zz xy xz yz.
		hull.inertia = Basis(Vector3(i[0], i[3], i[4]), Vector3(i[3], i[1], i[5]), Vector3(i[4], i[5], i[2]))
	hull.mass = _number(row, "mass", STAND_IN_MASS)
	hull.volume = _number(row, "volume", 0.0)
	hull.linear_damping = _number(row, "linear_damping", 0.0)
	hull.angular_damping = _number(row, "angular_damping", 0.0)
	var surface := String(row.get("surface", ""))
	hull.surface = surface if not surface.is_empty() else STAND_IN_SURFACE
	hull.bone = String(row.get("bone", ""))
	var held := numbers_of(String(row.get("held_bone", "")))
	if held.size() == 7:
		hull.held_bone = Transform3D(Basis(Quaternion(held[3], held[4], held[5], held[6]).normalized()), Vector3(held[0], held[1], held[2]))
	if hull.points.size() < 4:
		push_error("%s: %s has %d hull points" % [_path, item_class, hull.points.size()])
		return stand_in(item_class)
	_finish(hull)
	return hull


static func _finish(hull: Hull) -> void:
	var about_centre := PackedVector3Array()
	for point in hull.points:
		about_centre.append(point - hull.centre_of_mass)
	hull.shape = ConvexPolygonShape3D.new()
	hull.shape.points = about_centre
	hull.inverse_inertia = hull.inertia.inverse() if absf(hull.inertia.determinant()) > 1e-9 else Basis.IDENTITY


## "x y z;x y z" as points.
static func points_of(text: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for part in text.split(";", false):
		var n := numbers_of(part)
		if n.size() == 3:
			out.append(Vector3(n[0], n[1], n[2]))
	return out


## "x y z" as a vector.
static func vector_of(text: String) -> Vector3:
	var n := numbers_of(text)
	return Vector3(n[0], n[1], n[2]) if n.size() == 3 else Vector3.ZERO


static func numbers_of(text: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in text.strip_edges().split(" ", false):
		if part.is_valid_float():
			out.append(part.to_float())
	return out


static func _number(row: Dictionary, column: String, fallback: float) -> float:
	var text := String(row.get(column, ""))
	return text.to_float() if text.is_valid_float() else fallback
