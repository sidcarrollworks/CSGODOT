# What everything costs, and what going online will

An audit of every system's cost, measured on dust2 with ten and twenty
players (you and bots) on 2026-09-23: Godot 4.7.2 headless, Jolt, 64 ticks a
second, an AMD Ryzen 7 7800X3D. A slower CPU pays more for all of it; the
proportions hold. `scripts/profile_dust2.gd` measures it all again (the last
section says how).

## The budget

A tick at 64 Hz is 15.6 ms, and everything the game does runs on one thread:
the script, the physics queries it makes, and the frames. What is left of a
second after 64 ticks is what the frames get, so roughly

    frames a second = (1000 - 64 x tick ms) / frame ms

When the ticks take more than the second, each frame runs more ticks to
catch up (up to `max_physics_steps_per_frame`, 16), which makes the frame
longer still, and the game crawls. That was the lag with five a side
(PR #43): at the 128 ticks a second the game ran then, ten players took
about 8.5 ms of every 7.8 ms tick.

## Where it goes

Headless, so a frame is its script alone: drawing comes on top
(`reference/rendering.md` and `scripts/profile_render.gd` measure that).

| A tick | 10 players | 20 players | Each player |
|---|---|---|---|
| Bots' `run_command` (movement, mostly) | 2.4 to 3.0 ms | 6.6 to 7.4 ms | 0.3 to 0.37 ms |
| Bots thinking (sight, paths) | 0.31 to 0.37 ms | 0.75 to 0.81 ms | grows as bots x enemies |
| Your `run_command` | 0.10 ms | 0.10 ms | |
| Footsteps | 0.04 ms | 0.08 ms | |
| **The tick** | **2.9 to 3.5 ms** | **7.6 to 8.4 ms** | |

The profiler ran the nodes in the tree's order backwards then, without
their priorities, so the match went first and you last, right after the
bots. Run in the engine's own order (since the evening of 2026-09-23), you
are the first thing in the tick, with the map's collision not yet in the
cache: your command and its run are 0.11 to 0.13 ms, and footsteps 0.02 with
ten players. The tick is the same either way: ten players 2.6 to 3.1 ms,
twenty 6.7 to 7.8, timed that evening by a node first and a node last in
every tick, with nothing taken over.

The physics server's own step was about 0.2 ms a tick with ten players and
0.3 with twenty (measured at 128; at 64 a tick seldom shares a frame with
another, which is how it is seen).

| A frame | 10 players | 20 players | Each body |
|---|---|---|---|
| Animation trees (12 and 22) | 0.98 to 1.04 ms | 1.95 to 2.0 ms | about 85 us |
| Skeletons posed, hitboxes and pins moved to them | 0.38 ms | 0.69 to 0.72 ms | about 32 us |
| Bots drawn between ticks and lit | 0.22 ms | 0.40 to 0.45 ms | about 23 us |
| The HUD, your view | 0.08 ms | 0.08 ms | |
| **The frame's script** | **1.7 ms** | **3.2 ms** | |

Headless that is 145 frames a second with ten players and 117 to 128 with
twenty, all 64 ticks a second in both.

Drawn, and so not in these tables: the two lamps down dust2's lower
tunnels (`MapLighting.add_lamps`, 2026-09-24) are Godot spot lights with
shadows, the map's only lights besides the sun. Godot renders a positional
light's shadow again only when something inside its range moves (its
lights and shadows documentation), so they cost a shadow pass a frame while
a player or a bot is in the tunnel and none otherwise. Not measured on the
GPU yet.

The HUD on the GPU (2026-09-25, dust2 at outside long with ten players,
the render time Godot measures, alternated in blocks): 2D blended in linear
light as CS2's HUD is (`hdr_2d`) costs 0.005 ms at 1080p and 0.02 ms at 4K;
the blurred world behind its panels (a copy of the screen under each panel
and Godot's blurred mipmaps of it) 0.08 ms at 1080p and 0.11 ms at 4K with
three panels blurred (warmup: the ring, the alert, your card), about a
third of that in a live round, where only the ring blurs. Blurring from
Godot's automatic copy of the whole screen cost 0.51 ms at 4K, which is
why each panel copies its own part. `scripts/profile_render.gd` measures
both again (the `sdr_2d` and `no_hud_blur` variants).

The buy menu's agent (2026-09-25, dust2 at T spawn, the menu open over the
AK-47, `viewport_get_measured_render_time_gpu` over 120 frames): its
picture, 900 by 1080 at 1080p and 1775 by 2130 at 4K, takes 0.15 ms of the
GPU at 1080p (4x MSAA) and 0.31 ms at 4K (2x; 0.35 with 4x), and nothing
while the menu is shut. Its video memory is held from the first opening:
+96 MB at 1080p, +217 MB at 4K (335 with 4x, 114 with no MSAA), which is
why a picture taller than 1440 lines gets 2x (`MSAA_4X_UP_TO`). Building
it reads every pose of both sides and both sides' agents, 294 ms at the
map's load with nothing read before it (less in a match, whose players have
read the agents), so the half-time swap's build takes 2 ms; the first time
the mouse is over a gun whose model nobody has held yet, reading the model
takes 20 to 45 ms, which reading every holdable model before play would
take away.

