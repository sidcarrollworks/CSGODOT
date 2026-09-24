# How CS2's footsteps work

Research on what makes noise in CS2 and how far it carries, for bots'
hearing (roadmap item 23, "reacting to sound"), the radar's own-noise ring
(`round-hud-bots.md` A5 and its build notes) and the footstep sounds
themselves (`reference/cs2-systems.md` S2). Written 2026-09-24. Docs only: no
code or other page changes with it; the corrections it calls for are listed
at the end.

**How each claim is marked.** *Read* means read directly from CS2's shipped
files as SteamDatabase's GameTracking-CS2 publishes them (commit `d45f52d`,
2026-09-23; paths below are in that repository). *SDK* means read from Source
SDK 2013 (`src/game/shared/baseplayer_shared.cpp`), which is a spec only:
CS2 is a different engine, so an SDK number is where CS2 started, not proof
of what it does now. *Community* comes from web search summaries, since the
pages themselves refuse fetches from the cloud. *Inferred* is a reasoned
guess from the above. Nothing here comes from Valve's leaked CS:GO source.

Sources, shortened below:

| Short | File in GameTracking-CS2 |
|---|---|
| FS | `game/csgo/pak01_dir/soundevents/game_sounds_footsteps.vsndevts` (the footstep and landing sound events) |
| PL | `game/csgo/pak01_dir/soundevents/game_sounds_player.vsndevts` |
| SPF | `game/csgo/pak01_dir/scripts/surfaceproperties_footsteps.txt` (surface to sound event) |
| CV | `DumpSource2/convars.txt` |
| SS, CS | `game/csgo/bin/win64/server_strings.txt`, `client_strings.txt` (strings in the DLLs) |
| SCH | `DumpSource2/schemas/` (the game's class layouts) |
| RAD | `game/csgo/pak01_dir/panorama/styles/hud/hudradar.css` and `layout/hud/hudradar.xml` |
| BT | `game/csgo/pak01_dir/scripts/ai/modules/bt_memorize_noises.kv3` |

## The short version

| Question | CS2 | Ours today (main 3975eef) |
|---|---|---|
| Who decides a step | The server, on its tick (*Read*: `mp_footsteps_serverside true`) | A view node's own `_physics_process` (`footsteps.gd:85`), outside the `GameWorld` tick |
| Silent when | Walking (0.52 of max speed) and crouching (0.34). *Inferred:* below 0.55 of the current max speed (`footstep_audible_threshold 0.55`) | Below 131 u/s, or crouched (`footsteps.gd:17, 99`) |
| Steps a second | Not in the files. *SDK:* every 300 ms at 220 u/s and over, 400 ms below, 100 ms more crouched or on a ladder | 0.34 s at 220 and over, 0.5 s below (`footsteps.gd:19-21`) |
| Landing sound when | *Inferred:* falling faster than 260 u/s on touchdown (`sv_min_jump_landing_sound 260`) | Faster than 200 u/s (`footsteps.gd:24`) |
| How far a step carries | Full volume 117 units off, half by 400, a thirtieth by 1095, **silent at 1100** (*Read*, FS) | Godot's inverse distance, 10 m reference, cut at 80 m (3150 units) (`footsteps.gd:60-62`) |
| How far a step is sent | 1250 units (*Read*: `sv_max_distance_transmit_footsteps`) | Everywhere |
| Loudness by surface | A volume per surface (dirt 0.6, glass 1.5, others 0.7 to 1.0) and a quiet, medium or loud class (*Read*, FS) | Every surface at 0 dB |
| Bots hear | Competitive's classic bot takes each `player_footstep` event (*Read*: `CCSBotManager::PlayerFootstepEvent`); its range is not in the files | Nothing |
| The radar's ring | A circle for the range of your own noise (*Read*, RAD; *Community*) | Not built |

## 1. The server decides every step

- **`mp_footsteps_serverside true`** (*Read*, CV 4794, a release convar):
  "Makes the server always play footstep sounds. Clients never calculate
  footstep sounds locally, instead relying on the server." The game rules
  carry the same switch as `m_bPlayAllStepSoundsOnServer` (*Read*, SCH
  `server/CCSGameRules.h`), networked to clients (*Read*, CS
  `NetworkVar_m_bPlayAllStepSoundsOnServer@C_CSGameRules`).
- **The step state lives in the player's movement services** (*Read*, SCH):
  `CPlayer_MovementServices_Humanoid` has `m_flStepSoundTime` (the countdown
  to the next step), `m_nStepside` (which foot), `m_flFallVelocity` and
  `m_surfaceProps` (the surface under the feet). `CCSPlayer_MovementServices`
  adds `m_bMadeFootstepNoise` and `m_iFootsteps`. The pawn has
  `m_flEmitSoundTime`, networked to clients (*Read*, CS
  `NetworkVar_m_flEmitSoundTime@C_CSPlayerPawn`). These are the same fields
  Source's player had (*SDK*: `UpdateStepSound` counts `m_flStepSoundTime`
  down each tick and plays a step when it reaches zero), so a step is a timer
  on the tick, not a foot touching down in the animation (*Inferred*).
