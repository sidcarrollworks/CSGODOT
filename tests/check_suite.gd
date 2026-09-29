extends SceneTree

## What every test file shares: counting its checks, saying which failed,
## and ending with one line scripts/run_tests.sh reads to report every file
## together.
##
## A test file extends this by path (extends "res://tests/check_suite.gd"),
## runs its checks with _check, _check_equal and _check_near, and ends with
## _finish, or with _skip when what it checks is not there (dust2 before it
## is extracted). Whatever else it prints is its own.
##
## The last line of a file's output is the one the runner reads:
##
##     TESTS <name> <checks> <failures>
##     TESTS <name> skipped <why>
##
## A file that ends without it (a script error, a crash, a quit of its own)
## counts as failed.
##
## A check Sid has chosen to leave failing for now is a known-open one
## (_check_known_open): it still runs and is printed, as "KNOWN OPEN (where
## it is tracked): ...", but does not fail the file; the runner's summary
## counts them. Once one passes it says so, so it can go back to a _check.

var _checks: int = 0
var _failures: int = 0
var _known_open: int = 0


## Every ray in a tick that can meet a hitbox is held to the hitboxes
## themselves, in every check file (Box3DQueries.check_sets): what it met
## is compared with the nearest capsule on its line, worked out from the
## hitboxes' own nodes. A file in which one did not agree has failed.
func _init() -> void:
	Box3DQueries.check_sets = true
	Box3DQueries.set_faults = PackedStringArray()
	Box3DQueries.set_rays_held = 0


## Whether a passing check is printed as well as a failing one. Some files
## read better as a list of what was checked.
func _print_passes() -> bool:
	return false


## How close _check_near wants two numbers to be.
func _near_tolerance() -> float:
	return 0.01


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		if _print_passes():
			print("  ok   %s" % description)
		return
	_failures += 1
	printerr("FAIL: %s" % description)


## A check that is known to fail and left open by Sid's choice: run and
## reported every time, not failing the file. tracked says where the gap is
## written down (a roadmap item, a playtest issue).
func _check_known_open(condition: bool, description: String, tracked: String) -> void:
	_checks += 1
	if condition:
		print("KNOWN OPEN NOW PASSES (%s): %s; make it a _check again" % [tracked, description])
		return
	_known_open += 1
	print("KNOWN OPEN (%s): %s" % [tracked, description])


func _check_equal(actual: Variant, expected: Variant, description: String) -> void:
	_check(actual == expected, description if actual == expected
		else "%s (expected %s, got %s)" % [description, expected, actual])


func _check_near(actual: float, expected: float, description: String) -> void:
	var close := absf(actual - expected) <= _near_tolerance()
	_check(close, description if close
		else "%s (expected %.6f, got %.6f)" % [description, expected, actual])


## Says how the file went and ends the run: exit 0 if every check passed.
## name is what the checks are of ("weapon", "match"), as the summary says.
func _finish(name: String) -> void:
	if not Box3DQueries.set_faults.is_empty():
		_checks += 1
		_failures += 1
		printerr("FAIL: %d of %d rays in a tick met what the hitboxes do not bear out; the first: %s" % [
			Box3DQueries.set_faults.size(), Box3DQueries.set_rays_held, Box3DQueries.set_faults[0]])
	elif Box3DQueries.set_rays_held > 0:
		print("%d rays in a tick held to the hitboxes themselves, all borne out." % Box3DQueries.set_rays_held)
	if _failures == 0:
		print("%d %s checks passed%s." % [_checks, name, "" if _known_open == 0 else ", %d of them known open" % _known_open])
	else:
		printerr("%d of %d %s checks failed." % [_failures, _checks, name])
	print("TESTS %s %d %d" % [name, _checks, _failures])
	quit(0 if _failures == 0 else 1)


## Ends the run having checked nothing, because what the file checks is not
## there; why is said once, here and in the runner's summary.
func _skip(name: String, why: String) -> void:
	print(why)
	print("TESTS %s skipped %s" % [name, why])
	quit(0)
