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
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/common.sh"

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
	echo "No Godot binary found. Run this with GODOT=/path/to/godot." >&2
	exit 1
fi

# The import pass registers the class_name globals. Without it the test script
# cannot see MovementSolver and friends, and fails to parse.
if [[ -d "$PROJECT_DIR/assets" ]]; then
	# Extracted content has to be imported with its texture settings in place,
	# here as anywhere else.
	import_assets "$GODOT" "$PROJECT_DIR"
else
	"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null
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
	"$GODOT" --headless --path "$PROJECT_DIR" --script "tests/$name" 2>&1 | tee "$log"
	status=${PIPESTATUS[0]}
	result="$(grep -a '^TESTS ' "$log" | tail -n 1)"
	read -r _ suite checks failures rest <<<"$result"
	if [[ -z "$result" ]]; then
		summary+=("FAILED   $name ended without reporting (exit $status): a script error or a crash, see above")
		failed_files=$((failed_files + 1))
	elif [[ "$checks" == "skipped" ]]; then
		summary+=("skipped  $suite: $failures $rest")
	elif [[ "$failures" != "0" || $status -ne 0 ]]; then
		summary+=("FAILED   $suite: $failures of $checks checks failed")
		failed_files=$((failed_files + 1))
		total=$((total + checks))
	else
		summary+=("ok       $suite: $checks checks")
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
