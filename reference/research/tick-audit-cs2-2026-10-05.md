# How CS2's server runs a tick, and what ours should take from it: 5 October 2026

Sid asked for a performance audit of the tick, read against how CS2 does
it in Ghidra: "as close to CS2 as can be for the tick and server code ...
I want to learn how exactly and why they do what they do." This page has
three parts:

- what our tick costs now, measured;
- how CS2's server runs a tick, read from its shipped `server.dll`;
- what to change, ranked.

Nothing in the game changes with it. It repairs one profiler
(`scripts/profile_player_tick.gd`) and adds the Ghidra query script it was
read with (`scripts/shooting_audit/TickQuery.java`).

## How it was read

- **The binary.** CS2's `server.dll` build 2000922 (patch 1.41.8.8),
  SHA-256 `3541e46a3193fcf1151e97ce19cd4daf86c5fdb2889033c2bab1d4cc7f555b9c`:
  the file in the analysed project, as `TickQuery.java`'s `info` prints
  it, and the one the shooting, grenade and collision ledgers of
  2 October record. Every address here is that build's. Later ledgers
  matched what they used against build 2000924 (1.41.8.8, `098d4ddd…`)
  byte for byte: movement-ghidra its 97 function spans,
  grenade-subtick-snapshot 28, the sky-clipping follow-up its own. Where
  this page reuses their addresses, those hold for both builds; the rest
  were matched against no later build. CS2 updated to build 2000927
  (1.41.8.9) on 5 October: match an address against the installed file
  before relying on it there.
- **The tool.** Ghidra 12.1.4, run headless and read-only on copies of the
  analysed project. `TickQuery.java` runs batches of queries: strings with
  the functions that use them, decompile, disassemble, callers and callees,
  and vtables found from MSVC's RTTI by hand. The project's analysis had
  not labelled the vtables.
- **The researchers.** Six read the binary, one area each:
  - the server frame and how commands run;
  - the movement pipeline;
  - traces;
  - shots and lag compensation;
  - bots;
  - entities, events and animation.
- **The check.** A second reader re-checked each researcher's claims in the
  binary on the same project copy, trying to refute them. Of 50 claims
  checked, 21 were confirmed, 29 corrected (mostly names, counts and
  conditions) and none refuted. Only the corrected form is written here.
- **Our side.** Four readers mapped our tick from the code at `6890b5f`.
  Four comparisons and one ranking followed.
- **Off limits.** Valve's leaked source code was not used. Every statement
  about CS2 below comes from the binary.
- **Labels.** "Read" means seen in the code or the disassembly. "Inferred"
  is a reading of intent, or a name the binary does not carry.
  "Estimated" is arithmetic.

## Our tick today

Measured on Sid's machine (Ryzen 7 7800X3D), headless, current main with
native movement and Box3D, 5 October 2026:

| Fixture | Mean tick | 95th | Worst | Notes |
|---|---|---|---|---|
| A live round by system (`profile_dust2.gd -- 5 4 round`) | 2.50 ms | 3.10 | 3.72 | bots' run_command 1.68 ms, their thinking on worker threads 0.34, end_tick 0.18, yours 0.14 |
| The seeded match (`profile_box3d_match.gd`) | 2.42 ms | 2.97 | 5.20 | 54.7 traces and 76.6 physics queries a tick |
| The same, terrain-aware eyes off (`profile_ground_eyes.gd --without-terrain`) | 1.83 ms | 2.21 | 4.48 | 27.0 traces; the eyes cost 0.58 ms, 27.7 casts a tick |
| Worst ticks (`profile_worst_ticks.gd`) | 1.87 ms | 2.79 | 15.1 at the start | kill ticks 3.8 to 4.6 ms |

