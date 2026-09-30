# Foot IK: how CS2 plants third-person feet on slopes

Research for playtest 2026-09-25 issue 5 (bots hover over T spawn's
ramp, `reference/playtest-2026-09-25.md`), written 2026-09-28. Public
sources only; no leaked Valve code was read. Marks: **VERIFIED** (read in the named file or page) and
**INFERRED** (reasoned from verified facts; says from what).

## Sources

| Key | Source | Version read |
|---|---|---|
| ES | Esoterica, Bobby Anguelov, MIT: github.com/BobbyAnguelov/Esoterica | commit 8c673cf (2026-09-09) |
| SCH | SteamTracking/GameTracking-CS2 `DumpSource2/schemas/` | commit 3fc98e7 (2026-09-25) |
| CV / CMD | same repo, `DumpSource2/convars.txt`, `DumpSource2/commands.txt` | same |
| SS / CS | same repo, `game/csgo/bin/win64/server_strings.txt`, `client_strings.txt` | same |
| VN | Valve's notes (counter-strike.net/news/updates) as archived by github.com/ckreisl/cs-updates-as-json, `data/cs2/updates_raw.json` | commit 9f71dbe (2026-09-26), 234 posts |
| WG | `reference/animgraph/worldmodel.md:14` (CS2 1.41.8.3) | in repo |

## Summary

- CS2's `FootIK` is Esoterica's foot IK node: a **two-bone IK on each leg**
  (ankle, its parent, its grandparent) towards a target the game supplies.
  It **does not move the pelvis or root**, does not clamp the target (an
  unreachable target straightens the leg towards it), and sets the ankle's
  rotation to the target's. Its blend time only fades the whole node in or
  out when its Enabled input flips; CS2's is 0.0.
