# The third-person graph

Written by `scripts/animgraph_tables.gd` on 2026-09-23 from `animation/graphs/worldmodel/worldmodel.vnmgraph_c` in CS2 1.41.8.3. Do not edit by hand; `reference/animgraph2.md` says how to read it.

The player as the others see them: `worldmodel.vnmgraph`, over the world rig (`animation/skeletons/characters/worldmodel.vnmskel`). It runs the locomotion (`locomotion.md`) and the weapon graphs through graph slots, so its own states name which graph plays rather than clips.

Each node is named by its path in Valve's editor. Conditions are written out with the parameters by name (`parameters.md` has their values); a transition's blend is its length, then its easing and options where they are not the plain ones. (options is Esoterica's transition-option bit field, which Valve's version orders its own way.)

## From the root

1. `SnapWeapon` Snap Weapon (FlashedAmount: flashed_amount; WeaponCategory: weapon_category; WeaponType: weapon_type)
2. `LayerBlend` Layer Blend
3. `AimCS` Aim IK (VerticalAngle: aim_angle_pitch; HorizontalAngle: aim_angle_yaw; WeaponCategory: weapon_category; WeaponType: weapon_type; WeaponAction: action; WeaponDrop: weapon_drop_amount; IsDefusing: is_defusing; CrouchWeight: move_crouch_amount; HandIKBlendInTimeSeconds: 0.3; ActionBlendTimeSeconds: 0.4; PlantingBlendTimeSeconds: 0.2)
4. `FootIK` Foot IK (leftEffectorBoneID: ankle_L; rightEffectorBoneID: ankle_R; LeftTarget: ik_left_foot; RightTarget: ik_right_foot; BlendTimeSeconds: 0.0)
5. `LayerBlend` Layer Blend
6. `StateMachine` SM0

## Layers

`Layer Blend`, over AimCS over FootIK over state machine SM0 (2 states), with 7 layers:

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `flashed` | state machine flashed (2 states) | the state's | - | ModelSpace | no |

`Layer Blend`, over state machine SM0 (2 states):

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `Weapons` | state machine Weapons (1 states) | the state's | - | ModelSpace | no |
| `Defuse` | state machine Defuse (2 states) | the state's | - | ModelSpace | no |
| `BodyAdditives` | state machine BodyAdditives (4 states) | the state's | - | Additive | no |
| `Weapon Shoot` | state machine Weapon Shoot (7 states) | the state's | - | Additive | no |
| `BodyFlinch` | state machine BodyFlinch (3 states) | the state's | - | Additive | no |
| `HeadFlinch` | state machine HeadFlinch (3 states) | the state's | - | Additive | no |
| `FireFlinch` | state machine FireFlinch (3 states) | the state's | - | Additive | no |

`SM0/Locomotion/Layer Blend`, over state machine SM0/Locomotion/locomotion (3 states):

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `SM0/Locomotion/Idle Poses` | state machine SM0/Locomotion/Idle Poses (9 states) | the state's | - | Additive | no |

