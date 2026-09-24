# How CS2's audio works

Research on CS2's whole sound system for the Godot clone, written 2026-09-24
after Sid asked to widen the footsteps research "to the entire audio system".
Docs only: no code or other page changes with it. The corrections it calls for
are listed on each page, and the most important ones are summarised here.

| Page | What it covers |
|---|---|
| [`audio-engine.md`](audio-engine.md) | What a sound event is and how its volume is worked out, the mixer and its ducking, reverb, occlusion, HRTF and the audio settings menu, how sounds reach clients, and how each maps onto Godot |
| [`audio-gameplay.md`](audio-gameplay.md) | Every sound that tells a player something: gunfire for every gun, handling and the new silent reload, bullets, hits and kills, grenades and deafening, the bomb, movement besides steps, who is sent what, and what bots hear |
| [`footsteps.md`](footsteps.md) | Steps and landings: who decides a step, when it sounds, how far it carries, surfaces, bots and the radar's ring |
| [`audio-round.md`](audio-round.md) | The round's sounds in order, the buy menu, the announcer, radio, agent voice lines, callouts and bot chatter, music kits, and dust2's ambience |

**Sources, newest and primary first.** Every number comes from the newest
source that has it:
1. CS2's own shipped files at the newest build, from SteamDatabase's
   GameTracking-CS2 commit `d45f52d`: **CS2 build 2000915, patch 1.41.8.3,
   2026-09-23** (`game/csgo/steam.inf`).
2. Valve's own release notes, dated as Valve posted them, from the archive
   ckreisl/cs-updates-as-json @656981c (231 posts, 2023-03-22 to 2026-09-22).
3. Community pages, through search summaries only (the pages refuse fetches
   from the cloud), dated where the summary gives a date.
4. Older code, Source SDK 2013, only where nothing newer has the fact, and
   marked as older and not confirmed for CS2.

Every claim on every page is marked *Read*, *Valve*, *Community*, *SDK* or
*Inferred*. Nothing comes from Valve's leaked CS:GO source.

## The short version

- **A CS2 sound is a sound event, not a file.** Each event names its files and
  carries a volume, a mixgroup and a hand-drawn curve from distance in units
  to loudness. It also sets random pitch and volume, how many copies one
  player may play at once, and how much occlusion and reverb it takes. Almost
  every gameplay sound uses one operator stack, `csgo_mega`, which multiplies
  the mixgroup's level, the event's volume and the curve, among other factors
  (`audio-engine.md` section 1). Ours plays file sets through Godot's inverse
  distance falloff, with levels set by ear.
- **The server decides what makes a sound, and the client decides how it
  sounds.** The server starts events and sends them to the clients within
  range: steps to 1250 units, gunfire to 9000. Each client works out the
  curve, occlusion, reverb, HRTF and the mix on its own (`audio-engine.md`
  sections 3 to 5). For us, the tick records what happened and a view plays it
  per frame. None of that adds hull traces or disk reads to the tick.
- **How far each sound carries** (all *Read*, build 2000915):

  | Sound | Silent at (units) | Page |
  |---|---|---|
  | Running step, landing | 1100 (loudest at 117) | footsteps.md |
  | Reload, dry fire, picking up a gun | 1100 | audio-gameplay.md 1.3 |
  | The same reload held silent (since 2026-09-22) | at 0.07 of the volume, the curve reached five times sooner | audio-gameplay.md 1.3 |
  | Unsilenced gunshot, near layer | about 2500 (full to 175) | audio-gameplay.md 1.1 |
  | Unsilenced gunshot, distant layer | from 800, peaks around 2350, 0.10 at 2869 | audio-gameplay.md 1.1 |
  | Silenced gunshot (M4A1-S, USP-S, MP5-SD) | 1400, no distant layer | audio-gameplay.md 1.1 |
  | Bullet impact | 600 (glass 1000) | audio-gameplay.md 2.1 |
  | Grenade throw / bounce | 1100 / 1700 | audio-gameplay.md 4.1 |
  | HE, flash, smoke detonation | 2700, 2740, 2090 near, each with a distant layer | audio-gameplay.md 4.2 |
  | Bomb beep | 1300 | audio-gameplay.md 5 |
  | Bomb plant / defuse start | 4100 / 2000 | audio-gameplay.md 5 |
  | Announcer, agent voice lines | no fall-off: heard as a radio | audio-round.md 2 |

- **The mix.** CS2 has 60 mixgroups at fixed levels: weapons 0.6, footsteps
  0.8, bullet impacts 0.3, explosions 0.7, ambient 0.45 and voice 0.34, among
  others. Mix layers duck groups for a moment: when your shot hits, distant
  gunfire and ambience drop for about 0.3 s (Valve, 2025-05-15). The bomb's
  shockwave and the death camera have layers of their own. No layer turns
  music down under gunfire (`audio-engine.md` section 2). Ours has no buses.
- **Occlusion and HRTF live only on the client.** Occlusion is a filter
  worked out from four rays with one bounce; Steam Audio's baked occlusion is
  off (`snd_use_baked_occlusion 0`). Steam Audio's HRTF is always on, and
  sounds very close to you play in plain stereo (`audio-engine.md` sections 3
  and 4). Godot has neither.
- **Music and the announcer are client-side and quiet by default.** In
  competitive, the round start and action music default to 0; the bomb and
  ten-second music to 0.04; round end, MVP and death camera to 0.16. The
  ten-second warning is music, not a beep. Every music cue uses your own kit
  except the MVP anthem, which uses the MVP's (`audio-round.md` sections 1
  and 3).