The live-round tick is 2.45 to 2.50 ms, the bots' run_command 1.68 of
it. Most of what the tick grew since 2 October is the two movement ports,
by their own paired measurements on the seeded ten-player fixture:
- the terrain-aware eyes (#187), 0.69 ms
  (`terrain-eyes-2026-10-03.md`), 0.58 in the table above;
- the horizontal movement port (#188), 0.11 ms
  (`horizontal-integration-2026-10-03.md`).

The bots have changed since (#189 to #196). On that fixture the tick is
0.24 ms lower than right after both ports (2.42 against 2.661) while it
traces 18% more (54.7 against 46.35), so the drift between builds is
about the size of the smaller port. The playtest's 1080p run has the tick
in frames at 1.75 ms on 2 October's build and 1.96 on 5 October's
(`reference/playtest-2026-10-05.md`).

One running bot's tick, from `profile_player_tick.gd -- 5 60`:

| Microseconds a bot a tick | Script movement | Native movement |
|---|---|---|
| run_command, all of it | 281 | 232 |
| simulate, all of it | 231 | 182 |
| of it, the movement step (`_simulate_step`, `_update_air`) | 97 | inside simulate's own time |
| of it, simulate's own time outside the step: mostly the terrain eyes, which no profiler splits yet | 133 | 178 with the native step in it |
| a hull cast through the bridge (2.3 a tick) | 20 each | |
| think, and finding its way | 27, of it 19 | 26, of it 18 |

The terrain sampler now costs more than the movement step it rides on.

## How CS2 runs a tick

### 1. One tick, in order

The loop that decides when a tick happens is in `engine2.dll`. It calls
`CSource2Server::GameFrame` (`180dd3dd0`, vtable `18198ecf8` slot 19) with
three byte flags; their names, "simulating", "first tick" and "last tick",
are inferred. One frame can hold several ticks, and the server knows which
one it is running. The command queue reads the tick's index in the frame
(`gpGlobals+0x14`) and how many the frame holds (`+0x18`), and trims its
buffer only on the first one. So once-per-frame work is not repeated when
the engine catches up (read).

`GameFrame` runs one tick in this order (read):

1. **The clock is scoped.** `tickcount = (int)(curtime*64+0.5)`, with a
   literal 64.0 (`MULSS` at `180dd407c`, `CVTTSS2SI` at `180dd40b1`). The
   owning thread's id goes into the globals. Both are restored at the end.
2. **`FrameUpdatePreEntityThink`** goes to every game system. The bots
   think here (section 5), before anyone moves.
3. **The trace query cache** is refreshed on the thread pool
   (`UpdateQueryCache`, `180f929f0`). What it holds was not established.
4. **`CSimThinkManager::Run`** (`1805af880`):
   - every player controller, in slot order, runs all of its commands
     (`SimulateUserCommands`, through `CALL [RAX+0x508]` at `1805af94a`)
     before the next player starts;
   - then every entity whose think tick has come thinks (gathered by
     `18058ad30`, run by `PhysicsRunThink`, `180e89370`).
5. **Entity input and output** is serviced (`CEventQueue::ServiceEvents`,
   `18138bee0`).
6. **`FrameUpdatePostEntityThink`** goes to every game system. Four answer:
   - the physics step (`CPhysicsGameSystem::OnSimulate`, `18059f050`);
   - the round and match rules (`CCSGameRules::Think`, `18095fc30`, from
     `CGameRulesGameSystem`);
   - server animation (`AnimTickUpdate`, `180530420`);
   - lag-compensation recording (`180ec0520`).

   Their order is a listener array (`1805349a0`) that was not decoded. So
   the rules run after every command and every think, but which side of
   the physics step they run is open.
7. **Then:** client data (`UpdateAllClientData`, `180d110b0`), timer
   callbacks due by now (`180fc2790`), queued spawns and deletes
   (`181380a10`), and network messages. A convar,
   `sv_early_network_message_processing` (default 0), adds an earlier
   pass; the end-of-tick one always runs.

Why (inferred): players act on the world as the last tick left it.
Entities react to everything the players did. Last come the batch passes
that only follow from those results (physics, rules, animation, history).
Each runs once over a flat list, which is where threads pay.

Ours has the same shape. `GameWorld.step` (`src/sim/game_world.gd`) runs
these in order:
- every command gathered first, with the bots thinking on worker threads;
- each player's run_command in join order;
- then end_tick.

The one difference in order: our `MatchState.tick` runs before the
entities (`game_world.gd:358-360`, then `game_systems.gd:142-143`). So a
grenade or fire kill that empties a side ends the round a tick late.

### 2. Commands: one intake, a budget, and a clock in ticks

Commands from clients and from bots go into one intake,
`ProcessUsercmds` (`180b616a0`). A bot builds one command a tick and
submits it as a one-command packet (`1802e68e0` calls
`180b616a0(controller, cmd, 1, 0, -1.0)`).

Humans run through `CPlayerCommandQueue::RunTickCommands` (`180ece170`):
- **One command a tick.**
- **Starved, with nothing queued:** a substitute is made from the last
  command. Its number advances for 3 ticks (`cq_max_starved_substitute_commands`
  4; its `CMOVGE` at `180ece017` is in `180ecdeb0`, the helper
  `RunTickCommands` calls at `180ece2aa`), then repeats.
- **Excess commands:** trimmed only on the first tick of a frame, after a
  catch-up phase or a lasting excess. Trimmed commands are held, and up to
  `sv_late_commands_allowed` (5) of them run before the on-time one with
  frame time 0.
- **The clock:** the tickbase is set so an on-time command runs at exactly
  the server tick, `curtime = tick/64`.

Bots, as fake clients, use the older loop in
`CBasePlayerController::OnSimulateUserCommands` (`180b5f9c0`):
- at most 3 queued commands a call (`CMP R15D,0x3` at `180b60018`);
- clock correction within `sv_clockcorrection_msecs` (30 ms, about 2
  ticks);
- a warning when one player's commands take longer than
  `sv_usercmd_execute_warning_ms` (5.0 ms, `1800d0370`), timed with
  `RDTSC`.

This build has no `sv_maxusrcmdprocessticks`.

`PlayerRunCommand` (`180c75ce0`) scopes the clock for one command:
- tickbase + 1;
- `curtime = tickbase/64`;
- frame time 1/64, or 0 for a late command.

The tickbase is the controller's (`m_nTickBase`, controller `+0x4b8`). The
+1 happens only when the command's `+0x90` is clear and the frame time is
not 0.

Why (inferred):
- **One command a tick** makes a player's simulation rate independent of
  network jitter. Jitter becomes queue depth, which the client corrects.
- **Substitutes** hide packet loss.
- **Late commands at frame time 0** keep a press without moving the player
  twice.
- **The 3-command cap and the 5 ms warning** mean one player cannot
  stretch the tick for everyone, and a pathological one is named.

Ours runs one command a player a tick, made locally, and has no cap or
warning yet. That is for the netcode, rank 22 below.

### 3. One command: the movement pipeline

`CCSPlayer_MovementServices::RunCommand` (`180adaaa0`, gated by
`sv_runcmds`) runs `PlayerRunCommand`. That calls `OnPawnProcessCommand`
(`180c741b0`), which runs in order:

1. the pawn's own thinks;
2. `SetupMove` (slot 34, `180adb4a0`);
3. `DoMovement` (`180c68400`);
4. `FinishMove` (slot 38, `180abdf20`);
5. the button callbacks (`180c688a0`);
6. `UpdateInputState`;
7. the post-command hooks.

Pawns and controllers are kept off the global think list: `UpdateThink`
(`1805be910`) skips classes whose vtable `+0x558` or `+0x560` says so, and
`CCSPlayerPawn` and `CCSPlayerController` do. Everything a player owns
runs at the player's own command time, which is what client prediction
replays (inferred).

**SetupMove** builds the subtick step list (`180c77d00`).
- Phases are snapped to 1/64 of a tick by adding and subtracting 131072.0
  in float32 (`180c77dcf`).
- Up to 4 forced boundaries are inserted (`180c71780`); the stashed
  friction phase enters this way.
- A validator (`180c79a30`) throws every subtick step away, and the
  command runs as one whole-tick interval, when any of these holds:
  - there are more than 32 steps (`CMP R8D,0x20` at `180c79a5a`);
  - a phase goes backwards or past 1.0;
  - a button is not a single bit inside mask `0xe1f`;
  - the summed analog input exceeds 2.0.
- So a command has at most about 37 intervals.
- SetupMove also rewrites the pawn's interaction mask from
  `mp_solid_enemies` and `mp_solid_teammates` (both 1) on every command.

Why (inferred): the validator stops a client inventing events to multiply
the server's work, and the 1/64 grid makes event times small exact
numbers that client and server compute alike. Ours has no subtick cap
(`player_sim.gd:924-929`).

**DoMovement** (`180c68400`) runs a whole move for every subtick phase
that differs from the last one it ran (read). For each, it scopes the
clock to the interval's end and calls:
- the interval reset (`180adb830`);
- `PlayerMove` (`180ad89b0`);
- the interval finish (`180abe000`, which updates the eyes and runs the
  terrain sampler).

There is no reduced path for a subtick interval. An event bends the path
with collision at the instant it happens. That gives a higher tick rate's
result where events are, without paying for one everywhere (inferred).

**PlayerMove** (`180ad89b0`):
- brings every entity's bounds up to date first (`180d117b0`, 12 bytes
  that run the full refresh `180d11a40` on the global list);
- zeroes a per-move trace counter (`services+0x648`);
- runs `FullWalkMove` (`180ad5c00`): PreMove, Duck, Jump, then WalkMove or
  AirMove, then PostMove;
- at the end adds the counter to a VProf counter named
  `PlayerMovementTraces`, unless pawn slot `0xc20` says not to (inferred:
  bots).

Valve's own production measure of movement cost is therefore hull traces
per move. Terrain casts, `CanUnduck`, the duck trace and the FinishMove
probe are not counted in it.

- **PreMove** (`180ad5fb0`):
  - builds the player cache (below);
  - with `sv_optimizedmovement` on (1), walking and not moved by game code,
    skips the start-of-move ground check and keeps the ground PostMove
    found. It clears the ground without a trace when rising faster than
    250 (`0x437A0000` at `180ad635a`);
  - runs the ladder probe only with input or on a ladder.
- **WalkMove** (`180ae3950`):
  - friction, acceleration and the speed cap; half the acceleration is
    deferred;
  - under 1 u/s it stops with no trace at all, not even StayOnGround;
  - otherwise one hull trace to `origin + v*dt`. If clear, it moves and
    runs StayOnGround (`180add7e0`: up 2, down to the step height, snapping
    only on walkable ground for a change over 1/64);
  - if blocked, TryPlayerMove (`180adffc0`: 4 bumps, 0.03125 back-off,
    reusing the first trace), then StepMove (`180addb20`), then one raised
    retry at 64 u/s, then StayOnGround.
- **AirMove** (`180adc620`): split air acceleration and gravity, then
  TryPlayerMove.
- **PostMove** (`180ad5d10`) always categorizes (`180ab45d0`):
  - one inset hull trace, skipped when rising faster than 140;
  - up to 4 quadrant hull traces (`180adef70`) when nothing standable is
    under the centre;
  - then it clears the player cache.

The budget, counted from those paths (estimated):
- still on the ground: 1 trace an interval;
- a clear walk with input: about 5;
- a blocked walk at worst: about 31;
- in the air: up to 4, 8 in the landing branch.

On top come up to 25 terrain casts an interval while moving (section 4),
and one 72-unit air probe a command (`180adeca0`).

Every loop is bounded:
- 3 commands a call;
- 32 subtick steps plus 4 forced boundaries;
- 4 bumps;
- one step retry;
- 4 quadrants;
- 64 cached players;
- 25 terrain cells, and 512 cached cells.

Bots run the same pipeline; no movement level of detail was found.

Why (inferred): Valve does not minimise traces. CS2 spends more hull
traces an interval than we do (about 5 on a clear walk, against our 2.7 a
player a tick). Instead, each trace is made cheap and every loop is
bounded. The next section is how.

### 4. Traces: values on the stack, and the players kept out of the movement query

Nearly every gameplay trace goes through one function,
`CGamePhysicsQueryInterface::TraceShape` (`180c28520`, VProf scope and an
atomic counter "PhysicsTraces"). It is called from 121 functions. Bullets'
interval query, overlap queries and exact pair casts go to the physics
module directly.

**The filter** is a plain struct of about 0x48 bytes on the stack:
- three 64-bit layer masks: interacts-with, exclude, and interacts-as;
- two entity ids, two owner ids and two hierarchy ids to ignore;
- a collision group and flags;
- a byte saying whether it has a `ShouldHitEntity` override.

The physics module compares the ignore ids inside the query (`180c20a60`,
`180aae950`). Nothing in the world is edited to leave a body out.

**Two paths through TraceShape:**
- Without the override: one call (world slot `+0x558`) returns the closest
  hit into a 0x48-byte stack record.
- With it (slot `+0x560`): every candidate is collected into a vector with
  128 inline slots and sorted, start-solid first and then by fraction.
  World hits are accepted without a callback; the rest are asked of
  `ShouldHitEntity`.

The hit becomes a `CGameTrace` (`180be76a0`) with no allocation.

The movement filter (`CTraceFilterPlayerMovementCS`, vtable `181920e20`)
always has the override. It never hits collision group 0x10, and defers to
the teammate rule (`180ae0f20`) when both pawns carry the same team tag.
Under the default `mp_solid_teammates` 1 no pawn carries one, so everyone
is solid to everyone. Standing on a player (`180acbfa0`): never on one
standing on you, always on an enemy, and on a teammate through a stacking
test.

**The player cache: players are not in the physics query for movement**
(`sv_use_playercache`, default 1, `1800cafa0`).
- **The build.** PreMove builds the cache (`180ad8140`). The region is the
  hull grown by `max(24, maxspeed/64)` on every side and
  `max(12, stepsize)` more vertically. It holds up to 64 living pawns whose
  box overlaps the region, as origin plus mins and maxs.
- **Each movement hull trace** goes through `180ad6d80`. When the cache is
  valid and covers the swept box, it adds the player layer (`0x40000`) to
  the exclude mask and runs the engine trace. It then sweeps the hull
  analytically against each cached box (`180ab43c0`, then `181474190`):
  - the other box is grown by the mover's half extents;
  - a slab test with tolerance 0.03125;
  - a normal of ±1 on the entry axis;
  - fraction 0 for a start inside.

  A box wins when it is earlier, or when it starts solid and the world
  trace does not.
- **Outside the region** it falls back to `180ad6700`: the world trace,
  then one exact cast per eligible player.
- **PostMove clears the cache.**

Why (inferred):
- Commands run one player at a time, so nothing else moves during an
  interval and a snapshot of the others is exact.
- Ten box tests cost a few dozen flops each, against a walk of the
  broadphase and an exact cast for each player it turns up. The pawns
  stay in the physics world; it is the movement query that leaves them
  out.
- The 1/32 skin gives stable, axis-aligned contacts that never start
  inside each other.

**Hitboxes are not physics bodies.** `CCSHitboxSystem` (vtable `181918528`)
keeps one padded box per entity in 8-wide SIMD lane arrays (`1801a9a60`,
`1801a9880`). A trace with the hitbox bit slab-tests those boxes after the
world query, bounded by the world hit. Exact hitbox shapes are cast only
for the bodies the ray reaches (section 6).

**Bounds are kept current lazily.** A moved entity goes on a dirty list.
Each query refreshes only the dirty entities its rules could hit
(`180d117c0`, under a recursive mutex). `PlayerMove` and `FireBullets` run
full refreshes.

**The terrain eye sampler** (`180a6cb30`) runs at every interval's finish:
- **In the air:** it returns at once without a world ground entity.
- **Standing still:** it reuses its answer when the position, floored to
  0.01, is unchanged.
- **Otherwise:** it fills a 5x5 grid at 8 units, skipping cells whose
  cached height is close to the current one. The cache is keyed by integer
  XY, holds 512 entries, and never stores failures.

Each miss is a zero-height ±3.99 square cast with a callback-free filter on
mask `0x2011` (`180a69a60`). That takes TraceShape's cheap closest-hit
path and meets no player and no hitbox.

Ours runs this algorithm in GDScript (`src/movement/ground_eyes.gd`), and
its casts cross into Box3D through a Variant call each
(`src/physics/terrain_trace.gd:17-24`). That is the 0.58 ms.

What each of our queries pays instead (read, `native/src/hull_mover.cpp:1002-1023`
and `src/physics/box3d_queries.gd`):
- a Variant call;
- a new String-keyed Dictionary for the result;
- `get_meta` and an ObjectDB lookup to find the body;
- 10 player hulls and 190 hitbox capsules kept as Box3D proxies.

Once a player's tick, not per query, a layer write on the mover's own
proxy leaves it out of every cast in that scope (`box3d_queries.gd:155-195`).

In script, a hull cast through the bridge is 20 µs, a terrain cast about
21 µs all-in, and a world ray 12 µs. The first ray of a tick that can
meet a hitbox is 101 µs on average and 1,453 at worst. Box3D's 0.246
overlap band also turns player contact into recovery searches of up to 22
casts.

### 5. Bots: aim every tick, decide every other tick, think in parallel only where it reads

The bots live in `FrameUpdatePreEntityThink`. `CBotGameSystem`
(`18031da10`) calls `CCSBotManager::StartFrame` (`1802df210`), which calls
`CBotManager::StartFrame` (`180325130`). So every bot decides from the
world as the last tick left it, before any command runs. That is our
`GameWorld.commands_for` contract.

`CBotManager::StartFrame` runs, in order (read):
1. **Smokes.** It refreshes the smoke list (`1803271d0`): spheres used for
   sight.
2. **The parity flag.** Each bot gets `~(pawn entity index + tickcount) & 1`
   (`180325890`-`18032589c`).
3. **Threat search, in parallel.** With `sv_bot_parallel_threat_detection`
   on (1), it first computes every living player's sight points serially
   (`ComputePartPositions`). Then a ParallelFor runs each flagged bot's
   `UpdateReactionQueue` (`1802e6b10`), the threat search, on the thread
   pool.
4. **Then serially, for every bot:**
   - `Upkeep` (`1802e6d30`) every tick: aim, no rays;
   - `Update` (`1802e2450`) only on flagged ticks, so at 32 Hz: decisions,
     path following, the current enemy's re-check;
   - slot 22 every tick, which builds and submits the command
     (`ExecuteCommand`, `1802e68e0`).

No convar sets these rates. Which half of the bots runs on a tick follows
their entity indices, and nothing balances it.

**Sight.** `IsVisible(pos)` (`1802cd3d0`) tests in cost order:
- blindness (a time on the pawn);
- the field of view: cos 0.766, a 40-degree half-angle;
- smoke, analytically: the chord through each sphere is summed against
  `bot_max_visible_smoke_length` 200;
- only then one line trace from the bot's cached eye.

`IsVisible(player)` (`1802cd6a0`) checks range, then five points from the
per-frame cache: gut, head, feet (origin + 5) and two sides.
`FindMostDangerousThreat` (`1802bf7e0`) gives a teammate one ray and an
enemy up to five, keeps up to 16 threats sorted by distance, and rolls a
newly seen enemy against a visibility score (`1802cc000`). Peripheral
vision, one ray per spot in the bot's nav area, runs at most every
0.29 s.

**Reaction is a delay line.** The chosen threat goes into a 20-entry ring,
and the bot acts on the entry `n` back (`UpdateReactionQueue`; the
recognized enemy comes from `1802c6410`). At 64 Hz the delay comes to
about 2/3 of the profile's reaction time, less 1/32 s (estimated). The
Normal profile's 0.6 s gives about 0.375 s.

**Aim.** Upkeep predicts the last seen spot plus velocity times the time
since, adds an error and removes most of the aim punch. The error is
redrawn by `SetAimOffset` (`1802d8380`) every `AimFocusInterval × U(0.8, 1.2)`
s. `UpdateLookAngles` (`1802e4300`) moves the view with a damped spring on
each axis, pitch twice as stiff.

**Paths.** `ComputePath` (`1802bafa0`) has a per-bot cooldown of
`U(0.4, 0.6)` s and searches synchronously inside Update. There is no
global cap by default: `throttle_expensive_ai` (0) is opt-in, and
`nav_pathfind_multithread` is 0.

Why (inferred):
- **Aim** is a control problem: a spring needs small, regular steps.
- **Decisions** model human reaction, hundreds of milliseconds, so 32 Hz
  loses nothing, and parity halves their cost without a timer per bot.
- **Only the read-only ray work is threaded**, and the cheap tests come
  before any ray.
- **The path cooldown's jitter** keeps bots out of step.
- **One intake for bots and clients** means a bot can never move or shoot
  differently from a player, and takeover needs no special case.

Ours runs every bot's think every tick, aligns the round planner's reviews
on one tick (`src/bots/bot_round_plan.gd:55-59`), and gives out 2 path
searches a tick in all.

### 6. Shots: one rewind a trigger pull, transforms not bones, hitboxes outside the physics world

`FX_FireBullets` (`180298420`) runs, in order:
1. `StartLagCompensation` once a pull (`180ed9ba0`);
2. a full refresh of the dirty bounds;
3. the pellets' spread;
4. `FireBullet` (`180a713c0`) for each pellet, given 4 penetrations;
5. `FinishLagCompensation` (`180ec02f0`).

Damage is applied inside that bracket, to whichever targets the filters
below rewound. The knife and the Zeus use the same pair.

**The history** is recorded at `FrameUpdatePostEntityThink`
(`180ec0520`), after everyone has run, when `sv_unlag` is on and there are
two players or more. `RecordDataIntoTrack` (`180ed28b0`):
- clears a dead pawn's track;
- recycles records older than `sv_maxunlag`;
- adds a record only when the pawn's simulation tick advanced;
- drops all older records on a jump of more than 64 units (squared 4096
  at `180ed2bf0`) or a change in the hitbox count.

A record is 0x480 bytes from a per-entity pool with a free list. It holds
origin, angles, bounds, the tick, and the world transform of every hitbox:
position, scale and rotation, 32 bytes each. It holds no bones.
`sv_maxunlag` registers at 1.0; the game's config sets 0.2
(`reference/research/combat.md`, GI 81).

**Which moment is rewound to.** `GetTargetTime` (`180ec49e0`) takes the
current tick less the latency, and accepts the client's own render time
only within 200 ms of that. With `sv_csgo_shoot_use_full_interp` on, the
rewind (`180ed7eb0`, a virtual: only vtables refer to it; the entry
`FX_FireBullets` calls is `180ed9ba0`) reads the two ticks the client was
drawing between and the fraction, and lerps exactly those two records.

**Who is moved: the cheapest tests first.**
- The shooter must be attacking: the attack held, or the last attack
  within 5 commands (`1801ec9c0`).
- Teammates are not moved without friendly fire.
- With `sv_lagcomp_filterbyviewangle` on, a target must be near, or
  within 45 degrees of the view (`180d147c0`).
- It must be within the weapon's range + 1024 (`180edd070`).
- To move its hitboxes, its bounding sphere plus 10 units must meet a
  20-degree cone along the shot (`180ed6f80`, `181474940`).

Why (inferred): moving an entity is the expensive part, so only bodies
that could be hit are moved.

**The rewind moves a pointer, not a skeleton.** `BacktrackEntity`
(`180eba4d0`) lerps origin and bounds, interpolates the recorded hitbox
transforms (`180cad220`), and points `CSkeletonInstance+0x400` at the
result. While it is set, every hitbox query returns that list. No bone is
rewound and no animation re-run. `RestoreEntity` (`180ed4eb0`) puts back
what nothing else changed meanwhile, and clears the pointer.

**The hitbox test.** `CCSHitboxSystem` slot 1 (`180a305b0`):
- takes the set's transforms: the rewind's if set, else a 4-slot history
  ring if the skeleton has one, else bones computed with mask 0x100;
- casts the ray against each hitbox's sphere, capsule or box.

It does not keep the nearest hit. It keeps the nearest in each hit-group
bin and takes the bins in a fixed order, which as Source's hit groups
reads head, stomach, chest, neck, arms, other, legs (the reading is
inferred). Slot 0 (`180a31270`) casts back for the exit, so a body
becomes one flesh solid a round can pass through.

**A bullet's path is a list of intervals.** `TraceBulletIntervals`
(`180a6a6a0`) makes a world-only sizing pass, then one
`TraceLineIntervals` (`180c27be0`) that returns every crossing along the
line, with the hitbox system's intervals merged in.
`BuildSegmentsFromContacts` (`180a6e900`) turns them into alternating free
and solid segments. `HandleSegmentPenetration` (`180a90e10`) applies the
range falloff and the wall loss to each. The main query does not grow
with the number of walls.

Ours tests rounds against 190 Box3D hitbox proxies, brought up to date at
the first hitbox ray of a tick. It keeps no history: a round meets the
last drawn pose, which depends on join order and frame timing.

### 7. Animation, bones and the dead on the server

**Animation runs on the tick.** `AnimTickUpdate` (`180530420`) advances
every animgraph-2 entity's graph every tick, on worker threads, with
`dt = ticks since its last update / 64`. An entity whose
`m_bAnimGraphUpdateEnabled` is off is skipped and stamped, so it never
catches up with one huge step.

**Bones are lazy.** `CalcWorldSpaceBones(mask)` (`180c9f9d0`) returns at
once if that class of bones is already computed. Otherwise it takes the
skeleton's lock and computes only those bones: hitboxes `0x100`, physics
`0x10`.

**A death builds no server ragdoll.** `DeathNotice` (`180917780`) fires
`player_death` synchronously. `1801c5740` then:
- writes the client ragdoll's inputs: damage bone, force, weapon name,
  headshot;
- sets `m_bRagdollClientSide`;
- changes the pawn's collision once (`180adba60`);
- clears `m_bAnimGraphUpdateEnabled`.

Why (inferred): a body decides nothing, but costs seconds of solver work
after every kill, and kills cluster.

Ours:
- steps each death's ragdoll in the tick's Box3D world for seconds;
- poses hitboxes from frames;
- turns a dead body's tree off and pays a 2 to 3 ms reactivation step on
  the tick at the respawn (`player_model.gd:1130-1136`, `1373-1383`).

### 8. Thinks, physics, events and network state

**Thinks are a schedule.** `SetNextThink` (`1803e4ea0`) works in integer
ticks: `(int)(t*64+0.5)`, with -1 meaning never and a positive time that
rounds to 0 becoming tick 1 (read in disassembly). The manager keeps a
dense list of only the thinking entities, with a side table of 0x8000
slots. Cost follows the thinkers, not all entities. Moving things are on a
separate simulating list (`1805bab90`), stepped every tick.

**Physics.** `CPhysicsGameSystem::OnSimulate` (`18059f050`):
- pulls kinematic targets;
- simulates its simulating list;
- makes one physics-module call that steps every world at 1/64;
- pushes back the moved bodies.

Its transform workers default to serial.

**Events cost what their audience costs.** `CreateEvent` (`180be93a0`)
allocates an event only when it has listeners or is forced. `FireEvent`
(`180bf9220`) calls each listener at once and frees the event.

**Network state is marked at the assignment.** Every networked setter
compares, assigns and marks the field (`1801a70a0`). Up to 48 changed
offsets are kept an entity; past that, the entity is marked fully
changed.

Ours:
- ticks every entity every tick after copying the list
  (`src/game/sim_entities.gd:62-69`);
- copies each event's whole default schema whatever the audience
  (`src/game/game_events.gd:209-238`).

## What CS2 teaches about building a tick

1. **One fixed order, set by what each stage reads:** input decided,
   commands, reactions, then the batch passes.
2. **Bots are clients.** They decide before anyone moves and hand a real
   command to the same intake as the network.
3. **Thread only what reads the world and writes itself.** Commands,
   movement, thinks and rules stay on one thread in CS2 too. Our bots'
   run_command, 69% of the tick, is serial in CS2 as well. The lever is
   what each query costs, not more threads.
4. **Do not minimise traces; make each one cheap.** Each one is a stack
   filter, a stack result and no allocation, all in C++. The terrain
   sampler shows the cost of the wrong tier: the same algorithm in
   GDScript costs 0.58 ms of our 2.42 ms tick, 32% over the tick without
   it.
5. **Keep what moves every tick out of the queries, and test it
   analytically.** Movement traces leave the players out by layer and
   sweep them as cached boxes; hitboxes are SIMD boxes outside the
   physics world, with exact shapes built only for what a ray reaches.
6. **Split the rate by what each part needs.** Control loops run every
   tick; decisions run at human speed, staggered by parity; path searches
   carry a jittered cooldown per bot.
7. **What is only seen or heard is not server state:** no server ragdoll,
   no event without a listener.
8. **Schedule, do not sweep; compute lazily.** Thinks run when due,
   bounds refresh when dirty, and bones are computed by class when asked.
9. **Bound every loop a client or the world can drive, and name the
   player who blows the budget.**
10. **Count the cost you budget.** Valve counts hull traces per move,
    terrain casts apart. Ours folds terrain casts into `PlayerBody.traces`
    (`ground_eyes.gd:123`), so the 54.7 "traces" a tick are about half
    terrain casts (27.7).
11. **Record history once a tick into pooled records holding what the
    rewind needs.** Then rewind by override, not by re-posing.
12. **Time is integer ticks and a constant.** CS2 multiplies by a literal
    64.0. Ours reads `Engine.physics_ticks_per_second` on every `SimClock`
    call (`src/sim/sim_clock.gd:16-27`), from 27 call sites in
    `player_sim.gd` alone.

## What to tackle next

Ranked by tick time saved on the frames that hold a tick, closeness to
CS2, determinism risk and effort. "Remote" items are code a cloud thread
can do; "Local" items need Sid's machine for the extracted assets or his
eyes.

1. **Repair and split the profilers before cutting.** Remote edits, Local
   runs.
   - `profile_player_tick.gd` is repaired in this PR. It still needs a
     clock around `GroundEyes._sample` and the terrain cast, which today
     hide inside simulate's 133 to 178 µs of own time.
   - `profile_box3d_costs.gd` needs terrain buckets. TerrainTrace calls
     the native world directly (`terrain_trace.gd:17-24`), outside its
     cast buckets.
   - `profile_dust2.gd` needs end_tick split into MatchState.tick,
     tick_all, the drop world, ItemDrops, Economy, BombSystem and the
     events' flush. Add the bots' sight rays and path searches granted
     and refused.
   - A hull-only trace count and a recovery-cast count beside
     `PlayerBody.traces`, comparable with `PlayerMovementTraces`.
2. **Port the terrain-eye sampler to the native library**, held bit-exact
   to the script as the movement step is. Remote code, Local A/B.
   - **Where:** `src/movement/ground_eyes.gd:56-197` and `TerrainTrace`
     stay as the reference, added to `PlayerBody.NATIVE_COPIES` and
     `native/SConstruct`. The sampler can run inside `HullMover::step`
     after the step, to save a second crossing.
   - **Saving:** estimated 0.25 to 0.40 ms a tick, 10 to 16%. The
     terrain cast's Box3D share, unmeasured, bounds it.
   - **The float32 points to hold:**
     - the 0.01 quantisation;
     - `height()`'s 196608 add;
     - `floorf(contact*10)/10`;
     - `first_cell`'s fmod;
     - the PackedFloat32Array heights in `compute_drop`.
3. **Take the death ragdoll off the tick.** Local. Do as CS2 does: record
   the ragdoll's inputs at the death (bone, force, weapon, headshot,
   origin).
   - **Phase A:** drop the body on the next frame.
   - **Phase B:** step it in a ragdoll-only Box3D world from frames that
     hold no tick, as unseen bodies' animation already is.
   - **Saving:** estimated 0.7 to 1.0 ms off a 3.8 to 4.6 ms kill tick,
     and 0.15 to 0.6 ms off every tick for the seconds a body falls.
   - **First measure:** the second world's build time and memory. It
     would hold dust2's 435,649 triangles again.
4. **Test rounds against capsules in script, as CS2's hitbox system
   does, not Box3D proxies.** Remote code, Local run.
   - **The change:** a world-only ray, then the capsules of the bodies
     whose boxes the line passes, bounded by the world hit. The capsule
     tests move from `box3d_queries.gd:894-973` into a new
     `src/combat/hitbox_query.gd`. Rounds stop calling `_sync_sets`.
   - **Saving:** estimated 25 to 70 µs a round against today's 101 µs
     mean and 1,453 µs worst for the first hitbox ray. The mean tick
     barely moves; shot ticks do.
   - **Groundwork:** this is what lag compensation (8) builds on.
5. **Take body work off the transition ticks.** Local.
   - **Respawn:** pose without the reactivation step. Either keep the
     hand-stepped tree active through a death, as CS2 stamps and skips,
     or pose waiting bodies on frames in freeze time.
   - **Buys:** add every set a side can hold when the body is built, so
     the clip library never changes in play.
   - **The side swap:** build each player's other-side body ahead, one a
     frame, in the half's last round.
   - **Saving:** 2 to 3 ms a body off spawn and buy ticks, and about 26 ms
     off the half-time tick (estimated from 2.6 ms a body).
6. **Bots on CS2's cadence.** Remote.
   - **Phase 1:** sight on alternate ticks by `(userid + tick) & 1`,
     keeping last tick's target.
   - **Phase 2:** split `_think` into Update (decisions, sight, paths, at
     32 Hz) and Upkeep (aim and the command, every tick).
   - **Saving:** estimated 0.15 to 0.2 ms a tick when thinking in turn,
     0.05 to 0.09 on the threads. Both think-path checks must still
     agree.
7. **Spread the path searches.** Remote.
   - Opening paths in freeze time, and a per-bot `U(0.4, 0.6)` s
     cooldown drawn from a seeded hash.
   - Planner reviews staggered by slot.
   - The failed search's `push_warning` taken out of the tick (about
     1 ms a print).
