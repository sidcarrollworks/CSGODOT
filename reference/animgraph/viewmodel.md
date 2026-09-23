# The first-person gun

Written by `scripts/animgraph_tables.gd` on 2026-09-23 from `animation/graphs/viewmodel/viewmodel_gun.vnmgraph+ak47.vnmgraph_c` in CS2 1.41.8.2. Do not edit by hand; `reference/animgraph2.md` says how to read it.

`viewmodel_gun.vnmgraph`, the graph that plays a gun's first-person clips (`viewmodel.vnmgraph` runs it, and the knife's, grenade's and the inspects' graphs, by what is in hand). Its clips are shown for the ak47; every gun but the CZ75-Auto, the Dual Berettas and the R8 Revolver, which have graphs of their own, is a variation of it.

Each node is named by its path in Valve's editor. Conditions are written out with the parameters by name (`parameters.md` has their values); a transition's blend is its length, then its easing and options where they are not the plain ones. (options is Esoterica's transition-option bit field, which Valve's version orders its own way.)

## From the root

1. `Scale` Scale (Mask: mask silencer; Enable: weapon_type is one of weapon_usp_silencer, weapon_m4a1_silencer and (not (weapon_is_silenced or event WPN_SHOW_SILENCER)))
2. `LayerBlend` Layer Blend
3. `StateMachine` actions

## Layers

`Layer Blend`, over state machine actions (2 states):

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `HideBullets` | state machine HideBullets (4 states) | the state's | - | Additive | no |

`actions/Actions/Layer Blend`, over state machine actions/Actions/SM (6 states):

| Layer | Plays | Weight | Bone mask | Blend | Synced |
|---|---|---|---|---|---|
| `actions/Actions/EmptyPose` | state machine actions/Actions/EmptyPose (2 states) | the state's | - | Overlay | no |
| `actions/Actions/m249_negev_settle` | state machine actions/Actions/m249_negev_settle (3 states) | the state's | - | Additive | no |


## State machines (11)

### `actions`

Starts in Attack.

| State | Plays | Goes to |
|---|---|---|
| Attack (starts here when action is action_attack) | state machine actions/Attack/SM (2 states) | Actions when weapon_is_gun and not (action is action_attack) ((action is action_deploy ? 0 : 0.2) s) |
| Actions (starts here when not (action is action_attack)) | state machine actions/Actions/SM (6 states), with 2 layers | Attack when weapon_is_gun and (action is action_attack and event WPN_ENTERING_IRONSIGHTS) (0 s, can interrupt)<br>Attack when weapon_is_gun and action is action_attack and (not (action is action_attack and event WPN_ENTERING_IRONSIGHTS)) (0 s, can interrupt) |

### `actions/Attack/SM`

Starts in ATK0.

| State | Plays | Goes to |
|---|---|---|
| ATK0 | the first of: clip shoot1_ak if not weapon_is_using_ironsights and not (weapon_ammo = 0); no clip (the slot is empty in this variation) if weapon_type is one of weapon_sg556, weapon_aug, weapon_temp and weapon_ironsight_amount >= 0.1; clip shoot1_ak if not weapon_is_using_ironsights and weapon_ammo = 0 | ATK2 when action_reset and action is action_attack (0 s) |
| ATK2 | the first of: clip shoot1_ak if not weapon_is_using_ironsights and not (weapon_ammo = 0); no clip (the slot is empty in this variation) if weapon_type is one of weapon_sg556, weapon_aug, weapon_temp and weapon_ironsight_amount >= 0.1; clip shoot1_ak if not weapon_is_using_ironsights and weapon_ammo = 0 | ATK0 when action_reset and action is action_attack (0 s) |

### `actions/Actions/SM`

Starts in Idle.

| State | Plays | Goes to |
|---|---|---|
| SilencerOff (starts here when action is action_silencer_detach) | no clip (the slot is empty in this variation) | - |
| Inspect (starts here when action is action_inspect) | the viewmodel_inspects graph (ak47) | Idle when action is one of action_idle, (none) and not (weapon_ironsight_amount > 0) (0.3 s, InOutQuad)<br>Idle when action is one of action_idle, (none) and weapon_ironsight_amount > 0 (0 s, InOutQuad) |
| Reload (starts here when action is action_reload) | state machine actions/Actions/SM/Reload/SM (2 states) | - |
| Idle (starts here when action is one of action_idle, (none)) | a 1D blend on weapon_ironsight_amount of idle_ak at 0, IronsightPose at 1 | - |
| Deploying (starts here when action is action_deploy) | state machine actions/Actions/SM/Deploying/SM (2 states) | Inspect when action is action_inspect and (not (event WPN_INSPECT_USE_DRAW_VERSION or event WPN_INSPECT_USE_FIXUP_VERSION)) (0.65 s)<br>Inspect when action is action_inspect and event WPN_INSPECT_USE_DRAW_VERSION (0.2 s)<br>Inspect when action is action_inspect and event WPN_INSPECT_USE_FIXUP_VERSION (0.2 s) |
| SilencerOn (starts here when action is action_silencer_attach) | no clip (the slot is empty in this variation) | - |

From more than one state:

