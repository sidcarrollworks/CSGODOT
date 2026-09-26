# How the game is built

The README says what the game is; this page says how its parts work, with
the files that hold them. `reference/roadmap.md` has what is left, and
`CLAUDE.md` the rules every change keeps to.

## Scale: Source units, not metres

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

The physics engine is Jolt, and Jolt's settings assume metres. The ones that
are lengths or speeds (how far bodies may sink into each other before they
are pushed apart, how slowly a body must move to fall asleep, the fastest
any body may go) are set in project settings to their defaults times 39.37.
Left alone, the speed limit of 500 was 500 u/s, which a falling body passes
156 units down.

One more unit to know about: CS2's field of view numbers (`fov 90`,
`viewmodel_fov 68`) are the horizontal angle at 4:3, as Source games have
always meant them; Godot's `Camera3D.fov` is vertical. They are converted
(`ViewModelProjection.vertical_fov`): 90 is 73.7 vertical, 68 is 53.6. Setting
Godot's fov to 90 gives a 121 degree horizontal view at 16:9, which is what
this project did until it was noticed.

## Simulation and view

The game is built the way a server runs it, so going online later is not a
rewrite. Every player, you and the bots alike, is a `PlayerSim`
(`src/player/player_sim.gd`) that moves forward one tick at a time by
running a `UserCmd` (`src/sim/user_cmd.gd`), shaped like CS2's user command:
the buttons held, the move keys, the look angles, and each press or release
inside the tick with the fraction of the tick it happened at. Your keys
become one command a tick (`PlayerInput.build_command`); a bot's brain
writes its own. One `GameWorld` (`src/sim/game_world.gd`) runs the game,
as a server does: every tick it asks each player for their command, runs
them in the order they joined (on dust2 you, then the bots), then the
match; nothing else runs itself. The simulation never reads the keys or the
wall clock: its time is the world's tick number (`src/sim/sim_clock.gd`),
so the same commands give the same game however fast they are run, which
`tests/run_sim_checks.gd` holds it to. What you see and hear, the camera,
the arms, your body and shadow, sounds and bullet holes, is `PlayerView`
(`src/player/player_view.gd`), which reads the simulation and never changes
it.

The simulation runs 64 ticks a second, as CS2's does, and takes input
between them (a press carries its fraction of the tick). It ran 128 until
2026-09-23, when Sid chose 64 for what a server will cost: everything a tick
does is paid half as often, and a server has room for more players.
Everything drawn is drawn between the last two ticks, as far between them as
the frame falls, so 64 a second does not show: your camera, the kick of your
view and your gun, other players' bodies (and their hitboxes, which ride
them, so a round meets a body where it was seen) and ragdolls.

A tick at 64 Hz is 15.6 ms, and every player's share of it has to fit with
room left to draw the frames. When it does not, each frame runs more ticks
to catch up, which makes the frame longer still, and the game crawls. Ten
players on dust2 take about 3 ms a tick on Jolt, and twenty about 8
(headless, 2026-09-23), most of it their movement: a trace of the hull
through dust2's collision costs 20 to 50 us, and a player makes one a tick
standing still and four running in the open, more against a wall or a slope
(PlayerBody counts them, and run_tests.gd holds them to that). So nothing
that reads the disk runs in a tick, and what is only seen, like the probe
light on a bot's body, follows the frames drawn rather than the ticks.
`reference/performance.md` has what every system costs, with ten players and
twenty, what going online will add, and what to do about it next;
`scripts/profile_dust2.gd` measures it again.

## Shooting

Hitscan, traced from the sub-tick position of the eye, with three things done
deliberately:

**Sub-tick.** A click carries the time it happened and the look angles at that
instant. The shot is traced from those angles and from where the player was at
that instant, not from wherever the view and the body had got to by the next
simulation tick. At 64 Hz that is up to 15.6 ms of aim
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
the one number that corrects it. Fifteen more guns have patterns on the
AK-47's scale from a community source (`reference/spray_patterns/README.md`
says how far to trust them); the G3SG1 and SCAR-20 have none yet.

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

## Players, bots and the match