- **Bots hear through game events.** Competitive's classic bot listens to
  weapon fire, reloads, zooms, bullet impacts, footsteps, grenade bounces and
  detonations, doors and the bomb's beep. The files give no hearing range
  for it; the deathmatch bots' behaviour tree hears noises within 3000 units
  (`audio-gameplay.md` section 8, `footsteps.md` section 6).

## What it means for the build

Nothing here is agreed as a plan; it is what the research points to.

1. **Game state first.** A shot, a reload part and whether it was silent, a
   step, a landing, a detonation, a bomb beep and a flash's strength are
   facts on the `GameWorld` tick, sent as the `GameEvents` CS2 uses
   (`weapon_fire`, `player_footstep`, `bomb_beep` and so on). Bots and the radar
   read the same facts, so a bot hears what a player would. Today views start
   sounds from `shot_traced`, a signal fired inside the tick
   (`player_sim.gd:138`, `player_view.gd:157-160`, `bot.gd:381-384`), and
   `player_footstep` is never sent.
2. **One table of sound events, generated from CS2's text files.** A script
   turns the `.vsndevts` events we use into a table in `reference/`: files,
   volume, mixgroup, curves, pitch and volume ranges, limits, blocks and child
   events, like the other generated tables. That retires every level set by
   ear in `src/audio/`, `c4_view.gd` and `bullet_impacts.gd`, and it moves
   `reference/cs2-systems.md` S2 from Local to Remote.
3. **A view that plays events the way CS2 does, per frame, on the client.**
   `ATTENUATION_DISABLED`, with `volume_db` set from the event's curve by the
   listener's distance; a distant layer as a second player; one Godot bus per
   mixgroup at CS2's levels; mix layers as short bus ramps; instance limits and
   blocks per player and event (`audio-engine.md` section 6).
4. **Measured improvements beyond CS2**, each client-only, so none costs the
   server anything: an elevation cue or an HRTF for height, which players
   criticise most; capped per-frame occlusion rays; a ring-volume setting
   for the flashbang. When the netcode comes, one server-side option costs a
   squared-distance compare per recipient per event: cull each sound by its
   curve's end, as CS2 does for steps at 1250.

## The biggest differences today

Read on main 3975eef. Each page lists its own with file:line; these are the
ones a player would notice first.

- Ranges: ours carry far too far. Gunfire uses inverse distance to 300 m
  (11,811 units), impacts and steps to 80 m (3150 units), and the bomb to
  300 m. A silenced shot carries as far as a loud one
  (`weapon_sounds.gd:56-68`, `bullet_impacts.gd:85-86`, `footsteps.gd:60-62`,
  `c4_view.gd:80-81`).
- Missing: grenade sounds (none at all), distant gunfire layers, bots'
  reloads, the victim's and onlookers' hit sounds, a hit on an unarmoured
  body, and every round, announcer, radio, music and ambient sound.
- Wrong files: the kill sound plays `bodyshot_kill_01`, which no CS2 event
  uses. The bomb's beep stem mixes site A's and site B's beeps at random
  (`sound_bank.gd:46-49`). The AK's fire set includes `ak47_03`, which its
  event leaves out.
- Round events: `MatchState` only emits Godot signals (`match_state.gd:181`),
  so `round_start`, `round_freeze_end` and `round_end` never reach the
  `GameEvents` the economy and the bomb listen to. That wiring is section 5
  of `reference/systems/contracts.md`, which the local agent is doing now; the
  round's sounds hang off those events.

## What players criticise and want

Sid asked (2026-09-24) to track these. Each page has its own dated list; the
most requested, across all of them:

| Critique | Pages | Could apply here |
|---|---|---|
| Height and direction are hard to hear, worst on maps with levels | audio-engine 9, audio-gameplay 10, footsteps 8 | Yes; Godot has no HRTF, so ours starts worse. Client-only fix, measured by a blind direction and height test |
| Hearing through walls, and occlusion that muffles too much | audio-engine 9, audio-gameplay 10 | Yes; client-only rays with a per-frame cap |
| Hits hard to count at high fire rates | audio-gameplay 10 | Already on the shooter's frame; a short duck of the weapons bus is the option |
| The flashbang's ringing is unpleasant | audio-gameplay 10 | A ring-volume setting that keeps the muffle |
| Music too loud or too quiet by mode; the ten-second warning hidden inside music volume | audio-round 6 | A ten-second cue with its own level, independent of music volume |
| Steps too quiet next to gunfire; your own steps masking others' | footsteps 8 | CS2's own curve already quiets your own steps; louder enemy steps are an option to measure |

## Local checks

Only Sid's copy of CS2 can settle these. The full lists are at the end of each
page: F1 to F8 in `footsteps.md`, the engine's A1 to A8, gameplay's L1 to L8
and the round's own. The ones the others depend on:
- What a distance curve does past its last point (the distant gunfire layers
  and the bomb's blast end above zero): audio-engine A1, audio-gameplay L1.
- The threshold for a silent step and the step cadence, from one demo parsed
  with demoparser2: footsteps F1 and F2.
- How strong the flashbang's and the HE's deafening is, and how long it lasts:
  audio-gameplay and audio-engine.
- dust2's soundscape entities, which place its ambience: audio-round.
