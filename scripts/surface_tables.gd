extends SceneTree

## Writes reference/surfaces/surfaces.csv and surfaces.md from CS2's own
## surface files, as scripts/extract_assets.sh surfaces extracts them:
## surfaceproperties/surfaceproperties.vsurf, which lists every surface with
## its parent and its physics, and scripts/surfaceproperties_game.txt, which
## gives the game's values (the material letter, the jump and speed factors,
## and the two a round going through it uses).
##
##   godot --headless --path . --script scripts/surface_tables.gd
##
## (scripts/extract_assets.sh surfaces runs this for you.) Both files give a
## surface only what differs from its parent, so surfaces.csv keeps them as
## they are, blank where a surface inherits, and SurfaceProperties resolves
## them; surfaces.md shows them resolved. The vsurf names a parent by the hash
## of its name (m_baseNameHash against m_nameHash), and most entries by name
## too (base); the two are checked against each other. CS2_VERSION, if set, is
## recorded as the build the files came from.

const VSURF := "res://assets/surfaces/surfaceproperties/surfaceproperties.vsurf"
const GAME := "res://assets/surfaces/scripts/surfaceproperties_game.txt"
const OUT_DIR := "res://reference/surfaces"

## The columns of surfaces.csv after name, parent and hash (the vsurf's
## m_nameHash, which is how the game's own data names a surface): the physics
## the vsurf gives, then the game file's values, under the names
## SurfaceProperties uses.
const PHYSICS := {"friction": "friction", "elasticity": "elasticity", "density": "density"}
const GAME_VALUES := {
	"gamematerial": "gamematerial", "jumpfactor": "jumpfactor", "maxspeedfactor": "maxspeedfactor",
	"climbable": "climbable", "bulletPenetrationDistanceModifier": "penetration_distance",
	"bulletPenetrationDamageModifier": "penetration_damage", "allowsmokethrough": "smoke_through",
}


