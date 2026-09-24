#!/usr/bin/env python3
"""Turns the per-shot mouse moves of Artanis-RCS (MIT) into spray pattern
files in degrees, one per gun, named by CS2 class.

    python3 scripts/convert_rcs_patterns.py <Artanis-RCS checkout>

Artanis-RCS is a recoil compensation tool: each row of its patterns/<gun>.csv
is the mouse move, in counts at sensitivity 1, that pulls the aim back onto
the target before the next shot (dx right, dy down, then a delay in ms). It
multiplies each by 2.45 and divides by the in-game sensitivity; CS2 turns a
count into 0.022 degrees times the sensitivity (m_yaw and m_pitch). So a
row is 2.45 x 0.022 degrees of mouse, and the bullet had drifted the other
way by as much. Summing the rows gives where each shot lands, from the
first.

The files are then put on the scale of the repo's own ak47.csv, which
assumes the AK-47 climbs 16 degrees: the one factor that lays the source's
AK-47 best over ours (least squares, all 30 shots), applied to every gun,
so one recoil_scale corrects them all together as it does the two rifles.
"""

import math
import pathlib
import subprocess
import sys

DEGREES_PER_ROW_UNIT = 2.45 * 0.022

# Source file -> (CS2 class, name CS2 gives it).
GUNS = {
    "ak47": ("weapon_ak47", "AK-47"),
    "m4a4": ("weapon_m4a1", "M4A4"),
    "m4a1": ("weapon_m4a1_silencer", "M4A1-S"),
    "galil": ("weapon_galilar", "Galil AR"),
    "famas": ("weapon_famas", "FAMAS"),
    "sg553": ("weapon_sg556", "SG 553"),
    "aug": ("weapon_aug", "AUG"),
    "p90": ("weapon_p90", "P90"),
    "bizon": ("weapon_bizon", "PP-Bizon"),
    "ump45": ("weapon_ump45", "UMP-45"),
    "mac10": ("weapon_mac10", "MAC-10"),
    "mp5sd": ("weapon_mp5sd", "MP5-SD"),
    "mp7": ("weapon_mp7", "MP7"),
    "mp9": ("weapon_mp9", "MP9"),
    "m249": ("weapon_m249", "M249"),
    "negev": ("weapon_negev", "Negev"),
    "cz75": ("weapon_cz75a", "CZ75-Auto"),
}

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "reference" / "spray_patterns"


def read_source(path):
    shots = []
    x = y = 0.0
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        fields = line.strip().split(",")
        if len(fields) < 3:
            continue
        x -= float(fields[0]) * DEGREES_PER_ROW_UNIT
        y -= float(fields[1]) * DEGREES_PER_ROW_UNIT
        shots.append((x, y))
    return shots


def read_ours(path):
    shots = []
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split(",")
        shots.append((float(fields[1]), float(fields[2])))
    return shots


def fit_scale(source, ours):
    count = min(len(source), len(ours))
    dot = sum(source[i][0] * ours[i][0] + source[i][1] * ours[i][1] for i in range(count))
    norm = sum(source[i][0] ** 2 + source[i][1] ** 2 for i in range(count))
    return dot / norm


def main():
    source_dir = pathlib.Path(sys.argv[1]) / "patterns"
    commit = subprocess.run(
        ["git", "-C", sys.argv[1], "log", "-1", "--format=%H %cs"],
        capture_output=True, text=True, check=True).stdout.split()
    scale = fit_scale(read_source(source_dir / "ak47.csv"), read_ours(OUT / "ak47.csv"))
    print("scale onto ak47.csv: %.4f (the source's AK-47 climbs %.2f degrees)" % (
        scale, max(y for _, y in read_source(source_dir / "ak47.csv"))))
    for name, (weapon_class, display) in GUNS.items():
        shots = read_source(source_dir / ("%s.csv" % name))
        lines = [
            "# %s (%s): %d shots." % (display, weapon_class, len(shots)),
            "# From Artanis-RCS (MIT), github.com/ArtanisInc/Artanis-RCS,",
            "# patterns/%s.csv at %s (%s). Converted by" % (name, commit[0][:7], commit[1]),
            "# scripts/convert_rcs_patterns.py: the mouse moves summed and turned",
            "# into degrees (2.45 x 0.022 per unit), then x%.4f onto ak47.csv's" % scale,
            "# scale. Not measured here. See README.md for how far to trust it.",
            "# shot,x_degrees,y_degrees",
        ]
        lines += ["%d,%.4f,%.4f" % (i, x * scale, y * scale) for i, (x, y) in enumerate(shots)]
        (OUT / ("%s.csv" % weapon_class)).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
