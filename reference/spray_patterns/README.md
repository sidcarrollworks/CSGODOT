# Spray patterns

One CSV per weapon. `ak47.csv` and `m4a1s.csv` are the two the game plays,
read off CS2 plots (below). The `weapon_<class>.csv` files, named by CS2
class, are every other fully automatic gun's pattern from a community
source, plus that source's AK-47 and M4A1-S for comparison (see "Every other
gun"). Note `weapon_m4a1.csv` is the M4A4, whose class that is. Each row is
one shot:

```
shot,x_degrees,y_degrees
```

`x_degrees` is degrees to the right of the point of aim and `y_degrees` is
degrees above it, both measured from where the first shot went. Shot 0 is
therefore always `0,0`. Lines starting with `#` are comments and are ignored.

The file is read by `RecoilPattern.load_pattern()` at startup, and a shot index
past the end of the pattern reuses the last row, which is what CS2 does once a
magazine runs longer than the pattern.

## Where these came from

Both were read off CS2 spray plots on 2026-09-21: 30 shots for the AK-47 and
25 for the M4A1-S. The plots encode firing order as saturation, with the last
round the most saturated, so the order is recovered by sorting the dots by
saturation. Where two neighbouring dots are within the encoding's noise, the
order that keeps the path of the spray continuous wins, because a spray is a
path and cannot jump about.

The shape is measured. **The size is not.** The plots carry no angular scale,
so both patterns were scaled together by assuming the AK-47 climbs 16 degrees
from its first shot to the top of its pattern. Scaling them together preserves
the relationship between the two guns, which is the part that decides whether
the M4A1-S feels easier to control than the AK, and it does.

## Correcting the scale

Do not edit the rows. Set `recoil_scale` on the weapon in
`src/weapons/weapon_library.gd`; it multiplies the whole pattern.

To find the right value, spray a wall in CS2 from a measured distance and
measure the height of the pattern on it. The climb in degrees is
`atan(height / distance)`. Then `recoil_scale = measured / 16.0` for the AK,
and the same number goes on both weapons, since they share the scale.

## Measuring one from scratch

The pattern is deterministic in CS2, so a single clean spray is enough.

1. In CS2: `sv_cheats 1`, `weapon_accuracy_nospread 1`, `weapon_recoil_cooldown 0`,
   and `weapon_debug_spread_gap 1`. Stand still, crouched, facing a flat wall at
   a known distance. Empty the magazine in one burst.
2. Screenshot the wall with the bullet holes on it. Note the distance to the
   wall and your FOV.
3. Convert each hole to an angle. A hole `d` units from the point of aim on a
   wall `D` units away is `atan(d / D)` degrees off axis. Write the rows out in
   firing order.

The awkward step is step 3, so the test range does it for you in the other
direction:

1. Open `maps/test_range/test_range.tscn` and pick the weapon with `1` or `2`.
2. Empty the magazine into the wall. Every impact is marked.
3. Press `P`. The range converts the impacts back into angles and writes
   `spray_<weapon>.csv` next to the project's user data, printing the real path
   to the console.
4. Copy that file over the one here.

So the workflow that actually works is: match the in-game spray by eye against
the CS2 screenshot, adjust, re-spray, export when it looks right. That is worse
than measuring CS2 directly and better than the placeholder.

## Every other gun

The `weapon_<class>.csv` files hold 17 patterns, taken on 2026-09-24 from
[Artanis-RCS](https://github.com/ArtanisInc/Artanis-RCS) (MIT licence,
commit 7387d39 of 1 May 2026; the patterns date from its first upload on 9
June 2025, the MP9's from 22 July 2025 and the Negev's from 10 October 2025).
`scripts/convert_rcs_patterns.py` rebuilds them from a checkout.

| Class | Gun | Shots |
|---|---|---|
| weapon_ak47 | AK-47 (comparison only) | 30 |
| weapon_m4a1_silencer | M4A1-S (comparison only) | 25 |
| weapon_m4a1 | M4A4 | 30 |
| weapon_galilar | Galil AR | 35 |
| weapon_famas | FAMAS | 25 |
| weapon_sg556 | SG 553, unscoped | 30 |
| weapon_aug | AUG, unscoped | 30 |
| weapon_mac10, weapon_mp9, weapon_mp7, weapon_mp5sd, weapon_ump45, weapon_p90, weapon_bizon | the seven SMGs | 30, 30, 30, 30, 25, 50, 64 |
| weapon_m249, weapon_negev | M249, Negev | 100, 150 |
| weapon_cz75a | CZ75-Auto | 12 |

