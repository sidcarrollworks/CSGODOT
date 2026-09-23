class_name HitboxSet
extends RefCounted

## A model's hitboxes as CS2 defines them, read from the decompiled model
## description that scripts/extract_assets.sh characters leaves beside the
## model's glTF.
##
## The set is a list of capsules, each on a bone: a radius and two points in
## that bone's own space, in units, and a hit group that says what part of
## the body it is. The game's groups are Source's: 1 head, 2 chest, 3
## stomach, 4 and 5 the arms, 6 and 7 the legs, 8 the neck, which takes a
## head's damage. Nineteen capsules on a player model, from the head to the
## ankles.

## Hit group to the zone the weapon data prices, and which side of the body.
const ZONES := {
	1: [&"head", &""],
	2: [&"chest", &""],
	3: [&"stomach", &""],
	4: [&"arm", &"left"],
	5: [&"arm", &"right"],
	6: [&"leg", &"left"],
	7: [&"leg", &"right"],
	8: [&"head", &""],
}

## Each model description's capsules, read once (load_for()), for every body
## and side swap after; load_for hands out copies.
static var _loaded := {}


## The capsules in a model description's text, each as {"name", "bone",
## "radius", "point0", "point1", "group", "zone", "side"}: empty when it
## has none.
static func parse(text: String) -> Array[Dictionary]:
	var capsules: Array[Dictionary] = []
	var field := RegEx.create_from_string("(\\w+)\\s*=\\s*(\"[^\"]*\"|\\[[^\\]]*\\]|[-\\w.]+)")
	var blocks := text.split("_class = \"HitboxCapsule\"")
	for index in range(1, blocks.size()):
		var block: String = blocks[index]
		var end := block.find("_class")
		if end >= 0:
			block = block.substr(0, end)
		var values := {}
		for found in field.search_all(block):
			values[found.get_string(1)] = found.get_string(2)
		if not (values.has("parent_bone") and values.has("point0") and values.has("point1") and values.has("radius")):
			continue
		var group := int(values.get("group_id", "0"))
		var zone: Array = ZONES.get(group, [&"chest", &""])
		capsules.append({
			"name": _unquote(values.get("name", values["parent_bone"])),
			"bone": _unquote(values["parent_bone"]),
			"radius": float(values["radius"]),
			"point0": _vector(values["point0"]),
			"point1": _vector(values["point1"]),
			"group": group,
			"zone": zone[0],
			"side": zone[1],
		})
	return capsules


## The capsules of the model description beside a model's glTF, or none.
static func load_for(model_path: String) -> Array[Dictionary]:
	var path := model_path.get_basename() + ".vmdl"
	if not _loaded.has(path):
		if not FileAccess.file_exists(path):
			return []
		_loaded[path] = parse(FileAccess.get_file_as_string(path))
	return (_loaded[path] as Array[Dictionary]).duplicate(true)


static func _unquote(value: String) -> String:
	return value.trim_prefix("\"").trim_suffix("\"")


static func _vector(value: String) -> Vector3:
	var parts := value.trim_prefix("[").trim_suffix("]").split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
