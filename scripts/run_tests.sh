#!/usr/bin/env bash
# Runs the headless test suite. Needs a Godot 4.7 binary: on PATH as `godot`,
# left on the desktop, or wherever GODOT points.
#
#   scripts/run_tests.sh              every test file
#   scripts/run_tests.sh sim match    only the files whose names contain these
#
# Every file in tests/ named run_*.gd is a test file (tests/check_suite.gd
# says how one reports), so a new one is picked up without touching this.
# Every file runs even when one before it fails, and the summary at the end
# says how each went. It exits 1 if any file failed or ended without saying
# how it went (a script error or a crash), which is what CI goes by.
#
# Each file has CSGODOT_TEST_TIMEOUT seconds (600 by default; CI sets less)
# where the `timeout` command exists, so one that hangs fails instead of
# holding up the rest. The game's physics is the Box3D addon: when it cannot
# load, the run stops before the tests, saying how to install it, since a
# match's world does not tick without it.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/common.sh"

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
	echo "No Godot binary found. Run this with GODOT=/path/to/godot." >&2
	exit 1
fi
LIMIT="${CSGODOT_TEST_TIMEOUT:-600}"

## Runs a command for at most $1 seconds where coreutils' timeout exists
## (Linux, Git Bash), killing it 10 s after asking it to stop.
limited() {
	local seconds="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout -k 10 "$seconds" "$@"
	else
		"$@"
	fi
}

# The import pass registers the class_name globals. Without it the test script
# cannot see MovementSolver and friends, and fails to parse.
if [[ -d "$PROJECT_DIR/assets" ]]; then
	# Extracted content has to be imported with its texture settings in place,
	# here as anywhere else.
	import_assets "$GODOT" "$PROJECT_DIR"
else
	# Godot can finish an import and fail on its way out the first time it
	# picks up a GDExtension, as a fresh clone does with Box3D; a second run
	# finds nothing left to do. So a failed import runs once more, and the
	# log is kept rather than thrown away.
	mkdir -p "$PROJECT_DIR/.godot"
	import_log="$PROJECT_DIR/.godot/import.log"
	if ! limited 300 "$GODOT" --headless --path "$PROJECT_DIR" --import >"$import_log" 2>&1 \
		&& ! limited 300 "$GODOT" --headless --path "$PROJECT_DIR" --import >"$import_log" 2>&1; then
		echo "Godot's import failed twice; the tests may not find their classes. The end of $import_log:" >&2
		tail -n 20 "$import_log" >&2
	fi
fi

if grep -q '^physics/backend="box3d"' "$PROJECT_DIR/project.godot"; then
	box3d_log="$(mktemp)"
	limited 120 "$GODOT" --headless --path "$PROJECT_DIR" --script res://scripts/check_box3d.gd >"$box3d_log" 2>&1
	box3d_status=$?
	grep -av '^Godot Engine' "$box3d_log" | grep -av '^[[:space:]]*$'
	rm -f "$box3d_log"
	if [[ $box3d_status -ne 0 ]]; then
		echo "The game's physics, Box3D, did not load, so no test can run a match. See above." >&2
		exit 1
	fi
fi

files=()
for path in "$PROJECT_DIR"/tests/run_*.gd; do
	name="$(basename "$path")"
	if [[ $# -eq 0 ]]; then
		files+=("$name")
		continue
	fi
	for wanted in "$@"; do
		if [[ "$name" == *"$wanted"* ]]; then
			files+=("$name")
			break
		fi
	done
done
if [[ ${#files[@]} -eq 0 ]]; then
	echo "No test file in tests/ matches: $*" >&2
	exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
summary=()
total=0
failed_files=0
for name in "${files[@]}"; do
	echo "=== tests/$name"
	limited "$LIMIT" "$GODOT" --headless --path "$PROJECT_DIR" --script "tests/$name" 2>&1 | tee "$log"
	status=${PIPESTATUS[0]}
	result="$(grep -a '^TESTS ' "$log" | tail -n 1)"
	read -r _ suite checks failures rest <<<"$result"
	known="$(grep -ac '^KNOWN OPEN (' "$log")"
	if [[ $status -eq 124 || $status -eq 137 ]]; then
		if [[ -z "$result" ]]; then
			summary+=("FAILED   $name timed out after ${LIMIT}s without reporting")
		else
			summary+=("FAILED   $suite: reported $checks checks, then did not exit within ${LIMIT}s")
		fi
		failed_files=$((failed_files + 1))
	elif [[ -z "$result" ]]; then
		summary+=("FAILED   $name ended without reporting (exit $status): a script error or a crash, see above")
		failed_files=$((failed_files + 1))
	elif [[ "$checks" == "skipped" ]]; then
		summary+=("skipped  $suite: $failures $rest")
	elif [[ "$failures" != "0" || $status -ne 0 ]]; then
		summary+=("FAILED   $suite: $failures of $checks checks failed")
		failed_files=$((failed_files + 1))
		total=$((total + checks))
	else
		summary+=("ok       $suite: $checks checks$([[ $known -gt 0 ]] && echo ", $known known open")")
		total=$((total + checks))
	fi
done

echo
echo "=== Summary"
for line in "${summary[@]}"; do
	echo "$line"
done
if [[ $failed_files -eq 0 ]]; then
	echo "$total checks in ${#files[@]} files, all passed."
	exit 0
fi
echo "$failed_files of ${#files[@]} files failed."
exit 1
