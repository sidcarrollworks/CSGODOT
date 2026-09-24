# What the game tells the animation graphs

Written by `scripts/animgraph_tables.gd` on 2026-09-23 from CS2 1.41.8.3's animation graphs. Do not edit by hand.

The control parameters are what the game sets on a player's graphs every frame; the graphs do the rest. An ID parameter is a name: Values lists every one the graphs test it for, which is the game's vocabulary for it (an empty one is written (none)). A float's range is for the game's code to say; the blend spaces in `locomotion.json` and the conditions in the layout pages show what values the graphs expect. Graphs names the families that take the parameter (`graphs.md`).

## Third person (`worldmodel`)

| Parameter | Type | Graphs | Values |
|---|---|---|---|
| `action` | ID | worldmodel, worldmodel_grenade, worldmodel_gun, worldmodel_gun_cz75, worldmodel_knife, worldmodel_locomotion | (none), action_attack, action_c4_plant, action_deploy, action_healthshot_inject, action_idle, action_inspect, action_reload, action_silencer_attach, action_silencer_detach |
| `action_reset` | Bool | worldmodel, worldmodel_grenade, worldmodel_gun, worldmodel_knife | - |
| `aim_angle_pitch` | Float | worldmodel | - |
| `aim_angle_yaw` | Float | worldmodel | - |
| `air_action` | ID | worldmodel, worldmodel_locomotion | air_action_jump, air_action_land, air_action_start_fall |
| `air_height_above_ground` | Float | worldmodel, worldmodel_locomotion | - |
| `attack_is_final_bullets` | Bool | worldmodel | - |
| `attack_throw_strength` | Float | worldmodel, worldmodel_grenade | - |
| `attack_type` | ID | worldmodel, worldmodel_grenade, worldmodel_knife | attack_grenade_charge, attack_grenade_ready, attack_grenade_throw, attack_gun_charge, attack_gun_primaryfire, attack_gun_secondaryfire, attack_knife_heavybackstab, attack_knife_heavyhit, attack_knife_heavymiss, attack_knife_lightbackstab, attack_knife_lighthit, attack_knife_lightmiss |
| `attack_variation` | Float | worldmodel | - |
| `deploy_variation` | Float | worldmodel, worldmodel_gun, worldmodel_knife | - |
| `flashed_amount` | Float | worldmodel | - |
| `flinch_body_restart` | Bool | worldmodel | - |
| `flinch_body_type` | ID | worldmodel | (none), flinch_body_arm_left, flinch_body_arm_right, flinch_body_chest_east, flinch_body_chest_north, flinch_body_chest_south, flinch_body_chest_west, flinch_body_leg_left, flinch_body_leg_right, flinch_body_stomach_north, flinch_body_stomach_south |
| `flinch_head_restart` | Bool | worldmodel | - |
| `flinch_head_type` | ID | worldmodel | (none), flinch_head_east, flinch_head_north, flinch_head_south, flinch_head_west |
| `flinch_is_on_fire` | Bool | worldmodel | - |
| `ground_action` | ID | worldmodel, worldmodel_locomotion | ground_action_idle, ground_action_move, ground_action_plant_and_turn, ground_action_start, ground_action_turn_on_spot, ground_action_turn_on_spot_loop |
| `ground_action_direction_id` | ID | worldmodel, worldmodel_locomotion | E, N, NE, NW, S, SE, SW, W |
| `ground_turn_angle_or_velocity` | Float | worldmodel, worldmodel_locomotion | - |
| `idle_variation` | Float | worldmodel | - |
| `ik_left_foot` | Target | worldmodel | - |
| `ik_right_foot` | Target | worldmodel | - |
| `is_defusing` | Bool | worldmodel, worldmodel_grenade, worldmodel_gun, worldmodel_knife | - |
| `ladder_angle_yaw` | Float | worldmodel, worldmodel_locomotion | - |
| `ladder_angle_yaw_backwards` | Float | worldmodel, worldmodel_locomotion | - |
| `ladder_cycle` | Float | worldmodel, worldmodel_locomotion | - |
| `move_crouch_amount` | Float | worldmodel, worldmodel_grenade, worldmodel_gun, worldmodel_gun_cz75, worldmodel_locomotion | - |
| `move_crouch_amount_eased` | Float | worldmodel_knife, worldmodel_locomotion | - |
| `move_direction_id` | ID | worldmodel, worldmodel_locomotion | E, N, NE, NW, S, SE, SW, W |
| `move_is_walking` | Bool | worldmodel, worldmodel_locomotion | - |
| `move_speed_horizontal` | Float | worldmodel, worldmodel_locomotion | - |
| `move_speed_horizontal_previous` | Float | worldmodel, worldmodel_locomotion | - |
| `move_speed_x` | Float | worldmodel, worldmodel_locomotion | - |
| `move_speed_y` | Float | worldmodel, worldmodel_locomotion | - |
| `move_type` | ID | worldmodel, worldmodel_locomotion | move_type_air, move_type_ground, move_type_jump, move_type_ladder |
| `reload_stage` | ID | worldmodel, worldmodel_gun, worldmodel_gun_cz75 | stage_outro |
| `weapon_action_speedscale` | Float | worldmodel | - |
| `weapon_ammo` | Float | worldmodel, worldmodel_gun, worldmodel_gun_cz75 | - |
| `weapon_ammo_max` | Float | worldmodel | - |
| `weapon_ammo_reserve` | Float | worldmodel | - |
| `weapon_category` | ID | worldmodel, worldmodel_knife | weapon_category_equipment, weapon_category_grenade, weapon_category_knife, weapon_category_machinegun, weapon_category_pistol, weapon_category_rifle, weapon_category_shotgun, weapon_category_smg, weapon_category_sniper |
| `weapon_drop_amount` | Float | worldmodel | - |
| `weapon_extra_info` | ID | worldmodel, worldmodel_gun_cz75 | weapon_cz75_front_mag_removed |
| `weapon_ironsight_amount` | Float | worldmodel | - |
| `weapon_is_legacy_model` | Bool | worldmodel | - |
| `weapon_is_silenced` | Bool | worldmodel | - |
| `weapon_type` | ID | worldmodel, worldmodel_grenade, worldmodel_gun, worldmodel_gun_cz75, worldmodel_knife | (none), weapon_ak47, weapon_aug, weapon_awp, weapon_bayonet, weapon_bizon, weapon_c4, weapon_cz75a, weapon_deagle, weapon_decoy, weapon_elite, weapon_famas, weapon_fiveseven, weapon_flashbang, weapon_g3sg1, weapon_galilar, weapon_glock, weapon_healthshot, weapon_hegrenade, weapon_hkp2000, weapon_incgrenade, weapon_knife, weapon_knife_butterfly, weapon_knife_canis, weapon_knife_cord, weapon_knife_css, weapon_knife_falchion, weapon_knife_flip, weapon_knife_gut, weapon_knife_gypsy_jackknife, weapon_knife_karambit, weapon_knife_kukri, weapon_knife_m9_bayonet, weapon_knife_outdoor, weapon_knife_push, weapon_knife_skeleton, weapon_knife_stiletto, weapon_knife_survival_bowie, weapon_knife_t, weapon_knife_tactical, weapon_knife_ursus, weapon_knife_widowmaker, weapon_m249, weapon_m4a1, weapon_m4a1_silencer, weapon_mac10, weapon_mag7, weapon_molotov, weapon_mp5sd, weapon_mp7, weapon_mp9, weapon_negev, weapon_nova, weapon_p250, weapon_p90, weapon_revolver, weapon_sawedoff, weapon_scar20, weapon_sg556, weapon_smokegrenade, weapon_ssg08, weapon_taser, weapon_tec9, weapon_temp, weapon_ump45, weapon_usp_silencer, weapon_xm1014 |

