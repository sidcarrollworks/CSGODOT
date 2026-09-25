# CSGODOT roadmap

Written 2026-09-22 off `main` at `173a35e` (PR #21), read from the code rather
than from notes, brought up to date with PRs #23 to #25 at 23:00, and
with PR #27 (phase 1's Remote items: being shot) on 2026-09-22, and with
PRs #28 to #34 (every gun extracted, the game's own weapon numbers, the
range's fixes and ragdolls, wall penetration, dust2's nav mesh, buy zones,
bomb sites and radar) on 2026-09-23. It
replaces `plan-to-playable.md`, most of which has landed. This copy in the
repo is the one to keep current: whoever lands a roadmap item marks it done
here in the same PR.

The target is Sid's scope: CS2 on dust2, with every gun in the CS2 weapon
sheet and every system CS2 has (money, buying, the bomb, grenades, dropping
guns, multiplayer), and movement, shooting and hit registration that feel the
same as CS2. Both were widened on 2026-09-22. Everything past that is listed
at the end under "Later".

Each item says where it can be done: **Local** needs Sid's machine (CS2,
Source2Viewer, the extracted assets, or playing the game), so his local agent
or Sid takes it; **Remote** is code and headless tests a cloud thread can do.

---

Updated 2026-09-22: weapon numbers from Sid's spreadsheet and tapping (PR #23), every gun added, items marked Local or Remote; at 21:55, every CS2 system added (phases 3 to 10) from `reference/cs2-systems.md`; at 23:00, phase 3 done (PR #24) and the first shot while running fixed.
Updated 2026-09-23 (later): match and round flow done (item 11).
Updated 2026-09-23: wall penetration done (item 7, PR #31) with its two measurements added (7a, 7b); dust2's nav mesh extracted and read (PR #32), so bots can start walking it (item 22); the range fixes and your own ragdoll in (PR #30), so items 6 and 6a can start; dust2's buy zones, bomb sites and radar read (PR #34); the blood extraction and what can start now added to "Waiting on Sid" and the last section.
Updated 2026-09-23 later: bots walk the nav mesh (item 22), to the bomb sites and back.
Updated 2026-09-23 evening: one world runs the tick (`GameWorld`, the first part of `reference/systemization.md`'s step 1).
Updated 2026-09-23 night: dust2 buys (items 13 and 14 wired in), spawns give the knife and pistol only, the match sends CS2's round events, the bomb and grenades are in dust2's match, bots buy as CS2's do and hold what is in hand (items 6 and 24), and a drop is thrown from the hand (item 12).
Updated 2026-09-24: binds added (item 12a, planned in `reference/binds.md`): one table of keys, CS2's defaults, for the game and the test range alike.
Updated 2026-09-24 later: game modes apart from maps (item 24a, `reference/systemization.md` step 4's first part): any extracted defusal map plays in competitive.

## Part 1: what exists

### Movement
- Source SDK 2013's movement ported line by line: acceleration, air
  acceleration, friction, collide-and-slide, step move, at a fixed 64 Hz, as
  CS2's, in Source units (`src/movement/`). It was 128 until 2026-09-23, when
  Sid chose 64 for what a server costs; what is drawn is drawn between ticks.
- Every gap the Source 2 research guide found is closed: `StayOnGround`, the
  quadrant ground trace, `CheckVelocity` (3500), `NON_JUMP_VELOCITY` 140, the
  splined duck eye offset, the ground-normal wish projection behind a flag, the
  trace push-out set to zero, `cs2_deadstrafe` renamed `source_deadstrafe` with
  its citation.
- Sub-tick input: clicks and jumps carry their timestamp, the shot is traced
  from the interpolated position and the look angles at that instant. Since
  PR #24 this works in the running game, not only in the tests.

### Simulation and view (PR #24)
- Every player, you and the bots, is one simulation (`PlayerSim`) run a tick
  at a time from CS2-shaped input commands (`src/sim/user_cmd.gd`), on
  simulation time rather than the wall clock (`src/sim/sim_clock.gd`).
- Your keys become one command a tick (`PlayerInput.build_command`); a bot's
  brain writes its own. What you see and hear is a view that only reads the
  simulation (`src/player/player_view.gd`).
- Scroll up jumps, noclip on V.
- The match is simulation too (`src/match/match_state.gd`, item 11): it
  moves on with the tick and changes the game only through the players.
- One world runs the tick (`src/sim/game_world.gd`, 2026-09-23): every
  player's command in the order they joined, then the match. Nothing runs
  itself, and its tick count is simulation time.
- A movement test course: strafe lane, stairs, ramps at 20/35/44/50 degrees,
  surf lane, jump gauges.

### Shooting
- AK-47 and M4A1-S with the real spray patterns read off CS2 plots (30 and 25
  rounds), every number from CS2's own weapons.vdata through `WeaponVData`
  (PR #28; the sheet, PR #23, gives only landing and ladder), inaccuracy by
  movement state with counter-strafing, damage falloff, armour.
- Spread is seeded per round by the moment it was fired, so a first shot at
  a run lands anywhere in the running cone (PR #24; before, every first round
  landed on one spot 0.9 degrees off the aim, and Sid saw running first
  shots as perfectly accurate).
- Recoil is view punch only and the bullets follow the pattern alone. Four
  springs, tuned against Sid's playtests and signed off as good enough (PR #9).
  Animation and accuracy-reset times measured in CS2.
- The firing clip replays on every round; viewmodel bob, sway and lag;
  your own body and shadow when you look down.
- Tracers and muzzle flashes (2026-09-24), CS2's own: every gun's tracer at
  its effect's speed, length and colour, from the drawn muzzle, every round
  but a silenced one's; every gun's flash in first person and third, its
  flames, beams, sparks, smoke and light (`src/effects/`,
  `reference/weapons/effects.md`).
- Test range: a wall ruled in degrees at 496 units, spray export to CSV, and
  a dummy wearing CS2's own hitboxes with a hit log, damage numbers, armour and
  distance switches, a never-die mode and a ragdoll death (PR #20).

### Map and art
- dust2 extracted from Sid's CS2 install and imported: visible world, the
  game's own collision hull, player clips (which stop players and not rounds,
  PR #21), entity lump, blend layers, sky, 3D skybox.
- Lighting from the map's own numbers: sun, fog, exposure, the baked
  lightmaps for bounce light, light probes for props, players and arms.
  The 3D skybox lit by its own lightmaps, the props with a decal UV set
  (the kasbah towers, arches, crates) by the map's through their third
  UV set, and the props' decals and glow; and the two lamps down lower
  tunnels, which CS2 lights as it draws rather than bakes, lit the same
  way (`MapLighting.add_lamps`). After Sid found black skybox buildings,
  orange blocks on the towers and a dark lower tunnel (2026-09-24,
  `reference/asset-pipeline.md`).
- What a frame costs to draw, measured on Sid's machine (2026-09-24,
  `scripts/profile_render.gd`, `reference/rendering.md`): the sun's live
  shadows are most of it. Occlusion culling from the collision hull and a
  skybox the depth test can hide went in with it (PR #78).
- What is drawn is what CS2 draws from where you stand: the map's own
  visibility (`world_visibility.vvis_c`, `WorldVisibility`), read after
  Source 2 Viewer, culls the world meshes the camera's cluster cannot see,
  keeping their shadows. Sid found a kasbah tower at B drawn over the 3D
  skybox's dome from T spawn, which CS2 does not draw there (2026-09-24).
  With it, the rest of what he found then: dust2's windows, black where
  the probes were read at the middle of a mesh merged from all over the
  map, are lit from their own vertices; and the skybox's palm, bush, olive
  and antenna cards, exported without their alpha, get it back at
  extraction (`scripts/export_alpha.gd`).
- Viewmodel arms and weapons at CS2's `viewmodel_fov`; third-person agents
  (Phoenix and SAS) on the locomotion rig, moved by CS2's own blend spaces
  (runs at 225, walks at 136, crouching at 96, kept in step) in an animation
  tree, with the air blended the same way.
- Every gun extracted (PR #28): the 34 guns' models, first- and third-person
  animations and sounds, the scope overlay and the equipment icons, listed in
  `reference/weapons/`. Only the AK-47 and M4A1-S are in your hands so far;
  the range's shooter also carries an MP9.
- dust2's own nav mesh (PR #32), read by `SourceNavMesh`: 2,242 areas and
  their links, with paths between any two points. Bots walk it, the paths
  pulled taut, jumping and crouching where it says (item 22).
- dust2's buy zones, bomb sites and callout volumes (`BrushVolume`), its
  radar (`MapOverview`) and its baked bomb damage file, extracted and read
  (PR #34).
- The equipment extracted: the bomb and the defuse kit, the six grenades,
  the two default knives and the Zeus, with their animations and sounds,
  listed with the game's numbers and their clips' timings in
  `reference/weapons/equipment.md`. Each builds in first person; nothing
  hands them to a player yet.
- CS2's animation graphs (AnimGraph 2) read (`NmGraph`): the parameters the
  game sets, the third-person graph's layers and state machines, the
  locomotion's blend spaces with each clip's speed, and the first-person
  gun's actions, in `reference/animgraph/`; `reference/animgraph2.md` says
  what they are and what they mean here. The locomotion's blend spaces move
  the third-person body (above); nothing else of them plays yet.

### Combat
- Bots and the player share one damage path (`Hitscan.fire_at` then
  `HitTarget.apply_damage`).
- Bots and the player wear CS2's 19 hitbox capsules on their bones; bullets
  pass the hull and only hitboxes count. The player's are on a third-person
  body the simulation poses each tick and nobody sees (PR #27).
- Being hit tags you (the weapon's tagging power, from the game's own
  weapons.vdata through `WeaponVData`, two CS2 ticks after the hit, back
  over 1.5 s) and throws your aim, and your next rounds with it
  (PR #27). Bots too.
- Every player, you included, dies into a ragdoll built from their
  capsules, with hinged knees and elbows and friction in every joint (PR
  #30). While you are dead the camera leaves your head and looks at your
  body. On the range and in warmup you are back at spawn after 3 s, a bot
  after 5 s; in a round nobody comes back, and after 2 s you watch a
  living teammate (item 11).
- Friendly fire in a match: a teammate's round does 33% (item 11). Every
  player's hull is solid to every other's, teammates included; a dead
  one's is not.
- Bullet holes from the game's own decal materials, per surface, with impact
  sounds.
- Wall penetration (item 7, PR #31): a round goes through thin walls by what they
  are made of, with CS2's own per-surface numbers, and loses damage doing it.
  A hole on both sides of every wall.

### Bots
- dust2 fills both sides to five with bots, on the player's own body and
  movement solver (item 11).
- They walk their side's spawn points in a loop, see the player (3000 units,
  75-degree half cone, line of sight, 0.5 s reaction), turn, and fire bursts
  through the same simulation and trigger path as the player, with 1.2
  degrees of extra aim error. They target only the other side.
- Their bodies hold, fire and reload their guns with the guns' own
  third-person clips, over the upper body (item 6). On dust2 a body holds
  whatever is in its hand, its model and its clips changing with it, and
  moves on CS2's locomotion for it: the pistol's, the knife's (knives and
  grenades) or the rifle's.
- On dust2 they spawn as you do, with the knife and their side's pistol,
  and buy in freeze time as CS2's classic bot does (`BotBuying`: nothing
  below $2,000, a primary by one of `botprofile.db`'s weapon templates,
  armour, a kit for a CT, a third of the time a grenade), then take their
  best gun out. They tap a pistol every half second rather than hold the
  trigger (item 24).

### Sound
- The game's own sounds: weapon shots, reload and draw (every gun's, from
  the game's tables), the shooter's hit feedback as CS2's attacker feedback
  events have it (the body's thud, kevlar, the headshot and the helmet's
  dink, a kill's own; files, volumes, pitches and distance curves from
  `game_sounds_player.vsndevts`), what the one hit and those near hear of
  a hit and the death groan (`HitSounds`), footsteps and landings per
  surface, impact sounds.

### HUD
- In a match, the score, each side's players alive, the round's clock and
  a line saying which part of the match it is; dead in a round, whose eyes
  you are in (item 11).
- Crosshair, health, armour, ammo, death countdown, the movement tuning
  readout, and where you stand and look in the top left (PR #25, F3 hides
  it).
- A red arc round the crosshair on the side each hit came from (PR #27).
- On the test range, a shooter that fires at you on B, with its weapon (U),
  your armour (Y) and never-die (J) switched, a readout of your tag and
  flinch, and a window on your own hitboxes (T) (PR #27).

### Tooling
- `scripts/extract_assets.sh` (map, physics, weapons, characters, sounds and
  more, the nav mesh with `nav`), `inspect_assets`, and `run_tests.sh` with
  eight headless test files (movement, map, dust2, model, weapon,
  penetration, range, simulation): 622 checks pass without the assets.

---

## Part 2: what is left, in order

Each phase can start once the one before it is in, except where noted.
Items marked **(Sid)** need Sid's machine or a decision from him.

### Phase 1: make being shot feel like CS2

This was the unfinished half of hit registration. Items 1 to 4 are in (PR
#27); blood and the third-person firing layer are left.

PR #30 fixed what Sid's first playtest of #27 found: a range bot's gunfire
playing from the middle of the map, bots folded over while firing, and the
dummy's ragdoll blowing apart. It also ragdolls your own body where you can
see it when you are killed, and gives the ragdoll's joints resistance so
limbs stop spinning (Sid, 2026-09-23). It took out the whole-body firing
clip that folded the bots over, so bots fire with no arm movement until
item 6 is built.

1. **The player's own hitboxes.** *(done, PR #27; Sid checks the fit)* The player
   wears the same 19 capsules as the bots, on a third-person body the
   simulation carries and poses each tick (`PlayerSim.wear_body`), hidden,
   since the view draws its own body set back from the eyes. Crouched,
   jumping or mid-strafe, a bot's round meets your head where your head is.
   Without the character extracted the four boxes stand in, and the console
   says so (`--- your hitboxes:`). **Sid:** play dust2 with the hitboxes
   drawn on a bot, and on the test range press T to watch your own capsules
   from outside while you crouch, strafe and jump; the model
   checks now assert 19 capsules on you with the head 50 to 72 units up.
2. **Tagging.** *(done, PR #27; Sid checks the feel)* A hit leaves the player
   1 minus the weapon's tagging power of their top speed (40% after an AK-47
   round, a stop after an SMG's), two CS2 ticks after it lands
   (`sv_predictable_damage_tag_ticks`), and friction brings them down to
   it. The tagging power is CS2's `m_flFlinchVelocityModifierLarge` taken
   from one, read from the game's own file through `WeaponVData` (the sheet
   agrees for every gun). Still estimated: the speed comes back at CS:GO's
   0.4 a second, and weapons.vdata's `...Small` figure, in
   `reference/weapons/vdata.csv` for every gun, is not used (**measure**,
   below).
3. **Aim punch when hit.** *(done, PR #27; Sid checks the size)* A hit pushes the
   aim up about 2 degrees unarmoured and half a degree through kevlar or a
   helmet, recovering the way a spray's aim punch does, within about
   0.4 s. Unlike the recoil's view kick it is the aim: the
   crosshair shows it and rounds fired meanwhile go there. Both sizes are
   estimates; CS2 scales its flinch by `mp_flinch_punch_scale` 3 but does
   not publish the base.
4. **Damage direction indicator and armour on the HUD.** *(done, PR #27)* Armour
   beside health, with a helmet's dome on the shield when there is one; a
   red arc round the crosshair for each hit, on the side the round came
   from, fading after 1.5 s.

4a. **Measure being shot in CS2.** *(Local)* With a friend or bots on a
   local server: how long a tag takes to wear off after one AK-47 body
   shot (1.5 s here), whether a leg shot or a shot through kevlar tags less
   (the `...Small` modifier and A1 in `reference/cs2-systems.md`), and a
   screenshot pair of the view just before and just after an unarmoured
   hit, to size the flinch (2 degrees here).
5. **Blood on hit.** *(Local extracts the effects, then Remote)* A round into a body leaves no mark, so a hit is only
   heard, not seen. CS2's blood impact and decal behind the target.
6. **Firing on the third-person model.** *(Done 2026-09-23 but for the flinches; Sid checks it)* A bot's body holds, fires and
   reloads its own gun: the gun's third-person clips (`WeaponData.world_clip_set`)
   in `PlayerModel.animation_tree`, over the locomotion as CS2's graph
   stacks them (`reference/animgraph/worldmodel.md`), through its UpperBody
   mask: the gun's hold added, its reload or draw in place of the upper
   body, each round's shot added on top. CS2's additive clips are re-expressed
   from the rest pose for Godot's additive blend (`PlayerModel.rest_relative`).
   Since 2026-09-23 a map's bot holds whatever is in its hand
   (`PlayerModel.hold`): each item's model kept while carried and shown in
   hand, its own set's clips added the first time, and the locomotion
   switched to the pistol's, knife's or rifle's as CS2's graph picks it
   (`PlayerModel.variation_for`). What its bots may hold is read before
   play (`prepare_holding`), so taking a gun in hand reads nothing from the
   disk. Every body does it, yours unseen too, as CS2's server poses every
   player's hitboxes with what they hold; the variation switches once the
   draw is over, as CS2's graph has it. Left: CS2 blends the weapon layer in
   model space, Godot in each bone's own, so the upper body follows the hips
   here; the flinches, additive too and ready to go in the same way, are
   not extracted yet (the characters step takes only the deaths from
   `world/shared/`); and the aim: CS2's AimCS bends the upper body and head
   with the aim's pitch (and the torso with part of its yaw), on the
   server, so the hitboxes move with it. Here bodies and their hitboxes
   stand as if looking level (`reference/research/hitboxes-aim.md`: a
   Local measurement, then the aim stage after systemization step 8).

6a. **Your shadow has no arms.** *(Remote, can start now; Sid checks it)* Sid noticed
   2026-09-22 22:06. The shadow twin (commit f42114e) put the head back but folds the
   arms on purpose (`SHADOW_FOLDED_BONES` in `player_view.gd`), because
   arms in the locomotion pose would fall across the view model's. It is also
   built with no weapon (`model.setup(team, "")`). CS2's shadow is the
   third-person body, arms and gun included, so: unfold the arms, give the
   shadow the weapon's world model, and pose its upper body from the
   third-person firing layer (item 6).

### Phase 2: finish the shooting model

7. **Wall penetration.** *(done, PR #31; Sid checks it on the range with M)* `Hitscan.trace` now finds the far
   side of each wall it meets and carries on through it when the round has
   the power, up to four walls, never into the sky. Each weapon's power is
   the game's `m_flPenetration` (rifles 2, SMGs 1). Each surface's two
   numbers are CS2's own, read from the game's files through
   `SurfaceProperties` (item 7b), taken by the name the hull gives each
   part. How thickness and those
   numbers become reach and damage is this project's own routine, since
   CS2's is not published, and its four constants are estimates. On the
   test range, M stands a wall of one of seven surfaces in front of the
   dummy and the log says what each wall let through. A round stops at the
   first person it hits: going on through them (collaterals) is not in yet.
7a. **Measure penetration in CS2 (Sid).** *(Local)* Set the four estimates
   in `Penetration` (`REACH_PER_POWER`, `FLAT_LOSS`, `DAMAGE_DEPTH`,
   `MOST_WALLS`) from the game: with `sv_showimpacts 1` and
   `sv_showimpacts_penetration 1`, shoot a bot through a few dust2 walls of
   known surface (mid doors, a wooden crate, a thin concrete wall, a car)
   with the AK-47 and an SMG, and note the damage each did, the thickness
   the game shows, and where a round stopped getting through. Then shoot
   the same walls on our dust2 and compare.
7b. **Surface parents.** *(done 2026-09-23)* `scripts/extract_assets.sh
   surfaces` extracts `surfaceproperties.vsurf` (all 164 surfaces, each with
   its parent, physics and the hash the game names it by) and
   `surfaceproperties_game.txt`, and writes them to `reference/surfaces/`
   (`surfaces.csv`, and `surfaces.md` resolved); `SurfaceProperties` reads
   them and `Penetration` takes its numbers and parents from it instead of the
   hand-typed table and the guessed parents. The 84 copied numbers (for 78
   surfaces) matched the game's file exactly; the parents did not. On dust2's
   hull that moves the dumpsters (`metal_dumpster`, which takes a metal
   barrel's 0.01 and stops a round), the trees (`Wood_Tree`, dense wood: 0.5
   and 0.3, not 0.9 and 0.6), carpet (dirt's damage, 0.3 not 0.5) and plastic
   (a plastic box's reach, 0.75 not 0.5); off it, chains, gravel and stucco.
   Two parts were misnamed on the way in and are right now: the railings,
   which Source 2 Viewer writes as `vrf_unknown_key_2838185980` because it has
   no name for them, are `metalrailing` by that hash
   (`SurfaceProperties.by_hash`), and the second of two parts of one surface,
   which Godot numbers (`physics_group_wood_plank2`), is its surface and not
   the word before (wood). The dust2 checks hold every part of the hull, by
   the name the game passes on, to the CS2 surface of its own name.
7c. **Surfaces per triangle.** *(Local, then Remote)* The hull's physics gives
   a surface to each triangle as well as to each shape, and the export keeps
   only the shape's: dust2's ground mesh comes out all `concrete`, though of
   its 175,380 triangles 9,107 are sand, 3,501 gravel, 3,081 dirt, 1,641 tile
   and 3,615 default; the wood mesh carries 1,326 plastic ones. Penetration
   and footsteps take those patches as concrete and wood. The indices are in
   the physics block (`Source2Viewer-CLI -b PHYS` on `world_physics.vmdl_c`:
   each mesh's `m_Materials`, one a triangle, into `m_surfacePropertyHashes`);
   extract them beside the hull and split each collision mesh by surface at
   import.
8. **Set `recoil_scale` from a measurement (Sid).** *(Local)* The spray's overall size
   is the one estimate left in the recoil model (it assumes the AK climbs 16
   degrees). Spray a wall in CS2 from 496 units and compare it with the
   range's degree-lined wall. A community recoil tool's patterns (2026-09-24,
   `reference/spray_patterns/README.md`) put the AK's climb at 11.7
   degrees, which would make `recoil_scale` 0.73; the measurement decides.
9. **Weapon numbers from the CS2 Weapon Spreadsheet.** *(done, PR #23)*
   Every number the firing model uses was read from the sheet, now in the
   repo: damage, armour, falloff, magazine (M4A1-S 20), inaccuracy, recovery
   and landing. Since PR #28 the game's own weapons.vdata (`WeaponVData`)
   replaces every one it has, which is all but landing and ladder. Taps now
   recover the way CS's do instead of carrying on down the pattern, a held
   trigger fires at exactly 600 RPM, and movement inaccuracy follows CS's
   curve. `reference/weapons/README.md` explains the sheet column by column.

### Every gun (new, 2026-09-22)

Sid widened the scope to every gun in the sheet.
`reference/weapons/TODO.md` in the repo is the list, split into what needs
Sid's machine (extracting models, animations and sounds, measuring reloads,
spray patterns, fitting, playtests) and what a cloud thread can do (a weapon
registry off the sheet, semi-auto, modes, scopes, shotguns, slots, buy menu,
tracers). The extraction is done (L1 to L5, 2026-09-22): every gun's model,
animations and sounds, and the game's own tuning and timings in
`reference/weapons/`. The registry can start in a thread at once, taking its
numbers from `WeaponVData`.

### Every CS2 system (new, 2026-09-22 21:40)

Sid: buying and money are in, "just like in CS2", and the game needs every
system CS2 has. `reference/cs2-systems.md` in the repo maps each one: CS2's
rules and numbers (from Valve's own config and weapon files where they
exist), what is built, and the Local and Remote work. The phases below put
them in order. Settled by Sid's message: the bomb is in (so dust2 plays as
dust2), and the economy and buy menu are in. Taken as the default because
he asked for CS2's systems: 5 v 5, with bots filling the empty places.

### Rendering (new, 2026-09-24)

Sid: dust2 runs poorly at 1920x1080 here, where CS2 plays it at 3840x2160
and about 180 frames a second on his RTX 4070 Ti, and lighting and shaders
should look and run as well as Source 2's. `reference/rendering.md` is the
list, split into Local and Remote items, with the measurements.

- **The profiler (R1).** *(done, PR #78)* Draws dust2 from eight fixed views
  and switches one feature off at a time.
- **The skybox behind the map by its vertices (R2).** *(done, PR #78; Sid
  re-runs the profiler)* Writing its depth per fragment cost 0.8 ms at 1080p
  and 3.2 ms at 4K.
- **Occlusion culling (R3).** *(done, PR #78, from the collision hull; Sid
  walks long doors and top of mid again)* The camera's pass went from about
  1,170 draw calls to 290.
- **The sun's shadows as CS2 draws them (R4).** *(first tier built, PR #82;
  the pages extracted and checked 2026-09-25; Sid plays and profiles,
  rendering.md L7)* The map's shadow from
  the sun comes from CS2's baked pages: `direct_light_shadows` on its
  surfaces, and the probe atlas's `_dlshd` on everything the probes light,
  players, dropped guns, grenades and the bomb among them. The 3D skybox
  reads its own page. The live shadow
  map draws only what moves; drawing the map into it cost 2.0 ms of GPU at
  1080p, 6.3 ms at 4K and 1.7 ms of the renderer's CPU, from 6,200 draw
  calls a frame. Next, if the playtest wants crisper edges up close: a
  static shadow map of the map, rendered once at load, since dust2 ships
  none (L6).
- **Research CS2's renderer (R0), reflections from the map's cubemaps (R5)
  and CS2's video settings (R6).** *(Remote, not started)*

### Phase 3: split the game from the player (the ground for multiplayer)

10. **Simulation apart from input and drawing.** *(done, PR #24; Sid said yes, 2026-09-22 21:57)*
    Multiplayer is now on the list, and it is far cheaper to build every
    system below as server-side state that the screen only draws than to
    rewrite each one later. `PlayerController` today reads input, simulates
    and draws in one node. Split it: a simulation that takes numbered input
    commands (the sub-tick ones already exist) and a view that draws it.
    Single player becomes that simulation running inside the game with bots,
    the way CS2's offline mode is a listen server. Done: see "Simulation and
    view" in part 1. The match state came with phase 4 (item 11), and the
    world that owns the tick and the players (`GameWorld`,
    `reference/systemization.md` finding 1) on 2026-09-23; still to come is
    the server around it (phase 9).

### Phase 4: a match of rounds

11. **Match and round flow.** *(done, PR #40)* Warmup, freeze time 15 s, round time
    1:55, MR12 with the side swap, overtime, no respawn, spectating
    teammates, friendly fire at CS2's reductions, solid teammates. Replaces
    the 3 s respawn. Done: `MatchState` (`src/match/`) runs it as server
    state on the tick, with CS2's numbers in `MatchRules`: 120 s of warmup
    with respawns (F5 ends it, as `mp_warmup_end` does), 15 s of freeze time
    (look, duck, reload; no moving, jumping or firing), 1:55 rounds won on
    eliminations or by the CTs on time, 7 s between rounds, the side swap
    with 15 s of half time and the score kept by the team, the clinch at
    13, one MR3 overtime at 12-12 without a swap into it, and 15-15 a draw.
    Survivors keep their armour and weapon and are healed; the dead and
    everyone after a swap start fresh. Dead in a round, after 2 s you watch
    a living teammate, from their eyes or behind them (fire: next, jump:
    switch). A teammate's round does 33%. Hulls are solid to each other.
    dust2 plays five a side, bots in every place but yours. Since
    2026-09-23 the match says what the round is doing as CS2's game events
    (`round_announce_warmup`, `begin_new_match`, `round_prestart` handed
    out before anyone spawns, `round_start`, `round_freeze_end`,
    `round_end`, `announce_phase_end`, `cs_win_panel_match`), which the
    economy, the bomb, the grenades and what lies on the ground go by; a
    planted bomb stops the clock and a dead T side from ending the round,
    and its blast or defuse ends it. A spawn from nothing is CS2's: the
    knife and the side's pistol (the Glock-18, the CTs' P2000), no armour
    (`mp_free_armor 0`). A grenade does 85% to the thrower's side in
    dust2's match (`GrenadeRules.TEAM_DAMAGE_IN_MATCH`), all of it to the
    thrower. Left for the item that brings it: the round's full HUD (15).
    Guessed, not from CS2: both sides wiped out on one tick goes to the Ts,
    and half time's 15 s replaces the 7 s pause rather than following it.
12. **Inventory.** *(done 2026-09-23 but for E to swap and guns on the
    ground as physics objects; Sid checks it on the range)* Slots, switching
    with draw times, dropping (G), picking up and swapping, drops on death.
    `Inventory` with CS2's carrying rules, slots, Q and cycling grenades,
    each gun its own `Weapon`; `DroppedItem` and `ItemDrops` for dropping,
    picking up and drops on death (`reference/systems/contracts.md`). Every
    player carries one (you and the bots, `player_sim.gd`): a spawn's knife
    and pistol (in a match; the range hands out its gun), 1 to 5 and Q, the item's draw time and
    speed on every switch, a switch stopping a reload, G dropping what is in
    hand, a grenade thrown from the hand, and each item's first-person model
    built once and kept while carried, so a switch builds nothing. The
    dropped guns are drawn (`DroppedItemView`, the range and dust2). Since
    2026-09-23 a drop is thrown from the hand as it was held (`HeldPose`:
    CS2's hold from its third-person clips, measured level and turned with
    the aim's pitch, from where the player stands and looks), at CS2's
    300 u/s where they look, turning as it flies,
    bouncing, and laid on its side where it stops; a death lets the gun go
    from the hand, moving as the body was. Left: E to swap with the gun in
    hand, and a gun on the ground as a rigid body that blasts and rounds
    push, on its own physics hull (`reference/cs2-systems.md` section 4).
12a. **Binds: the same keys everywhere, the test range included.** *(Remote;
    Local wires section 5's keys through it and checks CS2's defaults; new
    2026-09-24, Sid: "Ideally the same keys are used everywhere even in
    testing")* One table maps a key to a command, as CS2's `bind "g"
    "drop"`, starting from CS2's own defaults
    (`game/csgo/cfg/user_keys_default.vcfg`) with Sid's two departures,
    the wheel's jump and noclip on V. A `+` command is a held button in the
    next `UserCmd`; any other goes to `game.command` or runs on the client,
    so keys never reach the simulation. The range's and the developer's
    actions become named commands (CS2's names where it has them: `god`,
    `mp_warmup_end`, `give`) in a second table that uses only keys CS2
    leaves unbound, and dust2 can load it too. Nine test keys have to move
    because CS2 uses them: G (never-die, CS2's drop), H, T, M, U, I, Y, F3
    and F5; and 5, Q, Z and X, the bomb's and the grenade lane's stand-ins,
    retire when the inventory and the throw are in the player. Checks: the
    defaults equal CS2's file, no key bound twice, every bound command
    exists, a key gives the right button or command, and nothing else reads
    a key. The table, the moves and each key's new place are in
    `reference/binds.md`. Best before section 5's wiring adds G, E and Q,
    so they go in once; rebinding waits for the settings page (26) and the
    console (`reference/systemization.md` step 4).
    *(The keys section 5 wired went in first, in `PlayerInput`, with the
    inventory (item 12): G `drop`, E `+use`, MOUSE2 `+attack2`, 3 to 5
    and Q `lastinv`, and the throw from the hand, which retired the 5, Q,
    Z and X stand-ins; the never-die moved off G to `[`. The table takes
    them over.)*
13. **Economy.** *(done 2026-09-23, Remote; wired into dust2 with the
    GameWorld; Local E1 checks three guesses)* $800 start, $16,000 cap, round
    rewards, the loss ladder that a win steps down by one, plant and defuse
    rewards, kill awards from the game's own `m_nKillAward`, half time and
    overtime money. `Economy` (`src/economy/`) is a system on the shared
    contracts, paid by game events; every number and guess is in
    `reference/systems/economy.md`.
14. **Buying.** *(done 2026-09-23 but for choosing a loadout, Remote; on the
    test range now, on dust2 with the GameWorld; Local E2 measures the
    guesses)* Buy zones and 20 s of buy time, CS2's buy menu (B, then a
    column and an item by number, or the mouse), undoing a purchase, the
    default loadout, armour and the helmet, the kit, grenades, the Zeus,
    team-only weapons. On dust2 since 2026-09-23: its own buy zones (or a
    stand-in round each side's spawn where they are not extracted, which
    the map says), your money and "B  buy" with the time left on the HUD,
    and why B does nothing when it does not open; warmup's $16,000; a gun
    bought taken in hand. Still to do: choosing another loadout (a settings
    page).
15. **HUD for rounds.** *(Remote; the radar is extracted, `MapOverview`)*
    Money, armour, timer, score and players alive, kill feed, radar,
    scoreboard, round-end panel.

### Phase 5: the bomb

16. **Plant, timer, defuse, explosion.** *(Remote part built 2026-09-23 in
    `src/bomb/`, on the test range (5 takes the bomb out and the attack
    button plants it, E defuses, L the kit, all through your commands);
    in dust2's match since 2026-09-23 (its two sites, the map's own blast
    radius, the round ending on the blast or the defuse); the HUD is next,
    as `reference/systems/bomb.md` sets out; the plant time, defuse reach and
    beeps are guesses until C1)* *(Local measures,
    then Remote; the bomb and the kit are extracted)* One T carries it; plant in a site; 40 s
    with beeps; defuse 10 s or 5 with a kit; the explosion (CS2 reworked it
    in July 2026 into a shockwave with damage baked per map: dust2's is
    `baked_bomb_damage.vdata`, extracted, its damage values not yet worked
    out). The site volumes are read (`BrushVolume.bomb_sites`).

### Phase 6: grenades

17. **Throwing.** *(done on the range, the grenades PR, and from the hand
    since 2026-09-23: 4 takes one out, the attack buttons pull the pin and
    throw on letting go; on dust2 too since 2026-09-23, bought from the
    menu, the map cleared of them at each round's start; Local measures, G1)*
    Three throw strengths, your velocity added, bounces off the hull. The
    grenade clip is still left out of the hull on import
    (`reference/systems/grenades.md`, item 6).
18. **HE, flashbang, decoy.** *(done on the range, the grenades PR; Local
    measures G2, G3, G5 and extracts the particles)*
19. **Molotov and incendiary.** *(done on the range, the grenades PR; Local
    extracts the particles)* Flames spreading over the ground, put out by
    smoke.
20. **Smoke.** *(done on the range, the grenades PR; Local measures G4 and
    extracts the particles)* CS2's volumetric smoke: a voxel fill through
    the map, HE and bullets opening holes, blocking sight for players and
    bots. Bots' sight asks it once `bot.gd` does
    (`reference/systems/grenades.md`, item 4).

### Phase 7: knife and Zeus

21. **Knife and Zeus.** *(Local measures, then Remote; both are extracted)*

### Phase 8: bots that play CS

22. **Navigation.** *(done 2026-09-23, Remote; Sid checks it on dust2.
    Local: the mesh's analysis still to read)* Bots walk dust2's own nav
    mesh (`scripts/extract_assets.sh nav`, read by `SourceNavMesh`, PR #32).
    `SourceNavMesh.walk_path` takes `find_path`'s route and pulls it taut
    (the funnel algorithm, turning 10 units in from the corners of the edges
    it crosses), keeping each jump's take-off and landing; a bot walks it
    through its commands, as a player would, jumping (with a crouch in the
    air) where a link rises past a step, crouching before an area marked
    for a low ceiling, and finding its way again when it is held up. On
    dust2 each bot walks from its spawn to a bomb site and back, A and B in
    turn (`bots_walk_to_sites`; off, they walk their spawn points as
    before). Without the mesh they walk straight lines between their spawn
    points, and the map says so in the top left. Still unread: the file's
    analysis of the mesh (hiding spots, where the sides meet, how early
    each team reaches each area; `reference/cs2-systems.md` N3), which
    item 23 wants.
23. **Behaviour beyond "see and shoot".** *(Remote)* Cover, holding angles,
    counter-strafing, reacting to sound, flinching. The two difficulty knobs
    (reaction time and aim error) stay the honest way to set difficulty.
24. **Playing the round.** *(Remote; Local records grenade lineups)* Bots on
    both sides fighting each other, buying to a plan, planting, rotating,
    retaking and defusing, throwing known smokes and flashes, getting out of
    fire. *(Smoke hiding players from bots and flashes blinding them done
    2026-09-24: `Bot.can_see`, `Bot.is_blind`.)* *(CS2's stock buying done 2026-09-23: `BotBuying`, from its
    convars and `botprofile.db`, `reference/systems/economy.md`. A team's
    plan (full buy, force, save) is still to do, beyond CS2's own bots.)*

### Phase 9: multiplayer

24a. **Game modes apart from maps.** *(done 2026-09-24, Remote; Local checks
    below; `reference/systemization.md` finding 11 and step 4)* A map is
    loaded by name and a mode runs on whatever map is loaded, so any CS2
    defusal map the extraction has taken plays in competitive, not only
    dust2. `scripts/extract_assets.sh` takes the map's name after each of a
    map's steps (`map de_mirage`; de_dust2 when there is none; dust2's
    paths unchanged); `MapLoader` (`src/map/map_loader.gd`) derives every
    path from the name (`MapPaths`), loads the map, its lighting, its sky
    (from the map's own sky material), its skybox, entities and nav mesh,
    and says what is missing; `Competitive` (`src/modes/competitive.gd`)
    sets up you, the bots, the match, its systems, the HUD and the views,
    and F5, reading the map only through `MapContents`. Bots walk to the
    `BombsiteA` and `BombsiteB` callouts, or to the bomb sites' volumes
    where a map names its callouts otherwise. The map is chosen by
    `map_name` on `maps/play/play.tscn` or `--map` on the command line;
    `maps/de_dust2/de_dust2.tscn` is that scene set to dust2. No research
    page covers other maps. **Local** (Sid, 2026-09-24): `scripts/run_tests.sh`
    with the assets passed (1781 checks, dust2's 78 among them); dust2 on
    the play scene finds its sky from the env_sky material; de_inferno,
    extracted with `map de_inferno`, loads in 16 s with nothing missing
    (16 spawns a side, 2 buy zones a side, both sites, bomb radius 600,
    a nav mesh of 2738 areas) and its bots took the callout route and
    fought for 100 s. Still open: extract and play de_mirage. **Still to
    do**, each its own item: the test range as
    a mode; ladders (the nav mesh reads them, nothing climbs them); doors
    and breakables; hostage maps (a mode of their own); a dedicated server,
    a mode that loads the map's collision, entities and nav mesh and builds
    nothing to be seen (part of item 25).
24b. **What de_inferno showed** (Sid's local test of 24a, 2026-09-24; none
    of these comes from 24a):
    - *Bots stall.* *(Remote, then Sid plays it)* 5 of 9 stood still for
      about 60 s of a live round, alive and not fighting (1 on dust2). Two
      Ts at A stop at (221, 232, 2030), 68 units above their site floor
      (292, 164, 2000) and 77 away in plan; two CTs back from B jam
      together at (2579 to 2611, 128, 2008), one jumping; a CT back from
      A stops at (1493, 205, 2442), a spot it passed on the way out.
      Doors and func_brush blockers are ruled out.
    - *Café tables, chairs and signs draw solid black.* *(Local finds the
      cause, then Remote)* They have textures; `prepare_export` warned
      that inferno's world and skybox glTFs have a primitive with both
      blend paint and vertex colour, which it leaves alone. Unconfirmed
      as the cause. dust2's windows were black the same way for another
      reason (2026-09-24): a prop merged from copies all over the map was
      lit by the probes at the middle of its box, inside a building, and
      is now lit from its own vertices (`ProbeMaterials.cube_for`); worth
      a look at inferno's café again.
    - *No sky panorama on inferno.* *(Remote for the warning; the fix
      waits on Source 2 Viewer)* CS2 1.41.8.3 ships VCS 72 shaders and
      Source2Viewer-CLI 20.0 reads 59 to 71, so its env_sky material
      (`materials/skybox/test/s2_de_inferno_sky01.vmat_c`) did not
      decompile and 4284 textures failed. `extract_assets.sh` should warn
      when Source 2 Viewer prints "Only VCS file versions". The same gap
      costs every colour texture exported since its alpha: dust2's 3D
      skybox, exported again on 2026-09-24, drew its palm and bush cards
      whole. *(Done 2026-09-24 for the alpha: the extraction decompiles
      those textures again on their own, which keeps it; the panorama
      still waits.)* Support is on Source 2 Viewer's master since
      2026-09-23; export again with the release that has it.
    - *The first import fails to compile `prepare_export.gd`.* *(Remote)*
      On a fresh checkout `lightmap_materials.gd:75` names `BlendMaterials`
      before any import has registered the class names, so the first
      `map <name>` skips the lightmap average (`average.json`) until the
      next import. Loading `BlendMaterials` by path there should fix it.

25. **Netcode.** *(Remote; Local playtests across machines)* CS2's model: the
    server decides, clients send input with sub-tick times and predict their
    own player, everyone else is drawn between snapshots, and a shot is
    checked against what the shooter saw (up to 200 ms back). Godot's ENet gives
    the transport; prediction, snapshot buffering and the rewind are built on
    it. A dedicated server build, and connecting by address. What each part
    will cost, and what to settle before it (a server that builds nothing to
    be seen; hitboxes posed by the tick, and their history kept as capsules),
    is in `reference/performance.md`. The tick rate is settled: 64.

### Phase 10: a game you can hand to someone

26. **Menus and settings.** *(Remote)* Main menu, pause, host and join, team
    select, and settings for sensitivity (already in CS2's units), crosshair,
    viewmodel, rebinding the keys of item 12a's table, audio and video.
27. **An exported build** *(Local)*, so a playtest does not need the editor.
    The extracted assets stay outside it.

### Movement: what is still open

These do not block anything above; they are feel checks.

- **Measurements in CS2 (Sid):** *(Local)* standing jump height, crouch-jump reach, and
  whether the dead-strafe zone feels right. The movement fixes that change
  them have landed, so they can be measured now.
- **Per-surface friction.** *(Local done 2026-09-23: the table is extracted,
  `SurfaceProperties.player_friction`; Remote: feed it in)* `MovementSolver`
  takes a surface friction and is always handed 1.0 on the ground. Source
  gives a player the surface's physics friction times 1.25, at most 1
  (`CGameMovement::CategorizeGroundSurface`), and scales ground friction and
  acceleration by it. On dust2 that is all of it everywhere but glass (0.625)
  and pottery (0.5); the part under the player's feet is what `Footsteps`
  already finds, and `Penetration.surface_for` names its surface.
- **Surf ramp ends** (parked by Sid). *(Remote)* The course cannot reproduce the
  complaint yet because its ramps have no end to launch off.

### Housekeeping

All Remote, except the real ragdoll data, which needs extracting locally.

- *(done 2026-09-23)* `tests/probe_release.gd.uid` had no script beside it;
  removed.
- *(done 2026-09-23)* CI: `.github/workflows/tests.yml` runs
  `scripts/run_tests.sh` with a headless Godot 4.7.2 on every pull request
  and push to main; the runner now runs every test file and sums them up
  (step 0 of `reference/systemization.md`).
- CS2's own ragdoll data is not extracted; the ragdoll uses the hitbox
  capsules. Swapping in the real one is optional polish.

---

## Waiting on Sid

| | What | Unblocks |
|---|---|---|
| Hands | Spray a wall in CS2 from 496 units | Item 8 |
| Hands | Measure jump height, crouch-jump reach, dead-strafe feel | Movement check |
| Hands | Check on the range that the shooting bot stays upright while firing, and that the dummy's ragdoll and your own settle without spinning (PR #30) | Confirms PR #30 |
| Hands | Extract CS2's blood impact effects and decals | Item 5 |
| Hands | Check that first shots at a run now miss (PR #24) | Item 9 |
| Hands | Play being shot on the test range (B, U, Y, J, T) and dust2: your capsules' fit, the tag, the flinch, the hit arcs (PR #27) | Items 1 to 4 |
| Hands | Measure a tag's length and the flinch's size in CS2 | Item 4a |
| Hands | Shoot through dust2's walls in CS2 with `sv_showimpacts_penetration 1` and note the damage | Item 7a |
| Done | CS2's surfaces extracted and read (`SurfaceProperties`): penetration's parents from the game, the friction table | Item 7b, per-surface friction |
| Hands | Carry the hull's surfaces per triangle through the export (dust2's ground is not all concrete) | Item 7c |
| Hands | Play wall penetration on the test range (M) and dust2 | Item 7 |
| Done | The every-gun extraction (weapons TODO L1 to L3), and reload, draw and zoom figures from the game's own data (L5) | Every gun: `reference/weapons/models.md`, `sounds.md`, `timings.md`, `vdata.md` |
| Done | dust2's buy zones, bomb sites and callout volumes, its radar, and its baked bomb damage file (cs2-systems B1, B3, C2; PR #34) | Phases 4 and 5 |
| Done | dust2's nav mesh, extracted and read (`SourceNavMesh`), checked against the hull, the spawns and the callouts (PR #32) | Phase 8 |
| Done | The equipment's extraction: the bomb and the kit, the six grenades, the default knives and the Zeus, with the game's numbers and their clips' timings (cs2-systems C3, G6, K2) | Phases 5 to 7 |
| Hands | The systems' Local list for bots in `reference/cs2-systems.md`: read the nav mesh's analysis (N3), record grenade lineups (N2) | Phase 8 |
| Decided | The game's own numbers win over the sheet's wherever the game has them (Sid, 2026-09-22), the Desert Eagle's jump inaccuracy included (46.75, not 378.30) | `WeaponVData`, every gun |
| Hands | List CS2's binds on a fresh config (`key_listboundkeys`) to confirm the defaults file | Item 12a |
| Hands | The systems' Local list in `reference/cs2-systems.md`: bomb (C1, the explosion's particles from C3, and decoding C2's damage), grenades (G1 to G5, and G6's particle and smoke textures), knife (K1), sounds (S1, S2) | Phases 4 to 7 |
| Hands | Run `scripts/profile_render.gd` again at 1080p and 4K, and walk long doors and top of mid, on PR #78 | Rendering R2, R3 |
| Decided | dust2's sun shadows come from CS2's baked pages, the live shadow map drawing only what moves (Sid, 2026-09-25) | Rendering R4 |
| Hands | Run the dust2 checks again, play dust2's shadows beside CS2's, and profile with `live_map_shadows` and `no_visibility`, on PR #82 (rendering.md L7; the pages were extracted and checked 2026-09-25) | Rendering R4 |

---

## Later (past the current scope)

- The CS2 features nobody has asked for yet, listed at the end of
  `reference/cs2-systems.md`: pings and radio, voice and text chat, votes,
  other modes, demos, anti-cheat.
- More maps.
- Original assets in place of Valve's, if the game is ever sold.

---

## The order in one line

The game is split from the player first (Sid chose server-side from the
start, and tagging and aim punch are simulation too, so they are built on
the split rather than before it); then being shot feels right and the
shooting model is finished; then a match of rounds with money and
buying, the bomb, grenades, the knife and Zeus, bots that play the round,
multiplayer, and menus with a build. Every gun runs alongside all of it.
The split is done (PR #24) and being shot is in apart from blood and the
third-person firing layer (PR #27), and wall penetration is in (PR #31),
so what is left of the shooting model is measuring (7a, 8).

`reference/systemization.md` (2026-09-23) plans the shared systems these
items should be built on, in five steps: the world that owns the tick
(done, 2026-09-23), an item registry, damage that records its attacker and
game events come before items 12 and 13, and a third-person presenter,
hitboxes posed by the tick and bots as brains come before the bomb and
grenades.

What a thread can start now: what is left of the inventory (item 12: E to
swap, guns on the ground as rigid bodies); the bind table (12a), taking over
the keys the inventory put in `PlayerInput`; from the weapons todo, the
game's recovery fields (R13); the
third-person firing layer (item 6), then the shadow's arms (6a); and the
housekeeping.
