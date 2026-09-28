extends "res://tests/check_suite.gd"

## Recoil on every gun, not only the AK-47 and M4A1-S (playtest 2026-09-25,
## issue 14): the 15 community patterns read into the guns they belong to,
## every gun kicking the view and the weapon model, the guns with no pattern
## kicking by CS2's recoil magnitude, and every pattern's pushes solved
## before play rather than in the tick of a first buy.
##
##   godot --headless --path . --script tests/run_recoil_checks.gd
##
## run_weapon_tests.gd checks the recoil model itself on the AK-47 and
## M4A1-S; this checks that every other gun is wired into it.

const SECOND := 1_000_000
const DT := 1.0 / 128.0

## The guns WeaponLibrary.build reads a community pattern for: every
## weapon_<class>.csv but the AK-47's and M4A1-S's, which keep the patterns
## read off Sid's plots (ak47.csv, m4a1s.csv).
const COMMUNITY := [
	"weapon_m4a1", "weapon_galilar", "weapon_famas", "weapon_sg556", "weapon_aug",
	"weapon_p90", "weapon_bizon", "weapon_ump45", "weapon_mac10", "weapon_mp5sd",
	"weapon_mp7", "weapon_mp9", "weapon_m249", "weapon_negev", "weapon_cz75a",
]


func _initialize() -> void:
	_check_patterns_are_the_files()
	_check_only_those_guns_have_patterns()
	_check_the_scoped_copies_carry_the_pattern()
	_check_held_sprays_walk_the_pattern()
	_check_every_gun_kicks()
	_check_the_provisional_kick_goes_by_magnitude()
	_check_the_provisional_kick_leans_by_the_seed()
	_check_the_scope_shrinks_the_kick()
	_check_every_pattern_is_solved_before_play()
	_finish("recoil")


func _check_patterns_are_the_files() -> void:
	for weapon_class in COMMUNITY:
		var data := WeaponLibrary.build(weapon_class)
		var file := RecoilPattern.load_from(
			RecoilPattern.PATTERN_DIR.path_join("%s.csv" % weapon_class)
		)
		_check(
			not file.is_empty() and data.recoil_pattern == file,
			"%s carries its pattern file's %d rounds (%d)"
				% [weapon_class, file.size(), data.recoil_pattern.size()]
		)
	# The two hand-read ones stay on theirs.
	_check_equal(
		WeaponLibrary.build("weapon_ak47").recoil_pattern, RecoilPattern.load_pattern("ak47"),
		"the AK-47 keeps the pattern read off Sid's plot"
	)
	_check_equal(
		WeaponLibrary.build("weapon_m4a1_silencer").recoil_pattern, RecoilPattern.load_pattern("m4a1s"),
		"the M4A1-S keeps the pattern read off Sid's plot"
	)


func _check_only_those_guns_have_patterns() -> void:
	var without: Array[String] = []
	for weapon_class in WeaponLibrary.classes():
		var data := WeaponLibrary.build(weapon_class)
		if data.recoil_pattern.is_empty():
			without.append(weapon_class)
		elif not (weapon_class in COMMUNITY or weapon_class in ["weapon_ak47", "weapon_m4a1_silencer"]):
			_check(false, "%s has a pattern from nowhere" % weapon_class)
	_check_equal(
		without.size(), WeaponLibrary.classes().size() - COMMUNITY.size() - 2,
		"every other gun has no pattern, and no bullet path is made up for it (%s)" % [without]
	)


func _check_the_scoped_copies_carry_the_pattern() -> void:
	for weapon_class in ["weapon_sg556", "weapon_aug"]:
		var data := WeaponLibrary.build(weapon_class)
		_check(
			data.scoped != null and data.scoped.recoil_pattern == data.recoil_pattern,
			"%s's scoped numbers carry its pattern" % weapon_class
		)
		_check(
			data.scoped != null and data.scoped.recoil_magnitude < data.recoil_magnitude,
			"and the game's smaller scoped magnitude (%.0f against %.0f)"
				% [data.scoped.recoil_magnitude if data.scoped else 0.0, data.recoil_magnitude]
		)


