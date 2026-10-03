#!/usr/bin/env python3
"""Build pinned Box3D + the opt-in projectile cast, via install_box3d.ps1/sh.

Requires Git, Python 3 and a C/C++ toolchain (VS Build Tools on Windows).
Builds debug and release; source/compilation caches live in ignored .godot/.
"""
import argparse
import hashlib
import os
from pathlib import Path
import platform
from pathlib import PurePosixPath
import shutil
import subprocess
import sys
import urllib.request
import zipfile

SOURCE_COMMIT = "3ce52ff999f2509a89ec53538ff77c3cf35092fa"
CPP_COMMIT = "ba0edfed90512ec64aba51d4295a3e7e30112f86"
ARCHIVE_SHA = "aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3"
ARCHIVE_URL = "https://github.com/Stink-O/box3d-godot/releases/download/v0.4.3/box3d-addon-v0.4.3.zip"
SCONS_VERSION = "4.8.1"


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def linked(path):
    return path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()) or (
        os.name == "nt" and path.exists() and path.lstat().st_file_attributes & 0x400
    )


def prepare_output(project):
    # Detach a worktree's linked bin entry only, preserving the shared target.
    for path in (project / "addons", project / "addons/box3d"):
        if linked(path):
            raise RuntimeError(f"Refusing to install through linked addon directory: {path}")
    output = project / "addons/box3d/bin"
    if linked(output):
        if output.is_symlink():
            output.unlink()
        else:
            os.rmdir(output)  # Windows junction entry only, never recursive.
    output.mkdir(parents=True, exist_ok=True)
    return output


def install_resources(project, archive):
    # Check every destination before writing, including links below box3d.
    # A checksum pins the zip, but an existing worktree may share directories.
    with zipfile.ZipFile(archive) as package:
        resources = []
        for member in package.infolist():
            parts = PurePosixPath(member.filename).parts
            if parts[:2] != ("addons", "box3d") or ".." in parts or "\\" in member.filename:
                raise RuntimeError(f"Unexpected archive member: {member.filename}")
            if parts[:3] == ("addons", "box3d", "bin"):
                continue
            destination = project
            for part in parts:
                destination /= part
                if linked(destination):
                    raise RuntimeError(f"Refusing to install through linked resource: {destination}")
            resources.append(member)
        for member in resources:
            package.extract(member, project)


def host_target(system, machine):
    host = {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}.get(system)
    arch = "arm64" if machine.lower() in ("arm64", "aarch64") else "x86_64" if machine.lower() in ("x86_64", "amd64") else None
    if host is None or arch is None or (host != "macos" and arch != "x86_64"):
        raise RuntimeError(f"Unsupported Box3D host: {system}/{machine}")
    return host, arch


def checkout(url, commit, path):
    if not path.exists():
        path.mkdir(parents=True)
        run("git", "init", "-q", str(path))
        run("git", "-C", str(path), "remote", "add", "origin", url)
        run("git", "-C", str(path), "fetch", "-q", "--depth", "1", "origin", commit)
        run("git", "-C", str(path), "-c", "core.autocrlf=false", "checkout", "-q", "FETCH_HEAD")
    head = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    if head != commit:
        raise RuntimeError(f"Unexpected checkout {head} in {path}; use a fresh build directory")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--build-directory", type=Path)
    parser.add_argument("--jobs", type=int, default=min(8, max(1, (os.cpu_count() or 2) - 2)))
    args = parser.parse_args()
    project = args.project.resolve()
    if not (project / "project.godot").is_file():
        raise RuntimeError("--project must contain project.godot")
    patch = project / "scripts/box3d-projectiles.patch"
    digest = hashlib.sha256(patch.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    host, arch = host_target(platform.system(), platform.machine())
    build = (args.build_directory or project / ".godot/box3d-build" / digest[:16]).resolve()
    build.mkdir(parents=True, exist_ok=True)
    source = build / "source"
    checkout("https://github.com/Stink-O/box3d-godot.git", SOURCE_COMMIT, source)
    checkout("https://github.com/godotengine/godot-cpp.git", CPP_COMMIT, source / "godot/godot-cpp")
    normalized = build / "projectiles.patch"
    normalized.write_bytes(patch.read_bytes().replace(b"\r\n", b"\n"))
    reverse = subprocess.run(["git", "apply", "--reverse", "--check", str(normalized)], cwd=source, capture_output=True)
    if reverse.returncode:
        run("git", "apply", "--check", str(normalized), cwd=source)
        run("git", "apply", str(normalized), cwd=source)
    # Refuse unaccounted source edits rather than build an unpinned binary.
    actual = subprocess.check_output(["git", "-c", "core.autocrlf=false", "diff", "--no-ext-diff"], cwd=source)
    if actual.replace(b"\r\n", b"\n") != normalized.read_bytes():
        raise RuntimeError(f"Build checkout has changes beyond the pinned patch: {source}")
    venv = build / "venv"
    python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not python.exists():
        run(sys.executable, "-m", "venv", str(venv))
    version = subprocess.run([str(python), "-c", f"import SCons; assert SCons.__version__ == '{SCONS_VERSION}'"], capture_output=True)
    if version.returncode:
        run(str(python), "-m", "pip", "install", f"scons=={SCONS_VERSION}")
    for target in ("template_debug", "template_release"):
        run(str(python), "-m", "SCons", f"platform={host}", f"arch={arch}", f"target={target}", f"-j{max(1, args.jobs)}", cwd=source / "godot")
    # Archive supplies icons/resources, never the unpatched binaries.
    download = project / ".godot/box3d-download"
    download.mkdir(parents=True, exist_ok=True)
    archive = download / "addon.zip"
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA:
        urllib.request.urlretrieve(ARCHIVE_URL, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA:
        raise RuntimeError("Box3D archive checksum differs from the pinned release")
    output = prepare_output(project)
    install_resources(project, archive)
    suffix = ".dll" if host == "windows" else ".so" if host == "linux" else ".framework"
    for target in ("template_debug", "template_release"):
        name = f"libbox3d_godot.{host}.{target}" + ("" if host == "macos" else f".{arch}") + suffix
        library = source / "godot/demo/addons/box3d/bin" / name
        if linked(output / name):
            raise RuntimeError(f"Refusing to overwrite linked library: {output / name}")
        if library.is_dir():
            shutil.copytree(library, output / name, dirs_exist_ok=True)
        else:
            shutil.copy2(library, output / name)
    if host == "macos":
        descriptor = project / "addons/box3d/box3d.gdextension"
        descriptor.write_text(descriptor.read_text().replace('; macos.', 'macos.'), encoding="utf-8")
    print(f"Installed Box3D v0.4.3 + projectile patch {digest[:16]} ({host}/{arch}, debug + release). Restart Godot.")


if __name__ == "__main__":
    main()
