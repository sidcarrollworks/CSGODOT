class_name WeaponSheet
extends RefCounted

## The CS2 Weapon Spreadsheet, read from reference/weapons/cs2_weapon_sheet.csv.
##
## CS2's own weapon tuning (scripts/weapons.vdata_c) cannot be extracted, so
## every weapon's numbers come from this sheet instead: one row per weapon and
## per mode ("AUG (scoped)", "FAMAS (burst)", "M4A1-S (silencer)"), its values
## copied verbatim. A mode row gives only what the mode changes and says "-"
## for the rest, so a mode is read over its weapon's main row.
##
## The sheet checks out against itself, which is why it is trusted: its fatal
## headshot range is damage, head multiplier, armour and falloff worked
## through exactly as HitTarget and WeaponData do them, for every weapon, and
## its accurate range is where the standing cone is six inches wide, for
## every weapon. reference/weapons/README.md has what every column means.

const PATH := "res://reference/weapons/cs2_weapon_sheet.csv"

static var _rows: Dictionary = {}


## Every row, by the weapon's name as the sheet spells it.
static func rows() -> Dictionary:
	if _rows.is_empty():
		_rows = _load(PATH)
	return _rows


static func has(weapon: String) -> bool:
	return rows().has(weapon)


## One column of one row, as the sheet has it ("$2,700", "77.50%", "-").
static func raw(weapon: String, column: String) -> String:
	var row: Dictionary = rows().get(weapon, {})
	return str(row.get(column, ""))


## One column as a number: currency, percentages (as fractions), multipliers
## and metres stripped of their units. NAN where the sheet has no number
## ("-", "N/A", "see note", blank).
static func number(weapon: String, column: String) -> float:
	return parse_number(raw(weapon, column))


## A mode's column, falling back to its weapon's main row where the mode
## says "-" or nothing.
static func number_for_mode(weapon: String, mode: String, column: String) -> float:
	if not mode.is_empty():
		var value := number(mode, column)
		if not is_nan(value):
			return value
	return number(weapon, column)


## A mode's column as text, falling back the same way.
static func text_for_mode(weapon: String, mode: String, column: String) -> String:
	if not mode.is_empty():
		var value := raw(mode, column).strip_edges()
		if not value.is_empty() and value != "-":
			return value
	return raw(weapon, column).strip_edges()


static func parse_number(text: String) -> float:
	var s := text.strip_edges()
	if s.is_empty() or s == "-" or s == "N/A" or not (s[0].is_valid_int() or s[0] == "$" or s[0] == "."):
		return NAN
	var percent := s.ends_with("%")
	s = s.replace("$", "").replace(",", "").replace("%", "").trim_suffix("x").trim_suffix("m")
	if not s.is_valid_float():
		return NAN
	return s.to_float() / 100.0 if percent else s.to_float()


## Converts the sheet's inaccuracy into the cone's degrees.
##
## The sheet gives inaccuracy in CS's own units: thousandths of the tangent of
## the widest angle a round can leave the aim by, the way the weapon scripts
## store it. Its accurate range checks it: 7.01 for the AK is 15.24 cm off at
## 21.74 m, the sheet's figure.
static func cone_degrees(value: float) -> float:
	return rad_to_deg(atan(value / 1000.0))


## Puts a weapon's numbers from the sheet on data. mode, where given, is the
## row the weapon is carried in ("M4A1-S (silencer)"), read over the main row.
##
## Everything the firing model uses comes from here. What the sheet does not
## have (reload time, the spray pattern, the stomach and leg multipliers,
## models and clips) is the caller's.
static func apply(data: WeaponData, weapon: String, mode: String = "") -> void:
	assert(has(weapon), "No row for %s in %s" % [weapon, PATH])
	var get_value := func(column: String) -> float:
		return number_for_mode(weapon, mode, column)

	data.base_damage = get_value.call("Damage")
	data.pellets = int(get_value.call("Bullets"))
	data.armor_penetration = get_value.call("Armor Penetration")
	data.range_modifier = 1.0 - get_value.call("Damage Falloff @ 500U")
	data.head_multiplier = get_value.call("Headshot Multiplier")
	data.cycle_time = 60.0 / get_value.call("Fire Rate (RPM)")
	data.penetration_power = get_value.call("Penetration Power")
	data.magazine_size = int(get_value.call("Magazine Size"))
	data.reserve_ammo = int(get_value.call("Total Ammo")) - data.magazine_size
	data.max_player_speed = get_value.call("Mobility")
	data.tagging_power = get_value.call("Tagging Power")
	data.max_range = get_value.call("Bullet Range")
	data.automatic = text_for_mode(weapon, mode, "Hold to Shoot") == "Yes"

	data.inaccuracy_standing = cone_degrees(get_value.call("Standing Inaccuracy"))
	data.inaccuracy_crouching = cone_degrees(get_value.call("Crouching Inaccuracy"))
	data.inaccuracy_moving = cone_degrees(get_value.call("Running Inaccuracy"))
	data.inaccuracy_ladder = cone_degrees(get_value.call("Ladder Inaccuracy"))
	data.inaccuracy_jumping = cone_degrees(get_value.call("Inaccuracy at Jump Apex"))
	data.inaccuracy_landing = cone_degrees(get_value.call("Inaccuracy After Landing"))
	data.inaccuracy_per_shot = cone_degrees(get_value.call("Inaccuracy From Firing"))
	data.recovery_time_crouch = get_value.call("Recovery TimeCrouch")
	data.recovery_time_stand = get_value.call("Recovery TimeStand")


static func _load(path: String) -> Dictionary:
	var result := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No weapon sheet at %s" % path)
		return result
	var header := PackedStringArray()
	while not file.eof_reached():
		var fields := file.get_csv_line()
		if fields.is_empty() or fields[0].begins_with("#") or (fields.size() == 1 and fields[0].is_empty()):
			continue
		if header.is_empty():
			header = fields
			continue
		var row := {}
		for i in mini(header.size(), fields.size()):
			row[header[i]] = fields[i]
		result[row.get("Weapon", "")] = row
	file.close()
	return result