- **The client can also play steps from the animation, but not by default.**
  The client DLL alone has `Footstep: %s (Anim: %s, WalkSpeed Parameter:
  %.2f)` and `Footstep sound event invalid: %s (Anim: %s)` (*Read*, CS
  18884-18885), and the animgraph schemas have footstep tags
  (`CFootstepLandedAnimTag` with `FOOTSOUND_Left`/`Right`, SCH
  `animgraphlib/`). *Inferred:* that is the path `mp_footsteps_serverside 0`
  would use; with the default, the server's timer decides and the client only
  plays what it is sent.
- **Every step is a game event.** `player_footstep` with `userid` (*Read*:
  `game/core/pak01_dir/resource/core.gameevents:382`); the server has a
  `player_footstep` string and a `PlayerFootstepEvent` class in its bot
  manager (*Read*, SS 31160, 8454). The repo's schema already has it
  (`src/game/game_events.gd:50`), but nothing sends it.
- **Why it matters here.** Bots hear steps and the radar draws them, so a
  step is game state, not only something heard. That puts it on the
  `GameWorld` tick under `CLAUDE.md`'s rules, with the sound itself played per
  frame by a view that reads it (section 7).

## 2. When a step sounds

- **Walking and crouching are silent; running is not** (*Community*, every
  guide agrees: "Walking (holding the Shift key) silences your steps";
  "Holding the left ctrl key will also make your movement silent on all
  surfaces", counterstrike.fandom.com/wiki/Footsteps via search summary).
- **The threshold is probably 55 % of the current top speed.**
  `footstep_audible_threshold 0.55` (*Read*, CV 3277; development-only, no
  description). *Inferred:* a fraction of the player's current maximum speed,
  since it is below 1 and sits just above the walk modifier (0.52) and well
  above the crouch modifier (0.34, both `reference/movement_constants.md`), so
  walking and crouching both land under it and running lands over it. What
  that gives by weapon (max speeds from `reference/weapons/vdata.csv`):

  | Held | Max speed | Silent below (0.55) | Walk speed (0.52) |
  |---|---|---|---|
  | Knife | 250 | 137.5 | 130 |
  | Glock, USP-S | 240 | 132 | 124.8 |
  | M4A1-S | 225 | 123.75 | 117 |
  | AK-47 | 215 | 118.25 | 111.8 |
  | AWP (unscoped / scoped) | 200 / 100 | 110 / 55 | 104 / 52 |
  | Negev | 150 | 82.5 | 78 |

  Ours is a fixed 131 (`footsteps.gd:17`). The two agree on walking and
  running with every gun; they differ in the gap between 131 and 0.55 of the
  gun's speed (a knife at 135 is silent in CS2 and heard here, *Inferred*)
  and for a scoped AWP moving between 55 and 100 (heard in CS2, silent here,
  *Inferred*). Whether "current max" includes scoping, and whether the
  threshold is on the ground speed or the full speed, is Local check F1.
- **The SDK's floor for any step is 90 u/s standing and 60 crouched or on a
  ladder** (*SDK* `GetStepSoundVelocities`), below which no step sounds at
  all; CS2 moved that decision to the threshold above (*Inferred*).
- **How often.** Not in CS2's files. *SDK* `SetStepSoundTime`: a step every
  **300 ms** at 220 u/s and over, **400 ms** under it; **350 ms** on a
  ladder; **600 ms** knee-deep in water; **+100 ms** crouched or on a ladder.
  The boundary drops to 80 u/s when crouched or on a ladder. Ours is 0.34 s
  and 0.5 s around 220 (`footsteps.gd:19-21`), set by ear. Local check F2.
- **Left and right sound the same.** Every surface maps both `walkleft` and
  `walkright` to the same `*.StepLeft` event (*Read*, SPF), each event a pool
  of 3 to 17 files played at random. The engine still alternates
  `m_nStepside` (*Read*, SCH), for nothing audible (*Inferred*).
- **Steps are blocked from stacking.** `block_matching_events true`,
  `block_match_entity true`, `block_duration 0.15` (*Read*, FS `Base.Footstep`):
  the same player cannot start a second step event within 0.15 s
  (*Inferred* from the names).
- **Ladders** play `CT_Ladder`/`T_Ladder` (metal, volume 0.7, loud class) or
  `*_Wood_Ladder` (*Read*, SPF, FS). The movement services keep
  `m_nLadderSurfacePropIndex` for which (*Read*, SCH).
- **The suit rustles.** `Gear.CT` and `Gear.T` (volume 0.25 and 0.3, heard to
  750 units) and `Heavy.Step` (the heavy armour's bass step, heard to 1310)
  are in the footsteps file (*Read*, FS). What plays `Gear.*` is not in the
  strings; `Gear.JumpLand.CT/T` are named in the server DLL (*Read*, SS
  16514) but set to volume 0.0 (*Read*, FS), so jumping and landing make no
  suit sound. *Inferred:* `Gear.*` rides along with running steps. Local
  check F6.

## 3. Landings

- **`sv_min_jump_landing_sound 260`** (*Read*, CV 10326, a release convar,
  no description). *Inferred:* a landing plays when the fall speed at
  touchdown is over 260 u/s. At gravity 800 that is a fall of
  260² / 1600 = **42.25 units**. A jump onto flat ground lands at the jump's
  own 301.99 u/s (`sv_jump_impulse`), so every flat jump lands loud. Ours
  sounds from 200 u/s (`footsteps.gd:24`), a fall of 25 units, so stepping off
  a 32-unit ledge makes a landing here and none in CS2 (*Inferred*). Local
  check F3.
- **A landing is its own event per surface**, `Land_<Surface>.StepLeft` (*Read*,
  FS), with its own sounds (`land_concrete`, `land_sand`, ...), in the same
  mixgroup as steps. Its distance curve is slightly different (section 4).
- **A walk or crouch does not silence a landing** (*Inferred*: nothing in
  the files ties the landing to speed, and the community lists jumping with
  running as the loudest movement).
- *SDK:* the old stamina rule charged a landing (`sv_staminalandcost 0.05`),
  but CS2 marks it "sv_legacy_jump only" (*Read*, CV 10719); the movement
  research thread covers the 2026 jump.

## 4. How far a step carries

- **Every footstep uses one distance curve** (*Read*, FS `Base.Footstep`,
  inherited by every `CT_*`/`T_*` step; `distance_volume_mapping_curve`,
  distance in units, volume as a factor):

  | Distance | 50 | 117 | 402 | 1095 | 1100 |
  |---|---|---|---|---|---|
  | Volume | 0.45 (-6.9 dB) | 1.0 | 0.49 (-6.2 dB) | 0.03 (-30.5 dB) | 0 |

  So a running step is at its loudest 117 units away, half as loud by 400,
  nearly gone by 1000 and **silent at 1100 units**. That matches the
  community's "running footsteps are audible within approximately 1100 units"
  (*Community*, csdb.gg and similar guides via search summary); others say
  800 to 900, which is where it falls under the game's other sound
  (*Inferred*). The dip close in (0.45 at 50) keeps your own steps, about 45
  units from your ears, below a teammate's beside you (*Inferred*).
- **Landings** (*Read*, FS `Base.Land`): 1.0 out to 37 units, 0.45 at 429,
  0.05 at 1090, silent at 1100.
- **Other movement noise for comparison** (*Read*, PL and FS): picking up a
  gun (`Player.PickupWeaponAudible`) silent at 1100; the suit rustle at 750;
  the heavy armour step at 1310; wading at 1100. A gunshot carries to 2500
  (`reference/research/combat.md`, R6), so footsteps are the short-range
  sound.
- **The server stops sending steps at 1250 units.**
  `sv_max_distance_transmit_footsteps 1250` "Maximum distance to transmit
  footstep sound effects" (*Read*, CV 10281, development-only). It sits just
  past the 1100 where a step goes silent, so a client far away never learns a
  step happened: a sound-based wallhack gets nothing it could not hear
  (*Inferred*). For single player this changes nothing; it matters when the
  netcode sends events.
- **Walls muffle steps.** `occlusion_intensity 0.375`,
  `use_baked_occlusion true`, `reverb_wet 1.0`, `distance_effect_mix 1.0`
  (*Read*, FS). An update in September 2023 "lowered occlusion and distance
  effects for gunfire, footsteps and reloads" (*Community*, search summary of
  csgo.com's news post). The baked occlusion is Steam Audio's, per map, and
  not extracted; Godot has no occlusion, so ours will be clearer through walls
  until something is built.
- **Heard in stereo only close up.** `distance_unfiltered_stereo_mapping_curve`
  goes from 1.0 at 50 units to 0 at 59 (*Read*, FS); *Inferred:* past 59
  units a step is positioned by the engine's 3D audio rather than played as a
  plain stereo file.
- **Steps come from 20 units above the feet** (`position_offset [0, 0, 20]`),
  at the world position, except the local player's own, which follow the
  entity (`use_entity_position_if_local_player`) (*Read*, FS).
- **Ours** (`footsteps.gd:60-62`): inverse distance with a 10 m (394 unit)
  reference, cut at 80 m (3150 units). At 1100 units, where CS2 is silent,
  ours still plays at 0.36 (-8.9 dB), louder than CS2's step at 400; ours goes
  on three times as far.

## 5. Surfaces

- **Surface to sound** (*Read*, SPF): two tables, `ct_player` (75 surfaces)
  and `t_player` (74), naming a `CT_*` or `T_*` event for each surface in
  CS2's surface list. The two sides' events mostly play the same files:
  `concrete_ct_*` is the concrete step for both (*Read*, FS). Surfaces not in
  the table take their parent's (*Inferred*: `reference/surfaces/surfaces.md`
  lists each surface's parents, and the table has no entry for, say, `rock`,
  whose parent is `concrete`).
- **Per-surface volume** (*Read*, FS `volume`): most are 0.9 or 1.0; dirt
  **0.6**, mud and ladders **0.7**, gravel **0.8**, glass and glass bottles
  **1.5**, a gun or shield underfoot **0.5**, the milk crate and car cover
  0.7. Landings: sand 1.2, flesh 0.4.
- **A loudness class on each** (*Read*, FS `metadata`, only in this file):
  `quietfs 600` (sand, grass, carpet, cardboard, wet sand; 17 events),
  `mediumfs 1000` (concrete, default, wood, tile, glass, plastic, rubber; 64),
  `loudfs 1600` (every metal, dirt, mud, gravel, snow, water, foliage,
  ladders, wet concrete and tile; 59), `silentfs` (`CT_Silent`, used for
  the Danger Zone cases). No DLL string reads these tags. *Inferred:* the
  number is a hearing distance in units for that class, meant for whatever
  judges how far a step is heard (the radar's ring or bots) rather than for
  the sound, which goes silent at 1100 on every surface. Local check F4
  settles it.
- **dust2's surfaces, and where ours differs** (ours `footsteps.gd:31-35`,
  CS2's event from SPF by the parent chain, *Inferred* where the surface has
  no entry of its own):

  | Surface | CS2 event (class, volume) | Ours |
  |---|---|---|
  | concrete, default | Concrete / Default (medium, 0.9) | concrete_ct, 0 dB |
  | sand | Sand (quiet, 1.0) | sand |
  | dirt | Dirt (loud, 0.6) | dirt, full volume |
  | gravel | Gravel (loud, 0.8) | not mapped: concrete |
  | rock | parent concrete: Concrete (medium, 0.9) | **gravel** |
  | tile | Tile (medium, 1.0) | tile |
  | Wood and its children | Wood, Wood_Box, Wood_Crate... (medium, 1.0) | wood |
  | solidmetal, metal children | SolidMetal (loud, 1.0) | metal_solid |
  | metalvent | MetalVent (loud, 1.0; plays `metal_auto` files) | metal_vent |
  | metalgrate | MetalGrate (loud, 0.9) | not mapped: `metal*` gives metal_solid |
  | chainlink | ChainLink (loud, 1.0) | metal_chainlink |
  | glass | Glass (medium, 1.5) | glass, 0 dB |
  | pottery | parent glassbottle: GlassBottle (medium, 1.5) | **tile** |
  | computer | parent Metal_Box, which has an entry with no sound, then solidmetal | **plastic_barrel** |
  | rubbertire | parent rubber: Rubber (medium, 1.0) | rubber |
  | carpet | Carpet (quiet, 1.0) | carpet |
  | plastic | parent Plastic_Box: Plastic_Box (medium, 0.7) | not mapped: concrete |

  dust2's ground still exports as all concrete (roadmap item 7c), so its
  sand, gravel and dirt patches step as concrete here until that lands.

## 6. Who hears a step

- **Players**, through the sound, to 1100 units (section 4).
- **Competitive's bots** are the classic `CCSBot` (`round-hud-bots.md` B1).
  Its bot manager listens for `player_footstep` (*Read*, SS 8454
  `PlayerFootstepEvent@CCSBotManager`). A bot remembers one noise:
  `m_noisePosition`, `m_noiseTravelDistance`, `m_noiseTimestamp`,
  `m_noiseSource`, and "bends" it with `m_noiseBendTimer`,
  `m_bentNoisePosition` (*Read*, SCH `server/CCSBot.h`; `round-hud-bots.md`
  B4). Its states include `InvestigateNoiseState` and the chatter
  `HeardNoise` (*Read*, SS 8382, 17104); its debug line is `Heard noise (%s
  from %s, pri %s, time %3.1f)`, so a noise has a priority (*Read*, SS 17103);
  `Noise occurred off the nav mesh - ignoring!` (*Read*, SS 70) means a noise
  is placed on the nav mesh first. *Inferred:* `m_noiseTravelDistance` is the
  distance along the mesh, so a bot judges a step by how far it would walk to
  it, not straight through a wall. **The classic bot's hearing range for a
  step is in no file.** Starting from the sound's own 1100 units keeps bots
  hearing what a player would; Local check F5 measures it.
- **The deathmatch bots' behaviour tree** hears `NOISE` entities within a
  3000-unit sphere, keeping any within 800 and picking at random by distance
  out to 3000 (*Read*, BT; `round-hud-bots.md` B7). That is not competitive,
  but it is the one hearing range Valve wrote down.
- **The radar's ring.** `RadarPlayerSoundSnippet` puts a `PlayerSound` circle
  on your own icon: 1 px white at 25 % alpha, additive; the class
  `player-sound-max` flashes it with a 3 px border for 0.5 s (*Read*, RAD
  css 518-544, xml 47-50 and 97). The client also has a `player-sound-footstep`
  class (*Read*, CS 38099). The circle "indicates how far the sounds that you
  are making (footsteps, shooting...) can be heard" (*Community*,
  primagames.com via search summary). *Inferred:* it is sized by the range of
  the loudest noise you made recently, with the footstep class for a step and
  the max class for the largest, such as a shot. Its size is set in C++, not
  in the layout; check F4.
