class_name WeaponLibrary
extends RefCounted

## Every gun in CS2, built by its class name (build), and the two the project
## started with, which carry what was measured of them by hand.
##
## Every number the firing model uses comes from the game's own tuning,
## scripts/weapons.vdata_c, read through WeaponVData: damage, armour, falloff,
## fire rate, magazine and reserve, speed, inaccuracy and recovery, and when a
## reload lets the gun fire again. The CS2 Weapon Spreadsheet (WeaponSheet) is
## read first and stays only for the landing and ladder figures, which the
## game stores as something else; everything else it has, the game overrides,
## because the sheet was typed in by hand. What neither carries is set here:
##
## - the spray patterns, read off CS2 spray plots Sid supplied on 2026-09-21;
## - how long the weapon model's recoil takes to settle, from his
##   frame-by-frame capture of CS2 on 2026-09-22;
## - the stomach and leg multipliers, x1.25 and x0.75 as on every rifle in CS.


## The sheet's inaccuracy in the cone's degrees. See WeaponSheet.cone_degrees.
static func cs_inaccuracy(value: float) -> float:
	return WeaponSheet.cone_degrees(value)


static func ak47() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "AK-47"
	data.item_class = "weapon_ak47"
	data.model_path = "res://assets/weapons/weapons/models/ak47/weapon_rif_ak47.gltf"
	data.clip_set = "rifle_ak"
	data.world_clip_set = "rifle/rifle_ak"

	# 36 to an unarmoured chest, x4 head, 77.5% through armour, 2% lost every
	# 500 units, 600 RPM, 30 and 90, 215 u/s, firing again 2.467 s into a
	# reload.
	WeaponSheet.apply(data, "AK-47")
	WeaponVData.apply(data, "weapon_ak47")
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.25
	data.leg_multiplier = 0.75

	data.recoil_pattern = RecoilPattern.load_pattern("ak47")

	# Measured in CS2: the weapon model stops moving after 644 +- 5 ms.
	data.recoil_animation_time = 0.644
	return data


static func m4a1s() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "M4A1-S"
	data.item_class = "weapon_m4a1_silencer"
	data.model_path = "res://assets/weapons/weapons/models/m4a1_silencer/weapon_rif_m4a1_silencer.gltf"
	# The shared rifle clips are the ones authored on the M4A1-S: the weapon rig
	# they carry is its.
	data.clip_set = "_default_rifle"
	data.world_clip_set = "rifle/rifle_m4a1_silencer"

	# Carried with the silencer on, so its row is read over the main one: the
	# damage is the same either way (38, x3.475 head, 132), the silencer
	# changes the inaccuracy and the recoil. 20 in the magazine and 60 in
	# reserve, as the sheet says. The spray plot its pattern was read from has
	# 25 dots, most likely from CS:GO before the magazine was cut to 20; the
	# pattern file keeps them and the gun fires the first 20.
	WeaponSheet.apply(data, "M4A1-S (no silencer)", "M4A1-S (silencer)")
	# The game's second values are the silenced ones.
	WeaponVData.apply(data, "weapon_m4a1_silencer", true)
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.25
	data.leg_multiplier = 0.75

	data.recoil_pattern = RecoilPattern.load_pattern("m4a1s")

	# Measured in CS2: the weapon model stops moving after 353 +- 5 ms.
	data.recoil_animation_time = 0.353
	return data


## Every gun, one of each, in the order the game lists them.
static func all() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for weapon_class in classes():
		out.append(build(weapon_class))
	return out


## The class names of every gun build() makes: the 34 in
## reference/weapons/models.md.
static func classes() -> PackedStringArray:
	return PackedStringArray(_files().keys())


static func has(weapon_class: String) -> bool:
	return _files().has(weapon_class)


## Any gun by its CS2 class name, as a fresh WeaponData: the game's numbers
## (WeaponVData), the sheet's landing and ladder, and its model and clips
## from what the extraction lists (models.md). The AK-47 and M4A1-S are the
## hand-built ones, with their spray patterns and measured recoil. For the
## rest, what neither file carries is left as it is on every WeaponData:
## no spray pattern (the pattern is a straight climb of nothing until one is
## read off a plot, weapons TODO L6), and the AK-47's recoil settling time.
## The M4A1-S and USP-S are carried silenced, as CS2 hands them out. Null
## for a class that is not a gun.
static func build(weapon_class: String) -> WeaponData:
	match weapon_class:
		"weapon_ak47":
			return ak47()
		"weapon_m4a1_silencer":
			return m4a1s()
	if not has(weapon_class):
		return null
	var files: Dictionary = _files()[weapon_class]
	var data := WeaponData.new()
	var row: String = files["sheet_row"]
	data.item_class = weapon_class
	data.display_name = display_name(weapon_class)
	data.model_path = MODELS_ROOT.path_join(files["folder"]).path_join(files["model"])
	data.clip_set = files["first_person"]
	data.world_clip_set = files["third_person"]
	var silenced := row.ends_with(" (no silencer)")
	var silenced_row := row.trim_suffix(" (no silencer)") + " (silencer)"
	if WeaponSheet.has(row):
		WeaponSheet.apply(data, row, silenced_row if silenced else "")
	WeaponVData.apply(data, weapon_class, silenced)
	# The same on every gun in CS2: the game keeps only the head's per gun.
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.25
	data.leg_multiplier = 0.75
	if data.zoom_levels() > 0:
		data.scoped = scoped_of(data, row)
	return data