func _initialize() -> void:
	if not FileAccess.file_exists(VSURF) or not FileAccess.file_exists(GAME):
		print("surface tables: %s or %s is missing (scripts/extract_assets.sh surfaces)" % [VSURF, GAME])
		quit(1)
		return
	var surfaces := _entries(FileAccess.get_file_as_string(VSURF))
	var game := {}
	for entry in _entries(FileAccess.get_file_as_string(GAME)):
		game[entry["name"]] = entry["fields"]

	var by_hash := {}
	for surface in surfaces:
		by_hash[surface["fields"].get("m_nameHash", "")] = surface["name"]
	var disagree := PackedStringArray()
	var unknown := PackedStringArray()
	var columns := ["name", "parent", "hash"] + PHYSICS.values() + GAME_VALUES.values()
	var lines := PackedStringArray([",".join(columns)])
	var rows := {}
	for surface in surfaces:
		var fields: Dictionary = surface["fields"]
		var base_hash: String = fields.get("m_baseNameHash", "0")
		var parent: String = by_hash.get(base_hash, "") if base_hash != "0" else ""
		if base_hash != "0" and parent.is_empty():
			unknown.append(surface["name"])
		if fields.has("base") and fields["base"] != parent:
			disagree.append("%s (base %s, hash %s)" % [surface["name"], fields["base"], parent])
		var row := {"name": surface["name"], "parent": parent, "hash": fields.get("m_nameHash", "")}
		var physics: Dictionary = surface["blocks"].get("physics", {})
		for key: String in PHYSICS:
			row[PHYSICS[key]] = physics.get(key, "")
		var values: Dictionary = game.get(surface["name"], {})
		for key: String in GAME_VALUES:
			row[GAME_VALUES[key]] = values.get(key, "")
		rows[surface["name"]] = row
		var cells := PackedStringArray()
		for column: String in columns:
			cells.append(String(row[column]))
		lines.append(",".join(cells))
	var not_in_vsurf := PackedStringArray()
	for name: String in game:
		if not rows.has(name):
			not_in_vsurf.append(name)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_write(OUT_DIR.path_join("surfaces.csv"), "\n".join(lines) + "\n")
	_write(OUT_DIR.path_join("surfaces.csv.import"), "[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % OUT_DIR.path_join("surfaces.csv"))
	_write(OUT_DIR.path_join("surfaces.md"), _table(surfaces, rows))
	print("surface tables: %d surfaces, %d in the game file; parents by name and hash disagree for %d, unknown for %d; game entries not in the vsurf: %d"
		% [rows.size(), game.size(), disagree.size(), unknown.size(), not_in_vsurf.size()])
	for problem in disagree + unknown + not_in_vsurf:
		print("  ", problem)
	quit(0 if disagree.is_empty() and unknown.is_empty() and not_in_vsurf.is_empty() else 1)


## The entries of a KV3 text file of the form these two share: a list of
## blocks, each a surfacePropertyName and its keys, some of which are blocks
## of their own (physics, audioparams). Each as {"name", "fields", "blocks"}.
func _entries(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry := {}
	var block := ""
	var pending := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		var depth := line.length() - line.lstrip("\t").length()
		var body := line.strip_edges()
		if depth == 2 and body == "{":
			entry = {"name": "", "fields": {}, "blocks": {}}
		elif depth == 2 and body.begins_with("}"):
			if not String(entry.get("name", "")).is_empty():
				out.append(entry)
			entry = {}
		elif entry.is_empty():
			continue
		elif depth == 3 and body.ends_with("=") and not body.contains("\""):
			pending = body.trim_suffix("=").strip_edges()
		elif depth == 3 and body == "{":
			block = pending
			entry["blocks"][block] = {}
		elif depth == 3 and body == "}":
			block = ""
		elif body.contains(" = "):
			var key := body.get_slice(" = ", 0)
			var value := body.substr(body.find(" = ") + 3).strip_edges().trim_prefix("\"").trim_suffix("\"")
			if depth == 3:
				if key == "surfacePropertyName":
					entry["name"] = value
				else:
					entry["fields"][key] = value
			elif depth == 4 and not block.is_empty():
				entry["blocks"][block][key] = value
	return out


## surfaces.md: every surface with what it resolves to.
func _table(surfaces: Array[Dictionary], rows: Dictionary) -> String:
	var version := OS.get_environment("CS2_VERSION")
	var md := PackedStringArray([
		"# CS2's surfaces",
		"",
		"Written by `scripts/surface_tables.gd` from CS2%s's `surfaceproperties/surfaceproperties.vsurf` and"
			% (" " + version if not version.is_empty() else ""),
		"`scripts/surfaceproperties_game.txt` (`scripts/extract_assets.sh surfaces`); `surfaces.csv` has",
		"the same values as the files give them, blank where a surface takes its parent's. Here they are resolved:",
		"each surface's own, else its parent's, and so on up to `default`. Player friction is the physics",
		"friction times 1.25, at most 1, as Source's `CGameMovement::CategorizeGroundSurface` makes it",
		"(`gamemovement.cpp`, Source SDK 2013): it scales ground friction and acceleration.",
		"",
		"| Surface | Parents | Material | Friction | Player friction | Jump | Speed | Penetration reach | Penetration damage | Smoke through |",
		"|---|---|---|---|---|---|---|---|---|---|",
	])
	for surface in surfaces:
		var name: String = surface["name"]
		var chain := PackedStringArray()
		var at: String = rows[name]["parent"]
		while not at.is_empty() and chain.size() < 12:
			chain.append(at)
			at = rows.get(at, {}).get("parent", "")
		var friction := _resolved(rows, name, "friction")
		md.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [
			name, " > ".join(chain) if not chain.is_empty() else "-",
			_resolved(rows, name, "gamematerial"), friction,
			("%.3f" % minf(float(friction) * 1.25, 1.0)).rstrip("0").rstrip(".") if not friction.is_empty() else "",
			_resolved(rows, name, "jumpfactor"), _resolved(rows, name, "maxspeedfactor"),
			_resolved(rows, name, "penetration_distance"), _resolved(rows, name, "penetration_damage"),
			_resolved(rows, name, "smoke_through"),
		])
	return "\n".join(md) + "\n"


func _resolved(rows: Dictionary, surface: String, column: String) -> String:
	var at := surface
	for i in 16:
		var row: Dictionary = rows.get(at, {})
		if not String(row.get(column, "")).is_empty():
			return row[column]
		at = row.get("parent", "")
		if at.is_empty():
			break
	var fallback: Dictionary = rows.get("default", {})
	return fallback.get(column, "")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