- **Spectators** see a player's x-ray glow "pop when noise is made"
  (`spec_glow_spike_factor 1.2`, `spec_glow_full_time 1`,
  `spec_glow_decay_time 2`, `spec_glow_silent_factor 0.4`; *Read*, CV
  9543-9556). So each client knows when each player last made noise, which
  `m_flEmitSoundTime` would carry (*Inferred*).

## 7. What it means for the build

For whoever builds bots' hearing (item 23) or the radar (the round HUD); not
a plan anyone has agreed.

- **Steps as simulation state.** Per player, on the tick after movement: the
  step countdown (from `SimClock`, in ticks or seconds, never the frame's
  delta), the side, the fall speed at touchdown, the last noise's position,
  tick and range. When a step or landing is due, find the surface (one ray
  down, as `Footsteps.surface_below` does now) and send `player_footstep`.
  The cost per tick is a comparison per player; the ray runs only on a step,
  about three times a second for a running player, and landings. No new hull
  traces.
- **What the event needs.** CS2's event carries only `userid`; the listener
  reads the pawn's position. The repo's contract matches it
  (`contracts.md` "Players"). A hearing check needs the step's position,
  surface and whether it was a landing on the same tick; reading them from
  the player state keeps the event CS2's shape.
- **The sound as a view.** `Footsteps` would play what the event says, per
  frame, with CS2's curve: Godot's `AudioStreamPlayer3D` has no curve
  setting, so the view sets `volume_db` from the curve at the listener's
  distance when a step starts (steps are shorter than a third of a second)
  and uses `ATTENUATION_DISABLED`, or approximates it with
  `max_distance = 1100` units. Surface volumes multiply in.
