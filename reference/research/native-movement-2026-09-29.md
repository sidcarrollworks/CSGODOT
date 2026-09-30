# The movement's step in native code (2026-09-29)

Sid asked for it on 2026-09-28 ("the movement into native code") and on
2026-09-29 allowed the two downloads it needs, SCons and godot-cpp's source.
Nothing had been researched for it: `reference/godot/engine.md` had what
the Godot docs say of GDExtension, and
[box3d-walking-hitch-2026-09-28.md](box3d-walking-hitch-2026-09-28.md) had
what a walking bot's tick is made of. This page is what was built, how it
is held to the script, what it is worth, and what is left.

Measured on Sid's machine (Windows 11, Godot 4.7.2's editor binary,
headless), the library built `template_debug` with Visual Studio 2022,
which is the one the editor binary loads and is optimized (`/O2`). Both
build scripts were run there: `build_native.sh` under Git Bash, and
`build_native.ps1` under Windows PowerShell 5.1 and PowerShell 7.

## What a walking bot's tick was made of

Five bots walking dust2's site routes for 30 seconds, by the script
(`scripts/profile_player_tick.gd -- 5 30 --movement script`), microseconds
a bot a tick:

| | calls | inclusive | its own |
|---|---|---|---|
| `run_command` | 1.00 | 145.5 | 21.7 |
| `simulate` | 1.00 | 106.7 | 27.1 |
| `_simulate_step` | 1.00 | 74.7 | 5.8 |
| `_trace`, each | 1.62 | 31.5 | 8.9 |
| `_cast_hull` (the bridge and Box3D's cast) | 2.40 | 36.7 | 36.7 |

So 75 us of a bot's 145 were the step, and of the step Box3D's own casts
were about a third (2.4 of them, 10 us each through the binding). The rest
was script: the branches of the move, the vector arithmetic, a dictionary
for every sweep's answer.

## What was built

`native/src/hull_mover.cpp` (class `HullMover`) is
`PlayerBody._simulate_step` and everything under it, in the same order:
the duck, the jump, the walk and the air move, the step up and down, the
slide along what is met, staying on the ground, the ground check, the
trace with its recovery from a start inside something, and the solver's
friction and acceleration (`MovementSolver`). Under them the hull's sweep
as the bridge answers it for an upright box (`Box3DQueries.shape_cast_prepared`,
`_native_cast`, `_mapped`): the back-off, the clearance along the hit's
normal, the reach past the end, the inset.

It asks Box3D for its sweeps through the binding's own method, by name
(`world.call("shape_cast_box", ...)`), so the library is built against
Godot's API alone. It reads the body's state and config by property name,
runs the step on its own copy, and writes the state back, the body's place
once. Two things it asks the script for: the hull resized when a duck
changes its height, and the four rays under the hull's corners.

The script stays, and is the reference. `PlayerBody._native_mover` hands
the step to the native code only where its assumptions hold: the library
built, the game on Box3D, the hull a box, the collision shape exactly half
the hull's height over the feet and unturned, nothing above the body moved
or turned, the box's size the config's. Anywhere else the script runs it,
and `--movement script` (or the setting `csgodot/simulation/movement`) has
the script run every step.

`native/README.md` has how to build it and the rules for writing it.

## Held to the script, to the last bit

A GDScript float is a double and a vector's parts are single floats, so
the script's arithmetic widens and narrows at every step. The C++ does so
at the same steps, is compiled with `/fp:precise` (`-ffp-contract=off`
elsewhere) so that no multiply and add are fused, and takes the one cosine
it needs from the script, since two C runtimes may differ in a cosine's
last bit.

With `PlayerBody.check_steps` on, which `tests/check_suite.gd` turns on for
every check file, each native step is first run by the script from the same
start, the start put back, the native step run, and the two compared in
every part of the body's state, exactly: its place, its velocity, the
ground, the duck, the floor's normal, the recovery, the traces counted and
the queries made. One difference fails the file, with the step's start.

The whole suite on Sid's machine, with the extracted assets (4,496 checks
in 61 files, all passed, on this branch with perf/death-on-the-tick merged
into it):

