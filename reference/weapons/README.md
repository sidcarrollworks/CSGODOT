# The CS2 weapon sheet

`cs2_weapon_sheet.csv` is the CS2 Weapon Spreadsheet (last weapon update 18
March 2026, "Simple" tab), which Sid supplied on 2026-09-22. It has one row per
weapon and one per mode (scoped, burst, silencer on or off, the R8's fan fire),
45 in all, with the values copied verbatim. `src/weapons/weapon_sheet.gd`
reads it.

**Since 2026-09-22 the game's own file wins.** Sid: "If we can get any of
those numbers from the game files we should use those. The spreadsheet was
human inputted and could have errors." Every number the firing model uses now
comes from CS2's `scripts/weapons.vdata`, through `WeaponVData` and the
committed `vdata.csv`, and the sheet is read first only for the two figures
the game stores as something else: the landing penalty and the ladder. The
tests check the two against each other for every gun and mode; they agree
but for the Desert Eagle's jump and the SG 553's scoped firing inaccuracy,
where the weapon takes the game's.

CS2's own tuning lives in `scripts/weapons.vdata_c`. It was taken not to decode
into usable values, so this sheet stood in for it; Source 2 Viewer 20.0 decodes
it (2026-09-22), and `vdata.md` beside this has what the sheet leaves out and a
check of every value the two share: 914 agree. See "Found beside the sheet".

## Why it can be trusted

The sheet checks out against itself, and against this project's own model:

- **Fatal headshot range** is damage x head multiplier, less 2%, 6% or
  whatever the falloff is every 500 units, through armour for the helmet
  column, until it drops under 100. Worked through exactly that way, it
  matches the sheet to the hundredth of a unit for every weapon that has
  one. That also confirms two things about how CS does damage that the build
  already assumed: falloff compounds per 500 units, and only a helmet
  protects the head (the helmet column uses armour penetration, the bare one
  does not).
- **Accurate range** is where the standing (or crouched) cone is 15.24 cm, six
  inches, from the point of aim: standing inaccuracy / 1000 x range = 0.1524 m
  for every row that has both. That fixes what the inaccuracy numbers mean
  (next section).
- **Totals** add up: total ammo is the magazine plus the reserve, for every
  weapon.

The tests check the accurate range for every row, and the fatal headshot
ranges of the AK-47 and M4A1-S through `HitTarget`, the path a real round
takes.

## Every column

| Column | What it is | In the build |
|---|---|---|
| Price, Kill Award | Buy price and the money a kill with it pays | Not yet: no economy |
| Damage | To an unarmoured chest at point blank | `base_damage` |
| Bullets | Rounds per trigger pull: 1, or a shotgun's pellets (6 to 9) | `pellets`, each traced on its own (`Weapon.pellet_directions`) |
| Armor Penetration | Share of damage that gets through armour | `armor_penetration` |
| Damage Falloff @ 500U | Share lost every 500 units, compounding | `range_modifier` = 1 - this |
| Headshot Multiplier | Not always x4: M4A1-S x3.475, Desert Eagle x3.9 | `head_multiplier` |
| Fire Rate (RPM) | Rounds a minute | `cycle_time` = 60 / this |
| Penetration Power | How well a round goes through walls: 100% SMGs, shotguns and most pistols; 200% rifles, LMGs, the Deagle and the R8; 250% snipers | `penetration_power`: how far through a wall a round gets (`Penetration`) |
| Magazine Size, Reserve, Total Ammo | Reserve is counted in magazines, or in rounds for the tube-fed shotguns | `magazine_size`, `reserve_ammo` = total - magazine |
| Mobility | Top running speed holding it, u/s | `max_player_speed` |
| Tagging Power | How much of a victim's speed a hit takes | `tagging_power`, tags the victim in `PlayerSim` (1 minus CS2's `m_flFlinchVelocityModifierLarge`) |
| Bullet Range | Where a round stops: 8,192 rifles and snipers, 3,600 or 3,700 SMGs, 4,096 pistols, 1,400 or 3,000 shotguns | `max_range` |
| Hold to Shoot | Automatic or not | `automatic`: a semi-automatic gun fires once a click (`Weapon.can_fire`) |
| Tracers | Every round, every third, or none (silenced) | Every round, CS2's client overriding the every-third; none silenced (`Tracers`, `reference/weapons/effects.md`) |
| Accurate Range Stand / Crouch | Where the cone is six inches wide, in metres | Checked, not stored |
| Standing / Crouching Inaccuracy | The cone standing still, crouched still | `inaccuracy_standing`, `_crouching` |
| Running Inaccuracy | The cone at full run | `inaccuracy_moving` |
| Ladder Inaccuracy | The cone on a ladder | `inaccuracy_ladder`, not used: no ladders on dust2 |
| Inaccuracy at Jump Apex | The cone at the top of a standing jump | `inaccuracy_jumping` |
| Inaccuracy After Landing | The penalty landing puts on | `inaccuracy_landing` |
| Inaccuracy From Firing | Added by each round | `inaccuracy_per_shot` |
| Recovery Time Crouch / Stand | Seconds for the firing penalty to fall to a tenth (CS:GO's definition) | `recovery_time_crouch`, `_stand` |
| Recoil Amount | How hard each round kicks, in CS's own units | Not used: the patterns are measured |
| Recoil Angle Variance, Amount Variance | How much each round's kick direction and size vary | Not used, same reason |
| Recoil Pattern | Set (the same every spray) or Random | The two rifles are Set |
| Fatal Headshot Range, (Helmet) | See above | Checked by the tests |

## How to read the inaccuracy

The inaccuracy columns are in CS's own units, the way the weapon scripts store
them: **thousandths of the tangent of the widest angle a round can leave the
aim by**. The AK's 7.01 standing is tan 0.40 degrees; at 21.74 m that is 15.24
cm, its accurate range. `WeaponSheet.cone_degrees()` converts.

Every inaccuracy figure is a **total**, the rifle's own spread included. CS
keeps spread and inaccuracy apart (in CS:GO's weapon scripts the AK is 0.6
spread and 6.41 standing inaccuracy, which is the sheet's 7.01), and running, jumping and landing add
their own terms on top of standing. So:

- at full run the cone is the running figure, and at a slow walk it is the
  standing one;
- a jump taken at a run adds the jump's excess over standing on top of the
  run: 182.07 + 140.76 for the AK, worse than either alone. A standing jump
  (147.77) is not as bad as a full run (182.07);
- landing sets the penalty to the landing figure, which then recovers like a
  round's;
- crouching lowers the floor to the crouching figure and recovers faster.

## Nuances that matter, weapon by weapon

- **Modes are rows of their own.** "M4A1-S (silencer)", "USP-S (silencer)",
  "AUG (scoped)", "SG 553 (scoped)", the three snipers scoped, "FAMAS (burst)",
  "Glock-18 (burst)" and "Revolver (Rapid Fire)" give only what the mode
  changes and "-" for the rest. `WeaponSheet.apply(data, weapon, mode)` reads
  a mode over its weapon.
- **The silencer changes accuracy and recoil, not damage.** The M4A1-S does 38
  either way, but silenced it stands tighter (5.40 against 5.50), runs looser
  (127.40 against 98.38), costs much less per round (7.00 against 12.00),
  kicks less (21 against 25) and draws no tracers. The build carries it
  silenced.
- **Scoping changes mobility and accuracy.** The AWP runs at 200 and 100
  scoped; its unscoped standing cone (81.00) is almost useless and scoped it
  is 2.20. Snipers need a scope state before they mean anything.
- **Semi-automatic weapons** ("Hold to Shoot: No") fire once a click: every
  pistol but the CZ75 and R8, the pump shotguns (Mag-7, Nova, Sawed-Off),
  the AWP and SSG 08, and the burst modes. `Weapon` fires one of them once
  until the trigger comes up or a fresh press is reported (weapons TODO R2).
- **Shotguns fire pellets** (Bullets 6 to 9), each doing the listed damage,
  with range cut to 1,400 or 3,000. The XM1014's 20 a pellet at x4 is 80, so
  it has no fatal headshot range.
- **The SG 553 has 100% armour penetration**, so its two fatal ranges are the
  same. The AUG's helmet range is only 197 units.
- **"Random" recoil** on the pistols but the CZ75 and R8, the pump shotguns,
  the AWP, the SSG 08 and the FAMAS burst means each
  round's kick is drawn fresh (Recoil Amount and the two variances), so there
  is no pattern to measure; "Set" weapons have one.
- **The R8 row says "see note"** for its standing, crouching and running
  accuracy and has a spreadsheet error (#VALUE!) under landing: its first shot waits on the hammer, which the
  columns cannot say. It needs its own handling.
- **Not in the sheet:** reload times, draw times, stomach and leg multipliers
  (x1.25 and x0.75 on every gun), the speed range movement inaccuracy scales
  over, how the recoil index recovers between taps, and model or sound names.

## Where the build and the sheet still differ

- **The M4A1-S spray pattern has 25 rounds**, read off a plot most likely
  taken in CS:GO before the magazine was cut to 20. The gun fires the first 20.
- **Recoil size.** The patterns' shape is measured; their size still rests on
  the AK climbing 16 degrees (`recoil_scale`). The sheet's Recoil Amount does
  not convert into degrees without CS's recoil code, so the 496-unit wall
  spray is still the way to settle it.
- **Recovery between taps** is not in the sheet. The build uses CS:GO's
  shape for it (`src/weapons/recoil_state.gd`, and "Tapping" in
  `reference/weapon_stats.md`); CS2's own constants are not published.

## Found beside the sheet

CS2's own `scripts/weapons.vdata` decodes with Source 2 Viewer 20.0, straight
out of the game on Sid's machine (`scripts/extract_assets.sh weapon-data`;
SteamDatabase's GameTracking-CS2 repository publishes the same file
decompiled). `vdata.md` and `vdata.csv` are written from it for the build
extracted. It carries what the sheet leaves out: a second, slower recovery
time that takes over after the first few rounds of a spray (AK: 0.506
standing, 0.420 crouched, from round 2 to 5), spread apart from inaccuracy,
the scopes' zoom levels and times, the deploy time, how soon a reload lets
the gun fire again, the muzzle's position, the tracers, the burst timing,
and Random recoil's angle and size (R6). Of these the firing model uses the
spread (inside every inaccuracy total) and when a reload lets the gun fire
again (`reload_time`), and the tracers (`src/effects/`) use the tracer
effect, its frequency and the range; the muzzle's position is where the
model's own muzzle attachment is from the eye, which the effects checks hold
`Muzzles` to. The rest are not used yet. For everything the two
share, the game's file wins (see the top of this file).

Checked against the sheet, 914 values agree. Of the six that do not, five
are scoped rows where the sheet says "-" (as unscoped) and the game gives
scoped play its own figure: the AWP's and SSG 08's scoped recoil (25 against
78 and 33) and the SG 553's scoped firing inaccuracy. The sixth is a real
difference for Sid: the Desert Eagle's inaccuracy at the jump's apex, 378.30
in the sheet (18 March 2026) and 46.75 in the game (1.41.8.1, 9 September
2026). The sheet's running and jump figures are its own sums of the game's
terms (standing + spread + the movement's), and its ladder and landing
figures composites of another kind, which is why the raw fields look
different where they are not.
