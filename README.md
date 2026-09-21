# CSGODOT

A Counter-Strike 2 style shooter in Godot 4. Single player against bots,
dust2, two weapons to start with (AK-47 and M4A1-S).

The whole point of the project is that movement, shooting and hit registration
feel like CS2. Everything here is arranged around making that measurable rather
than a matter of opinion.

## The one surprising thing: scale

**This project works in Source units, not metres. 1 Godot unit = 1 Source unit
= 1 inch = 0.0254 m.**

A standing player is 72 units tall, gravity is 800 u/s², running speed is
250 u/s. This is deliberate:

- Every CS constant is used verbatim, with no conversion step to get wrong.
- dust2 exported from Source 2 Viewer drops in at 1:1 with no scaling.

It means Godot's default gravity is turned off in project settings and the
camera near plane is set well inside one unit. If a number here looks enormous,
that is why.

## Running it

Open the project in Godot 4.7 and press play. The main scene is the movement
test course.

| Key | |
|---|---|
| `WASD` | move |
| `Space` | jump |
| `Ctrl` | duck |
| `Shift` | walk |
| `Esc` | release the mouse |

The readout in the top left is the tuning instrument: current speed, vertical
speed, peak speed, and speed gained over the last jump. Speed gained per jump
is the number that tells you whether air acceleration is right.

## The test course

Everything on it is a measurement, not decoration:

- **Strafe lane**, markers every 128 units, brighter every 512. How far a
  strafe jump actually carried you.
- **Stairs**, eight 16-unit steps you should walk up without jumping, ending in
  a 24-unit lip you should not (step height is 18).
- **Ramps** at 20°, 35°, 44° and 50°. The 44° one is walkable and the 50° one
  is not, which is the threshold that makes surfing possible.
- **Surf lane**, two opposing 55° ramps with a drop-in platform. If
  collide-and-slide is right you ride these and gain speed. If it is wrong you
  stick or stutter. This is the clearest single test of the port.
- **Jump gauges** at 32, 48, 56 and 64 units. A standing jump clears 56 and
  not 64.

## Tests

```sh
GODOT=/path/to/godot scripts/run_tests.sh
```

Thirty checks covering the acceleration model against hand-computed values,
plus a real jump driven through the actual body to pin jump height. The
acceleration model is the part that decides feel and the part most likely to be
broken by a well-meaning edit, so it is worth having pinned down.

## Layout

```
src/movement/    the acceleration model and collide-and-slide
src/player/      input (timestamped), camera, the local player
src/ui/          the tuning readout
maps/            generated test courses; dust2 goes here later
tests/           headless test suite
reference/       measured constants and how they were measured
scripts/         tooling (test runner, input map generator)
assets/          extracted CS2 content. GITIGNORED. Never commit Valve assets.
```

`reference/` is in version control and `assets/` is not, on purpose. The
reference data is our own measurements and stays valid; the extracted content
is disposable and regenerable, and keeping it out of git means swapping to
original assets later is a content change rather than a git history problem.

## What is deliberately not here yet

No dust2, no weapons, no bots. Movement is tuned in a flat grey room first,
because tuning it on a real map is much harder and everything built on top of
bad movement is wasted work.