- **Hearing as a query.** A bot asks which steps and shots it heard this
  tick within their range (1100 for a step, 2500 for a gun), by nav-mesh
  distance if that proves cheap enough, straight-line otherwise; the radar
  asks the same of the local player's own last noise. Both read the same
  state, so a bot hears exactly what a player would.
- **Beyond CS2.** Nothing here calls for an improvement on CS2's rule
  (walk silent, run heard to 1100); it is what the game's sound play rests
  on. The gap to close is occlusion, which Godot does not model.

## 8. Corrections other docs and code need

Not made here; each belongs to whoever owns the file.

- `src/audio/footsteps.gd` (Sid's local agent owns `src/audio/`):
  - `:17` `QUIET_BELOW 131` becomes 0.55 of the current max speed
    (*Inferred*, check F1).
  - `:19-21` the cadence has no source; the SDK's 300 / 400 ms, +100
    crouched, is the better start until F2.
  - `:24` `LANDING_FALL_SPEED 200` becomes 260 (`sv_min_jump_landing_sound`).
  - `:60-62` the distance falls off as CS2's curve, silent at 1100, instead
    of inverse distance to 3150.
  - `:31-35` `rock` maps to concrete, `pottery` to glass bottle, `computer`
    to solid metal, `metalgrate` and `gravel` get their own sets; each set
    gets CS2's volume (dirt 0.6, gravel 0.8, glass 1.5).
  - `:85` the decision runs in the node's own `_physics_process`, outside
    the `GameWorld` tick (`game_world.gd:16-20` says so); CS2 decides on the
    server, and bots need it, so it moves into the simulation and the node
    only plays it.
- `src/game/game_events.gd:50`: `player_footstep` is in the schema but no
  code sends it.
- `reference/cs2-systems.md:450` (S2): the sound event files are readable
  text in GameTracking-CS2, so the footsteps' volumes and distances are
  Remote now (they are in this page); the other files (weapons, player, world)
  can be read the same way.
- `reference/asset-pipeline.md:51`: "The sound event definitions ... are not
  fetched; those are by ear" is true of the extraction, but the definitions
  are in GameTracking-CS2 and this page has the footsteps'.
- `reference/research/round-hud-bots.md:905`: "Add the 'own noise' circle
  once footstep ranges exist": they exist (1100, or the class numbers if F4
  says so).
