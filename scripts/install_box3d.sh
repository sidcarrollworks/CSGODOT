#!/usr/bin/env bash
# Installs the pinned Box3D addon, the game's physics, on Linux and macOS: CI,
# the cloud threads and anyone off Windows (scripts/install_box3d.ps1 there).
#
#   scripts/install_box3d.sh
#
# It downloads box3d-godot's v0.4.3 release, checks its pinned SHA-256 and
# unpacks addons/box3d/. The release's Linux library needs glibc 2.43, newer
# than Ubuntu 24.04's 2.39 (GitHub's ubuntu-latest), and cannot load on an
# older one: Godot then runs without Box3D, and a match's world never ticks.
# So on a Linux whose glibc is older, the library the tests load (the debug
# one, which the Godot editor binary picks) is built from the same release's
# source, pinned by commit, with godot-cpp at the commit that source records,
# and put in place of the release's. The build takes a few minutes once and
# is kept under .godot/box3d-build/out, which CI caches. It needs git, a C and
# C++ compiler and Python 3; SCons is installed into a virtual environment
# there when it is not on PATH. Safe to run again.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="v0.4.3"
ARCHIVE_SHA256="aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3"
ARCHIVE_URL="https://github.com/Stink-O/box3d-godot/releases/download/$VERSION/box3d-addon-$VERSION.zip"
# The commit the v0.4.3 tag names: a tag can be moved, a commit cannot.
SOURCE_COMMIT="3ce52ff999f2509a89ec53538ff77c3cf35092fa"
SOURCE_URL="https://github.com/Stink-O/box3d-godot.git"
GODOT_CPP_URL="https://github.com/godotengine/godot-cpp.git"
# The newest glibc the release's Linux library asks for (libm's GLIBC_2.43,
# read from its .gnu.version_r on 2026-09-28).
RELEASE_GLIBC="2.43"
LIBRARY="libbox3d_godot.linux.template_debug.x86_64.so"

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

## A shallow checkout of one commit of a repository, into an empty directory.
fetch_commit() {
	local url="$1" commit="$2" into="$3"
	mkdir -p "$into"
	git -C "$into" init -q
	git -C "$into" remote add origin "$url"
	git -C "$into" fetch -q --depth 1 origin "$commit"
	git -C "$into" checkout -q FETCH_HEAD
}

download="$PROJECT_DIR/.godot/box3d-download"
archive="$download/addon.zip"
mkdir -p "$download"
if [[ ! -f "$archive" || "$(sha256_of "$archive")" != "$ARCHIVE_SHA256" ]]; then
	echo "Downloading box3d-godot $VERSION"
	curl -fsSL -o "$archive" "$ARCHIVE_URL"
fi
if [[ "$(sha256_of "$archive")" != "$ARCHIVE_SHA256" ]]; then
	echo "The Box3D archive's checksum differs from the pinned release. Nothing was installed." >&2
	exit 1
fi
if command -v unzip >/dev/null 2>&1; then
	unzip -oq "$archive" -d "$PROJECT_DIR"
else
	python3 -m zipfile -e "$archive" "$PROJECT_DIR"
fi
echo "Installed Box3D $VERSION in addons/box3d."

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
	exit 0
fi
glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
if [[ -n "$glibc" && "$(printf '%s\n%s\n' "$RELEASE_GLIBC" "$glibc" | sort -V | head -n 1)" == "$RELEASE_GLIBC" ]]; then
	echo "glibc $glibc runs the release's Linux library as it is."
	exit 0
fi

build="$PROJECT_DIR/.godot/box3d-build"
built="$build/out/$SOURCE_COMMIT/$LIBRARY"
if [[ ! -f "$built" ]]; then
	echo "glibc ${glibc:-unknown} is older than the $RELEASE_GLIBC the release's Linux library needs:"
	echo "building $LIBRARY from $SOURCE_COMMIT (a few minutes, once)."
	source_dir="$build/src"
	rm -rf "$source_dir"
	fetch_commit "$SOURCE_URL" "$SOURCE_COMMIT" "$source_dir"
	fetch_commit "$GODOT_CPP_URL" "$(git -C "$source_dir" rev-parse HEAD:godot/godot-cpp)" "$source_dir/godot/godot-cpp"
	scons="$(command -v scons || true)"
	if [[ -z "$scons" ]]; then
		if [[ ! -x "$build/venv/bin/scons" ]]; then
			python3 -m venv "$build/venv"
			"$build/venv/bin/pip" install -q scons
		fi
		scons="$build/venv/bin/scons"
	fi
	jobs="$(nproc 2>/dev/null || echo 2)"
	(cd "$source_dir/godot" && "$scons" platform=linux arch=x86_64 target=template_debug -j"$jobs")
	mkdir -p "$(dirname "$built")"
	cp "$source_dir/godot/demo/addons/box3d/bin/$LIBRARY" "$built"
	rm -rf "$source_dir"
fi
mkdir -p "$PROJECT_DIR/addons/box3d/bin"
cp "$built" "$PROJECT_DIR/addons/box3d/bin/$LIBRARY"
echo "Installed $LIBRARY built from $SOURCE_COMMIT for glibc ${glibc:-unknown}."
