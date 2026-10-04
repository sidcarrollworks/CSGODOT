"""Fingerprint PE32+ binaries and find selected ASCII strings, without loading DLLs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct


DEFAULT_PATTERN = (r"recoil|inaccuracy|accuracypenalty|burst|revolver|silencer|"
                   r"spread|aimpunch|postpone|taser")


def inspect(path, pattern=DEFAULT_PATTERN):
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise ValueError(f"Not a PE binary: {path}")
    header = struct.unpack_from("<I", data, 0x3C)[0]
    if data[header:header + 4] != b"PE\0\0":
        raise ValueError(f"Missing PE signature: {path}")
    machine, count, timestamp, _, _, optional, _ = struct.unpack_from(
        "<HHIIIHH", data, header + 4)
    if struct.unpack_from("<H", data, header + 24)[0] != 0x20B:
        raise ValueError(f"Requires PE32+: {path}")
    imagebase = struct.unpack_from("<Q", data, header + 48)[0]
    sections = []
    for i in range(count):
        pos = header + 24 + optional + i * 40
        name = data[pos:pos + 8].rstrip(b"\0").decode("ascii")
        vsize, rva, size, offset = struct.unpack_from("<IIII", data, pos + 8)
        sections.append(dict(name=name, rva=rva, size=size, offset=offset, vsize=vsize))
    metadata = dict(file=str(path.resolve()), sha256=hashlib.sha256(data).hexdigest(),
                    length=len(data), timestamp=timestamp, machine=hex(machine),
                    imagebase=hex(imagebase), sections=sections)
    rows = []
    pattern = re.compile(pattern, re.I)
    for match in re.finditer(rb"[\x20-\x7e]{5,}", data):
        value = match.group().decode("ascii")
        if not pattern.search(value):
            continue
        section = next((s for s in sections
                        if s["offset"] <= match.start() < s["offset"] + s["size"]), None)
        if section is None:
            continue
        rva = section["rva"] + match.start() - section["offset"]
        rows.append(dict(address=hex(imagebase + rva), rva=hex(rva), text=value))
    return metadata, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pattern", default=DEFAULT_PATTERN,
                        help="Case-insensitive ASCII string regex (default: shooting anchors)")
    parser.add_argument("binaries", type=Path, nargs="+")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for path in args.binaries:
        metadata, rows = inspect(path, args.pattern)
        name = path.stem
        (args.out / f"{name}-metadata.json").write_text(
            json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        (args.out / f"{name}-strings.json").write_text(
            json.dumps(rows, indent=2) + "\n", encoding="utf-8")
        (args.out / f"{name}-targets.tsv").write_text(
            "".join(f"{r['address'][2:]}\t{r['text']}\n" for r in rows), encoding="utf-8")
        print(f"{name}: {metadata['sha256']}; {len(rows)} matching strings")


if __name__ == "__main__":
    main()