8. **Lag compensation, CS2's way.** Remote, two pull requests.
   - **The history:** a ring of 14 records a player, written at end_tick
     from the tick's own root and the last fit's capsule ends.
   - **The rewind:** the single-interp lerp of the two ticks you drew
     between, once a pull. Bots, which send no render tick, use the
     newest record.
   - **Cost:** estimated 0.01 to 0.02 ms a tick. It is the largest
     fidelity gap left in the tick: a round meets the last drawn pose,
     and bots' rounds miss moving bots by up to about 7 units.
9. **Take players out of the hull sweeps, with CS2's player cache, in
   both backends.**
   - **The change:** sweep the other players as cached boxes with a 1/32
     slab test, and remove the player recovery code that exists only
     because of Box3D's band.
   - **Saving:** estimated 0.05 to 0.2 ms a tick, more on bunched slow
     ticks.
   - **Risk:** high determinism risk. It waits on (1)'s recovery count.
10. **A CS2-shaped cast in the Box3D patch.** A packed result and ignore
    ids instead of a Dictionary (the layer write is once a player's tick
    already, not a cast's). Estimated 1.5 to 3 µs a
    cast. Pairs with 2 and 9.
11. **Run the match after the entities**, as CS2's rules run after every
    think. No cost. It fixes the grenade-kill round ending a tick late.
12. **end_tick without allocations.** One `C4.Actor` a player refilled in
    place, typed reads, empty systems not called, and the entity list
    copied only when it changed. Estimated 0.04 to 0.09 ms and about 40
    fewer allocations a tick.
13. **Events only for an audience.** Return before copying the defaults
    when nobody listens. Turn a death's hitboxes off in one pass (361
    iterations to 38).
