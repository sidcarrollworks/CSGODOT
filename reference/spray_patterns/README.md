# Spray patterns

One CSV per weapon, named after the weapon with punctuation stripped
(`ak47.csv`, `m4a1s.csv`). Each row is one shot:

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
