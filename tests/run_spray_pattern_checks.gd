extends "res://tests/check_suite.gd"

## Checks the spray pattern files named by CS2 class
## (reference/spray_patterns/weapon_<class>.csv): that each reads, belongs to
## a fully automatic gun in the game's own file, starts at the point of aim
## and covers the magazine. Then that they agree with what the game's file
## says about their shape: guns that share a recoil seed and magnitude share a
## pattern, and a gun with no angle variance climbs straight up.
##
##   godot --headless --path . --script tests/run_spray_pattern_checks.gd
##
## The patterns came from a community tool, not from CS2 or a measurement
## here (reference/spray_patterns/README.md), so these checks are the part of
## them the game's own numbers can vouch for.

const PATTERN_DIR := "res://reference/spray_patterns"

## The seventeen guns the source covers.
const CLASSES := [
	"weapon_ak47", "weapon_m4a1", "weapon_m4a1_silencer", "weapon_galilar",
	"weapon_famas", "weapon_sg556", "weapon_aug", "weapon_p90", "weapon_bizon",
	"weapon_ump45", "weapon_mac10", "weapon_mp5sd", "weapon_mp7", "weapon_mp9",
	"weapon_m249", "weapon_negev", "weapon_cz75a",
]


func _initialize() -> void:
	for weapon_class in CLASSES:
		_check_file(weapon_class)
	_check_nothing_else()
	_check_shared_seed("weapon_mp7", "weapon_mp5sd")
	_check_straight_up("weapon_negev")
	_finish("spray-pattern")


func _check_file(weapon_class: String) -> void:
	var pattern := RecoilPattern.load_pattern(weapon_class)
	_check(not pattern.is_empty(), "%s has a pattern" % weapon_class)
	if pattern.is_empty():
		return
	_check(WeaponVData.has(weapon_class), "%s is a gun in vdata.csv" % weapon_class)
	_check_equal(WeaponVData.number(weapon_class, "m_bIsFullAuto"), 1.0,
		"%s is fully automatic" % weapon_class)
	_check_equal(pattern[0], Vector2.ZERO, "%s's first shot goes where it is aimed" % weapon_class)
	# The M4A1-S's has 25 rows, CS:GO's magazine, over CS2's 20: more is fine.
	var magazine := int(WeaponVData.number(weapon_class, "m_iMaxClip1"))
	_check(pattern.size() >= magazine, "%s's pattern covers its %d rounds (has %d)" % [
		weapon_class, magazine, pattern.size()])
	var highest := 0.0
	for offset in pattern:
		highest = maxf(highest, offset.y)
	_check(highest > 5.0 and highest < 25.0,
		"%s climbs a spray's height (%.1f degrees)" % [weapon_class, highest])


## Every weapon_*.csv here is one of the checked seventeen, so a new one
## gets its checks added with it.
func _check_nothing_else() -> void:
	for file in DirAccess.get_files_at(PATTERN_DIR):
		if file.begins_with("weapon_") and file.ends_with(".csv"):
			_check(file.get_basename() in CLASSES, "%s is one of the checked guns" % file)


## CS2 gives the MP7 and MP5-SD the same recoil seed, magnitude and angle
## variance, so the same kicks.
func _check_shared_seed(first: String, second: String) -> void:
	for field in ["m_nRecoilSeed", "m_flRecoilMagnitude", "m_flRecoilAngleVariance"]:
		_check_equal(WeaponVData.number(first, field), WeaponVData.number(second, field),
			"%s and %s share %s" % [first, second, field])
	_check_equal(RecoilPattern.load_pattern(first), RecoilPattern.load_pattern(second),
		"%s and %s share a pattern" % [first, second])


## A gun whose kicks have no angle variance kicks straight up every round.
func _check_straight_up(weapon_class: String) -> void:
	_check_equal(WeaponVData.number(weapon_class, "m_flRecoilAngleVariance"), 0.0,
		"%s has no recoil angle variance" % weapon_class)
	var sideways := 0.0
	for offset in RecoilPattern.load_pattern(weapon_class):
		sideways = maxf(sideways, absf(offset.x))
	_check_equal(sideways, 0.0, "%s never moves sideways" % weapon_class)
