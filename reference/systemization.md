# Systemization audit

Read from `main` at `79f6ca6` (PR #43) on 2026-09-23, every file under `src/`,
the two map scripts, the test runners and the roadmap, at Sid's request, in
the project's "Systemization audit" thread. Revised the same evening
against `5a700c1` (PRs #44 and #45: Jolt, and the local agent's performance
audit, `reference/performance.md`) and `526e7ba` (PR #46: 64 ticks a
second). Line numbers are for the commit named beside them, or `79f6ca6`.

This copy in the repo is the one to keep current, as with the roadmap:
whoever lands a step marks it done here in the same pull request.

Done: step 0 (the test runner and CI, 2026-09-23); the world that owns the
tick, in its first form (finding 1, brought forward into step 1 by Sid,
2026-09-23: `GameWorld`); the item registry and the inventory, wired into
every player (finding 5, 2026-09-23: `ItemRegistry`, and an `Inventory` on
each `PlayerSim` that the game knows by userid, each gun its own `Weapon`
through a switch, a drop and a pick-up, the slots in the command); damage
that knows who dealt it and game events, for rounds (findings 3 and 4, the
contract threads, wired into `player_sim.gd` the same day; the flinch and
the fall still read the `last_hit_*` fields).

The question asked: where does the code repeat itself, or hand-build one
case at a time, in a way a shared system would replace, and in what order
should those systems be built so the roadmap's next items (inventory,
economy, buying, the round HUD, the bomb, grenades, bots that play CS,
netcode) land on them instead of adding to the repetition.

## In short

The split made in PR #24 holds: every player runs from `UserCmd`s on
`SimClock` time, and what is drawn only reads the simulation. What is
missing is everything around the players. Nothing owns the simulation's
tick, a bot is a subclass of the player rather than a player with a brain,
damage does not know who dealt it, the simulation reports what happened
through signals that carry scene nodes, and every gun is written by hand.
Each of the next roadmap items needs one or more of these, so building them
first is cheaper than building items 12 to 20 around their absence.

The three to do first, because items 12 and 13 need them at once:

1. **An item registry by CS2 class name**, covering all 43 classes in
   `vdata.csv` (guns, grenades, knife, Zeus, bomb, kit, armour). This is
   weapons TODO R1, widened.
2. **Damage that carries its attacker** (`DamageInfo`), through one path
   for bullets, grenades, fire, the bomb, the knife, the Zeus and falls.
   Kill awards, the kill feed and the scoreboard have nothing to read today.