**What the source is.** A recoil compensation tool: each row is the mouse
move that pulls the aim back after a shot. Summed and turned into degrees
(2.45 counts at sensitivity 1 per row unit, the tool's own factor, times
CS2's 0.022 degrees a count), they give where each shot lands. It does not
say how it got them. Nothing here is from Valve's leaked code.

**Why it is worth trusting.**

- Its AK-47 and M4A1-S lay over the two plots Sid supplied almost exactly:
  scaled by one factor, the AK's 30 shots sit 0.67 degrees apart on average
  (root mean square), the M4A1-S's 0.42, and the best factor for each gun
  alone is the same to 1% (1.358 and 1.369). Two sources, read two ways,
  agree on shape and on the two guns' sizes relative to each other.
- It agrees with CS2's own weapon file where that file can speak: the MP7
  and MP5-SD have the same recoil seed (61649), magnitude and angle
  variance in `vdata.csv`, and the source's two patterns are identical; the
  Negev is the one automatic gun with no angle variance (the P2000 and
  USP-S are the others with none), and the source's Negev
  climbs straight up with no sideways move at all.
  `tests/run_spray_pattern_checks.gd` holds both.
- It is current: Valve's only recoil change to these guns since the upload
  is "MP9 - increased recoil magnitude" (16 July 2025), and the source
  replaced its MP9 on 17 and 22 July. Valve's notes of 21 April 2026 changed
  the camera's motion, not where bullets go ("Bullet trajectories should
  continue to match CS2").

**Its scale.** Taken at the tool's own factor, the AK-47 climbs 11.7
degrees, where `ak47.csv` assumes 16. The files are stored on `ak47.csv`'s
scale (every gun times 1.3577, the factor that fits the two AKs), so the
guns keep their sizes relative to the two rifles and one `recoil_scale`
still corrects all of them. If the tool's factor is right, `recoil_scale`
wants to be 0.73 on every gun; the 496-unit spray in CS2 (roadmap item 8)
settles which.

**Where it differs from our two.**

- AK-47, rounds 17 to 20 (counting from 0): the source has them in the
  order 18, 17, 20, 19 of ours. The dots sit within 0.3 degrees of each
  other in pairs, and the plots' saturation could not tell them apart
  (as "Where these came from" warns); the source reads as the better order.
  Round 1 is 0.5 degrees up in ours and on the point of aim in the source.
- M4A1-S: rounds 15 to 18 are ordered differently in the same way, and ours
  runs up to 0.6 degrees higher over the last rounds (9.57 against 8.96 at
  the top). Its 25 rows in both are CS:GO's magazine; CS2 fires 20.

Neither `ak47.csv` nor `m4a1s.csv` has been changed.

**Not covered.** No source reachable from here has patterns for the rest,
and Sid's notes (2026-09-24) and CS2's weapon file sort them as follows:

- **R8 Revolver, fan fire:** a wide spread, not a pattern (Sid). The game
  agrees: fan fire's spread is 0.068 against 0.00052 on a single shot, and
  its kick is 45 against 20 (`vdata.csv`, the alternate values).
- **XM1014:** each shot kicks the view up hard and the pellets spread wide;
  there is no path to learn (Sid). Its recoil magnitude is 80 with a
  variance of 20. The spread may still be fixed: it is one of the four
  shotguns with a spread seed (817955), from the Holiday Spread update
  (`reference/research/combat.md`, R5).
- **SG 553 and AUG, scoped:** the path keeps its shape (Sid). Its size
  does not stay the same: CS2's file gives the scoped mode less recoil,
  19 against 28 on the SG 553 and 16 against 24 on the AUG, with the same
  seed and angle variance. Inferred: the scoped pattern is the unscoped
  one times 0.68 and 0.67. A scoped spray at the wall would confirm it.
- **G3SG1 and SCAR-20:** still needed. The sheet marks both "Set Pattern",
  and the game gives each its own seed.

The guns the sheet marks "Random" (every other pistol, the other
shotguns, the AWP and the SSG 08) are weapons TODO R6. The 496-unit wall
procedure above still covers any of them.

**Not yet read by the game.** `WeaponLibrary.build` gives every gun but the
AK-47 and M4A1-S no pattern. Reading these is one line there,
`data.recoil_pattern = RecoilPattern.load_pattern(weapon_class)` when the
file exists; the recoil settling time, still the AK-47's on every other
gun, would want the same care.
