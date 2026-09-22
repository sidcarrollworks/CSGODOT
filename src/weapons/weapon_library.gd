class_name WeaponLibrary
extends RefCounted

## The two weapons the project starts with.
##
## Every number here is a published community figure, not a measurement, and
## the sources disagree in places. They are a starting point for tuning and
## should not be trusted until someone has checked them in game. See
## reference/weapon_stats.md for where each one came from.
##
## The exceptions, which ARE measured, are the spray patterns, the M4A1-S
## magazine size, and the two recovery timings below. The patterns and the
## magazine come from CS2 spray plots Sid supplied on 2026-09-21; the timings
## come from his frame-by-frame capture of CS2 on 2026-09-22.

static func ak47() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "AK-47"
	data.model_path = "res://assets/weapons/weapons/models/ak47/weapon_rif_ak47.gltf"
	data.clip_set = "rifle_ak"

	# 36 to an unarmoured chest, x4 head, x1.25 stomach, x0.75 leg, and
	# roughly 78% through armour.
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

	data.inaccuracy_standing = 0.02
	data.inaccuracy_moving = 0.95
	data.inaccuracy_jumping = 4.5
	data.inaccuracy_per_shot = 0.13
	return data


static func m4a1s() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "M4A1-S"
	data.model_path = "res://assets/weapons/weapons/models/m4a1_silencer/weapon_rif_m4a1_silencer.gltf"
	# The shared rifle clips are the ones authored on the M4A1-S: the weapon rig
	# they carry is its.
	data.clip_set = "_default_rifle"

	# 37 to an unarmoured chest, 132 to the head, 47 stomach, 28 leg.
	data.base_damage = 37.0
	data.armor_penetration = 0.70
	data.head_multiplier = 3.57  # 132 / 37, rather than a clean x4
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.27
	data.leg_multiplier = 0.76
	data.range_modifier = 0.94

	data.cycle_time = 0.1  # 600 RPM
	# 25, not the 20 this used to say. The CS2 spray plot for this weapon has
	# 25 dots on it, which settles it.
	data.magazine_size = 25
	data.reserve_ammo = 75
	data.reload_time = 3.1

	data.max_player_speed = 225.0

	data.recoil_pattern = RecoilPattern.load_pattern("m4a1s")

	# Measured in CS2: animation 353 +- 5 ms, accuracy 542 +- 0 ms. Both are
	# faster than the AK, and the gap between them is a similar 189 ms.
	data.recoil_animation_time = 0.353
	data.accuracy_reset_time = 0.542

	data.inaccuracy_standing = 0.015
	data.inaccuracy_moving = 0.8
	data.inaccuracy_jumping = 4.0
	data.inaccuracy_per_shot = 0.10
	return data


static func all() -> Array[WeaponData]:
	return [ak47(), m4a1s()]