- The game code, not the graph, decides the targets: CS2's animation state
  keeps a **per-foot float offset**, `m_flFootIKOffsetLeft/Right`
  (SCH). The smoothing Valve keeps tuning ("Made foot IK transitions
  smoother") must live there, since the node's own blend is 0.
- Height on slopes is a **movement** matter in CS2: the networked
  `m_bUsingGroundTopologyOffset` on `CCSPlayer_MovementServices`, and Valve's
  note that the change moved grenade lineups, i.e. the eye. How far the body
  drops is in no public file.
- The **server runs the graph, FootIK included**, and networks the pose's
  task list to clients (Esoterica's task serialisation, which CS2 carries as
  `m_SerializePoseRecipeAG2*`). So the server's leg hitboxes almost certainly
  include the foot IK (INFERRED; Local check below).
- What to copy: draw-only is **not** CS2's model. CS2's leg pose (and leg
  hitboxes) is decided on the server from the game's own ground traces. We
  should run a per-foot ground offset + two-bone leg IK on the tick's pose
  (or at least in the pose the hitboxes read), keep the pelvis where the
  animation puts it, and add any whole-body lowering to the movement side.

## 1. What the FootIK node does

**The CS2 node is Esoterica's.** VERIFIED: CS2's node definition
(`SCH animlib/CNmFootIKNode__CDefinition.h`) has the same fields in the same
order as Esoterica's `FootIKNode::Definition`
(`ES Code/Engine/Animation/Graph/Nodes/Animation_RuntimeGraphNode_FootIK.h:24-31`):
left/right effector bone, left/right target node, enable node, blend time,
blend mode, target-in-world-space. CS2's runtime task `CNmFootIKTask`
(`SCH animlib/CNmFootIKTask.h`) matches Esoterica's `FootIKTask`
(`ES .../TaskSystem/Tasks/Animation_Task_FootIK.h:37-51`) field for field.
That CS2's code does exactly what Esoterica's does is INFERRED from that
match; Valve may have changed the bodies.

What Esoterica's node does (VERIFIED, ES):

- **Setup.** Each effector must have at least two ancestors; the chain is
  effector, parent, grandparent (`Animation_RuntimeGraphNode_FootIK.cpp:37-73`).
  In CS2 that is `ankle_L` (WG) and, INFERRED from the rig's bone names in
  `reference/asset-pipeline.md:49` and `ragdoll-joints.md:41`,
  `leg_lower_L`, `leg_upper_L`. Check the parents in the vnmskel.
- **Update** (`:111-192`). Pass the child pose through; update the IK
  weight from the Enabled bool; if weight > 0 and both targets are set,
  register one `FootIKTask`; if only one target is set, a single
  `TwoBoneIKTask` for that leg. **A target the game leaves unset turns IK off
  for that foot** (`IsTargetSet`, `:167-187`).
- **Solve** (`Animation_Task_FootIK.cpp:44-93`). Read each target's
  transform; if `m_isTargetInWorldSpace` and not a bone target, convert it
  to character space by the inverse world transform (`:56-58`); otherwise it
  is already **character (model) space**. Then
  `TwoBoneSolver::Solve` on each leg with chain-rotation weight 0.
- **Two-bone solver** (`ES Code/Engine/Animation/IK/TwoBoneIK.cpp:97-167`):
  law of cosines bends the knee so hip-to-ankle equals hip-to-target
  (`:121`), about the current knee plane (or the reference pose's if the leg
  is straight, `:129-151`); then rotates the hip bone so the ankle points at
  the target (`:164`); **then sets the ankle's rotation to the target's
  rotation** (`:167`). The only clamp is `cosThetaDesired` to [-1, 1]
  (`:121`): a target beyond reach gives a straight leg aimed at it, the foot
  short of it. **No pelvis or root motion, no length or angle limits.**
- **Blend.** `IKBlendMode::Effector` (the default, and CS2's enum
  `NmIKBlendMode_t { Effector = 0, Pose = 1 }`, SCH
  `animlib/NmIKBlendMode_t.h`) slerps the target from the animated ankle
  towards the IK target by the weight before solving (`TwoBoneIK.cpp:48-52`);
  `Pose` blends the solved local transforms instead (`:71-82`).
  The weight comes from `Math::BlendWeight` (`ES Code/Base/Math/BlendWeight.cpp:70-134`):
  a linear ramp over `m_blendTime` each time Enabled flips, reversible
  mid-blend. With no Enabled input the weight is 1 from the start
  (`Animation_RuntimeGraphNode_FootIK.cpp:91-94`).

CS2's instance (WG): `ankle_L`, `ankle_R`, targets `ik_left_foot`,
`ik_right_foot`, `BlendTimeSeconds 0.0`. The generator
(`scripts/animgraph_tables.gd`) does not print `m_blendMode`,
`m_bIsTargetInWorldSpace` or `m_nEnabledNodeIdx`; the schema's defaults are
Effector, false, -1 (SCH). INFERRED: CS2 uses character-space targets and
no Enabled input, so the node is either fully on or off per foot by whether
the target is set. **Re-extract those three fields** (Remote once assets
exist, or Local): if Enabled is wired, blend time 0 means it snaps.

Placement in the graph (WG:11-17, VERIFIED): FootIK sits over the
locomotion and all additive layers, under `AimCS` and the flashed layer. So
the legs are solved after flinches and landings; the aim then turns the
upper body.

## 2. Schema fields

Verbatim, SCH commit 3fc98e7:

- `animlib/CNmFootIKNode__CDefinition.h`: `class CNmFootIKNode::CDefinition
  : public CNmPassthroughNode::CDefinition { CGlobalSymbol
  m_leftEffectorBoneID; CGlobalSymbol m_rightEffectorBoneID; int16
  m_nLeftTargetNodeIdx; int16 m_nRightTargetNodeIdx; int16 m_nEnabledNodeIdx;
  float32 m_flBlendTimeSeconds; NmIKBlendMode_t m_blendMode; bool
  m_bIsTargetInWorldSpace; }` (defaults: indices -1, 0.0, "Effector", false).
- `animlib/CNmFootIKTask.h`: `m_nLeftEffectorBoneIdx, m_nRightEffectorBoneIdx,
  CTransform m_leftTargetTransform, m_rightTargetTransform,
  m_nLeftTargetBoneIdx, m_nRightTargetBoneIdx, CNmTarget m_leftTarget,
  m_rightTarget, NmIKBlendMode_t m_blendMode, float32 m_flBlendWeight, bool
  m_bIsTargetInWorldSpace, bool m_bIsRunningFromDeserializedData`.
- `animlib/CNmTarget.h`: `CTransform m_transform; CGlobalSymbol m_boneID;
  bool m_bIsBoneTarget, m_bIsUsingBoneSpaceOffsets, m_bHasOffsets, m_bIsSet`.
- `animdoclib/CnmGraphDocFootIKNode.h` (editor): input pins "Input" (Pose),
  "Left Foot Target", "Right Foot Target" (Target), "Enabled" (Bool); output
  "Result". `..._CData.h`: `m_leftEffectorBoneName`,
  `m_rightEffectorBoneName`, `m_flBlendTimeSeconds`.
- `client/CCSPlayerAnimationState.h` (the type is also the server's
  `CCSPlayer_MovementServices::m_AnimationState`): `m_currentMoveType`,
  `m_groundMoveState`, ..., **`float32 m_flFootIKOffsetLeft; float32
  m_flFootIKOffsetRight;`**, `m_flWeaponDropPercentageDueToMovement`, ...
- `server/CCSPlayer_MovementServices.h:3-5` (and `client/` the same):
  `CCSPlayerAnimationState m_AnimationState; bool m_bUsingGroundTopologyOffset;
  float32 m_flUsingGroundTopologyOffsetTransitionSmoothing;`
- `server/CPlayer_MovementServices_Humanoid.h`: `Vector m_groundNormal`
  (MNotSaved), `m_flSurfaceFriction`, `m_vecSmoothedVelocity`, ...
- `server/CBaseAnimGraphController.h`: `CUtlVectorEmbeddedNetworkVar<
  AnimGraph2SerializedPoseRecipeSlot_t > m_SerializePoseRecipeAG2Slots;
  CNetworkUtlVectorBase< uint8 > m_SerializePoseRecipeAG2Dynamic; uint32
  m_nSerializePoseRecipeAG2ActiveSlot; int32 m_nSerializePoseRecipeVersionAG2;`
  and `AnimGraph2SerializedPoseRecipeSlot_t { CUtlBinaryBlock m_topology; }`.

Networking, VERIFIED from the DLL strings: both DLLs carry
`CNetworkVarBase<...NetworkVar_m_bUsingGroundTopologyOffset@CCSPlayer_MovementServices>`
and `...m_flUsingGroundTopologyOffsetTransitionSmoothing...` (SS:4960, 4311;
CS:6407, 5751) and `...NetworkVar_m_topology@AnimGraph2SerializedPoseRecipeSlot_t`
(SS:4481). Both DLLs hold `CNmFootIKNode`, `CNmFootIKTask`, `ik_left_foot`,
`ik_right_foot` (SS:2407, 7182-7183, 27182-27183; CS:3561, 8924-8925,
33988-33989) and the task's debug name "Foot IK" (SS:16196).
`m_flFootIKOffsetLeft/Right` have no NetworkVar string (INFERRED: not
networked by itself; it reaches clients inside the pose recipe or is
recomputed).

No schema field names a pelvis offset, feet traces or a hip drop for AG2.
The `animgraph_footlock_*` convars (`animgraph_footlock_hip_offset_enable`,
`_use_hip_shift`, `_trace_ground_enabled`, `_ik_enable`, CV:289-326) and
`ik_debug_groundtraces` (CV:4009) belong to Source 2's older AnimGraph 1
`CFootLockUpdateNode` (SCH `animgraphlib/`); INFERRED not used by CS2's AG2
player graph, which has no foot-lock node (WG).

## 3. Valve's notes

VERIFIED, VN, dated by post time (UTC); headings in brackets are Valve's.

- 2023-08-02: "Improved foot animation when quickly alternating between
  standing still and moving".
- 2023-09-29: "Fixed a case where foot pinning wasn't active".
- 2023-10-10 (notes for 10/9): "Fixed several hitbox alignment bugs".
- 2023-10-12: "Fixed the \"Smooth Criminal\" foot pinning bug".
- 2023-11-02: "For a given map location, eye height is now consistent
  regardless of how the player arrived".
- 2023-11-30: "Improved foot placement and posing when running".
- 2024-10-02 [ANIMATION]: "Improved character posing when on large slopes";
  "Made feet pin and unpin differently for all use cases to help remove
  aggressively leaned characters (AKA the MJ lean)"; "Pin/unpin IK logic now
  not affected by poor server ping times"; "Feet IK now repositions to idle
  pose if the feet have pinned at a largely different pose to that authored".
- 2024-11-07 [ANIMATION]: "Fixes for IK logic to improve third-person feet
  posing, especially on slopes." "Fixed a case where the feet and legs of
  players could pop out of position when exiting the bomb-plant animation."
  "Reduced animation-related network bandwidth usage."
- 2026-04-01 [ANIMGRAPH 2] (beta): "The CS2 animation system has been
  updated to Animgraph 2, which reduces CPU and networking costs associated
  with animation." ... "In support of Animgraph 2, the logic adjusting
  player height on sloped surfaces has been refactored." "Player height on
  ramps is now consistent and no longer depends on approach direction." "As
  a result of this change, grenade lineups on sloped surfaces may have
  changed."
- 2026-04-17 [ANIMGRAPH 2] (beta): "Adjusted foot IK when idle".
- 2026-04-22 [GAMEPLAY]: "Adjusted ground smoothing at locations where the
  player can stand on very thin ledges."
- 2026-04-24 [ANIMGRAPH 2]: "Made foot IK transitions smoother." (same post:
  "Fixed a case where legs would snap when quickly stopping and then
  continuing in same direction.")
- 2026-04-30 [MISC]: "Adjusted ground smoothing at locations where sloped
  ground surfaces join with step-height transitions."
- 2026-05-07 [MISC]: "Minor adjustments to ground smoothing transitions when
  leaving the ground and when landing."

Readings (INFERRED): "pinning"/"pin and unpin" in 2023-24 is AnimGraph 1's
foot lock; since AG2 the wording is "foot IK". "Player height on sloped
surfaces" changing grenade lineups means it moves the eye, so it is movement
code (the ground-topology offset, a networked movement field), not just the
drawn body. "Ground smoothing" is the same system: a smoothed ground height
under the player, eased on take-off and landing
(`m_flUsingGroundTopologyOffsetTransitionSmoothing`). Community pages
(eastgate.host, refrag.gg, white.market, found by web search 2026-09-28)
restate the notes with no measurements; not used as evidence.

## 4. Do the server's hitboxes include the IK?

- VERIFIED: the server DLL contains the FootIK node, its task and the two
  target parameter names (SS above), and the server's movement services
  own `m_AnimationState` with the per-foot IK offsets (SCH).
- VERIFIED (ES): Esoterica's task system serialises the executed task list
  as "topology" and task data (`ES Code/Engine/Animation/TaskSystem/Animation_TaskSystem.h:184-190`,
  `SerializeTasks(..., Blob& outSerializedTopologyData, Blob&
  outSerializedTaskData)`), and `FootIKTask::Serialize` writes each target's
  rotation and quantised translation (`Animation_Task_FootIK.cpp:105-153`).
  CS2 networks `AnimGraph2SerializedPoseRecipeSlot_t::m_topology` and
  `m_SerializePoseRecipeAG2Dynamic` (SCH, SS:4481).
- INFERRED, strongly: the server runs the full third-person graph including
  FootIK, and clients rebuild the server's pose from the networked recipe
  (VN 2026-04-01: AG2 "reduces ... networking costs"). The lag-compensated
  hitboxes are posed from that, so **leg hitboxes follow the IK'd legs** on
  the server. `sv_csgo_shoot_lagcompensation_max_error` checks only the head
  (CV:10965-10966), which the foot IK does not move unless the body drops.
- Unknown: whether the server's lag-compensation record stores the pose
  after FootIK or before. Check it Local.

## 5. Does the body drop on slopes?

- VERIFIED: a networked movement flag and smoothing value for a "ground
  topology offset" exist (section 2); Valve says height on ramps is
  consistent and moved lineups (section 3).
- INFERRED: the whole player (eye and model origin) is offset to a smoothed
  ground height on slopes; the pelvis is not lowered separately by the
  graph, since FootIK never touches it (section 1) and no AG2 field names a
  hip offset. The per-foot offsets then reach the lower foot's ground.
- **How much**: no public file or note gives a number. Measure it (Local 2).
  Watch for the sign: on a ramp the hull's box rests on its uphill edge, so
  the origin sits above the ground under its centre by
  `16 * tan(slope)` units (hull half-width 16); an offset that lowers the
  origin towards the centre's ground would explain "consistent height". Our
  bots' hover (roadmap item 5) is exactly that gap (INFERRED).

## 6. What to copy

1. Per foot, on the tick: trace down from above each ankle's animated
   position; offset = ground height minus the animated foot's height,
   clamped to about the step height; ease it (CS2's name suggests a float
   per foot, `m_flFootIKOffsetLeft/Right`). Keep it server state; the drawn
   model reads it.
2. Two-bone IK on `leg_upper`/`leg_lower`/`ankle` (Esoterica's solver above
   is short and MIT; Godot 4.7's `TwoBoneIK3D`/`SkeletonModifier3D` may do,
   see `reference/godot/`), ankle rotation aligned to the ground normal,
   pelvis untouched, applied before the hitboxes are read
   (twist-constraints.md:152-157 says a modifier's result is what
   `SkinnedHitboxes` reads).
3. A ground-topology offset for the whole player in movement, only once
   Local 2 gives its size; until then leave the eye alone (lineups).
4. Cost: two short traces per player per tick; count them with
   `scripts/profile_dust2.gd`.

## 7. What this project does now (issue 5's Remote part)

`FootPlant` (`src/player/foot_plant.gd`), a `SkeletonModifier3D` on every
third-person body's rig (`PlayerModel.foot_plant`), before the twist
bones' modifiers:

- **When:** alive and on the ground, seen or not
  (`PlayerModel.plants_feet`), since the hitboxes ride the legs it bends,
  as CS2's server hitboxes most likely do (section 4). It eases in and out
  over 0.1 s and follows a changing floor over the same (CS2's smoothing
  lives in the game code, section 1; its time is a guess).
- **Rays:** one per ankle, straight down from the body's origin height
  under the ankle, world layer only (`GroundProbe.ground_below`, the helper
  issue 17 built), up to 12 units; cast again only once that ankle has
  moved a unit. Standing still costs no rays after the first. A foot over a
  deeper gap is left where the clip has it, as CS2 leaves a foot whose
  target is unset.
- **Legs:** two-bone IK on `leg_upper`/`leg_lower`/`ankle`, bending about
  the knee's current plane as Esoterica's solver does, each foot brought
  down by its own gap from where the clip has it (so a stride keeps its
  lift), the ankle tipped toward the ground's normal (up to 30 degrees).
- **Pelvis:** lowered by the larger gap (up to 12 units). CS2's graph does
  not do this; it lowers the whole player in movement (section 5). Without
  it the downhill foot of a near-straight idle leg cannot reach the floor,
  so this stands in for CS2's ground-topology offset on the drawn body and
  its hitboxes, while the eye stays at the hull's until Local 2 gives
  CS2's number.
- **Rest clearance:** under Box3D a standing hull rests 0.257 inch off the floor, so 0.3 comes off each foot's gap (`FootPlant.REST_CLEARANCE`): no fit on flat ground.
- **Where it runs:** in the skeleton's deferred update, each frame, like
  the pose the hitboxes already follow; its rays are frame-time queries
  (`reference/godot/physics.md`). A flat floor costs no fit.
- **Checks:** `tests/run_foot_plant_checks.gd`, a stand-in leg skeleton on
  a 13 degree ramp; the agents' own legs in `tests/run_model_checks.gd`
  (with assets).

Left for later, each once its Local check answers it: lowering the eye on
slopes (movement's ground-topology offset, Local 2), the IK on the tick
rather than the frame if Local 3 shows CS2's lag-compensated hitboxes carry
it, and CS2's easing times (Local 4).

## 8. Local checks (Sid, CS2)

Setup: `sv_cheats 1; mp_warmup_end; mp_freezetime 60; mp_roundtime 60;
bot_stop 1; bot_add_t` (or `bot_place` a bot on the ramp), on dust2's T
spawn ramp and on long doors' slope.

1. **Feet.** Side-on screenshots of a standing bot, from both sides and
   along the slope: does the downhill foot reach the ground, does the uphill
   knee bend more, does the foot tilt to the slope? Repeat crouched and
   walking (`bot_stop 0`, `bot_mimic 1`).
2. **Body height.** `cl_showpos 1` on flat ground by the ramp, then stand at
   the same spot on the ramp approached from uphill and downhill: note Z
   and eye height. `cl_ent_bbox` / `ent_bbox` on a bot on the ramp against
   the model: how far does the model's origin sit below the box bottom's
   uphill edge? Screenshot the gap at the downhill edge.
3. **Hitboxes follow the feet?** `ent_hitbox` (server, CMD:1315) and
   `cl_ent_hitbox` (client, CMD:533) on the ramp bot, side-on: do the leg
   and foot capsules bend with the IK'd legs, and do server and client
   agree? Then `sv_showhitregistration 3` (CV:11721, "Display lag_compensated
   hitboxes. 0 = off, 1 = server only, 2 = client only, 3 = both") and shoot
   the downhill ankle: do the server boxes sit on the drawn foot?
4. **Transitions.** Walk a bot over the ramp's lip (`bot_mimic`) and watch
   `host_timescale 0.2`: does the foot ease to the ground or snap? Time it.
5. **Ledges and stairs.** Stand half off a box edge and on dust2's stairs:
   does one foot hang (IK target unset) or reach down?
6. **Extraction.** Re-run `scripts/animgraph_tables.gd` printing FootIK's
   `m_blendMode`, `m_bIsTargetInWorldSpace`, `m_nEnabledNodeIdx`, and dump
   `ankle_L`'s two parents from the vnmskel.
