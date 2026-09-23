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
- Test range: a wall ruled in degrees at 496 units, spray export to CSV, and
  a dummy wearing CS2's own hitboxes with a hit log, damage numbers, armour and
  distance switches, a never-die mode and a ragdoll death (PR #20).

### Map and art
- dust2 extracted from Sid's CS2 install and imported: visible world, the
  game's own collision hull, player clips (which stop players and not rounds,
  PR #21), entity lump, blend layers, sky, 3D skybox.
- Lighting from the map's own numbers: sun, fog, exposure, the baked
  lightmaps for bounce light, light probes for props, players and arms.
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
  third-person clips, over the upper body (item 6).

### Sound
- The game's own sounds: weapon shots, reload and draw, hit sounds (kevlar,
  headshot, kill), footsteps and landings per surface, impact sounds.

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
   Left: CS2 blends the weapon layer in model space, Godot in each bone's
   own, so the upper body follows the hips here; and the flinches, additive
   too and ready to go in the same way, are not extracted yet (the
   characters step takes only the deaths from `world/shared/`).

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
   range's degree-lined wall.
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

### Phase 3: split the game from the player (the ground for multiplayer)

10. **Simulation apart from input and drawing.** *(done, PR #24; Sid said yes, 2026-09-22 21:57)*
    Multiplayer is now on the list, and it is far cheaper to build every
    system below as server-side state that the screen only draws than to
    rewrite each one later. `PlayerController` today reads input, simulates
    and draws in one node. Split it: a simulation that takes numbered input
    commands (the sub-tick ones already exist) and a view that draws it.
    Single player becomes that simulation running inside the game with bots,
    the way CS2's offline mode is a listen server. Done: see "Simulation and
    view" in part 1. Still to come on it, with the systems that need them: a
    server that owns the players (phase 9), and the match state (phase 4).

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
    dust2 plays five a side, bots in every place but yours. Left for the
    items that bring them: the bomb's round ends and its stop on the clock
    (item 16, through `end_round`), money at half time and in overtime
    (13), the loadout a side really starts with, a pistol (12 and 14),
    grenades' friendly fire (17 to 20), and the round's full HUD (15).
    Guessed, not from CS2: both sides wiped out on one tick goes to the Ts,
    and half time's 15 s replaces the 7 s pause rather than following it.
12. **Inventory.** *(Remote; Local extracts world models)* Slots, switching
    with draw times, dropping (G), picking up and swapping, drops on death.
13. **Economy.** *(Remote)* $800 start, $16,000 cap, round rewards, the loss
    ladder that a win steps down by one, plant and defuse rewards, kill
    awards from the sheet.
14. **Buying.** *(Remote; the buy zones and icons are extracted and read,
    `BrushVolume.buy_zones`)* Buy zones and 20 s of buy time, the buy menu,
    undoing a purchase, the loadout, armour, the kit, grenades, the Zeus,
    team-only weapons.
15. **HUD for rounds.** *(Remote; the radar is extracted, `MapOverview`)*
    Money, armour, timer, score and players alive, kill feed, radar,
    scoreboard, round-end panel.

### Phase 5: the bomb

16. **Plant, timer, defuse, explosion.** *(Local measures, then Remote; the
    bomb and the kit are extracted)* One T carries it; plant in a site; 40 s
    with beeps; defuse 10 s or 5 with a kit; the explosion (CS2 reworked it
    in July 2026 into a shockwave with damage baked per map: dust2's is
    `baked_bomb_damage.vdata`, extracted, its damage values not yet worked
    out). The site volumes are read (`BrushVolume.bomb_sites`).

### Phase 6: grenades

17. **Throwing.** *(Remote; Local measures)* Three throw strengths, your
    velocity added, bounces off the hull and the grenade clip.
18. **HE, flashbang, decoy.** *(Remote; Local measures and extracts the
    particles; the grenades are extracted)*
19. **Molotov and incendiary.** *(Remote; Local measures and extracts the
    particles; the grenades are extracted)* Flames spreading over the
    ground, put out by smoke.
20. **Smoke.** *(Remote; Local measures and extracts the particles; the
    grenade is extracted)* CS2's volumetric smoke: a voxel fill through the
    map, HE and bullets opening holes, blocking sight for players and bots.
    The biggest single item in the game.

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
    fire.

### Phase 9: multiplayer

25. **Netcode.** *(Remote; Local playtests across machines)* CS2's model: the
    server decides, clients send input with sub-tick times and predict their
    own player, everyone else is drawn between snapshots, and a shot is
    checked against what the shooter saw (up to 1 s back). Godot's ENet gives
    the transport; prediction, snapshot buffering and the rewind are built on
    it. A dedicated server build, and connecting by address. What each part
    will cost, and what to settle before it (a server that builds nothing to
    be seen; hitboxes posed by the tick, and their history kept as capsules),
    is in `reference/performance.md`. The tick rate is settled: 64.

### Phase 10: a game you can hand to someone

26. **Menus and settings.** *(Remote)* Main menu, pause, host and join, team
    select, and settings for sensitivity (already in CS2's units), crosshair,
    viewmodel, binds, audio and video.
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

- `tests/probe_release.gd.uid` has no script beside it.
- The repo has no CI. A GitHub Action running `scripts/run_tests.sh` with a
  headless Godot would catch breakage from any of the agents pushing to
  `main`; the asset-dependent checks already skip themselves.
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
| Hands | The systems' Local list in `reference/cs2-systems.md`: bomb (C1, the explosion's particles from C3, and decoding C2's damage), grenades (G1 to G5, and G6's particle and smoke textures), knife (K1), sounds (S1, S2) | Phases 4 to 7 |

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

What a thread can start now: the inventory and economy (items 12 and 13),
on the match (item 11, done); from the weapons todo, the
registry of all 34 guns (R1), semi-automatic fire (R2), tracers (R10) and
the game's recovery fields (R13), with shotguns (R5) after it; the
third-person firing layer (item 6), then the shadow's arms (6a); and the
housekeeping.
