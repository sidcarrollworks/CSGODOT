# CSGODOT roadmap

Written 2026-09-22 off `main` at `173a35e` (PR #21), read from the code rather
than from notes, brought up to date with PRs #23 to #25 at 23:00, and
with PR #27 (phase 1's Remote items: being shot) on 2026-09-22. It
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

## Part 1: what exists

### Movement
- Source SDK 2013's movement ported line by line: acceleration, air
  acceleration, friction, collide-and-slide, step move, at a fixed 128 Hz in
  Source units (`src/movement/`).
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
  (Phoenix and SAS) on the locomotion rig with eight-way clips.

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
- The player has health and armour, dies, and is back at spawn after 3 s.
- Bots die into a ragdoll built from their capsules, back on their route
  after 5 s.
- Bullet holes from the game's own decal materials, per surface, with impact
  sounds.

### Bots
- Two bots of the other side, on the player's own body and movement solver.
- They walk their spawn points in a loop, see the player (3000 units,
  75-degree half cone, line of sight, 0.5 s reaction), turn, and fire bursts
  through the same simulation and trigger path as the player, with 1.2
  degrees of extra aim error. They target only the other side.

### Sound
- The game's own sounds: weapon shots, reload and draw, hit sounds (kevlar,
  headshot, kill), footsteps and landings per surface, impact sounds.

### HUD
- Crosshair, health, armour, ammo, death countdown, the movement tuning
  readout, and where you stand and look in the top left (PR #25, F3 hides
  it).