- `reference/roadmap.md:491` (item 23, "reacting to sound"): the hearing
  facts are in section 6 here.

## 9. What only Sid can measure (Local)

Each takes CS2 on Sid's machine. The most useful tool is a demo: record a
short one on a private server (`sv_cheats 1`), then parse it with
demoparser2 (MIT, `combat.md` already plans it) for each `player_footstep`
event's tick with the player's velocity, duck state and weapon that tick.

| Check | What to do | What it settles |
|---|---|---|
| F1. The silent threshold | In the demo, speed up slowly from standing (`cl_showpos 1`) with the knife, the AK and the AWP scoped and unscoped; note the speed of the first `player_footstep` | Whether it is 0.55 of the weapon's current max speed |
| F2. The cadence | Run, walk just over the threshold, crouch-run if it makes any, climb a ladder; the ticks between events | 300 / 400 / 350 ms and the +100 when crouched, or CS2's own |
| F3. Landings | Drop off ledges of known height (`cl_showpos` gives the height before and after), and jump in place | Whether a landing needs 260 u/s |
| F4. The radar ring | Screenshot the ring while running on concrete, sand and metal (dust2 has all three), and after a shot; measure its radius against the overview scale (`MapOverview`) | Whether the ring is 1100 for every surface, or 600 / 1000 / 1600 by class |
| F5. Bots' hearing | `bot_stop 1` with a bot facing away; run toward it from 1500, 1100, 800 units (`cl_showpos` for the distance) and note when it turns; repeat walking | The classic bot's footstep range |
| F6. The suit | Listen for the suit rustle while running and walking, with and without heavy armour (`Gear.*`, `Heavy.Step`) | When the suit sound plays |
| F7. How far a step is heard | Stand still while a bot runs straight past at a known line; note (or record) where its steps fade, with `cl_showpos` for both positions | That a step fades out at 1100 as the file says, occlusion aside |