What is drawn is cut down by the map's own visibility (`WorldVisibility`,
2026-09-24), as CS2 cuts it: from T spawn 2,702 of dust2's 3,589 world
meshes are not drawn (they still cast their shadows), and from mid 2,178.
The GPU's saving is not measured yet. On the CPU it is a frame's lookup of
the camera's cluster, 4 us, and when the camera moves into another cluster,
the meshes marked again: 0.4 to 2.9 ms at five of Sid's spots, more the more
there is to see. Which clusters each mesh touches is worked out once, at
load, on a worker thread (about 0.1 s there; 0.7 s when it ran on the main
thread), and is known before the rest of the map has loaded: the load takes
6.6 s with it and without it. Reading the file is 3 ms. None of it is on the
tick, and nothing without a camera runs it.

| Now and then | Cost |
|---|---|
| A round's holes, sounds and the shooter's body | 0.04 ms |
| A round traced | 10 us, 60 us through two walls |
| A death's ragdoll built | 0.56 ms |
| A path over the nav mesh | 0.45 to 0.57 ms, two a tick at most |
| A side swap, one player's new body | 2.6 ms |
| A spawn | 2 us |
| A gun drawn: its weapon and view model built again | 0.64 ms |
| A bot's body taking a class in hand the first time: its clips added (on the tick), its model built (the next frame) | 0.30 ms and 0.23 ms |
| A bot's body switching between things it carries | 0.03 ms |
| The tracers and muzzle flashes, a frame while any are drawn (`ShotEffects`, dust2's bots fighting: up to 81 cards) | 0.38 ms mean, 0.26 median, 1.1 at the 95th, 2.3 most; nothing in the tick |

A body that holds whatever is in its hand (every player's since 2026-09-24,
yours unseen too, as CS2's server poses everyone's hitboxes with what they
hold; a map's bot's since 2026-09-23) carries
the pistol's and the knife's locomotion beside the rifle's, and moves by
one at a time: its motion's parameters take 7.6 us a tick against 5.6, and
its animation 93 us a frame against 87 (one body, headless, AK and Glock).

| Once | Cost |
|---|---|
| dust2 loaded to the first frame | 4.8 s (5.1 with twenty players), before its bots' guns were read |
| The first body of each kind (its ~80 scenes read) | 240 ms; every one after, 2.7 ms |
| The first body that holds what is in hand (the pistol's and knife's locomotion read too) | 210 ms more; every one after, 4.6 ms |
| What dust2's bots may hold, read before play (`prepare_holding`: 17 classes' clips and models) | 1.0 s with the disk's cache warm, 2.8 s cold |
| Then everything else on either side's menu, the knife and the bomb, whose clips every body takes up, yours too (clips only) | 0.4 s more |
| Every gun's sounds (`WeaponSounds`: 334 files, from `sounds.md` and `timings.csv`) | 0.39 s warm, 2.3 s cold |
| Bullet-hole textures, and every sound set | 270 ms, and 120 to 570 ms (the disk's cache warm or cold) |
| The tracers' and flashes' textures (`ShotEffects.prepare`; the flames' sheets are 4096 by 2048, and the first flash of a fight reading one held its frame up 12 ms) | 25 to 30 ms |

A trace of the player's hull through dust2's collision is 20 to 50 us,
depending on how many triangles are under it, and it is most of what a
player costs: a tick standing still is one trace, running in the open four,
more against a wall or up a slope. A ray is 2 to 15 us.

Memory: 1.94 GB static in a headless run, 146 MB of it the light probe
atlas, of which the probe volumes use 48.6%. 28,000 objects and 4,600
nodes, and no orphan nodes after fifteen seconds of fighting.

## Frame pacing

Sid's machine (RTX 4070 Ti, a 240 Hz screen), dust2 with ten players at
3840x2160 fullscreen, V-Sync on (Godot's default), 2026-09-24: how evenly
frames come, and how evenly what they draw moves.

- A frame that runs a tick takes 7.4 to 7.9 ms, one that does not 3.1 to
  3.2 (medians): the tick is about 4.5 ms of the main thread with the bots,
  and at 210 to 230 frames a second one frame in three or four runs one.
  Without the bots the frames that tick take 4.6 ms and the rest lock to
  the screen's 240 Hz.
- Godot takes its tick fraction at a frame's start, before the frame's
  tick runs, and the mouse's movement is read then too. So a frame that ran
  a tick drew the world and the view 4.5 ms behind the rest, and motion
  stepped unevenly (judder), worst when turning fast. It is drawn now as
  far between the ticks as the clock says when it is drawn (`DrawClock`,
  with `physics_jitter_fix` 0 so the ticks keep to the clock), and the view
  takes in the mouse's movement just before it places the camera.

Against when each frame finished drawing (`RenderingServer.frame_post_draw`),
from a straight line fitted to where the camera was drawn over five
seconds: flying straight at 250 units a second (noclip), and turning at 600
degrees a second with the mouse moved through Windows' own input path
(`mouse_event`, from a compiled helper, 13,636 counts a second at
sensitivity 2). "Uneven" is the spread of each frame's step against its
time.

| | Before | After |
|---|---|---|
| Flying: off a steady line | 2.5 to 4.2 ms rms, 35% uneven | 0.6 ms, 20% |
| Turning: off a steady turn | 1.7 ms rms (1.0 degree), 65% | 0.7 ms (0.4 degree), 22% |

The same with the turn fed in by script at each frame's start: 1.9 ms
before, 0.5 after. Exclusive fullscreen with the frame rate capped just
under the refresh took the flight from 0.46 to 0.41 ms. That cap is the
docs' advice for a variable refresh screen with V-Sync on (G-Sync or
FreeSync): `r - r * r / 3600`, 224 at 240 Hz, keeps frames inside the
screen's range (`application/run/max_fps`). Sid plays CS2 with G-Sync,
V-Sync and NVIDIA Reflex, and Reflex sets about that cap there, besides
keeping the queue of frames short (Godot's nearest is
`rendering/rendering_device/vsync/frame_queue_size`, 2 by default; not
measured here). On a fixed
refresh screen the same cap shows some frames twice, and the game cannot
tell which screen it has, so it is a setting for the menus (item 26), not
a default. Tearing a frame timer cannot see: the game asks for V-Sync, and
run from the editor it plays embedded in the editor's Game view (Godot
4.7's default), which cannot go fullscreen, where G-Sync engages by
default.

What is left is the tick's own 4.5 ms in the frame that runs it, which only
a cheaper tick removes (the bots' movement is most of it, "Where it goes").

## What has been done about it

| Change | Where | Effect |
|---|---|---|
| Footsteps asked the disk whether the sounds were there, every tick | PR #43 | 1.9 ms of the tick gone |
| Source's WalkMove: a move that meets nothing is taken, under 1 u/s stops | PR #43 | 9 to 11 traces a tick down to 2 to 5 |
| A bot's probe light per frame, not per tick | PR #43 | |
| Jolt | PR #44 | 4.3 ms a tick to 3.5; rays half the time |
| Bodies built from what was read before | PR #45 | 240 ms a body to 2.7; half time froze for 1.6 s |
| The probe light's lookup | PR #45 | 27 us to 11, the same cube to the bit |
| Sound sets loaded with the map | PR #45 | the first step on a surface hitched up to 47 ms |
| Two path searches a tick | PR #45 | a round's start took 5 to 10 ms in one tick |
| The ground looked for once a tick (Source's sv_optimizedmovement) | PR #45 | a trace a tick fewer; twenty players' tick at 128, 6.4 to 7.3 ms down to 5.6 to 6.2 |
| 64 ticks a second, and everything drawn between ticks | PR #46 | a second of simulation 0.36 s to 0.21 with ten players, 0.76 to 0.52 with twenty; twenty players headless from 57 to 81 frames a second to 117 to 128 |
| One world runs the tick (`GameWorld`), the two path searches a tick its to give out | PR #50 | nothing, as it should: every tick's callbacks in the engine's order, main against it, 3.04, 2.97 and 2.63 ms against 3.00, 2.93 and 2.59 with ten players, window for window; with twenty, 6.75, 7.60 and 7.42 against 6.70, 7.82 and 7.65 |
| A weapon's recoil solved once for each pattern, and the pattern read once | fix/equip-hitch | every weapon built (a gun drawn, any respawn) solved its pushes again: 15 ms, a frozen frame each time a gun was drawn, and 15 ms a player respawned at a fresh round's start; now 0.01 ms, and a draw 18 ms to 0.64 |
| A gun's recoil numbers carried by its copies (`WeaponData`'s solved fields stored, solved as the registry builds each gun) | the Godot docs audit | every new gun (a buy, a pickup, a round's pistols) solved its weapon model's hold time again on the first tick it was held: 20 to 22 ms, more than a tick; now 1 us, and `ItemRegistry.load_all` 17 ms to 69 |
| Frames drawn where the clock is: `physics_jitter_fix` 0, `DrawClock`, and the mouse read just before the view is placed | frame pacing | a frame that ran a tick was drawn 4.5 ms behind; flying 2.5 to 4.2 ms off a steady line to 0.6, turning 1.7 to 0.7 ("Frame pacing") |

A tick at 64 costs a little more than one at 128 did: it moves everyone
twice as far, with more to meet on the way, and holds twice the rounds and
steps. There are half as many, so a second of play costs 42% less with ten
players and 32% less with twenty, not half.

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

**The server** runs every player's command each tick, about 0.35 ms each,
and it has to pose every body's hitboxes each tick too. Today a body's
animation steps with the frames drawn (its AnimationTree is on the idle
process), and the hitboxes follow the body as it is drawn, between ticks. A
server draws no frames, and needs the hitboxes where each tick puts them,
every tick, to keep a history to rewind. That is another 0.1 ms a body a
tick (an animation step and the posing). A player is then about half a
millisecond of every 15.6 ms tick, so twenty are about 9 ms, 60% of a core,
and one core would hold about thirty flat out; for more, a player's traces
are the thing to cut. A server also draws nothing, so it wants no meshes,
materials, lightmaps, probe atlas, decals, sounds or HUD, where today the
map and every body build all of them: a body's skeleton, clips and hitboxes
are all it needs.

**A client** runs its own player a tick at a time (0.1 to 0.4 ms), and on
every word from the server runs again the commands the server has not
answered yet: at 64 Hz and 60 ms of ping that is four ticks, 0.5 to 1.5 ms,
many times a second. A command run again must not sound its shots or leave
its holes again, and today run_command signals both. Everyone else costs
the client their animation, posing, drawing between ticks and light each
frame, about 0.14 ms a player: 2.7 ms a frame for nineteen, before drawing
them. Their hitboxes matter to a client only for effects, since the server
decides the hits. Your own player carries three bodies, the simulation's
with the hitboxes, the one you see and its shadow, and three animation
trees (0.25 ms a frame).

**Lag compensation** wants each player's 19 capsules recorded every tick:
their end points are about 450 bytes, 29 KB a player for a second at 64 Hz.
A rewound round is best tested against those in script, ray against
capsule, rather than by moving the physics world's hitbox areas back and
forth, which Jolt would have to re-index every time.

**The tick rate** is 64, as CS2's servers run, with input taken between
ticks (a press carries its fraction of the tick). Sid chose it on
2026-09-23 over 128 for what a server costs and the room it leaves for more
players. What it gives up: other players are drawn a couple of snapshots
behind, about 31 ms at 64 against 16 at 128, which is the peeker's
advantage CS2 is faulted for, and a round's rewind has half as many ticks to
place bodies between. The netcode is where to win some of that back, with as
short a buffer as the connection allows. The movement comes out as Source's
at 64 (`reference/movement_constants.md` has what the tick rate changes,
air strafing most), and run_tests.gd holds it at any tick rate.

## Next, in order

1. A server that builds nothing to be seen: the map's collision, entities
   and nav mesh; bodies as skeletons, clips and hitboxes; no audio, decals,
   HUD or probe atlas.
2. Animation stepped by the tick where it places hitboxes (the server; bots
   on your own machine), and by the frame where it is only seen. The tree
   can be stepped from run_command in manual mode.
3. The lag-compensation history as capsule end points a tick, and rewound
   rounds tested against it in script.
4. run_command safe to run again for prediction: no sounds, marks or events
   the second time.
5. On a client: no hitboxes posed for other players; bodies far off stepped
   less often; your drawn body and its shadow on one tree (the shadow
   copying the pose, the folded head aside).
6. The probe light sampled on the GPU (the atlas as a 3D texture), which
   takes the script out of it; meanwhile the atlas packed to its volumes,
   146 MB to 71.
7. Bots' sight, which grows as bots times enemies: look every few ticks, or
   share what one sees of another with the other.
8. One body of each kind built while the map loads, so the first bot to
   spawn does not pay the 240 ms.
9. What the bots may hold read on a thread while the map loads, or only
   each side's likely guns, rather than the 2.8 s of every template's; and
   on a server, only their clips (their models are only seen).

## Measuring it again

    godot --headless --path . --script scripts/profile_dust2.gd -- 5 3

Team size 5 is ten players, and 3 is the number of five-second windows.
Three things to know when reading it:

- It runs every node's callbacks itself, so the figures are by system: the
  world's tick (`GameWorld`) in the world's own parts, each player's
  command and its run, then the match, and everything else node by node,
  all in the order the engine would run them (by priority, then the tree's).
  The step from the last node's callback to the next tick in the same frame
  is the physics server's; with more frames than ticks few ticks share a
  frame and that line can be missing.
- Godot's own `Performance.TIME_PHYSICS_PROCESS` and `TIME_PROCESS` are the
  worst tick and frame of the last second, not averages.
- The single operations put the bot back where it was after every call,
  which moves it, so its ground check is never the last one's: take a
  standing tick's cost from the windows, not from there.
