# Ragdolls: CS2's shapes, joint limits, and staying on a one-sided floor

Written for issue 4 of the 2026-09-25 playtest (`reference/playtest-2026-09-25.md`):
a dead T's legs sank through T spawn's road, and an elbow and a hip bent
past what a body allows. What `src/combat/ragdoll.gd` does now, and why, is
here; the checks are `tests/run_ragdoll_checks.gd`.

## Sources

- **CS2's ragdoll shapes.** The agents' decompiled model descriptions
  (`assets/characters/agents/models/tm_phoenix/tm_phoenix_varianta.vmdl`,
  `ctm_sas.vmdl`), as the playtest page's investigator read them on Sid's
  machine: a `PhysicsShapeList` of 12 capsules and 3 spheres on 15 bones,
  surface `playerflesh`. **Primary** (CS2's files; extraction of 2026-09-21/22).
- **How Source 2 Viewer writes them, and joints.** ValveResourceFormat,
  `ValveResourceFormat/IO/Extract/ModelExtract.Physics.cs` and
  `ModelExtract.PhysicsJoints.cs` at `f3ad9fb` (2026-09-25). **Primary** for
  the file format.
- **Godot's joints on Jolt.** Godot 4.7.2-stable source:
  `scene/3d/physics/joints/joint_3d.cpp`, `generic_6dof_joint_3d.cpp`,
  `modules/jolt_physics/joints/jolt_generic_6dof_joint_3d.cpp`,
  `jolt_hinge_joint_3d.cpp`, and a headless experiment in this thread.
  **Primary.**
- **CS2's playerflesh.** `reference/surfaces/surfaces.csv` (generated from
  CS2's `surfaceproperties.vsurf`): friction 0.8, elasticity 0.25, density
  900. **Primary.**
- **Human joint ranges.** The commonly cited clinical norms (American
  Academy of Orthopaedic Surgeons, *Joint Motion: Method of Measuring and
  Recording*, 1965; Soucie et al., "Range of motion measurements: reference
  values and a database for comparison studies", *Haemophilia* 17(3), 2011).
  Taken as widely quoted; the papers themselves were not re-read in this
  thread. **Secondary**, and a stand-in until CS2's own joints are read.

No current primary source gives CS2's joint limits, masses or damping in a
form this project has: the decompiled `.vmdl` from Source2Viewer-CLI 20.0
holds no `PhysicsJoint` node.

## What CS2's ragdoll is

- **Fifteen bodies**, one per shape: `pelvis`, `spine_2`, `head_0`, and each
  side's `arm_upper`, `arm_lower`, `hand`, `leg_upper`, `leg_lower`, `ankle`.
  No neck body, and the torso is two pieces. `RagdollShapes` reads them
  (`PhysicsShapeCapsule`: `radius`, `point0`, `point1`; `PhysicsShapeSphere`:
  `radius`, `center`; both in the bone's space, in units, with
  `parent_bone`), leaving out a sphere of radius 0, which the compiler uses
  to keep a body with no shape.
- **Joints.** Source 2 Viewer's current code writes them into the `.vmdl`
  as a `PhysicsJointList`: `PhysicsJointConical` (`swing_limit`,
  `min_twist_angle`, `max_twist_angle`, `swing_offset_angle`) and
  `PhysicsJointRevolute` (`min_angle`, `max_angle`), each with
  `parent_body`, `child_body`, `anchor_origin`, `anchor_angles`,
  `collision_enabled` and a `friction`. Friction compiles to a motor on the
  joint: its force is `friction × 360 × the child body's mass` (in newtons
  per kilogram). Body markup (`PhysicsBodyMarkup`) carries `mass_override`,
  `linear_damping`, `angular_damping` and the like. Whether a released
  Source2Viewer-CLI build has this, and what CS2's agents hold, is for the
  next extraction to show (see "Left for Sid" below). Nothing here reads
  the joints yet.

## What the ragdoll does now

- **Shapes.** CS2's fifteen where the model description has them; the
  hitbox capsules where it does not (with the neck folded into the chest,
  as CS2 has no neck body). Mass is shared by volume, as CS2's uniform
  playerflesh would; friction is playerflesh's 0.8.
- **Limits from standing.** Every joint's limits are measured from the body
  standing with its arms and legs hanging straight down (the skeleton's rest
  pose for the rest), not from how it died: the joints are made with the
  bodies laid out at rest, then the bodies are put back where they died.
  Godot fixes a joint's frames from its node's and its two bodies' global
  transforms whenever its nodes are set or it enters the tree
  (`Joint3D::_update_joint` → `_configure_joint`), which is what makes this
  work. A hip that died mid-stride can go no further back than a hip can.
- **Different limits each way.** Every joint but the knees and elbows is a
  `Generic6DOFJoint3D`. On Jolt it is a `SixDOFConstraint` with pyramid
  swing limits, and each angular axis takes its own lower and upper limit,
  so a hip can go 120° forward and 20° back. Godot's angle is the negative
  of the child's turn about the joint's axis (the Jolt module swaps and
  negates the limits; the experiment confirmed it: a limit of [0, 0.6] let
  the child turn to -0.6), so a turn allowed from lo to hi is a limit from
  -hi to -lo.
- **Hinges** for the knees (0 to 125°, backward) and elbows (0 to 120°,
  forward), their bend axis from the rest pose, and from the body's facing
  where the rest pose is straight or bent the wrong way (a knee locked back).
- **Friction in the solver.** Each joint has a motor driving its turn to
  zero with at most `JOINT_TORQUE` × the child's mass, as CS2 compiles its
  joint friction. Before, the friction was written into the bodies'
  angular velocities from `_physics_process`, outside the solver. With the
  new limits a body on the 20° ramp gathered speed from that and cartwheeled
  down it; the motor only ever takes speed away. The ragdoll checks pass
  from 1000 to 4000; at 6000 the stiff body rolls down the ramp like a log.
  2000 is a guess until CS2's `friction` values are read.
- **Clear of the floor.** dust2's hull is one-sided
  (`ConcavePolygonShape3D`, `backface_collision` false): the solver pushes a
  part back only while its centre is over a face. So:
  - At build, each part looks down from 24 units over its centre for the
    top of what it is in, and up for an underside it is only under (a
    ledge, a table); the whole body is lifted straight up by the deepest
    overlap, plus 0.25. A contact query would not do: a foot wholly inside
    a kerb touches no face.
  - Each tick, while a body is awake, the same look over its centre, no
    further than its radius; a part whose centre the step left under the
    floor goes back on top and loses its downward speed.

## What the checks found

`tests/run_ragdoll_checks.gd` drops a stand-in body (rest pose arms at 45°,
killed with a rifle up and mid-stride, feet 1.5 units into the floor as the
real ankle hitboxes start) on one-sided triangle floors built as
`MapImporter._build_collision` builds dust2's: flat, a 20° ramp, and a road
with a kerb 6 units high and no face under it. Standing, running downhill at
250 u/s and shot in the legs, with CS2's shapes and with the hitbox
capsules. On main at `4ae290c`, 13 of its 56 checks fail:

- **The kerb.** A foot that starts inside the kerb (as a foot drawn stepping
  onto a kerb does) is never pushed out; it falls through the bottom, and
  the shin and foot end 16 units under the road. This matches the
  screenshot (a T by T spawn's red and white kerb, a thigh down into the
  road), so it is the likeliest cause of what Sid saw. A plain floor or
  ramp never showed it.
- **A slow creep.** With the new limits, a foot held at the end of its
  ankle's bend and pressed into the ramp by the leg pushed the shin through
  at about 1 unit a second. More solver steps (`position_steps` 4 or 6,
  `velocity_steps` 20) moved the failures around rather than curing them,
  so the project's Jolt settings are left alone; the per-tick check cures it.
- **Joints.** Hips 60 to 80° back and shoulders well past their range, in
  most cases.

With this change all 56 pass, and the range's 79.

**Not done: the body's parts colliding with each other.** With the mask
widened to the ragdoll layer, the headless run was killed by the machine
(out of memory or hung) before it reported, so it is left out. Joined pairs
would be excluded (`exclude_nodes_from_collision`), but the rifle pose's
hands start inside the chest, and a mask on the layer also makes separate
corpses collide, which nobody has checked CS2 does. Watching CS2 (below)
decides whether to try again.

## Cost

Measured headless in the cloud container (not Sid's machine;
`reference/performance.md` has 0.56 ms for a build there):

| | main | this change |
|---|---|---|
| Building a ragdoll | 1.2 to 2.6 ms | 2.5 to 3.3 ms |
| The per-tick floor check, 15 bodies awake | none | 0.04 to 0.05 ms |

The build is about 1 ms dearer here (the joints are made with the bodies
moved twice, and up to 60 rays find the floor). The per-tick check stops
once a body sleeps. Both are in what is only seen: CS2 ragdolls its dead on
each client, and the server's hitboxes do not follow the ragdoll.

## Players' critiques of CS2's ragdolls

- January 2025 (the 8 January 2025 patch, "Fixed a regression in
  grenade interactions with ragdolls"): corpses flung into the air on death,
  which players found distracting and sometimes blocking their view
  ([esports.gg](https://esports.gg/news/counter-strike-2/first-2025-cs2-update-includes-nasty-ragdoll-bug-sending-players-flying-literally/),
  [EarlyGame](https://earlygame.com/news/counter-strike-2/latest-cs2-update-makes-ragdolls-fly-around-the-map/)).
  Secondary (news reports). The lift here moves the body without giving it
  any speed, and the per-tick check only takes downward speed away, so
  neither can fling a body.

No other CS2-era critique of ragdolls sinking or bending was found in one
search; a longer look is for whoever takes the Local checks.

## Left for Sid

- **CS2's joints.** Read them once a Source2Viewer-CLI build writes
  `PhysicsJointList` (see above). Until the VCS 72 shader problem is fixed,
  any re-export must be one that exports no materials: the agents'
  `.vmdl` text only, never the `characters` step, which overwrites the
  working materials. Then a script turns the joints into a generated table
  under `reference/`, and `Ragdoll` reads CS2's limits, frames and friction
  in place of the table in `ragdoll.gd`.
- **By eye in CS2:** whether its ragdolls collide with themselves and with
  each other, and how stiff they settle.
- **On dust2:** deaths on the T spawn ramp and street (by the kerb), long
  and the stairs; standing, running downhill and shot in the legs; your own
  death too. `scripts/run_tests.sh ragdoll` with the extracted agents runs
  the one check that needs them (the real agent's ragdoll on the ramp).
