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

One more unit to know about: CS2's field of view numbers (`fov 90`,
`viewmodel_fov 68`) are the horizontal angle at 4:3, as Source games have
always meant them; Godot's `Camera3D.fov` is vertical. They are converted
(`ViewModelProjection.vertical_fov`): 90 is 73.7 vertical, 68 is 53.6. Setting
Godot's fov to 90 gives a 121 degree horizontal view at 16:9, which is what
this project did until it was noticed.

## Running it

Open the project in Godot 4.7 and press play. The main scene is dust2. The
other one worth opening is `maps/test_range/test_range.tscn`,
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

`maps/test_range/test_range.tscn`. A flat wall 512 units away to spray at,
ruled in degrees, beside it a lane with a dummy in it to check damage
against, and off to the left a bot that shoots you when you tell it to.

| Key | |
|---|---|
| `1` / `2` | AK-47 / M4A1-S |
| `R` | reload |
| `P` | export the spray you just fired |
| `O` | clear the impact markers, the log, and stand the dummy up |
| `H` | draw or hide the dummy's hitboxes |
| `K` | the dummy's armour: kevlar and helmet, kevlar, none |
| `N` | the dummy's distance: 256, 512, 1024, 2048 units |
| `G` | the dummy never dies: a kill is logged and it is refilled, so a whole spray registers |
| `B` | the shooter fires at you, or holds its fire |
| `U` | the shooter's weapon: AK-47, M4A1-S, MP9 |
| `Y` | your armour: kevlar and helmet, kevlar, none |
| `J` | you never die: a kill refills you |
| `T` | a window on your own body and hitboxes: from the front, from the side, off |

Every bullet leaves a mark: dark on the wall, red on the dummy. The readout
shows the current shot index in the pattern and the size of the inaccuracy cone
right now, which is the number that moves when you walk, crouch or jump.

