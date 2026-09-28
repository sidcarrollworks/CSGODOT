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
# So on a Linux whose glibc is older:
#
# - First, the same tag's Linux libraries rebuilt against Ubuntu 22.04's
#   glibc 2.35 (scripts/build_box3d_linux.sh), from this repo's release
#   box3d-v0.4.3-linux-glibc2.35, checked against their own pinned SHA-256.
#   They need no compiler and no minutes of building.
# - Where that release cannot be fetched (until it exists, or offline), the
#   library the tests load (the debug one, which the Godot editor binary
#   picks) is built from the release's source, pinned by commit, with
#   godot-cpp at the commit that source records. That takes a few minutes
#   once, is kept under .godot/box3d-build/out, which CI caches, and needs
#   git, a C and C++ compiler and Python 3; SCons goes into a virtual
#   environment there when it is not on PATH.
#
# A download that does not match its pinned checksum stops the install with
# nothing unpacked from it. Safe to run again.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="v0.4.3"
ARCHIVE_SHA256="aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3"
ARCHIVE_URL="https://github.com/Stink-O/box3d-godot/releases/download/$VERSION/box3d-addon-$VERSION.zip"
# The tag's Linux libraries rebuilt against glibc 2.35; the newest symbol
# they ask for is GLIBC_2.34. BOX3D_LINUX_URL points elsewhere (a file:// copy).
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

## A shallow checkout of one commit of a repository, into an empty directory.
fetch_commit() {
	local url="$1" commit="$2" into="$3"
	mkdir -p "$into"
	git -C "$into" init -q
	git -C "$into" remote add origin "$url"
	git -C "$into" fetch -q --depth 1 origin "$commit"
	git -C "$into" checkout -q FETCH_HEAD
}

## Installs the libraries rebuilt against glibc 2.35 if they can be fetched;
## fails, so the source build runs, if they cannot. A download that differs
## from their pinned checksum stops the install.
install_prebuilt() {
	local zip="$download/linux.zip"
	if [[ ! -f "$zip" || "$(sha256_of "$zip")" != "$LINUX_SHA256" ]]; then
		rm -f "$zip"
		if ! curl -fsSL --retry 3 -o "$zip" "$LINUX_URL" 2>/dev/null; then
			rm -f "$zip"
			return 1
		fi
	fi
	if [[ "$(sha256_of "$zip")" != "$LINUX_SHA256" ]]; then
		rm -f "$zip"
		echo "The Linux libraries at $LINUX_URL differ from their pinned checksum. Nothing was installed from them." >&2
		exit 1
	fi
	unpack "$zip"
}

download="$PROJECT_DIR/.godot/box3d-download"
archive="$download/addon.zip"
mkdir -p "$download"
if [[ ! -f "$archive" || "$(sha256_of "$archive")" != "$ARCHIVE_SHA256" ]]; then
	echo "Downloading box3d-godot $VERSION"
	curl -fsSL --retry 3 -o "$archive" "$ARCHIVE_URL"
fi
if [[ "$(sha256_of "$archive")" != "$ARCHIVE_SHA256" ]]; then
	echo "The Box3D archive's checksum differs from the pinned release. Nothing was installed." >&2
	exit 1
fi
unpack "$archive"
echo "Installed Box3D $VERSION in addons/box3d."

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
	exit 0
fi
glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
if [[ -n "$glibc" ]] && at_least "$glibc" "$RELEASE_GLIBC"; then
	echo "glibc $glibc runs the release's Linux library as it is."
	exit 0
fi

if [[ -n "$glibc" ]] && at_least "$glibc" "$LINUX_GLIBC"; then
	if install_prebuilt; then
		echo "Installed the Linux libraries rebuilt against glibc 2.35, for glibc $glibc."
		exit 0
	fi
	why="the libraries rebuilt against glibc 2.35 could not be fetched from $LINUX_URL"
else
	why="the libraries rebuilt against glibc 2.35 need at least $LINUX_GLIBC"
fi

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
