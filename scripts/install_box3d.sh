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
# So on a Linux whose glibc is older than 2.43:
#
# - With glibc 2.34 or newer, the same tag's Linux libraries rebuilt against
#   Ubuntu 22.04's glibc 2.35 (debug and release), from this repo's release
#   box3d-v0.4.3-linux-glibc2.35, checked against their own pinned SHA-256.
#   They need no compiler and no minutes of building.
# - Where that release cannot be fetched (until it exists, or offline), or
#   glibc is older than 2.34, the library the tests load (the debug one,
#   which the Godot editor binary picks) is built from the release's source,
#   pinned by commit, with godot-cpp at the commit that source records. That
#   takes a few minutes once, is kept under .godot/box3d-build/out, which CI
#   caches, and needs git, a C and C++ compiler and Python 3; SCons goes into
#   a virtual environment there when it is not on PATH.
#
# Every download is checked before anything is unpacked, and one that does
# not match its pinned checksum stops the install with nothing changed.
# Safe to run again.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
	echo "No project.godot in $PROJECT_DIR." >&2
	exit 1
fi
VERSION="v0.4.3"
ARCHIVE_SHA256="aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3"
ARCHIVE_URL="https://github.com/Stink-O/box3d-godot/releases/download/$VERSION/box3d-addon-$VERSION.zip"
# The tag's Linux libraries rebuilt against glibc 2.35; the newest symbol
# they ask for is GLIBC_2.34. BOX3D_LINUX_URL points elsewhere (a file:// copy).
# Attaching a different zip to the release means changing LINUX_SHA256 here,
# which also renews CI's cache key.
LINUX_URL="${BOX3D_LINUX_URL:-https://github.com/sidcarrollworks/CSGODOT/releases/download/box3d-$VERSION-linux-glibc2.35/box3d-linux-$VERSION-glibc2.35.zip}"
LINUX_SHA256="564efa7fcf8003ffdb98553d7840a3f1ccc49dd3b39d447d20ee3c93f9562a2b"
LINUX_GLIBC="2.34"
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

## Whether version $1 is at least $2.
at_least() {
	[[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

unpack() {
	if command -v unzip >/dev/null 2>&1; then
		unzip -oq "$1" -d "$PROJECT_DIR"
	else
		python3 -m zipfile -e "$1" "$PROJECT_DIR"
	fi
}

## Whether zip $1 holds member $2. The listing is read to its end (no grep
## -q), so its writer is never cut off, which pipefail would take as failure.
zip_has() {
	if command -v unzip >/dev/null 2>&1; then
		unzip -Z1 "$1" | grep -xF "$2" >/dev/null
	else
		python3 -c 'import sys, zipfile; sys.exit(sys.argv[2] not in zipfile.ZipFile(sys.argv[1]).namelist())' "$1" "$2"
	fi
}

## Downloads url $1 to file $3 unless a copy there already has checksum $2.
## Fails when it cannot be downloaded; stops the install, deleting it, when
## what came down has another checksum.
fetch_pinned() {
	local url="$1" sha="$2" file="$3"
	if [[ -f "$file" && "$(sha256_of "$file")" == "$sha" ]]; then
		return 0
	fi
	rm -f "$file"
	if ! curl -fsSL --retry 3 -o "$file" "$url" 2>/dev/null; then
		rm -f "$file"
		return 1
	fi
	if [[ "$(sha256_of "$file")" != "$sha" ]]; then
		rm -f "$file"
		echo "$url differs from its pinned checksum. Nothing was installed." >&2
		exit 1
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
linux_zip="$download/linux.zip"
mkdir -p "$download"
if [[ ! -f "$archive" || "$(sha256_of "$archive")" != "$ARCHIVE_SHA256" ]]; then
	echo "Downloading box3d-godot $VERSION"
fi
if ! fetch_pinned "$ARCHIVE_URL" "$ARCHIVE_SHA256" "$archive"; then
	echo "Could not download $ARCHIVE_URL. Nothing was installed." >&2
	exit 1
fi

# Which Linux library to use, decided (and its download checked) before
# anything is unpacked: the release's, the rebuilt one, or a source build.
plan="release"
glibc=""
if [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]; then
	glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
	if [[ -n "$glibc" ]] && at_least "$glibc" "$RELEASE_GLIBC"; then
		plan="release"
	elif [[ -n "$glibc" ]] && at_least "$glibc" "$LINUX_GLIBC"; then
		if fetch_pinned "$LINUX_URL" "$LINUX_SHA256" "$linux_zip"; then
			if ! zip_has "$linux_zip" "addons/box3d/bin/$LIBRARY"; then
				echo "$LINUX_URL has no addons/box3d/bin/$LIBRARY in it. Nothing was installed." >&2
				exit 1
			fi
			plan="rebuilt"
		else
			plan="build"
			why="the libraries rebuilt against glibc 2.35 could not be fetched from $LINUX_URL"
		fi
	else
		plan="build"
		why="the libraries rebuilt against glibc 2.35 need at least $LINUX_GLIBC"
	fi
fi

unpack "$archive"
echo "Installed Box3D $VERSION in addons/box3d."
case "$plan" in
	release)
		if [[ -n "$glibc" ]]; then
			echo "glibc $glibc runs the release's Linux library as it is."
		fi
		exit 0
		;;
	rebuilt)
		unpack "$linux_zip"
		echo "Installed the Linux libraries rebuilt against glibc 2.35, for glibc $glibc."
		exit 0
		;;
esac

build="$PROJECT_DIR/.godot/box3d-build"
built="$build/out/$SOURCE_COMMIT/$LIBRARY"
if [[ ! -f "$built" ]]; then
	echo "glibc ${glibc:-unknown} is older than the $RELEASE_GLIBC the release's Linux library needs, and"
	echo "$why:"
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