3. **Game events**: one stream of plain-data events out of the simulation
   (a death, a shot, an impact, a round's end), which the HUD, sound,
   decals, economy, bots' hearing and later the network all read.

## What is already systemized, and should stay as it is

- `UserCmd` and `SimClock` (`src/sim/`): one command shape for keys, bots and
  later the network, and simulation time in microseconds derived from the
  tick. Every new system should take its input from these.
- `WeaponVData` reads every number the firing model uses from the game's own
  file, with the sheet only for landing and ladder. This is the model the
  item registry below extends to everything else a player carries.
- `MatchRules` is a Resource whose fields are CS2's convars with their
  names in the comments. The settings system below generalises it.
- Deterministic seeds for spread, the hit flinch's lean and spawn order.
- The data readers for the map (`SourceNavMesh`, `BrushVolume`,
  `MapOverview`, `SurfaceProperties`, `SourceEntities`, `NmGraph`) each
  answer questions about one of the game's files and do it well; finding 12
  is only about what they share.

## Findings

### 1. Nothing owns the simulation's tick

Each player ticks itself in its own `_physics_process`
(`player_controller.gd:84`, `bot.gd:160`), `MatchState` runs after them
because it sets `process_physics_priority = 100` (`match_state.gd:105`), and
`Footsteps` and `PlayerView` have physics callbacks of their own. The order
players run in is the order they were added to the scene: on dust2 you run
before every bot (`de_dust2.gd` adds you first), so your rounds meet where
the bots stood last tick and theirs meet where you stand this tick. Nobody
chose that order; it falls out of the scene tree.

Finding the players is a group scan every time (`bot.gd:332` for sight,
`player_sim.gd:627` for spectating, `de_dust2.gd:185`), and there is no list
of what else exists in the world, because nothing else exists yet.

**Why now.** The bomb, dropped weapons, grenades, fires and smokes are all
things that tick. Economy runs after a round ends, the bomb stops the round
clock, a smoke changes what a bot can see. Each would pick its own process
priority. Netcode needs one place that gathers a command per player, runs
the tick in a fixed order and takes a snapshot after it.

Two things merged since show the gap. The profiler the local agent wrote
(`scripts/profile_dust2.gd`) switches off every node's physics and process
callbacks and runs them itself, in its own loop, to time the tick by
system: it had to build the loop the game does not have. And the cap of two
nav-mesh searches a tick is a pair of static counters on `Bot` keyed by
tick number, because there is no world object for a per-tick budget to
live on.

**The system.** A `GameWorld` node (the server, in single player a listen
server) that owns the tick: gather one command per player from whatever
drives them, run the players in a fixed order, run the world's entities,
run the rules (match, then economy), then hand out the tick's events. It
holds the lists of players and entities that the group scans read today,
the per-tick budgets (path searches, later sight checks), the timing the
profiler measures, and the tick rate (64 since PR #46, set in
`project.godot` and read through `SimClock`).
**Size:** medium. It moves code more than it writes it.

*(Done 2026-09-23, in its first form: `src/sim/game_world.gd`.)* Each map
(dust2, the range, the movement course) starts a `GameWorld` and every
player joins it; no player and no match runs itself any more. Each tick
the world asks each player for its command (`PlayerSim.command_for`: your
keys, a bot's choices), runs them in the order they joined (on dust2 you,
then the bots), then the match at the tick's end. It counts its own ticks,
which `SimClock` reads, holds the players that a bot's sight and a dead
player's spectating look through instead of the scene's group, and gives
out the two path searches a tick. The profiler runs its tick in the
world's own parts (`begin_tick`, each player, `end_tick`) rather than a
loop of its own. Still to come on it: the world's other things (dropped
weapons, the bomb, grenades) as they arrive, the tick's events handed out
at `end_tick` (step 1), sight checks as a per-tick budget, and more of the
checks on a world they step themselves (finding 13).

### 2. A bot is a kind of player, not a player with a brain

`Bot extends PlayerSim` and `PlayerController extends PlayerSim`, so the
thing that decides and the thing that is simulated are one object. The
results:

- Weapons are handed out two ways. A player gets `equip(data)`; a bot gets
  `arm(data)` plus `weapon_data` plus `weapon_model` (`bot.gd:136`), and
  `Weapon.new` is written four times (`bot.gd:126, 138, 396`,
  `player_sim.gd:289`). `MatchState._arm` and `_swap_sides`
  (`match_state.gd:288` on) check `player as Bot` to choose between them.
- `Bot.respawn` (`bot.gd:393`) repeats `PlayerSim.respawn` with its own
  additions.
- The brain keeps its own clocks in `delta` sums and an unseeded
  `RandomNumberGenerator` (`bot.gd:105`), so a bot's game is not
  repeatable from its commands, unlike everything else in the simulation.
- The two known bot problems from the catch-up (re-pathing about 20 times
  in freeze time, and every bot sent to the same site each round) come from
  the brain having no view of the match: it cannot see that it is frozen or
  what round it is.

**Why now.** Item 23 (cover, hearing, counter-strafing) and item 24 (buying,
planting, rotating, retaking) roughly triple what a brain does. In
multiplayer a human who disconnects is taken over by a bot, and a dead
player can take control of a bot, as in CS2; both mean swapping what drives
a player without replacing the player.

**The system.** Every player is a `PlayerSim`. What drives it is a separate
command source: `PlayerInput` for you, a `BotBrain` for a bot, later the
network. The brain reads the world (its player, the match, the nav mesh,
events it can hear) and writes a `UserCmd`, with its random numbers seeded
from the tick. Inside the brain, split sensing (sight, sound), choosing a
goal (walk to a site, engage, plant, buy) and turning the goal into keys,
so item 24 adds goals rather than branches. **Size:** medium, and it
touches the same files as Sid's local agents' bot and performance work,
so it goes after the performance audit lands.

### 3. Damage does not know who dealt it

