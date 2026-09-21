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

## Both files here are placeholders

They were generated from a crude model of the right general shape: up first,
then a left sweep, then a right sweep. They are not measurements, and the guns
will not spray like CS2 until they are replaced. Both files say so in their
header, so a real pattern is obvious by the absence of that warning.

This is not a shortcut that can be skipped. The spray pattern is most of what
makes a rifle feel like itself, and no amount of tuning elsewhere compensates
for a wrong one.

## Measuring a real one

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