- to Inspect when weapon_is_gun and action is action_inspect ((graph event WPN_STATE_IDLE (FullyInState) ? 0.4 : 0.65) s, InOutQuad, can interrupt), from SilencerOff, Reload, Idle, SilencerOn
- to Reload when weapon_is_gun and action is action_reload (0.2 s, options 40), from any state
- to Idle when weapon_is_gun and action is one of action_idle, (none) (0.2 s), from SilencerOff, Reload, Deploying, SilencerOn
- to Deploying when weapon_is_gun and action is action_deploy (0 s), from any state
- to SilencerOn when weapon_is_gun and action is action_silencer_attach (0.2 s), from any state
- to SilencerOff when weapon_is_gun and action is action_silencer_detach (0.2 s), from any state

### `actions/Actions/SM/Reload/SM`

Starts in Reload1.

| State | Plays | Goes to |
|---|---|---|
| Reload1 | the first of: clip reload_ak if not (weapon_ammo = 0); clip reload_ak if weapon_ammo = 0 | Reload0 when reload_stage is not stage_outro and the state's current sync event is WPN_RELOAD_OUTRO (0 s, options 40) |
| Reload0 | the first of: clip reload_ak if not (weapon_ammo = 0); clip reload_ak if weapon_ammo = 0 | Reload1 when reload_stage is not stage_outro and the state's current sync event is WPN_RELOAD_OUTRO (0 s, options 40) |

### `actions/Actions/SM/Deploying/SM`

Starts in Deploy0.

| State | Plays | Goes to |
|---|---|---|
| Deploy0 | by deploy_variation, one of: clip draw_ak; no clip (the slot is empty in this variation) | Deploy2 when action_reset and action is action_deploy (0 s) |
| Deploy2 | by deploy_variation, one of: clip draw_ak; no clip (the slot is empty in this variation) | Deploy0 when action_reset and action is action_deploy (0 s) |

### `actions/Actions/EmptyPose`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| EmptyPose (starts here when weapon_ammo = 0 and weapon_ammo_reserve = 0) | a pose | Off when not (weapon_ammo = 0) (0 s) |
| Off (starts here when not (weapon_ammo = 0 and weapon_ammo_reserve = 0)) |   | EmptyPose when weapon_ammo = 0 (0 s) |

### `actions/Actions/m249_negev_settle`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| settle animation | clip idle_from_activity_m249 | Off when the state is done (0 s) |
| Off |   | activity_state when weapon_type is one of weapon_m249, weapon_negev and action is one of action_deploy, action_inspect, action_reload (0.2 s) |
| activity_state |   | settle animation when action is action_idle (0.3 s) |

### `HideBullets`

Starts in Off.

| State | Plays | Goes to |
|---|---|---|
| m249 (starts here when weapon_type is weapon_m249 and weapon_ammo <= 17) | state machine HideBullets/m249/SM (2 states) | - |
| Off |   | - |
| Negev (starts here when weapon_type is weapon_negev and weapon_ammo <= 17) | state machine HideBullets/Negev/SM (2 states) | - |
| XM1014 (starts here when weapon_type is weapon_xm1014 and weapon_ammo <= 17) | state machine HideBullets/XM1014/SM (3 states) | - |

From more than one state:

- to Off when (not (weapon_type is weapon_m249 and weapon_ammo <= 17 and not (event WPN_SHOW_BULLETS))) and (not (weapon_type is weapon_negev and weapon_ammo <= 17 and not (event WPN_SHOW_BULLETS))) and (not (weapon_type is weapon_xm1014 and weapon_ammo_reload_count <= 4 and not (event WPN_SHOW_BULLETS))) (0.2 s), from any state
- to Negev when weapon_type is weapon_negev and weapon_ammo <= 17 and not (event WPN_SHOW_BULLETS) (0.2 s), from any state
- to XM1014 when weapon_type is weapon_xm1014 and weapon_ammo_reload_count <= 4 and not (event WPN_SHOW_BULLETS) (0.2 s), from any state
- to m249 when weapon_type is weapon_m249 and weapon_ammo <= 17 and not (event WPN_SHOW_BULLETS) (0.2 s), from any state

### `HideBullets/m249/SM`

Starts in Odd.

| State | Plays | Goes to |
|---|---|---|
| Odd (starts here when not ((weapon_ammo Mod 2) = 0)) | a pose | Even when (weapon_ammo Mod 2) = 0 (0 s) |
| Even (starts here when (weapon_ammo Mod 2) = 0) | a pose | Odd when not ((weapon_ammo Mod 2) = 0) (0 s) |

### `HideBullets/Negev/SM`

Starts in Odd.

| State | Plays | Goes to |
|---|---|---|
| Odd (starts here when not ((weapon_ammo Mod 2) = 0)) | a pose | Even when (weapon_ammo Mod 2) = 0 (0 s) |
| Even (starts here when (weapon_ammo Mod 2) = 0) | a pose | Odd when not ((weapon_ammo Mod 2) = 0) (0 s) |

### `HideBullets/XM1014/SM`

Starts in Odd.

| State | Plays | Goes to |
|---|---|---|
| Odd (starts here when not (event WPN_HIDE_BULLETS) and not ((weapon_ammo Mod 2) = 0)) | a pose | - |
| Even (starts here when not (event WPN_HIDE_BULLETS) and (weapon_ammo Mod 2) = 0) | a pose | - |
| HideAll (starts here when event WPN_HIDE_BULLETS) | a pose | - |

From more than one state:

- to Even when not (event WPN_HIDE_BULLETS) and (weapon_ammo Mod 2) = 0 (0 s), from any state
- to HideAll when event WPN_HIDE_BULLETS (0 s), from any state
- to Odd when not (event WPN_HIDE_BULLETS) and not ((weapon_ammo Mod 2) = 0) (0 s), from any state