**The wall** is ruled at every degree from the spawn's eye, bold every five and
numbered: up and down from the aim line, left and right from the centre. A
spray fired from the spawn reads off in degrees, and so does a CS2 spray fired
at a wall from the same distance (496 units to the wall's face), so the two can
be compared without knowing either's scale.

**The dummy** is a bot that stands still and does not shoot back: the same
body and hitboxes the bots on dust2 wear, CS2's nineteen capsules on its bones
where the characters have been extracted, the four standard boxes where they
have not. Fire at it from the yellow spot to the right of the spawn, where
nothing stands between you at any distance. Its hitboxes are drawn over it,
coloured by zone, and the one a round goes into lights up. Each round shows
the damage it did beside where it landed (red for the head), and the readout
at the top right keeps a log: what each round did, to which part, from how
far, what it carried before the armour, and the health left; and for a kill,
the damage in how many hits and the time from the first to the last. The readout also says which
hitboxes it wears, and when they are the stand-in boxes on an extracted
character, why the game's are missing. It starts
in kevlar and a helmet, as an opponent in a rifle round would be. Killed, it
falls as a ragdoll, knocked the way the round was going, and two and a half
seconds later stands up again where it was, whole. G makes it never die
instead.

**The shooter** is a dust2 bot on the red spot left of the wall, armed and
facing the spawn, holding its fire. B sets it on you: it turns, and fires
in bursts with its weapon's own spread and recoil and a bot's aim error.
Each hit tags you (the readout in the bottom left gives the share of your
top speed you have left and how fast you are going, so run while it fires),
throws your aim (the flinch, in degrees), and puts a red arc round the
crosshair on its side. U swaps its weapon: the rifles tag to 40%, the MP9
(the game's own numbers for it on the AK-47's spray, which is not measured
for it) stops you. Y takes your armour off a piece at a time, for the
flinch with and without it; J keeps you alive for as long as you want to be
shot. T opens a window in the bottom right on your own body and hitboxes,
which your camera never shows: the capsules the bots' rounds meet, from in
front of you or from your side, to check them against how you stand,
crouch, strafe and jump. Without the character extracted it shows the four
stand-in boxes.

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

**Recoil is view punch, not aim, and the view is not the bullets.** Firing
moves the camera and never the player's own look angles, so pulling down to
counter the kick changes your aim by exactly what you pulled, the same as CS.

The view kick is also deliberately much smaller than the spray: about a fifth
of it, and it settles back while the spray carries on climbing. Bullets follow
the recoil and nothing else: held down, they walk the pattern exactly; off the
trigger the recoil and its place in the pattern both recover over a few tenths
of a second, so taps land near the aim and a burst after a short pause picks
up part-way down (`src/weapons/recoil_state.gd`). Turning the view kick off entirely leaves every
bullet hole exactly where it was, which is the property that makes a spray
learnable rather than something you read off the screen.
`reference/weapon_stats.md` has the measurements and the knobs.

The spray patterns are the real ones, read off CS2 spray plots: 30 shots for
the AK-47 and 25 for the M4A1-S (whose magazine is 20), with firing order recovered from the plots'
saturation ramp. Their shape is measured; their overall size is an estimate,
because the plots carry no angular scale, and `recoil_scale` on the weapon is
the one number that corrects it.

CS2 keeps weapon tuning in `scripts/weapons.vdata_c`. Source2Viewer 20.0
decodes it, `scripts/extract_assets.sh weapon-data` writes every gun's fields
to `reference/weapons/vdata.csv`, and `WeaponVData` reads them: damage,
armour, falloff, fire rate, magazine and reserve, speed, inaccuracy and
recovery, and when a reload lets the gun fire again all come from the game.
The CS2 Weapon Spreadsheet is read first and now supplies only the landing
and ladder figures, which the game stores another way; the spray patterns
and recovery timings come from measuring CS2 by hand.
`reference/weapons/vdata.md` checks the game's numbers against the sheet, and
`reference/weapon_stats.md` lists where the rest came from.

## dust2

The map is not in this repository and never will be. It is Valve's geometry,
extracted from your own CS2 install into `assets/`, which is gitignored.

On a machine with CS2 installed, and with
[Source2Viewer-CLI](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
somewhere it can be found:

```sh
scripts/extract_assets.sh list-map     # see what is inside the dust2 VPK
scripts/extract_assets.sh map          # extract it, then import it into Godot
scripts/extract_assets.sh weapons      # every gun: models and animations
scripts/extract_assets.sh sounds       # every gun's sounds, footsteps by surface, hits
```

`map` takes a few minutes and a little under two gigabytes. It pulls seven
things out of the game: the visible world as glTF with its textures, the
collision hull as a second glTF, the entity lump as text, the second texture
layer of every material that has one (which a glTF has no room for), the sky
as an HDR panorama, the 3D skybox (the buildings and hills beyond the map, a
small map of their own, drawn behind everything as the game draws it),
and the lightmaps the game baked its bounce light
into, with the light probes beside them. `physics`, `entities`, `layers`,
`sky`, `skybox` and `lightmaps` fetch the last six on their own; all but
the lightmaps take seconds. The lightmaps are one 300 MB image, which
Godot's first import spends a few minutes compressing to 90; the probes are
720 small slices that the game packs into one file the first time it runs.

`weapons` fetches every gun with its first- and third-person animations and
the game's weapon tuning, and `hud` the scope overlay and equipment icons.
`characters` fetches one player model per side (Phoenix and SAS) with their
skeletons, and the rifle animations, which in CS2 are files of their own:
the first-person set, and the third-person locomotion (eight-way run, walk
and crouch, idles, in-air, jump, shoot). `all` does the lot.

With those in place the player has arms and a weapon on screen, animated by
the game's own clips: draw on equip, shoot and reload from the firing model,
idle between. `src/player/view_model.gd` puts the agent's arm meshes and the
weapon's meshes on the rigs the clips animate, and
`src/player/view_model_projection.gd` draws them in the world's own render
with a projection of their own, set in their vertex pass: narrowed to CS2's
`viewmodel_fov`, so they do not stretch at the edges, and squeezed towards
the camera in depth, so they never poke through a wall. Being in the world's
render is what lets the sun, its shadows and the probes reach them; drawn by
a second camera in a viewport of their own, the usual way and how this
project began, they got the sky's glow and never the sun, since a camera
sees only the lights and shadow casters on its own layers. Without the
models extracted there are simply
no arms, and everything else works. On top of the clips, the weapon bobs as
you walk and run, settles lower into the hands at speed, and lags a little
behind a turn (`src/player/view_model_motion.gd`): the bob in Source's own
shape, the amounts set by eye against CS2. Look down and your own body is
there, chest and legs, walking the same clips as a bot's, with your shadow
on the ground: the third-person model with its head and arms folded away
(`RigModel.fold_bones`), since the camera sits inside the one and the view
model stands in for the others. The shadow is cast by a twin of that model
drawn only into the shadow maps, with its head on, so the shadow has one.

Other players are the same agents seen from outside (`src/player/player_model.gd`):
the body on the third-person rig, the weapon in its hand, and the locomotion
clip that fits how the body is moving relative to where it faces, cross-faded
and scaled to its speed. dust2 puts two bots of the other side in
(`bots` on the scene root), walking their spawn points on a loop. A bot
(`src/bots/bot.gd`) is the player's own simulation run by commands its
brain writes instead of keys, so it moves and fires the way a player does, and it can be
shot: it wears the game's own hitboxes, the nineteen capsules CS2 defines
for the model, riding its bones (`src/combat/skinned_hitboxes.gd`), so a
bullet lands on the head, chest, stomach, an arm or a leg and is priced
accordingly, ahead of the movement hull, which bullets pass. A kill turns
the body into a ragdoll (`src/combat/ragdoll.gd`): a rigid body on each bone
with capsules, shaped by them and jointed in cones, knocked the way the last
round was going, falling and lying where it lands; the bot is back at the
start of its route a few seconds later. (CS2's own ragdoll description is
not extracted yet; the hitbox capsules stand in for its shapes. Without
them, the game's death clip for where the round landed plays instead.) And it shoots back:
a player in its sight (in the open, within its cone, for half a second)
stops it in its tracks; it turns, and fires its weapon in bursts with the
weapon's own spread and recoil, reloading when it runs dry. You have the
same health and armour a bot has, and the same nineteen capsules: your
simulation carries the third-person body nobody sees, posed each tick for
how you move, crouch and jump, so a bot's round meets your head where your
head is (without the character extracted, HitTarget's four standard boxes
stand in, and the console says so). Being hit works as in CS2, for you and
the bots alike: a round tags you, leaving you the share of your speed its
weapon's tagging power spares (40% after an AK-47 round) a couple of ticks
later and giving it back over 1.5 s, and it throws your aim up about 2
degrees, half a degree through armour, taking your next rounds with it
(`src/player/player_sim.gd`). The HUD has a crosshair, health, armour (the
shield gets a helmet's dome when you have one), ammunition, a red arc round
the crosshair on the side each hit came from (`src/ui/damage_indicator.gd`),
and three seconds dead before you are back at your spawn with a full
magazine. Bots do not take cover or think beyond that. In the top left the HUD says where you stand and look,
like CS2's `getpos`: the feet's position and the view's yaw and pitch,
which is everything needed to put a render where a screenshot was taken.
F3 hides it.

The sounds are the game's own too (`src/audio/`): the weapon's shots,
reload in its parts and draw, flat in your ears the way the game plays your
own gun; your hits, kevlar, headshot or kill; and footsteps and landings
from everyone's feet, in the world, on the surface they stand on, which the
collision hull names part by part (sand, dirt, wood, metal, tile). Running
sounds, walking does not, as in CS. A round that meets the world leaves one
of the game's bullet holes there and the sound of that surface taking it
(`src/combat/bullet_impacts.gd`). Without `sounds` extracted the game is
silent, the walls unmarked, and everything else works.

`assets/` can live on another drive: make it a junction (`mklink /J`) and
every script and Godot itself read straight through it.

The script finds everything itself: Source2Viewer-CLI on `PATH` or where the
release zip unpacks to in Downloads, CS2 by way of Steam's library list (so a
second drive is fine), Godot on `PATH` or the desktop, and the resources
inside the VPKs by listing them rather than hardcoding paths, which drift
between game updates. Override with `S2V=`, `CS2_PATH=` and `GODOT=` if it
guesses wrong.

Then open `maps/de_dust2/de_dust2.tscn` and press play. You start at one of
the map's own T spawn points (`spawn_team` on the scene root switches sides),
colliding with the hull the game itself collides with, player clips included
(which stop you and not your rounds). None of the visible world is solid.

The lighting is the map's own numbers, translated (`src/map/map_lighting.gd`):
the sun's colour, brightness and size from `light_environment`, the sky
panorama from `env_sky`, distance haze from `env_cubemap_fog`, exposure from
the `post_processing_volume`, plus screen-space occlusion and a little bloom.
The sun's shadows reach across the whole map, and the world casts them with
both faces of every surface: its walls are one-sided, so a shadow pass that
only sees front faces lets the sun into every room whose wall faces the
other way. The 3D skybox casts none, as in the game.
The bounce light is the game's own too: CS2 bakes it into lightmaps, and the
walls, ground and most props read those (`src/map/lightmap_materials.gd`,
the `lightmapped*.gdshader`s) in place of Godot's flat sky ambient, so the
shade under an arch is the warm dim of the game rather than a blue-grey.
What has no lightmap coordinates of its own is lit by the game's light
probes instead (`src/map/light_probes.gd`): an ambient cube baked at every
cell of a grid across the map, which the remaining props read once where
they stand and the players, bots and your own arms read every frame from
where they are, so the arms dim in a tunnel and warm under an awning. The
far skybox keeps the lightmap's average light as its ambient.

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

Seven files: movement, map import, dust2, models, weapons, the test range
and the simulation. Without the extracted assets 519 checks run and pass;
the dust2 and model files skip what needs files that have not been
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

## Simulation and view

The game is built the way a server runs it, so going online later is not a
rewrite. Every player, you and the bots alike, is a `PlayerSim`
(`src/player/player_sim.gd`) that moves forward one tick at a time by
running a `UserCmd` (`src/sim/user_cmd.gd`), shaped like CS2's user command:
the buttons held, the move keys, the look angles, and each press or release
inside the tick with the fraction of the tick it happened at. Your keys
become one command a tick (`PlayerInput.build_command`); a bot's brain
writes its own. The simulation never reads the keys or the wall clock: its
time is the tick number (`src/sim/sim_clock.gd`), so the same commands give
the same game however fast they are run, which `tests/run_sim_checks.gd`
holds it to. What you see and hear, the camera, the arms, your body and
shadow, sounds and bullet holes, is `PlayerView`
(`src/player/player_view.gd`), which reads the simulation and never changes
it.

## Layout

```
src/sim/         user commands and simulation time
src/movement/    the acceleration model and collide-and-slide
src/player/      the player simulation, input to commands, the first-person view
src/map/         glTF map import, and the map's entity data (spawn points)
src/weapons/     weapon data, recoil patterns, the firing model
src/combat/      hitboxes, hit targets, hitscan
src/ui/          the tuning readout and the crosshair
maps/            generated test courses, and the dust2 scene
tests/           headless test suite
reference/       measured constants and how they were measured; the roadmap
                 (roadmap.md), CS2's systems (cs2-systems.md), the guns' todo
                 list (weapons/TODO.md)
scripts/         tooling (asset extraction and inspection, test runner)
assets/          extracted CS2 content. GITIGNORED. Never commit Valve assets.
```

`reference/` is in version control and `assets/` is not, on purpose. The
reference data is our own measurements and stays valid; the extracted content
is disposable and regenerable, and keeping it out of git means swapping to
original assets later is a content change rather than a git history problem.

## What is deliberately not here yet

No bots that do anything but walk their spawn and shoot what they see, no
nav mesh, no firing animation on the third-person model. `reference/roadmap.md`
has the rest, in order.

Movement and shooting are tuned in flat grey rooms first, because tuning them
on a real map is much harder and everything built on top of bad movement is
wasted work.

The surf lane also cannot yet reproduce the one open movement complaint:
launching off the end of a ramp. Its channel runs into the floor, so there is
no ramp end to leave. That geometry is the next thing the course needs.