`Hitscan.fire_at` (`hitscan.gd:230`) passes the shooter's team and nothing
else about the shooter. What the victim needs to know about the hit is
written into five fields on its `HitTarget` before `apply_damage` is called
(`last_hit_direction`, `last_hit_from`, `last_hit_weapon`, set by the
caller; `last_hitbox`, `last_hit_armored`, set inside;
`hit_target.gd:46-57`), and read back by `PlayerSim._on_hit` for the tag
and the flinch. A death is announced four ways: `HitTarget.died`,
`PlayerSim.killed(zone)`, `Bot.died(zone)` and `PlayerController.died`.

Searching `src/` for an attacker, killer or shooter finds nothing.

**Why now.** Item 13's kill awards depend on who killed whom with what
(the award is per weapon). The kill feed and scoreboard (item 15) need
the same. HE grenades, molotovs, the bomb, the knife, the Zeus and falling
all do damage without a bullet, and each would otherwise add its own way
in.

**The system.** A `DamageInfo` (CS's `CTakeDamageInfo`): attacker, the item
class that did it, amount before and after armour, zone and hitbox,
direction and origin, whether armour or a helmet took part, walls gone
through, whether it was a teammate. One `take_damage(info)` on the victim,
and one death that carries the killing `DamageInfo`. Tagging and the
flinch read it instead of the `last_hit_*` fields. **Size:** small.

### 4. The simulation reports through signals that carry nodes

`PlayerSim` has seven signals (`player_sim.gd:102-115`), and
`shot_traced` passes a `Hitscan.Result` holding a `Hitbox` node. Each
listener is wired by hand to each player: `PlayerView` for you
(`player_view.gd:116-121`), `Bot._ready` for itself, the test range for
its dummy and shooter. `MatchState` has five more.

**Why now.** The kill feed, the economy, round-end sounds, bots reacting
to gunfire (item 23) and the network all need to hear about everything
that happens, not about one player. Anything sent to a client has to be
plain data; a node reference cannot be.

**The system.** Game events, as CS2 has them (`player_death`,
`player_hurt`, `weapon_fire`, `bullet_impact`, `round_start`, `round_end`,
`item_pickup`, `bomb_planted` and so on): plain-data records with player
ids rather than nodes, queued during the tick and handed out once at its
end by the `GameWorld`. The existing signals can stay for what only the
view of one player needs. **Size:** small to medium.

### 5. Every gun is written by hand

`WeaponLibrary` builds the AK-47 and M4A1-S one function each
(`weapon_library.gd`), with the model path, clip sets, body multipliers
and animation time typed in. The range's MP9 is an AK-47 with the MP9's
numbers put over it (`test_range.gd:373-378`). A player's weapon choice is
a `match` on 1 and 2 (`player_sim.gd:297`), and the side's starting weapon
another (`match_state.gd:245`). Switching weapons builds a new `Weapon`, so
it refills the magazine. `WeaponData` holds simulation numbers and drawing
details (model path, clip sets, view model recoil and sway) side by side.

**Why now.** Items 12 to 15 and 17 to 21 all key on "which item": slots,
prices, team restrictions, kill awards, icons, world models, draw times,
the grenades' and the Zeus's own numbers. `WeaponVData.classes()` already
has 43 classes, 9 of them equipment.

**The system.** An item registry keyed by CS2's class name
(`weapon_ak47`, `weapon_hegrenade`, `weapon_c4`, `item_kevlar`): each
entry's numbers from `vdata.csv`, its price, slot and team from the same
file or `cs2-systems.md`'s sources, its models, clips and sounds from the
extracted files' tables (`reference/weapons/models.md`, `sounds.md`,
`timings.csv`), and only what the game does not carry (spray patterns,
measured timings) written by hand. The simulation half and the drawing
half as two parts of the entry. The inventory holds `Weapon` instances by
slot, so ammo and recoil state survive a switch and a drop. **Size:**
medium. It replaces R1 in the weapons TODO.

### 6. How a player looks from outside lives inside `Bot`

Your view (`PlayerView`) plays your sounds, footsteps, impacts and view
model. A bot does the same for itself inside the simulation class: it
builds `WeaponSounds` and `Footsteps` (`bot.gd:117-131`), marks impacts and
plays the firing layer in `_on_shot_traced` (`bot.gd:364`), and lights its
model in `_process`. The ragdoll, which the simulation's own comment says
only draws, is built in `PlayerSim._fall` (`player_sim.gd:564`).