`SM0/Planting/SM/Planting0/Layer Blend`, over a 1D blend on move_crouch_amount (held from the state's entry) of planting at 0, planting_crouch at 1:

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `SM0/Planting/SM/Planting0/SM0` | state machine SM0/Planting/SM/Planting0/SM0 (2 states) | the state's | - | Additive | no |

`Weapon Shoot/Pistols/SM/Elites/Layer Blend`, over state machine Weapon Shoot/Pistols/SM/Elites/Left (2 states):

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `Weapon Shoot/Pistols/SM/Elites/Right` | state machine Weapon Shoot/Pistols/SM/Elites/Right (2 states) | the state's | - | Overlay | no |


## State machines (62)

### `SM0`

Starts in Locomotion.

| State | Plays | Goes to |
|---|---|---|
| Locomotion (starts here when not (action is action_c4_plant)) | state machine SM0/Locomotion/locomotion (3 states), with 1 layers | Planting when action is action_c4_plant (0.1 s) |
| Planting (starts here when action is action_c4_plant) | state machine SM0/Planting/SM (1 states) | Locomotion when not (action is action_c4_plant) (0.1 s) |

### `SM0/Locomotion/locomotion`

Starts in knives.

| State | Plays | Goes to |
|---|---|---|
| knives (starts here when not (action is action_deploy) and locomotion_knife) | the worldmodel_locomotion graph (knife) | - |
| pistols (starts here when not (action is action_deploy) and locomotion_pistol) | the worldmodel_locomotion graph (pistol) | - |
| rifles (starts here when not (action is action_deploy) and locomotion_rifle) | the worldmodel_locomotion graph (rifle) | - |

From more than one state:

- to pistols when (is_defusing or not (action is action_deploy)) and locomotion_pistol (0 s, options 88), from any state
- to rifles when (is_defusing or not (action is action_deploy)) and locomotion_rifle (0 s, options 88), from any state
- to knives when (is_defusing or not (action is action_deploy)) and locomotion_knife (0 s, options 88), from any state

### `SM0/Locomotion/Idle Poses`

Starts in Equipment.

| State | Plays | Goes to |
|---|---|---|
| Equipment (starts here when weapon_category is weapon_category_equipment) | state machine SM0/Locomotion/Idle Poses/Equipment/SM (2 states) | - |
| SniperRifles (starts here when weapon_category is weapon_category_sniper) | state machine SM0/Locomotion/Idle Poses/SniperRifles/SM (4 states) | - |
| Grenades (starts here when weapon_category is weapon_category_grenade) | state machine SM0/Locomotion/Idle Poses/Grenades/SM (2 states) | - |
| MG (starts here when weapon_category is weapon_category_machinegun) | state machine SM0/Locomotion/Idle Poses/MG/SM (2 states) | - |
| Shotguns (starts here when weapon_category is weapon_category_shotgun) | state machine SM0/Locomotion/Idle Poses/Shotguns/SM (4 states) | - |
| SMG (starts here when weapon_category is weapon_category_smg) | state machine SM0/Locomotion/Idle Poses/SMG/SM (7 states) | - |
| Rifles (starts here when weapon_category is weapon_category_rifle) | state machine SM0/Locomotion/Idle Poses/Rifles/SM (8 states) | - |
| Knives (starts here when weapon_category is weapon_category_knife) | state machine SM0/Locomotion/Idle Poses/Knives/SM (22 states) | - |
| Pistols (starts here when weapon_category is weapon_category_pistol) | state machine SM0/Locomotion/Idle Poses/Pistols/SM (11 states) | - |

From more than one state:

- to SniperRifles when weapon_category is weapon_category_sniper (0.2 s), from any state
- to Grenades when weapon_category is weapon_category_grenade (0.2 s), from any state
- to MG when weapon_category is weapon_category_machinegun (0.2 s), from any state
- to Shotguns when weapon_category is weapon_category_shotgun (0.2 s), from any state
- to SMG when weapon_category is weapon_category_smg (0.2 s), from any state
- to Rifles when weapon_category is weapon_category_rifle (0.2 s), from any state
- to Knives when weapon_category is weapon_category_knife (0.2 s), from any state
- to Pistols when weapon_category is weapon_category_pistol (0.5 s), from any state
- to Equipment when weapon_category is weapon_category_equipment (0.2 s), from any state

### `SM0/Locomotion/Idle Poses/Equipment/SM`

Starts in HealthShot.

| State | Plays | Goes to |
|---|---|---|
| HealthShot (starts here when weapon_type is weapon_healthshot) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_healthshot at 0, idle_crouch_healthshot at 1 | C4 when weapon_type is weapon_c4 (0 s) |
| C4 (starts here when weapon_type is weapon_c4) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_c4 at 0, idle_crouch_c4 at 1 | HealthShot when weapon_type is weapon_healthshot (0 s) |

### `SM0/Locomotion/Idle Poses/SniperRifles/SM`

Starts in AWP.

| State | Plays | Goes to |
|---|---|---|
| AWP (starts here when weapon_type is weapon_awp) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_awp at 0, idle_crouch_awp at 1 | - |
| SSG08 (starts here when weapon_type is weapon_ssg08) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_ssg08 at 0, idle_crouch_ssg08 at 1 | - |
| G3SG1 (starts here when weapon_type is weapon_g3sg1) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_g3sg1 at 0, idle_crouch_g3sg1 at 1 | - |
| SCAR20 (starts here when weapon_type is weapon_scar20) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_scar20 at 0, idle_crouch_scar20 at 1 | - |

From more than one state:

- to SSG08 when weapon_type is weapon_ssg08 (0 s), from any state
- to G3SG1 when weapon_type is weapon_g3sg1 (0 s), from any state
- to SCAR20 when weapon_type is weapon_scar20 (0 s), from any state
- to AWP when weapon_type is weapon_awp (0 s), from any state

### `SM0/Locomotion/Idle Poses/Grenades/SM`

Starts in Grenades.

| State | Plays | Goes to |
|---|---|---|
| Grenades (starts here when weapon_type is one of weapon_decoy, weapon_hegrenade, weapon_smokegrenade, weapon_incgrenade, weapon_flashbang, (none)) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_grenade at 0, idle_crouch_grenade at 1 | Molotov when weapon_type is weapon_molotov (0 s) |
| Molotov (starts here when weapon_type is weapon_molotov) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_molotov at 0, idle_crouch_molotov at 1 | Grenades when weapon_type is one of weapon_decoy, weapon_hegrenade, weapon_smokegrenade, weapon_incgrenade, weapon_flashbang, (none) (0 s) |

### `SM0/Locomotion/Idle Poses/MG/SM`

Starts in M249.

| State | Plays | Goes to |
|---|---|---|
| M249 (starts here when weapon_type is weapon_m249) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_m249 at 0, idle_crouch_m249 at 1 | Negev when weapon_type is weapon_negev (0 s) |
| Negev (starts here when weapon_type is weapon_negev) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_negev at 0, idle_crouch_negev at 1 | M249 when weapon_type is weapon_m249 (0 s) |

### `SM0/Locomotion/Idle Poses/Shotguns/SM`

Starts in Nova.

| State | Plays | Goes to |
|---|---|---|
| Nova (starts here when weapon_type is weapon_nova) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_nova at 0, idle_crouch_nova at 1 | - |
| XM1014 (starts here when weapon_type is weapon_xm1014) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_xm1014 at 0, idle_crouch_xm1014 at 1 | - |
| SawedOff (starts here when weapon_type is weapon_sawedoff) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_sawedoff at 0, idle_crouch_sawedoff at 1 | - |
| MAG7 (starts here when weapon_type is weapon_mag7) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_mag7 at 0, idle_crouch_mag7 at 1 | - |

From more than one state:

- to XM1014 when weapon_type is weapon_xm1014 (0 s), from any state
- to SawedOff when weapon_type is weapon_sawedoff (0 s), from any state
- to MAG7 when weapon_type is weapon_mag7 (0 s), from any state
- to Nova when weapon_type is weapon_nova (0 s), from any state

### `SM0/Locomotion/Idle Poses/SMG/SM`

Starts in MP7.

| State | Plays | Goes to |
|---|---|---|
| MP7 (starts here when weapon_type is weapon_mp7) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_mp7 at 0, idle_crouch_mp7 at 1 | - |
| MP9 (starts here when weapon_type is weapon_mp9) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_mp9 at 0, idle_crouch_mp9 at 1 | - |
| MP5SD (starts here when weapon_type is weapon_mp5sd) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_mp5sd at 0, idle_crouch_mp5sd at 1 | - |
| MAC10 (starts here when weapon_type is weapon_mac10) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_mac10 at 0, idle_crouch_mac10 at 1 | - |
| p90 (starts here when weapon_type is weapon_p90) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_p90 at 0, idle_crouch_p90 at 1 | - |
| Bizon (starts here when weapon_type is weapon_bizon) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_bizon at 0, idle_crouch_bizon at 1 | - |
| ump45 (starts here when weapon_type is weapon_ump45) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_ump45 at 0, idle_crouch_ump45 at 1 | - |

From more than one state:

- to MP9 when weapon_type is weapon_mp9 (0 s), from any state
- to MP5SD when weapon_type is weapon_mp5sd (0 s), from any state
- to MAC10 when weapon_type is weapon_mac10 (0 s), from any state
- to p90 when weapon_type is weapon_p90 (0 s), from any state
- to Bizon when weapon_type is weapon_bizon (0 s), from any state
- to ump45 when weapon_type is weapon_ump45 (0 s), from any state
- to MP7 when weapon_type is weapon_mp7 (0 s), from any state

### `SM0/Locomotion/Idle Poses/Rifles/SM`

Starts in AK.

| State | Plays | Goes to |
|---|---|---|
| AK (starts here when weapon_type is weapon_ak47) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_ak at 0, idle_crouch_ak at 1 | - |
| M4A1S (starts here when weapon_type is weapon_m4a1_silencer) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_m4a1s at 0, idle_m4a1s at 1 | - |
| SG556 (starts here when weapon_type is weapon_sg556) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_sg556 at 0, idle_crouch_sg556 at 1 | - |
| AUG (starts here when weapon_type is weapon_aug) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_aug at 0, idle_crouch_aug at 1 | - |
| GALIL (starts here when weapon_type is weapon_galilar) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_galilar at 0, idle_crouch_galilar at 1 | - |
| M4A4 (starts here when weapon_type is weapon_m4a1) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_m4a4 at 0, idle_crouch_m4a4 at 1 | - |
| FAMAS (starts here when weapon_type is weapon_famas) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_famas at 0, idle_crouch_famas at 1 | - |
| TEMP (starts here when weapon_type is weapon_temp) | a 1D blend on move_crouch_amount eased over 0.2 s of idle at 0, idle_crouch at 1 | - |

From more than one state:

- to M4A1S when weapon_type is weapon_m4a1_silencer (0 s), from any state
- to SG556 when weapon_type is weapon_sg556 (0 s), from any state
- to AUG when weapon_type is weapon_aug (0 s), from any state
- to GALIL when weapon_type is weapon_galilar (0 s), from any state
- to M4A4 when weapon_type is weapon_m4a1 (0 s), from any state
- to FAMAS when weapon_type is weapon_famas (0 s), from any state
- to TEMP when weapon_type is weapon_temp (0.2 s), from any state
- to AK when weapon_type is weapon_ak47 (0 s), from any state

### `SM0/Locomotion/Idle Poses/Knives/SM`

Starts in Default_CT.

| State | Plays | Goes to |
|---|---|---|
| Default_CT (starts here when weapon_type is weapon_knife) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_default_ct at 0, idle_crouch_default_ct at 1 | - |
| Default_T (starts here when weapon_type is weapon_knife_t) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_default_t at 0, idle_crouch_default_t at 1 | - |
| Bayonet (starts here when weapon_type is weapon_bayonet) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_bayonet at 0, idle_crouch_bayonet at 1 | - |
| Bowie (starts here when weapon_type is weapon_knife_survival_bowie) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_bowie at 0, idle_crouch_bowie at 1 | - |
| Butterfly (starts here when weapon_type is weapon_knife_butterfly) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_butterfly at 0, idle_crouch_butterfly at 1 | - |
| CSS (starts here when weapon_type is weapon_knife_css) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_css at 0, idle_crouch_css at 1 | - |
| m9 (starts here when weapon_type is weapon_knife_m9_bayonet) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_m9 at 0, idle_crouch_m9 at 1 | - |
| Gut (starts here when weapon_type is weapon_knife_gut) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_gut at 0, idle_crouch_gut at 1 | - |
| Tactical (starts here when weapon_type is weapon_knife_tactical) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_tactical at 0, idle_crouch_tactical at 1 | - |
| Flip (starts here when weapon_type is weapon_knife_flip) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_flip at 0, idle_crouch_flip at 1 | - |
| Navaja (starts here when weapon_type is weapon_knife_gypsy_jackknife) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_navaja at 0, idle_crouch_navaja at 1 | - |
| Falchion (starts here when weapon_type is weapon_knife_falchion) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_falchion at 0, idle_crouch_falchion at 1 | - |
| Canis (starts here when weapon_type is weapon_knife_canis) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_canis at 0, idle_crouch_canis at 1 | - |
| Talon (starts here when weapon_type is weapon_knife_widowmaker) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_talon at 0, idle_crouch_talon at 1 | - |
| Push (starts here when weapon_type is weapon_knife_push) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_push at 0, idle_crouch_push at 1 | - |
| Cord (starts here when weapon_type is weapon_knife_cord) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_cord at 0, idle_crouch_cord at 1 | - |
| Outdoor (starts here when weapon_type is weapon_knife_outdoor) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_outdoor at 0, idle_crouch_outdoor at 1 | - |
| Skeleton (starts here when weapon_type is weapon_knife_skeleton) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_skeleton at 0, idle_crouch_skeleton at 1 | - |
| Stiletto (starts here when weapon_type is weapon_knife_stiletto) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_stiletto at 0, idle_crouch_stiletto at 1 | - |
| Ursus (starts here when weapon_type is weapon_knife_ursus) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_ursus at 0, idle_crouch_ursus at 1 | - |
| Kukri (starts here when weapon_type is weapon_knife_kukri) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_kukri at 0, idle_crouch_kukri at 1 | - |
| Karambit (starts here when weapon_type is weapon_knife_karambit) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_karambit at 0, idle_crouch_karambit at 1 | - |

From more than one state:

- to Default_T when weapon_type is weapon_knife_t (0 s), from any state
- to Bayonet when weapon_type is weapon_bayonet (0 s), from any state
- to Bowie when weapon_type is weapon_knife_survival_bowie (0 s), from any state
- to Butterfly when weapon_type is weapon_knife_butterfly (0 s), from any state
- to CSS when weapon_type is weapon_knife_css (0 s), from any state
- to m9 when weapon_type is weapon_knife_m9_bayonet (0 s), from any state
- to Gut when weapon_type is weapon_knife_gut (0 s), from any state
- to Tactical when weapon_type is weapon_knife_tactical (0 s), from any state
- to Flip when weapon_type is weapon_knife_flip (0 s), from any state
- to Navaja when weapon_type is weapon_knife_gypsy_jackknife (0 s), from any state
- to Falchion when weapon_type is weapon_knife_falchion (0 s), from any state
- to Canis when weapon_type is weapon_knife_canis (0 s), from any state
- to Talon when weapon_type is weapon_knife_widowmaker (0 s), from any state
- to Push when weapon_type is weapon_knife_push (0 s), from any state
- to Cord when weapon_type is weapon_knife_cord (0 s), from any state
- to Outdoor when weapon_type is weapon_knife_outdoor (0 s), from any state
- to Skeleton when weapon_type is weapon_knife_skeleton (0 s), from any state
- to Stiletto when weapon_type is weapon_knife_stiletto (0 s), from any state
- to Ursus when weapon_type is weapon_knife_ursus (0 s), from any state
- to Kukri when weapon_type is weapon_knife_kukri (0 s), from any state
- to Karambit when weapon_type is weapon_knife_karambit (0 s), from any state
- to Default_CT when weapon_type is weapon_knife (0 s), from any state

### `SM0/Locomotion/Idle Poses/Pistols/SM`

Starts in USP.

| State | Plays | Goes to |
|---|---|---|
| Revolver (starts here when weapon_type is weapon_revolver) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_revolver at 0, idle_crouch_revolver at 1 | - |
| USP (starts here when weapon_type is weapon_usp_silencer) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_usp at 0, idle_crouch_usp at 1 | - |
| Glock (starts here when weapon_type is weapon_glock) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_glock at 0, idle_crouch_glock at 1 | - |
| CZ75 (starts here when weapon_type is weapon_cz75a) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_cz75a at 0, idle_crouch_cz75a at 1 | - |
| Elites (starts here when weapon_type is weapon_elite) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_elite at 0, idle_crouch_elite at 1 | - |
| P2000 (starts here when weapon_type is weapon_hkp2000) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_hkp at 0, idle_crouch_hkp at 1 | - |
| TEC9 (starts here when weapon_type is weapon_tec9) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_tec9 at 0, idle_crouch_tec9 at 1 | - |
| FiveSeven (starts here when weapon_type is weapon_fiveseven) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_fiveseven at 0, idle_crouch_fiveseven at 1 | - |
| Taser (starts here when weapon_type is weapon_taser) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_taser at 0, idle_crouch_taser at 1 | - |
| P250 (starts here when weapon_type is weapon_p250) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_p250 at 0, idle_crouch_p250 at 1 | - |
| Deagle (starts here when weapon_type is weapon_deagle) | a 1D blend on move_crouch_amount eased over 0.2 s of idle_deagle at 0, idle_crouch_deagle at 1 | - |

From more than one state:

- to USP when weapon_type is weapon_usp_silencer (0 s), from any state
- to Glock when weapon_type is weapon_glock (0 s), from any state
- to CZ75 when weapon_type is weapon_cz75a (0 s), from any state
- to Elites when weapon_type is weapon_elite (0 s), from any state
- to P2000 when weapon_type is weapon_hkp2000 (0 s), from any state
- to TEC9 when weapon_type is weapon_tec9 (0 s), from any state
- to FiveSeven when weapon_type is weapon_fiveseven (0 s), from any state
- to Taser when weapon_type is weapon_taser (0 s), from any state
- to P250 when weapon_type is weapon_p250 (0 s), from any state
- to Deagle when weapon_type is weapon_deagle (0 s), from any state
- to Revolver when weapon_type is weapon_revolver (0 s), from any state

### `SM0/Planting/SM`

Starts in Planting0.

| State | Plays | Goes to |
|---|---|---|
| Planting0 | a 1D blend on move_crouch_amount (held from the state's entry) of planting at 0, planting_crouch at 1, with 1 layers | - |

### `SM0/Planting/SM/Planting0/SM0`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| TurnOnSpot | a 1D blend on ground_turn_angle_or_velocity of turn_right_loop_180_c4 at -600, turn_right_loop_180_c4 at -300, turn_right_loop_90_c4 at -150, turn_right_loop_45_c4 at -75, turn_idle_loop_c4 at -7, turn_idle_loop_c4 at 0, turn_idle_loop_c4 at 7, turn_left_loop_45_c4 at 75, turn_left_loop_90_c4 at 150, turn_left_loop_180_c4 at 300, turn_left_loop_180_c4 at 600 | Off when not (event WPN_C4_ALLOW_TURN) (0.1 s) |
| Off |   | TurnOnSpot when event WPN_C4_ALLOW_TURN (0.1 s) |

### `Weapons`

Starts in State.

| State | Plays | Goes to |
|---|---|---|
| State | state machine Weapons/State/Weapons (9 states), at weapon_action_speedscale times the speed | - |

### `Weapons/State/Weapons`

Starts in Equipment.

| State | Plays | Goes to |
|---|---|---|
| Equipment (starts here when weapon_category is weapon_category_equipment) | state machine Weapons/State/Weapons/Equipment/SM (2 states) | - |
| SniperRifles (starts here when weapon_category is weapon_category_sniper) | state machine Weapons/State/Weapons/SniperRifles/SM (4 states) | - |
| Grenades (starts here when weapon_category is weapon_category_grenade) | state machine Weapons/State/Weapons/Grenades/SM (6 states) | - |
| MG (starts here when weapon_category is weapon_category_machinegun) | state machine Weapons/State/Weapons/MG/SM (2 states) | - |
| Shotguns (starts here when weapon_category is weapon_category_shotgun) | state machine Weapons/State/Weapons/Shotguns/SM (4 states) | - |
| SMG (starts here when weapon_category is weapon_category_smg) | state machine Weapons/State/Weapons/SMG/SM (7 states) | - |
| Rifles (starts here when weapon_category is weapon_category_rifle) | state machine Weapons/State/Weapons/Rifles/SM (8 states) | - |
| Knives (starts here when weapon_category is weapon_category_knife) | state machine Weapons/State/Weapons/Knives/SM (22 states) | - |
| Pistols (starts here when weapon_category is weapon_category_pistol) | state machine Weapons/State/Weapons/Pistols/SM (11 states) | - |

From more than one state:

- to SniperRifles when weapon_category is weapon_category_sniper (0.1 s), from any state
- to Grenades when weapon_category is weapon_category_grenade (0.1 s), from any state
- to MG when weapon_category is weapon_category_machinegun (0.1 s), from any state
- to Shotguns when weapon_category is weapon_category_shotgun (0.1 s), from any state
- to SMG when weapon_category is weapon_category_smg (0.1 s), from any state
- to Rifles when weapon_category is weapon_category_rifle (0.1 s), from any state
- to Knives when weapon_category is weapon_category_knife (0.1 s), from any state
- to Pistols when weapon_category is weapon_category_pistol (0.1 s), from any state
- to Equipment when weapon_category is weapon_category_equipment (0.1 s), from any state

### `Weapons/State/Weapons/Equipment/SM`

Starts in HealthShot.

| State | Plays | Goes to |
|---|---|---|
| HealthShot (starts here when weapon_type is weapon_healthshot) | state machine Weapons/State/Weapons/Equipment/SM/HealthShot/SM (3 states) | C4 when weapon_type is weapon_c4 (0 s) |
| C4 (starts here when weapon_type is weapon_c4) | state machine Weapons/State/Weapons/Equipment/SM/C4/SM (2 states) | HealthShot when weapon_type is weapon_healthshot (0 s) |

### `Weapons/State/Weapons/Equipment/SM/HealthShot/SM`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Deploy (starts here when action is action_deploy) | a 1D blend on move_crouch_amount eased over 0.2 s of draw_healthshot at 0, draw_crouch_healthshot at 1 | Off when action is one of action_idle, (none) (0.2 s) |
| Inject (starts here when action is action_healthshot_inject) | a 1D blend on move_crouch_amount eased over 0.2 s of shoot_healthshot at 0, shoot_crouch_healthshot at 1 | Off when action is one of action_idle, (none) (0.2 s) |
| Off (starts here when action is one of action_idle, (none)) |   | - |

From more than one state:

- to Inject when action is action_healthshot_inject (0 s), from any state
- to Deploy when action is action_deploy (0.2 s), from any state

### `Weapons/State/Weapons/Equipment/SM/C4/SM`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Deploying (starts here when action is action_deploy) | a 1D blend on move_crouch_amount eased over 0.2 s of draw_c4 at 0, draw_crouch_c4 at 1 | Off when action is not action_deploy (0.2 s) |
| Off (starts here when not (action is action_deploy)) |   | Deploying when action is action_deploy (0.2 s) |

### `Weapons/State/Weapons/SniperRifles/SM`

Starts in AWP.

| State | Plays | Goes to |
|---|---|---|
| AWP (starts here when weapon_type is weapon_awp) | the worldmodel_gun graph (awp) | - |
| SSG08 (starts here when weapon_type is weapon_ssg08) | the worldmodel_gun graph (ssg08) | - |
| G3SG1 (starts here when weapon_type is weapon_g3sg1) | the worldmodel_gun graph (g3sg1) | - |
| SCAR20 (starts here when weapon_type is weapon_scar20) | the worldmodel_gun graph (scar20) | - |

From more than one state:

- to SSG08 when weapon_type is weapon_ssg08 (0 s), from any state
- to G3SG1 when weapon_type is weapon_g3sg1 (0 s), from any state
- to SCAR20 when weapon_type is weapon_scar20 (0 s), from any state
- to AWP when weapon_type is weapon_awp (0 s), from any state

### `Weapons/State/Weapons/Grenades/SM`

Starts in Decoy.

| State | Plays | Goes to |
|---|---|---|
| Decoy (starts here when weapon_type is weapon_decoy) | the worldmodel_grenade graph (decoy) | - |
| HE (starts here when weapon_type is weapon_hegrenade) | the worldmodel_grenade graph (he) | - |
| Smoke (starts here when weapon_type is weapon_smokegrenade) | the worldmodel_grenade graph (smoke) | - |
| Incendiary (starts here when weapon_type is weapon_incgrenade) | the worldmodel_grenade graph (incendiary) | - |
| Molotov (starts here when weapon_type is weapon_molotov) | the worldmodel_grenade graph (molotov) | - |
| Flash (starts here when weapon_type is weapon_flashbang) | the worldmodel_grenade graph (flash) | - |

From more than one state:

- to HE when weapon_type is weapon_hegrenade (0 s), from any state
- to Smoke when weapon_type is weapon_smokegrenade (0 s), from any state
- to Incendiary when weapon_type is weapon_incgrenade (0 s), from any state
- to Molotov when weapon_type is weapon_molotov (0 s), from any state
- to Flash when weapon_type is weapon_flashbang (0 s), from any state
- to Decoy when weapon_type is weapon_decoy (0 s), from any state

### `Weapons/State/Weapons/MG/SM`

Starts in M249.

| State | Plays | Goes to |
|---|---|---|
| M249 (starts here when weapon_type is weapon_m249) | the worldmodel_gun graph (m249) | Negev when weapon_type is weapon_negev (0 s) |
| Negev (starts here when weapon_type is weapon_negev) | the worldmodel_gun graph (negev) | M249 when weapon_type is weapon_m249 (0 s) |

### `Weapons/State/Weapons/Shotguns/SM`

Starts in Nova.

| State | Plays | Goes to |
|---|---|---|
| Nova (starts here when weapon_type is weapon_nova) | the worldmodel_gun graph (nova) | - |
| XM1014 (starts here when weapon_type is weapon_xm1014) | the worldmodel_gun graph (xm1014) | - |
| SawedOff (starts here when weapon_type is weapon_sawedoff) | the worldmodel_gun graph (sawedoff) | - |
| MAG7 (starts here when weapon_type is weapon_mag7) | the worldmodel_gun graph (mag7) | - |

From more than one state:

- to XM1014 when weapon_type is weapon_xm1014 (0 s), from any state
- to SawedOff when weapon_type is weapon_sawedoff (0 s), from any state
- to MAG7 when weapon_type is weapon_mag7 (0 s), from any state
- to Nova when weapon_type is weapon_nova (0 s), from any state

### `Weapons/State/Weapons/SMG/SM`

Starts in MP7.

| State | Plays | Goes to |
|---|---|---|
| MP7 (starts here when weapon_type is weapon_mp7) | the worldmodel_gun graph (mp7) | - |
| MP9 (starts here when weapon_type is weapon_mp9) | the worldmodel_gun graph (mp9) | - |
| MP5SD (starts here when weapon_type is weapon_mp5sd) | the worldmodel_gun graph (mp5sd) | - |
| MAC10 (starts here when weapon_type is weapon_mac10) | the worldmodel_gun graph (mac10) | - |
| p90 (starts here when weapon_type is weapon_p90) | the worldmodel_gun graph (p90) | - |
| Bizon (starts here when weapon_type is weapon_bizon) | the worldmodel_gun graph (bizon) | - |
| ump45 (starts here when weapon_type is weapon_ump45) | the worldmodel_gun graph (ump45) | - |

From more than one state:

- to MP9 when weapon_type is weapon_mp9 (0 s), from any state
- to MP5SD when weapon_type is weapon_mp5sd (0 s), from any state
- to MAC10 when weapon_type is weapon_mac10 (0 s), from any state
- to p90 when weapon_type is weapon_p90 (0 s), from any state
- to Bizon when weapon_type is weapon_bizon (0 s), from any state
- to ump45 when weapon_type is weapon_ump45 (0 s), from any state
- to MP7 when weapon_type is weapon_mp7 (0 s), from any state

### `Weapons/State/Weapons/Rifles/SM`

Starts in AK.

| State | Plays | Goes to |
|---|---|---|
| AK (starts here when weapon_type is weapon_ak47) | the worldmodel_gun graph (ak47) | - |
| M4A1S (starts here when weapon_type is weapon_m4a1_silencer) | the worldmodel_gun graph (m4a1s) | - |
| SG556 (starts here when weapon_type is weapon_sg556) | the worldmodel_gun graph (sg556) | - |
| AUG (starts here when weapon_type is weapon_aug) | the worldmodel_gun graph (aug) | - |
| GALIL (starts here when weapon_type is weapon_galilar) | the worldmodel_gun graph (galil) | - |
| M4A4 (starts here when weapon_type is weapon_m4a1) | the worldmodel_gun graph (m4a4) | - |
| FAMAS (starts here when weapon_type is weapon_famas) | the worldmodel_gun graph (famas) | - |
| TEMP (starts here when weapon_type is weapon_temp) | a graph from the caller | - |

From more than one state:

- to M4A1S when weapon_type is weapon_m4a1_silencer (0 s), from any state
- to SG556 when weapon_type is weapon_sg556 (0 s), from any state
- to AUG when weapon_type is weapon_aug (0 s), from any state
- to GALIL when weapon_type is weapon_galilar (0 s), from any state
- to M4A4 when weapon_type is weapon_m4a1 (0 s), from any state
- to FAMAS when weapon_type is weapon_famas (0 s), from any state
- to TEMP when weapon_type is weapon_temp (0.2 s), from any state
- to AK when weapon_type is weapon_ak47 (0 s), from any state

### `Weapons/State/Weapons/Knives/SM`

Starts in Default_CT.

| State | Plays | Goes to |
|---|---|---|
| Default_CT (starts here when weapon_type is weapon_knife) | the worldmodel_knife graph (default_ct) | - |
| Default_T (starts here when weapon_type is weapon_knife_t) | the worldmodel_knife graph (default_t) | - |
| Bayonet (starts here when weapon_type is weapon_bayonet) | the worldmodel_knife graph (bayonet) | - |
| Bowie (starts here when weapon_type is weapon_knife_survival_bowie) | the worldmodel_knife graph (bowie) | - |
| Butterfly (starts here when weapon_type is weapon_knife_butterfly) | the worldmodel_knife graph (butterfly) | - |
| CSS (starts here when weapon_type is weapon_knife_css) | the worldmodel_knife graph (css) | - |
| m9 (starts here when weapon_type is weapon_knife_m9_bayonet) | the worldmodel_knife graph (m9) | - |
| Gut (starts here when weapon_type is weapon_knife_gut) | the worldmodel_knife graph (gut) | - |
| Tactical (starts here when weapon_type is weapon_knife_tactical) | the worldmodel_knife graph (tactical) | - |
| Flip (starts here when weapon_type is weapon_knife_flip) | the worldmodel_knife graph (flip) | - |
| Navaja (starts here when weapon_type is weapon_knife_gypsy_jackknife) | the worldmodel_knife graph (navajo) | - |
| Falchion (starts here when weapon_type is weapon_knife_falchion) | the worldmodel_knife graph (falchion) | - |
| Canis (starts here when weapon_type is weapon_knife_canis) | the worldmodel_knife graph (canis) | - |
| Talon (starts here when weapon_type is weapon_knife_widowmaker) | the worldmodel_knife graph (talon) | - |
| Push (starts here when weapon_type is weapon_knife_push) | the worldmodel_knife graph (push) | - |
| Cord (starts here when weapon_type is weapon_knife_cord) | the worldmodel_knife graph (cord) | - |
| Outdoor (starts here when weapon_type is weapon_knife_outdoor) | the worldmodel_knife graph (outdoor) | - |
| Skeleton (starts here when weapon_type is weapon_knife_skeleton) | the worldmodel_knife graph (skeleton) | - |
| Stiletto (starts here when weapon_type is weapon_knife_stiletto) | the worldmodel_knife graph (stiletto) | - |
| Ursus (starts here when weapon_type is weapon_knife_ursus) | the worldmodel_knife graph (ursus) | - |
| Kukri (starts here when weapon_type is weapon_knife_kukri) | the worldmodel_knife graph (kukri) | - |
| Karambit (starts here when weapon_type is weapon_knife_karambit) | the worldmodel_knife graph (karambit) | - |

From more than one state:

- to Default_T when weapon_type is weapon_knife_t (0 s), from any state
- to Bayonet when weapon_type is weapon_bayonet (0 s), from any state
- to Bowie when weapon_type is weapon_knife_survival_bowie (0 s), from any state
- to Butterfly when weapon_type is weapon_knife_butterfly (0 s), from any state
- to CSS when weapon_type is weapon_knife_css (0 s), from any state
- to m9 when weapon_type is weapon_knife_m9_bayonet (0 s), from any state
- to Gut when weapon_type is weapon_knife_gut (0 s), from any state
- to Tactical when weapon_type is weapon_knife_tactical (0 s), from any state
- to Flip when weapon_type is weapon_knife_flip (0 s), from any state
- to Navaja when weapon_type is weapon_knife_gypsy_jackknife (0 s), from any state
- to Falchion when weapon_type is weapon_knife_falchion (0 s), from any state
- to Canis when weapon_type is weapon_knife_canis (0 s), from any state
- to Talon when weapon_type is weapon_knife_widowmaker (0 s), from any state
- to Push when weapon_type is weapon_knife_push (0 s), from any state
- to Cord when weapon_type is weapon_knife_cord (0 s), from any state
- to Outdoor when weapon_type is weapon_knife_outdoor (0 s), from any state
- to Skeleton when weapon_type is weapon_knife_skeleton (0 s), from any state
- to Stiletto when weapon_type is weapon_knife_stiletto (0 s), from any state
- to Ursus when weapon_type is weapon_knife_ursus (0 s), from any state
- to Kukri when weapon_type is weapon_knife_kukri (0 s), from any state
- to Karambit when weapon_type is weapon_knife_karambit (0 s), from any state
- to Default_CT when weapon_type is weapon_knife (0 s), from any state

### `Weapons/State/Weapons/Pistols/SM`

Starts in USP.

| State | Plays | Goes to |
|---|---|---|
| Revolver (starts here when weapon_type is weapon_revolver) | the worldmodel_gun graph (revolver) | - |
| USP (starts here when weapon_type is weapon_usp_silencer) | the worldmodel_gun graph (usp) | - |
| Glock (starts here when weapon_type is weapon_glock) | the worldmodel_gun graph (glock) | - |
| CZ75 (starts here when weapon_type is weapon_cz75a) | the worldmodel_gun_cz75 graph | - |
| Elites (starts here when weapon_type is weapon_elite) | the worldmodel_gun graph (elites) | - |
| P2000 (starts here when weapon_type is weapon_hkp2000) | the worldmodel_gun graph (hkp2000) | - |
| TEC9 (starts here when weapon_type is weapon_tec9) | the worldmodel_gun graph (tec9) | - |
| FiveSeven (starts here when weapon_type is weapon_fiveseven) | the worldmodel_gun graph (five_seven) | - |
| Taser (starts here when weapon_type is weapon_taser) | the worldmodel_gun graph (taser) | - |
| P250 (starts here when weapon_type is weapon_p250) | the worldmodel_gun graph (p250) | - |
| Deagle (starts here when weapon_type is weapon_deagle) | the worldmodel_gun graph (deagle) | - |

From more than one state:

- to USP when weapon_type is weapon_usp_silencer (0 s), from any state
- to Glock when weapon_type is weapon_glock (0 s), from any state
- to CZ75 when weapon_type is weapon_cz75a (0 s), from any state
- to Elites when weapon_type is weapon_elite (0 s), from any state
- to P2000 when weapon_type is weapon_hkp2000 (0 s), from any state
- to TEC9 when weapon_type is weapon_tec9 (0 s), from any state
- to FiveSeven when weapon_type is weapon_fiveseven (0 s), from any state
- to Taser when weapon_type is weapon_taser (0 s), from any state
- to P250 when weapon_type is weapon_p250 (0 s), from any state
- to Deagle when weapon_type is weapon_deagle (0 s), from any state
- to Revolver when weapon_type is weapon_revolver (0 s), from any state

### `Defuse`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Defuse | state machine Defuse/Defuse/SM (3 states) | Off when not is_defusing (0.4 s) |
| Off |   | Defuse when is_defusing (0.2 s) |

### `Defuse/Defuse/SM`

Starts in Knife.

| State | Plays | Goes to |
|---|---|---|
| Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | state machine Defuse/Defuse/SM/Knife/SM (2 states) | - |
| Pistol (starts here when weapon_category is weapon_category_pistol) | state machine Defuse/Defuse/SM/Pistol/SM (2 states) | - |
| Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | state machine Defuse/Defuse/SM/Rifle/SM (2 states) | - |

From more than one state:

- to Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `Defuse/Defuse/SM/Knife/SM`

Starts in Knife.

| State | Plays | Goes to |
|---|---|---|
| Knife (starts here when not (weapon_type is one of weapon_knife_karambit, weapon_knife_widowmaker)) | state machine Defuse/Defuse/SM/Knife/SM/Knife/SM (2 states) | - |
| Karambit_Widowmaker (starts here when weapon_type is one of weapon_knife_karambit, weapon_knife_widowmaker) | state machine Defuse/Defuse/SM/Knife/SM/Karambit_Widowmaker/SM (2 states) | - |

### `Defuse/Defuse/SM/Knife/SM/Knife/SM`

Starts in Enter.

| State | Plays | Goes to |
|---|---|---|
| Loop | a 1D blend on move_crouch_amount of defuse_loop_knife at 0, defuse_crouch_loop_knife at 1 | - |
| Enter | a 1D blend on move_crouch_amount of defuse_enter_knife at 0, defuse_crouch_enter_knife at 1 | Loop when the state has 0.2 s left (0.2 s) |

### `Defuse/Defuse/SM/Knife/SM/Karambit_Widowmaker/SM`

Starts in Enter.

| State | Plays | Goes to |
|---|---|---|
| Loop | a 1D blend on move_crouch_amount of defuse_loop_knife_talon at 0, defuse_crouch_loop_knife_talon at 1 | - |
| Enter | a 1D blend on move_crouch_amount of defuse_enter_knife_talon at 0, defuse_crouch_enter_knife_talon at 1 | Loop when the state has 0.2 s left (0.2 s) |

### `Defuse/Defuse/SM/Pistol/SM`

Starts in Enter.

| State | Plays | Goes to |
|---|---|---|
| Loop | a 1D blend on move_crouch_amount of defuse_loop_pistol at 0, defuse_crouch_loop_pistol at 1 | - |
| Enter | a 1D blend on move_crouch_amount of defuse_enter_pistol at 0, defuse_crouch_enter_pistol at 1 | Loop when the state has 0.2 s left (0.2 s) |

### `Defuse/Defuse/SM/Rifle/SM`

Starts in Enter.

| State | Plays | Goes to |
|---|---|---|
| Loop | a 1D blend on move_crouch_amount of defuse_loop_rifle at 0, defuse_crouch_loop_rifle at 1 | - |
| Enter | a 1D blend on move_crouch_amount of defuse_enter_rifle at 0, defuse_crouch_enter_rifle at 1 | Loop when the state has 0.2 s left (0.2 s) |

### `BodyAdditives`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Breathing | clip breathing (loops) | Off when (not (not is_defusing and move_speed_horizontal <= 5 and move_type is move_type_ground and flinch_body_type is (none) and flinch_head_type is (none) and action is one of (none), action_idle, action_inspect)) and not (move_type is move_type_air) (0 s) |
| Off |   | - |
| JumpAdditiveStart | state machine BodyAdditives/JumpAdditiveStart/jump_additive_starts (2 states) | JumpAdditiveLand when air_action is air_action_land (0 s, options 40)<br>Off when time in the state <= 0.35 and move_type is one of move_type_ground, move_type_ladder (0 s) |
| JumpAdditiveLand | state machine BodyAdditives/JumpAdditiveLand/jump_additive_lands (2 states) | Off when the state is done (0 s) |

From more than one state:

- to JumpAdditiveStart when move_type is move_type_air and air_action is one of air_action_jump, air_action_start_fall (0.2 s), from any state
- to JumpAdditiveLand when air_action is air_action_land (0.2 s), from Breathing, Off
- to Breathing when not is_defusing and move_speed_horizontal <= 5 and move_type is move_type_ground and flinch_body_type is (none) and flinch_head_type is (none) and action is one of (none), action_idle, action_inspect (0 s), from Off, JumpAdditiveStart

### `BodyAdditives/JumpAdditiveStart/jump_additive_starts`

Starts in stand.

| State | Plays | Goes to |
|---|---|---|
| stand (starts here when not (move_crouch_amount >= 0.5)) | state machine BodyAdditives/JumpAdditiveStart/jump_additive_starts/stand/SM (3 states) | crouch when move_crouch_amount >= 0.5 (0.2 s, options 4) |
| crouch (starts here when move_crouch_amount >= 0.5) | state machine BodyAdditives/JumpAdditiveStart/jump_additive_starts/crouch/SM (3 states) | stand when not (move_crouch_amount >= 0.5) (0.2 s, options 4) |

### `BodyAdditives/JumpAdditiveStart/jump_additive_starts/stand/SM`

Starts in knives.

| State | Plays | Goes to |
|---|---|---|
| rifles (starts here when not (action is action_deploy) and locomotion_rifle) | clip jump_additive_start_rifle | - |
| pistols (starts here when not (action is action_deploy) and locomotion_pistol) | clip jump_additive_start_pistol | - |
| knives (starts here when not (action is action_deploy) and locomotion_knife) | clip jump_additive_start | - |

From more than one state:

- to pistols when not (action is action_deploy) and locomotion_pistol (0.2 s), from any state
- to knives when not (action is action_deploy) and locomotion_knife (0.2 s), from any state
- to rifles when not (action is action_deploy) and locomotion_rifle (0.2 s), from any state

### `BodyAdditives/JumpAdditiveStart/jump_additive_starts/crouch/SM`

Starts in knives.

| State | Plays | Goes to |
|---|---|---|
| rifles (starts here when not (action is action_deploy) and locomotion_rifle) | clip jump_additive_crouch_start_rifle | - |
| pistols (starts here when not (action is action_deploy) and locomotion_pistol) | clip jump_additive_crouch_start_pistol | - |
| knives (starts here when not (action is action_deploy) and locomotion_knife) | clip jump_additive_crouch_start | - |

From more than one state:

- to pistols when not (action is action_deploy) and locomotion_pistol (0.2 s), from any state
- to knives when not (action is action_deploy) and locomotion_knife (0.2 s), from any state
- to rifles when not (action is action_deploy) and locomotion_rifle (0.2 s), from any state

### `BodyAdditives/JumpAdditiveLand/jump_additive_lands`

Starts in stand.

| State | Plays | Goes to |
|---|---|---|
| stand (starts here when not (move_crouch_amount >= 0.5)) | state machine BodyAdditives/JumpAdditiveLand/jump_additive_lands/stand/SM (3 states) | crouch when move_crouch_amount >= 0.5 (0.2 s) |
| crouch (starts here when move_crouch_amount >= 0.5) | state machine BodyAdditives/JumpAdditiveLand/jump_additive_lands/crouch/SM (3 states) | stand when not (move_crouch_amount >= 0.5) (0.2 s) |

### `BodyAdditives/JumpAdditiveLand/jump_additive_lands/stand/SM`

Starts in knives.

| State | Plays | Goes to |
|---|---|---|
| knives (starts here when not (action is action_deploy) and locomotion_knife) | clip jump_additive_land | - |
| rifles (starts here when not (action is action_deploy) and locomotion_rifle) | clip jump_additive_land_rifle | - |
| pistols (starts here when not (action is action_deploy) and locomotion_pistol) | clip jump_additive_land_pistol | - |

From more than one state:

- to rifles when not (action is action_deploy) and locomotion_rifle (0.2 s), from any state
- to pistols when not (action is action_deploy) and locomotion_pistol (0.2 s), from any state
- to knives when not (action is action_deploy) and locomotion_knife (0.2 s), from any state

### `BodyAdditives/JumpAdditiveLand/jump_additive_lands/crouch/SM`

Starts in knives.

| State | Plays | Goes to |
|---|---|---|
| knives (starts here when not (action is action_deploy) and locomotion_knife) | clip jump_additive_crouch_land | - |
| rifles (starts here when not (action is action_deploy) and locomotion_rifle) | clip jump_additive_crouch_land_rifle | - |
| pistols (starts here when not (action is action_deploy) and locomotion_pistol) | clip jump_additive_crouch_land_pistol | - |

From more than one state:

- to rifles when not (action is action_deploy) and locomotion_rifle (0.2 s), from any state
- to pistols when not (action is action_deploy) and locomotion_pistol (0.2 s), from any state
- to knives when not (action is action_deploy) and locomotion_knife (0.2 s), from any state

### `Weapon Shoot`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| SniperRifles (starts here when action is action_attack and weapon_category is weapon_category_sniper) | state machine Weapon Shoot/SniperRifles/SM (4 states) | - |
| MG (starts here when action is action_attack and weapon_category is weapon_category_machinegun) | state machine Weapon Shoot/MG/SM (2 states) | - |
| Shotguns (starts here when action is action_attack and weapon_category is weapon_category_shotgun) | state machine Weapon Shoot/Shotguns/SM (4 states) | - |
| SMG (starts here when action is action_attack and weapon_category is weapon_category_smg) | state machine Weapon Shoot/SMG/SM (7 states) | - |
| Rifles (starts here when action is action_attack and weapon_category is weapon_category_rifle) | state machine Weapon Shoot/Rifles/SM (9 states) | - |
| Pistols (starts here when action is action_attack and weapon_category is weapon_category_pistol) | state machine Weapon Shoot/Pistols/SM (11 states) | - |
| Off (starts here when weapon_category is one of weapon_category_equipment, weapon_category_grenade, weapon_category_knife or not (action is action_attack)) |   | - |

From more than one state:

- to MG when action is action_attack and weapon_category is weapon_category_machinegun (0 s), from any state
- to Shotguns when action is action_attack and weapon_category is weapon_category_shotgun (0 s), from any state
- to SMG when action is action_attack and weapon_category is weapon_category_smg (0 s), from any state
- to Rifles when action is action_attack and weapon_category is weapon_category_rifle (0 s), from any state
- to Pistols when action is action_attack and weapon_category is weapon_category_pistol (0 s), from any state
- to Off when weapon_category is one of weapon_category_equipment, weapon_category_grenade, weapon_category_knife or not (action is action_attack) (0.2 s), from any state
- to SniperRifles when action is action_attack and weapon_category is weapon_category_sniper (0 s), from any state

### `Weapon Shoot/SniperRifles/SM`

Starts in AWP.

| State | Plays | Goes to |
|---|---|---|
| AWP (starts here when weapon_type is weapon_awp) | clip shoot_awp | - |
| SSG08 (starts here when weapon_type is weapon_ssg08) | clip shoot_ssg08 | - |
| G3SG1 (starts here when weapon_type is weapon_g3sg1) | clip shoot_g3sg1 | - |
| SCAR20 (starts here when weapon_type is weapon_scar20) | clip shoot_scar20 | - |

From more than one state:

- to SSG08 when weapon_type is weapon_ssg08 (0 s), from any state
- to G3SG1 when weapon_type is weapon_g3sg1 (0 s), from any state
- to SCAR20 when weapon_type is weapon_scar20 (0 s), from any state
- to AWP when weapon_type is weapon_awp (0 s), from any state

### `Weapon Shoot/MG/SM`

Starts in M249.

| State | Plays | Goes to |
|---|---|---|
| M249 (starts here when weapon_type is weapon_m249) | clip shoot_m249 | Negev when weapon_type is weapon_negev (0 s) |
| Negev (starts here when weapon_type is weapon_negev) | clip shoot_negev | M249 when weapon_type is weapon_m249 (0 s) |

### `Weapon Shoot/Shotguns/SM`

Starts in Nova.

| State | Plays | Goes to |
|---|---|---|
| Nova (starts here when weapon_type is weapon_nova) | clip shoot_nova | - |
| XM1014 (starts here when weapon_type is weapon_xm1014) | clip shoot_xm1014 | - |
| SawedOff (starts here when weapon_type is weapon_sawedoff) | clip shoot_sawedoff | - |
| MAG7 (starts here when weapon_type is weapon_mag7) | clip shoot_mag7 | - |

From more than one state:

- to XM1014 when weapon_type is weapon_xm1014 (0 s), from any state
- to SawedOff when weapon_type is weapon_sawedoff (0 s), from any state
- to MAG7 when weapon_type is weapon_mag7 (0 s), from any state
- to Nova when weapon_type is weapon_nova (0 s), from any state

### `Weapon Shoot/SMG/SM`

Starts in MP7.

| State | Plays | Goes to |
|---|---|---|
| MP7 (starts here when weapon_type is weapon_mp7) | clip shoot_mp7 | - |
| MP9 (starts here when weapon_type is weapon_mp9) | clip shoot_mp9 | - |
| MP5SD (starts here when weapon_type is weapon_mp5sd) | clip shoot_mp5sd | - |
| MAC10 (starts here when weapon_type is weapon_mac10) | clip shoot_mac10 | - |
| p90 (starts here when weapon_type is weapon_p90) | clip shoot_p90 | - |
| Bizon (starts here when weapon_type is weapon_bizon) | clip shoot_bizon | - |
| ump45 (starts here when weapon_type is weapon_ump45) | clip shoot_ump45 | - |

From more than one state:

- to MP9 when weapon_type is weapon_mp9 (0 s), from any state
- to MP5SD when weapon_type is weapon_mp5sd (0 s), from any state
- to MAC10 when weapon_type is weapon_mac10 (0 s), from any state
- to p90 when weapon_type is weapon_p90 (0 s), from any state
- to Bizon when weapon_type is weapon_bizon (0 s), from any state
- to ump45 when weapon_type is weapon_ump45 (0 s), from any state
- to MP7 when weapon_type is weapon_mp7 (0 s), from any state

### `Weapon Shoot/Rifles/SM`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| AK (starts here when weapon_type is weapon_ak47) | clip shoot_ak | - |
| M4A1S (starts here when weapon_type is weapon_m4a1_silencer) | clip shoot_m4a1s | - |
| SG556 (starts here when weapon_type is weapon_sg556) | clip shoot_sg556 | - |
| AUG (starts here when weapon_type is weapon_aug) | clip shoot_aug | - |
| GALIL (starts here when weapon_type is weapon_galilar) | clip shoot_galilar | - |
| M4A4 (starts here when weapon_type is weapon_m4a1) | clip shoot_m4a4 | - |
| FAMAS (starts here when weapon_type is weapon_famas) | clip shoot_famas | - |
| Off |   | - |
| TEMP (starts here when weapon_type is weapon_temp) | no clip (the slot is empty in this variation) | - |

From more than one state:

- to M4A1S when weapon_type is weapon_m4a1_silencer (0 s), from any state
- to SG556 when weapon_type is weapon_sg556 (0 s), from any state
- to AUG when weapon_type is weapon_aug (0 s), from any state
- to GALIL when weapon_type is weapon_galilar (0 s), from any state
- to M4A4 when weapon_type is weapon_m4a1 (0 s), from any state
- to FAMAS when weapon_type is weapon_famas (0 s), from any state
- to TEMP when weapon_type is weapon_temp (0.2 s), from any state
- to AK when weapon_type is weapon_ak47 (0 s), from any state

### `Weapon Shoot/Pistols/SM`

Starts in USP.

| State | Plays | Goes to |
|---|---|---|
| Revolver (starts here when weapon_type is weapon_revolver) | state machine Weapon Shoot/Pistols/SM/Revolver/SM (2 states) | - |
| USP (starts here when weapon_type is weapon_usp_silencer) | clip shoot_usp | - |
| Glock (starts here when weapon_type is weapon_glock) | clip shoot_glock | - |
| CZ75 (starts here when weapon_type is weapon_cz75a) | clip shoot_cz75 | - |
| Elites (starts here when weapon_type is weapon_elite) | state machine Weapon Shoot/Pistols/SM/Elites/Left (2 states), with 1 layers | - |
| P2000 (starts here when weapon_type is weapon_hkp2000) | clip shoot_hkp | - |
| TEC9 (starts here when weapon_type is weapon_tec9) | clip shoot_tec9 | - |
| FiveSeven (starts here when weapon_type is weapon_fiveseven) | clip shoot_fiveseven | - |
| Taser (starts here when weapon_type is weapon_taser) | clip shoot_taser | - |
| P250 (starts here when weapon_type is weapon_p250) | clip shoot_p250 | - |
| Deagle (starts here when weapon_type is weapon_deagle) | clip shoot_deagle | - |

From more than one state:

- to USP when weapon_type is weapon_usp_silencer (0 s), from any state
- to Glock when weapon_type is weapon_glock (0 s), from any state
- to CZ75 when weapon_type is weapon_cz75a (0 s), from any state
- to Elites when weapon_type is weapon_elite (0 s), from any state
- to P2000 when weapon_type is weapon_hkp2000 (0 s), from any state
- to TEC9 when weapon_type is weapon_tec9 (0 s), from any state
- to FiveSeven when weapon_type is weapon_fiveseven (0 s), from any state
- to Taser when weapon_type is weapon_taser (0 s), from any state
- to P250 when weapon_type is weapon_p250 (0 s), from any state
- to Deagle when weapon_type is weapon_deagle (0 s), from any state
- to Revolver when weapon_type is weapon_revolver (0 s), from any state

### `Weapon Shoot/Pistols/SM/Revolver/SM`

Starts in Primary.

| State | Plays | Goes to |
|---|---|---|
| Secondary (starts here when attack_type is attack_gun_secondaryfire) | clip shoot_alt_revolver | Primary when attack_shoot_reset and not (attack_type is attack_gun_secondaryfire) (0.2 s) |
| Primary (starts here when not (attack_type is attack_gun_secondaryfire)) | state machine Weapon Shoot/Pistols/SM/Revolver/SM/Primary/SM (2 states) | Secondary when attack_shoot_reset and attack_type is attack_gun_secondaryfire (0.2 s) |

### `Weapon Shoot/Pistols/SM/Revolver/SM/Primary/SM`

Starts in Charge.

| State | Plays | Goes to |
|---|---|---|
| Charge | the zero pose | Shoot when attack_type is attack_gun_primaryfire (0 s) |
| Shoot | clip shoot_revolver | Charge when attack_type is attack_gun_charge (0 s) |

### `Weapon Shoot/Pistols/SM/Elites/Left`

Starts in Idle.

| State | Plays | Goes to |
|---|---|---|
| Shoot (starts here when attack_type is attack_gun_primaryfire) | the first of: clip shoot_left1_elite if not attack_is_final_bullets; clip shoot_leftlast_elite if attack_is_final_bullets | Idle when not (attack_type is attack_gun_primaryfire) (0.1 s) |
| Idle (starts here when not (attack_type is attack_gun_primaryfire)) | the zero pose | Shoot when attack_type is attack_gun_primaryfire (0 s) |

### `Weapon Shoot/Pistols/SM/Elites/Right`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Shoot (starts here when attack_type is attack_gun_secondaryfire) | the first of: clip shoot_right1_elite if not attack_is_final_bullets; clip shoot_rightlast_elite if attack_is_final_bullets | Off when not (attack_type is attack_gun_secondaryfire) (0.1 s) |
| Off (starts here when not (attack_type is attack_gun_secondaryfire)) |   | Shoot when attack_type is attack_gun_secondaryfire (0 s) |

### `BodyFlinch`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Off (starts here when flinch_is_on_fire and flinch_body_type is (none)) |   | Flinch_WPNs when not (flinch_body_type is (none)) (0 s) |
| Flinch_WPNs | state machine BodyFlinch/Flinch_WPNs/SM (3 states) | Flinch_WPNs0 when not (flinch_body_type is (none)) and flinch_body_restart (0.1 s) |
| Flinch_WPNs0 | state machine BodyFlinch/Flinch_WPNs0/SM (3 states) | Flinch_WPNs when not (flinch_body_type is (none)) and flinch_body_restart (0.1 s) |

From more than one state:

- to Off when flinch_body_type is (none) (0 s), from any state

### `BodyFlinch/Flinch_WPNs/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | the first of: clip flinch_chest_knife if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear_knife if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right_knife if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left_knife if flinch_body_type is flinch_body_chest_west; clip flinch_stomach_knife if flinch_body_type is flinch_body_stomach_north; clip fli... | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | the first of: clip flinch_chest_pistol if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear_pistol if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right_pistol if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left_pistol if flinch_body_type is flinch_body_chest_west; clip flinch_stomach_pistol if flinch_body_type is flinch_body_stomach_north; cli... | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | the first of: clip flinch_chest if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left if flinch_body_type is flinch_body_chest_west; clip flinch_stomach if flinch_body_type is flinch_body_stomach_north; clip flinch_stomach_rear if flinch_bod... | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `BodyFlinch/Flinch_WPNs0/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | the first of: clip flinch_chest_knife if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear_knife if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right_knife if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left_knife if flinch_body_type is flinch_body_chest_west; clip flinch_stomach_knife if flinch_body_type is flinch_body_stomach_north; clip fli... | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | the first of: clip flinch_chest_pistol if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear_pistol if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right_pistol if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left_pistol if flinch_body_type is flinch_body_chest_west; clip flinch_stomach_pistol if flinch_body_type is flinch_body_stomach_north; cli... | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | the first of: clip flinch_chest if flinch_body_type is flinch_body_chest_north; clip flinch_chest_rear if flinch_body_type is flinch_body_chest_south; clip flinch_chest_right if flinch_body_type is flinch_body_chest_east; clip flinch_chest_left if flinch_body_type is flinch_body_chest_west; clip flinch_stomach if flinch_body_type is flinch_body_stomach_north; clip flinch_stomach_rear if flinch_bod... | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `HeadFlinch`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Off |   | Flinch_WPNs when flinch_head_type is not (none) (0 s) |
| Flinch_WPNs (starts here when not (flinch_head_type is (none))) | state machine HeadFlinch/Flinch_WPNs/SM (3 states) | Flinch_WPNs0 when flinch_head_type is not (none) and flinch_head_restart (0.1 s) |
| Flinch_WPNs0 | state machine HeadFlinch/Flinch_WPNs0/SM (3 states) | Flinch_WPNs when flinch_head_type is not (none) and flinch_head_restart (0.1 s) |

From more than one state:

- to Off when flinch_head_type is (none) (0.1 s), from any state

### `HeadFlinch/Flinch_WPNs/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | the first of: clip flinch_head_knife if flinch_head_type is flinch_head_north; clip flinch_head_rear_knife if flinch_head_type is flinch_head_south; clip flinch_head_right_knife if flinch_head_type is flinch_head_east; clip flinch_head_left_knife if flinch_head_type is flinch_head_west | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | the first of: clip flinch_head_pistol if flinch_head_type is flinch_head_north; clip flinch_head_rear_pistol if flinch_head_type is flinch_head_south; clip flinch_head_right_pistol if flinch_head_type is flinch_head_east; clip flinch_head_left_pistol if flinch_head_type is flinch_head_west | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | the first of: clip flinch_head if flinch_head_type is flinch_head_north; clip flinch_head_rear if flinch_head_type is flinch_head_south; clip flinch_head_right if flinch_head_type is flinch_head_east; clip flinch_head_left if flinch_head_type is flinch_head_west | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `HeadFlinch/Flinch_WPNs0/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | the first of: clip flinch_head_knife if flinch_head_type is flinch_head_north; clip flinch_head_rear_knife if flinch_head_type is flinch_head_south; clip flinch_head_right_knife if flinch_head_type is flinch_head_east; clip flinch_head_left_knife if flinch_head_type is flinch_head_west | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | the first of: clip flinch_head_pistol if flinch_head_type is flinch_head_north; clip flinch_head_rear_pistol if flinch_head_type is flinch_head_south; clip flinch_head_right_pistol if flinch_head_type is flinch_head_east; clip flinch_head_left_pistol if flinch_head_type is flinch_head_west | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | the first of: clip flinch_head if flinch_head_type is flinch_head_north; clip flinch_head_rear if flinch_head_type is flinch_head_south; clip flinch_head_right if flinch_head_type is flinch_head_east; clip flinch_head_left if flinch_head_type is flinch_head_west | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `FireFlinch`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Off |   | - |
| OnFire_WPNs (starts here when not (flinch_body_type is (none))) | state machine FireFlinch/OnFire_WPNs/SM (3 states) | OnFire_WPNs0 when not flinch_is_on_fire (0.1 s, options 4) |
| OnFire_WPNs0 | state machine FireFlinch/OnFire_WPNs0/SM (3 states) | Off when not flinch_is_on_fire and time in the state > 0.15 (0.1 s, options 4) |

From more than one state:

- to OnFire_WPNs when flinch_is_on_fire (0.2 s), from any state

### `FireFlinch/OnFire_WPNs/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | clip flinch_molotov_knife (loops) | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | clip flinch_molotov_pistol (loops) | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | clip flinch_molotov (loops) | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `FireFlinch/OnFire_WPNs0/SM`

Starts in Flinch_Knife.

| State | Plays | Goes to |
|---|---|---|
| Flinch_Knife (starts here when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun)) | clip flinch_molotov_knife (loops) | - |
| Flinch_Pistol (starts here when weapon_category is weapon_category_pistol) | clip flinch_molotov_pistol (loops) | - |
| Flinch_Rifle (starts here when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) | clip flinch_molotov (loops) | - |

From more than one state:

- to Flinch_Pistol when weapon_category is weapon_category_pistol (0.2 s), from any state
- to Flinch_Rifle when weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun (0.2 s), from any state
- to Flinch_Knife when not (weapon_category is weapon_category_pistol) and not (weapon_category is one of weapon_category_rifle, weapon_category_machinegun, weapon_category_shotgun) (0.2 s), from any state

### `flashed`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| Off |   | flashed when not (flashed_amount <= 0.1) (0.2 s) |
| flashed | a 1D blend on move_crouch_amount eased over 0.2 s of flashed at 0, flashed_crouch at 1 | Off when flashed_amount <= 0.1 (0.2 s) |
