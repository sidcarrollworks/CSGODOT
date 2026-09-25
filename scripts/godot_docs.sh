#!/usr/bin/env bash
# Fetch the Godot docs this project's reference/godot/ pages were written
# from, as searchable text (no images), into .godot-docs/ (gitignored).
#
#   scripts/godot_docs.sh            fetch once, or report where they are
#   scripts/godot_docs.sh update     refetch at the pinned commit
#
# Then search them, for example:
#   rg -n "cast_motion" .godot-docs/classes/class_physicsdirectspacestate3d.rst
#   rg -l "physics_interpolation" .godot-docs/tutorials
#
# The class reference is classes/class_<lowercase name>.rst; the manual is
# tutorials/; engine internals are engine_details/. Keep BRANCH and COMMIT
# the same as the source line in reference/godot/README.md, and move both
# together when project.godot moves to a new Godot version.
set -euo pipefail

BRANCH=4.7
COMMIT=9adca4c1c72917bfe1b7be3108abed5ce26696a6
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.godot-docs"

if [[ -d "$DEST/.git" && "${1:-}" != "update" ]]; then
	echo "Godot docs ($BRANCH @${COMMIT:0:7}) are in $DEST"
	exit 0
fi

rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin https://github.com/godotengine/godot-docs.git
git -C "$DEST" config core.sparseCheckout true
printf '%s\n' '/*' '!*.png' '!*.jpg' '!*.jpeg' '!*.gif' '!*.webp' '!*.svg' \
	'!*.mp4' '!*.webm' '!*.ogv' '!*.zip' > "$DEST/.git/info/sparse-checkout"
git -C "$DEST" fetch -q --depth 1 --filter=blob:none origin "$COMMIT"
git -C "$DEST" checkout -q FETCH_HEAD
# Keep Godot's editor and --import from scanning the docs.
touch "$DEST/.gdignore"
echo "Godot docs ($BRANCH @${COMMIT:0:7}) fetched into $DEST"
