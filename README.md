# CSGODOT

**Counter-Strike 2, rebuilt from scratch in Godot 4.7.**

[![Tests](https://github.com/sidcarrollworks/CSGODOT/actions/workflows/tests.yml/badge.svg)](https://github.com/sidcarrollworks/CSGODOT/actions/workflows/tests.yml)
![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)
![64 tick](https://img.shields.io/badge/tick-64%20Hz-555)

The goal is simple to state: movement, shooting and hit registration that
feel the same as CS2's. Everything else is arranged so that "the same" is
something the tests can measure, not a matter of opinion.

It plays today as a single player competitive match against bots, or as
Practice with no bots and an unlimited warmup, on dust2 and other extracted
CS2 defusal maps.

---

## What's in it

| | |
|---|---|
| **Movement** | Source's movement ported line by line: acceleration, air strafing, collide-and-slide, step-up, crouch jumps, bunny hops. Crouch speed and accuracy stay steady while turning. A fixed 64 Hz tick with sub-tick input, so a click is traced from where you were aiming at that instant. Jumping and landing add a subtle camera and weapon dip. |
| **Shooting** | Every CS2 firearm is available, with the game's own weapon data. Spray patterns, tapping and burst-dependent accuracy recovery, wall penetration by surface and thickness, nineteen hitbox capsules per extracted player model, tagging and aim punch, scopes and shotgun pellets. The AUG and SG 553 raise their sights, keeping the lens clear while blurring the scene outside it; the lowered lens is black. The Nova, XM1014 and Sawed-Off reload one shell at a time, and firing interrupts the reload. |
| **Grenades** | All six, with delayed hand release, gradual throw strength and saved jump parameters. Flight uses the audited CS2 box hull and two physics steps per tick, with grenade clips retained from the map. Recorded CS2 lineup comparison and full effect parity remain open. |
| **Knife** | Left-click slashes and right-click stabs, with 48/32-unit forward reach, backstabs, armour and kill credit. Attacks work in the air, with first- and third-person clips and sounds. Damage and timing still await CS2 measurements. |
| **The match** | CS2's competitive rules: warmup, freeze time, rounds, side swap, overtime. Money and CS2's buy menu, the bomb (plant and defuse), and all six grenades, smoke included. Five a side, with bots filling every place but yours. |
| **Inventory** | Weapon slots, last-weapon switching and mouse-wheel cycling. Physical dropped items, walking pickups, and E to take ground items, swap the gun in a slot or take the bomb from a teammate bot. A prompt identifies the gun, grenade or bomb you can pick up. The buy menu marks owned and unavailable items, refunds purchases, and supports Ctrl-click to buy and throw. |
| **Bots** | The same simulation as you, driven by commands instead of keys. They buy, follow the loaded map's nav mesh to the bomb sites, jump and crouch along the route, make way for teammates, shoot with each gun's spread and recoil, and respect smokes and flashes. |
| **Map and players** | The map's baked lighting, sun shadows, light probes, reflections and colour grade. First-person arms and guns on CS2's clips, your body when looking down and its full shadow, feet fitted to the ground and hands to the gun, and ragdolls on death. Shots leave muzzle flashes, tracers, material-specific bullet impacts and short, dense blood mist at each bullet contact. Body hits leave bone-following wounds and play additive body/head flinches. |
| **HUD** | Health, armour and ammo, money, team cards and the round clock, weapon selection and use prompts, damage directions, a kill feed with assists and kill-type icons, and round win panels with the MVP and a fun fact. Round results have fixed foreground text and a slower-growing copy clipped behind it, on a translucent strip that fades at the sides. Dead players can spectate teammates. |
| **Sound** | Weapon shots, reloads, near-empty and dry-fire clicks, body/head/armour hit feedback for attackers, victims and onlookers, footsteps by surface, grenade and bomb sounds, flash ringing and muffling, the announcer, round countdowns and music cues. |

**Not yet:** Zeus attacks, burst-mode and silencer switching,
full grenade effects and CS2-matched grenade lineups, radar
and scoreboard, bots that play the objectives as a team, multiplayer, and
full main and settings menus.
[`reference/roadmap.md`](reference/roadmap.md) has everything left, in order.

## Getting started

Use [Godot 4.7](https://godotengine.org/); development and CI use **4.7.2**.
The pinned native libraries support **Windows and Linux x86-64**. Run the
commands below from the repository root. The `.sh` scripts need Bash; on
Windows, use Git Bash for extraction and tests.

### Install the physics addon

The game's physics is **Box3D v0.4.3**, a separate GDExtension world. Its
binaries are not committed. Install the pinned addon before opening the
project or running the tests. On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_box3d.ps1
```

On Linux:

```bash
scripts/install_box3d.sh
```

The installer builds **debug and release** libraries from pinned source with
our projectile-query patch. It requires Git, Python 3 and a C/C++ compiler
(Visual Studio C++ Build Tools on Windows; GCC/Clang on Linux). The first
build takes several minutes; later runs use the ignored `.godot/` cache.
The addon archive supplies checksum-verified resources; its unpatched
binaries are not installed. Restart Godot after installation.
[The grenade port](reference/research/grenade-port-2026-10-02.md) explains
the patch and its separate projectile tolerance.

### Play

Open the project in Godot, then choose a scene:

- **The test maps need no CS2 extraction.** Open
  `maps/test_movement/test_movement.tscn` or `maps/test_range/test_range.tscn`
  and press F6 to run the current scene. Extracted assets add CS2's models,
  animations and sounds.
- **dust2 needs CS2's files.** The map, models, animations and sounds are
  Valve's, so they are never in this repository. With CS2 installed and
  [Source2Viewer-CLI](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
  on your machine, extract them into the gitignored `assets/` folder:

  ```sh
  scripts/extract_assets.sh all
  ```

  Then press play: `maps/de_dust2/de_dust2.tscn` is the main scene. It
  asks for the mode first: Competitive (5 v 5 with bots) or Practice (no
  bots, and warmup lasts until F5 starts the rounds). `--mode competitive`
  or `--mode practice` on the command line skips the question.
  [`reference/extracting.md`](reference/extracting.md) covers each step,
  where the script looks for things, and what to do when an import
  misbehaves. Set `S2V`, `CS2_PATH` or `GODOT` in Bash if the viewer, game
  installation or Godot binary is not found automatically.

  To update an existing extraction with the new hit effects and flinches,
  run `scripts/extract_assets.sh impacts`, `character-animations` and
  `sounds`. `all` includes these steps. The impact stage checks fresh
  texture data before cached images can conceal a missing asset.

- **Any other defusal map:** extract it by name and play it.

  ```sh
  scripts/extract_assets.sh map de_mirage
  godot --path . maps/play/play.tscn -- --map de_mirage
  ```

### Optional native movement

The movement step also has a C++ implementation. Building it speeds up
movement; without it, the game uses the GDScript reference. It needs git,
Python 3 and a C++ compiler (Visual Studio's C++ tools on Windows).

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_native.ps1
```

On Linux, or in Git Bash on Windows:

```bash
scripts/build_native.sh
```

Restart Godot after building. Rebuild after changes under `native/` or to
the movement scripts it copies. A library built from different sources is
refused, with a warning, and the script runs instead. To use the script
explicitly, pass `--movement script` after `--` when launching Godot.
[`native/README.md`](native/README.md) lists the source files and build
options.

## Controls

CS2's default keys, everywhere, including the test maps.

| Key | Action | Key | Action |
|---|---|---|---|
| `W` `A` `S` `D` | Move | `1` to `5` | Primary, pistol, knife, grenades, bomb |
| `Space`, scroll up | Jump | `Q` | Last thing held |
| `Ctrl` | Crouch | `G` | Drop |
| `Shift` | Walk | `E` | Defuse, pick up ground items/swap a gun, take the bomb from a teammate bot |
| `Mouse 1` | Fire, knife slash, throw overhand, or plant with C4 held | `B` | Buy menu, in your buy zone |
| `Mouse 2` | Scope, knife stab, or throw a grenade underhand (both buttons: between) | `R` | Reload |
| Scroll down | Cycle inventory | `Ctrl` + click in the buy menu | Buy and throw |
| `V` | Noclip | `F5` | End warmup |
| `Esc` | Toggle mouse capture | `F3` | Hide the position and frame-rate readout |

When you are dead, `Mouse 1` watches the next teammate and `Space` moves the
camera between their eyes and behind them. Planting automatically crouches
you for the duration of the plant. The test range adds its own keys
on keys CS2 leaves free; they are listed in
[`reference/test-maps.md`](reference/test-maps.md), and every bind with its
plan in [`reference/binds.md`](reference/binds.md).

## The test maps

Movement and shooting are tuned in flat grey rooms first, because tuning
them on a real map is much harder and everything built on bad movement is
wasted work.

- **The movement course** is all measurement: a strafe lane marked every 128
  units, stairs and step heights, ramps either side of the walkable angle,
  a surf lane, and jump gauges.
- **The test range** has a wall ruled in degrees to spray at, a dummy that
  logs every round's damage by hitbox and distance, walls of CS2's surfaces
  to shoot through, a bot that shoots back, grenades and the bomb.

[`reference/test-maps.md`](reference/test-maps.md) describes both in full.

## How it is built

Four decisions shape the whole codebase:

1. **Source units, not metres.** One Godot unit is one inch, so every CS
   constant is used as the game has it: a player is 72 units tall, gravity
   is 800, running speed is 250. If a number looks enormous, this is why.
2. **A fixed 64 Hz tick, as CS2's.** What is drawn is interpolated between
   ticks, and input carries its time within the tick.
3. **Built as a server runs it.** Every player, you and the bots alike, is a
   simulation stepped one tick at a time by a CS2-shaped user command.
   `GameWorld` gathers everyone's command first, with bots thinking on up
   to four worker threads, then runs the players in order, the match and the
   shared systems. Events, damage records and inventories connect the
   systems; what you see and hear only reads them.
4. **CS2's own numbers win.** Weapon values come from the game's
   `weapons.vdata`, dumped to [`reference/weapons/vdata.csv`](reference/weapons/vdata.csv);
   anything measured by hand goes in `reference/` with how it was measured.

Box3D owns the shared collision world: the map, player hulls and hitboxes,
dropped items and ragdolls. The bridge converts inches to metres at its
boundary; Source movement and grenade flight remain game rules. Godot's
Jolt physics is used for standalone fixtures and the comparison mode,
selected with `--physics legacy` after `--`; that mode has no ragdolls.
The [grenade collision audit](reference/research/collision-foundation-2026-10-02.md)
documents the small-hull differences and the corrected travel budget for
repeated bounces in one step. The [grenade port](reference/research/grenade-port-2026-10-02.md)
adds a dedicated projectile trace, CS2 box flight, release/jump timing and
activation rules. Local CS2 lineup comparison remains open.

The GDScript movement step is the reference for the native implementation.
Tests compare their results bit for bit. Hitbox proxies update when needed,
ragdolls are prepared before death, and animation and skeleton fitting
avoid repeating work for bodies nobody sees. These are measured in
[`reference/performance.md`](reference/performance.md); the 6 ms maximum
frame-time target remains open.

This is the foundation for multiplayer, which still needs networking,
prediction, authoritative hitbox poses stepped by the tick, and a pose
history for lag compensation. The local game's hitboxes currently follow
the animated bodies drawn between ticks.

[`reference/how-it-works.md`](reference/how-it-works.md) explains each
system in depth, with the files that hold it.

## Tests

```sh
scripts/run_tests.sh              # every test file
scripts/run_tests.sh sim match    # only files whose names contain these
```

Run these in Bash (Git Bash on Windows), with Box3D installed. The runner
imports the project first. It finds Godot on `PATH` or in common Windows
download locations; set `GODOT=/path/to/godot` if it is elsewhere.

Each system has a headless check file in `tests/` (`run_*.gd`). Every file
runs even if another fails, and script errors, crashes and timeouts fail the
run. The default per-file limit is 180 seconds when coreutils' `timeout` is
available; `CSGODOT_TEST_TIMEOUT` changes it. Explicitly known-open checks
are reported separately and do not fail the run.

The same suite runs on GitHub for every pull request and push to `main`.
CI installs Box3D and builds the native movement library. Wherever that
library is built, the suite holds its movement steps to the script's
results bit for bit. In-tick rays that can meet hitboxes are also checked
against the capsules themselves. Checks that need extracted assets skip
when they are missing; drawing checks skip headless. Run the suite with the
assets locally for map, model and sound changes.

## Project layout

| Folder | What is in it |
|---|---|
| `src/sim/` | The tick: user commands, simulation time, the `GameWorld` |
| `src/movement/` | Player hulls and the reference acceleration and collide-and-slide movement |
| `src/physics/` | The shared Box3D world, query bridge and unit conversion |
| `src/player/` | The player's simulation, input, first-person view and character models |
| `src/weapons/`, `src/combat/` | Guns, recoil, hitscan, hitboxes, penetration, ragdolls |
| `src/match/`, `src/modes/` | Match rules and round flow; competitive mode on any map |
| `src/economy/`, `src/bomb/`, `src/grenades/` | Money and buying, the C4, every grenade |
| `src/game/` | What the systems share: events, inventory, dropped items |
| `src/bots/` | Bots and how they buy |
| `src/map/` | Map import, lighting, nav mesh, buy zones and bomb sites |
| `src/audio/`, `src/effects/`, `src/ui/` | Sound, muzzle flashes, tracers and hit effects, the HUD |
| `native/` | The C++ movement step and its build configuration |
| `addons/` | GDExtension addons; installed and built binaries are gitignored |
| `maps/` | dust2, the any-map play scene, and the two test maps |
| `tests/` | The headless test suite |
| `scripts/` | Extraction, test runner, profilers |
| `reference/` | Measurements, research and plans (committed) |
| `assets/` | Extracted CS2 content (gitignored, never committed) |

## Documentation

| Page | Read it for |
|---|---|
| [`reference/how-it-works.md`](reference/how-it-works.md) | How each system works, in depth |
| [`reference/roadmap.md`](reference/roadmap.md) | What is done and what is next |
| [`reference/cs2-systems.md`](reference/cs2-systems.md) | CS2's rules and numbers for each system |
| [`reference/weapons/`](reference/weapons/) | Every gun: the game's data, what is left to build |
| [`reference/systems/`](reference/systems/) | How the round's systems talk to each other |
| [`reference/research/`](reference/research/) | Research into how CS2 does things, before building them |
| [`reference/rendering.md`](reference/rendering.md), [`reference/performance.md`](reference/performance.md) | What a frame and a tick cost, and how to measure them |
| [`reference/godot/`](reference/godot/) | The Godot 4.7 APIs this project uses, and their pitfalls |
| [`reference/box3d-trial.md`](reference/box3d-trial.md), [`native/README.md`](native/README.md) | Physics setup and comparison, and building the native movement code |
| [`reference/test-maps.md`](reference/test-maps.md), [`reference/binds.md`](reference/binds.md) | The test maps and their controls |
| [`reference/extracting.md`](reference/extracting.md), [`reference/asset-pipeline.md`](reference/asset-pipeline.md) | Getting CS2's content in |

## Contributing

Work reaches `main` through pull requests only, with the tests green.
[`CLAUDE.md`](CLAUDE.md) holds the rules every change keeps to. CS2's
content is Valve's and stays out of the repository.
