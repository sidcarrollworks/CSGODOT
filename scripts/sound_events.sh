#!/usr/bin/env bash
# Regenerates reference/sounds/sound_events.json, sound_events.md and
# default_bus_layout.tres from CS2's own sound event, sound stack and mixer
# files, as SteamDatabase's GameTracking-CS2 publishes them in text. Needs
# no copy of CS2 and no extracted assets, so a cloud thread can run it.
#
#   scripts/sound_events.sh                  the newest GameTracking-CS2 commit
#   scripts/sound_events.sh <commit>         a given one
#   GAMETRACKING=<checkout> scripts/sound_events.sh    a checkout you already have
#
# Fetches only the files it reads (a sparse, shallow clone of a few MB) into
# .gametracking-cs2/ (gitignored), then runs scripts/sound_event_tables.gd,
# which says what it keeps. Which event files are read is EVENT_FILES there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"
GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
	echo "No Godot binary found. Run this with GODOT=/path/to/godot." >&2
	exit 1
fi

DEST="${GAMETRACKING:-$ROOT/.gametracking-cs2}"
if [[ -z "${GAMETRACKING:-}" ]]; then
	WANTED="${1:-HEAD}"
	if [[ ! -d "$DEST/.git" ]]; then
		git init -q "$DEST"
		git -C "$DEST" remote add origin https://github.com/SteamDatabase/GameTracking-CS2.git
		git -C "$DEST" config core.sparseCheckout true
	fi
	printf '%s\n' \
		'/game/csgo/steam.inf' \
		'/game/csgo/pak01_dir/soundevents/' \
		'/game/csgo/pak01_dir/soundstacks/' \
		'/game/csgo/pak01_dir/scripts/soundmixers.txt' > "$DEST/.git/info/sparse-checkout"
	git -C "$DEST" fetch -q --depth 1 --filter=blob:none origin "$WANTED"
	git -C "$DEST" checkout -q FETCH_HEAD
	# Keep Godot's editor and --import from scanning it.
	touch "$DEST/.gdignore"
fi
COMMIT="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || echo "")"

# The generator uses KV3 (src/audio/kv3.gd), a class_name global.
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --script scripts/sound_event_tables.gd -- "$DEST" "$COMMIT"
