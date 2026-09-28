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
# Each file gets CSGODOT_TEST_TIMEOUT seconds (180 by default; the slowest,
# dust2's bot check, took 69 s with the extracted assets on Sid's machine on
# 2026-09-28) and is then killed and counted as failed, so one stuck file
# cannot eat CI's whole job. It needs coreutils' timeout (Linux, Git Bash; common.sh's
# with_timeout); without it a file runs with no limit. The import runs under
# a limit too, with one retry (common.sh's run_import). The game's physics is
# the Box3D addon: when it cannot load, the run stops before the tests, saying
# how to install it, since a match's world does not tick without it.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/common.sh"

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
	echo "No Godot binary found. Run this with GODOT=/path/to/godot." >&2
	exit 1
fi
LIMIT="${CSGODOT_TEST_TIMEOUT:-180}"

# The import pass registers the class_name globals. Without it the test script
# cannot see MovementSolver and friends, and fails to parse.
if [[ -d "$PROJECT_DIR/assets" ]]; then
	# Extracted content has to be imported with its texture settings in place,
	# here as anywhere else. An import that fails twice stops the run, as
	# below: without it the tests cannot find their classes.
	if ! import_assets "$GODOT" "$PROJECT_DIR"; then
		exit 1
	fi
else
	# A fresh clone's first import can also fail on its way out the first
	# time it picks up a GDExtension (Box3D); run_import retries it once.
	# It has 300 s here (CI's job has 30 minutes for everything), where a
	# fresh dust2 on Sid's machine takes about a minute.
	if ! CSGODOT_IMPORT_TIMEOUT="${CSGODOT_IMPORT_TIMEOUT:-300}" run_import "$GODOT" "$PROJECT_DIR"; then
		exit 1
	fi
fi

if grep -q '^physics/backend="box3d"' "$PROJECT_DIR/project.godot"; then
	box3d_log="$(mktemp)"
	with_timeout 120 "$GODOT" --headless --path "$PROJECT_DIR" --script res://scripts/check_box3d.gd >"$box3d_log" 2>&1
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
	with_timeout "$LIMIT" "$GODOT" --headless --path "$PROJECT_DIR" --script "tests/$name" 2>&1 | tee "$log"
	status=${PIPESTATUS[0]}
	result="$(grep -a '^TESTS ' "$log" | tail -n 1)"
	read -r _ suite checks failures rest <<<"$result"
	known="$(grep -ac '^KNOWN OPEN (' "$log")"
	if [[ $status -eq 124 || $status -eq 137 ]] && [[ -z "$result" ]]; then
		summary+=("FAILED   $name timed out after ${LIMIT}s without reporting")
		failed_files=$((failed_files + 1))
	elif [[ $status -eq 124 || $status -eq 137 ]]; then
		if [[ "$checks" == "skipped" ]]; then
			summary+=("FAILED   $suite skipped, then did not exit within ${LIMIT}s")
		else
			summary+=("FAILED   $suite hung on exit after reporting $failures of $checks checks failed (killed after ${LIMIT}s)")
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