14. **View work out of the tick.** Grenade models built on the frame
    after the throw. The use search culled by distance.
15. **Cheap rejects first in bot sight**, as CS2's order does:
    blindness taken once, one query object a bot, no smoke test with no
    clouds.
16. **Bots react and aim like CS2:**
    - the 20-entry reaction ring;
    - the look spring;
    - the decaying focus error;
    - leading the target;
    - pulling down the recoil.

    Needs 6.
17. **Movement rules to CS2's:**
    - subtick validation, with the 32-step cap;
    - the ground cleared above 250 u/s without a trace;
    - the 72-unit air probe as a hull sweep;
    - the quadrant fallback as sub-hull sweeps.
18. **A think schedule for entities in integer ticks.** Under 10 µs today;
    it keeps cost in proportion as rounds fill the map.
19. **CS2's sight:**
    - a per-tick part-position pre-pass;
    - a 40-degree cone;
    - five points an enemy;
    - the threat list and the noticing roll.

    Its cost can go either way, up to about 1.3 ms at 5v5 at worst, so
    measure both cones first.
20. **Penetration and hit-group priority as CS2 scores them.** A gameplay
    change: it needs CS2 captures and Sid's sign-off.
21. **A cheaper path search.** Split `walk_path`, then cache routes or
    port the funnel to the native library.
