# CS2's animation graphs

Written by `scripts/animgraph_tables.gd` on 2026-09-23 from the 232 graphs under `animation/graphs/` in CS2 1.41.8.3, as `scripts/extract_assets.sh animgraphs` decodes them. Do not edit by hand. `reference/animgraph2.md` says what a graph is and how to read these.

A graph with variations is one graph compiled again with other clips in its slots, named `<graph>.vnmgraph+<variation>`; the nodes, blends and conditions are the same in each. Nodes counts every node, the parameters and the conditions among them; Runs is the graphs it plays through its graph slots.

## worldmodel

| Graph | Variations | Nodes | Parameters | Skeleton | Runs |
|---|---|---|---|---|---|
| `worldmodel` | - | 1870 | 47 | worldmodel | worldmodel_locomotion, worldmodel_gun, worldmodel_grenade, worldmodel_knife, worldmodel_gun_cz75 |
| `worldmodel_grenade` | decoy, flash, he, incendiary, molotov, smoke | 74 | 7 | worldmodel | - |
| `worldmodel_gun` | ak47, aug, awp, bizon, deagle, elites, famas, five_seven, g3sg1, galil, glock, hkp2000, m249, m4a1s, m4a4, mac10, mag7, mp5sd, mp7, mp9, negev, nova, p250, p90, revolver, sawedoff, scar20, sg556, ssg08, taser, tec9, ump45, usp, xm1014 | 121 | 8 | worldmodel | - |
| `worldmodel_gun_cz75` | - | 70 | 6 | worldmodel | - |
| `worldmodel_knife` | bayonet, bowie, butterfly, canis, cord, css, default_ct, default_t, falchion, flip, gut, karambit, kukri, m9, navajo, outdoor, push, skeleton, stiletto, tactical, talon, ursus | 238 | 8 | worldmodel | - |
| `worldmodel_locomotion` | knife, pistol, rifle | 810 | 18 | worldmodel | - |

## viewmodel

| Graph | Variations | Nodes | Parameters | Skeleton | Runs |
|---|---|---|---|---|---|
| `viewmodel` | - | 457 | 20 | viewmodel | viewmodel_gun_revolver, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_talon, viewmodel_knife_karambit, viewmodel_grenade, viewmodel_inspects |
| `viewmodel_grenade` | decoy, flash, he, incendiary, molotov, smoke | 73 | 7 | viewmodel | - |
| `viewmodel_gun` | ak47, aug, awp, bizon, deagle, famas, five_seven, g3sg1, galil, glock, hkp2000, m249, m4a1s, m4a4, mac10, mag7, mp5sd, mp7, mp9, negev, nova, p250, p90, sawedoff, scar20, sg556, ssg08, ssg08_legacy, taser, tec9, ump45, usp, xm1014 | 285 | 16 | viewmodel | - |
| `viewmodel_gun_cz75` | - | 122 | 9 | viewmodel | viewmodel_inspects |
| `viewmodel_gun_elites` | - | 173 | 9 | viewmodel | viewmodel_inspects |
| `viewmodel_gun_revolver` | - | 194 | 10 | viewmodel | viewmodel_inspects |
| `viewmodel_inspects` | ak47, aug, awp, bizon, c4, cz75a, deagle, decoy_grenade, elite, famas, five_seven, flashbang_grenade, g3sg1, galil, glock, he_grenade, hkp2000, incendiary_grenade, knife_bayonet, knife_bowie, knife_canis, knife_cord, knife_css, knife_default_ct, knife_default_t, knife_falchion, knife_flip, knife_gut, knife_karambit, knife_kukri, knife_m9, knife_navajo, knife_outdoor, knife_push, knife_skeleton, knife_stiletto, knife_tactical, knife_talon, knife_ursus, m249, m4a1s, m4a4, mac10, mag7, molotov, mp5sd, mp7, mp9, negev, nova, p250, p90, revolver, sawedoff, scar20, sg556, smoke_grenade, ssg08, ssg08_legacy, taser, tec9, ump45, usp, xm1014 | 85 | 4 | viewmodel | - |
| `viewmodel_knife` | bayonet, bowie, canis, cord, css, default_ct, default_t, falchion, flip, gut, kukri, m9, navajo, outdoor, push, skeleton, stiletto, tactical, ursus | 161 | 10 | viewmodel | - |
| `viewmodel_knife_butterfly` | - | 166 | 9 | viewmodel | - |
| `viewmodel_knife_karambit` | - | 173 | 9 | viewmodel | - |
| `viewmodel_knife_talon` | - | 175 | 9 | viewmodel | - |

## chicken

| Graph | Variations | Nodes | Parameters | Skeleton | Runs |
|---|---|---|---|---|---|
| `chicken` | - | 836 | 11 | chicken | - |
| `egg_pristine_world` | - | 69 | 4 | pristine_egg_world | - |

## ui

| Graph | Variations | Nodes | Parameters | Skeleton | Runs |
|---|---|---|---|---|---|
| `uimodel` | - | 960 | 18 | worldmodel | uimodel_walkup, uimodel_idles, uimodel_celebration |
| `uimodel_celebration` | celebrate_ava, celebrate_crasswater, celebrate_darryl, celebrate_doctor, celebrate_goggles, celebrate_mae, celebrate_muhlik, celebrate_ricksaw, celebrate_rouchard, celebrate_vypa, celebrate_wet_sox, defeat_ava, defeat_crasswater, defeat_darryl, defeat_doctor, defeat_goggles, defeat_mae, defeat_muhlik, defeat_ricksaw, defeat_rouchard, defeat_vypa, defeat_wet_sox | 28 | 1 | worldmodel | - |
| `uimodel_idles` | - | 596 | 14 | worldmodel | - |
| `uimodel_walkup` | - | 404 | 14 | worldmodel | uimodel_idles |
