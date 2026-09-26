# Each item's body on the ground

Written by `scripts/weapon_tables.gd` (`scripts/weapon_physics_table.gd`) on 2026-09-25 from CS2 1.41.8.5: the physics hull beside each world model (`*_physics.gltf`, from `scripts/extract_assets.sh weapons` and `equipment`) and the model's PHYS block (`scripts/extract_assets.sh weapon-physics`). Do not edit by hand. `physics.csv` beside it is what `ItemPhysics` reads; the hull's corners are there.

Positions are in the world model's axes (+Z the muzzle, +Y the top, +X the gun's left), in inches from the model's origin. The volume and centre of mass are reckoned from the hull's triangles; the game's volume is beside ours as a check, and its centroid beside our centre of mass, though the game's is the average of the hull's corners, not the centre of the volume. The inertia is for a mass of 1, about the centre of mass. The frame says whether the exported hull already sat on the model (model) or was placed by its bone's bind pose (bone), whichever puts the corners' average on the game's centroid.

| Class | Bone | Surface | Mass | Angular damping | Volume (game's) | Centre of mass (game's) | Frame |
|---|---|---|---|---|---|---|---|
| `weapon_glock` | weapon_offset |  | 3.0 | 10.0 | 27.1681 (27.1684) | 0.0 1.0648 1.8017 (0.0 0.9405 2.0312) | model |
| `weapon_hkp2000` | weapon_offset |  | 3.0 | 0.0 | 27.429 (27.4291) | 0.0 1.7709 4.9355 (0.0 1.9125 4.7918) | model |
| `weapon_usp_silencer` | weapon_offset |  | 3.0 | 0.0 | 138.9038 (138.9054) | -0.0023 2.1841 8.2937 (0.0194 2.112 7.146) | model |
| `weapon_elite` | weapon |  | 4.0 | 0.0 | 125.2613 (125.2614) | 0.7048 0.5839 2.6181 (0.6797 0.635 2.6962) | model |
| `weapon_p250` | weapon_offset |  | 3.0 | 0.0 | 28.1538 (28.1543) | 0.0 3.4109 3.7571 (0.0 3.3984 3.6429) | model |
| `weapon_tec9` | weapon_offset |  | 3.0 | 0.0 | 117.261 (117.2626) | 0.146 2.8093 9.4175 (0.1602 3.2244 9.1577) | model |
| `weapon_fiveseven` | weapon_offset |  | 3.0 | 0.0 | 26.84 (26.8404) | 0.0 5.2178 1.6038 (0.0 5.3169 1.5249) | model |
| `weapon_cz75a` | weapon_offset |  | 3.0 | 0.0 | 55.519 (55.5192) | 0.0 2.4988 4.6588 (0.0 3.0893 4.7147) | model |
| `weapon_deagle` | weapon_offset |  | 4.0 | 0.0 | 68.5308 (68.5315) | 0.0 1.9401 2.457 (0.0 2.0824 1.8445) | model |
| `weapon_revolver` | weapon_offset |  | 4.0 | 0.0 | 73.8203 (73.8216) | 0.0 2.1434 3.7916 (0.0 1.8784 3.2498) | model |
| `weapon_nova` | weapon_offset |  | 4.0 | 0.0 | 245.2492 (245.248) | 0.0 1.8581 -1.6465 (0.0 2.324 2.7655) | model |
| `weapon_xm1014` | weapon_offset |  | 4.0 | 0.0 | 232.63 (232.6326) | 0.0 1.6602 3.0997 (0.0 1.9136 5.6513) | model |
| `weapon_sawedoff` | weapon_offset |  | 4.0 | 0.0 | 130.2082 (130.2103) | 0.0 0.0153 8.7459 (0.0 -0.0485 9.4419) | model |
| `weapon_mag7` | weapon_offset |  | 4.0 | 0.0 | 298.9984 (299.0023) | 0.0 6.48 3.546 (0.0 6.6794 2.2013) | model |
| `weapon_mac10` | weapon_offset |  | 3.5 | 0.0 | 206.8744 (206.8749) | 0.0 0.1477 6.489 (0.0 0.1685 6.7526) | model |
| `weapon_mp9` | weapon_offset |  | 3.5 | 0.0 | 293.5196 (293.5247) | 0.0 2.1867 2.1648 (0.0 1.8058 4.1121) | model |
| `weapon_mp7` | weapon_offset |  | 3.5 | 0.0 | 223.5723 (223.5752) | 0.0 -0.2593 -0.1938 (0.0 -0.7007 -0.3958) | model |
| `weapon_mp5sd` | weapon_offset |  | 3.5 | 0.0 | 384.731 (384.7371) | 0.0 1.4606 7.7876 (0.0 1.3006 6.9268) | model |
| `weapon_ump45` | weapon_offset |  | 3.5 | 0.0 | 451.5926 (451.5986) | 0.0 0.9683 5.8182 (0.0 0.8815 6.2358) | model |
| `weapon_p90` | weapon_offset |  | 3.5 | 0.0 | 236.4375 (236.4404) | 0.0 4.2121 6.3851 (0.0 4.6575 7.1452) | model |
| `weapon_bizon` | weapon_offset |  | 3.5 | 0.0 | 340.5226 (340.5227) | 0.0 0.6206 2.6445 (0.0 0.8633 3.1201) | model |
| `weapon_galilar` | weapon_offset |  | 4.0 | 0.0 | 447.6764 (447.6837) | 0.0 1.2669 8.1188 (0.0 2.0912 10.0251) | model |
| `weapon_famas` | weapon_offset |  | 4.0 | 0.0 | 581.0451 (581.058) | 0.0 1.9618 4.6072 (0.0 2.6987 6.5482) | model |
| `weapon_ak47` | weapon_offset |  | 4.0 | 0.0 | 389.3433 (389.3459) | 0.0 -0.0745 6.2389 (0.0 0.5961 6.1148) | model |
| `weapon_m4a1` | weapon_offset |  | 4.0 | 0.0 | 586.041 (586.038) | -0.0018 10.3597 17.7215 (0.0067 10.7087 21.2185) | model |
| `weapon_m4a1_silencer` | weapon_offset |  | 4.0 | 0.0 | 731.2904 (731.2982) | 0.0 2.857 6.9438 (0.0 3.4078 7.8802) | model |
| `weapon_sg556` | weapon_offset |  | 4.5 | 0.0 | 493.4979 (493.4967) | -0.2184 0.527 1.2784 (-0.2184 1.2933 0.8999) | model |
| `weapon_aug` | weapon_offset |  | 4.5 | 0.0 | 530.5777 (530.5805) | 0.1921 1.3554 0.3658 (0.2434 1.7323 2.865) | model |
| `weapon_m249` | weapon_offset |  | 6.0 | 0.0 | 1949.5574 (1949.5688) | 0.2038 1.3051 6.2451 (0.2466 1.3939 7.1864) | model |
| `weapon_negev` | weapon_offset |  | 6.0 | 0.0 | 1480.5299 (1480.5299) | -0.1167 1.5224 4.2684 (-0.3423 1.1292 4.0182) | model |
| `weapon_ssg08` | weapon_offset |  | 5.0 | 0.0 | 945.9105 (945.9105) | -0.3367 2.99 7.6174 (-0.5138 2.9064 6.6774) | model |
| `weapon_awp` | weapon_offset |  | 5.0 | 0.0 | 661.7095 (661.7) | -0.0049 7.8093 11.843 (0.0428 7.1209 11.7951) | model |
| `weapon_g3sg1` | weapon_offset |  | 5.0 | 0.0 | 668.4562 (668.4636) | 0.0 4.8084 19.7759 (0.0 5.082 22.5041) | model |
| `weapon_scar20` | weapon_offset |  | 5.0 | 0.0 | 647.3555 (647.362) | 0.0 11.342 20.1459 (0.0 11.8681 19.8799) | model |
| `weapon_c4` | weapon_offset |  | 4.0 | 0.0 | 176.4593 (176.4612) | 0.064 -0.23 -0.82 (0.064 -0.23 -0.82) | model |
| `item_defuser` | weapon_hand_r |  | 15.0 | 0.0 | 567.0629 (567.066) | 0.323 0.248 0.2302 (0.3458 -0.0145 -0.3097) | model |
| `weapon_taser` | weapon_offset |  | 3.0 | 0.0 | 76.5739 (76.5749) | 0.0 3.7768 1.8804 (0.0 3.8952 2.8178) | model |
| `weapon_hegrenade` | weapon_offset |  | 3.0 | 0.0 | 56.2381 (56.2377) | 0.0495 -0.032 0.1043 (0.0273 -0.2251 0.1036) | model |
| `weapon_flashbang` | weapon_offset |  | 3.0 | 8.0 | 47.3265 (47.3263) | -0.1951 -0.2718 0.0 (-0.1802 -1.267 0.0) | model |
| `weapon_smokegrenade` | weapon_offset |  | 3.0 | 8.0 | 34.6779 (34.678) | 0.0 -0.6368 0.0 (0.0 -1.2367 0.0) | model |
| `weapon_molotov` | molotov |  | 3.0 | 8.0 | 102.0957 (102.0966) | 0.0 0.1692 0.0 (0.0 -0.3026 0.0) | model |
| `weapon_incgrenade` | weapon_offset |  | 3.0 | 8.0 | 34.6779 (34.678) | 0.0 -0.6368 0.0 (0.0 -1.2367 0.0) | model |
| `weapon_decoy` | weapon_offset |  | 3.0 | 8.0 | 47.3265 (47.3263) | -0.1951 -0.2718 0.0 (-0.1802 -1.267 0.0) | model |