22. **The command queue, caps and warning for the netcode.** No effect
    while commands are local.
23. **Measure first, then decide:**
    - `SimClock` caching;
    - `PlayerModel.update_motion`, 0.164 ms a tick for ten;
    - posing on the tick for a dedicated server, 1.62 ms a batch of ten.

The steady-tick items, 2, 6, 9, 10 and 12, sum to an estimated 0.4 to
0.85 ms: about the 0.7 ms the tick grew since 2 October. Items 3, 4 and 5
are the event ticks, the ones that make the slow seconds of play.

## Not established yet

- **Whether this reaches the 6 ms frames.** The rendered frame holding a
  tick was last split on 30 September, before the terrain eyes. Run
  `scripts/watch_game.gd` at 1080p on current main, and again after each
  item.
- **The terrain cast's Box3D share, and the recovery casts' share of the
  hull casts.** These need the profiler splits in item 1.
- **Spawn and buy tick costs** were not split. Tell reactivation from new
  clips with a stopwatch round `pose_again` and the first step after
  `_add_set`.
- **`profile_box3d_costs.gd`'s own listeners** make the drop world step
  every tick. Its end_tick and native-step figures are not the game's
  idle tick; `profile_dust2.gd`'s 0.18 ms is.
- **CS2 questions left open:**
  - the order of the four post-think systems;
  - whether `CCSGameRules::Think` polls elimination every tick;
  - how buy and bomb zones are kept;
  - whether bots' shots are lag-compensated;
  - which skeletons own the 4-slot hitbox ring;
  - the sub-box geometry of the quadrant fallback;
  - the CheckStuck stagger;
  - the bots' path cost function;
  - how CS2 swaps models at half time;
  - what `vphysics2.dll` does inside a step.
