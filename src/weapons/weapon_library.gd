class_name WeaponLibrary
extends RefCounted

## The two weapons the project starts with.
##
## Damage, armour, falloff, fire rate, speed and inaccuracy come from the CS2
## Weapon Spreadsheet (last weapon update 18 March 2026) Sid supplied on
## 2026-09-22; its rows for these two weapons are copied into
## reference/weapon_stats.md. Reload times are not in it and are still
## community figures.
##
## Also measured: the spray patterns and the M4A1-S magazine size, from CS2
## spray plots Sid supplied on 2026-09-21, and the two recovery timings
## below, from his frame-by-frame capture of CS2 on 2026-09-22.


## The sheet gives inaccuracy in CS's own units: thousandths of the tangent
## of the largest angle a round can leave the aim by, the way the weapon
## scripts store it. "Accurate range" checks it: 7.01 for the AK is 15.24 cm
## off at 21.74 m, the sheet's figure. The cone here is in degrees.
static func cs_inaccuracy(value: float) -> float:
	return rad_to_deg(atan(value / 1000.0))

static func ak47() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "AK-47"
	data.model_path = "res://assets/weapons/weapons/models/ak47/weapon_rif_ak47.gltf"
	data.clip_set = "rifle_ak"

	# 36 to an unarmoured chest, x4 head, 77.5% through armour, 2% lost every
	# 500 units. The sheet has no stomach or leg multiplier; x1.25 and x0.75
	# are what every rifle in CS uses.
	data.base_damage = 36.0
	data.armor_penetration = 0.775
	data.head_multiplier = 4.0
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.25
	data.leg_multiplier = 0.75
	data.range_modifier = 0.98

	data.cycle_time = 0.1  # 600 RPM
	data.magazine_size = 30
	data.reserve_ammo = 90
	data.reload_time = 2.5

	data.max_player_speed = 215.0

	data.recoil_pattern = RecoilPattern.load_pattern("ak47")

	# Measured in CS2: the weapon model stops moving after 644 +- 5 ms, and
	# the accuracy box is back to baseline after 867 +- 0 ms. The gun looks
	# ready 223 ms before it is.
	data.recoil_animation_time = 0.644
	data.accuracy_reset_time = 0.867

	# The sheet's figures are totals, the rifle's spread included: standing
	# still, crouched, at full run, at the top of a standing jump, and added
	# by each round.
	data.inaccuracy_standing = cs_inaccuracy(7.01)
	data.inaccuracy_crouching = cs_inaccuracy(5.41)
	data.inaccuracy_moving = cs_inaccuracy(182.07)
	data.inaccuracy_jumping = cs_inaccuracy(147.77)
	data.inaccuracy_per_shot = cs_inaccuracy(7.80)
	return data


static func m4a1s() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "M4A1-S"
	data.model_path = "res://assets/weapons/weapons/models/m4a1_silencer/weapon_rif_m4a1_silencer.gltf"
	# The shared rifle clips are the ones authored on the M4A1-S: the weapon rig
	# they carry is its.
	data.clip_set = "_default_rifle"

	# 38 to an unarmoured chest, x3.475 head (132), 70% through armour, 6%
	# lost every 500 units. Stomach and leg as every rifle's.
	data.base_damage = 38.0
	data.armor_penetration = 0.70
	data.head_multiplier = 3.475
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.25
	data.leg_multiplier = 0.75
	data.range_modifier = 0.94

	data.cycle_time = 0.1  # 600 RPM
	# 25, not the 20 this used to say. The CS2 spray plot for this weapon has
	# 25 dots on it. The weapon spreadsheet says 20 (and 60 in reserve), so
	# one of the two is wrong: see reference/weapon_stats.md.
	data.magazine_size = 25
	data.reserve_ammo = 75
	data.reload_time = 3.1

	data.max_player_speed = 225.0

	data.recoil_pattern = RecoilPattern.load_pattern("m4a1s")

	# Measured in CS2: animation 353 +- 5 ms, accuracy 542 +- 0 ms. Both are
	# faster than the AK, and the gap between them is a similar 189 ms.
	data.recoil_animation_time = 0.353
	data.accuracy_reset_time = 0.542

	# The silencer-on row, since that is how it is carried. Firing costs it
	# less than the AK, running costs it less, and it stands a little tighter.
	data.inaccuracy_standing = cs_inaccuracy(5.40)
	data.inaccuracy_crouching = cs_inaccuracy(4.60)
	data.inaccuracy_moving = cs_inaccuracy(127.40)
	data.inaccuracy_jumping = cs_inaccuracy(105.10)
	data.inaccuracy_per_shot = cs_inaccuracy(7.00)
	return data


static func all() -> Array[WeaponData]:
	return [ak47(), m4a1s()]