## Held down with the cone taken away, every round of every patterned gun
## lands on its entry, at the gun's own rate of fire, the whole magazine.
func _check_held_sprays_walk_the_pattern() -> void:
	for weapon_class in COMMUNITY + ["weapon_ak47", "weapon_m4a1_silencer"]:
		var data := WeaponLibrary.build(weapon_class)
		data.inaccuracy_standing = 0.0
		data.inaccuracy_crouching = 0.0
		data.inaccuracy_per_shot = 0.0
		data.spread = 0.0
		var weapon := Weapon.new(data)
		var state := Weapon.ShooterState.new(0.0, true, false)
		var cycle := int(round(data.cycle_time * SECOND))
		var rounds := mini(data.magazine_size, data.recoil_pattern.size())
		var worst := 0.0
		var worst_round := -1
		var fired := 0
		for shot in rounds:
			var at := SECOND + shot * cycle
			weapon.update(0.0, at)
			var round_fired := weapon.fire(at, 0.0, Vector3.ZERO, 0.0, 0.0, state)
			if round_fired == null:
				break
			fired += 1
			var angles := PlayerInput.angles_from_direction(round_fired.direction)
			# Pattern x is degrees right, and yaw decreases rightward.
			var miss := Vector2(-angles.x, angles.y).distance_to(data.recoil_offset(shot))
			if miss > worst:
				worst = miss
				worst_round = shot
		_check_equal(fired, rounds, "%s fires its %d rounds on a held trigger" % [weapon_class, rounds])
		_check(
			worst < 0.02,
			"%s lands every round on its pattern entry (worst %.4f degrees off, round %d)"
				% [weapon_class, worst, worst_round]
		)
		if data.recoil_pattern.size() > 8:
			_check(
				data.recoil_offset(rounds - 1).length() > 1.0,
				"and %s's bullets climb (%.2f degrees by the last round)"
					% [weapon_class, data.recoil_offset(rounds - 1).length()]
			)


## Every gun kicks the camera and the weapon model on its first round.
func _check_every_gun_kicks() -> void:
	var still: Array[String] = []
	for weapon_class in WeaponLibrary.classes():
		var data := WeaponLibrary.build(weapon_class)
		if data.view_kick_up() <= 0.0:
			still.append("%s (no kick)" % weapon_class)
			continue
		var weapon := Weapon.new(data)
		var now := SECOND
		weapon.fire(now, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new(0.0, true, false))
		var view := 0.0
		var model := 0.0
		for tick in 16:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			view = maxf(view, weapon.aim_punch.y)
			model = maxf(model, weapon.viewmodel_punch().length())
		if view <= 0.1 or model <= 0.0:
			still.append("%s (view %.2f, model %.3f)" % [weapon_class, view, model])
	_check(still.is_empty(), "every one of the %d guns kicks the view and the weapon model on its first round %s"
		% [WeaponLibrary.classes().size(), still if not still.is_empty() else ""])


## A gun with no pattern kicks the AK-47's per-round kick times its recoil
## magnitude over the AK's 30: provisional, until a CS2 demo measures it.
func _check_the_provisional_kick_goes_by_magnitude() -> void:
	var ak := WeaponLibrary.build("weapon_ak47")
	_check_equal(ak.recoil_magnitude, 30.0, "the AK-47's recoil magnitude is the game's 30")
	var per := ak.view_kick_up() / 30.0
	_check_near(WeaponData.provisional_kick_per_magnitude(), per, "the provisional kick is the AK-47's per unit of magnitude")
	var deagle := WeaponLibrary.build("weapon_deagle")
	var glock := WeaponLibrary.build("weapon_glock")
	var awp := WeaponLibrary.build("weapon_awp")
	var nova := WeaponLibrary.build("weapon_nova")
	_check_near(deagle.view_kick_up(), per * 48.2, "the Deagle kicks 48.2 of it (%.2f degrees)" % deagle.view_kick_up())
	_check_near(glock.view_kick_up(), per * 18.0, "the Glock, its single fire, 18 (%.2f)" % glock.view_kick_up())
	_check(
		nova.view_kick_up() > awp.view_kick_up() and awp.view_kick_up() > deagle.view_kick_up()
			and deagle.view_kick_up() > ak.view_kick_up() and ak.view_kick_up() > glock.view_kick_up(),
		"so the kicks order as the game's magnitudes do: Nova, AWP, Deagle, AK-47, Glock"
	)
	var usp := WeaponLibrary.build("weapon_usp_silencer")
	_check_near(usp.recoil_magnitude, 23.0, "the USP-S, carried silenced, takes the game's silenced 23")