| Where | Steps compared | Differing |
|---|---|---|
| `run_dust2_think_checks` (dust2's match, twice) | 56,254 | 0 |
| `run_native_movement_checks` (the course) | 49,029 | 0 |
| `run_dust2_bot_checks` | 19,205 | 0 |
| `run_box3d_match_checks` | 8,202 | 0 |
| `run_bot_think_checks` | 7,232 | 0 |
| `run_bot_move_checks` | 6,023 | 0 |
| `run_dust2_checks` | 5,120 | 0 |
| `run_range_checks` | 4,950 | 0 |
| `run_sim_checks` | 3,454 | 0 |
| fourteen more files | 12,213 | 0 |
| all | 171,682 | 0 |

The course (`tests/run_native_movement_checks.gd`) is there for what a
match seldom does. Two bodies walk by seeded chance for 24,000 ticks over
stairs, ramps of 30 and 60 degrees, a ceiling too low to stand under, a
ledge and a third body standing; they jump part-way through a tick, duck
and stand, are put inside the floor and inside each other, and twelve of
the movement's settings are changed under them. It also checks that a
difference is found (a body whose script step drifts), and that what the
native code cannot run is left to the script.

Not held: any platform but Windows x86-64 until CI has run it on Linux
(below).

## What it is worth

A walking bot's tick, the same walk by each
(`scripts/profile_player_tick.gd -- 5 30`, with `--movement script` and
without), two runs of each, alternated:

| Microseconds a bot a tick | By the script | By the native code |
|---|---|---|
| `simulate` | 101.6 to 106.7 | 66.8 to 69.5 |
| `run_command` | 138.7 to 145.5 | 103.2 to 106.8 |

dust2's seeded Competitive match (nine bots and a player, 3,099 ticks,
the match of `scripts/profile_worst_ticks.gd` timed tick by tick with
nothing put into the code), two plays a process, four processes alternated
script, native, script, native:

| A tick, us | Script 1 | Native 1 | Script 2 | Native 2 |
|---|---|---|---|---|
| mean, first play | 1955 | 1678 | 1948 | 1560 |
| mean, second play | 1894 | 1694 | 1792 | 1549 |
| 95th, first play | 2818 | 2353 | 2725 | 2069 |
| 95th, second play | 2630 | 2382 | 2486 | 2142 |

About 35 us a walking bot a tick, a third of its movement, and 0.2 to 0.3
ms of a ten-player tick of 1.8 to 1.95. The worst ticks are not the
movement's (deaths, rounds fired) and are as they were.

It is less than the step's share of the script suggested, for two reasons.
The casts are Box3D's and cost what they cost, 10 us each. And 27 us of
`simulate` is not the step: the bridge's scope begun and ended, the other
hulls synchronized, the body's own proxy moved after.

## What is left

In order of what it would give:

1. **The bridge's work around the step, 27 us a bot a tick**
   (`Box3DQueries.begin_scope`, `sync_dynamic`, `sync_object`), which is
   script over dictionaries. It could move into the same library, held to
   the script the same way.
2. **`run_command`'s own 21 us**, the body's animation parameters set by
   name every tick.
3. **The casts through `Object::call`**, a Variant call and a Dictionary
   for every answer. Bound against Box3D's own headers a sweep would be a
   plain call; it would tie the library's build to Box3D's.

## What the review found

Three reviewers read the change (the port against the script, how the
script uses it, the build), and each finding was then argued against by
another. The port itself stood: no place was found where the C++ does not
do what the script does. Six findings around it were confirmed, and are
fixed in the same pull request:

| Found | Fixed by |
|---|---|
| A library built from an older script ran in the game, and nothing said so: `addons/csgodot_native/` is not committed and stays through a pull | The library carries a stamp of its sources and of the scripts it copies; the game works the same out as it starts and runs the script where they differ, with a warning |
| A library that was built and did not load left every check passing with nothing compared | The build scripts end by asking Godot whether it loads; the checks fail on a library that is installed and does not run |
| `build_native.ps1` ended at its first probe under Windows PowerShell 5.1, which makes an error of what a program writes to stderr | Programs are run with errors continuing and judged by their exit codes; run under 5.1 and 7 |
| The profiles built on the checks (`profile_box3d_match.gd`, `profile_box3d_costs.gd`) ran every step both ways and timed it | They turn the comparisons off, and say which movement they timed |
| A bot with its own of the step's functions (`profile_player_tick.gd`, `profile_hull_traces.gd`) had them go unrun, and the trace profile counted every stop as a hitch | A body whose script has its own of them is the script's to step; so is any body while the bridge has a script of its own |
| The shell script built for macOS and arm64, which the `.gdextension` does not list | It builds what is listed, and says so of anything else |

Left as found: CI's cache keeps the virtual environment SCons is in, which
a new runner image's Python would not run. The script now makes it again
when it no longer runs SCons.

## Code fixes and Local checks

- **CI's build has not run.** The step added to
  `.github/workflows/tests.yml` builds the library on Linux with GCC, and
  every check file then compares the two there. It passing is the first
  proof off Windows. If a step differs there, the step is the script's
  until it is understood: the `.gdextension` lists the platforms the
  native code is trusted on.
- **arm64 is not listed.** A compiler for arm64 may fuse a multiply and an
  add in the engine's own vector arithmetic, which this library's build
  does not. List it after the checks have passed on it.
- **Local: play with it.** Build it in the main checkout
  (`scripts/build_native.ps1`), restart Godot, and play a Competitive
  match: the HUD's frame meter against a run with `--movement script`.
- **Build it again after a pull** that changed `native/` or a script it
  copies. Until then the game says the library is from other sources and
  runs the script, which is the slower of the two and never the wrong one.
