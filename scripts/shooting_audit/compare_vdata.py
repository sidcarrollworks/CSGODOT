"""Compare decoded weapons.vdata with the generated CSV; never modifies either input.

Reads Source2Viewer's line-oriented scalar/one-line-array output, matching the
format used by scripts/weapon_tables.gd. Nested resource blocks are not fields.
"""
import argparse
import csv
import json
from pathlib import Path
import re


SHOOTING_FIELD = re.compile(
    r"Spread|Inaccuracy|Recoil|Recovery|Burst|Silencer|Revolver|CycleTime|MaxSpeed|"
    r"NumBullets|Damage|Range|Armor|Penetration")


def parse(text):
    entries = {}
    current = None
    for line in text.splitlines():
        entry = re.fullmatch(r"\t([A-Za-z_0-9]+) = ?", line)
        if entry:
            current = entry[1]
            entries[current] = {}
        field = re.fullmatch(r"\t\t([A-Za-z_0-9]+) = (.+)", line)
        if current and field and field[2].strip():
            entries[current][field[1]] = field[2].strip()
    return entries


def resolve(entries, name, stack=()):
    if name in stack:
        raise ValueError(f"Inheritance cycle: {stack} -> {name}")
    fields = entries[name]
    base = fields.get("_base", "").strip('"')
    return {**(resolve(entries, base, (*stack, name)) if base else {}), **fields}


def normalize(value):
    value = value.removeprefix("[").removesuffix("]").strip().strip('"')
    return "|".join(part.strip() for part in value.split(","))


def compare(entries, old):
    resolved = {name: resolve(entries, name) for name in old if name in entries}
    changed, new, missing = [], [], []
    compared = 0
    for name, fields in resolved.items():
        for key, value in fields.items():
            if not SHOOTING_FIELD.search(key):
                continue
            value = normalize(value)
            if key not in old[name]:
                new.append(dict(weapon=name, field=key, current=value))
            else:
                compared += 1
                if old[name][key] != value:
                    changed.append(dict(weapon=name, field=key, old=old[name][key], current=value))
        for key, value in old[name].items():
            if SHOOTING_FIELD.search(key) and key not in fields:
                missing.append(dict(weapon=name, field=key, old=value))
    return resolved, dict(compared_fields=compared, changed=changed,
                         newly_present=new, missing_from_scalar_decode=missing,
                         missing_weapons=sorted(old.keys() - entries.keys()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--table", type=Path, default=Path("reference/weapons/vdata.csv"))
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    entries = parse(args.source.read_text(encoding="utf-8-sig"))
    old = {}
    with args.table.open(encoding="utf-8-sig", newline="") as file:
        rows = csv.reader(file)
        next(rows)
        for name, field, value in rows:
            old.setdefault(name, {})[field] = value
    resolved, report = compare(entries, old)
    args.out.mkdir(parents=True, exist_ok=True)
    for name, value in [("resolved-vdata", resolved), ("vdata-comparison", report)]:
        (args.out / f"{name}.json").write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8")
    print(f"Resolved {len(resolved)} weapons/equipment; compared {report['compared_fields']} fields; "
          f"{len(report['changed'])} changed; {len(report['newly_present'])} newly present; "
          f"{len(report['missing_from_scalar_decode'])} absent from scalar decode")
    # A changed value is an audit result, not a tool failure.


if __name__ == "__main__":
    main()
