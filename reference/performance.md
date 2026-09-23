# What everything costs, and what going online will

An audit of every system's cost, measured on dust2 with ten and twenty
players (you and bots) on 2026-09-23: Godot 4.7.2 headless, Jolt, an AMD
Ryzen 7 7800X3D. A slower CPU pays more for all of it; the proportions hold.
`scripts/profile_dust2.gd` measures it all again (the last section says how).

## The budget

A tick at 128 Hz is 7.8 ms, and everything the game does runs on one thread:
the script, the physics queries it makes, and the frames. What is left of a
second after 128 ticks is what the frames get, so roughly

    frames a second = (1000 - 128 x tick ms) / frame ms

When the ticks take more than the second, each frame runs more ticks to
catch up (up to `max_physics_steps_per_frame`, 16), which makes the frame
longer still, and the game crawls. That was the lag with five a side
(PR #43): ten players took about 8.5 ms of every 7.8 ms tick.

## Where it goes

Headless, so a frame is its script alone: drawing comes on top.

| A tick | 10 players | 20 players | Each player |
|---|---|---|---|
| Bots' `run_command` (movement, mostly) | 2.2 to 2.6 ms | 4.3 to 5.0 ms | about 0.25 ms |
| Bots thinking (sight, paths) | 0.23 to 0.34 ms | 0.74 to 0.78 ms | grows as bots x enemies |
| Your `run_command` | 0.11 ms | 0.11 ms | |
| Footsteps | 0.03 ms | 0.06 ms | |
| The physics server's step | about 0.2 ms | about 0.3 ms | |
| **The tick** | **2.6 to 3.0 ms** | **5.6 to 6.2 ms** | |

| A frame | 10 players | 20 players | Each body |
|---|---|---|---|
| Animation trees (12 and 22) | 0.95 ms | 1.8 to 1.9 ms | about 80 us |
| Skeletons posed, hitboxes and pins moved to them | 0.34 ms | 0.60 ms | about 28 us |
| Bots' probe light | 0.24 ms | 0.47 to 0.53 ms | about 27 us |
| The HUD, your view | 0.08 ms | 0.08 ms | |
| **The frame's script** | **1.6 ms** | **3.0 ms** | |

Headless that is 145 frames a second with ten players and 57 to 81 with
twenty, all 128 ticks a second in both.

| Now and then | Cost |
|---|---|
| A round's holes, sounds and the shooter's body | 0.03 to 0.04 ms |
| A round traced | 10 us, 60 us through two walls |
| A death's ragdoll built | 0.56 ms |
| A path over the nav mesh | 0.45 to 0.57 ms, two a tick at most |
| A side swap, one player's new body | 2.6 ms |
| A spawn | 2 us |

| Once | Cost |
|---|---|
| dust2 loaded to the first frame | 4.1 s (4.6 with twenty players) |
| The first body of each kind (its ~80 scenes read) | 240 ms; every one after, 2.7 ms |
| Bullet-hole textures, and every sound set | 270 ms, and 120 to 570 ms (the disk's cache warm or cold) |

A trace of the player's hull through dust2's collision is 20 to 50 us,
depending on how many triangles are under it, and it is most of what a
player costs: a tick standing still is one trace, running in the open four,
more against a wall or up a slope. A ray is 2 to 15 us.

Memory: 1.94 GB static in a headless run, 146 MB of it the light probe
atlas, of which the probe volumes use 48.6%. 28,000 objects and 4,600
nodes, and no orphan nodes after fifteen seconds of fighting.

## What has been done about it

| Change | Where | Effect |
|---|---|---|
| Footsteps asked the disk whether the sounds were there, every tick | PR #43 | 1.9 ms of the tick gone |
| Source's WalkMove: a move that meets nothing is taken, under 1 u/s stops | PR #43 | 9 to 11 traces a tick down to 2 to 5 |
| A bot's probe light per frame, not per tick | PR #43 | |
| Jolt | feature/jolt-physics | 4.3 ms a tick to 3.5; rays half the time |
| Bodies built from what was read before | this branch | 240 ms a body to 2.7; half time froze for 1.6 s |
| The probe light's lookup | this branch | 27 us to 11, the same cube to the bit |
| Sound sets loaded with the map | this branch | the first step on a surface hitched up to 47 ms |
| Two path searches a tick | this branch | a round's start took 5 to 10 ms in one tick |
| The ground looked for once a tick (Source's sv_optimizedmovement) | this branch | a trace a tick fewer; twenty players' tick 6.4 to 7.3 ms down to 5.6 to 6.2 |

Looked at and left:

- **Animation tracks that only hold a bone at its rest.** 9% of the tracks,
  3 to 7% of an animation step. The clips carry no scale tracks at all.
- **The collision hull cut into cells.** dust2's 38 hull parts each span the
  map, so every trace visits all of them; cutting them into 1024-unit cells
  made traces 1.5 times faster on Godot Physics but only 1.2 on Jolt. Parts
  of one material in one body then get Godot's numbered names, which
  footsteps and penetration read, and parts in separate bodies lose Jolt's
  removal of internal edges, which only works within a body.

## Going online

CS2's way, which the simulation was written for: the server runs everyone
at a fixed tick and decides every hit; each client runs its own player ahead
of the server (prediction) and shows everyone else a little behind; and the
server judges a round against the hitboxes as the shooter saw them (lag
compensation).

**The server** runs every player's command each tick, about 0.25 ms each,
and it has to pose every body's hitboxes each tick too. Today a body's
animation steps with the frames drawn (its AnimationTree is on the idle
process), and the hitboxes are moved when the skeleton is posed, so their
place at a tick is wherever the last frame left them. A server draws no
frames, and needs the hitboxes where the tick puts them, every tick, to keep
a history to rewind. That is another 0.1 ms a body a tick (an animation
step and the posing). Twenty players at 128 Hz is then about 7 ms of every
7.8 ms tick on one thread, most of a core; at 64 Hz half that. A server
also draws nothing, so it wants no meshes, materials, lightmaps, probe
atlas, decals, sounds or HUD, where today the map and every body build all
of them: a body's skeleton, clips and hitboxes are all it needs.

**A client** runs its own player a tick at a time (0.1 to 0.3 ms), and on
every word from the server runs again the commands the server has not
answered yet: at 128 Hz and 60 ms of ping that is eight ticks, 1 to 2.5 ms,
many times a second. A command run again must not sound its shots or leave
its holes again, and today run_command signals both. Everyone else costs
the client their animation, posing and light each frame, about 0.13 ms a
player: 2.5 ms a frame for nineteen, before drawing them. Their hitboxes
matter to a client only for effects, since the server decides the hits. Your
own player carries three bodies, the simulation's with the hitboxes, the
one you see and its shadow, and three animation trees (0.25 ms a frame).

**Lag compensation** wants each player's 19 capsules recorded every tick:
their end points are about 450 bytes, 58 KB a player for a second at
128 Hz. A rewound round is best tested against those in script, ray against
capsule, rather than by moving the physics world's hitbox areas back and
forth, which Jolt would have to re-index every time.

**The tick rate** is the biggest lever of all. CS2's servers run 64 ticks a
second and take input between ticks, as this project already does (a press
carries its fraction of the tick). Everything above that happens a tick is
paid 128 times a second here: the server's share, the client's re-runs,
the history. The movement is written to come out the same at any tick rate
(the half-steps of gravity, `tick_rate_independent_jump`), and run_tests.gd
measures jumps both ways.

## Next, in order

1. Decide the tick rate: 64 as CS2, or 128 and budget for it. It halves
   everything a tick costs.
2. A server that builds nothing to be seen: the map's collision, entities
   and nav mesh; bodies as skeletons, clips and hitboxes; no audio, decals,
   HUD or probe atlas.
3. Animation stepped by the tick where it places hitboxes (the server; bots
   on your own machine), and by the frame where it is only seen. The tree
   can be stepped from run_command in manual mode.
4. The lag-compensation history as capsule end points a tick, and rewound
   rounds tested against it in script.
5. run_command safe to run again for prediction: no sounds, marks or events
   the second time.
6. On a client: no hitboxes posed for other players; bodies far off stepped
   less often; your drawn body and its shadow on one tree (the shadow
   copying the pose, the folded head aside).
7. The probe light sampled on the GPU (the atlas as a 3D texture), which
   takes the script out of it; meanwhile the atlas packed to its volumes,
   146 MB to 71.
8. Bots' sight, which grows as bots times enemies: look every few ticks, or
   share what one sees of another with the other.
9. One body of each kind built while the map loads, so the first bot to
   spawn does not pay the 240 ms.

## Measuring it again

    godot --headless --path . --script scripts/profile_dust2.gd -- 5 3

Team size 5 is ten players, and 3 is the number of five-second windows.
Three things to know when reading it:

- It runs every node's callbacks itself, so the figures are by system. The
  step from the last node's callback to the next tick in the same frame is
  the physics server's; at 145 frames a second few ticks share a frame and
  that line can be missing.
- Godot's own `Performance.TIME_PHYSICS_PROCESS` and `TIME_PROCESS` are the
  worst tick and frame of the last second, not averages.
- The single operations put the bot back where it was after every call,
  which moves it, so its ground check is never the last one's: take a
  standing tick's cost from the windows, not from there.