With those in place the player has arms and whatever is in hand on screen,
animated by the game's own clips: the draw on taking it out, shoot and
reload from the firing model, a grenade's pin and throws, the bomb's plant,
idle between. `src/player/view_model.gd` puts the agent's arm meshes and the
weapon's meshes on the rigs the clips animate, one for each thing carried,
built as it comes into the inventory and hidden while something else is in
hand, so taking it out builds nothing; and
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
there, belt and legs, walking the same clips as a bot's, with your shadow
on the ground: the third-person model folded away from the chest up
(`RigModel.fold_bones` on spine_2), since the camera sits inside the head,
the view model stands in for the arms, and CS2 shows no chest looking down.
Looking down it tips back about its feet and its lower back bends forward
(`LookDownArch`), so the view feels like the back arching over the legs.
The shadow is cast by a twin of that model drawn only into the shadow maps,
whole, so the shadow has a head and arms.

Other players are the same agents seen from outside (`src/player/player_model.gd`):
the body on the third-person rig, the weapon in its hand, moved as CS2's own
animation graph moves it. Its running, walking and crouching clips sit in
CS2's blend spaces, each at the speed the game authored it for (runs at
225 units a second, walks at 136, crouching at 96), and the body's speed
along and across where it faces mixes the ones around it, kept in step as
CS2 keeps them; the air is blended the same way, with the game's cross-fades
into it and back (`reference/animgraph2.md`). Over that the upper body
holds, fires and reloads the gun with the gun's own clips, as CS2's graph
lays them over the legs: every round a bot fires kicks its arms and
shoulders, and its reload plays while its legs keep moving. dust2 plays a
match of five a side, bots in every place but yours (`team_size` on the
scene root), each walking from a spawn point to a bomb site and back over
the map's nav mesh, or its side's spawn points on a loop without it. A bot
(`src/bots/bot.gd`) is the player's own simulation run by commands its
brain writes instead of keys, so it moves and fires the way a player does, and it can be
shot: it wears the game's own hitboxes, the nineteen capsules CS2 defines
for the model, riding its bones (`src/combat/skinned_hitboxes.gd`), so a
bullet lands on the head, chest, stomach, an arm or a leg and is priced
accordingly, ahead of the movement hull, which bullets pass. A kill turns
the body into a ragdoll (`src/combat/ragdoll.gd`): CS2's own fifteen ragdoll
shapes from the model description (the hitbox capsules where it has none),
jointed with limits that differ each way, measured from standing, knocked the
way the last round was going, lifted clear of the floor, falling and lying
where it lands; off the range the bot is back at the start of its route a few
seconds later, and in a match at the next round. (CS2's joints are not read
yet: `reference/research/ragdoll-joints.md`. Without the model, the game's
death clip for where the round landed plays instead.) And it shoots back:
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
(`src/player/player_sim.gd`). Smoke hides a player from a bot as far as
CS2's bot sees through it, and a flash blinds a bot by the same rules it
blinds you; beyond that, bots do not take cover or think.

The HUD (`src/ui/game_hud.gd`) is laid out as today's CS2 lays it out:
health, armour and ammunition in one cluster at the bottom round the team's
emblem, your money in the bottom left, the clock, scores and who is alive
at the top, a bar saying what part of the match it is, a red arc round the
crosshair on the side each hit came from, and CS2's buy menu on B. Each
piece is a `HudElement` that draws with `HudStyle`'s colours, font and icons
and redraws only when what it shows changes. The kill feed, radar and
scoreboard are roadmap item 15. On the range and in warmup, three seconds
dead puts you back at your spawn with a full magazine. In the top left the
HUD says where you stand and look,
like CS2's `getpos`: the feet's position and the view's yaw and pitch,
which is everything needed to put a render where a screenshot was taken,
and under it the frame rate and the slowest frame of the last second (the
range and the movement course show the same). F3 hides them.

