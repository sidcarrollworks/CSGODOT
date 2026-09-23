# CS2's animation graphs (AnimGraph 2)

What CS2's animation system is, how much of it the game's files give us, and
what that means for this project. Worked out on 2026-09-23 from CS2 1.41.8.2,
Source 2 Viewer 20.0 and Esoterica's source; the tables in
`reference/animgraph/` are generated from the game's own graphs by
`scripts/animgraph_tables.gd`.

## What it is

AnimGraph 2 is the animation system CS2 has been moving to. First-person
animations went over to it in 2025, and third-person followed: all of them
re-authored, in the beta of April 2026 and live from 21 April 2026, which
Valve said cut the CPU and network cost of animation. Its files are
`.vnmgraph` (the graphs), `.vnmclip` (the clips) and `.vnmskel` (the
skeletons). The clips and skeletons are what `scripts/extract_assets.sh`
has been extracting all along; the graphs are the logic that plays them.
CS2 ships 232 graphs under `animation/graphs/`, and none of the old
AnimGraph's (`.vanmgrph`).

It is the animation graph of **Esoterica**, Bobby Anguelov's open-source
engine (MIT, <https://github.com/BobbyAnguelov/Esoterica>), under Valve's
names; source2.wiki says as much, and the data shows it. Valve's
`CNmTransitionNode::CDefinition` has exactly the fields of Esoterica's
`TransitionNode::Definition`, in Valve's spelling: `m_nTargetStateNodeIdx`
for `m_targetStateNodeIdx`, and so on through `m_boneMaskBlendInTimePercentage`,
which defaults to 0.33 in both. Of the 57 node types CS2's graphs use,
nearly all are Esoterica's, most under the same name (`Clip` is Esoterica's
`AnimationClip`); the clear exceptions are three of Valve's own, below.
So for what a node does, the answer is in Esoterica's
`Code/Engine/Animation/Graph/Nodes/Animation_RuntimeGraphNode_*.cpp`: that
source is, in effect, the documentation of CS2's animation runtime.

The clip format is Esoterica's too (`m_syncTrack`, `m_rootMotion`,
`m_bIsAdditive`, `m_secondaryAnimations`, which carries the weapon rig's
track in a first-person clip), and so are its events: `CNmIDEvent`
(`WPN_RELOAD_ADD_AMMO`...), `CNmSoundEvent`, `CNmParticleEvent` and the rest,
which `reference/weapons/timings.md` reads.

## Getting at the graphs

`scripts/extract_assets.sh animgraphs` has Source 2 Viewer print every
graph's compiled data (`-b DATA` over `animation/graphs/`: 15 MB of text in
a few seconds) to `assets/characters/animation/graphs/graph_data.txt`, and
runs `scripts/animgraph_tables.gd`, which reads it with `NmGraph`
(`src/player/nm_graph.gd`) and writes:

- `reference/animgraph/graphs.md`: every graph, its variations, node and
  parameter counts, and the graphs it runs.
- `reference/animgraph/parameters.md`: every control parameter, its type,
  and every value the graphs test it for; and the virtual parameters, with
  what they are computed from.
- `reference/animgraph/worldmodel.md`, `locomotion.md` and `viewmodel.md`:
  the third-person graph, its locomotion, and the first-person gun, laid
  out: the chain from the root, the layers, and every state machine with its
  states, what each plays and where it goes, when and how fast.
- `reference/animgraph/locomotion.json`: the locomotion's blend spaces as
  data, for code to build from without the assets.

## How a graph works

The game sets a player's **control parameters** every frame: floats
(`move_speed_x`), IDs, which are names (`action` is `action_reload`),
bools and targets (the feet's IK targets). The graph turns them into a pose.
Everything else is in the graph, and so is in the file.

A compiled graph is a flat list of nodes that refer to each other by index,
each with the path it had in Valve's editor
(`SM/Ground/Standing/Move/run_ne`). The control parameters come first; then
value nodes (comparisons, and, or, not, math, easing, a value held from when
a state was entered or left); then pose nodes, which play and mix clips:

- **State machines.** Each state plays a pose node. Transitions go to other
  states when a condition holds, blending over a set time with an easing
  (`0.2 s, OutQuad`). An entry override starts the machine in another state
  than its default when a condition holds as it is entered; a global
  transition, which Valve's editor draws once, is compiled onto every state.
- **Blends.** A 1D blend mixes its inputs by one value, each fully in at its
  own point; a 2D blend places its inputs on a plane (the locomotion's are
  at the speeds each clip is authored for), cut into triangles, and mixes
  the three corners around the value. Blends keep their inputs in step by
  their sync tracks (a clip's footfalls, say), not by time.
- **Layers.** A layer blend plays layers over a base: each one in model
  space, local space, as an overlay or additively, at a weight (or the weight
  of the state it is in) and through a bone mask (`UpperBody`).
- **Other graphs.** A referenced-graph node runs another graph in its place:
  CS2's third-person graph runs a locomotion graph and a weapon's.
- **Variations.** One graph compiled again with other clips in its slots,
  named `<graph>.vnmgraph+<variation>`: `worldmodel_gun.vnmgraph+ak47`. The
  logic, blends and timings are the same in every variation; only the clips
  differ.
- **IK and aim.** Foot IK on the ankles from the game's targets, two-bone IK
  for the hands, and CS2's aim node.

## CS2's player graphs

**Third person** (`worldmodel.md`, `locomotion.md`). From the root:
Valve's `SnapWeapon` (fed the flashed amount, the weapon's category and
type), a layer blend with the flashed layer, Valve's `AimCS` (the aim's pitch
and yaw, the weapon, the action, the drop and defusing, the crouch; hand IK
blending in over 0.3 s), foot IK on the ankles, then a layer blend over the
base state machine: Locomotion or Planting. Its layers, in order: the
weapon's actions and the defuse in model space, then body additives (the
jump's start and landing), the shooting, and the body, head and fire
flinches, all additive. That is the layering item 6 of the roadmap asks for.

