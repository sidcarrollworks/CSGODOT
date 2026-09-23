class_name WeaponLibrary
extends RefCounted

## The two weapons the project starts with.
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


static func all() -> Array[WeaponData]:
	return [ak47(), m4a1s()]
