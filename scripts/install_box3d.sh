#!/bin/sh
# Installs the pinned Box3D addon for Linux: CI and the cloud threads.
# install_box3d.ps1 does the same on Windows.
#
#   scripts/install_box3d.sh
#
# The upstream v0.4.3 zip's Linux libraries need glibc 2.43, newer than
# ubuntu-latest's 2.39, so Godot can't load them there. This takes the upstream
# zip for everything else and lays over it the same tag's Linux libraries
# rebuilt against glibc 2.35 (scripts/build_box3d_linux.sh), hosted on this
# repo's release box3d-v0.4.3-linux-glibc2.35. Both archives are checked
# against a pinned SHA-256 before anything is unpacked.
set -eu

VERSION=v0.4.3
UPSTREAM_URL="https://github.com/Stink-O/box3d-godot/releases/download/$VERSION/box3d-addon-$VERSION.zip"
UPSTREAM_SHA256=aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3
LINUX_URL="${BOX3D_LINUX_URL:-https://github.com/sidcarrollworks/CSGODOT/releases/download/box3d-$VERSION-linux-glibc2.35/box3d-linux-$VERSION-glibc2.35.zip}"
LINUX_SHA256=564efa7fcf8003ffdb98553d7840a3f1ccc49dd3b39d447d20ee3c93f9562a2b

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$PROJECT_DIR/project.godot" ] || { echo "No project.godot in $PROJECT_DIR." >&2; exit 1; }
DOWNLOADS="$PROJECT_DIR/.godot/box3d-download"
mkdir -p "$DOWNLOADS"

# fetch <url> <sha256> <file>: reuses a download whose checksum still matches.
fetch() {
	if [ -f "$3" ] && echo "$2  $3" | sha256sum -c --status; then
		return
	fi
	curl -fsSL --retry 3 -o "$3" "$1"
	if ! echo "$2  $3" | sha256sum -c --status; then
		rm -f "$3"
		echo "Box3D archive $(basename "$3") differs from the pinned checksum. Nothing was installed." >&2
		exit 1
	fi
}

fetch "$UPSTREAM_URL" "$UPSTREAM_SHA256" "$DOWNLOADS/addon.zip"
fetch "$LINUX_URL" "$LINUX_SHA256" "$DOWNLOADS/linux.zip"
unzip -q -o "$DOWNLOADS/addon.zip" -d "$PROJECT_DIR"
unzip -q -o "$DOWNLOADS/linux.zip" -d "$PROJECT_DIR"
echo "Installed Box3D $VERSION (Linux libraries built against glibc 2.35) in $PROJECT_DIR/addons/box3d."
