# The third-person locomotion

Written by `scripts/animgraph_tables.gd` on 2026-09-25 from `animation/graphs/worldmodel/worldmodel_locomotion.vnmgraph+rifle.vnmgraph_c` in CS2 1.41.8.5. Do not edit by hand; `reference/animgraph2.md` says how to read it.

`worldmodel_locomotion.vnmgraph`, which the third-person graph runs for the legs and body: idle, starts, moving, turning on the spot, the air and ladders. Its clips are shown for the rifle variation; the pistol and knife ones swap in their own sets, and the blend spaces are the same in all three (`locomotion.json` has each variation's clips).

Each node is named by its path in Valve's editor. Conditions are written out with the parameters by name (`parameters.md` has their values); a transition's blend is its length, then its easing and options where they are not the plain ones. (options is Esoterica's transition-option bit field, which Valve's version orders its own way.)

## From the root

1. `StateMachine` SM

## State machines (25)

### `SM`

Starts in Ground.

| State | Plays | Goes to |
|---|---|---|
| Ground (starts here when move_type is move_type_ground) | state machine SM/Ground/Standing (6 states) | - |
| Ladder (starts here when move_type is move_type_ladder) | a 1D blend on move_crouch_amount_eased of Standing at 0, Crouched at 1 | - |
| InAir (starts here when move_type is one of move_type_air, move_type_jump) | state machine SM/InAir/SM (2 states) | Ground when move_type is one of move_type_ground, move_type_ladder and event MS_AIR_FINISHING (0.05 s)<br>Ground when move_type is one of move_type_ground, move_type_ladder and not (event MS_AIR_FINISHING) (0.2 s) |
| landing_blend | a 1D blend on a curve of air_height_above_ground (10 to 0, 40 to 50) on a 5 Hz spring, damping 1.2, from 50 of Blend 1D at 10, Blend 1D at 50 | - |
| Jump | a 1D blend on move_crouch_amount_eased of Blend 2D at 0, Blend 2D at 1 | landing_blend when the state is done (0 s) |

From more than one state:

- to Ladder when move_type is move_type_ladder (0 s), from any state
- to InAir when move_type is move_type_air ((air_action is air_action_start_fall ? 0.3 : 0.1) s), from any state
- to Ground when move_type is move_type_ground (0.1 s), from Ladder, landing_blend, Jump

### `SM/Ground/Standing`

Starts in Idle.

| State | Plays | Goes to |
|---|---|---|
| PlantAndTurn (starts here when not move_is_walking and ground_action is ground_action_plant_and_turn) | state machine SM/Ground/Standing/PlantAndTurn/SM (4 states) | Idle when graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_idle (0.35 s, OutQuart)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (graph event Plant_E2W (Any) or Plant_E2W_crossleg (Any)) (0.2 s, OutSine)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (graph event Plant_W2E (Any) or Plant_W2E_crossleg (Any)) (0.2 s, OutSine)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_N2S (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_S2N (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_N2S_crossleg (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_S2N_crossleg (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (not (graph event Plant_E2W (Any) or Plant_E2W_crossleg (Any) or Plant_W2E (Any) or Plant_W2E_crossleg (Any) or Plant_N2S (Any) or Plant_N2S_crossleg (Any) or Plant_S2N (Any) or Plant_S2N_crossleg (Any))) (0.2 s) |
| Idle (starts here when ground_action is ground_action_idle) | state machine SM/Ground/Standing/Idle/SM (2 states) | PlantAndTurn when ground_action is ground_action_move (0.2 s) |
| Move (starts here when ground_action is ground_action_move) | a 1D blend on move_crouch_amount of Blend 2D at 0, Blend 2D at 1 | - |
| TurnOnSpot (starts here when ground_action is one of ground_action_turn_on_spot, ground_action_turn_on_spot_loop) | state machine SM/Ground/Standing/TurnOnSpot/SM (2 states) | - |
| Starts (starts here when ground_action is ground_action_start) | a 1D blend on move_crouch_amount of Parameterized Clip Selector at 0, idle_crouch_rifle at 1 | Move when ground_action is ground_action_move (0.2 s, OutQuad) |
| PlantAndTurnWalks (starts here when move_is_walking and ground_action is ground_action_plant_and_turn) | state machine SM/Ground/Standing/PlantAndTurnWalks/SM (4 states) | Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_S2N (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_N2S (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (graph event Plant_W2E (Any) or Plant_W2E_crossleg (Any)) (0.2 s, OutSine)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (graph event Plant_E2W (Any) or Plant_E2W_crossleg (Any)) (0.2 s, OutSine)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_N2S_crossleg (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and graph event Plant_S2N_crossleg (Any) (0.3 s, OutQuint)<br>Move when (graph event PLANT_AND_TURN_COMPLETE (Any) and ground_action is ground_action_move) and (not (graph event Plant_E2W (Any) or Plant_E2W_crossleg (Any) or Plant_W2E (Any) or Plant_W2E_crossleg (Any) or Plant_N2S (Any) or Plant_N2S_crossleg (Any) or Plant_S2N (Any) or Plant_S2N_crossleg (Any))) (0.2 s) |

From more than one state:

- to TurnOnSpot when ground_action is one of ground_action_turn_on_spot, ground_action_turn_on_spot_loop (0.2 s, can interrupt), from any state
- to Starts when ground_action is ground_action_start (0.1 s), from any state
- to PlantAndTurnWalks when ground_action is ground_action_plant_and_turn and move_is_walking (0.15 s, can interrupt), from any state
- to Move when ground_action is ground_action_move (0.2 s), from Idle, TurnOnSpot
- to PlantAndTurn when not move_is_walking and ground_action is ground_action_plant_and_turn (0.1 s, can interrupt), from Move, TurnOnSpot, Starts, PlantAndTurnWalks
- to Idle when ground_action is ground_action_idle (0.2 s), from Move, TurnOnSpot, Starts, PlantAndTurnWalks

### `SM/Ground/Standing/PlantAndTurn/SM`

Starts in N2S_complex.

| State | Plays | Goes to |
|---|---|---|
| E2W (starts here when ground_action_direction_id is W) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| W2E (starts here when ground_action_direction_id is E) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| N2S_complex (starts here when ground_action_direction_id is S) | state machine SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM (2 states) | - |
| S2N_complex (starts here when ground_action_direction_id is N) | state machine SM/Ground/Standing/PlantAndTurn/SM/S2N_complex/SM (2 states) | - |

From more than one state:

- to W2E when ground_action_direction_id is E (0.1 s), from any state
- to N2S_complex when ground_action_direction_id is S (0.2 s), from any state
- to S2N_complex when ground_action_direction_id is N (0.2 s), from any state
- to E2W when ground_action_direction_id is W (0.1 s), from any state

### `SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM`

Starts in N2S.

| State | Plays | Goes to |
|---|---|---|
| N2S (starts here when not (graph event Plant_S2N (Any) or Plant_S2N_crossleg (Any))) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| Force_pose (starts here when graph event Plant_S2N (Any) or Plant_S2N_crossleg (Any)) | state machine SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM/Force_pose/SM (2 states) | - |

### `SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM/N2S/SM`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 110) | clip planted_slow_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 110)) | clip planted_slow_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM/Force_pose/SM`

Starts in N2S_force_crossleg_response.

| State | Plays | Goes to |
|---|---|---|
| N2S_force_vanilla_response (starts here when graph event Plant_S2N (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| N2S_force_crossleg_response (starts here when graph event Plant_S2N_crossleg (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |

### `SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM/Force_pose/SM/N2S_force_vanilla_response/SM`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 150) | clip planted_slow_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 150)) | clip planted_slow_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurn/SM/N2S_complex/SM/Force_pose/SM/N2S_force_vanilla_response/SM0`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 150) | clip planted_slow_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 150)) | clip planted_slow_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurn/SM/S2N_complex/SM`

Starts in S2N.

| State | Plays | Goes to |
|---|---|---|
| S2N (starts here when not (graph event Plant_N2S (Any) or Plant_N2S_crossleg (Any))) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| force_pose (starts here when graph event Plant_N2S (Any) or Plant_N2S_crossleg (Any)) | state machine SM/Ground/Standing/PlantAndTurn/SM/S2N_complex/SM/force_pose/SM (2 states) | - |

### `SM/Ground/Standing/PlantAndTurn/SM/S2N_complex/SM/S2N/SM`

Starts in s2n_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| s2n_crossleg_normal (starts here when move_speed_horizontal_previous >= 110) | clip planted_slow_s2n_crossleg_rifle | - |
| s2n_un_crossleg (starts here when not (move_speed_horizontal_previous >= 110)) | clip planted_slow_s2n_rifle | - |

### `SM/Ground/Standing/PlantAndTurn/SM/S2N_complex/SM/force_pose/SM`

Starts in S2N_force_crossleg_response.

| State | Plays | Goes to |
|---|---|---|
| S2N_force_crossleg_response (starts here when graph event Plant_N2S_crossleg (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| S2N_force_vanilla_response (starts here when graph event Plant_N2S (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |

### `SM/Ground/Standing/Idle/SM`

Starts in default.

| State | Plays | Goes to |
|---|---|---|
| default (starts here when not (action is action_c4_plant)) | a 1D blend on move_crouch_amount of idle_rifle at 0, idle_crouch_rifle at 1 | bomb_plant when action is action_c4_plant (0.2 s) |
| bomb_plant (starts here when action is action_c4_plant) | a 1D blend on move_crouch_amount of idle_rifle at 0, idle_crouch_rifle at 1 | default when not (action is action_c4_plant) (0.2 s) |

### `SM/Ground/Standing/TurnOnSpot/SM`

Starts in Turn Loop.

| State | Plays | Goes to |
|---|---|---|
| Small Turn (starts here when ground_action is ground_action_turn_on_spot) | a 1D blend on move_crouch_amount of Blend 1D at 0, Blend 1D at 1 | Turn Loop when ground_action is ground_action_turn_on_spot_loop (0.3 s, options 4) |
| Turn Loop (starts here when ground_action is ground_action_turn_on_spot_loop) | a 1D blend on move_crouch_amount of Blend 1D at 0, Blend 1D at 1 | Small Turn when ground_action is ground_action_turn_on_spot (0.3 s, options 4) |

### `SM/Ground/Standing/PlantAndTurnWalks/SM`

Starts in N2S_complex.

| State | Plays | Goes to |
|---|---|---|
| E2W (starts here when ground_action_direction_id is W) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| W2E (starts here when ground_action_direction_id is E) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| N2S_complex (starts here when ground_action_direction_id is S) | state machine SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM (2 states) | - |
| S2N_complex (starts here when ground_action_direction_id is N) | state machine SM/Ground/Standing/PlantAndTurnWalks/SM/S2N_complex/SM (2 states) | - |

From more than one state:

- to W2E when ground_action_direction_id is E (0.1 s), from any state
- to N2S_complex when ground_action_direction_id is S (0.2 s), from any state
- to S2N_complex when ground_action_direction_id is N (0.2 s), from any state
- to E2W when ground_action_direction_id is W (0.1 s), from any state

### `SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM`

Starts in N2S.

| State | Plays | Goes to |
|---|---|---|
| N2S (starts here when not (graph event Plant_S2N (Any) or Plant_S2N_crossleg (Any))) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| Force_pose (starts here when graph event Plant_S2N (Any) or Plant_S2N_crossleg (Any)) | state machine SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM/Force_pose/SM (2 states) | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM/N2S/SM`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 60) | clip planted_walk_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 60)) | clip planted_walk_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM/Force_pose/SM`

Starts in N2S_force_crossleg_response.

| State | Plays | Goes to |
|---|---|---|
| N2S_force_vanilla_response (starts here when graph event Plant_S2N (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| N2S_force_crossleg_response (starts here when graph event Plant_S2N_crossleg (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM/Force_pose/SM/N2S_force_vanilla_response/SM`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 60) | clip planted_walk_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 60)) | clip planted_walk_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/N2S_complex/SM/Force_pose/SM/N2S_force_vanilla_response/SM0`

Starts in n2s_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| n2s_crossleg_normal (starts here when move_speed_horizontal_previous >= 60) | clip planted_walk_n2s_crossleg_rifle | - |
| n2s_un_crossleg (starts here when not (move_speed_horizontal_previous >= 60)) | clip planted_walk_n2s_rifle | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/S2N_complex/SM`

Starts in S2N.

| State | Plays | Goes to |
|---|---|---|
| S2N (starts here when not (graph event Plant_N2S (Any) or Plant_N2S_crossleg (Any))) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| force_pose (starts here when graph event Plant_N2S (Any) or Plant_N2S_crossleg (Any)) | state machine SM/Ground/Standing/PlantAndTurnWalks/SM/S2N_complex/SM/force_pose/SM (2 states) | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/S2N_complex/SM/S2N/SM`

Starts in s2n_crossleg_normal.

| State | Plays | Goes to |
|---|---|---|
| s2n_crossleg_normal (starts here when move_speed_horizontal_previous >= 60) | clip planted_walk_s2n_crossleg_rifle | - |
| s2n_un_crossleg (starts here when not (move_speed_horizontal_previous >= 60)) | clip planted_walk_s2n_rifle | - |

### `SM/Ground/Standing/PlantAndTurnWalks/SM/S2N_complex/SM/force_pose/SM`

Starts in S2N_force_crossleg_response.

| State | Plays | Goes to |
|---|---|---|
| S2N_force_crossleg_response (starts here when graph event Plant_N2S_crossleg (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |
| S2N_force_vanilla_response (starts here when graph event Plant_N2S (Any)) | a 1D blend on move_crouch_amount of Selector at 0, idle_crouch_rifle at 1 | - |

### `SM/Ladder/Standing`

Starts in front.

| State | Plays | Goes to |
|---|---|---|
| front (starts here when ladder_angle_yaw in -125 to 125) | a 1D blend on ladder_angle_yaw of ladder_facing_fast_neg135_rifle at -135, ladder_facing_fast_neg90_rifle at -90, ladder_facing_fast_neg45_rifle at -45, ladder_facing_fast_rifle at 0, ladder_facing_fast_45_rifle at 45, ladder_facing_fast_90_rifle at 90, ladder_facing_fast_135_rifle at 135 | back when ladder_angle_yaw in -200 to -125 or ladder_angle_yaw in 125 to 200 (0.2 s) |
| back (starts here when not (ladder_angle_yaw in -125 to 125)) | a 1D blend on ladder_angle_yaw_backwards of ladder_back_fast_135_rifle at -135, ladder_back_fast_90_rifle at -90, ladder_back_fast_45_rifle at -45, ladder_back_fast_rifle at 0, ladder_back_fast_neg45_rifle at 45, ladder_back_fast_neg90_rifle at 90, ladder_back_fast_neg135_rifle at 135 | front when ladder_angle_yaw in -125 to 67.5 (0.2 s) |

### `SM/Ladder/Crouched`

Starts in front.

| State | Plays | Goes to |
|---|---|---|
| front (starts here when ladder_angle_yaw in -125 to 125) | a 1D blend on ladder_angle_yaw of ladder_facing_crouch_neg135_rifle at -135, ladder_facing_crouch_neg90_rifle at -90, ladder_facing_crouch_neg45_rifle at -45, ladder_facing_crouch_rifle at 0, ladder_facing_crouch_45_rifle at 45, ladder_facing_crouch_90_rifle at 90, ladder_facing_crouch_135_rifle at 135 | back when ladder_angle_yaw in -200 to -125 or ladder_angle_yaw in 125 to 200 (0.2 s) |
| back (starts here when not (ladder_angle_yaw in -125 to 125)) | a 1D blend on ladder_angle_yaw_backwards of ladder_back_crouch_135_rifle at -135, ladder_back_crouch_90_rifle at -90, ladder_back_crouch_45_rifle at -45, ladder_back_crouch_rifle at 0, ladder_back_crouch_neg45_rifle at 45, ladder_back_crouch_neg90_rifle at 90, ladder_back_crouch_neg135_rifle at 135 | front when ladder_angle_yaw in -125 to 67.5 (0.2 s) |

### `SM/InAir/SM`

Starts in Jump.

| State | Plays | Goes to |
|---|---|---|
| landing_blend (starts here when not (air_action is air_action_jump)) | a 1D blend on a curve of air_height_above_ground (10 to 0, 40 to 50) on a 5 Hz spring, damping 1, from 50 of Blend 1D at 10, Blend 1D at 50 | Jump when air_action is air_action_jump (0.2 s) |
| Jump (starts here when air_action is air_action_jump) | a 1D blend on move_crouch_amount_eased of Blend 2D at 0, Blend 2D at 1 | landing_blend when the state is done (0 s) |

## Blend spaces

- `SM/Ground/Standing/Move/Blend 2D`, on move_speed_x (held from the state's exit) and move_speed_y (held from the state's exit): idle_rifle (0, 0), run_n_rifle (225, 0), run_ne_rifle (159, -159), run_e_rifle (0, -225), run_se_rifle (-159, -159), run_s_rifle (-225, 0), run_sw_rifle (-159, 159), run_w_rifle (0, 225), run_nw_rifle (159, 159), walk_n_rifle (136, 0), walk_ne_rifle (96, -96), walk_e_rifle (0, -136), walk_se_rifle (-96, -96), walk_s_rifle (-136, 0), walk_sw_rifle (-96, 96), walk_w_rifle (0, 136), walk_nw_rifle (96, 96)
- `SM/Ground/Standing/Move/Blend 2D`, on move_speed_x and move_speed_y: idle_crouch_rifle (0, 0), crouch_n_rifle (96, 0), crouch_ne_rifle (67, -67), crouch_e_rifle (0, -96), crouch_se_rifle (-67, -67), crouch_s_rifle (-96, 0), crouch_sw_rifle (-67, 67), crouch_w_rifle (0, 96), crouch_nw_rifle (67, 67)
- `SM/InAir/SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_stand_rifle (0, 0), inair_n_rifle (225, 0), inair_e_rifle (0, -225), inair_s_rifle (-225, 0), inair_w_rifle (0, 225)
- `SM/InAir/SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_crouch_stand_rifle (0, 0), inair_crouch_n_rifle (96, 0), inair_crouch_e_rifle (0, -96), inair_crouch_s_rifle (-96, 0), inair_crouch_w_rifle (0, 96)
- `SM/InAir/SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_stand_rifle (0, 0), inair_n_rifle (225, 0), inair_e_rifle (0, -225), inair_s_rifle (-225, 0), inair_w_rifle (0, 225)
- `SM/InAir/SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_crouch_stand_rifle (0, 0), inair_crouch_n_rifle (96, 0), inair_crouch_e_rifle (0, -96), inair_crouch_s_rifle (-96, 0), inair_crouch_w_rifle (0, 96)
- `SM/InAir/SM/Jump/Blend 2D`, on move_speed_x and move_speed_y: jump_stand_rifle (0, 0), jump_n_rifle (225, 0), jump_e_rifle (0, -225), jump_s_rifle (-225, 0), jump_w_rifle (0, 225)
- `SM/InAir/SM/Jump/Blend 2D`, on move_speed_x and move_speed_y: jump_crouch_stand_rifle (0, 0), jump_crouch_n_rifle (96, 0), jump_crouch_e_rifle (0, -96), jump_crouch_s_rifle (-96, 0), jump_crouch_w_rifle (0, 96)
- `SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_stand_rifle (0, 0), inair_n_rifle (225, 0), inair_e_rifle (0, -225), inair_s_rifle (-225, 0), inair_w_rifle (0, 225)
- `SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_crouch_stand_rifle (0, 0), inair_crouch_n_rifle (96, 0), inair_crouch_e_rifle (0, -96), inair_crouch_s_rifle (-96, 0), inair_crouch_w_rifle (0, 96)
- `SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_stand_rifle (0, 0), inair_n_rifle (225, 0), inair_e_rifle (0, -225), inair_s_rifle (-225, 0), inair_w_rifle (0, 225)
- `SM/landing_blend/Blend 2D`, on move_speed_x and move_speed_y: inair_crouch_stand_rifle (0, 0), inair_crouch_n_rifle (96, 0), inair_crouch_e_rifle (0, -96), inair_crouch_s_rifle (-96, 0), inair_crouch_w_rifle (0, 96)
- `SM/Jump/Blend 2D`, on move_speed_x and move_speed_y: jump_stand_rifle (0, 0), jump_n_rifle (225, 0), jump_e_rifle (0, -225), jump_s_rifle (-225, 0), jump_w_rifle (0, 225)
- `SM/Jump/Blend 2D`, on move_speed_x and move_speed_y: jump_crouch_stand_rifle (0, 0), jump_crouch_n_rifle (96, 0), jump_crouch_e_rifle (0, -96), jump_crouch_s_rifle (-96, 0), jump_crouch_w_rifle (0, 96)
