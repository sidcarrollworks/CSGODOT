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
test course. The other one worth opening is `maps/test_range/test_range.tscn`,
which is where shooting gets tuned.

| Key | |
|---|---|
| `WASD` | move |
| `Space` | jump |
| `Ctrl` | duck |
| `Shift` | walk |
| `Scroll up` | jump, for bunny hopping |
| `V` | noclip |
| `Esc` | release the mouse |
| `Mouse 1` | fire |
| `R` | reload |
| `1` / `2` | AK-47 / M4A1-S |

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

## The test range

`maps/test_range/test_range.tscn`. A flat wall 512 units away to spray at, and
a dummy at 1024 units with head, chest, stomach and leg hitboxes to check
damage against.

| Key | |
|---|---|
| `1` / `2` | AK-47 / M4A1-S |
| `R` | reload |
| `P` | export the spray you just fired |
| `O` | clear the impact markers |

Every bullet leaves a mark: dark on the wall, red on the dummy. The readout
shows the current shot index in the pattern and the size of the inaccuracy cone
right now, which is the number that moves when you walk, crouch or jump.

`P` turns the marks you just made back into a spray pattern file in the same
format the weapons read, so a pattern can be adjusted by eye against a CS2
screenshot and exported without converting anything by hand. See
`reference/spray_patterns/README.md`.

## Shooting

Hitscan, traced from the camera, with three things done deliberately:

**Sub-tick.** A click carries the time it happened and the look angles at that
instant. The shot is traced from those angles, not from wherever the view had
drifted to by the next simulation tick. At 128 Hz that is up to 7.8 ms of aim
error removed, and it is the difference between hit registration feeling fair
and feeling like it lags you. This is why `PlayerInput` timestamps events
rather than polling, and it is in from day one because retrofitting it later
means rewriting every consumer.

**Deterministic spread.** Each shot's random cone offset comes from a seed
derived from the shot, not from a live RNG. The same shot fired twice under the
same conditions goes to the same place, which is what makes a spray learnable
and what makes the tests able to assert where a bullet went.

**Recoil is view punch, not aim.** Firing moves the camera, and never the
player's own look angles. Pulling down to counter the kick therefore changes
your aim by exactly what you pulled, the same as CS. The player's angles and
the punch are added at the last moment, in `PlayerController`, and stored
separately everywhere else.

The stats themselves are the weak part. CS2 keeps weapon tuning in
`scripts/weapons.vdata_c`, which does not decode into usable values, so none of
it could be extracted the way the map and models were. Everything in
`src/weapons/weapon_library.gd` is a published community figure, and the spray
patterns are outright placeholders. `reference/weapon_stats.md` lists every
number, where it came from, and how to measure the real one.

## dust2

The map is not in this repository and never will be. It is Valve's geometry,
extracted from your own CS2 install into `assets/`, which is gitignored.

On a machine with CS2 installed, and with
[Source2Viewer-CLI](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
somewhere it can be found:

```sh
scripts/extract_assets.sh list-map     # see what is inside the dust2 VPK
scripts/extract_assets.sh map          # extract it to glTF
scripts/extract_assets.sh weapons      # the AK-47 and M4A1-S models
```

The script finds the CS2 install and the resources inside the VPKs itself
rather than hardcoding paths, which drift between game updates. Override with
`CS2_PATH=` and `S2V=` if it guesses wrong.

To see what the extraction produced without opening the editor:

```sh
GODOT=/path/to/godot scripts/inspect_assets.sh
```

On Windows, double-click `scripts/inspect_assets.bat`, which runs the same
thing through Git Bash and waits for a keypress rather than closing.

That prints the file layout and then the import inventory, and is the output
to send over when an import is misbehaving. It is also written to
`inspect-output.txt`, and the import inventory alone is written to
`map-report.txt` whenever the dust2 scene runs. Both are gitignored. There are
three copies because each route fails for someone: the on-screen label is easy
to miss, the editor Output panel scrolls, and a double-clicked terminal closes
before it can be read.

Then open `maps/de_dust2/de_dust2.tscn`. It finds whatever landed in `assets/`
and imports it, printing the same inventory: mesh counts, the bounding box
and every distinct material name. Those three things answer the questions
nobody can answer in advance — whether the export came out at Source scale,
whether it is the right way up, and which materials mark collision geometry.
Read the inventory, then set `collision_material_hints` on the importer to
match what is actually there.

There are no spawn points: they live in the map's entity data, which the glTF
export does not carry. You start above the bounding box and fall in. Noclip is
bound to `V`, which is how you find a better spawn.

## Tests

```sh
GODOT=/path/to/godot scripts/run_tests.sh
```

Note that GDScript's analyser warnings (shadowed variables, unused locals) only
appear when the editor loads a script. They do not show up in a headless run,
so if the Godot console shows any, paste them over and they will get fixed.

Ninety-one checks, in three files: movement, map import and weapons.

Half of the movement ones are the acceleration model against hand-computed
values, which is the part that decides feel and the part most likely to be
broken by a well-meaning edit. The rest drive the real body through the real
course: a standing jump, a crouch jump, a slide down the surf ramp, and a walk
up the access ramp. Those catch the things that are right in the maths and
wrong in the world, which is where the bugs have actually been.

The weapon checks pin fire rate, ammo and reloading, spread determinism, recoil
matching the pattern shot for shot, the ordering of the inaccuracy states,
damage falloff and hitbox multipliers, and that a wall between the muzzle and
the target stops the bullet registering.

The run prints the measured heights and speeds even when it passes, because
watching those numbers move is how you notice a change the assertions were not
tight enough to catch.

## Layout

```
src/movement/    the acceleration model and collide-and-slide
src/player/      input (timestamped), camera, the local player
src/weapons/     weapon data, recoil patterns, the firing model
src/combat/      hitboxes, hit targets, hitscan
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

No dust2, no weapon models, no bots. Shooting works but fires from an invisible
gun at a dummy that does not move.

Movement and shooting are tuned in flat grey rooms first, because tuning them
on a real map is much harder and everything built on top of bad movement is
wasted work.