**Why now.** In multiplayer every other human is drawn exactly like a bot
is, so that drawing cannot live in `Bot`. Item 6a (your shadow with arms
and a gun) is the third-person body drawn once more, into the shadow maps.

The performance audit's second step, a server that builds nothing to be
seen (no meshes, materials, probe atlas, decals, sounds or HUD, where today
the map and every body build them all), is this finding from the other
side: it can only happen once drawing is out of the simulation classes. It
also counts three bodies and three animation trees on your own player (the
one with the hitboxes, the one you see, its shadow), 0.25 ms a frame.

**The system.** A third-person presenter that draws any `PlayerSim` from
outside (body, weapon layers, sounds, footsteps, impacts, ragdoll), and
the first-person view for the player being played. The simulation keeps
only what decides the game: the posed skeleton the hitboxes ride. On a
server nothing else is built; on a client other players' bodies are drawn
without hitboxes, and your seen body and shadow share one tree.
**Size:** medium; do it with finding 2.

### 7. Three ways of turning the hull into a surface

A hit on the world is named three ways:

- `Penetration.surface_for` (`penetration.gd:56`) resolves a hull part to
  CS2's surface through `SurfaceProperties`, including the hashed names
  Source 2 Viewer cannot spell and Godot's numbered duplicates.
- `Footsteps.set_for` (`footsteps.gd:122`) has its own table of hull names
  to footstep sets, and calls anything it does not know concrete.
- `BulletImpacts.surface_for` (`bullet_impacts.gd:120`) maps the footstep
  set to an impact set through a third table.

So the railings that penetration knows are `metalrailing` step and ring
as concrete, and per-surface friction (a Remote item in the roadmap) would
add a fourth lookup. Item 7c, surfaces per triangle, would have to be
taught to all of them.

The performance audit found a second cost of reading surfaces off node
names: cutting dust2's hull into cells made traces 1.2 times faster on Jolt
(1.5 on Godot Physics) and was left out, partly because parts of one
material then get Godot's numbered names, which footsteps and penetration
read.

**The system.** One lookup from a trace result to CS2's surface record,
with everything the game hangs off a surface: friction, the two
penetration numbers, the footstep and impact sound sets, the decal set.
`SurfaceProperties` is most of it already. The surface is resolved once, at
import, and stored on the shape (as metadata or a table by shape), so how
the hull is cut up no longer decides what it is made of. **Size:** small.
It also does the per-surface friction item, and makes the hull split and
item 7c's per-triangle surfaces possible.

### 8. The hitboxes are posed on the frame clock, not the tick

`PlayerSim.run_command` sets the body's animation parameters each tick
(`player_model.gd:258`), but the `AnimationTree` is created in code with
Godot's default process callback (`player_model.gd:240`), which advances
it on drawn frames, and the capsules follow on `skeleton_updated`
(`skinned_hitboxes.gd`). The pose a round meets on a given tick depends
on how many frames were drawn since the last one, and a server that draws
nothing would pose them on its idle loop. The performance audit found the
same and measured it: an animation step and the posing cost about 0.1 ms a
body, 80 us of it the tree, and the profiler already steps the trees in
manual mode.

**Why now.** Lag compensation (item 25) rewinds the hitboxes to where the
shooter saw them, which needs a record of each player's capsules per tick,
which needs them posed on the tick. It is also a fairness question today:
the top priority is hit registration that feels the same as CS2.

