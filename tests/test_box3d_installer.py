"""Offline installer tests using local Git repositories; no downloads or compiler."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("installer", Path(__file__).parents[1] / "scripts/build_box3d_projectiles.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / "project"
        (self.project / "addons/box3d").mkdir(parents=True)
        self.shared = self.root / "shared"
        self.shared.mkdir()
        (self.shared / "keep.txt").write_text("shared")

    def tearDown(self):
        self.temporary.cleanup()

    def link(self, destination):
        if os.name == "nt":
            subprocess.run(["cmd", "/c", "mklink", "/J", str(destination), str(self.shared)], check=True, capture_output=True)
        else:
            destination.symlink_to(self.shared, target_is_directory=True)

    def archive(self, entries):
        path = self.root / "addon.zip"
        with zipfile.ZipFile(path, "w") as package:
            for name, data in entries:
                package.writestr(name, data)
        return path

    def git(self, path, *args):
        return subprocess.check_output(["git", "-C", str(path), *args], text=True, stderr=subprocess.PIPE).strip()

    def repository(self, path, contents):
        path.mkdir(parents=True)
        self.git(path, "init", "-q")
        (path / "source.txt").write_text(contents, encoding="utf-8")
        self.git(path, "add", "source.txt")
        self.git(path, "-c", "user.name=Installer Test", "-c", "user.email=installer@example.invalid", "commit", "-qm", "Fixture")
        return self.git(path, "rev-parse", "HEAD")

    def test_checks_out_missing_directory(self):
        remote = self.root / "remote"
        commit = self.repository(remote, "dependency")
        destination = self.root / "build/source"
        installer.checkout(str(remote), commit, destination)
        self.assertEqual(self.git(destination, "rev-parse", "HEAD"), commit)
        self.assertEqual((destination / "source.txt").read_text(), "dependency")

    def test_initializes_empty_submodule_directory_inside_parent_repository(self):
        remote = self.root / "remote"
        commit = self.repository(remote, "dependency")
        parent = self.root / "box3d"
        parent_commit = self.repository(parent, "parent")
        destination = parent / "godot/godot-cpp"
        destination.mkdir(parents=True)
        # Git searches ancestors until this empty submodule has its own repo.
        self.assertEqual(self.git(destination, "rev-parse", "HEAD"), parent_commit)
        installer.checkout(str(remote), commit, destination)
        self.assertEqual(self.git(destination, "rev-parse", "HEAD"), commit)
        self.assertEqual(Path(self.git(destination, "rev-parse", "--show-toplevel")).resolve(), destination.resolve())
        self.assertEqual(self.git(parent, "rev-parse", "HEAD"), parent_commit)

    def test_reuses_pinned_checkout_without_discarding_patch(self):
        destination = self.root / "source"
        commit = self.repository(destination, "original")
        (destination / "source.txt").write_text("patched", encoding="utf-8")
        # No fetch is needed to reuse an existing checkout at the pinned commit.
        installer.checkout(str(self.root / "unavailable-remote"), commit, destination)
        self.assertEqual((destination / "source.txt").read_text(), "patched")

    def test_refuses_wrong_checkout_without_modifying_it(self):
        remote = self.root / "remote"
        commit = self.repository(remote, "dependency")
        destination = self.root / "source"
        wrong_commit = self.repository(destination, "unexpected")
        with self.assertRaisesRegex(RuntimeError, "Unexpected checkout"):
            installer.checkout(str(remote), commit, destination)
        self.assertEqual(self.git(destination, "rev-parse", "HEAD"), wrong_commit)
        self.assertEqual((destination / "source.txt").read_text(), "unexpected")

    def test_refuses_nonempty_directory_without_repository(self):
        destination = self.root / "source"
        destination.mkdir()
        (destination / "keep.txt").write_text("keep", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "nonempty"):
            installer.checkout(str(self.root / "unavailable-remote"), "0" * 40, destination)
        self.assertEqual((destination / "keep.txt").read_text(), "keep")
        self.assertFalse((destination / ".git").exists())

    def test_detaches_only_bin_link(self):
        self.link(self.project / "addons/box3d/bin")
        output = installer.prepare_output(self.project)
        self.assertFalse(installer.linked(output))
        self.assertEqual((self.shared / "keep.txt").read_text(), "shared")
        (output / "local.dll").write_text("local")
        self.assertFalse((self.shared / "local.dll").exists())

    def test_refuses_linked_resource_before_any_write(self):
        self.link(self.project / "addons/box3d/icons")
        archive = self.archive([("addons/box3d/README.md", "new"), ("addons/box3d/icons/test.svg", "icon")])
        with self.assertRaises(RuntimeError):
            installer.install_resources(self.project, archive)
        self.assertFalse((self.project / "addons/box3d/README.md").exists())
        self.assertFalse((self.shared / "test.svg").exists())

    def test_never_installs_archive_binaries(self):
        archive = self.archive([("addons/box3d/README.md", "metadata"), ("addons/box3d/bin/unpatched.dll", "binary")])
        installer.install_resources(self.project, archive)
        self.assertEqual((self.project / "addons/box3d/README.md").read_text(), "metadata")
        self.assertFalse((self.project / "addons/box3d/bin").exists())

    def test_refuses_archive_escape(self):
        for entry in ("../escape", "addons/box3d/../../escape", "/addons/box3d/file", "addons/box3d/..\\escape"):
            with self.subTest(entry=entry), self.assertRaises(RuntimeError):
                installer.install_resources(self.project, self.archive([(entry, "bad")]))

    def test_supported_hosts_match_descriptor(self):
        self.assertEqual(installer.host_target("Windows", "AMD64"), ("windows", "x86_64"))
        self.assertEqual(installer.host_target("Linux", "x86_64"), ("linux", "x86_64"))
        self.assertEqual(installer.host_target("Darwin", "arm64"), ("macos", "arm64"))
        with self.assertRaises(RuntimeError):
            installer.host_target("Linux", "aarch64")


if __name__ == "__main__":
    unittest.main()
