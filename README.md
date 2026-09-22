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
- **Stairs**, which are also the ground-adhesion test: running down them should
  never leave the ground and should hold full run speed. See
  `reference/movement_constants.md` on `StayOnGround`.
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

Hitscan, traced from the sub-tick position of the eye, with three things done
deliberately:

**Sub-tick.** A click carries the time it happened and the look angles at that
instant. The shot is traced from those angles and from where the player was at
that instant, not from wherever the view and the body had got to by the next
simulation tick. At 128 Hz that is up to 7.8 ms of aim
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

The spray patterns are the real ones, read off CS2 spray plots: 30 shots for
the AK-47 and 25 for the M4A1-S, with firing order recovered from the plots'
saturation ramp. Their shape is measured; their overall size is an estimate,
because the plots carry no angular scale, and `recoil_scale` on the weapon is
the one number that corrects it.

The rest of the stats are the weak part. CS2 keeps weapon tuning in
`scripts/weapons.vdata_c`, which does not decode into usable values, so none of
it could be extracted the way the map and models were. Everything else in
`src/weapons/weapon_library.gd` is a published community figure.
`reference/weapon_stats.md` lists every number, where it came from, and how to
measure the real one.

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

`map` takes a couple of minutes and a little over a gigabyte. It pulls five
things out of the game: the visible world as glTF with its textures, the
collision hull as a second glTF, the entity lump as text, the second texture
layer of every material that has one (which a glTF has no room for), and the
sky as an HDR panorama. `physics`, `entities`, `layers` and `sky` fetch the
last four on their own, in seconds.

The script finds everything itself: Source2Viewer-CLI on `PATH` or where the
release zip unpacks to in Downloads, CS2 by way of Steam's library list (so a
second drive is fine), Godot on `PATH` or the desktop, and the resources
inside the VPKs by listing them rather than hardcoding paths, which drift
between game updates. Override with `S2V=`, `CS2_PATH=` and `GODOT=` if it
guesses wrong.

Then open `maps/de_dust2/de_dust2.tscn` and press play. You start at one of
the map's own T spawn points (`spawn_team` on the scene root switches sides),
colliding with the hull the game itself collides with, player clips included.
None of the visible world is solid.

The lighting is the map's own numbers, translated (`src/map/map_lighting.gd`):
the sun's colour, brightness and size from `light_environment`, the sky
panorama from `env_sky`, distance haze from `env_cubemap_fog`, exposure from
the `post_processing_volume`, plus screen-space occlusion and a little bloom.
It is the cheap kind of lighting, with no bounce light: CS2 bakes that, and
baking it here is its own project.

To see what came through without opening the editor:

```sh
scripts/inspect_assets.sh
```

On Windows, double-click `scripts/inspect_assets.bat`, which runs the same
thing through Git Bash and waits for a keypress rather than closing.

That prints the file layout and then the import inventory: mesh counts, the
bounding box, where collision came from, the spawn points and every distinct
material name. It is the output to send over when an import is misbehaving.

Three things are put right between extraction and import, by scripts that
the commands above run for you (`reference/asset-pipeline.md` has the
measurements behind each). Source 2 Viewer exports overlays and the kasbah
window insets 15.5 units out along their normals, which leaves signs hanging
off their walls and windows standing proud of their holes;
`scripts/prepare_export.gd` moves them back. The same script keeps the paint
that says where a wall is plaster and where it is brick, which arrives in a
vertex attribute Godot would otherwise drop; with that and the second layers,
`src/map/blend_materials.gd` mixes the two the way the game does. And
extracted textures are imported VRAM-compressed with mipmaps, which Godot
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

A hundred and ninety checks, in four files: movement, map import, dust2
and weapons. The dust2 file skips itself where the map has not been
extracted.

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

Several checks are written as A/B pairs against a config flag: the stairs are
run with `stay_on_ground` on and off, the hop is taken with `subtick_jump` on
and off. Those assert that the fix still does something, which a one-sided
assertion does not.

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
src/weapons/     weapon data, recoil patterns, the firing model
src/combat/      hitboxes, hit targets, hitscan
src/ui/          the tuning readout and the crosshair
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

No weapon models, no bots, no nav mesh. dust2 is in as geometry, collision and
spawn points and nothing more. Shooting works but fires from an invisible gun
at a dummy that does not move.

Movement and shooting are tuned in flat grey rooms first, because tuning them
on a real map is much harder and everything built on top of bad movement is
wasted work.

The surf lane also cannot yet reproduce the one open movement complaint:
launching off the end of a ramp. Its channel runs into the floor, so there is
no ramp end to leave. That geometry is the next thing the course needs.