Computed by the graphs themselves (virtual parameters), from the others:

| Parameter | Graph | Is |
|---|---|---|
| `attack_is_knife` | `worldmodel` | action is action_attack and weapon_category is weapon_category_knife |
| `attack_is_gun` | `worldmodel` | action is action_attack and weapon_category is one of weapon_category_pistol, weapon_category_machinegun, weapon_category_rifle, weapon_category_shotgun, weapon_category_smg, weapon_category_sniper |
| `attack_shoot_reset` | `worldmodel` | action_reset and attack_is_gun |
| `locomotion_knife` | `worldmodel` | weapon_category is one of weapon_category_grenade, weapon_category_knife or weapon_type is weapon_healthshot |
| `locomotion_pistol` | `worldmodel` | weapon_category is weapon_category_pistol or weapon_type is weapon_c4 |
| `locomotion_rifle` | `worldmodel` | weapon_category is one of weapon_category_machinegun, weapon_category_rifle, weapon_category_shotgun, weapon_category_smg, weapon_category_sniper |
| `UpperBodyMask` | `worldmodel` | by move_type, move_type_ladder: mask UpperBody_Ladder, else mask UpperBody |
| `move_crouch_amount_eased` | `worldmodel` | move_crouch_amount eased over 0.2 s |
| `weapon_has_front_mag_removed` | `worldmodel_gun_cz75` | weapon_extra_info is weapon_cz75_front_mag_removed |
| `attack_is_knife` | `worldmodel_knife` | action is action_attack and weapon_category is weapon_category_knife |
| `is_medium_speed` | `worldmodel_locomotion` | move_speed_horizontal_previous in 80 to 170 |
| `is_low_speed` | `worldmodel_locomotion` | move_speed_horizontal_previous < 80 |
| `is_high_speed` | `worldmodel_locomotion` | move_speed_horizontal_previous > 170 |

## First person (`viewmodel`)