- **Box3D.** Whether a layer write rebuilds a broadphase proxy, as Box2D
  v3's public source does, and what one costs.
- **Twenty players** have not been measured on current main.
- **Determinism coverage for a native sampler:** a synthetic-geometry
  both-ways check that runs on CI, since the dust2 checks skip there.

## Reading CS2 again

`scripts/shooting_audit/TickQuery.java` runs read-only query batches over
an analysed project. Its usage is in `scripts/shooting_audit/README.md`.
Never open one project from two headless runs at once. For parallel
readers, copy the project once per reader; this audit used seven copies
of the analysed server project on D:.

The functions this page relies on, for `server.dll` build 2000922
(SHA-256 `3541e46a…`) only:

| Address | What it is |
|---|---|
| `180dd3dd0` | `CSource2Server::GameFrame`: one tick, in order |
| `1805349a0` | dispatches a game-system event to every listener |
| `1805af880` | `CSimThinkManager::Run`: commands by controller in slot order, then due thinks |
| `1805be910` | `UpdateThink`: the think list; player pawns and controllers kept off it |
| `1803e4ea0` | `SetNextThink`: `(int)(t*64+0.5)` |
| `180e89370`, `180e88ee0` | `PhysicsRunThink`, and one context's think |
| `18138bee0` | entity input and output serviced |
| `180fc2790` | timers due by now |
| `180f929f0` | the trace query cache, refreshed in parallel |
| `180b616a0` | `ProcessUsercmds`: one intake for clients and bots |
| `180ece170` | `CPlayerCommandQueue::RunTickCommands`: one command a tick, substitutes, late commands |
| `180b5f9c0` | `OnSimulateUserCommands`: at most 3 a call, the 5 ms warning |
| `180b3f420` | clock correction |
| `180c75ce0` | `PlayerRunCommand`: the clock for one command |
| `180c741b0` | `OnPawnProcessCommand`: one command's steps |
| `180adb4a0`, `180c77d00`, `180c79a30` | SetupMove, the subtick step list, its validator |
| `180c68400` | `DoMovement`: a whole move per subtick interval |
| `180ad89b0` | `PlayerMove`, and the `PlayerMovementTraces` counter |
| `180ad5c00`, `180ad5fb0`, `180ad5d10` | FullWalkMove, PreMove, PostMove |
| `180ae3950` | WalkMove |
| `180adffc0`, `180addb20`, `180add7e0` | TryPlayerMove, StepMove, StayOnGround |
| `180adc620` | AirMove |
| `180ab45d0`, `180adef70` | CategorizePosition and its quadrant fallback |
| `180abdf20`, `180adeca0` | FinishMove, and the 72-unit air probe |
| `180abe000`, `180ae23e0` | the interval's finish, and the eyes |
| `180a6cb30`, `180a69a60` | the terrain sampler and its cell cast |
| `180ad8140`, `180ad6d80`, `180ad6700` | the player cache: built, used, and the fallback |
| `180ab43c0`, `181474190` | the box sweep and its slab test |
| `180ae0f20`, `180ae0de0`, `180acbfa0` | teammate solidity, stacking, standing on a player |
| `180c28520` | `CGamePhysicsQueryInterface::TraceShape` |
| `180be76a0` | a hit converted to `CGameTrace` |
| `180c27be0` | `TraceLineIntervals` |
| `180d117c0`, `180d11a40` | dirty bounds refreshed for a query, and in full |
| `1801a9a60`, `1801a9880` | the hitbox system's SIMD boxes |
| `180298420` | `FX_FireBullets` |
| `180a713c0`, `180a6a6a0`, `180a6e900`, `180a90e10` | a bullet: the trace, its intervals, segments, penetration |
| `180a305b0`, `180a31270` | the hitbox test with hit-group priority, and the exit |
| `180ec0520`, `180ed28b0` | lag compensation recorded, and one track |
| `180ec49e0`, `180ed7eb0`, `180ed9ba0` | the target time, and starting a rewind |
| `1801ec9c0`, `180d147c0`, `180edd070`, `180ed6f80` | who is rewound: the attack, the view, the range, the cone |
| `180eba4d0`, `180cad220`, `180ed4eb0` | the rewind, the transforms' lerp, the restore |
| `180530420` | `AnimTickUpdate`: animation on the tick |
| `180c9f9d0` | `CalcWorldSpaceBones(mask)`: lazy bones |
| `180ca5ed0` | the hitbox list and transforms: rewind, ring, or bones |
| `180917780`, `1801c5740`, `180adba60` | a death: the notice, the client ragdoll's inputs, collision |
| `18059f050`, `1805bab90` | the physics step, and the simulating list |
| `180be93a0`, `180bf9220` | `CreateEvent` and `FireEvent` |
| `1801a70a0` | network state marked at the assignment |
| `18031da10`, `1802df210`, `180325130` | the bots' frame: parity, the parallel threat search, Upkeep, Update, the command |
| `1802e6d30`, `1802e2450`, `1802e68e0` | Upkeep, Update, the command submitted |
| `1802e6b10`, `1802bf7e0`, `1802cc000` | the reaction ring, the threat search, the noticing score |
| `1802cd3d0`, `1802cd6a0` | sight: a point, and a player's five points |
| `1802d8380`, `1802e4300` | the aim error, and the look spring |
| `1802bafa0` | `ComputePath`: the per-bot cooldown |
| `1803271d0` | the bots' smoke list |
