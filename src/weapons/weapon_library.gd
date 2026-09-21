class_name WeaponLibrary
extends RefCounted

## The two weapons the project starts with.
##
## Every number here is a published community figure, not a measurement, and
## the sources disagree in places. They are a starting point for tuning and
## should not be trusted until someone has checked them in game. See
## reference/weapon_stats.md for where each one came from.

static func ak47() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "AK-47"

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
	data.inaccuracy_standing = 0.02
	data.inaccuracy_moving = 0.95
	data.inaccuracy_jumping = 4.5
	data.inaccuracy_per_shot = 0.13
	return data


static func m4a1s() -> WeaponData:
	var data := WeaponData.new()
	data.display_name = "M4A1-S"

	# 37 to an unarmoured chest, 132 to the head, 47 stomach, 28 leg.
	data.base_damage = 37.0
	data.armor_penetration = 0.70
	data.head_multiplier = 3.57  # 132 / 37, rather than a clean x4
	data.chest_multiplier = 1.0
	data.stomach_multiplier = 1.27
	data.leg_multiplier = 0.76
	data.range_modifier = 0.94

	data.cycle_time = 0.1  # 600 RPM
	data.magazine_size = 20
	data.reserve_ammo = 80
	data.reload_time = 3.1

	data.max_player_speed = 225.0

	data.recoil_pattern = RecoilPattern.load_pattern("m4a1s")
	data.inaccuracy_standing = 0.015
	data.inaccuracy_moving = 0.8
	data.inaccuracy_jumping = 4.0
	data.inaccuracy_per_shot = 0.10
	return data


static func all() -> Array[WeaponData]:
	return [ak47(), m4a1s()]