| Parameter | Type | Graphs | Values |
|---|---|---|---|
| `action` | ID | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver, viewmodel_inspects, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | (none), action_attack, action_c4_plant, action_deploy, action_healthshot_inject, action_idle, action_inspect, action_reload, action_silencer_attach, action_silencer_detach, action_ui_keychain |
| `action_reset` | Bool | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver, viewmodel_inspects, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | - |
| `attack_throw_strength` | Float | viewmodel, viewmodel_grenade | - |
| `attack_type` | ID | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_gun_elites, viewmodel_gun_revolver, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | attack_grenade_charge, attack_grenade_ready, attack_grenade_throw, attack_gun_charge, attack_gun_dryfire, attack_gun_primaryfire, attack_gun_secondaryfire, attack_knife_heavybackstab, attack_knife_heavyhit, attack_knife_heavymiss, attack_knife_lightbackstab, attack_knife_lighthit, attack_knife_lightmiss |
| `attack_variation` | Float | viewmodel, viewmodel_gun_revolver, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | - |
| `deploy_variation` | Float | viewmodel, viewmodel_gun, viewmodel_gun_revolver, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | - |
| `idle_variation` | Float | viewmodel, viewmodel_gun, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | - |
| `inspect_extra_info` | ID | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver, viewmodel_inspects, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | inspect_should_loop |
| `inspect_variation` | Float | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver, viewmodel_inspects, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | - |
| `reload_stage` | ID | viewmodel, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver | stage_outro |
| `weapon_action_speedscale` | Float | viewmodel | - |
| `weapon_ammo` | Float | viewmodel, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver | - |
| `weapon_ammo_max` | Float | viewmodel, viewmodel_gun | - |
| `weapon_ammo_reserve` | Float | viewmodel, viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites | - |
| `weapon_category` | ID | viewmodel, viewmodel_grenade, viewmodel_gun, viewmodel_knife, viewmodel_knife_butterfly, viewmodel_knife_karambit, viewmodel_knife_talon | weapon_category_equipment, weapon_category_grenade, weapon_category_knife, weapon_category_machinegun, weapon_category_pistol, weapon_category_rifle, weapon_category_shotgun, weapon_category_smg, weapon_category_sniper |
| `weapon_extra_info` | ID | viewmodel, viewmodel_gun_cz75 | weapon_cz75_front_mag_removed |
| `weapon_ironsight_amount` | Float | viewmodel, viewmodel_gun | - |
| `weapon_is_gun` | Bool | viewmodel_gun, viewmodel_gun_cz75, viewmodel_gun_elites, viewmodel_gun_revolver | - |
| `weapon_is_legacy_model` | Bool | viewmodel | - |
| `weapon_is_silenced` | Bool | viewmodel, viewmodel_gun | - |
| `weapon_type` | ID | viewmodel, viewmodel_gun, viewmodel_knife | weapon_ak47, weapon_aug, weapon_awp, weapon_bayonet, weapon_bizon, weapon_c4, weapon_cz75a, weapon_deagle, weapon_decoy, weapon_elite, weapon_famas, weapon_fiveseven, weapon_flashbang, weapon_g3sg1, weapon_galilar, weapon_glock, weapon_healthshot, weapon_hegrenade, weapon_hkp2000, weapon_incgrenade, weapon_knife, weapon_knife_butterfly, weapon_knife_canis, weapon_knife_cord, weapon_knife_css, weapon_knife_falchion, weapon_knife_flip, weapon_knife_gut, weapon_knife_gypsy_jackknife, weapon_knife_karambit, weapon_knife_kukri, weapon_knife_m9_bayonet, weapon_knife_outdoor, weapon_knife_push, weapon_knife_skeleton, weapon_knife_stiletto, weapon_knife_survival_bowie, weapon_knife_t, weapon_knife_tactical, weapon_knife_ursus, weapon_knife_widowmaker, weapon_m249, weapon_m4a1, weapon_m4a1_silencer, weapon_mac10, weapon_mag7, weapon_molotov, weapon_mp5sd, weapon_mp7, weapon_mp9, weapon_negev, weapon_nova, weapon_p250, weapon_p90, weapon_revolver, weapon_sawedoff, weapon_scar20, weapon_sg556, weapon_smokegrenade, weapon_ssg08, weapon_taser, weapon_tec9, weapon_temp, weapon_ump45, weapon_usp_silencer, weapon_xm1014 |

Computed by the graphs themselves (virtual parameters), from the others:

| Parameter | Graph | Is |
|---|---|---|
| `weapon_is_gun` | `viewmodel` | weapon_category is none of weapon_category_knife, weapon_category_grenade, weapon_category_equipment |
| `attack_shoot_reset` | `viewmodel_gun` | action_reset and action is action_attack |
| `weapon_is_using_ironsights` | `viewmodel_gun` | weapon_type is one of weapon_sg556, weapon_aug, weapon_temp and weapon_ironsight_amount >= 0.1 |
| `weapon_ammo_reload_count` | `viewmodel_gun` | (weapon_ammo_max - weapon_ammo) |
| `attack_shoot_reset` | `viewmodel_gun_cz75` | action_reset and action is action_attack |
| `weapon_has_front_mag_removed` | `viewmodel_gun_cz75` | weapon_extra_info is weapon_cz75_front_mag_removed |
| `attack_is_final_bullets` | `viewmodel_gun_elites` | weapon_ammo <= 1 |
| `attack_shoot_reset` | `viewmodel_gun_elites` | action_reset and action is action_attack |
| `attack_shoot_reset` | `viewmodel_gun_revolver` | action_reset and action is action_attack |