The locomotion is a graph of its own, in three variations the third-person
graph picks by the weapon: knife-style for grenades, knives and the
healthshot, pistol-style for pistols and the bomb, rifle-style for the rest.
The game decides what the legs are doing (`ground_action`: idle, start,
move, plant and turn, turn on the spot) and the graph follows it. Moving is
two 2D blend spaces over the body's forward and leftward speed, standing
and crouched, mixed by the crouch amount: idle at the centre, the eight run
clips at 225 units a second (159 on the diagonals), the eight walk clips at
136 and the crouch clips at 96; the idle at the centre is scaled to last
one second. The states cross-fade in 0.1 to 0.35 s. Starting off
plays a planted start in the direction of travel; reversing plays a plant
and turn; the air has a jump and a landing blended by speed the same way.

The flinches say where a hit came from: `flinch_head_type` is north, south,
east or west; `flinch_body_type` is a part and a side (chest or stomach and
a direction, an arm, a leg); `flinch_is_on_fire` for burning.

**First person** (`viewmodel.md`). `viewmodel.vnmgraph` runs a graph for
what is in hand: the gun graph, in a variation per gun (the CZ75-Auto, Dual
Berettas and R8 Revolver have graphs of their own), the knives', the
grenades' and the inspects'. The gun graph's actions: attack, which
alternates between two states on every shot so each round restarts the
firing clip; idle, blended with the ironsight pose; reload, deploy,
inspect and the silencer. A layer hides the rounds in the XM1014's tube and
the M249's and Negev's belts as they empty (`bullet_hide_*`).

## What the files do not say

- **Valve's own nodes.** `AimCS` (the aim, and the hands' IK by weapon),
  `SnapWeapon`, and `ChainLookat` (only the chicken uses it). The files give
  their inputs and settings, not what they do with them.
- **How the game computes the parameters.** What makes `ground_action` a
  plant and turn, which hit is `flinch_body_chest_north`, how the aim's yaw
  runs ahead of the body. The names, the values the graphs test for, and the
  blend spaces' layout narrow it down; the rest is measuring in CS2.
- **Some transition options.** Esoterica keeps them as bit flags; CS2's
  values do not fit Esoterica's current order, so Valve's has moved on.
- **The clips' non-additive copies** that CS2 1.41.8.2 added
  (`prepare_shoot_revolver.vnmclip+non_additive`): the additive clip lists
  its copy as a dependency, and no graph names one.

## What it means here

The steps, smallest first:

1. **Build the locomotion from the game's numbers.** *(Done: `PlayerModel`,
   which used to pick one clip at a time and scale it from 250, 130 and 85
   units a second.)* A Godot `AnimationTree` with `locomotion.json`'s blend
   spaces (Godot's `AnimationNodeBlendSpace2D` takes the points and the
   triangles as they are), standing and crouched mixed by `duck_progress`,
   the air's spaces with CS2's cross-fades into it (0.1 s) and back (0.2 s),
   fed the body's speed along and across its facing. CS2 syncs the clips by
   their whole cycle; Godot's spaces do not, so each moving clip is stretched
   to one cycle and a time scale over them sets the cycle's length from the
   clips being mixed. Still to come from `locomotion.md`: the starts, the
   plant and turn, turning on the spot, the jump's takeoff (its directional
   clips are not extracted) and ladders.
2. **The layers.** *(Done but for the flinches: `PlayerModel.add_weapon_layers`.)*
   The weapon's actions, the shooting and the flinches over the locomotion,
   as the third-person graph stacks them, with its bone masks and its flinch
   types; item 6, and 6a after it. The gun's hold, reload, draw and shots go
   in through CS2's UpperBody mask (`spine_0` and every bone under it, and
   the gun's), which the skeleton's data lists by root bones, the rest
   inheriting their weight. CS2's additive clips hold bare differences,
   composed in the bone's own space (`base * delta`, and `base + delta`
   for translation, as Esoterica's `AdditiveBlendFunction` has it); Godot
   adds a clip's difference from the bone's rest, composed the same way, so
   each key is re-expressed from the rest as the clip loads
   (`PlayerModel.rest_relative`). An additive clip is told by the
   `+non_additive` copy beside it. The weapon layer is blended in each
   bone's own space where CS2 blends it in model space.
3. **More of the graphs by conversion.** Most node types have a Godot
   counterpart (state machines, 1D and 2D blends, additive and masked layers,
   time scaling); Valve's three nodes and the IK would be ours to write.
4. **Or run the graphs as they are,** on a port of Esoterica's graph runtime.
   The most faithful and the most work.

## Sources

- HLTV, "AnimGraph2 goes live in latest CS2 update", 21 April 2026:
  <https://www.hltv.org/news/44430/animgraph2-goes-live-in-latest-cs2-update>
- Counter-Strike 2 update notes: <https://www.counter-strike.net/news/updates>
- source2.wiki, "What is Source 2": <https://www.source2.wiki/Basics/what-is-source-2>
- Esoterica: <https://github.com/BobbyAnguelov/Esoterica>