## The lean of a gun with no pattern comes from its recoil seed and the
## round: the same every time, some rounds each way, and none for a gun the
## game gives no angle variance.
func _check_the_provisional_kick_leans_by_the_seed() -> void:
	var sides := func(weapon_class: String) -> Array[float]:
		var data := WeaponLibrary.build(weapon_class)
		var weapon := Weapon.new(data)
		var out: Array[float] = []
		var cycle := int(round(maxf(data.cycle_time, 0.3) * SECOND))
		for shot in 7:
			var at := SECOND + shot * cycle
			weapon.trigger_held = false
			weapon.update(0.0, at)
			var fired := weapon.fire(at, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new(0.0, true, false))
			out.append(fired.view_punch.x if fired != null else NAN)
		return out
	var first: Array[float] = sides.call("weapon_deagle")
	_check_equal(first, sides.call("weapon_deagle"), "the Deagle leans the same way round for round, every time (%s)" % [first])
	var left := first.filter(func(x: float) -> bool: return x < 0.0).size()
	var right := first.filter(func(x: float) -> bool: return x > 0.0).size()
	_check(left > 0 and right > 0, "and both ways (%d left, %d right)" % [left, right])
	var usp: Array[float] = sides.call("weapon_usp_silencer")
	_check(usp.all(func(x: float) -> bool: return x == 0.0), "the USP-S, with no angle variance, goes straight up (%s)" % [usp])


## Scoped, a gun kicks by the game's scoped magnitude: the AWP's 25 against
## 78 unscoped.
func _check_the_scope_shrinks_the_kick() -> void:
	var data := WeaponLibrary.build("weapon_awp")
	var weapon := Weapon.new(data)
	var noscope := weapon.fire(SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new(0.0, true, false))
	var scoped_weapon := Weapon.new(data)
	scoped_weapon.press_zoom(SECOND)
	var later := SECOND * 3
	scoped_weapon.update(0.0, later)
	var scoped := scoped_weapon.fire(later, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new(0.0, true, false))
	_check(noscope != null and scoped != null, "the AWP fires scoped and not")
	if noscope == null or scoped == null:
		return
	_check_near(
		scoped.view_punch.y / noscope.view_punch.y, 25.0 / 78.0,
		"scoped, the AWP's kick is 25/78 of its noscope kick (%.2f against %.2f degrees)"
			% [scoped.view_punch.y, noscope.view_punch.y]
	)


## load_all solves every pattern's pushes, so no Weapon built in a tick (a
## buy, a pickup) solves one: the Negev's 150 rounds took tens of ms.
func _check_every_pattern_is_solved_before_play() -> void:
	RecoilState._solved.clear()
	ItemRegistry._weapon_data.clear()
	var started := Time.get_ticks_usec()
	ItemRegistry.load_all()
	var took := float(Time.get_ticks_usec() - started) / 1000.0
	print("ItemRegistry.load_all with every pattern solved: %.0f ms" % took)
	var unsolved: Array[String] = []
	for def in ItemRegistry.guns():
		var data := ItemRegistry.weapon_data(def.item_class)
		if data.recoil_pattern.is_empty():
			continue
		var pattern := PackedVector2Array()
		for i in data.recoil_pattern.size():
			pattern.append(data.recoil_offset(i))
		if not RecoilState._solved.has([pattern, data.cycle_time]):
			unsolved.append(def.item_class)
	_check(unsolved.is_empty(), "load_all leaves every gun's pattern solved %s" % [unsolved if not unsolved.is_empty() else ""])
	for weapon_class in ["weapon_m249", "weapon_negev"]:
		var data := ItemRegistry.weapon_data(weapon_class)
		var at := Time.get_ticks_usec()
		var weapon := Weapon.new(data)
		var built := float(Time.get_ticks_usec() - at) / 1000.0
		print("a %s built after load_all: %.2f ms" % [weapon_class, built])
		_check(weapon.data.recoil_pattern.size() >= 100, "%s's copy carries its %d-round pattern" % [weapon_class, data.recoil_pattern.size()])