## A scoped gun's numbers with the scope up: everything as data has it, over
## which the sheet's "(scoped)" row and the game's second values go (speed,
## inaccuracy, recovery; damage and fire rate are the same either way).
static func scoped_of(data: WeaponData, sheet_row: String) -> WeaponData:
	var scoped := data.duplicate() as WeaponData
	scoped.scoped = null
	var scoped_row := sheet_row + " (scoped)"
	if WeaponSheet.has(sheet_row):
		WeaponSheet.apply(scoped, sheet_row, scoped_row if WeaponSheet.has(scoped_row) else "")
	WeaponVData.apply(scoped, data.item_class, true)
	return scoped


## CS2's English name for a gun: the sheet's, without the silencer's mode.
static func display_name(weapon_class: String) -> String:
	if not has(weapon_class):
		return ""
	return String(_files()[weapon_class]["sheet_row"]).trim_suffix(" (no silencer)")


const MODELS_PAGE := "res://reference/weapons/models.md"
const MODELS_ROOT := "res://assets/weapons/weapons/models"
const EQUIPMENT_PAGE := "res://reference/weapons/equipment.md"

static var _files_cache := {}
static var _equipment_cache := {}


## How an item is drawn: its model and its first- and third-person clip
## sets, as {model_path, clip_set, world_clip_set}. A gun's from models.md;
## the knife's, the Zeus's, the grenades', the C4's and the kit's from
## equipment.md, the knife by side (a terrorist's is the T knife). The kit,
## which nobody holds in the hand, has no first-person set (""). Empty for
## what has no model (armour).
static func look(item_class: String, team: String = "") -> Dictionary:
	if has(item_class):
		var files: Dictionary = _files()[item_class]
		return {
			"model_path": MODELS_ROOT.path_join(files["folder"]).path_join(files["model"]),
			"clip_set": files["first_person"],
			"world_clip_set": files["third_person"],
		}
	var row_class := "weapon_knife_t" if item_class == "weapon_knife" and team == "T" else item_class
	var row: Dictionary = _equipment().get(row_class, {})
	if row.is_empty():
		return {}
	return {
		"model_path": MODELS_ROOT.path_join(row["model"]),
		"clip_set": row["first_person"] if row["first_person"] != "-" else "",
		"world_clip_set": row["third_person"] if row["third_person"] != "-" else "",
	}


## Each piece of equipment's row of the first table in equipment.md:
## {class: {model, first_person, third_person}}. Read once.
static func _equipment() -> Dictionary:
	if not _equipment_cache.is_empty():
		return _equipment_cache
	var file := FileAccess.open(EQUIPMENT_PAGE, FileAccess.READ)
	if file == null:
		push_error("No equipment list at %s" % EQUIPMENT_PAGE)
		return _equipment_cache
	var in_table := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("| Class | Name | Model | First person"):
			in_table = true
			continue
		if not in_table:
			continue
		if not line.begins_with("|"):
			break
		var cells := line.trim_prefix("|").trim_suffix("|").split("|")
		if cells.size() < 5 or cells[0].strip_edges().begins_with("---"):
			continue
		_equipment_cache[_cell(cells[0])] = {
			"model": _cell(cells[2]),
			"first_person": _cell(cells[3]),
			"third_person": _cell(cells[4]),
		}
	return _equipment_cache


## A table cell's text without its backticks or a count after it
## ("`equipment/c4` (6)" is "equipment/c4").
static func _cell(cell: String) -> String:
	var text := cell.strip_edges()
	var paren := text.find(" (")
	if text.begins_with("`") and paren > 0:
		text = text.substr(0, paren)
	return text.replace("`", "")


## Each gun's row of the first table in models.md: {class: {sheet_row,
## folder, model, first_person, third_person}}. Read once.
static func _files() -> Dictionary:
	if not _files_cache.is_empty():
		return _files_cache
	var file := FileAccess.open(MODELS_PAGE, FileAccess.READ)
	if file == null:
		push_error("No weapon file list at %s" % MODELS_PAGE)
		return _files_cache
	var in_table := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("| Class | Sheet row"):
			in_table = true
			continue
		if not in_table:
			continue
		if not line.begins_with("|"):
			break
		var cells := line.trim_prefix("|").trim_suffix("|").split("|")
		if cells.size() < 7 or cells[0].strip_edges().begins_with("---"):
			continue
		var clean := func(cell: String) -> String:
			var text := cell.strip_edges()
			var paren := text.find(" (")
			if text.begins_with("`") and paren > 0:
				text = text.substr(0, paren)
			return text.replace("`", "")
		_files_cache[clean.call(cells[0])] = {
			"sheet_row": String(cells[1]).strip_edges(),
			"folder": clean.call(cells[2]),
			"model": clean.call(cells[3]),
			"first_person": clean.call(cells[5]),
			"third_person": clean.call(cells[6]),
		}
	return _files_cache
