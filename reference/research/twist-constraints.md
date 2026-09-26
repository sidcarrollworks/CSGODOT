# How CS2 poses the twist bones

Research for playtest issue 8 (`reference/playtest-2026-09-25.md`): the
first-person wrists wrung on the knife, the glove cuff sunk into the
forearm. Written 2026-09-26 in a cloud thread, without CS2's files, from
Source 2 Viewer's public source and the playtest page's reading of the
agents' `.vmdl` on Sid's machine.

**How each claim is marked.** *Read* is read from a source named below.
*From the page* is what `reference/playtest-2026-09-25.md` issue 8 read in
the extracted agents (CS2 as installed on Sid's machine, 2026-09-25).
*Measured* is run here, headless. *Inferred* is a reasoned guess. Nothing
here comes from Valve's leaked source.

## The short version

- CS2's clips never key the twist bones. Each agent's model carries an
  `AnimConstraintList` whose 13 `AnimConstraintTiltTwist` blocks pose them
  after the animation, every frame (*From the page*: `tm_phoenix_varianta.vmdl`
  and `ctm_sas.vmdl`, 13 each).
- A tilt-twist constraint turns **one bone about one of its own axes** by
  **its weight times the twist of another bone** in that bone's parent,
  measured about one of its axes. The bend (tilt) of the followed bone is
  left out. A negative weight turns the other way (*Read*, Source 2
  Viewer's `TiltTwist`).
- The forearms: `arm_lower_*_TWIST` takes 0.5 and `_TWIST1` 1.0 of the
  hand's twist, both about X (*From the page*). Without them the skin
  weighted to them (11.8% of the arms' weight each side, against 6.6% on
  each hand) stays with the forearm while the hand turns up to 80 degrees on
  the knife's idle: the wrung cuff.
- Built here as `TwistConstraints` (the reader) and `TwistModifier` (a
  `SkeletonModifier3D` on each drawn rig), on the view model, the
  third-person bodies and the buy menu's agent. 13 constraints cost about
  13 us a frame per body in GDScript (*Measured*, cloud CPU).

## Sources

- **Source 2 Viewer (ValveResourceFormat)**, MIT, reverse-engineered from
  CS2's compiled files, not leaked source. Commit `f3ad9fb` (2026-09-25),
  read 2026-09-26:
  - `Renderer/Renderer/BoneConstraintSolver.cs` (last changed `c2941e9`,
    2026-09-19; the solvers added in `8a322d7`, 2026-09-16), class
    `TiltTwist` and its `TwistAngle`. Its release 19.2 announced "a CS2
    first-person viewmodel ... with a new animation mixer, IK, and
    tilt-twist constraint solver".
  - `ValveResourceFormat/Resource/ResourceTypes/ModelAnimation/BoneConstraints.cs`,
    `TiltTwistConstraint`: reads `m_nTargetAxis` and `m_nSlaveAxis`.
  - `ValveResourceFormat/IO/Extract/ModelExtract.Rig.cs`: how the
    compiled constraint is written back out as the `.vmdl` text our
    extraction reads (the names below).
- **The agents' `.vmdl`**, decompiled by Source2Viewer-CLI in
  `scripts/extract_assets.sh characters` (*From the page*; not in the
  repository, and not read here).

There is no newer or more primary source: Valve publishes nothing on its
constraints, and CS2's own solver is in its closed binaries. Source 2
Viewer's solver is checked against the game by eye, in its viewer, by its
authors; this page takes its maths as the best public account.

## What the file says

Source 2 Viewer writes a compiled `CTiltTwistConstraint` out as
(`ModelExtract.Rig.cs`, *Read*):

| `.vmdl` | compiled | meaning |
|---|---|---|
| `_class = "AnimConstraintTiltTwist"` | `CTiltTwistConstraint` | the constraint |
| child `AnimConstraintSlave`, `parent_bone`, `weight` | `m_slaves[i]`: `m_nBoneHash`, `m_flWeight` | the bone turned, and how much of the twist |
| its `relative_origin`, `relative_angles` | `m_vBasePosition`, `m_qBaseOrientation` | not used by the tilt-twist solver |
| child `AnimConstraintBoneInput`, `parent_bone` | `m_targets[0]`: `m_nBoneHash` | the bone followed |
| its `relative_angles` | `m_targets[0].m_qOffset` | the frame the followed bone's twist is measured from |
| its `relative_origin`, `weight` | `m_vOffset`, `m_flWeight` | not used |
| `input_axis` | `m_nTargetAxis` | 0 X, 1 Y, 2 Z: the axis the twist is measured about |
| `slave_axis` | `m_nSlaveAxis` | the axis the turned bone turns about |

The constraint's own fields come after its `children` in the text. Bone
names are written in lower case (`hand_l`) where the skeleton has `hand_L`,
so names are matched in any case. Angles are Source's QAngle, pitch, yaw
and roll in degrees, turned from the compiled quaternion by
`EntityTransformHelper.ToEulerAngles`; the quaternion is rebuilt as yaw
about Z, then pitch about Y, then roll about X (Source's `AngleQuaternion`,
`EulerAnglesToQuaternion` in the same file). `up_vector`, `up_type` and the
bind rotations belong to other constraint types (aim, twist); the
tilt-twist solver reads none of them.

## The maths

Per constraint, per frame, after the clips (`TiltTwist.Evaluate`, *Read*):

1. The followed bone's rotation in its parent: `local = parent⁻¹ · target`
   in model space, which is Godot's `get_bone_pose_rotation(target)`.
2. Take the offset out: `r = offset⁻¹ · local`, `offset` from
   `relative_angles`.
3. The twist of `r` about `input_axis` (`TwistAngle`): with `b` the basis
   of `r` (`b[i]` where axis i now points) and `a1`, `a2` the next two
   axes,
   - if the axis has tilted, `(a, b) = normalise(b[axis][a1], b[axis][a2])`,
     `m1 = b[a1][axis]`, `m2 = b[a2][axis]`, and the twist is
     `atan2(m2·a − m1·b, −m1·a − m2·b)`. This is the swing-twist split
     with the swing the shortest arc taking the axis back: *Measured*, it
     matches the textbook split (the rotation's quaternion part along the
     axis) over 200 random turns;
   - if it has not, the twist is read off the next axis,
     `atan2(b[a1][a2], b[a1][a1])`. The test for "not tilted" is
     `1 − cos(tilt) ≤ 1e-4`, so an axis tilted under 0.81 degrees counts as
     untilted, and the twist read is then out by up to about 0.25 degrees
     (*Measured*). Kept as written; it cannot be seen.
4. Times the turned bone's weight: a negative weight turns it the other
   way.
5. The turned bone's rotation in its parent is set to that angle about
   `slave_axis`; its position stays. Its children, if any, go with it.

What the answers to the plan's questions come to: the reference frame is
the followed bone's parent, with `relative_angles` taken out; tilt and twist
split as the shortest arc; a negative weight counter-turns; `up_vector`
does not matter; `relative_origin` does not matter.

## Where ours differs, and why

- **The turned bone keeps its rest.** Source 2 Viewer sets the bone's
  rotation in its parent to the twist alone; ours sets it to its rest times
  the twist. The two agree when the twist bone's rest is unturned in its
  parent, which a bone laid along its forearm is (*Inferred*); where it is
  not, ours still leaves the bone at rest when nothing twists. Our rig also
  adds a twist bone under its nearest ancestor that is present, composing
  the rest along the skipped bones (`RigModel._add_bone_from`), and keeping
  that rest keeps the bone where the skin expects it. The asset checks
  print any twist bone whose rest is turned.
- **The twist is unwrapped before the weight.** Source 2 Viewer unwraps
  the weighted angle against the last frame, so a half-weighted bone jumps
  when its target passes half a turn. Ours unwraps the target's twist first,
  then weights it. Nothing in CS2's clips turns a hand that far (the knife's
  draw reaches 120 degrees, *From the page*), so the two agree in play.
- **Only drawn bodies are twisted.** Your own body, on
  `PlayerSim.UNSEEN_LAYER`, and a hidden one are left alone.

## For the simulation

The twist bones carry no hitbox (*From the page*; the asset checks confirm
it per agent) and nothing is pinned to them, so the hitboxes and the tick
never see a difference. *Measured* in Godot 4.7.2, headless: a
`SkeletonModifier3D` runs in the skeleton's deferred update each frame,
what `skeleton_updated` reads (`SkinnedHitboxes`, the pins) is the pose
after the modifiers, and outside that update the pose is the clips' again.
So a modifier that moved a bone with a capsule on it (foot IK, issue 5)
would move that capsule; this one moves none.

## What players say

No critiques of CS2's wrists or twist bones were found (a web search on
2026-09-26 returned only viewmodel setting guides). Nothing to propose
beyond CS2's own behaviour.

## What a Local check would settle

- With the agents and the knife extracted, `scripts/run_tests.sh twist`:
  each agent's 13 constraints read, no capsule on a twist bone, no twist
  measured at the bind pose (this confirms `relative_angles` is what the
  followed bone's rest is measured from), and `arm_lower_R_TWIST1` turning
  as far as `hand_R` twists in the knife's idle.
- The knife's idle, draw and inspect and the AK's, on the T and CT arms,
  beside CS2's.
- The cost per frame in `scripts/profile_dust2.gd` with ten bots.
