class_name WeaponVData
extends RefCounted

## CS2's own weapon tuning, scripts/weapons.vdata_c, as
## reference/weapons/vdata.csv carries it: every field of every gun, resolved
## through the file's inheritance, one row each (written by
## scripts/weapon_tables.gd from `scripts/extract_assets.sh weapon-data`).
##
## This is the source for every number it has. The weapon sheet
## (WeaponSheet) was transcribed by hand from the same file and can carry a
## typing error; the game cannot. The sheet stays for the two figures the
## game stores as something else: the landing penalty (a coefficient the
## game scales by the fall, whose formula is not pinned down) and the ladder
## (a composite of another kind; dust2 has no ladders). reference/weapons/
## vdata.md checks the two against each other: 914 values agree.
##
## The game keeps spread and inaccuracy apart, and the firing model, like the
## sheet, works in totals: standing is its inaccuracy plus the spread, and the
## run and the jump add their own terms to that, which is exactly how the
## sheet's figures are made (checked for every gun). Two-valued fields are
## [normal, alternate]: unscoped and scoped, or the silencer off and on.

const PATH := "res://reference/weapons/vdata.csv"

static var _classes := {}


## Every gun's fields, by class: {"weapon_ak47": {"m_nDamage": "36", ...}}.
static func classes() -> Dictionary:
	if _classes.is_empty():
		_classes = _load(PATH)
	return _classes


static func has(weapon_class: String) -> bool:
	return classes().has(weapon_class)


## A field as a number: true and false are 1 and 0, and a two-valued field
## gives its second value when alternate is set. NAN if it is not there or
## not a number.
static func number(weapon_class: String, field: String, alternate: bool = false) -> float:
	var text := String((classes().get(weapon_class, {}) as Dictionary).get(field, ""))
	var values := text.split("|")
	var value := values[mini(1 if alternate else 0, values.size() - 1)].strip_edges()
	if value == "true":
		return 1.0
	if value == "false":
		return 0.0
	return value.to_float() if value.is_valid_float() else NAN


## Puts a gun's numbers from the game on data, over whatever was there. The
## alternate values are the scoped or silenced ones.
static func apply(data: WeaponData, weapon_class: String, alternate: bool = false) -> void:
	assert(has(weapon_class), "No %s in %s" % [weapon_class, PATH])
	var get_value := func(field: String) -> float:
		return number(weapon_class, field, alternate)

	data.base_damage = get_value.call("m_nDamage")
	data.pellets = int(get_value.call("m_nNumBullets"))
	# The armour ratio is twice the share of damage that gets through.
	data.armor_penetration = get_value.call("m_flArmorRatio") * 0.5
	data.range_modifier = get_value.call("m_flRangeModifier")
	data.head_multiplier = get_value.call("m_flHeadshotMultiplier")
	data.cycle_time = get_value.call("m_flCycleTime")
	data.penetration_power = get_value.call("m_flPenetration")
	data.magazine_size = int(get_value.call("m_iMaxClip1"))
	# Counted in magazines, but for the shotguns loaded a shell at a time.
	var reserve := int(get_value.call("m_nPrimaryReserveAmmoMax"))
	data.reserve_as_clips = get_value.call("m_bReserveAmmoAsClips") == 1.0
	data.reserve_ammo = reserve * data.magazine_size if data.reserve_as_clips else reserve
	data.max_player_speed = get_value.call("m_flMaxSpeed")
	# How much of a victim's speed a hit leaves is the flinch modifier.
	data.tagging_power = 1.0 - get_value.call("m_flFlinchVelocityModifierLarge")
	data.max_range = get_value.call("m_flRange")
	data.automatic = get_value.call("m_bIsFullAuto") == 1.0
	# When a reloading gun may fire again. For a magazine gun it is the
	# reload clip's length or a frame longer; for the shotguns that load a
	# shell at a time it ends near the end of the clip's intro, before the
	# first shell goes in (reference/weapons/timings.md).
	data.reload_time = get_value.call("m_flDisallowAttackAfterReloadStartDuration")

	var spread: float = get_value.call("m_flSpread")
	var stand: float = get_value.call("m_flInaccuracyStand")
	data.inaccuracy_standing = _cone(stand + spread)
	data.inaccuracy_crouching = _cone(get_value.call("m_flInaccuracyCrouch") + spread)
	data.inaccuracy_moving = _cone(get_value.call("m_flInaccuracyMove") + stand + spread)
	data.inaccuracy_jumping = _cone(get_value.call("m_flInaccuracyJump") + stand + spread)
	data.inaccuracy_per_shot = _cone(get_value.call("m_flInaccuracyFire"))
	data.spread = _cone(spread)
	data.spread_seed = int(get_value.call("m_nSpreadSeed"))
	data.recovery_time_crouch = get_value.call("m_flRecoveryTimeCrouch")
	data.recovery_time_stand = get_value.call("m_flRecoveryTimeStand")

	# The recoil: only the provisional kick of a gun with no pattern reads it
	# (WeaponData.recoil_magnitude).
	data.recoil_magnitude = get_value.call("m_flRecoilMagnitude")
	data.recoil_magnitude_variance = get_value.call("m_flRecoilMagnitudeVariance")
	data.recoil_angle = get_value.call("m_flRecoilAngle")
	data.recoil_angle_variance = get_value.call("m_flRecoilAngleVariance")
	data.recoil_seed = int(get_value.call("m_nRecoilSeed"))

	# The scope: one value each, the same scoped or not.
	data.zoom_fovs = PackedFloat32Array()
	var levels: float = get_value.call("m_nZoomLevels")
	for level in range(1, int(levels if not is_nan(levels) else 0.0) + 1):
		data.zoom_fovs.append(get_value.call("m_nZoomFOV%d" % level))
	data.zoom_times = PackedFloat32Array()
	if not data.zoom_fovs.is_empty():
		for level in 3:
			data.zoom_times.append(get_value.call("m_flZoomTime%d" % level))
	data.unzooms_after_shot = get_value.call("m_bUnzoomsAfterShot") == 1.0
	data.hides_view_model_when_zoomed = get_value.call("m_bHideViewModelWhenZoomed") == 1.0
	data.shows_crosshair = get_value.call("m_bShowCrosshair") != 0.0


## The game's inaccuracy (the tangent of the widest angle a round leaves the
## aim by) as the cone's degrees.
static func _cone(tangent: float) -> float:
	return WeaponSheet.cone_degrees(tangent * 1000.0)


static func _load(path: String) -> Dictionary:
	var out := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No weapon tuning at %s" % path)
		return out
	file.get_line()  # the header: class,field,value
	while not file.eof_reached():
		var line := file.get_line()
		var first := line.find(",")
		var second := line.find(",", first + 1)
		if first < 0 or second < 0:
			continue
		var weapon_class := line.substr(0, first)
		if not out.has(weapon_class):
			out[weapon_class] = {}
		(out[weapon_class] as Dictionary)[line.substr(first + 1, second - first - 1)] = line.substr(second + 1)
	return out
