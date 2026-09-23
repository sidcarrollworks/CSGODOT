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

var _checks: int = 0
var _failures: int = 0


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
	if _failures == 0:
		print("%d %s checks passed." % [_checks, name])
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
