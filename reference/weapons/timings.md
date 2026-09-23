# Every gun's timings

Written by `scripts/weapon_tables.gd` on 2026-09-23 from the first-person clips of CS2 1.41.8.2, as `scripts/extract_assets.sh weapon-animations` reads them. Do not edit by hand. `timings.csv` beside this has every clip's length and every event in it, sounds included, one row each.

These are the game's own animation data, not measurements. Each clip is authored at 30 frames a second and carries events at points through it; the ones that matter here:

- `WPN_RELOAD_ADD_AMMO`: the moment a reload puts the rounds in. A reload cancelled before it keeps the old magazine.
- The clip's end: the gun is ready again. The reload clips' lengths are CS2's reload times as they are quoted (AK-47 2.43 s, AWP 3.67 s, Glock 2.27 s).
- `WPN_RELOAD_INTRO`, `_LOOP`, `_OUTRO`: the shotguns that load a shell at a time mark the one clip's three parts; the loop repeats per shell.
- `WPN_SILENCER_ATTACH`, `_DETACH`: the moment the silencer is on or off, part way through the clip.

The firing clip is how long the gun model moves after a round, not how often it fires (the sheet's fire rate is that); the AK's 0.767 s against the 0.644 s its model was seen to settle in, the clip's last frames holding still.

| Class | Set | Draw | Reload: rounds in, ready | Empty reload: rounds in, ready | Firing clip | Also |
|---|---|---|---|---|---|---|
| `weapon_glock` | `pistol/pistol_glock18` | 1.00 s | 0.93 s, 2.27 s | 1.27 s, 2.27 s | 0.40 s |  |
| `weapon_hkp2000` | `pistol/pistol_hkp2000` | 1.00 s | 0.93 s, 2.27 s | 1.20 s, 2.27 s | 0.40 s |  |
| `weapon_usp_silencer` | `pistol/_default_pistol` | 1.00 s | 0.90 s, 2.17 s | 1.00 s, 2.17 s | 0.40 s | silencer attach: 3.37 s, done 4.83 s; silencer detach: 3.37 s, done 4.83 s; draw silenced 1.00 s |
| `weapon_elite` | `pistol/pistol_elite` | 1.00 s | 2.93 s, 3.77 s | - | 0.83 s |  |
| `weapon_p250` | `pistol/pistol_p250` | 1.00 s | 0.93 s, 2.27 s | 1.20 s, 2.27 s | 0.40 s |  |
| `weapon_tec9` | `pistol/pistol_tec9` | 1.00 s | 1.43 s, 2.57 s | - | 0.40 s |  |
| `weapon_fiveseven` | `pistol/pistol_fiveseven` | 1.00 s | 0.97 s, 2.27 s | 1.20 s, 2.27 s | 0.40 s |  |
| `weapon_cz75a` | `pistol/pistol_cz75a` | 1.83 s | 1.57 s, 2.73 s | 1.67 s, 2.73 s | 0.40 s | draw2 1.83 s |
| `weapon_deagle` | `pistol/pistol_deagle` | 1.00 s | 0.77 s, 2.20 s | 1.03 s, 2.20 s | 0.70 s |  |
| `weapon_revolver` | `pistol/pistol_revolver` | 1.17 s | 1.97 s, 2.27 s | - | 0.70 s | prepare shoot 0.97 s |
| `weapon_nova` | `rifle/rifle_nova` | 1.00 s | 0.67 s, 1.63 s | - | 0.80 s | shells: first at 0.37 s, then one every 0.43 s, the round in 0.30 s into each; the finish 0.83 s |
| `weapon_xm1014` | `rifle/rifle_xm1014` | 1.00 s | 1.03 s, 1.73 s | - | 0.87 s | shells: first at 0.70 s, then one every 0.60 s, the round in 0.33 s into each; the finish 0.43 s |
| `weapon_sawedoff` | `rifle/rifle_sawedoff` | 1.00 s | 0.67 s, 1.73 s | - | 0.80 s | shells: first at 0.40 s, then one every 0.53 s, the round in 0.27 s into each; the finish 0.80 s |
| `weapon_mag7` | `rifle/rifle_mag7` | 1.00 s | 1.07 s, 2.47 s | - | 1.20 s |  |
| `weapon_mac10` | `rifle/rifle_mac10` | 1.00 s | 1.20 s, 2.57 s | - | 0.80 s |  |
| `weapon_mp9` | `rifle/rifle_mp9` | 1.20 s | 0.87 s, 2.13 s | - | 0.83 s |  |
| `weapon_mp7` | `rifle/rifle_mp7` | 1.00 s | 1.43 s, 3.13 s | - | 0.80 s |  |
| `weapon_mp5sd` | `rifle/rifle_mp5sd` | 1.00 s | 2.00 s, 2.97 s | - | 0.40 s | draw2 1.00 s |
| `weapon_ump45` | `rifle/rifle_ump45` | 1.00 s | 1.53 s, 3.43 s | - | 1.00 s |  |
| `weapon_p90` | `rifle/rifle_p90` | 1.00 s | 2.00 s, 3.37 s | - | 0.83 s |  |
| `weapon_bizon` | `rifle/rifle_bizon` | 1.10 s | 1.13 s, 2.43 s | - | 0.87 s |  |
| `weapon_galilar` | `rifle/rifle_galilar` | 1.10 s | 1.17 s, 3.03 s | - | 0.80 s |  |
| `weapon_famas` | `rifle/rifle_famas` | 1.00 s | 1.67 s, 3.30 s | - | 0.87 s |  |
| `weapon_ak47` | `rifle/rifle_ak` | 1.00 s | 1.10 s, 2.43 s | - | 0.77 s |  |
| `weapon_m4a1` | `rifle/rifle_m4a4` | 1.13 s | 1.37 s, 3.07 s | - | 0.40 s |  |
| `weapon_m4a1_silencer` | `rifle/_default_rifle` | 1.13 s | 1.37 s, 3.07 s | - | 0.40 s | silencer attach: 3.43 s, done 4.83 s; silencer detach: 3.27 s, done 4.83 s |
| `weapon_sg556` | `rifle/rifle_sg556` | 1.00 s | 1.03 s, 2.77 s | - | 0.70 s |  |
| `weapon_aug` | `rifle/rifle_aug` | 1.17 s | 1.57 s, 3.77 s | - | 0.93 s |  |
| `weapon_m249` | `rifle/rifle_m249` | 1.10 s | 3.73 s, 5.70 s | - | 1.73 s |  |
| `weapon_negev` | `rifle/rifle_negev` | 1.10 s | 3.83 s, 5.70 s | - | 0.87 s |  |
| `weapon_ssg08` | `rifle/rifle_ssg08` | 1.00 s | 2.00 s, 3.70 s | - | 1.67 s |  |
| `weapon_awp` | `rifle/rifle_awp` | 1.27 s | 2.00 s, 3.67 s | - | 1.60 s |  |
| `weapon_g3sg1` | `rifle/rifle_g3sg1` | 1.00 s | 2.67 s, 4.67 s | - | 0.73 s |  |
| `weapon_scar20` | `rifle/rifle_scar20` | 1.00 s | 1.53 s, 3.07 s | 1.47 s, 3.07 s | 0.83 s |  |
