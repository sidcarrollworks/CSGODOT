# CSGODOT

**Counter-Strike 2, rebuilt from scratch in Godot 4.7.**

[![Tests](https://github.com/sidcarrollworks/CSGODOT/actions/workflows/tests.yml/badge.svg)](https://github.com/sidcarrollworks/CSGODOT/actions/workflows/tests.yml)
![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)
![64 tick](https://img.shields.io/badge/tick-64%20Hz-555)

The goal is simple to state: movement, shooting and hit registration that
feel the same as CS2's. Everything else is arranged so that "the same" is
something the tests can measure, not a matter of opinion.

It plays today as a single player competitive match against bots on dust2,
or on any other CS2 defusal map you extract.

---

## What's in it

| | |
|---|---|
| **Movement** | Source's movement ported line by line: acceleration, air strafing, collide-and-slide, step-up, crouch jumps, bunny hops. A fixed 64 Hz tick with sub-tick input, so a click is traced from where you were aiming at that instant. |
| **Shooting** | Every CS2 gun, with the game's own numbers read from its weapon data. Spray patterns, tapping and recoil recovery, wall penetration by surface and thickness, CS2's nineteen hitbox capsules on every body, tagging and aim punch when hit, scopes and shotgun pellets. |
| **The match** | CS2's competitive rules: warmup, freeze time, rounds, side swap, overtime. Money and CS2's buy menu, the bomb (plant and defuse), and all six grenades, smoke included. Five a side, with bots filling every place but yours. |
| **Bots** | The same simulation as you, driven by commands instead of keys. They buy, walk dust2's own nav mesh to the bomb sites, shoot back with each gun's real spread and recoil, and respect smokes and flashes. |
| **Look and sound** | The map's own baked lighting, light probes and sun. Your arms and gun in first person on CS2's animation clips, and your own body and shadow. A HUD in today's CS2 layout. The game's own sounds, with footsteps by surface. |

**Not yet:** the knife and Zeus as weapons, the kill feed, radar and
scoreboard, bots that play the round as a team, multiplayer, and menus.
[`reference/roadmap.md`](reference/roadmap.md) has everything left, in order.

## Getting started

You need [Godot 4.7](https://godotengine.org/). Open the project and press
play.

- **The test maps work straight away.** Open
  `maps/test_movement/test_movement.tscn` or `maps/test_range/test_range.tscn`.
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
  misbehaves.

- **Any other defusal map:** extract it by name and play it.

  ```sh
  scripts/extract_assets.sh map de_mirage
  godot --path . maps/play/play.tscn -- --map de_mirage
  ```

## Controls

CS2's default keys, everywhere, including the test maps.

| Key | Action | Key | Action |
|---|---|---|---|
| `W` `A` `S` `D` | Move | `1` to `5` | Primary, pistol, knife, grenades, bomb |
| `Space`, scroll up | Jump | `Q` | Last thing held |
| `Ctrl` | Crouch | `G` | Drop |
| `Shift` | Walk | `E` | Use (defuse) |
| `Mouse 1` | Fire, or throw a grenade overhand | `B` | Buy menu, in your buy zone |
| `Mouse 2` | Scope in, or throw a grenade underhand (both buttons: between) | `R` | Reload |
| `V` | Noclip | `F5` | End warmup |
| `Esc` | Release the mouse | `F3` | Hide the position and frame-rate readout |

When you are dead, `Mouse 1` watches the next teammate and `Space` moves the
camera between their eyes and behind them. The test range adds its own keys
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
   simulation stepped one tick at a time by a CS2-shaped user command. One
   `GameWorld` runs the tick; what you see and hear only reads it. That is
   what keeps multiplayer from being a rewrite.
4. **CS2's own numbers win.** Weapon values come from the game's
   `weapons.vdata`, dumped to [`reference/weapons/vdata.csv`](reference/weapons/vdata.csv);
   anything measured by hand goes in `reference/` with how it was measured.

[`reference/how-it-works.md`](reference/how-it-works.md) explains each
system in depth, with the files that hold it.

## Tests

```sh
scripts/run_tests.sh              # every test file
scripts/run_tests.sh sim match    # only files whose names contain these
```

Each system has a headless check file in `tests/` (`run_*.gd`). The same run
happens on GitHub for every pull request and every push to `main`; checks
that need the extracted assets skip themselves there and run on a machine
that has them.

## Project layout

| Folder | What is in it |
|---|---|
| `src/sim/` | The tick: user commands, simulation time, the `GameWorld` |
| `src/movement/` | The acceleration model and collide-and-slide |
| `src/player/` | The player's simulation, input, first-person view and character models |
| `src/weapons/`, `src/combat/` | Guns, recoil, hitscan, hitboxes, penetration, ragdolls |
| `src/match/`, `src/modes/` | Match rules and round flow; competitive mode on any map |
| `src/economy/`, `src/bomb/`, `src/grenades/` | Money and buying, the C4, every grenade |
| `src/game/` | What the systems share: events, inventory, dropped items |
| `src/bots/` | Bots and how they buy |
| `src/map/` | Map import, lighting, nav mesh, buy zones and bomb sites |
| `src/audio/`, `src/effects/`, `src/ui/` | Sound, muzzle flashes and tracers, the HUD |
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
| [`reference/extracting.md`](reference/extracting.md), [`reference/asset-pipeline.md`](reference/asset-pipeline.md) | Getting CS2's content in |

## Contributing

Work reaches `main` through pull requests only, with the tests green.
[`CLAUDE.md`](CLAUDE.md) holds the rules every change keeps to. CS2's
content is Valve's and stays out of the repository.
