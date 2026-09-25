#!/usr/bin/env bash
#
# Shared by the other scripts here. Source it, do not run it.

## Prints the path to a Godot binary, or nothing if there is none. Honours
## GODOT, then PATH, then the places a downloaded Windows build tends to be left
## lying: it ships as a bare Godot_v4.x-stable_win64.exe with no installer, so
## it is rarely on PATH.
find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
		return
	fi
	local candidate
	for candidate in godot godot4 Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return
		fi
	done
	local found="" newest="" name
	for candidate in \
		"$HOME"/Desktop/Godot_v4*win64.exe \
		"$HOME"/Downloads/Godot_v4*win64.exe \
		"$HOME"/Downloads/Godot_v4*/Godot_v4*win64.exe; do
		# An unmatched glob stays literal, hence the -f.
		[[ -f "$candidate" ]] || continue
		# The newest version wins, wherever it is: an old download lying
		# around must not be what runs a 4.7 project.
		name="${candidate##*/}"
		if [[ -z "$newest" || "$(printf '%s\n%s\n' "$newest" "$name" | sort -V | tail -n 1)" == "$name" ]]; then
			newest="$name"
			found="$candidate"
		fi
	done
	echo "$found"
}

## Imports whatever is in assets/: import_assets <godot> <project dir>
##
## The texture settings go down first, so a fresh extraction is imported once,
## compressed, rather than once lossless and then again. Godot's own output is
## a progress bar per file, so it goes to a log and only trouble is shown.
import_assets() {
	local godot="$1" project="$2"
	local log="$project/.godot/import.log"
	mkdir -p "$project/.godot"

	echo "Importing into Godot. A fresh dust2 takes about a minute; after that, seconds."
	# Both of these put the extraction right before Godot sees it, and both
	# leave alone what they have already done.
	local prepare
	for prepare in prepare_export write_import_settings; do
		"$godot" --headless --path "$project" --script "res://scripts/$prepare.gd" 2>&1 \
			| grep -v '^Godot Engine' | grep -v '^[[:space:]]*$' || true
	done

	local started=$SECONDS
	rm -f "$log.first"
	if ! "$godot" --headless --path "$project" --import >"$log" 2>&1; then
		# Godot can finish an import and crash on its way out: on Sid's
		# machine it did the first time dust2's baked shadow pages were
		# imported (2026-09-25), and a second run found nothing left to do
		# and exited cleanly. So it runs once more, and only a second
		# failure is a real one.
		mv "$log" "$log.first"
		echo "Godot's import exited with an error; running it once more. The first run's log: $log.first" >&2
		if ! "$godot" --headless --path "$project" --import >"$log" 2>&1; then
			echo "Godot's import failed. The end of $log:" >&2
			tail -n 20 "$log" >&2
			return 1
		fi
	fi
	echo "Imported in $((SECONDS - started))s."
	cat "$log.first" "$log" 2>/dev/null | grep -aE '^(ERROR|WARNING):' | grep -v 'load-time scene is not defined' \
		| sort | uniq -c | head -n 10 || true
}
