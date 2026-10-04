"""Exercise PE addresses and custom anchor selection without installed game files."""
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from pe_strings import inspect


class PEStringChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "fixture.dll"
        data = bytearray(0x400)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 0x80)
        data[0x80:0x84] = b"PE\0\0"
        struct.pack_into("<HHIIIHH", data, 0x84, 0x8664, 1, 123, 0, 0, 0xF0, 0)
        struct.pack_into("<H", data, 0x98, 0x20B)
        struct.pack_into("<Q", data, 0xB0, 0x180000000)
        section = 0x188
        data[section:section + 8] = b".rdata\0\0"
        struct.pack_into("<IIII", data, section + 8, 0x200, 0x2000, 0x200, 0x200)
        data[0x220:0x220 + 7] = b"recoil\0"
        data[0x240:0x240 + 13] = b"ThrowStrength"
        self.path.write_bytes(data)

    def test_default_anchors_and_identity(self):
        metadata, rows = inspect(self.path)
        self.assertEqual(metadata["sha256"], hashlib.sha256(self.path.read_bytes()).hexdigest())
        self.assertEqual(metadata["imagebase"], "0x180000000")
        self.assertEqual([row["text"] for row in rows], ["recoil"])
        self.assertEqual(rows[0]["rva"], "0x2020")
        self.assertEqual(rows[0]["address"], "0x180002020")

    def test_custom_regex_is_case_insensitive(self):
        _, rows = inspect(self.path, r"grenade|throwstrength")
        self.assertEqual([row["text"] for row in rows], ["ThrowStrength"])
        self.assertEqual(rows[0]["address"], "0x180002040")

    def test_non_pe_rejected(self):
        self.path.write_bytes(b"not a DLL")
        with self.assertRaisesRegex(ValueError, "Not a PE binary"):
            inspect(self.path)


if __name__ == "__main__":
    unittest.main()