- A red arc round the crosshair on the side each hit came from (PR #27).
- On the test range, a shooter that fires at you on B, with its weapon (U),
  your armour (Y) and never-die (J) switched, a readout of your tag and
  flinch, and a window on your own hitboxes (T) (PR #27).

### Tooling
- `scripts/extract_assets.sh` (map, physics, weapons, characters, sounds and
  more), `inspect_assets`, and `run_tests.sh` with seven headless test files
  (movement, map, dust2, model, weapon, range, simulation): 530 checks pass
  without the assets.

---

## Part 2: what is left, in order

Each phase can start once the one before it is in, except where noted.
Items marked **(Sid)** need Sid's machine or a decision from him.

### Phase 1: make being shot feel like CS2

This was the unfinished half of hit registration. Items 1 to 4 are in (PR
#27); blood and the third-person firing layer are left.

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
6. **Firing on the third-person model.** *(Remote; Sid checks it)* `PlayerModel` still says "Nothing is
   layered, so firing does not show yet": a bot kills you without its arms
   moving. Needs the upper-body layer over the locomotion clip.

6a. **Your shadow has no arms.** *(Remote; Sid checks it)* Sid noticed
   2026-09-22 22:06. The shadow twin (commit f42114e) put the head back but folds the
   arms on purpose (`SHADOW_FOLDED_BONES` in `player_view.gd`), because
   arms in the locomotion pose would fall across the view model's. It is also
   built with no weapon (`model.setup(team, "")`). CS2's shadow is the
   third-person body, arms and gun included, so: unfold the arms, give the
   shadow the weapon's world model, and pose its upper body from the
   third-person firing layer (item 6).

### Phase 2: finish the shooting model

7. **Wall penetration.** *(Remote)* `Hitscan` is one ray and stops at the first thing it
   hits. CS2 shoots through wood, thin metal and dust2's doors and boxes, and
   players do it on purpose. The spreadsheet gives both rifles 200%
   penetration power. The collision hull already names each surface,
   so a per-surface penetration table can hang off that.
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

11. **Match and round flow.** *(Remote)* Warmup, freeze time 15 s, round time
    1:55, MR12 with the side swap, overtime, no respawn, spectating
    teammates, friendly fire at CS2's reductions, solid teammates. Replaces
    the 3 s respawn.
12. **Inventory.** *(Remote; Local extracts world models)* Slots, switching
    with draw times, dropping (G), picking up and swapping, drops on death.
13. **Economy.** *(Remote)* $800 start, $16,000 cap, round rewards, the loss
    ladder that a win steps down by one, plant and defuse rewards, kill
    awards from the sheet.
14. **Buying.** *(Remote; Local extracts the buy zones and icons)* Buy zones
    and 20 s of buy time, the buy menu, undoing a purchase, the loadout,
    armour, the kit, grenades, the Zeus, team-only weapons.
15. **HUD for rounds.** *(Remote; Local extracts the radar)* Money, armour,
    timer, score and players alive, kill feed, radar, scoreboard, round-end
    panel.

### Phase 5: the bomb

16. **Plant, timer, defuse, explosion.** *(Local measures and extracts,
    then Remote)* One T carries it; plant in a site; 40 s with beeps; defuse
    10 s or 5 with a kit; the explosion (CS2 reworked it in July 2026 into a
    shockwave with damage baked per map, which the local agent looks for in
    dust2's files). The site volumes come out of the map with the buy zones.

### Phase 6: grenades

17. **Throwing.** *(Remote; Local measures)* Three throw strengths, your
    velocity added, bounces off the hull and the grenade clip.
18. **HE, flashbang, decoy.** *(Remote; Local measures and extracts)*
19. **Molotov and incendiary.** *(Remote; Local measures and extracts)*
    Flames spreading over the ground, put out by smoke.
20. **Smoke.** *(Remote; Local measures and extracts)* CS2's volumetric smoke:
    a voxel fill through the map, HE and bullets opening holes, blocking
    sight for players and bots. The biggest single item in the game.

### Phase 7: knife and Zeus

21. **Knife and Zeus.** *(Local measures and extracts, then Remote)*

### Phase 8: bots that play CS

22. **Navigation.** *(Local: the mesh extracted and read 2026-09-22, its
    analysis still to read; Remote next)* Bots walk straight lines between
    spawn points. dust2's own nav mesh is extracted (`scripts/extract_assets.sh
    nav`) and read (`SourceNavMesh`): 2,242 areas and their links, jumps and
    drops marked, with `route` and `find_path` between any two points; the
    dust2 checks walk both spawns to both sites on it, through no walls.
    Remote: bots follow `find_path`, pulled taut (it runs through edge
    middles), crouching where an area says so and jumping where a link rises
    past a step. Still unread: the file's analysis of the mesh (hiding spots,
    where the sides meet, how early each team reaches each area;
    `reference/cs2-systems.md` N3).
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
    it. A dedicated server build, and connecting by address.

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
- **Per-surface friction.** *(Local extracts the table, then Remote)* `MovementSolver` takes a surface friction and is
  always handed 1.0 on the ground. CS2's `surfaceproperties.vsurf` has the
  table; extract it and feed it in. Small, and mostly felt on dust2's few
  slick surfaces.
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
| Hands | Playtest the range dummy and ragdoll on current assets | Confirms PR #20 |
| Hands | Check that first shots at a run now miss (PR #24) | Item 9 |
| Hands | Play being shot on the test range (B, U, Y, J, T) and dust2: your capsules' fit, the tag, the flinch, the hit arcs (PR #27) | Items 1 to 4 |
| Hands | Measure a tag's length and the flinch's size in CS2 | Item 4a |
| Done | The every-gun extraction (weapons TODO L1 to L3), and reload, draw and zoom figures from the game's own data (L5) | Every gun: `reference/weapons/models.md`, `sounds.md`, `timings.md`, `vdata.md` |
| Done | dust2's nav mesh, extracted and read (`SourceNavMesh`), checked against the hull, the spawns and the callouts | Phase 8 |
| Hands | The systems' Local list for bots in `reference/cs2-systems.md`: read the nav mesh's analysis (N3), record grenade lineups (N2) | Phase 8 |
| Decided | The game's own numbers win over the sheet's wherever the game has them (Sid, 2026-09-22), the Desert Eagle's jump inaccuracy included (46.75, not 378.30) | `WeaponVData`, every gun |
| Hands | The systems' Local list in `reference/cs2-systems.md`: buy zones and bomb sites (B1), radar (B3), bomb (C1 to C3), grenades (G1 to G6), knife and Zeus (K1, K2), sounds (S1, S2) | Phases 4 to 7 |

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
third-person firing layer (PR #27), so finishing the shooting model is
next; the housekeeping can start today; phase 8 can start, the nav mesh
being read.
