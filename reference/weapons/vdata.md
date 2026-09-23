# The game's own weapon tuning

Written by `scripts/weapon_tables.gd` on 2026-09-22 from `scripts/weapons.vdata_c` in CS2 1.41.8.1, as `scripts/extract_assets.sh weapon-data` decodes it. Do not edit by hand. `vdata.csv` beside this has every field of every gun, resolved through the file's inheritance (each gun's entry has a `_base`, its prefab, which has its class's, and so on up to `weapon_base`), one row each.

This is what the weapon sheet (`cs2_weapon_sheet.csv`) is transcribed from, less what the sheet leaves out. Two-valued fields are `[normal, alternate]`: unscoped and scoped for the scoped guns, silencer off and on for the M4A1-S and USP-S. Inaccuracy is in radians of the tangent (the sheet's figures are these x 1000); spread is separate from inaccuracy, and the sheet's figures include it.

## Scopes

The zoom levels L5 of `TODO.md` asked for. A level's FOV is CS's horizontal degrees at 4:3, like `fov`; the zoom times are how long each step takes (0 into level 1, 1 into level 2, 2 back out).

| Class | Levels | FOV 1 | FOV 2 | Zoom times | Unzooms after a shot | Hides the view model | Speed, scoped |
|---|---|---|---|---|---|---|---|
| `weapon_sg556` | 1 | 45 | - | 0.06, 0.1, 0.0 s | no | no | 150.0 |
| `weapon_aug` | 1 | 45 | - | 0.06, 0.1, 0.0 s | no | no | 150.0 |
| `weapon_ssg08` | 2 | 40 | 15 | 0.05, 0.05, 0.05 s | yes | yes | 230.0 |
| `weapon_awp` | 2 | 40 | 10 | 0.05, 0.05, 0.05 s | yes | yes | 100.0 |
| `weapon_g3sg1` | 2 | 40 | 15 | 0.05, 0.05, 0.05 s | no | yes | 120.0 |
| `weapon_scar20` | 2 | 40 | 15 | 0.05, 0.05, 0.05 s | no | yes | 120.0 |

## What the sheet does not have

- Deploy: seconds from drawing the gun to firing it (the draw clips in `timings.md` are the same lengths, or close).
- Reload lockout: seconds after starting a reload that the gun cannot fire, which is shorter than the clip: the tail of a reload can be cut short by firing.
- Spread: the gun's own cone, inside the inaccuracy; normal, alternate.
- Recovery, final: a second, slower recovery time the firing penalty falls by from the round the transition starts at to the one it ends at, blended; stand and crouch.
- Muzzle: where the muzzle flash and tracers start, in the model's units (x forward).
- Tracers: one round in so many draws one; 0 is none.
- Burst: the cycle time in burst mode and the time between a burst's rounds.

| Class | Deploy | Reload lockout | Spread | Recovery, final (stand, crouch; rounds) | Muzzle | Tracers | Burst |
|---|---|---|---|---|---|---|---|
| `weapon_glock` | 1.0 s | 2.267 s | 0.002, 0.015 | 0.33, 0.33; 0 to 5 | [ 21.775, -2.805, -1.975 ] | 1 | 0.5 s cycle, 0.05 s apart |
| `weapon_hkp2000` | 1.0 s | 2.267 s | 0.002, 0.0015 | 0.349532, 0.291277; 3 to 10 | [ 21.32, -2.801, -1.704 ] | 1 | - |
| `weapon_usp_silencer` | 1.0 s | 2.2 s | 0.0025, 0.0015 | 0.349532, 0.291277; 3 to 10 | [ 22.818, -2.801, -2.2 ] | 1 | - |
| `weapon_elite` | 1.0 s | 3.767 s | 0.002, 0.002 | 0.524989, 0.437491; 3 to 10 | [ 23.752, -3.066, -1.754 ] | 1 | - |
| `weapon_p250` | 1.0 s | 2.267 s | 0.002, 0.002 | 0.345388, 0.287823; 3 to 10 | [ 21.729, -2.82, -1.623 ] | 1 | - |
| `weapon_tec9` | 1.0 s | 2.567 s | 0.002, 0.0018 | 0.391, 0.315; 3 to 10 | [ 27.931, -5.126, -3.697 ] | 1 | - |
| `weapon_fiveseven` | 1.0 s | 2.267 s | 0.002, 0.002 | 0.5, 0.5; 0 to 5 | [ 22.214, -2.825, -1.692 ] | 1 | - |
| `weapon_cz75a` | 1.83333 s | 2.733 s | 0.003, 0.003 | 0.345388, 0.287823; 3 to 10 | [ 23.526, -2.805, -1.753 ] | 1 | - |
| `weapon_deagle` | 1.0 s | 2.2 s | 0.002, 0.002 | 0.8112, 0.449927; 3 to 10 | [ 24.317, -3.83, -1.22 ] | 1 | - |
| `weapon_revolver` | 1.166667 s | 2.267 s | 0.00052, 0.068 | 0.8112, 0.449927; 3 to 10 | [ 24.558, -3.634, -1.894 ] | 1 | - |
| `weapon_nova` | 1.0 s | 0.467 s | 0.04, 0.04 | 0.460517, 0.328941; 2 to 5 | [ 42.23, -4.268, -3.652 ] | 1 | - |
| `weapon_xm1014` | 1.0 s | 0.6 s | 0.038, 0.038 | 0.506569, 0.361835; 2 to 5 | [ 39.73, -4.274, -4.177 ] | 1 | - |
| `weapon_sawedoff` | 1.0 s | 0.467 s | 0.062, 0.062 | 0.460517, 0.328941; 2 to 5 | [ 35.318, -4.309, -2.752 ] | 1 | - |
| `weapon_mag7` | 1.0 s | 2.5 s | 0.04, 0.04 | 0.399729, 0.285521; 2 to 5 | [ 39.795, -6.293, -5.04 ] | 1 | - |
| `weapon_mac10` | 1.0 s | 2.567 s | 0.0006, 0.0006 | 0.399729, 0.285521; 2 to 5 | [ 28.289, -6.171, -3.444 ] | 3 | - |
| `weapon_mp9` | 1.2 s | 2.133 s | 0.0006, 0.0006 | 0.25789, 0.184207; 2 to 5 | [ 22.783, -4.759, -2.531 ] | 3 | - |
| `weapon_mp7` | 1.0 s | 3.167 s | 0.0006, 0.0006 | 0.437491, 0.312494; 2 to 5 | [ 27.101, -5.278, -3.958 ] | 3 | - |
| `weapon_mp5sd` | 1.0 s | 2.967 s | 0.0006, 0.0006 | 0.437491, 0.312494; 2 to 5 | [ 38.905, -5.166, -4.33 ] | 0 | - |
| `weapon_ump45` | 1.0 s | 3.467 s | 0.001, 0.001 | 0.349993, 0.249995; 2 to 5 | [ 34.674, -5.162, -4.139 ] | 3 | - |
| `weapon_p90` | 1.0 s | 3.367 s | 0.001, 0.001 | 0.372098, 0.265784; 2 to 5 | [ 24.058, -5.247, -3.181 ] | 3 | - |
| `weapon_bizon` | 1.1 s | 2.433 s | 0.001, 0.001 | 0.331572, 0.236837; 2 to 5 | [ 33.442, -5.107, -3.014 ] | 3 | - |
| `weapon_galilar` | 1.1 s | 3.033 s | 0.0006, 0.0006 | 0.5, 0.47; 2 to 5 | [ 34.673, -5.319, -3.601 ] | 3 | - |
| `weapon_famas` | 1.0 s | 3.3 s | 0.0006, 0.0006 | 0.5, 0.48; 2 to 5 | [ 36.464, -6.028, -4.783 ] | 3 | 0.55 s cycle, 0.075 s apart |
| `weapon_ak47` | 1.0 s | 2.467 s | 0.0006, 0.0006 | 0.506, 0.419728; 2 to 5 | [ 37.422, -4.938, -3.394 ] | 3 | - |
| `weapon_m4a1` | 1.133333 s | 3.067 s | 0.0006, 0.00045 | 0.466044, 0.332888; 2 to 5 | [ 35.62, -4.975, -3.707 ] | 3 | - |
| `weapon_m4a1_silencer` | 1.133333 s | 3.067 s | 0.0006, 0.0005 | 0.466044, 0.332888; 2 to 5 | [ 39.583, -4.846, -3.367 ] | 3 | - |
| `weapon_sg556` | 1.0 s | 2.767 s | 0.0006, 0.0003 | 0.452886, 0.379204; 2 to 5 | [ 40.466, -5.134, -3.871 ] | 3 | - |
| `weapon_aug` | 1.16667 s | 3.767 s | 0.0005, 0.0003 | 0.429727, 0.30552; 2 to 5 | [ 29.957, -3.597, -2.666 ] | 3 | - |
| `weapon_m249` | 1.1 s | 5.7 s | 0.002, 0.002 | 0.828931, 0.592093; 2 to 5 | [ 52.925, -7.43, -3.928 ] | 1 | - |
| `weapon_negev` | 1.1 s | 5.7 s | 0.002, 0.002 | 0.1, 0.08; 9 to 12 | [ 45.371, -7.503, -3.87 ] | 1 | - |
| `weapon_ssg08` | 1.0 s | 3.7 s | 0.00028, 0.00023 | 0.142096, 0.055783; 2 to 5 | [ 48.901, -5.688, -3.681 ] | 1 | - |
| `weapon_awp` | 1.266667 s | 3.667 s | 0.0002, 0.0002 | 0.34539, 0.24671; 2 to 5 | [ 54.128, -5.022, -3.124 ] | 1 | - |
| `weapon_g3sg1` | 1.0 s | 4.667 s | 0.0003, 0.0003 | 0.544331, 0.388808; 2 to 5 | [ 45.492, -5.287, -4.119 ] | 1 | - |
| `weapon_scar20` | 1.0 s | 3.067 s | 0.0003, 0.0003 | 0.544331, 0.388808; 2 to 5 | [ 44.474, -5.69, -4.37 ] | 1 | - |

## Against the sheet

914 values the two share agree; 6 do not. The sheet's running and jump-apex figures are its own sums, standing inaccuracy + spread + the movement's own term, and are compared that way; its ladder and landing figures are composites of another kind (landing scales the game's term by the fall) and are left out. The sheet was last updated for 18 March 2026; where the two differ, the game is the newer.

| Sheet row | Column | Sheet | Game |
|---|---|---|---|
| Desert Eagle | Inaccuracy at Jump Apex | 378.30 | 46.75 |
| SG 553 (scoped) | Inaccuracy From Firing | 7.95 (the sheet's "-": as unscoped) | 9.2 |
| SSG 08 (scoped) | Recoil Amount | 33.0 (the sheet's "-": as unscoped) | 25.0 |
| SSG 08 (scoped) | Recoil Amount Variance | 15 (the sheet's "-": as unscoped) | 2.0 |
| AWP (scoped) | Recoil Amount | 78.0 (the sheet's "-": as unscoped) | 25.0 |
| AWP (scoped) | Recoil Amount Variance | 15 (the sheet's "-": as unscoped) | 2.0 |