dust2 is a match, run the way CS2's server runs one (`src/match/`), with
CS2's competitive numbers (`MatchRules`): two minutes of warmup, where you
come back when you die (F5 ends it), then rounds of 15 s of freeze time,
where you can look round but not move or fire, and 1:55 of play. A round
ends when a side is all dead, when time runs out, which the
counter-terrorists win, or by the bomb: once it is planted the clock no
longer ends the round and the Ts all dead does not either; its blast wins
it for the Ts, its defuse for the CTs. The next starts 7 s later, everyone
back at a spawn, the survivors healed with the armour and weapons they had. Nobody comes back
during a round: dead, you see your body for 2 s, then a living teammate's
eyes (fire moves to the next, jump puts the camera behind them). After 12
rounds the sides swap and the score goes with the team; 13 wins it, 12-12
goes to one overtime of six rounds, and 15-15 is a draw. A teammate's round
does a third of its damage, and nobody walks through anybody. The score,
each side's players alive and the clock are at the top of the screen. A
spawn from nothing gives the knife and the side's pistol (the Glock-18, the
CTs' P2000) and no armour, and the rest is bought: B in your buy zone,
$800 to start, $16,000 in warmup, your money above your health. The bots
buy in freeze time as CS2's own bots do, and hold what is in their hands.

## The round's systems

The bomb (`src/bomb/`), grenades (`src/grenades/`: HE, flash, smoke with its
voxels, molotov and incendiary fire, decoy), money and buying
(`src/economy/`), and what a player carries and drops (`src/game/`) are
systems of their own. They meet only through the contract in
`reference/systems/contracts.md`: schema-checked events, the world's
`GameSystems`, `DamageInfo.deal`, the inventory and player commands. Each
has a page in `reference/systems/` with the rules it settled while being
built. What is seen of a shot, its tracer and muzzle flash, is drawn from
the tick's events in `src/effects/`, never inside the tick.

## Sound

The sounds are the game's own too (`src/audio/`): the weapon's shots,
reload in its parts and draw, flat in your ears the way the game plays your
own gun; your hits, kevlar, headshot or kill; and footsteps and landings
from everyone's feet, in the world, on the surface they stand on, which the
collision hull names part by part (sand, dirt, wood, metal, tile). Running
sounds, walking does not, as in CS. A round that meets the world leaves one
of the game's bullet holes there and the sound of that surface taking it
(`src/combat/bullet_impacts.gd`). Without `sounds` extracted the game is
silent, the walls unmarked, and everything else works.

CS2's own sound events, the volume, distance curve, mixgroup, limits and
layers of every sound, are a table generated from the game's text files
(`reference/sounds/`, by `scripts/sound_events.sh`), and `SoundEvents`
(`src/audio/sound_events.gd`) plays any of them the way CS2's sound stack
does, on the bus of its mixgroup (`default_bus_layout.tres`). New sounds
are built on it; the ones above still carry levels set by ear.

## Lighting

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

## Tests

```sh
scripts/run_tests.sh              # every test file
scripts/run_tests.sh sim match    # only the files whose names contain these
```

Every file runs, even after one fails, and a summary at the end says how
each went; it exits 1 if any failed or ended without reporting (a script
error). The same run happens on GitHub for every pull request and every
push to main (`.github/workflows/tests.yml`), where the files that need
the extracted assets skip themselves as they do on a fresh clone. A test
file is any `tests/run_*.gd`; it extends `tests/check_suite.gd`, which
has the checks and the one line each file ends with for the summary.

Every system has its own file, from movement, weapons and the map to the
match, the bomb, grenades, the economy, bots and the HUD. Half of the
movement checks are the acceleration model against hand-computed
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

Note that GDScript's analyser warnings (shadowed variables, unused locals) only
appear when the editor loads a script. A headless run shows them only when
they are turned into errors, so to list them, put a throwaway `override.cfg`
in the project root:

```
[debug]

gdscript/warnings/shadowed_variable=2
gdscript/warnings/shadowed_variable_base_class=2
gdscript/warnings/confusable_local_declaration=2
gdscript/warnings/integer_division=2
```

then run each script through `godot --headless --path . --check-only --script
<file>`, and delete `override.cfg` afterwards. As errors they fail every
script that depends on the one they are in, so fix the first file named and
run again. The project has none of these four; a division meant to drop the
remainder says so with `@warning_ignore("integer_division")`. A check that
exits with no output at all crashed on the way out; run it again.

## Why `reference/` is committed and `assets/` is not

`reference/` is in version control and `assets/` is not, on purpose. The
reference data is our own measurements and stays valid; the extracted content
is disposable and regenerable, and keeping it out of git means swapping to
original assets later is a content change rather than a git history problem.

Movement and shooting are tuned in flat grey rooms first, because tuning them
on a real map is much harder and everything built on top of bad movement is
wasted work.
