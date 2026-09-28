class_name RagdollShapes
extends RefCounted

## A model's ragdoll as CS2 shapes it, read from the decompiled model
## description that scripts/extract_assets.sh characters leaves beside the
## model's glTF (HitboxSet reads the hitboxes from the same file).
##
## Source 2 Viewer writes the model's physics as a PhysicsShapeList: a
## capsule (radius, point0, point1) or a sphere (radius, center) on each
## bone that has a body, in units in that bone's own space. CS2's agents
## have fifteen: the pelvis, spine_2 (the chest), head_0, and each side's
## upper arm, forearm, hand, thigh, shin and ankle, on playerflesh. The neck,
## the other spine bones and the clavicles have none; they ride the body of
## the bone above them. A sphere of no radius keeps a body with no shape,
## which a ragdoll has no use for, so it is left out.

## Each model description's shapes, read once, for every death after;
## load_for hands out copies.
static var _loaded := {}


## The shapes in a model description's text, each as {"bone", "radius",
## "point0", "point1", "surface", "physics"}: a sphere is a capsule whose
## two points are its centre, and "physics" is true, which tells Ragdoll
## these are a ragdoll's own bodies and not hitboxes to fold together.
## Empty when it has none.
static func parse(text: String) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	var field := RegEx.create_from_string("(\\w+)\\s*=\\s*(\"[^\"]*\"|\\[[^\\]]*\\]|[-\\w.]+)")
	var kind := RegEx.create_from_string("_class\\s*=\\s*\"(PhysicsShapeCapsule|PhysicsShapeSphere)\"")
	for found in kind.search_all(text):
		var block := text.substr(found.get_end())
		var end := block.find("_class")
		if end >= 0:
			block = block.substr(0, end)
		var values := {}
		for pair in field.search_all(block):
			values[pair.get_string(1)] = pair.get_string(2)
		if not (values.has("parent_bone") and values.has("radius")) or float(values["radius"]) <= 0.0:
			continue
		var point0: Vector3
		var point1: Vector3
		if found.get_string(1) == "PhysicsShapeSphere":
			if not values.has("center"):
				continue
			point0 = HitboxSet._vector(values["center"])
			point1 = point0
		else:
			if not (values.has("point0") and values.has("point1")):
				continue
			point0 = HitboxSet._vector(values["point0"])
			point1 = HitboxSet._vector(values["point1"])
		shapes.append({
			"bone": HitboxSet._unquote(values["parent_bone"]),
			"radius": float(values["radius"]),
			"point0": point0,
			"point1": point1,
			"surface": HitboxSet._unquote(values.get("surface_prop", "")),
			"physics": true,
		})
	return shapes


## The ragdoll shapes of the model description beside a model's glTF, or
## none (not extracted, or an older extraction without them).
static func load_for(model_path: String) -> Array[Dictionary]:
	var path := model_path.get_basename() + ".vmdl"
	if not _loaded.has(path):
		if not FileAccess.file_exists(path):
			return []
		_loaded[path] = parse(FileAccess.get_file_as_string(path))
	return (_loaded[path] as Array[Dictionary]).duplicate(true)
