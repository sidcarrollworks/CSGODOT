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
Updated 2026-09-25: Sid's dust2 playtest, 22 issues with plans ("Playtest of 2026-09-25", `reference/playtest-2026-09-25.md`).
Updated 2026-09-30: grenade flight and lineups recorded for later (item 20a, Sid).

## Current status, 2026-10-03

Checked against merged `main` at `3d8aab6`, through PR #185. Completion
means the described implementation exists; measurements and remaining
parity work stay listed below. Three follow-up playtest PRs remain open.

| PR | Merged change |
|---|---|
| #159 | Stable freed-ragdoll regression check |
| #160 | Smooth jump transitions, camera/weapon dip and softer landing, accepted in Sid's competitive playtest |
| #161 | Dry-fire trigger clicks |
| #162 | Final standing/crouching spray recovery times |
| #163 | Ground-item E reach and gun/grenade/bomb pickup/swap prompts |
| #164 | Stable crouch speed and accuracy while turning |
| #165 | Usable knife, airborne attacks and corrected third-person clips |
| #166 | Round-end banner spacing, two title layers, slower background growth and narrower side fade |
| #167 | Nearby skybox terrain clipping and F11 rendering comparisons |
| #168 | Planting automatically crouches the planter |
| #169 | AUG/SG 553 framing, clear scoped lens, outside-lens blur and black lowered lens |
| #170 | Per-shell shotgun reloads and interruption by firing |
| #171 | Avoid repeated skeleton fitting for bodies that do not need it |
| #172 | Extracted current hit effects, contact-point mist, wounds, hit sounds and additive flinches |
| #173 | README gameplay/setup refresh |
| #174 | Documentation synchronized with the merged gameplay changes |
| #175 | Tab scoreboard with player statistics and round history |
| #176 | Current-build shooting audit and follow-up; formula/mode ports remain open |
| #180 | Current-build grenade throw, flight and fuse audit |
| #181 | Grenade collision audit, full sweep result and repeated-bounce time budget |
| #182 | Frame-consistency/performance audit and corrected profiling fixtures |
| #183 | Audited grenade strength/release, launch box, flight substeps and activation port |
| #184 | Exact jump-snapshot boundary, ordinary CS2 jump, sky collision classification, practice trails and crouch acceleration |
| #185 | Mirage extraction/import fixes and accepted Dust2 sky/world exposure calibration |

Pending review and local playtest, not part of merged `main`:

| PR | Follow-up |
|---|---|
| [#177](https://github.com/sidcarrollworks/CSGODOT/pull/177) | Free spectating, bot takeover and firing/throwing in noclip |
| [#178](https://github.com/sidcarrollworks/CSGODOT/pull/178) | Startup team selection |
| [#179](https://github.com/sidcarrollworks/CSGODOT/pull/179) | Feet planted while walking on slopes and stairs |

The next implementation is shared terrain-aware simulation eye state,
used by the camera and grenade snapshots. The movement section below
records its validation and the subsequent integration/transition work.

## Part 1: what exists

### Movement and simulation

- Source movement in inches at 64 Hz: acceleration, air strafing,
  collide-and-slide, step-up, crouch jumps and bunny hops. Crouch speed
  stays at the held item's crouched top while turning. PR #184 adds the
  audited ordinary CS2 jump and crouch acceleration scale, including
  partially crouched commands; full movement parity remains open.
- Sub-tick button edges and aim angles travel in `UserCmd`; `GameWorld`
  gathers all commands first, lets bots think on worker threads, runs the
  players, match and shared systems, then delivers schema-checked events.
- Box3D owns the game's collision world through the inch/metre bridge.
  The optional native movement step is held bit-for-bit to the script;
  Jolt is the explicit legacy comparison and standalone-fixture backend.
- Draw interpolation, camera/weapon jump response and prepared animation
  layers run outside the simulation. Skeleton fitting is skipped when it
  would repeat work; tick-start fits preserve the current hitbox contract.

### Shooting and inventory

- All 34 firearms build from CS2's vdata and the weapon registry. Spread,
  seeded recoil, state-dependent inaccuracy and final recovery times,
  tagging, armour and per-surface wall penetration are implemented.
- AK/M4A1-S patterns are measured; 15 more use community patterns. Guns
  without a pattern retain provisional view kick, not a measured bullet
  path. Spray scale, random-recoil paths and the R8 delay remain open.
- [The October 2 shooting audit](research/shooting-audit-2026-10-02.md)
  completes installed-build research for seeded recoil/RNG, shotgun
  patterns, burst/R8 timing and core recovery formulas. Implementation
  remains open: whole-index recovery and decay timing first, then shared
  RNG/recoil/spread and weapon modes. The
  [follow-up](research/shooting-followup-2026-10-02.md) traces silencer
  completion/holstering, zoom mode/floor recovery, fall-speed landing
  penalties and camera composition; their boundary/visual captures stay open.
- Sniper zoom, speed/accuracy and overlays work. AUG/SG 553 use raised
  sights with a clear lens, black lowered lens and a blurred outside scene;
  exact CS2 focus/dirt and inaccuracy display still need work.
- Nova, XM1014 and Sawed-Off reload individual shells from clip events;
  firing can stop the reload after a shell is available.
- Inventory slots, Q, wheel-down cycling, G drops, walking pickups and E
  pickup/swap work. Dropped items use extracted physical hulls. The HUD
  names the eligible ground gun, grenade or bomb using the same use search.
- The knife slashes/stabs in the air and on the ground, with backstabs,
  armour, kill credit, clips and sounds. Its measured CS2 tuning and Zeus
  attacks remain open.

### Map, players and combat

- Dust2 and Mirage have been extracted and loaded locally. Extracted
  defusal maps supply their own collision,
  entities, nav mesh, buy/bomb volumes, baked lighting, probes, reflections,
  grade, visibility and skybox. Nearby skybox fragments are clipped; the
  separate lower-mid occlusion flicker remains open. Mirage's wall paint
  and sky extraction are fixed (#185). Dust2's measured world exposure
  and compensated sky are accepted at the paired T-spawn view; full-map
  colour/exposure parity remains open.
- Extracted agents, first-person arms and every carried item use CS2's
  clips. Body variations follow the held weapon; feet, hands and twist
  bones are fitted, the visible local torso folds away, and its full twin
  casts the shadow. Ragdolls use extracted physics shapes where available.
- Hitscan meets 19 bone-following capsules per extracted body, using the
  shared `DamageInfo` path. These poses still follow drawn animation;
  authoritative tick poses and history remain multiplayer work.
- Tracers, muzzle flashes, weighted bullet-hole materials and representative
  surface impact graphs are implemented. Blood uses current extracted
  layers, shorter/denser mist at the pellet contact, parent-death ground
  projections, bounded wall marks and bone-following wounds.
- Surviving hits play independent additive body/head flinches from 42
  rifle/pistol/knife clips. Full Source particle behavior, skin UV2 wounds
  and ragdoll wound transfer remain documented approximations. Sustained
  particle CPU cost is measured in
  [the hit-effects report](research/hit-effects-performance-2026-10-02.md).

### Match, bots, HUD and audio

- Competitive is five a side with warmup, freeze, rounds, side swap and
  overtime; Practice has no bots and unlimited warmup until F5. Any
  extracted defusal map uses the shared mode.
- Economy, buy zones/time, purchases/refunds, Ctrl-click buy-and-throw,
  inventories, the bomb and six grenades are wired into the match.
  Planting crouches the planter. Grenade effects and lineups remain partial.
- Bots buy and hold equipment, follow nav routes to sites and back, make
  way for teammates, shoot with weapon rules and respect smoke/flash.
  Coordinated objective play remains open.
- Health/armour/ammo, money, clock/team cards, bomb carrier, use prompts,
  weapon selection, damage arcs, kill feed/icons, spectators and round-end
  reports are implemented. Round banners use fixed text plus a slowly
  growing clipped copy, with translucent blurred panels fading at the sides.
  The Tab scoreboard is built (#175), with player statistics and round
  history. Radar, chat and additional scoreboard/HUD details remain open.
- Weapon shots/reloads, dry-fire and low-ammo clicks, surface footsteps,
  impacts, grenade/C4 sounds, flash ring/muffle, announcer and music cues
  play. HitSounds selects attacker/victim/onlooker body/head/armour events
  once; the older manual attacker feedback is no longer dispatched.

### Tooling

- Extraction includes current impact KV3/material DATA, checked texture
  dependencies and sheet reconstruction, small impact models and additive
  flinch clips. Valve assets remain ignored; generated tables are committed.
- `scripts/run_tests.sh` discovers each `tests/run_*.gd`, checks native/script
  equivalence and fails on script errors/timeouts. The October 3 local run
  through #185 passed 7,752 checks across 80 files, with extracted assets
  and current native movement. Three drawing checks were skipped in
  headless mode; four AWP drop-settling checks remain known open.
  PR #185's asset-free CI passed 7,051 checks across 80 files. These counts
  do not claim that the skipped comparisons ran.
- Render/frame/tick and hit-effects profilers record costs. The 6 ms maximum
  frame-time target remains open; merged work is not a blanket performance
  or exact-CS2-parity claim.

---

## Part 2: what is left, in order

Each phase can start once the one before it is in, except where noted.
Items marked **(Sid)** need Sid's machine or a decision from him.

### Playtest of 2026-09-25 (dust2)

Sid played dust2 and sent 23 issues. `reference/playtest-2026-09-25.md`
has each one investigated: what Sid saw, the cause (verified or inferred),
what already covers it, the plan, and its Remote and Local parts. Its current-status section distinguishes merged fixes from remaining
comparisons; the original scheduling and extraction batches below it are
historical. Each issue separates implementation from an extraction run,
a look beside CS2 or the asset run of the checks. Mark an
issue done here and on the page in the same pull request.

| # | Issue | Remote | Local | With |
|---|---|---|---|---|
| 1 | A mode chosen at start: Competitive, or Practice with no bots | **Done** (2026-09-26, 24c): a picker, `--mode`, Practice as Competitive with no bots and a warmup that does not end | Try it in fullscreen | 24a, 24c, 26 |
| 2 | Dropped guns sink into slopes, the magazine goes through the floor, they turn about the wrong point | **Done (#117):** a body on CS2's own hull (one convex hull a gun, mass 3 to 6, from the game's physics), swept against the floor; checks on a one-sided trimesh | `extract_assets.sh weapon-physics` and commit `physics.csv`; look on T spawn's ramp | 12 |
| 3 | E picks up what you look at, swapping out what is in that slot | **Done:** E takes the item looked at in Source's use search (80 units across, CS2's `player_use_radius`; the aim on it far off, well off it up close) and in sight; a gun swaps with the one in its slot, thrown down as a drop; no room sends `item_pickup_failed`; near the bomb E is the bomb's (`use_claimed`), and a T's E takes the dropped bomb. The HUD names the ground gun, grenade or bomb E can take, using the same selection and eligibility; hides it when blocked, full, buying or dead | Pickup prompts playtested and accepted in #163; precise CS2 reach/tolerance comparison remains | 12, after 2 |
| 4 | Ragdoll legs through the floor, joints bending too far | **Done** (#121, `reference/research/ragdoll-joints.md`): start clear of the floor and kept over it, CS2's own shapes (in the agents' `.vmdl`), joint limits from standing; checks on a one-sided trimesh | Dump CS2's joints; deaths on the ramp | Housekeeping |
| 5 | Bots hover over T spawn's ramp in freeze time (the hull rests on the uphill edge; there is no foot IK) | *(Remote done, PR #131)* Research, then foot IK and a ground fit | CS2's feet on the ramp | After 17 |
| 6 | Bots meet head-on and hop at each other forever | **Done** (PR #113): making way for teammates (`BotSteering`), stuck handling that never jumps at one, goals spread over a site | dust2's chokepoints and 24b's inferno spot; `scripts/run_tests.sh dust2` runs the new no-stall check | 24b, 23 |
| 7 | The xbox tarp far too dark (its lightmap read from the wrong UV set) | *(done: `LightmapMaterials.OWN_UV2_SHADERS`, `uv2_at_origin`, `carry_model_tint`, `prop_colorize`)* The UV set for `csgo_environment`, and its tint | `extract_assets.sh layers`; an xbox shot in CS2 | After 12 |
| 8 | Wrists wrung on the knife (the forearm twist bones are never posed) | **Done:** CS2's tilt-twist constraints from the agents' `.vmdl` on the drawn arms and bodies (`TwistModifier`), the maths in `reference/research/twist-constraints.md` | `scripts/run_tests.sh twist` with the agents and knife extracted; the knife and AK beside CS2, both teams; the cost in `profile_dust2.gd` | 6 |
| 9 | A see-through seam in a wall (Godot's vertex compression) | *(done: `write_import_settings.gd`, `MapImporter.GLTF_FLAGS`)* The map imported without it | **Done:** reimported, the seam gone from Sid's spot, no measurable GPU cost at 4K | After 12 |
| 10 | Too saturated and contrasty against CS2 | *Done:* CS2's grade (its Hable curve and the map's post-processing file), the default since 2026-09-26 (`--grade aces` for the old) | *Done:* extracted, calibrated at long doors; Dust2's world exposure recalibrated to x1.5 from the paired T-spawn reference on 2026-10-03, with inverse compensation preserving the approved sky. Other maps retain x1.2; B site waits for a CS2 shot | R0 |
| 11 | Geometry flickering (the sky's brushes used as occluders) | The sky's brushes out of the occluders (`MapOccluders.NOT_DRAWN`, 2026-09-26): top of mid fixed, **lower mid still flickers**; F11 rendering comparisons added in #167, which also fixes the separate beige skybox plane at the crates; next is Sid's call: shrink the occluders or turn Godot's occlusion culling off | `profile_render.gd`'s `no_occlusion` to decide; walk R3's spots with F11; `run_tests.sh dust2` | R3 |
| 12 | Zigzag stripes on the kasbah towers (Godot's mesh LODs break the third UV set's lightmap) | *(done: `LightmapMaterials.drop_lods`)* No LODs, or LODs that keep that UV set, on those props | Look, profile | |
| 13 | White eyes | CS2's eye shader on the character shader *(done, 2026-09-26: `CharacterEyes`, the eye path in `character.gdshader`)* | Extract the eye textures (`character-masks`), `run_tests.sh model`; the Phoenix face and the SAS lenses beside CS2 | R7 |
| 14 | Recoil on the AK-47 and M4A1-S only | *(done 2026-09-26, PR #111)* The 15 more patterns already in `reference/spray_patterns/`, solved at load; a provisional kick for the rest | Spray the rest in CS2 (TODO L6); the R6 demo | 8 |
| 15 | Mouse wheel down to the next weapon | **Done 2026-09-28:** CS2's `invnext`, and what you carry in the bottom right after each switch | Its order in CS2, and how long the list stays up | 12a, after 16 |
| 16 | A quick switch cuts the draw short | **Done 2026-09-26:** the draw restarted on every switch, as CS2's graph does, and R during it reloads once it ends (Sid's CS2 check) | Play quick switches beside CS2 | 12 |
| 17 | Running into a jump snaps to the air pose | *(Remote done, PR #114; first-person follow-up #160)* The take-off from CS2's graph, weapon bob faded into/out of the air, and camera/relative weapon dip and recovery on takeoff and landing | Extract the jump clips; regenerate the tables; Sid accepted #160's camera/weapon tuning; exact CS2 comparison remains (amounts by eye, `research/jump-camera.md`) | 6 |
| 18 | Nobody seems to get the bomb | *(done 2026-09-26; "[E] Take Bomb" from a bot done 2026-09-28)* A check end to end, CS2's handing it to the human T (`bot_defer_to_human_items`), a cue for who carries it | Rounds as T and CT; CS2's warmup | 16, 15 |
| 19 | Grenade sounds and effects | The shared sound-event table and player (**done** 2026-09-26: `reference/sounds/`, `SoundEvents`, `default_bus_layout.tres`), then the grenades' sounds (**done** 2026-09-28: `GrenadeSounds`, `FlashMuffle`, the burn), the effects' research (**done** 2026-09-30: `reference/research/grenade-effects.md`); then the effects | Extract the missing sounds; the particles by grenade-effects.md section 9 | 17 to 20 |
| 20 | A click as the magazine nears empty (CS2's `Default.NearlyEmpty`) | On the shared sound player, the threshold provisional (**done** 2026-09-28); dry fire on an empty magazine (**done** 2026-09-30) | Measure the threshold in CS2; check dry fire's repeat and auto-reload in CS2 | After 19's groundwork |
| 21 | Round sounds (start, end, planted, ten seconds, announcer) | The cues from `reference/research/audio-round.md` (**done** 2026-09-28: `RoundSounds`, the freeze beeps and ten-second warning, the bomb's own events) | Extract the UI, music and announcer; listen | 16, after 19's groundwork |
| 22 | Looking down shows the vest where CS2 shows legs | **Done:** the seen body folds from spine_2 up, the shadow and bots whole | Beside CS2 | 6a |
| 23 | The distant hill missing (the 3D skybox past the camera's far plane, dropped before its depth squeeze can help) | *(done: `FarMaterials.CULL_BOX`, `far_position`)* Far meshes kept in the frustum, and a squeeze that keeps them inside the far plane | The view beside CS2; the cost | R2 |
| 24 | The sky dark slate grey (the skybox's clouds, CS2's additive `csgo_unlitgeneric`, imported as an opaque, lit sheet) | **Done 2026-09-28:** `UnlitMaterials`, unlit and added; its textures listed by `export_alpha.gd` | **Done:** `extract_assets.sh layers`; long doors' sky 0.39 of CS2's to 0.86. The rest of the gap, the sky's own brightness and haze, needs research | 10, 23 |
| 25 | Red window frames, doors and awnings too vivid (the export's tint over the whole texture, not only the tint mask's paint) | *(done 2026-09-26: `prop_tint`, `LightmapMaterials.carry_features`)* The tint moved off the colour and put back through `g_tTintMask`; the `layers` step fetches the masks | **Done 2026-09-28:** `layers` fetched 55 masks; long doors' shutters and door from 0.36 to 0.50 saturation to 0.22 to 0.34 (CS2's 0.17 to 0.31), the awning unchanged | 7, R7 |
| 26 | Walking, the character stops dead for a tick and sets off again (a move grazing a floor that rises a few degrees took no travel, and the step found no floor) | **Done 2026-09-28:** the sweep keeps its clearance along the hit's normal, and looks past its end (`Box3DQueries.shape_cast_prepared`); checks on made-up slopes | **Done 2026-09-28:** five bots a minute on dust2, 13 hitches to none (`tests/run_dust2_bot_checks.gd`); Sid played (2026-09-28): none seen, "the movement feels really nice" | |

**Crouch speed (Sid's 2026-09-30 playtest, PR #164): Remote done 2026-10-01.**
Crouch walking holds 0.34 of the held item's speed, easing with the duck.
Turning cannot add speed beyond that top; residual running speed still
decays through friction. The AK-47 and AWP retain their crouched accuracy
while turning, with or without Walk; script and native movement share the
same correction. See `reference/movement_constants.md`, "Crouch turning",
for the reproduction and the small accuracy-threshold rounding tolerance.
**Local:** crouch and turn with those guns in the range and on dust2.

**October 3 slope playtest:** crouched starts still accelerated from the
standing weapon speed. PR #184 now uses the binary-derived ordinary land
crouch acceleration scale (250 * 0.34), independently of the speed target.
138 real-command checks cover flat/uphill/downhill floors and crouch
entry/exit; existing crouch turning/accuracy and grenade lineups pass.
**Local:** retest the acceleration feel on Dust2. Full crouch transitions,
terrain eyes and deferred movement integration remain open in the
[movement audit](research/movement-ghidra-2026-10-03.md).

**Box3D is the game's physics (2026-09-28, Sid).** Sid chose to take the
trial below forward. The October 2 grenade port builds debug and release
libraries from pinned source plus the opt-in projectile-query patch
(`scripts/install_box3d.sh`, `.ps1`); it requires Git, Python and a C/C++
compiler and caches compilation under `.godot/`. This also avoids the
upstream Linux release's glibc requirement. The AWP's four settling checks
are known open (`_check_known_open`: reported every run, not failing it).
Every query goes through `PhysicsQueries` (`reference/godot/physics.md`); E's
sight test (#126), written straight on Godot's space, was ported with #125's
merge and is checked on a Box3D world (`tests/run_box3d_pickup_checks.gd`).
FootPlant leaves Box3D's rest clearance out of each foot's gap
(`FootPlant.REST_CLEARANCE`, 0.3; #141, playtest issue 5), so a body on
flat ground keeps its clip's legs, checked on a Box3D floor and ramp in
`tests/run_foot_plant_checks.gd`.
Left: the AWP's settling; ragdoll visual acceptance; movement at real map
edges; the 6 ms frame target; tick-owned hitbox poses for multiplayer; and
`scripts/profile_dust2.gd` at 5 and 10 a side on both backends, for
`reference/performance.md`.

**The walking hitch, and the tick 16% shorter (2026-09-28; the 6 ms target
still open).** Walking dust2 stopped a player dead for a tick, 13 times a
minute among five bots: a move grazing a floor that rises a few degrees
beside the way backed off further than it went, and the step up found no
floor on its way down (playtest issue 26). The sweep now keeps its clearance
along the hit's normal and looks past its end; a recovery is two casts
where eight were; a player's tick synchronizes the other hulls once and
leaves its own out once; a ray from the open is one native call. The seeded
ten-player tick went from 3.68 to 3.09 ms, its 95th from 4.79 to 4.05, and a
minute's walk from 117,000 hull casts to 96,000. The merges of 27 and 28
September had not slowed the tick: main ran level with #125's merge, 0.2 ms
over the branch. **The contained changes (2026-09-28, perf/tick-contained)**
took it on to 2.31 ms: the floor found once a walking tick, a trace asking
the bridge for its cast alone, the hulls looked over once a tick, and Box3D
left alone with nothing awake; a walking bot's tick 243 us to 172, with the
hull's sweep's shape an eighth smaller all round. Sid (2026-09-28): the
bots' thinking is to go on worker threads, and the movement into native
code. **The bots think on worker threads (2026-09-28,
perf/bots-think-together):** everyone's command asked for before anyone
runs, the seeded tick 2.02 ms where thinking in turn is 2.03, its
95th 2.68 against 2.92, and dust2's match the same match
either way. With nine bots that is all they are worth; with nineteen, 0.3
ms of a mean of 4.4 and 0.45 of a 95th of 6.9. The worst ticks, 7 ms and
more, are not the thinking's: they are shots (`scripts/profile_worst_ticks.gd`),
a round paying 0.85 ms to bring 190 hitboxes to their bones before it is
traced and 0.2 ms for every ray after, a shooter's run 1.5 to 5 ms where
a bot's is 0.17. **Hitboxes for shots (2026-09-29,
perf/hitboxes-for-shots):** a body's hitboxes are a set, brought up to date
only for a ray that could meet it; a round fired is 0.6 to 0.7 ms less
with ten players and 1.3 to 1.6 with twenty, the ticks over 6 ms with
twenty a quarter of what they were, and dust2's match the same match, byte
for byte ([hitboxes-for-shots-2026-09-28.md](research/hitboxes-for-shots-2026-09-28.md)).
**What a death costs on the tick (2026-09-29, perf/death-on-the-tick):**
the tick a player dies in was 6.4 to 7.3 ms where a quiet one is 2, and
8.5 to 14 the first times in a process (the very first 11 to 23). The body a
player dies into is made ahead, on a frame, and dropped at the death; one
dead body passes through another by an upper layer of its own; a body at
rest is stepped and posed no more; the kill feed makes its rows on the
frame; the HUD reads its faces and images before play. A tick with a
death is 4.0 to 4.8 ms, 4.1 to 6.8 the first times (the very first 4.2 to
9.2), a quiet tick with bodies lying 0.15 ms less, and the worst tick of
the warmup Sid played 4.5 to 5.7 ms where it was 7.4 to 9.7
([death-on-the-tick-2026-09-29.md](research/death-on-the-tick-2026-09-29.md)).
Sid, 2026-09-29, playing dust2 alone and against nine bots: alone 224
frames a second at 1080p and a worst frame of 5.5 to 7 ms; with the bots,
in warmup and shooting nothing, 130 to 190 and a worst frame over 10, the
same at 4K. It is the processor and the bots.
**The movement's step in native code (2026-09-29,
perf/native-movement):** `PlayerBody`'s step and the hull's sweep under it
are also C++ (`native/src/hull_mover.cpp`, a GDExtension of the game's
own, built by `scripts/build_native.sh` and `.ps1`, not committed). The
script is the reference and runs wherever the library is not built; every
check file runs each native step by the script as well and holds the two
to the same body to the last bit, 171,682 steps of them in the suite's
run. A walking bot's movement 102 to 107 us a tick down to 67 to 70, and
the seeded ten-player tick 1.8 to 1.95 ms down to 1.55 to 1.7
([native-movement-2026-09-29.md](research/native-movement-2026-09-29.md)).
Local: build it in the main checkout and play a match with it.
**Skeletons fitted when the body steps (2026-09-30,
perf/skeletons-when-stepped):** a skeleton runs its modifiers (the feet,
the hands, the twist bones) and moves the hitboxes, the gun and the eyes to
its bones in every frame by default. A body nobody sees steps only in the
frames without a tick, so every frame holding one fitted ten bodies again
to the pose they had. A body that steps by hand now fits its skeleton by
hand, when it steps, and where the frame before a tick went without, as
the tick begins, so every tick meets the hitboxes where it did; a ragdoll
at rest is fitted in no frame. A frame holding a tick does 0.7 to 0.9 ms
less work headless, its fitting 0.78 to 0.87 ms down to 0.01; at 90 frames
a second, where the tick's own fit is made, every frame's work 3.55 to 3.87
ms down to 3.45 to 3.50 ([skeletons-when-stepped-2026-09-30.md](research/skeletons-when-stepped-2026-09-30.md)).
Sid played it at 1080p (2026-09-30): a frame holding a tick 6.36 ms to 5.35,
the slowest frame of each second 9.7 ms to 7.9 at the median, and half of
all seconds with it under 8 ms where a quarter had been.
**The frame split, and the skeletons fitted for nothing (2026-09-30,
perf/skeletons-nobody-needs, Sid's "measure the rest" and "tackle #1").**
Every frame split into its parts as played (`scripts/watch_game.gd`;
`reference/performance.md`, "Where the rest of a frame goes"): the rest
was work, not the cap's sleep or the GPU: the skeletons fitted after the
scripts, deferred calls, and the draw's setup and finish. Three of those
skeletons were fitted in every frame for nothing: the body you look down
at, now walked only while the camera can see it; its eyes and its
shadow's twin's, now aimed by neither; and the shut buy menu's agent, now
not processed. Headless, a frame with a tick fits 0.08 ms less and runs
0.03 to 0.06 ms less script. No research covered it; the body's reach was
measured from both agents' skinned vertices (the boxes in
`PlayerView.SEEN_STANDING` and `SEEN_CROUCHED`, held by
`tests/run_model_checks.gd`).
**Next, proposed: the bodies nobody sees, animated on every frame that
holds no tick (Remote).** Their animation is still stepped in every frame
without a tick, 8.5 bodies of nine, where a round asks for a body's pose a
few times a second; with the skeletons, ten bodies were 1.1 to 1.4 ms of
every frame headless. No research covers it yet.
Left: the bridge's work around the movement's step (27 us a bot a tick,
script over dictionaries) into the native library; what a death
drops, 0.3 ms, and the first death's step, 6 ms once; a player's ragdoll
made from CS2's own shapes, which `RagdollShapes` reads and only a check
asks for; Godot's renderer on a thread of its own measured
drawn, not shipped on (Godot marks it experimental).
Measurements and the list:
[box3d-walking-hitch-2026-09-28.md](research/box3d-walking-hitch-2026-09-28.md).
**Where the slow frames come from (2026-10-02, Sid's "audit what is
necessary for performance and consistency").** Sid's play at 1080p, split
by what happened in each second: quiet play holds about 4.6 ms a frame,
ticks or not, and the slow frames come with events. A second with shots
averages 6.06 ms, one with a death 6.75, and seconds with spawns or buys
hold ticks of 5.2 to 5.5 ms. Scripts are the largest excess in 55% of slow
frames, and the tick in 37%; these percentages count frames, rather than
shares of the summed excess time. The list, ranked, is in
[frame-consistency-audit-2026-10-02.md](research/frame-consistency-audit-2026-10-02.md).
It runs: the hit particles culled and then made native; decal fades and
the MultiMeshes' bounds; respawns and new items posed off the tick; a
trace's hitbox sets; then the frames everywhere. The priorities follow
the measured event-related costs; frames without a tick can also exceed
6 ms. `scripts/profile_worst_ticks.gd` now makes the
bodies players die into before each tick, as the game does on frames; it
had built each death's ragdoll on the tick, 2.0 ms where the game pays 0.6.

**Box3D physics trial (2026-09-26, Sid).** The branch
`codex/box3d-dropped-guns` started with dropped-gun jitter and now follows
Sid's request to convert all game physics. The shared native world owns
map collision, player/hitbox queries, dropped bodies and ragdolls;
movement, hitscan/penetration, live-grenade collision, sight and surface
queries use it. Source movement and grenade-flight rules remain game
code. The branch defaults to `--physics box3d`; the old `--drop-physics`
flag remains an alias. Original Godot collision RIDs are detached while
the full adapter is active.

**Frame-time audit done (2026-09-26).** Repeated 4K ten-player p99 is
12.5–12.8 ms on Box3D, versus 9.1 ms through legacy. Disjoint CPU attribution
finds 3.47 ms/tick in proxy synchronization against 0.42 ms in the native-step
interval; first-use weapon/grenade spikes are a separate issue. The audit
records rendering ablations, a live round, focus-filtered tails and one-bot
scaling. It prioritized incremental proxy updates, contact trace amplification
and actual first-use prewarming; that audit changed no gameplay/graphics defaults.
Evidence and reproduction: [frame-times-2026-09-26.md](research/frame-times-2026-09-26.md).

**Bridge and recovery optimization done (2026-09-26; 6 ms target still open).** Query-only
proxies update on demand, reuse authored geometry, and avoid native kinematic
stepping. Movement groups its recovery casts, skips excluded self updates,
and stops identical failed searches; proven deep player overlap needs one
cast instead of sixty. Same-tick poses and geometry/lifecycle changes have
dedicated regression coverage. Effects and graphics settings are unchanged.
The **6 ms maximum frame-time target remains open**; measured results and
remaining costs are in [the follow-up](research/box3d-performance-fixes-2026-09-26.md).

**Repeated player-update work reduced (2026-09-26).** Per-tree animation
bindings skip unchanged persistent values while retaining consumed requests;
bot sight shares observer setup and visits nearest candidates first without
changing reaction timing. Static crouch-path data, shooter state, and recoil
damping constants are reused. The ordinary ten-player simulation averages
3.217 to 3.095 ms with the same shots and hull traces. This is a modest CPU
gain, not proof of a lower rendered maximum or multiplayer-ready pose timing.
Measurements and remaining work: [player-update-performance-2026-09-26.md](research/player-update-performance-2026-09-26.md).

Before that optimization, native gameplay integration passed 43/43, world/hitbox lifecycle 20/20,
ragdolls 67/67, focused movement 22/22, and real Dust2 integration 10/10;
the movement course passes 80/80 on each backend. The final seeded 5v5
CPU comparison averages 7.091 ms per native tick versus 3.296 ms for the
legacy query/drop path (see the trial notes for scope); this is not a
full-game speedup. The full suite and final targeted reruns cover 3,750
assertions: 3,746 pass and the four known AWP settling checks fail; one
draw-only suite skips headless. Implementation of the full-physics trial
is done; acceptance and its remaining quality/performance work stay open.
Ragdoll ball/hinge joints approximate the previous independent-axis
limits with conservative offset cones and need visual acceptance.

Sid's positive drop playtest led to release-orientation and bullet-push
fixes. A later failed shooting playtest exposed floor friction absorbing
downward shots; the supported-gun reaction now reflects the into-surface
component outward. Its current strength is 6.9 kg·inch/s per remaining
base-damage point: a 15% increase from 6.0, chosen for Sid's request for
a slight increase. Both reaction and strength are experimental; the
legacy comparison has no bullet push
and requires the native world for converted ragdolls. Setup, dated test
results and the original drop-only benchmarks are in
[box3d-trial.md](box3d-trial.md). Human acceptance and the quality decision
came with Sid's choice on 2026-09-28; the four AWP settling checks are known
open; the old timings do not measure the full conversion.

### Phase 1: make being shot feel like CS2

Items 1 to 4 landed in PR #27. Third-person firing, current extracted blood,
wounds, hit sounds and additive body/head reactions are implemented through
PR #172; the remaining comparison and accuracy work is listed per item.

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
5. **Blood on hit.** *(Implemented and merged 2026-10-02, PR #172; controlled CS2 comparison remains)*
   Per-pellet damage snapshots dispatch extracted blood/helmet particles,
   animated motion-vector sheets, parent-death floor splashes and real
   weighted world decals. Body wounds follow the struck bone using CS2's
   wound mask. The shared hit-audio path plays authored attacker, victim
   and onlooker sounds once. `scripts/extract_assets.sh impacts` reproduces
   the definitions, material DATA, textures and small impact meshes.
   Left: compare closed game-side CP/root selection, persistent wall blood,
   skin UV2 accumulation and Source shader aging against current CS2;
   documented approximations in `reference/research/blood-and-impacts.md`.
6. **Firing on the third-person model.** *(Firing done 2026-09-23; body/head flinches added 2026-10-02, PR #172, merged; controlled comparison remains)* A bot's body holds, fires and
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
   (`PlayerModel.variation_for`). Everything anyone may hold, every item on
   either menu, the knife and the bomb, is read before play, clips and
   models (`prepare_holding`), so taking a gun in hand reads nothing from
   the disk. Every body does it, yours unseen too, as CS2's server poses every
   player's hitboxes with what they hold; the variation switches once the
   draw is over, as CS2's graph has it. Left: CS2 blends the weapon layer in
   model space, Godot in each bone's own, so the upper body follows the hips
   here. Separate body/head flinch layers now use 42 extracted additive
   directional rifle/pistol/knife clips, with a 0.1s repeat-hit blend.
   The aim: CS2's AimCS bends the upper body and head
   with the aim's pitch (and the torso with part of its yaw), on the
   server, so the hitboxes move with it. Here bodies and their hitboxes
   stand as if looking level (`reference/research/hitboxes-aim.md`: a
   Local measurement, then the aim stage after systemization step 8).
   The hands' IK onto the gun, the other half of AimCS, is done
   (`HandGrip`, Sid 2026-09-29: guns floating out of the bots' hands): each
   frame after the foot fit, each arm is bent so its hand lands on the
   clip's `wpnHand_L`/`_R`, easing off over CS2's 0.3 s for a draw or a
   reload. The foot fit now lowers the gun with the pelvis
   (`FootPlant.lower_gun`), since on T ramp the drop took the hands past
   what the IK reaches (Sid, 2026-09-29). As merged it lowered the gun
   twice as far as the body, 12 units for 6 on a 13 degree ramp: on the
   rig `wpn` hangs under `wpnPivot`, and both were moved. The check that
   said so needs the models, so it first ran on Sid's machine, after the
   merge. **Put right 2026-09-29 (fix/gun-with-the-pelvis):** only the
   topmost of the gun's bones moves; a bot stood on ramps of 8 to 25
   degrees has its gun down by what its pelvis is and its hands on their
   grips, and walked up and down ones of 13 and 18 its hands are within
   0.01 of them, where they were up to 4.7 off. And at a
   respawn, which is where a slope's spawn showed it: the ragdoll, freed
   at the frame's end, posed the body once more where it lay, so for a
   frame the body was drawn where it died and its gun where it spawned,
   and for a frame or two after the body stood at rest, arms out, until
   its animation stepped. The ragdoll is let go of at once
   (`Ragdoll.let_go`), the body posed as it gets up
   (`PlayerModel.pose_again`), and the foot fit takes the floor as it finds
   it (`FootPlant.snap`) where it eased from the drop it had where the
   body died. Left: while a draw or a reload plays the hands are let go
   of, and part-way through a draw they are 4.7 units from their grips,
   on the flat as on a slope, since Godot blends the draw bone by bone
   where CS2 blends it in the model's space. Local: a look at bots on
   dust2's slopes and at a round's start on T spawn.

6a. **Your shadow has no arms.** *(done; Sid checks it in play)* Sid noticed
   2026-09-22 22:06. The shadow twin now keeps its arms and holds what is in
   hand as a bot's body does (`PlayerModel.hold`): the item's hold, draw,
   locomotion and model, cast only into the shadow maps, with its shots and
   reloads played on it (`PlayerView._follow_hand`). `Competitive` reads
   every item's model before play, so a buy shows in the shadow without a
   read from the disk. To check in play: the shadow of the arms and gun on
   the ground, and whether it darkens the view model's arms in the sun (the
   worry that folded them first); the upper body stands as if looking level,
   as every body does until the aim stage (item 6).

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
- **Even frames.** *(done, 2026-09-24; Sid plays and says whether the
  tearing is gone)* Sid saw dust2 choppy at 4K, most when turning fast. A
  frame that runs a tick (4.5 ms with the bots) drew the world and the view
  4.5 ms behind the rest; now each frame is drawn where the clock is
  (`DrawClock`, `physics_jitter_fix` 0) and the mouse is read just before
  the view is placed: turning 1.7 ms off a steady turn to 0.7, flying 2.5
  to 4.2 ms to 0.6 (performance.md, "Frame pacing"). For the tearing, the
  game starts in exclusive fullscreen with frames held just under the
  refresh, where G-Sync engages, as Sid plays CS2
  (feature/fullscreen-frame-cap).
- **Frame times against CS2's.** *(first-use hitches done,
  perf/no-first-use-hitches; Sid plays)* The goal, from Sid's CS2 at 4K
  with his settings (2026-09-25): 5.5 ms a frame walking round a
  deathmatch, 9 to 10 ms once the shooting starts.
  `scripts/profile_combat.gd` measures ours the same way: 4.4 ms and 4.2
  on average, the 95th 7.8 and 7.1. Nothing is built in the tick for the
  views any more, and the first buy, the first dropped gun and the first
  shots no longer hitch (they held a tick or a frame 18 to 347 ms); no
  frame is over 20 ms (performance.md, "Against CS2"). Every model anyone
  can take in hand in a match is read before play, as CS2 precaches every
  gun, and the guns' unused legacy bodies are left out at import
  (perf/read-match-guns-ahead; research/weapon-preload.md): 123 MiB more
  video memory, 0.17 s more at match start, and no model read during a
  match. The live round no longer costs more than freeze time
  (perf/bot-tick): from your spawn at 4K, 5.67 to 5.82 ms a frame once
  everyone moved, now 5.26 to 5.31, where freeze time is 5.24 to 5.29
  (performance.md, "Still and moving"). Left:
  the frames that run a tick, about 7 ms, which a cheaper tick shortens.
- **Screen-space occlusion off.** *(done, the Godot docs audit)* It
  darkened ambient light only, which no map material took then, so it
  drew nothing and cost 0.6 to 0.95 ms a frame at 4K (rendering.md,
  "Measured"). The map's bounce light is Godot's ambient light since R5,
  so an occlusion look like CS2's is a setting to judge beside the game.
- **Reflections (R5).** *(first tier built and kept, 2026-09-25: 1.15
  to 1.18 ms of GPU at 4K and about 500 MB, rendering.md R5; L8's
  screenshots are left)* Nothing reflected anything before, not
  even the sky: the switch that let the baked light in turned Godot's
  reflections off with it. The map's materials now hand their baked
  light to Godot as its ambient light, which keeps them, and a Godot
  reflection probe sits at each of CS2's cubemaps (dust2's 43 probe
  volumes), drawn once as the map starts. Next: CS2's own cubemap
  pictures in place of Godot's.
- **Players drawn as CS2 draws them (R7).** *(Remote, after L8's
  screenshots; the cloth built, 2026-09-25, and waits on rendering.md L9)*
  Why the players look flatter than CS2's, most visible first: no
  reflections (R5, built), one light sample for each body where CS2 reads
  the probes at every pixel, CS2's character shader layers lost in the
  export, and textures compressed twice. Of the layers, cloth is built:
  the players, your arms and the buy menu's agent are drawn with CS2's
  cloth sheen where their materials ask for it, their occlusion darkening
  the sun too, where they shone like plastic (Sid's buy menu screenshot,
  2026-09-25). The eyes' material is also built (playtest issue 13).
  Left of the layers: softened skin, rim and tint masks, and detail textures.
- **Research CS2's renderer (R0) and CS2's video settings (R6).**
  *(Remote, not started)*

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
12. **Inventory.** *(done 2026-09-23; E to swap done with the playtest's
    issue 3, guns on the ground as bodies with its issue 2; Sid checks it on
    the range)* Slots, switching
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
    from the hand, moving as the body was. E pickup/swap and its ground-item
    prompts are done (PR #163); blast impulses on dropped guns remain open. The 2026-09-26 Box3D trial
    gives dropped items native rigid bodies on their own physics hulls;
    its follow-up adds bullet impulses to guns and corrects their held
    orientation at release. After a failed shooting playtest, a
    grounded-contact response passes realistic downward-shot
    regressions. The subsequent full-physics conversion raises its
    experimental impulse strength by 15% for Sid's requested slight
    increase, to 6.9 kg·inch/s per remaining
    base-damage point; human acceptance remains pending. See
    [box3d-trial.md](box3d-trial.md). The playtest of
    2026-09-25's issues 2 and 3 track the broader work.
12a. **Binds: the same keys everywhere, the test range included.** *(Remote;
    Local wires section 5's keys through it and checks CS2's defaults; new
    2026-09-24, Sid: "Ideally the same keys are used everywhere even in
    testing")* One table maps a key to a command, as CS2's `bind "g"
    "drop"`, starting from CS2's own defaults
    (`game/csgo/cfg/user_keys_default.vcfg`) with Sid's two departures,
    the wheel's jump and noclip on V (the wheel down is `invnext`, CS2's
    own, since playtest issue 15: the table takes over its `invnext`
    action as it takes the rest). A `+` command is a held button in the
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
    the map says), your money and the buy zone's cart on the HUD,
    and why B does nothing when it does not open; warmup's $16,000; a gun
    bought taken in hand. Still to do: choosing another loadout (a settings
    page).
15. **HUD for rounds.** *(Remote; the radar is extracted, `MapOverview`)*
    Money, armour, timer, score and players alive, kill feed, radar,
    scoreboard, round-end panel. *(Part done 2026-09-25: the HUD follows
    today's CS2 layout on its own element system, `HudElement` and
    `HudStyle` in `src/ui/`: health, armour and ammo round the emblem at the
    bottom, rolling money with the buy zone's cart, the team counter with
    the clock, scores, players alive and a card per player, the alert bar,
    and the buy menu restyled. Built to CS2's own Panorama layouts and
    styles, in its font (Stratum2, unpacked from the game) and icons,
    blended additively in linear light with the world blurred behind its
    panels as Panorama does. Local: checked on Sid's machine against
    `In_game_ui.webp` at 1080p and 4K, where it matches to the pixel but
    for the player's portrait and colour. Still to do: the
    radar, the bomb's icon on the clock, the
    kill marks over the health and the low health and ammo glow. The buy
    menu rebuilt 2026-09-25 to Sid's screenshots of CS2's: its columns in
    CS2's order, CS2's word on each item, the countdown in warmup and freeze
    time, and your agent in CS2's own pose for what is in hand or under the
    mouse, holding it, framed by CS2's buy-menu camera. Each player's colour
    is drawn at random for the match until a setting chooses it (item 26).)*
    *(Round-end panel done 2026-09-26: CS2's win panel from its own
    hudwinpanel layout, styles and strings, ROUND WON or ROUND LOST with the
    round's fun fact and the MVP's band (`WinPanel`), from what the server
    now says on round_end, round_mvp and cs_win_panel_round (`RoundReport`
    in `src/match/`, which picks the MVP and the fun fact by the
    community's rules until CS2's are measured). Left: the glitch video, the
    MVP's 3D agent on the band and the team income line in the chat. Local:
    a round won and lost beside CS2's at 1080p; Sid accepted the refined
    banner in PR #166, merged 2026-10-02.)*
    *(Matched to Sid's CS2 screenshot of 2026-09-30: the post-round damage
    report under each enemy you traded damage with, "100 in 3" given and
    "27 in 1" taken with how the kill was made (`TeamCounter`, from CS2's
    hudteamcounter-postrounddamagereport styles); a bot MVP's "[BOT]" tag;
    the "shots fired" fun fact; and the fun fact drawn among those that
    hold rather than the first in a fixed order. Left: the players' names
    over their cards in the down time.)*
    *(Local checked 2026-10-01 at 1080p on dust2, with the extracted report
    frame and all kill-type icons: won/lost, the bot MVP tag, shots-fired
    line, staggered reports and next-round reset. Corrected the flipped
    damage-taken frame's origin so it stays behind its text; the renderer
    checks both frames' pixels inside their rows. The latest cropped
    reference also sets the result strip and spaced foreground title:
    a faint copy grows behind it, clipped to the thin horizontal borders,
    while the foreground stays fixed. Local renderer checks cover that
    growth and clipping. Local tuning slows the growth to 10 s and makes
    the strip translucent with the existing world blur. The full-screen
    reference narrows the strip to 640 px and extends the side fades across
    the tint, blur, dot pattern and borders; GPU checks cover transparency,
    the broad fade and the world becoming sharp again at both ends.)*
    *(Kill feed done 2026-09-28: CS2's death notices in the top right from
    its huddeathnotice layout and styles (`KillFeed`, from the game's
    player_death events), every mark the event can carry, your kills
    ringed red and your deaths on dark red, 5 s a row (7.5 s for yours),
    fading over 1 s. Its icons come with `extract_assets.sh hud`. The
    assister, a flash assist, a blind or airborne killer and a kill through
    smoke come from `KillCredit`, which fills player_death as the kill
    happens by CS2's rules; revenge and domination stay off, as CS2's
    `sv_nonemesis` leaves them. Local: a round's kills beside CS2's at
    1080p with its icons.)*
    *(Scoreboard done 2026-09-30, to Sid's CS2 screenshot of that day:
    CS2's classic competitive scoreboard while Tab is held (`+showscores`),
    from its scoreboard layout, styles and script (`Scoreboard`): the mode,
    map and time; each team's score, name and players alive; a row a
    player in competitive's order (the most damage first) with the status
    skull, C4 or kit, the bot's mark, the portrait in the player's colour,
    Money (your team's only), Kills, Deaths, Assists, HS% and DMG, your row
    lit; the timeline of the period's rounds with how each was won, each
    half's score, the trophy on the clinching round and the loss bonus's
    dashes. The numbers are the server's (`MatchStats` in `src/match/`,
    from the game's events; a team kill or suicide takes a kill away, a
    guess from CS:GO), the rounds `MatchState.history`. Its new icons
    (bot, bomb_c4, bomb, timer, trophy, competitive_teams) come with
    `extract_assets.sh hud`. Left: the second set of numbers (MVPs, utility
    damage, enemies flashed, K/D, ADR) and the mouse that cycles to it, the
    flair and rank, the music kit line, the survivors under each round,
    overtime's score column, the spectators, and the ping (bots show their
    mark; a player shows 0 until there is a network). Local: the board
    beside CS2's at 1080p, after `hud`.)*

### Phase 5: the bomb

16. **Plant, timer, defuse, explosion.** *(Remote part built 2026-09-23 in
    `src/bomb/`, on the test range (5 takes the bomb out and the attack
    button plants it, E defuses, L the kit, all through your commands);
    in dust2's match since 2026-09-23 (its two sites, the map's own blast
    radius, the round ending on the blast or the defuse); the HUD is next,
    as `reference/systems/bomb.md` sets out; the plant time, defuse reach and
    beeps are guesses until C1; since playtest issue 18 a human T gets it
    every round, as CS2's `bot_defer_to_human_items` has it, and your
    team's cards show the carrier's C4)* *(Local measures,
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
    grenade clip is retained separately on layer 32 since 2026-10-02
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
20a. **Grenade flight and lineups.** *(Sid, 2026-09-30; static research done
    2026-10-02, core throw/flight/activation port done; lineup comparisons
    and additional entity/water/spin behavior open. Remote for the
    code and headless checks, Local for anything measured in CS2)* In play, grenades are floaty and
    inconsistent in the air, and the map may be part of it. Running and
    jumping should change how far a grenade goes. The goal is to recreate
    CS2's lineups: the same spot, aim and throw lands where it does in CS2.
    Start from what the repo has:
    - The grenade systems from the grenades PR (#53): the flight in
      `src/grenades/grenade_flight.gd`, the throw's numbers in
      `src/grenades/grenade_rules.gd`, the hand timer/jump snapshot in
      `grenade_throw_state.gd`, and `reference/systems/grenades.md`.
    - The current-build research:
      [October 2 Ghidra grenade audit](research/grenade-audit-2026-10-02.md)
      verifies the velocity formula, gradual strength and middle snap,
      0.1 s release scheduling, jump snapshots, center-to-eye launch box,
      default box collision and two 1/128 s flight steps per 64 Hz tick.
      It also recovers bounce/settle rules, spawn-based fuses and smoke/
      decoy activation. The [core port](research/grenade-port-2026-10-02.md)
      implements these corrections, including a separate one-time enemy
      body hit and fire fuse extension; the audit supersedes older guesses in
      `reference/research/round-bomb-grenades.md` and its `round.md` summary.
    - **Collision foundation audited and narrow fixes done 2026-10-02:**
      [the follow-up](research/collision-foundation-2026-10-02.md) traces
      the engine push/filter/result callers, tests grenade-sized boxes
      and spheres against solid and triangle floors, and fixes repeated
      bounces reusing the full step's time. Grenade contact now comes from
      one complete sweep result. The subsequent core port adds
      `ProjectileTrace`, per-query tolerance, blocked starts and departure
      from touching planes. Player and rigid-body settings remain unchanged;
      a general physics rewrite is not a prerequisite established by the audit.
    - **Map import done:** grenade clips are retained on layer 32 and
      excluded from camera occluders; players retain their separate clips.
      [Sky clipping corrected](research/grenade-sky-clipping-2026-10-02.md):
      conditional sky brushes use layer 64, outside ordinary gameplay masks,
      rather than making invisible walls above mid. Fresh Dust2 collision
      matches the existing extraction; the bug was interaction classification.
      Synthetic layer checks and the extracted Dust2 run validate the import.
    - **Jump timer corrected:** [Xbox lineup follow-up](research/grenade-jump-lineup-2026-10-02.md)
      fixes the interval sign recovered from the instructions. The screenshot's
      T-spawn fixture now bounces onto Xbox across nine jump/release combinations;
      exact recorded CS2 trajectories and input-window comparisons remain open.
      The [mid-door reference](research/grenade-sky-clipping-2026-10-02.md#mid-door-landing-reference)
      reached the open door top with the previous quarter-tick movement,
      while other jump phases could fall off it.
      The [October 3 Ghidra audit](research/grenade-subtick-snapshot-2026-10-03.md)
      recovered the exact movement boundary and ordinary jump gravity adjustment.
      Both are merged in #184. Snapshot state is consistent
      across jump phases. Sid's subsequent CS2 console aim resolves the local
      mid-door miss with unchanged physics; the screenshot-derived aim was
      about 0.8 degrees lower. The preset now uses the supplied exact CS2
      pawn origin. Recorded trajectory comparison
      and general jump validation remain open. Sid still reports needing to
      aim higher at matching landmarks. The
      [camera-height follow-up](research/camera-height-2026-10-03.md) confirms
      64/46 base eye heights and a missing terrain eye adjustment used by
      CS2's grenade snapshots. Paired console coordinates now measure an
      effective 60.75-unit eye height there and 63.9375 at the new B-doors
      reference. Implement and validate the shared simulation offset before
      claiming parity. The [movement audit](research/movement-ghidra-2026-10-03.md)
      also confirms horizontal integration, crouch and modern landing/press-window
      gaps; matching native/script output is not evidence of CS2 parity.
    - **Local:** G1 in `reference/cs2-systems.md` now compares the recovered
      rules against CS2 (standing, running, crouching, jumping, button
      changes and close-wall releases), and a set of dust2 lineups
      recorded in CS2 to compare against (spot, angles, button, movement,
      and where it lands), which N2's lineups for the bots can share.

### Phase 7: knife and Zeus

21. **Knife and Zeus.** *(Local measures, then Remote; both are extracted)*
    The knife is done, Remote (2026-09-30): both attacks, backstabs, reach,
    damage, clips and sounds, on the community's numbers
    (`reference/cs2-systems.md` 8). Sid's October 1 PR #165 feedback is
    addressed: airborne swings keep the fallback hull's full width near
    the eye, and its forward extent is bounded to 48 units for slash and
    32 for stab. A wall on the line stops the attack; hull-only wall hits
    also play the wall outcome. Third-person attacks use the extracted
    knife graph's clip mapping, with both swing variants. Still to do: K1 (Local) measures the
    knife's numbers and plays it beside CS2; the Zeus (Remote).

### Phase 8: bots that play CS

22. **Navigation.** *(done 2026-09-23, Remote; Sid checks it on dust2.
    Local: the mesh's analysis still to read)* Bots walk dust2's own nav
    mesh (`scripts/extract_assets.sh nav`, read by `SourceNavMesh`, PR #32).
    `SourceNavMesh.walk_path` takes `find_path`'s route and pulls it taut
    (the funnel algorithm, turning 10 units in from the corners of the edges
    it crosses), keeping each jump's take-off and landing; a bot walks it
    through its commands, as a player would, jumping (with a crouch in the
    air) where a link rises past a step, crouching before an area marked
    for a low ceiling, and, held up by the map, wiggling, then jumping and
    finding its way again (held up by a teammate, it makes way instead:
    the playtest of 2026-09-25, issue 6). On
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
      Doors and func_brush blockers are ruled out. dust2 shows the same
      jam: the playtest of 2026-09-25, issue 6, traces it to bots having
      no way round a teammate and jumping when held up. The jam half is addressed on the
      Remote side (PR #113: bots make way for teammates); Sid's replay
      of the inferno spot is still open, as are the two Ts stopping above
      A's floor and the CT stopping on its way back, which are not jams.
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
24c. **A mode chosen at start: Competitive or Practice.** *(Remote done
    2026-09-26; Local below; playtest issue 1)* `maps/play/play.gd` takes
    `game_mode` (Ask, Competitive, Practice) and `--mode competitive|practice`
    on the command line, which wins. Ask shows a picker (`ModePicker`,
    `src/modes/mode_picker.gd`) before the map loads when the scene is the
    one being played on a screen; added under something else (the profilers,
    which now set Competitive, and the checks) or headless, it plays
    Competitive. Practice is `Competitive.practice()`: no bots and a warmup
    that stands still (`MatchRules.warmup_paused`, CS2's
    `mp_warmup_pausetimer 1`), so warmup's money, buying and respawns last
    until F5 starts the rounds. A departure from CS2, whose offline practice
    is a match with bots you choose. **Local:** play `de_dust2.tscn` in
    exclusive fullscreen, choose each mode, and say whether Practice has
    what testing needs. Roadmap 26's main menu replaces the picker.

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
    Video includes, from the frame pacing work (performance.md, "Frame
    pacing"): exclusive fullscreen, where G-Sync and FreeSync engage by
    default, and a frame cap just under the refresh for such screens
    (`r - r * r / 3600`, 224 at 240 Hz, about what NVIDIA Reflex sets in
    CS2), which a fixed-refresh screen does not want. Both are the game's
    defaults since 2026-09-24 (`project.godot`'s window mode,
    `PlayerView.frame_cap`), changed in Project Settings until the menus
    carry them.
27. **An exported build** *(Local)*, so a playtest does not need the editor.
    The extracted assets stay outside it.

### Movement: what is still open

The [October 3 movement audit](research/movement-ghidra-2026-10-03.md)
identifies simulation differences that also affect grenade launch inputs
and visual aiming. PR #184 merged the ordinary jump and targeted crouch
acceleration corrections; it did not complete movement parity.

The next work, in order (Remote implementation and checks; Local binary
audit, CS2 captures and performance measurements):

1. **Shared terrain-aware eye state.** Finish tracing the actual terrain
   sampler, then port the topology/root and duck adjustments into
   simulation state, used by both the rendered camera and grenade snapshot
   capture. Bound and cache its collision
   queries. Validate flat ground, slopes, thin edges, takeoff, landing
   and duck transitions against paired `getpos`/`getpos_exact` captures.
   Mid-door's effective eye offset is 60.75 units, B-doors' 63.9375;
   retain the 64/46 base values rather than hard-coding a global offset.
2. **Combined horizontal integration.** Port acceleration/friction and
   deferred velocity together in script and native movement. Test
   displacement, blocked motion, slopes and run/jump throws, not just
   final speed. Compare trace budgets and tick cost with the current build.
3. **Crouch and modern jump transitions.** Complete duck state/rates,
   repeated-input gates and landing/bhop press windows with boundary
   checks and CS2 captures. Keep them separately reviewable from grenade
   flight changes.

Mirage now provides another extracted map for paired throw references.
The B-doors standing jump throw is accepted in play; the mid-door visual
aim discrepancy and recorded trajectory parity remain open (item 20a/G1).
PR #179's foot planting is a presentation follow-up, pending review and
playtest separately from these simulation changes.

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
- CS2's ragdoll shapes are in the extracted agents' `.vmdl` (15 bodies);
  its joints and their limits are not extracted. The ragdoll uses the
  extracted physics shapes when available, with hitbox capsules as the
  fallback and estimated joint limits; playtest issue 4 records the
  remaining exact-joint work (`reference/playtest-2026-09-25.md`).

---

## Waiting on Sid

| | What | Unblocks |
|---|---|---|
| Hands | Remaining playtest CS2 comparisons and extraction work (`reference/playtest-2026-09-25.md`, current follow-up status; the original batches are historical) | Playtest parity checks |
| Hands | Spray a wall in CS2 from 496 units | Item 8 |
| Hands | Measure jump height, crouch-jump reach, dead-strafe feel | Movement check |
| Hands | Check on the range that the shooting bot stays upright while firing, and that the dummy's ragdoll and your own settle without spinning (PR #30) | Confirms PR #30 |
| Hands | Compare the extracted blood, wounds, hit sounds and additive flinches against current CS2 (PR #172) | Items 5, 6 |
| Hands | Check that first shots at a run now miss (PR #24) | Item 9 |
| Hands | Play being shot on the test range (I, U, Y, J, T) and dust2: your capsules' fit, the tag, the flinch, the hit arcs (PR #27) | Items 1 to 4 |
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
| Hands | The systems' Local list in `reference/cs2-systems.md`: bomb (C1, the explosion's particles from C3, and decoding C2's damage), grenades (G1 to G5, and G6's particle and smoke textures), knife (K1), remaining agent/buy UI sounds (S1; S2's event table is built) | Phases 4 to 7 |
| Hands | Run `scripts/profile_render.gd` again at 1080p and 4K, and walk long doors and top of mid, on PR #78 | Rendering R2, R3 |
| Decided | dust2's sun shadows come from CS2's baked pages, the live shadow map drawing only what moves (Sid, 2026-09-25) | Rendering R4 |
| Decided | R5's reflections stay, for 1.15 to 1.18 ms of GPU at 4K: all-metal guns such as the Desert Eagle only look right with them (Sid, 2026-09-25). The profile the R5 Hands row asks for is done; `no_reflections` does not measure it, the builds before and after R5 do (rendering.md R5) | Rendering R5 |
| Hands | Run the dust2 checks again, play dust2's shadows beside CS2's, and profile with `live_map_shadows` and `no_visibility`, on PR #82 (rendering.md L7; the pages were extracted and checked 2026-09-25) | Rendering R4 |
| Hands | Play dust2 beside CS2 for reflections and the players (the same agent in the same spots, in sun and shade), and profile with `no_reflections` (rendering.md L8) | Rendering R5, R7 |
| Hands | Extract the agents' cloth masks (`scripts/extract_assets.sh character-masks`), run the model checks, and look at the players' cloth beside CS2's in the sun, in play and in the buy menu (rendering.md L9) | Rendering R7 |

---

## Later (past the current scope)

- The CS2 features nobody has asked for yet, listed at the end of
  `reference/cs2-systems.md`: pings and radio, voice and text chat, votes,
  other modes, demos, anti-cheat.
- Broader map support beyond extracted defusal maps (hostages, doors and
  breakables); other defusal maps already load through `--map`.
- Original assets in place of Valve's, if the game is ever sold.

---

## Current dependency order

The player/simulation split, shared world and item/damage/event contracts,
third-person presenter, economy, buying, bomb, grenade cores and usable
knife are built. Recent playtest fixes are merged; their remaining CS2
measurements are listed beside each item rather than keeping their
implementation tasks open.

The remaining work includes gun modes/revolver/random-recoil fidelity,
Zeus attacks, grenade effects/lineups and additional entity physics,
HUD details, tactical/objective bots, networking and full menus. The
networking work still needs authoritative tick hitbox poses, history and
replay; it must not depend on drawn animation. Rendering and simulation
optimization continue against measured captures, including the dense
hit-effects cost and the still-open 6 ms maximum target.

Before further grenade tuning, finish shared terrain-aware eye state,
then combined movement integration and crouch/modern jump transitions as
listed above. Recheck the recorded Dust2 throws and collect Mirage pairs.
The open #177–179 playtest PRs can be reviewed and tested separately; their
features are not counted as merged here.

Use each phase's remaining items, the weapon TODO and the current status
in `reference/systemization.md` to choose work. The dated playtest and
performance audits preserve evidence; their original dispatch schedules
are not a current queue of missing features.
