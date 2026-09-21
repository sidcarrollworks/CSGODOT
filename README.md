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
- Coordinates out of the map's entity data (spawn points, bomb sites) need no
  unit conversion, only the turn from Z-up to Y-up (`SourceEntities.to_game`).

Source 2 Viewer exports glTF in metres, so the map importer scales dust2 up by
exactly 1/0.0254 on the way in. That is the one place a scale conversion
happens.

It means Godot's default gravity is turned off in project settings and the
camera near plane is set to one unit. If a number here looks enormous,
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
| `Scroll up` | jump, for bunny hopping |
| `V` | noclip |
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
- **Jump gauges** at 32, 48, 56, 64 and 72 units. The grey ones are reachable
  standing; the blue ones need a crouch jump.

## dust2

The map is not in this repository and never will be. It is Valve's geometry,
extracted from your own CS2 install into `assets/`, which is gitignored.

On a machine with CS2 installed, and with
[Source2Viewer-CLI](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
somewhere it can be found:

```sh
scripts/extract_assets.sh list-map     # see what is inside the dust2 VPK
scripts/extract_assets.sh map          # extract it, then import it into Godot
scripts/extract_assets.sh weapons      # the AK-47 and M4A1-S models
```

`map` takes a couple of minutes and a little over a gigabyte. It pulls three
things out of the VPK: the visible world as glTF with its textures, the
collision hull as a second glTF, and the entity lump as text. `physics` and
`entities` fetch the last two on their own, in seconds.

The script finds everything itself: Source2Viewer-CLI on `PATH` or where the
release zip unpacks to in Downloads, CS2 by way of Steam's library list (so a
second drive is fine), Godot on `PATH` or the desktop, and the resources
inside the VPKs by listing them rather than hardcoding paths, which drift
between game updates. Override with `S2V=`, `CS2_PATH=` and `GODOT=` if it
guesses wrong.

Then open `maps/de_dust2/de_dust2.tscn` and press play. You start at one of
the map's own T spawn points (`spawn_team` on the scene root switches sides),
under the map's own sun, colliding with the hull the game itself collides
with, player clips included. None of the visible world is solid.

To see what came through without opening the editor:

```sh
scripts/inspect_assets.sh
```

That prints the file layout and then the import inventory: mesh counts, the
bounding box, where collision came from, the spawn points and every distinct
material name. It is the output to send over when an import is misbehaving.

Extracted textures are imported VRAM-compressed with mipmaps, which Godot
does not do by itself for textures it only ever meets headless:
`scripts/write_import_settings.gd` sets that up before each import. It is the
difference between 1 GB of video memory and 4.

## Tests

```sh
scripts/run_tests.sh
```

Note that GDScript's analyser warnings (shadowed variables, unused locals) only
appear when the editor loads a script. They do not show up in a headless run,
so if the Godot console shows any, paste them over and they will get fixed.

Thirty-five movement checks. Half are the acceleration model against hand-computed
values, which is the part that decides feel and the part most likely to be
broken by a well-meaning edit. The rest drive the real body through the real
course: a standing jump, a crouch jump, a slide down the surf ramp, and a walk
up the access ramp. Those catch the things that are right in the maths and
wrong in the world, which is where the bugs have actually been.

The run prints the measured heights and speeds even when it passes, because
watching those numbers move is how you notice a change the assertions were not
tight enough to catch.

Then the map importer, against fixtures Godot generates for itself, one of
them shaped like a real Source 2 Viewer export: metres, a sun, a separate
hull. And last, where dust2 has been extracted, the real thing: a player is
dropped at every one of the map's thirty spawn points and has to land on the
floor just below. Scale, axis conversion, the hull and the entity coordinates
are four separate things, and that only passes when all four agree.

## Layout

```
src/movement/    the acceleration model and collide-and-slide
src/player/      input (timestamped), camera, the local player
src/map/         glTF map import, and the map's entity data (spawn points)
src/ui/          the tuning readout
maps/            generated test courses, and the dust2 scene
tests/           headless test suite
reference/       measured constants and how they were measured
scripts/         tooling (asset extraction and inspection, test runner)
assets/          extracted CS2 content. GITIGNORED. Never commit Valve assets.
```

`reference/` is in version control and `assets/` is not, on purpose. The
reference data is our own measurements and stays valid; the extracted content
is disposable and regenerable, and keeping it out of git means swapping to
original assets later is a content change rather than a git history problem.

## What is deliberately not here yet

No weapons, no bots, no nav mesh. dust2 is in as geometry, collision and spawn
points and nothing more. Movement is still tuned on the grey test course,
because tuning it on a real map is much harder and everything built on top of
bad movement is wasted work.
