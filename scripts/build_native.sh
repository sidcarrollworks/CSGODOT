#!/usr/bin/env bash
# Builds the game's native code (native/src: the movement's step) on
# Linux: CI, the cloud threads and anyone off Windows
# (scripts/build_native.ps1 there; this one also runs under Git Bash). It
# builds for what native/csgodot_native.gdextension lists, x86-64 Linux and
# Windows, which is where the native code has been held to the script's
# results; anywhere else it says so and builds nothing.
#
#   scripts/build_native.sh            the library the editor binary loads
#   scripts/build_native.sh release    and the one an exported game loads
#
# Without the library the game runs as it always did: the script runs the
# movement's step (PlayerBody), and the checks compare nothing. With it the
# native code runs the step, and every check file holds it to the script's
# result, bit for bit (tests/check_suite.gd).
#
# It needs git, Python 3 and a C++ compiler. godot-cpp is fetched at a
# pinned commit into the build directory (.godot/native-build, or where
# CSGODOT_NATIVE_BUILD points), and SCons goes into a virtual environment
# there when it is not on PATH. The first build compiles godot-cpp, a few
# minutes; later ones only what changed. Safe to run again.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
	echo "No project.godot in $PROJECT_DIR." >&2
	exit 1
fi
source "$PROJECT_DIR/scripts/common.sh"

# godot-cpp 10.0.0-stable: a tag can be moved, a commit cannot.
GODOT_CPP_COMMIT="507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
GODOT_CPP_URL="https://github.com/godotengine/godot-cpp.git"
SCONS_VERSION="4.8.1"
BUILD="${CSGODOT_NATIVE_BUILD:-$PROJECT_DIR/.godot/native-build}"

targets=(template_debug)
for wanted in "$@"; do
	case "$wanted" in
		release) targets+=(template_release) ;;
		debug) ;;
		*)
			echo "Unknown argument: $wanted (release, or nothing)" >&2
			exit 1
			;;
	esac
done

case "$(uname -s)" in
	Linux) platform="linux" ;;
	Darwin) platform="macos" ;;
	MINGW* | MSYS* | CYGWIN*) platform="windows" ;;
	*)
		echo "No build for $(uname -s) here." >&2
		exit 1
		;;
esac
case "$(uname -m)" in
	x86_64 | amd64) arch="x86_64" ;;
	arm64 | aarch64) arch="arm64" ;;
	*)
		echo "No build for $(uname -m) here." >&2
		exit 1
		;;
esac

# Only what is listed is built: a library Godot has no name for is a
# build's time spent and errors at every start after.
if ! grep -q "^$platform\.debug\.$arch *=" "$PROJECT_DIR/native/csgodot_native.gdextension"; then
	echo "The native code is not listed for $platform $arch (native/csgodot_native.gdextension), and the script runs the movement here." >&2
	echo "To try it: list its libraries there, build, and run scripts/run_tests.sh, which holds every step to the script's." >&2
	exit 1
fi

python="$(command -v python3 || command -v python || true)"
if [[ -z "$python" ]]; then
	echo "Python 3 is needed to build (SCons runs on it)." >&2
	exit 1
fi

godot_cpp="$BUILD/godot-cpp"
if [[ "$(git -C "$godot_cpp" rev-parse HEAD 2>/dev/null || true)" != "$GODOT_CPP_COMMIT" ]]; then
	echo "Fetching godot-cpp at $GODOT_CPP_COMMIT"
	rm -rf "$godot_cpp"
	mkdir -p "$godot_cpp"
	git -C "$godot_cpp" init -q
	git -C "$godot_cpp" remote add origin "$GODOT_CPP_URL"
	git -C "$godot_cpp" fetch -q --depth 1 origin "$GODOT_CPP_COMMIT"
	git -C "$godot_cpp" -c advice.detachedHead=false checkout -q FETCH_HEAD
fi

scons=()
if "$python" -m SCons --version >/dev/null 2>&1; then
	scons=("$python" -m SCons)
elif command -v scons >/dev/null 2>&1; then
	scons=(scons)
else
	venv="$BUILD/venv"
	venv_python="$venv/bin/python"
	[[ "$platform" == "windows" ]] && venv_python="$venv/Scripts/python.exe"
	# Made again when it no longer runs SCons: one kept from another Python
	# (CI's cache, across a new runner image) has a python and no SCons.
	if ! "$venv_python" -m SCons --version >/dev/null 2>&1; then
		rm -rf "$venv"
		"$python" -m venv "$venv"
		"$venv_python" -m pip install -q "scons==$SCONS_VERSION"
	fi
	scons=("$venv_python" -m SCons)
fi

jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
for target in "${targets[@]}"; do
	echo "Building the native code for $platform $arch, $target"
	(cd "$PROJECT_DIR/native" && "${scons[@]}" godot_cpp="$godot_cpp" platform="$platform" arch="$arch" target="$target" -j"$jobs")
done

# Godot finds the library by this file, which is put beside it only once
# there is a library: a listed extension with none is three errors at every
# start.
mkdir -p "$PROJECT_DIR/addons/csgodot_native"
cp "$PROJECT_DIR/native/csgodot_native.gdextension" "$PROJECT_DIR/addons/csgodot_native/csgodot_native.gdextension"

godot="$(find_godot)"
if [[ -n "$godot" ]]; then
	# The import pass lists the extension for the game to load.
	if [[ -d "$PROJECT_DIR/assets" ]]; then
		import_assets "$godot" "$PROJECT_DIR"
	else
		run_import "$godot" "$PROJECT_DIR"
	fi
	# Built is not loaded: Godot is asked.
	if ! "$godot" --headless --path "$PROJECT_DIR" --script scripts/native_loaded.gd; then
		echo "Built, but Godot does not load it: see what it says above." >&2
		exit 1
	fi
	echo "Built, and Godot loads it. Restart Godot if this project is open."
else
	echo "Built. No Godot binary was found to list it with: open the project in the editor once, or run scripts/run_tests.sh."
fi