**The system.** Advance each simulated body's animation by hand inside the
tick (Godot's manual callback mode) and keep a short ring of each tick's
capsule end points, which the performance audit sizes at about 450 bytes a
player a tick, 29 KB a second at 64 Hz; a rewound round is tested against
those in script, ray against capsule, rather than by moving Jolt's areas
back and forth. The drawn bodies go on animating per frame. On your own
machine that is two animation trees for every bot, the one its hitboxes
ride stepped by the tick and the one you see stepped by the frame, as
Source keeps a server's copy of every player and a client's even in one
process: about 0.1 ms a bot a tick more, some 6% of a core for nine bots.
So it needs the presenter (finding 6) first, to have a drawn body apart
from the simulated one.

PR #46 moved this further in the same direction, on purpose: a bot's body
is now drawn between its last two ticks every frame
(`PlayerModel.show_between`, called from `Bot._process`), and since the
hitboxes ride its bones, "a round meets it where the shooter saw it". For
you shooting a bot on your own machine that is the right result, and it is
a lag compensation of a kind. But it is done by moving the simulation's
hitboxes to wherever the last drawn frame put them, so what a bot's round
meets, and what a server would decide, still depends on frames. The
history above gives the same result the server's way: the hitboxes stay
where the tick put them, and a shot is tested against the history at the
fraction between ticks the shooter was seeing, which the command carries
(CS2's `input_history`). `show_between` then only moves the drawn body.
Until then one side effect is worth knowing: a bot's round at another bot
meets it where it was last drawn, up to two ticks behind where it is
(about 7 units at a run), while the bot aims at where it is, so bots miss
moving bots a little more than they should, both sides alike.
**Size:** small to medium; it needs Sid's machine to check the drawn bodies
still look right.

### 9. No general simulated thing, and no saving or restoring state

`PlayerSim` is the only thing in the simulation. Its state is spread over
the node, the `Weapon` (a dozen private fields), `RecoilState`s and
`HitTarget`, and none of it can be copied out and put back.

**Why now.** A dropped gun, the bomb, a thrown grenade, a fire and a smoke
are each a simulated thing with an id, a tick and state. Client prediction
(item 25) runs the local player ahead and replays it when the server
disagrees, which means saving and restoring exactly that state. The sim
check "the same commands give the same game" compares positions by hand
for the same reason.

The performance audit adds the other half: a client re-runs the commands
the server has not answered yet (about four ticks at 60 ms and 64 Hz,
many times a second), and today `run_command` sounds each shot and leaves
its holes through signals, so a re-run would do it again.

**The system.** A small base for simulated things: an id the network can
use, a tick called by the `GameWorld`, spawn and remove through the world,
and `save_state()` and `load_state()`. Players, the weapons in their
inventories and every new entity follow it. Timers inside it as deadlines
in simulation microseconds, which save and restore as plain numbers
(today the code mixes those with `delta` countdowns and running sums).
Re-running is then: load the state, run the commands with events
switched off (finding 4's queue simply not handed out), compare. **Size:**
medium, done alongside finding 1.

### 10. CS2's settings are scattered constants, and debug keys are per map

CS2 names its tuning as convars, and the code cites them in comments
throughout: `mp_tagging_scale` and `sv_predictable_damage_tag_ticks` as
constants in `PlayerSim`, `weapon_recoil_decay_coefficient` in `Weapon`,
`mp_freezetime` and the rest in `MatchRules`, the bots' reaction and aim
error as constants in `Bot`. The developer keys are wired by hand where
they are used: F5 in `de_dust2.gd`, F3 in `GameHud`, V through
`UserCmd.toggle_noclip`, and twelve range keys in `test_range.gd`, ten
of them in `project.godot` but not in `scripts/setup_input_map.gd`, which
is meant to write it.

**Why now.** Settings (item 26) and a dedicated server's config (item 25)
both need named, typed values with defaults. The range's keys are
commands (give a weapon, set armour, toggle god mode) that dust2
playtests would use too.

**The system.** A convar registry with CS2's names, defaults and a note of
where each number came from, which `MatchRules` and the scattered
constants read; server convars that a client is sent, and client ones
(sensitivity, crosshair). A console on the tilde key for setting them and
for commands (`mp_warmup_end`, `mp_restartgame`, `noclip`, `give`,
`bot_kick`, `god`), with the range's keys becoming binds to those
commands. **Size:** medium. The registry can start small and grow. The
bind table and the range's commands came forward as roadmap item 12a
(`reference/binds.md`, 2026-09-24); the console then runs the same
commands.

### 11. Each map scene is also the game's setup

`de_dust2.gd` (374 lines) imports the map, lights it, builds the skybox,
places you, reads the nav mesh, places and routes the bots, starts the
match, builds the HUD and the impacts, and handles F5. The test range
(881 lines) builds its own player, bots, HUD and log. The bots' routes to
the bomb sites are dust2 code (`bot_route`).

**Why now.** A main menu that hosts or joins (item 26) starts a game on
a map; a second map, or dust2 without bots, would copy this again.

**The system.** The map provides what is on it (geometry, lighting,
spawns, buy zones, bomb sites, nav mesh, radar), and a game mode
(competitive, warmup practice, the range) sets up players, rules and HUD
on whatever map is loaded. A dedicated server is then a mode that loads
the map's collision, entities and nav mesh and nothing to be seen, which is
what the performance audit's second step asks for. **Size:** medium, more
urgent than it looked, since netcode needs it.

### 12. The data readers each carry their own parser and paths

KV3 is parsed in `NmGraph.parse_kv3` (`nm_graph.gd:97`) and skipped in
`SourceNavMesh._skip_kv3` (`source_nav_mesh.gd:697`); the next KV3 files
wanted are the nav mesh's analysis (N3) and the baked bomb damage (C2).
CSV is read four ways (`WeaponVData._load`, `WeaponSheet`,
`SurfaceProperties._load`, `RecoilPattern`). `res://assets/...` paths are
typed in six files, and each system reports a missing extraction in its
own way (console, warnings, a label, the map report).

**The system.** One KV3 reader, one table reader, one list of where each
extracted asset lives, and one report of what is missing and which
`extract_assets.sh` step fetches it. **Size:** small; do it when the next
KV3 file is needed.

### 13. The tests

Nine test files, each a `SceneTree` script with its own copy of `_check`,
`_check_equal`, `_check_near` and the report. `scripts/run_tests.sh` boots
Godot nine times, and because it runs under `set -euo pipefail` and each
file exits 1 on a failure, the first failing file stops the run and the
files after it never report. `SimClock` reads
`Engine.get_physics_frames()`, so a check that wants the tick to move has
to await the engine's physics frames rather than step a clock it controls.
There is no CI, with agents on two sides pushing to
main. *(The runner, the check base and CI are done: step 0. CI runs what
needs no extracted assets, 744 of the 951 checks; the other 207 run only
on Sid's machine. `SimClock` now reads the `GameWorld`'s count, and a
check can hold a world and step it: `tests/run_sim_checks.gd` runs a
second of it in one frame.)*

**The system.** A shared check base, one runner that runs every file and
reports them all, a simulation harness that builds a `GameWorld` with
players and steps it on a clock the test controls, and a GitHub Action
running the lot headless (the roadmap's housekeeping item). **Size:**
small to medium, and it protects every change above.

### 14. Smaller conventions

- Sides are the strings "T" and "CT" in 41 places; a typo is a silent
  bug. A `Team` enum or constants.
- Body heights as bare numbers: a bot aims at feet plus 48 and looks for
  eyes at plus 60 (`bot.gd:198, 350`), the body's centre is plus 36, the
  light plus 40. Named once, on the movement config or the model.
- `METRE := 39.37` in three sound files.

These are worth doing as the files are touched rather than on their own.

## The plan

Everything here is Remote. None of it changes how the game plays; each
step lands behind the existing checks and adds its own. Sid's local agents
change `player_sim.gd`, `bot.gd` and the models often, so the steps that
rewrite those files go one pull request at a time, starting from a freshly
pulled main.

The performance audit ends with eight next steps (`performance.md`, "Next,
in order"; its first, the tick rate, was settled by PR #46 and taken out).
All but one are the systems below seen from the cost side, so this plan
takes them in as they are; the one left, the probe light on the GPU, is
its own.

**Step 0, now: the test runner and CI** (finding 13). *(Done 2026-09-23:
`scripts/run_tests.sh`, `tests/check_suite.gd`,
`.github/workflows/tests.yml`.)* One runner that
reports every file, a shared check base, a GitHub Action. Protects every
step after it and every agent pushing to main. CI runs the checks that
need no extracted assets; the rest (dust2, the models, the sounds) run on
Sid's machine only, so a change to anything drawn, heard or on the map
still needs a run there.

**Step 1, first, inside or just before items 12 and 13:**
- The world that owns the tick, in a first form (finding 1). *(Done
  2026-09-23.)* Brought forward from step 3 by Sid: the events below are
  handed out at the end of its tick, and there was nothing else to hand
  them out.
- The item registry (finding 5), which is R1. *(Built 2026-09-23:
  `ItemRegistry`, every item by CS2 class name; `WeaponLibrary.build` for
  all 34 guns.)*
- `DamageInfo` with the attacker (finding 3). *(Built: `DamageInfo.deal`,
  `HitTarget.take_damage`, `Hitscan.fire_as`.)*
- Game events, queued per tick and handed out by the world at its end
  (finding 4), starting with the ones items 12 to 15 need: death, hurt,
  fire, impact, round start and end, pickup and drop. Shots' sounds and
  holes move onto them, which is half of performance step 4. *(Built:
  `GameEvents` with CS2's names and keys, handed out by `world.game.step`
  after the match.)*
The three are one contract, `reference/systems/contracts.md`, in
`src/game/`, with the inventory (item 12's carrying rules), items on the
ground, players' commands and the world's `game`, which the bomb,
grenades and buying are built on. Wired into `player_sim.gd` and
`bot.gd` with roadmap item 12: the shooter's id and the inventory in
place of the one weapon. Left (its section 5): the match's events in
`match_state.gd`.

**Step 2, any time, small: one surface lookup resolved at import**
(finding 7), which feeds CS2's per-surface friction into the movement and
frees the hull to be cut into cells for faster traces.

**Step 3, the rest of the simulation's owner, before the bomb (item 16),
grenades (17 to 20) and netcode:**
1. What is left of the world (finding 1): the world's other things as
   they arrive, and checks that build a map's world and step it on a
   clock they control.
2. The third-person presenter (finding 6; performance step 5), which item
   6a then uses. It comes before the hitboxes posed by the tick, which
   want a drawn body apart from the one they ride (finding 8).
3. Hitboxes posed by the tick and their history as capsule end points,
   tested in script (finding 8; performance steps 2 and 3). Sid checks the
   drawn bodies.
4. Bots as brains driving a `PlayerSim` (finding 2), with sight on a
   schedule or shared (performance step 7), which also fixes the two known
   bot problems.
5. The entity base with saved state (finding 9), so a command can be run
   again without its sounds and marks (performance step 4).

**Step 4, before menus and netcode: game modes apart from maps** (finding
11), including a server mode that builds nothing to be seen (performance
step 1), and **convars and the console** (finding 10). The convar registry
can start earlier, as each step above adds settings.

**Step 5, when the next KV3 file is read: the shared readers** (finding
12), with one body of each kind built while the map loads (performance
step 8) as part of the asset list.

**Conventions** (finding 14) as files are touched.

Left to the performance side, since they are not systems: the probe light
sampled on the GPU and its atlas packed (performance step 6).

Against the roadmap's current "what a thread can start now" list: step 0
and step 1 go first, then items 12 and 13 on top of them; 6a waits for
step 3's presenter; R1 is step 1; R2, R10 and R13 can go ahead at any time
and are easier after R1.

## How the two audits meet

The performance audit (`reference/performance.md`, main `5a700c1`) measured
what this one found by reading, and agrees with it in four places:

- **Hitboxes on the frame clock** (finding 8). It found the same thing,
  measured the fix at about 0.1 ms a body a tick, and designed the history
  (capsule end points in script, not moved physics areas). Adopted as is.
- **Drawing inside the simulation** (findings 6 and 11). Its "server that
  builds nothing to be seen" and "your three bodies on fewer trees" need
  the presenter split first.
- **A command run twice** (findings 4 and 9). Its step 4, prediction
  without repeated sounds and marks, is what per-tick events and saved
  state give.
- **Bots' sight** (finding 2). It grows as bots times enemies; a brain
  with senses on a schedule is where "look every few ticks, or share what
  one sees" goes.

It also found two things that sharpen findings here. Its profiler had to
run every node's callbacks in a loop of its own to time the tick by system
(finding 1; it now runs the world's tick in the world's own parts), and
its best trace speed-up was left out because footsteps and penetration
read surfaces from node names (finding 7).

Its first step, the tick rate, is settled: 64, as CS2 (PR #46). Nothing
in this plan changes with it. Everything a tick does is paid half as
often, though a tick at 64 does a little more than one at 128 did (it
moves everyone twice as far), so a second of play costs 32 to 42% less
rather than half.
