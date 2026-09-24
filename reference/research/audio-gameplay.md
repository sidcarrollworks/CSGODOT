# What a CS2 player hears: gameplay sounds

Research for the Godot 4.7 clone, 2026-09-24. This page covers every sound that
tells a player something about the game: gunfire, bullets, hits and kills,
grenades, the bomb, movement other than footsteps, who is sent each sound, and
which of them bots hear. Footsteps and landings are done in
`reference/research/footsteps.md` and are only linked here. The audio engine
itself (what each curve field means past its last point, mixing, occlusion,
HRTF) is in `audio-engine.md`; where a number here depends on it, the page
says so. `audio.md` lists all the audio pages.

## Sources and their dates

Primary and current sources come first. Every *Read* claim is from one
GameTracking-CS2 checkout, commit d45f52d, which is **CS2 build 2000915,
PatchVersion 1.41.8.3, 2026-09-23** (the newest at the time of writing). Paths
below are relative to that checkout.

| Key | Source | Date or build |
|---|---|---|
| WPN | `game/csgo/pak01_dir/soundevents/game_sounds_weapons.vsndevts` (748 events), by line | build 2000915 |
| PLR | `game/csgo/pak01_dir/soundevents/game_sounds_player.vsndevts` | build 2000915 |
| PHY | `game/csgo/pak01_dir/soundevents/game_sounds_physics.vsndevts` | build 2000915 |
| WLD | `game/csgo/pak01_dir/soundevents/game_sounds_world.vsndevts` | build 2000915 |
| ANN | `game/csgo/pak01_dir/soundevents/vo/announcer/game_sounds_cs2_classic.vsndevts` | build 2000915 |
| STK | `game/csgo` sound stack `soundstacks_csgo_mega.vsndstck` (the `csgo_mega` operator graph every gameplay event uses; `snd_event_browser_default_stack "csgo_mega"`, `game/csgo/gameinfo.gi:209`) | build 2000915 |
| DSP | `game/core/pak01_dir/scripts/dsp_presets.txt` | build 2000915 (core engine file, carried from Source 1) |
| WV | `game/csgo/pak01_dir/scripts/weapons.vdata`, `m_aShootSounds` per gun | build 2000915 |
| CV | `DumpSource2/convars.txt`, by line | build 2000915 |
| SS, CS | `game/csgo/bin/win64/server_strings.txt`, `client_strings.txt` (names compiled into the DLLs) | build 2000915 |
| SCH | `DumpSource2/schemas/{server,client}/<Class>.h` | build 2000915 |
| PB | `Protobufs/cstrike15_usermessages.proto` (UM), `cs_gameevents.proto` (CGE), `gameevents.proto` | build 2000915 |
| GE | `game/csgo/pak01_dir/resource/mod.gameevents` | build 2000915 |
| BT | `game/csgo/pak01_dir/scripts/ai/modules/bt_memorize_noises.kv3`, `ai/rush/bt_default.kv3` | build 2000915 |
| *Valve* | Valve's own CS2 release notes, archived as `ckreisl/cs-updates-as-json` commit 656981c, `data/cs2/updates_raw.json` (231 posts, 2023-03-22 to 2026-09-22). Each claim gives the post's date (UTC) and quotes the line | the date given |
| *Community* | A WebSearch summary of the named page; most pages refuse fetches. Dated where the summary shows a date. Used only where Valve's notes say nothing | as given |
| *SDK* | Source SDK 2013, read as a spec only | 2013, not confirmed for CS2 |

Labels: *Read* is read directly from a file above. *Valve* is a line of
Valve's release notes, dated. *Community* is a search summary, kept only
where Valve's notes are silent (and each such place says so). *Inferred* is
my reasoning. Nothing here comes from Valve's leaked CS:GO source.

The repo is compared at `main` commit 3975eef (2026-09-23). Its `src/` is
identical to the research branch's, so every `src/` line reference holds on
`main`. `footsteps.md`, `audio-engine.md` and this page arrive on `main`
together.

How to read the numbers. Each event has a `volume` (a linear factor), a
`mixgroup`, and a `distance_volume_mapping_curve` of points
`distance:factor` in units (*Read*, STK: the curve's output multiplies the
event's volume). "Silent at N" means the curve reaches 0 at N. A curve whose
last point is above 0 (the distant gunfire layers, the bomb's blast) leaves
the question of what happens past the last point to `audio-engine.md` (1.2);
this page gives both readings where it matters. `instance_limit` is the most
copies one entity may play at once, the oldest stopped first
(`soundevent_limiter ... match_entity=1, stop_oldest=1`, *Read*, STK).
`block_duration`/`block_distance` stop the same event restarting within that
time and distance (*Read*, STK `soundevent_block`). Child events
(`soundevent_01`) start with their parent (*Read*, STK
`start_soundevent_list`). A `metadata` entry `localplayeronly` marks a sound
only the player making it hears (*Read* as the tag; *Inferred* as the
behaviour, from the events it sits on: every draw, inspect and pin pull).

The repo's existing pages already hold: gunshot ranges in
`reference/research/combat.md` R6 (this page gives the per-gun table behind
them), the whiz convars in combat.md R4, the bomb's beep cadence and sound
names in `round-bomb-grenades.md` 1.3, bots' hearing in `round-hud-bots.md`
B4 and B7, the radar's sound ring in `round-hud-bots.md` A-radar and
`footsteps.md` section 6, and all footstep, landing, ladder, wading and suit
rustle numbers in `footsteps.md`.

## The short version

| What | CS2 (build 2000915) | Ours today (repo `main`, 3975eef, 2026-09-23) |
|---|---|---|
| Unsilenced gunshot | Near layer full to 175 units, 0.74 at 440, 0.33 at 1288, about 0 at 2500; a separate distant layer rising from 800 units to about 0.34 to 0.54 at 2350 (*Read*, WPN) | One file set, inverse distance with a 787-unit reference, cut at 11 811 units, -6 dB (`weapon_sounds.gd:34,59-62`) |
| Silenced (M4A1-S, USP-S, MP5-SD) | Near layer only, silent at 1400, no distant layer (*Read*) | Same player and range as an unsilenced shot: heard to 11 811 units |
| Reload | 0.4 to 1.2 volume, 0.36 at about 267 units, silent at 1100. Since 22 Sep 2026, holding reload makes it "silent": volume x0.07 and distance x5 (*Read* + *Valve* 2026-09-22) | Timed parts played for the player only; bots' reloads make no sound (`bot.gd` calls only `shot()`) |
| Draw, inspect, silencer on/off, pin pull | Heard only by the player doing it (`localplayeronly`) (*Read*) | Draw plays for bots too, spatially (`weapon_sounds.gd:75`, `bot.gd:150`) |
| Hit feedback | Separate sounds for the attacker, the victim and onlookers, by body/head and armour/no armour, damage/death (*Read*, PLR) | Attacker only; a kill plays `player/bodyshot_kill_01`, which no CS2 event uses; an unarmoured body hit plays nothing (`weapon_sounds.gd:33,108-114`) |
| Grenades | Throw heard to 1100, bounce to 1700, HE blast silent at 2700 plus a distant layer to 2800 and beyond, flash to 2740 plus distant, smoke to 2090 plus distant, molotov/incendiary to 3000/2000 plus distant, fire loop to 1200 (*Read*) | No grenade sounds at all (`grenade_view.gd` has none) |
| Flashbang and HE deafening | `Flashbang.Ring.Short/Medium/Long` plus DSP muffle presets 134 to 136; HE "shock ring" presets 137 to 139 (*Read* names; *Inferred* wiring) | None |
| Bomb beeps | `C4.PlantSound` (site A) and `C4.PlantSoundB` (site B, pitch 0.9), silent at 1300; separate `_10sec` versions, added 2023-10-17 (*Read*; *Valve* for the 10-second sound; A/B split *Community*, Valve's notes silent) | One guessed stem `weapons/c4/c4_beep`, which by `SoundBank`'s prefix rule mixes the A and B beeps at random (`c4_view.gd:18`, `sound_bank.gd:46-49`) |
| Who is sent what | Gunfire: every client within 9000 units (`broadcast_distance_override 9000`); footsteps: within 1250 (`sv_max_distance_transmit_footsteps`) (*Read*) | Single player; no send filter yet |

## 1. Weapons

### 1.1 Gunfire, every gun

Each gun's shot is `WEAPON_SOUND_SINGLE` in its `m_aShootSounds` (*Read*, WV);
the silenced mode is `WEAPON_SOUND_SPECIAL1`, and the Negev's accurate burst
`WEAPON_SOUND_SINGLE_ACCURATE` (`Weapon_Negev.SingleFocused`). The near event
starts its distant layer as a child (*Read*, WPN `soundevent_01`).

Common to every unsilenced near layer, unless the table says otherwise
(*Read*, WPN, e.g. `Weapon_AK47.Single` 20442): mixgroup `Weapons`; curve
`25:0.8 30:1.0 175.7:1.0 440:0.74 1288:0.33 2500:~0` (the last point is 0.00
to 0.03 by gun); `instance_limit 1` per shooter, so a new shot cuts the tail of
the last; `position_offset [0,0,60]` (the sound comes from 60 units above the
feet); `occlusion_intensity 0.6`, and `use_baked_occlusion`, which does nothing
while `snd_use_baked_occlusion` is 0 as it is in this build (`audio-engine.md`
section 3);
`broadcast_distance_override 9000`.

Common to every distant layer (*Read*, WPN, e.g. `Weapon_AK47.SingleDistant`
20536): mixgroup `WeaponsDistant`; silent below its start; rises to a peak
about 1900 to 2370 units out; `0.10` (0.17 to 0.19 for three guns) at its last
point, 2868.6 units; occlusion 0 to 0.3 (the AK's is 0.0); `instance_limit` 2
(1 for the MP9, P90, SG 553, M249, Negev).

| Gun (class) | Near event | Near vol | Near curve differs | Distant vol | Distant: starts, peak, at 2869 | Notes |
|---|---|---|---|---|---|---|
| Glock-18 (`weapon_glock`) | `Weapon_Glock.Single` | 1.0 | pitch 0.9 | 0.7 | 800, 0.34 at 2354, 0.10 | children `Element_CRB` (0.2, to 2800) and `Element_Click` (0.3, to 300) |
| P2000 | `Weapon_hkp2000.Single` | 1.0 | | 1.0 | 459, 0.58 at 2336, 0.10 | |
| USP-S, silencer off | `Weapon_USP.Single` | 0.8 | | none | | no distant layer at all |
| USP-S, silenced | `Weapon_USP.SilencedShot` | 0.6 | `164:1.0 428:0.62 804:0.23 1300:0.05`, silent at 1400 | none | | no 9000 broadcast; `instance_limit 2` |
| Dual Berettas | `Weapon_ELITE.Single` | 1.0 | pitch 1.1 | 1.0 | 800, 0.23 at 2369, 0.10 | |
| P250 | `Weapon_P250.Single` | 0.9 | | 1.0 | 500, 0.34 at 1918, 0.10 | |
| Tec-9 | `Weapon_tec9.Single` | 0.8 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| Five-SeveN | `Weapon_FiveSeven.Single` | 1.0 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| CZ75-Auto | `Weapon_CZ75A.Single` | 0.8 | | 0.6 | 800, 0.25 at 2352, 0.10 | |
| Desert Eagle | `Weapon_DEagle.Single` | 0.9 | | 1.0 | 800, 0.34 at 2354, 0.10 | distant pitch 0.9 |
| R8 Revolver | `Weapon_Revolver.Single` | 0.8 | | 0.7 | 800, 0.34 at 2354, 0.10 | distant pitch 1.3 |
| Nova | `Weapon_Nova.Single` | 0.9 | `1178:0.31`, ~0 at 2150 | 1.0 | 459, 0.38 at 1942, 0.10 | block 0.1 s / 20 units |
| XM1014 | `Weapon_XM1014.Single` | 0.8 | | 1.0 | 434, 0.33 at 1942, 0.10 | block 0.1 s / 20 |
| Sawed-Off | `Weapon_Sawedoff.Single` | 0.9 | | 1.0 | 800, 0.42 at 1828, 0.19 | block 0.1 s / 20 |
| MAG-7 | `Weapon_Mag7.Single` | 0.9 | | 1.0 | 800, 0.34 at 2354, 0.10 | block 0.1 s / 20 |
| MAC-10 | `Weapon_MAC10.Single` | 0.65 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| MP9 | `Weapon_MP9.Single` | 0.75 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| MP7 | `Weapon_MP7.Single` | 1.0 | | 1.0 | 484, 0.34 at 2354, 0.10 | |
| MP5-SD | `Weapon_MP5.Single` (both modes) | 1.0 | silenced curve, silent at 1400 | none | | keeps the 9000 broadcast (*Read*, WPN 6431) |
| UMP-45 | `Weapon_UMP45.Single` | 0.9 | | 1.0 | 336, 0.34 at 1942, 0.10 | |
| P90 | `Weapon_P90.Single` | 0.8 | | 1.0 | 90, 0.34 at 2008, 0.10 | distant layer starts almost at the gun |
| PP-Bizon | `Weapon_bizon.Single` | 0.8 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| Galil AR | `Weapon_GalilAR.Single` | 1.0 | pitch 1.1 | 1.0 | 800, 0.50 at 2352, 0.17 | |
| FAMAS | `Weapon_FAMAS.Single` | 0.9 | | 1.0 | 800, 0.34 at 2354, 0.10 | child `Weapon_FAMAS.Mech` (0.35, to 914) |
| AK-47 | `Weapon_AK47.Single` | 1.1 | | 0.5 | 800, 0.54 at 2336, 0.10 | loudest near layer of the rifles |
| M4A4 | `Weapon_M4A4.Single` | 1.0 | pitch 1.2 | 1.0 | 800, 0.34 at 2354, 0.10 | |
| M4A1-S, silencer off | `Weapon_M4A1.Single` | 1.0 | pitch 1.1 | 1.0 | 800, 0.34 at 2354, 0.10 | distant file `m4a1_us_distant` |
| M4A1-S, silenced | `Weapon_M4A1.Silenced` | 0.8 | `25:0.7`, then the silenced curve, silent at 1400 | none | | no 9000 broadcast (*Read*, WPN 14263) |
| SG 553 | `Weapon_sg556.Single` | 0.9 | | 1.0 | 800, 0.34 at 2354, 0.10 | |
| AUG | `Weapon_AUG.Single` | 0.9 | | 1.0 (default) | 800, 0.41 at 2328, 0.10 | distant delay 0.02 s |
| M249 | `Weapon_M249.Single` | 1.7 | `25..175:0.8 1157:0.29 2500:0.01` | 1.0 | 352, 0.49 at 2082, 0.10 | child `Weapon_M249.Jangle` (0.15, to 237) |
| Negev | `Weapon_Negev.Single` / `.SingleFocused` | 1.0 | | 1.0 | 402, 0.34 at 2354, 0.10 | the accurate sound swaps in below 0.02 inaccuracy (combat.md R3) |
| SSG 08 | `Weapon_SSG08.Single` | 0.8 | `578:0.76 1343:0.39 2500:0.03` | 1.0 | 525, 0.34 at 2016, 0.10 | block 0.1 s / 20 |
| AWP | `Weapon_AWP.Single` | 1.0 | `175:1.0 ... 2800:0.05` | 1.0 | 800, 0.34 at 2354, 0.10 | block 0.3 s / 20; heard furthest of the near layers |
| G3SG1 | `Weapon_G3SG1.Single` | 1.0 | | 1.0 | 800, 0.50 at 2336, 0.18 | block 0.1 s / 20 |
| SCAR-20 | `Weapon_SCAR20.Single` | 1.0 | | 1.0 | 800, 0.34 at 2354, 0.10 | block 0.1 s / 20 |
| Zeus x27 | `Weapon_Taser.Single` | 0.35 | `175:1.0 848:0.26`, silent at 2420 | none | | child `Weapon_Taser.Charging` (0.2, silent at 504, delay 0.25 s) |

Notes.
- *Read*: the silenced events are the only gunshots without
  `broadcast_distance_override 9000`, and all three silenced curves are the
  same shape, silent at 1400 (combat.md R6 already says this).
- *Inferred*: beyond 2869 units the distant layer either holds 0.10 (heard
  across any map at about -20 dB relative to its own volume) or falls to 0
  just past it along the last tangent (-0.000835 a unit, which reaches 0 near
  2980). `audio-engine.md` 1.2 infers the first (a curve holds its last
  value); a local check (L1 below) settles it by ear on a long map.
- `snd_max_pitch_shift_inaccuracy 0.08` (*Read*, CV 8925) caps the pitch
  shift that `m_flInaccuracyPitchShift` applies to shots (combat.md R3 has
  the Negev's -50).

Valve's dated changes behind these numbers (*Valve*, newest first):

| Date | Valve's line | What it explains |
|---|---|---|
| 2025-10-14 | "Improved core utilization of some client particle and sound effects processing, reducing overall CPU usage when players are shooting." | Shot sounds are processed on the client (section 7) |
| 2025-05-15 | "Shortened front end of the AK-47 fire sound." | The AK's current near file |
| 2024-02-07 | "Replaced the M249 fire sound effect" | The M249's own curve and 1.7 volume |
| 2023-11-09 | "Fixed a case where unsilenced m4a1-s did not have any distant gunfire sounds" | The unsilenced M4A1-S's distant layer, `m4a1_us_distant` |
| 2023-09-28 | "Weapon sounds will no longer sound like they come from the spot you are zoomed into" | The shot is placed at the shooter (`position_offset [0,0,60]`) |
| 2023-09-16 | "Adjusted silenced weapon falloff" | The shared silenced curve, silent at 1400 (*Inferred* link) |
| 2023-09-13 | "Lowered occlusion and distance effects for gunfire, footsteps and reloads" | `occlusion_intensity 0.6` on the near layer, 0 to 0.3 on the distant (*Inferred* link) |
| 2023-06-30 | "Added distance effects to all positional sound sources." and "Fixed missing low frequencies at certain distances away from sound sources such as grenades and weapon fire." | The distant layers (`audio-engine.md` for the filters) |
| 2023-06-20 | "Improved sound synchronization for the first bullets during automatic fire" | Shots start from the fire-bullets message on the tick (section 7) |

### 1.2 Knife and Zeus

| Event | Vol | Curve (silent at) | Who hears | Source |
|---|---|---|---|---|
| `Weapon_Knife.Slash` (a miss) | 0.3 | `72:1.0 352:0.28`, 800 | everyone | *Read*, WPN 21216 |
| `Weapon_Knife.Swish.Light` / `.Heavy` | 0.03 / 0.04 | 548 | everyone | *Read* |
| `Weapon_Knife.Hit.Light.Flesh`, `.Heavy.Flesh`, `.Light.Backstab.Flesh`, `.Heavy.Backstab.Flesh` | 1.0, 0.9, 0.3, 0.2 (plus children: thuds 0.3, `.Heavy.Flesh.Add` 0.8) | `62:1.0 302:0.43`, 1000 | everyone | *Read*, WPN 42355 onwards; named in both DLLs (SS 22848-22849, CS 27530-27533) |
| `Weapon_Knife.HitWall` | 1.0 | 1000 (delay 0.09 s) | everyone | *Read* |
| `Weapon_Knife.Stab` | 1.0 | 1000, mixgroup `BulletImpacts` | everyone | *Read* |
| `Weapon_Knife.Deploy`, `.Draw.*`, `.Inspect.*`, `Knife.Catch*` | 0.06 to 0.3 | | only the holder (`localplayeronly`) | *Read* |
| `Player.DamageBody.Knife.AttackerFeedback` and `...Armor.Knife...` | 1.0 / 1.2 | | the attacker; the file is `common/null.vsnd`, i.e. silent | *Read*, PLR |
| `Weapon_Taser.Hit` | 0.6 | `203:1.0 611:0.28`, 2300 | everyone | *Read*, WPN 21482 |
| `Player.DeathTaser` / `_F` | 0.5 | `76:1.0 452:0.31`, 1000 | everyone | *Read*, PLR 804 |
| `Weapon_Taser.ChargeReady`, `.ChargeNotReady`, `.Draw` | 0.3 to 0.6 | | only the holder | *Read* |

So a knife kill carries to about 1000 units and a knife's hit feedback for the
attacker is the hit sound itself, not a separate feedback event (*Inferred*).

Valve's knife and Zeus changes (*Valve*):
- 2026-01-21: "Knife impact sounds are now unique based on primary fire or
  alt fire swings as well as front and rear attacks. This reflects the
  different damage amounts dealt with each attack", "Higher fidelity knife
  draw and inspect sounds". This is why there are four `Weapon_Knife.Hit.*`
  flesh events (light, heavy, and a backstab of each). Further "Various knife
  sound adjustments" followed on 2026-01-27 and 2026-01-30. (combat.md section
  2 cites this change through HLTV; Valve's note is the primary source.)
- 2024-02-07: "Replaced the Zeus charging, charge not available and charge
  ready states sound effects" (the `Weapon_Taser.Charging`, `.ChargeNotReady`,
  `.ChargeReady` events above).
- 2023-11-02: "Knife attacks no longer predict damage effects or sounds on the
  client". So the knife's hit sound waits for the server, unlike gunfire's
  feedback (section 7).
- 2023-10-17: "Reduced falloff distance of knife impact and swish sounds"
  (the 548 to 1000 unit ranges above).

### 1.3 Handling: dry fire, reload, draw, zoom, silencer, pickup, drop, inspect

| Sound | Event (example) | Vol | Curve (silent at) | Heard by | Source |
|---|---|---|---|---|---|
| Dry fire | `Default.ClipEmpty_Rifle` / `_Pistol` | 1.0 | `34:1.0 370:0.32`, 1100 | everyone; the rifle one blocks repeats for 0.1 s | *Read*, WPN 22993; SS 15109-15110 |
| Low-ammo click | `Default.NearlyEmpty` (`WEAPON_SOUND_NEARLYEMPTY`) | 1.5 | `34:1.0 370:0.32`, 1100, delay 0.05 s | not tagged local, so everyone (*Inferred*) | *Read*, WPN 405 |
| Magazine out/in, add ammo | `Weapon_AK47.Clipout`, `.AddAmmo`... | 0.4 to 1.2 (AK clipout 1.0, add ammo 1.2) | `50:1.0 267:0.36`, 1100 | everyone | *Read*, WPN 20811 |
| Bolt, slide | `Weapon_AK47.BoltPull`, `Weapon_USP.Slideback`... | 0.5 to 1.0 | `37:1.0 242:0.39` or `53:1.0 204:0.32`, 1100 | everyone | *Read* |
| Shotgun shell/pump | `Weapon_Nova.Pump` 1.0; `Weapon_Nova.AddAmmo` 0.3 | | `409:1.0`, 1100; the Nova's add-ammo is `localplayeronly` | pump: everyone | *Read* |
| The same parts inside a draw | `*_Q` events (`Weapon_AK47.BoltPull_Q`...) | 0.3 to 0.5 | | only the holder | *Read* |
| Draw | `Weapon_AK47.Draw` etc. | 0.05 to 0.5 | `396:1.0`, 1106 | only the holder | *Read*, WPN 20607 |
| Inspect | `Weapon_AK47.Inspect_F006`, `Inspect.Gear.*` | 0.01 to 0.1 | | only the holder | *Read* |
| Zoom in / out | `Weapon_AWP.Zoom` 0.1, `Weapon_AUG.ZoomIn` 0.05, `ZoomOut` 0.3, `Weapon_SCAR20.ZoomOut` 0.0 | | `40:1.0 242:0.46`, 597 | everyone within about 600 | *Read*, WPN 33292 |
| Unscope (snipers) | as above | | | nobody since 22 Sep 2026: "Un-scoping a sniper weapon no longer produces a sound" | *Valve*, 2026-09-22. The event files still carry zoom-out volumes, so the change is in code (*Inferred*). On 2025-10-29 Valve "Added scope in/out sound prediction to play immediately for local player" (*Valve*) |
| Silencer on/off | `Weapon_M4A1.Silencer_On/Off`, `Weapon_USP.AttachSilencer`, `...SilencerScrew1-5` | 0.3 | | only the holder | *Read*, WPN 14392 |
| Fire-mode switch | `Weapon.AutoSemiAutoSwitch` | 0.5 | `62:1.0 279:0.33`, 600 | everyone | *Read*, WPN 131; SS 22843 |
| Weapon pickup (others hear) | `Player.PickupWeaponAudible` 1.0; `Player.PickupGrenadeAudible` 0.5; `Player.PickupPistol` 0.4 | | `25:1.0 317:0.29`, 1100 | everyone | *Read*, PLR 1854; SS 19636-19638 |
| Weapon pickup (you hear) | `Player.PickupWeapon` 0.7; `PickupSMG/Rifle/Sniper/Shotgun/Heavy` 0.3 | | | only the picker | *Read*, PLR 163 |
| Weapon hitting the floor (drop) | `weapon.Rifle.Impact` 1.5, `.Pistol.` 1.0, `.SMG.` 1.0, `.Heavy.` 1.5, `.Sniper.` 2.0, `.Shotgun.` 1.0, `.C4.` 1.5, `.Knife.` 1.0, grenades 0.3 to 0.5 | | no distance curve (`use_distance_volume_mapping_curve false`); the curve present reads `41:1.0`, 0 at 1200 | everyone | *Read*, PHY 10598 |
| Buying kevlar | `Player.EquipArmor_CT` 0.1 / `_T` 0.3 | | `14:1.0 134:0.39`, 1000 | everyone | *Read*, PLR 402 |

**Silent reload (new, 22 Sep 2026).** Valve's note, in full: "Players can now
reload silently (but slowly) by pressing and holding the reload key."
(*Valve*, 2026-09-22, under GAMEPLAY). How much slower is not in the note or
in any file read (Local check L3). The files show
how: 154 reload events carry `suppression_enable true`,
`suppression_volume_multiplier 0.07`, `suppression_falloff_multiplier 0.2`
(*Read*, WPN; every Clipout, Clipin, AddAmmo, Bolt*, Slide* event). The stack
marks a sound suppressed when the source player's weapon is stealthy
(`game_get_source_player_info.output_is_stealthy`), then multiplies the
volume by 0.07 and divides the distance fed to the curve by 0.2 (*Read*, STK
operators `calc_is_suppressed`, `distance_after_suppression`,
`calc_volume_suppressed`). The weapon has `m_bStealthy`,
`m_bInSilentReloadSection`, `m_bSilentReloadStatCounted` and
`m_flStealthHoldStartTime` (*Read*, SCH `server/CCSWeaponBase.h` 32-35), and
`CCSUsrMsg_WeaponSound` has a `stealth` flag (*Read*, UM 236-245). So a
silent magazine-out is about 7 % as loud and behaves as if five times further
away: silent beyond 220 units instead of 1100 (*Inferred* arithmetic). The
dry-fire clicks carry 0.1 and 0.4 but `suppression_enable false`, so they
are not suppressed (*Read*).

Valve's other handling changes (*Valve*):
- 2026-03-18: "When you reload a magazine-fed weapon, all remaining ammo in
  the magazine is discarded and a new, full magazine is taken from the
  reserves." Not a sound change, but it is the reload whose sounds these are.
- 2026-01-21: "Weapon, knife and utility draw sounds no longer overlap when
  switching quickly between them". *Inferred*: draws share one limiter per
  player, so a new draw stops the last.
- 2025-07-28: "Various improvements to weapon reload and draw sounds in
  conjunction with AnimGraph2 updates." *Inferred*: the reload parts are timed
  from the new first-person animations, so our timed parts
  (`weapon_sounds.gd`) need the AnimGraph2 timings, not CS:GO's.
- 2023-09-13: "Lowered occlusion and distance effects for gunfire, footsteps
  and reloads".
- 2023-06-09: "Adjusted Famas and MP5-SD reload events to match the moment
  when the magazine is fully inserted."

Which of these carry information to an enemy: the shot (to 2500 plus the
distant layer), dry fire and the low-ammo click (1100), a reload (1100,
unless held), a pickup (1100), a zoom-in (600), a fire-mode switch (600), a
knife swing (800) or hit (1000), and a dropped gun hitting the floor. A draw,
an inspect, a silencer change and a pin pull tell an enemy nothing
(*Read*, `localplayeronly`).

## 2. Bullets in the world

### 2.1 Impacts by surface

Every `*.BulletImpact` event shares one shape (*Read*, PHY, e.g.
`Concrete.BulletImpact` 2391): mixgroup `BulletImpacts`, volume 1.0,
`40:1.0 219:0.33`, silent at 600, `instance_limit 1`, block 0.1 s within 20
units, occlusion 0.8. The exceptions (*Read*, PHY):

| Surface event | Differs |
|---|---|
| `Glass.BulletImpact` (1623) | `214:0.39`, silent at 1000 |
| `Flesh.BulletImpact` (104) | 0.7, mixgroup `PlayerDamage`, `248:0.46` |
| `Wood.BulletImpact` (7835) 0.3, `Wood_Solid` 0.7 | quieter |
| `Pottery.BulletImpact` | delay 0.1 s |
| `weapon.BulletImpact` | `instance_limit 3` |
| `Silent.BulletImpact` | volume 0 |
| `defuser.BulletImpact` | no curve |

The surface events present: Default, Concrete, SolidMetal, MetalVehicle,
MetalBarrel, Metal_Barrel, Metal_Box, MetalGrate, ChainLink, Tile, Water,
Underwater, Glass, GlassBottle, Pottery, Computer, WeaponMagazine, Carpet,
Sand, Dirt, Mud, Snow, Grass, Foliage, ceiling_tile, SandBarrel, Cardboard,
Plastic_Barrel, Plastic_Box, Plastic_milkCrate, Rubber, Rubber_Tire, Tape,
Wood, Wood_Box, Wood_Plank, Wood_Solid, Wood_Panel, ArmorFlesh, Flesh,
Watermelon, Fruit, Ball, Shield (*Read*, PHY). Which surface property names
which event is in the surface file (`surfaceproperties.vsurf`), not in this
checkout; `surfaceproperties_impact_effects.txt` gives only particles and
decals (*Read*). *Inferred*: the event name is the surface's own name, as the
footstep events are.

Breaking things: `Glass.Break` 0.7, `318:0.31`, silent at 1200;
`Breakable.Glass` 0.7, `245:0.42`, silent at 600; `Breakable.Metal` 1.0 to 1200;
the other `Breakable.*` and `*.Break` 0.7 to 0.8, silent at 600
(*Read*, PHY 1725, 5769). A vent being hit or walked on is `MetalVent.ImpactHard`
(0.4, `409:0.53`, silent at 2000) (*Read*, PHY 1118). Glass's longer reach
is Valve's "Increased audible distance of breaking glass window sounds"
(*Valve*, 2023-11-30).

**Distance to the listener.** Impacts use the ordinary distance curve from
the impact point to the listener; nothing in them depends on who fired
(*Read*). *Inferred*: an enemy hears your misses land within 600 units of
where they land, not where you stand.

### 2.2 Whizz (near miss) and ricochets

- `BulletBy.Supersonic.Crack`: volume 1.0, mixgroup `PlayerDamage`, flat 1.0
  from 0 to 1000 units, pitch 1.5, with child `BulletBy.Supersonic.TailM`
  (1.0). `BulletBy.Subsonic`: 0.25, mixgroup `Weapons`, `instance_limit 3`,
  block 0.3 s. `BulletBy.Supersonic.Tail` and `BulletBy.Subsonic.Tail` have
  volume 0 (*Read*, WPN 33452, 34081).
- They are client-side: the names are only in client.dll, with a
  `CBulletWhizTimer` game system and "Can't set position/velocity on whiz
  sound" (*Read*, CS 7639, 13260-13263, 16293). `cl_tracer_whiz_distance 72`
  and `cl_tracer_whiz_infront_distance 32` (*Read*, CV 2242-2245).
  *SDK* (2013, not confirmed for CS2): the whiz plays when a tracer passes
  within 72 units of the listener, at most every 0.1 s (combat.md R4).
- The curve is flat, so the whiz does not fade with distance to the shooter;
  it depends only on the round passing close (*Inferred*). The velocity and
  position setter suggests it is placed on the tracer and moved with it
  (*Inferred*). Which guns count as subsonic is not in any file read.
- `FX_RicochetSound.Ricochet`: 1.5, mixgroup `BulletImpacts`, `41:1.0`, silent
  at 236, `instance_limit 1`, six files `bullet_ric_01..06` (*Read*, WPN 3).
  Client-side (*Read*, CS 18564, beside `FX_TracerSound`). When it plays is
  not in the files; *Inferred*: at an impact on a hard surface near the
  listener, since it is gone by 236 units.
- Valve's release notes from 2023-03-22 to 2026-09-22 say nothing about the
  whiz, the crack or ricochets (*Valve*, by absence), so these events are
  unchanged since CS2's release as far as the notes show.

## 3. Being hit and killing

The server names the victim and onlooker versions, the client the attacker
versions (*Read*, SS 19597-19631; CS 23423-23433). The client also receives
`CMsgPlayerBulletHit` {attacker_slot, victim_slot, victim_pos, hit_group,
damage, penetration_count, is_kill, through_smoke} (*Read*, CGE; CS
`PlayerBulletHit_GameEvent_t` 23448). *Inferred*: the attacker's client plays
its feedback from that message when damage prediction is off. With it on, the
client plays the feedback before the server confirms: "Damage prediction
allows clients to immediately play the audio/visual effects of inflicting
damage without waiting for confirmation from the server ... but comes with the
risk of occasionally being wrong", and "Damage prediction is not active when
you have high ping" (*Valve*, 2024-11-13). The knife is excluded (*Valve*,
2023-11-02, section 1.2). Each event's `metadata` says who it is for, in Valve's own
words: "attacker only", "victim only", "onlookers only", "plays on victim and
onlookers" (*Read*, PLR).

| Case | Attacker hears | Victim hears | Onlookers hear |
|---|---|---|---|
| Body, no armour, not fatal | `Player.DamageBody.AttackerFeedback`: 1.0, pitch 1.3, `mud_impact_bullet1-4`, `21:1.0 1065:0.21`, mixgroup `PlayerAttackerFeedback`, `instance_limit 3` (PLR 2677) | `Player.DamageBody.Victim`: 1.5, `player_damagebody_*`, flat to 600, mixgroup `PlayerVictim`, delay 0.05 s, plus `VictimFlesh` 1.0 (PLR 3552) | `Player.DamageBody.Onlooker`: 1.0, `35:1.0`, silent at 1100 (PLR 3417) |
| Body through kevlar | `...DamageBodyArmor.AttackerFeedback`: 1.2, `kevlar_01-08`, plus flesh 0.3 delayed 0.1 s (PLR 2924) | `...DamageBodyArmor.Victim`: 1.5, kevlar, flat to 600 | `...DamageBodyArmor.Onlooker`: 0.7 plus flesh 0.3, silent at 1100 |
| Head, no helmet | `Player.DamageHeadShot.AttackerFeedback`: 0.5, `headshot_noarmor_01-05`, `104:1.0 1100:0.77` | `Player.DamageHeadShot.Victim`: 0.49, flat to 1070 (PLR 4351) | `...DamageHeadShot.Onlooker`: 0.5, `22:1.0 298:0.43`, silent at 1070 |
| Head, helmet (the "dink") | `Player.DamageHeadShotArmor.AttackerFeedback`: 0.5, `headshot_armor_e1`, `104:1.0 1100:0.77` (PLR 3282) | `...Victim`: 0.75, flat to 1300 | `...Onlooker`: 0.5, silent at 1070 |
| Kill, body | `Player.DeathBody.AttackerFeedback`: 1.0, mud thud, `21:1.0 1065:0.58` (PLR 2748) | `Player.DeathBody.Victim`: 2.0, pitch 0.8, flat to 1070, plus `DeathBody.Flesh` 2.0 | `...DeathBody.Onlooker`: 2.0, `51:1.0 400:0.45`, silent at 1070 |
| Kill, body, kevlar | `...DeathBodyArmor.AttackerFeedback`: 1.0 kevlar plus flesh 0.5 | `...Victim` 2.0 | `...Onlooker` 2.0 |
| Kill, head, no helmet | `Player.DeathHeadShot.AttackerFeedback`: 0.4, `104:1.0 738:0.81` (PLR 3137) | `...Victim` 0.55 | `...Onlooker` 0.5, silent at 1070 |
| Kill, head, helmet | `...DeathHeadShotArmor.AttackerFeedback`: its own file `headshot_armor_01` at volume **0**; the audible parts are the children `.Flesh` (0.3) and `.Dink` (0.6, pitch 1.1, `headshot_armor_e1`) (PLR 3211) | `...Victim` 0.7 plus `.Victim.Dink` 0.7 and `.Victim.Flesh` 0.2 | `...Onlooker` 0.5 plus `DeathHeadShot.Dink` 0.7 and `.Flesh` 0.2, silent at 1200 |
| Knife | silent feedback (`null.vsnd`); the knife's own hit sounds instead (1.2) | as body | as body |

Other damage sounds (*Read*, PLR): `Player.DamageKevlar` 0.5, silent at 594,
metadata "friendly fire hit"; `Player.BurnDamage` / `BurnDamageKevlar` 1.0,
silent at 1100, block 0.6 s (fire); `Player.DamageFall` 1.0, silent at 800;
`Player.DamageGrenadeBounce` 1.0, silent at 1100 (a grenade hitting a player);
`Player.Death` / `DeathFem` 0.5, `113:0.59`, silent at 1400 (death cries,
`death1-6`), named in server.dll (SS 19616, 19623).

What this means.
- The attacker's feedback curves never reach 0: 0.21 at 1065 for a body hit,
  0.77 for a headshot at 1100 (*Read*). *Inferred*: the attacker hears his hits
  at any range (the curve's value is held past its last point, or the audio
  engine page says otherwise). Valve fixed "some cases where shooting visible
  enemies over the top of smoke would not play an attacker feedback sound"
  (*Valve*, 2025-05-07). *Community*, where Valve's notes are silent: since
  November 2023 attackers hear headshot feedback through wallbangs and smokes,
  and body feedback "within the same distance as it does for onlookers"
  through them
  ([HLTV 37468](https://www.hltv.org/news/37468/cs2-update-addresses-sub-tick-feedback-syncs-bullet-spread),
  search summary, November 2023). No line in Valve's November 2023 notes says
  this; the nearest is the 2023-11-09 dink change below.
- The victim's sounds are flat and unoccluded, `position_offset [0,0,0]`:
  a hit is always heard in full by the one hit (*Read*).
- Everyone else near the victim hears the hit to about 1070 to 1100 units
  (*Read*). *Community*: this is the HE "sound cue" that reveals a damaged CT;
  in CS:GO the sound played only on a direct grenade hit
  ([dotesports](https://dotesports.com/counter-strike/news/cs2-pro-explains-why-new-he-mechanic-might-hurt-ct-side),
  [n4g](https://n4g.com/articles/cs2-he-grenade-sound-mechanic-analysis); date not
  shown in the summaries; Valve's notes do not mention it). *Inferred*: the
  cue is the onlooker damage event. Valve did fix "a bug where grenades were
  generating headshot sounds" (*Valve*, 2024-10-24), so a grenade hit plays
  only the body versions.
- Valve's note of 2025-05-15, under AUDIO: "Reduced delay for body shot impact
  sounds from the attacker perspective." and "Body shot impact sounds from the
  attacker perspective will momentarily reduce the volume of weapon fire and
  ambience to help ensure feedback remains audible." (*Valve*). In the current
  file the attacker's body feedback has `delay 0.0`, and the victim's 0.05
  (*Read*). The ducking is the mixer's (`audio-engine.md` section 2). The size of the
  old delay, 150 ms, is only in a community report
  ([dust2.us 61434](https://www.dust2.us/news/61434/cs2-may-5-15-update-finally-fixes-body-shot-sound-delays),
  May 2025; *Community*, Valve gives no figure).
- There is no separate "kill ding" in the gameplay files: a kill is the death
  version of the hit feedback. The headshot "tink" is `headshot_armor_e1`,
  played for helmeted heads only (*Read*). An unhelmeted headshot is the fleshy
  `headshot_noarmor_*` (*Read*).

Valve's dated hit-sound changes behind the table (*Valve*, newest first):

| Date | Valve's line | What it explains |
|---|---|---|
| 2026-04-01 | "Mix tweaks while taking damage" | The `PlayerVictim` mixgroup's ducking (`audio-engine.md` section 2) |
| 2025-05-15 | the two body-shot lines quoted above | Attacker body feedback `delay 0.0`; the duck on `PlayerAttackerFeedback` |
| 2025-05-07 | "Fixed some cases where shooting visible enemies over the top of smoke would not play an attacker feedback sound." | `through_smoke` in `CMsgPlayerBulletHit` |
| 2024-11-13 | Damage prediction added (quoted above) | The attacker's client may play feedback before the server confirms |
| 2024-11-07 | "Various adjustments to bullet hit feedback." | No detail given |
| 2024-10-24 | "Fixed a bug where grenades were generating headshot sounds." | Grenade damage plays body versions only |
| 2024-10-23 | "Fixed a bug where Zeus headshots wouldn't emit the death yelp." | `Player.DeathTaser` plays on every Zeus kill |
| 2023-11-09 | "Addressed issue where sometimes headshot dink sounds playing as feedback for the attacker could be mistaken for incoming damage" | The attacker dink is its own event (`headshot_armor_e1`, 0.5), apart from the victim's (0.75, flat) |
| 2023-11-09 | "Lowered volume of sound for headshot damage with no armor from a victims perspective to bring it inline with volume of other headshot sounds" | `Player.DamageHeadShot.Victim` at 0.49 |
| 2023-11-09 | "Fixed issue where at very close proximity, a victims death groan could be mistaken as coming from the attacker" | The death cry's placement (Local check L8) |
| 2023-09-06 | "Fixed a case where hit feedback sounds wouldn't play for spectators" | Spectators hear the attacker's feedback of the player they watch (*Inferred*) |

## 4. Grenades

### 4.1 Pin, throw, flight, bounce

| Sound | Event | Vol | Curve (silent at) | Heard by | Source |
|---|---|---|---|---|---|
| Pin pull | `HEGrenade.PullPin` 0.2, `Flashbang.PullPin` 0.6, `SmokeGrenade/IncGrenade.PullPin` 0.6, `Decoy.PullPin` 0.7 (+ `Grenade.PullPin.Gear` 0.05) | | `82:1.0 354:0.30`, 1106 | only the thrower (`localplayeronly`) | *Read*, WPN 38834 |
| Throw | `Flashbang.Throw` 1.4, `HEGrenade.Throw` 1.0 (delay 0.1), `SmokeGrenade.Throw` 1.0, `Decoy.Throw` 0.7, `IncGrenade.Throw` 0.5, `Molotov.Throw` 0.6 (+ `Grenade.Throw.Gear` 0.2) | | `47:1.0 399:0.30`, 1100 | everyone | *Read*, WPN 22499 |
| Jump-throw grunt | `BaseGrenade.JumpThrowM` / `F` 0.9; `BaseGrenade.JumpThrow` 1.0 | | silent at 800 / 1100 | everyone | *Read*, PLR 3004; SS 10417-10418 |
| Burning bottle in flight | `Molotov.Throw.Loop` 0.7 (+ `Molotov.ThrowFire` 0.9), `IncGrenade.Throw.Loop` 0.5 | | `112:1.0 222:0.58 502:0.25 733:0.10`, 1275 | everyone | *Read*, WPN 39358; SS 17381, 18294 |
| Bounce | `HEGrenade.Bounce` 0.8, `Flashbang.Bounce` 0.8, `SmokeGrenade.Bounce` 0.6 (+ `Bounce_Can` 1.0), `Molotov.Bounce` 1.0 (glass bottle), `IncGrenade.Bounce` 0.5 (+ `_M` 1.0) | | `28:1.0 306:0.28 791:0.05`, 1700; block 0.1 s | everyone | *Read*, WPN 22635 |

Bounces are one event per grenade, not per surface (*Read*: no
surface-specific grenade bounce exists; the projectile stores one
`m_iszBounceSound` and `m_flLastBounceSoundTime`, SCH `CBaseGrenade.h` 13,
`CBaseCSGrenadeProjectile.h` 14). The decoy has no bounce event of its own
(*Read*). Bots listen to `grenade_bounce` (section 7).

Valve's dated changes behind these rows (*Valve*):
- Bounce range: "Reduced the maximum audible distance of grenade bounce
  sounds" (2023-11-09), then "Further refined falloff distance curves and
  volume of grenade bounces" (2023-11-30). The 1700-unit curve above is the
  result.
- Throw and pin: "Each grenade now has unique higher-fidelity sounds for draw,
  inspect, pin-pull, and throw." (2025-09-16), hence the per-grenade `Throw`
  and `PullPin` volumes. "Fixed a case where grenade throw sounds would play
  twice" (2023-08-31).
- Jump-throw: "Added dedicated player-only sound when a grenade is correctly
  jump-thrown." (2023-03-30), then "The jump-throw confirmation grunt sound
  can now be heard by other players nearby" (2024-08-19). So the grunt is
  heard by everyone within 800 to 1100 units today, not only the thrower.
- Molotov and incendiary: "Incendiary and smoke grenades now play the correct
  sounds." and "Adjusted firstperson molotov audio and particle event timing."
  (2025-08-01).
- Landing: "Added separate sounds for grenades landing in vs out of the
  playable area" (2023-09-29); "Adjusted grenade/water interaction sounds"
  (2023-08-02).

### 4.2 Detonations

| Grenade | Near event | Near | Distant event | Distant | Source |
|---|---|---|---|---|---|
| HE | `BaseGrenade.Explode` 1.0, `instance_limit 1` | `231:1.0 779:0.57`, silent at 2700 | `BaseGrenade.ExplodeDistant` 1.5 | `504:0 944:1.0 2800:0.34` | *Read*, WPN 23133, 23206 |
| Flashbang | `Flashbang.Explode` 0.4 | `84:1.0`, silent at 2740 | `Flashbang.ExplodeDistant` 1.0 | `504:0.71 944:1.0`, silent at 2800 | *Read*, WPN 22232, 22299 |
| Smoke | `BaseSmokeEffect.Sound` 1.0, delay 0.2 s | `194:1.0 678:0.25`, silent at 2090 | `BaseSmokeEffect.SoundDistant` 1.0, delay 0.3 s | `616:0 944:0.46 2800:0.10` | *Read*, WPN 23281, 23355 |
| Smoke clearing | `SmokeGrenade.Clear` 0.2 | `194:1.0 825:0.39`, silent at 2700 | | | *Read*, WPN 33738; CS 25755 |
| Molotov | `Molotov.Start` 1.0 (+ `Molotov.Smash` 1.0, to 1594) | `154:1.0 977:0.49`, silent at 3000 | `Molotov.StartDistant` 1.0 | `264:0 920:0.81 2800:0.05` | *Read*, WPN 34218 |
| Incendiary | `IncGrenade.Start` 1.0 (+ `IncGrenade.Pop` 1.0) | `154:1.0 742:0.52`, silent at 2000 | `IncGrenade.Distant` 1.0 | `616:0 944:1.0 2800:0.24` | *Read*, WPN 34357 |
| Fire that fizzles (air burst or in smoke) | `Molotov.StartFailed`, `IncGrenade.StartFailed` 1.0 | silent at 3000 | the same distant layers | | *Read* |
| Fire burning | `Inferno.Loop` 0.3 (block 3 s / 60 units), `Molotov.Loop` 0.3, `Inferno.Fire.Ignite` 0.3 (`instance_limit 3`) | silent at 1200 (ignite 1000) | | | *Read*, WPN 25249; SS 17400-17402 |
| Fire ending | `Inferno.FadeOut` 0.7, silent at 1200; put out by smoke: `Molotov.Extinguish` 1.0, silent at 2500 | | | | *Read*, WPN 24767 |
| Decoy | no decoy detonation or firing event of its own | | | | *Read*; the decoy plays the gun it imitates (below) |

All distant layers are in mixgroup `ExplosionsDistant` and the near ones in
`Explosions` (*Read*). *Inferred*: like the gunfire distant layers, the HE's
(0.34 x 1.5 at 2800), the smoke's and the fires' last points are above 0, so
they either carry across the map or stop just past 2800 (`audio-engine.md`
1.2 infers the first; L1).

Valve's detonation changes (*Valve*): "Adjustments to smoke grenade sound
timing at a distance." (2023-03-30) (*Inferred*: the 0.3 s delay on the smoke's distant layer
against 0.2 s near); "Fixed missing low frequencies at certain
distances away from sound sources such as grenades and weapon fire."
(2023-06-30); "Tuned the vertical audio occlusion of grenade sounds in Nuke
and Vertigo" (2023-09-16); "Fixed a case where grenade sounds were missing
when exploding in-air" (2023-09-29) (*Inferred*: why the fizzle events
`*.StartFailed` keep the distant layers); "Improved molotov extinguish effects
to sound better when multiple are playing at once" (2023-11-09).

**The decoy.** It "emulates the sound of the most powerful weapon you are
carrying" (round-bomb-grenades.md 2.8), keeps `m_decoyWeaponDefIndex`, and
fires `decoy_firing` {userid, entityid, x, y, z} for each shot (*Read*, GE 541).
*Inferred*: each client plays that weapon's `WEAPON_SOUND_SINGLE` event at the
decoy, so its fake gunfire has the same near and distant layers and the same
9000 broadcast as the real gun. There is no decoy-specific sound to tell it
apart, other than its bursts' rhythm.

### 4.3 Flashbang ringing and HE deafening

- **The ring.** `Flashbang.Ring.Short`, `.Medium`, `.Long`: each 0.1,
  mixgroup `Explosions`, file `weapons/flashbang/explosion_ring.vsnd`, flat
  1.0 to 2800, occlusion 1.0 (*Read*, WPN 32784). Named in server.dll
  (*Read*, SS 16279-16281). *Inferred*: the server picks one by how blinded
  the player is (three strengths; round-bomb-grenades.md 2.5) and plays it to
  the flashed player only; nothing in the files says who hears it. The ring's
  low 0.1 is Valve's "Lowered volume of flashbang ringing and volume ducking
  effect." (*Valve*, 2023-03-24), and "Fixed a bug where flashbang or grenade
  sound effect would remain if player died while having that sound effect
  active." (*Valve*, 2023-03-30) says the effect is cleared on death.
- **The muffle.** DSP presets `core.flashbang.muffle.long` (134),
  `.medium` (135), `.short` (136): a diffusor plus a 3000 Hz sine LFO at gain
  0.05. Their header numbers differ only in two timings, 1.4/5.5, 0.4/1.4 and
  0.2/0.7 (*Read*, DSP 953-975). *Inferred*: the second is the effect's length
  in seconds (5.5 s, 1.4 s, 0.7 s) and the first its fade. The client keeps
  `m_bFlashDspHasBeenCleared` (*Read*, SCH `client/C_CSPlayerPawnBase.h` 15)
  and the string `dsp_player` (*Read*, CS 32257). *Inferred*: the flash sets
  the player's DSP to one of 134 to 136 and clears it when the blind ends.
  Which preset goes with which blind length is Local check L4.
- **HE deafening.** `core.grenade.shock.ring1/2/3` (137 to 139): "HE grenade
  shock effect, ear ringing combined with low pass filter", low-pass at 4000,
  2000 and 1000 Hz, durations 1, 1.5 and 3 (*Read*, DSP 977-1025, Valve's own
  comments). Older `core.explosion.ring1-3` (32 to 34, 1000 Hz low-pass) and
  `core.shock.muffle1-3` (35 to 37) also exist (*Read*, DSP 424-475). Which
  of these CS2 uses, and at what distance or damage, is in no file read.
  Valve's notes never mention HE deafening. *Community*: players say an HE hit
  "essentially deafens" them in CS2, more
  than in CS:GO, where they could still hear steps and shots
  ([Steam discussion 3881597531962761753](https://steamcommunity.com/app/730/discussions/0/3881597531962761753/),
  undated).
- There are also `core.player.death.muffle1/2` (140, 141) "Near-death muffled
  sound" (*Read*, DSP 1027-1045); whether CS2 uses them is unknown.

## 5. The bomb

| Moment | Event | Vol | Curve (silent at) | Source |
|---|---|---|---|---|
| Taking it out | `c4.draw`, `c4.draw.grab` (holder only); `c4.draw.beep` 0.1, silent at 500 (everyone) | | | *Read*, WPN |
| Starting the plant | `c4.initiate` 0.8 | `103:1.0`, silent at 1101 | *Read*, WPN 23762 |
| Typing the code | `c4.keypressquiet` 0.3 | holder only (`localplayeronly`) | *Read*, WPN 23818 |
| Quiet plant cue | `c4.plantquiet` 0.4 | `85:1.0`, silent at 299 | *Read* |
| Plant complete | `c4.plant` 0.6 (`WEAPON_SOUND_SINGLE` of `weapon_c4`) | `105:1.0 1089:0.40`, silent at **4100** | *Read*, WPN 24184; WV |
| Beep, site A | `C4.PlantSound` 0.9, `c4_beep2`, `instance_limit 1` | silent at 1300 | *Read*, WPN 24244 |
| Beep, site B | `C4.PlantSoundB` 0.5, pitch 0.9, `c4_beep3` | silent at 1300 | *Read*, WPN 24308 |
| Beeps in the last 10 s | `C4.PlantSound_10sec` 0.9 (delay 0.05), `C4.PlantSoundB_10sec` 0.6 (delay 0.07) | silent at 1300 | *Read*, WPN 34785 |
| The light's blink | `C4.LightFlash` 0.3, `c4_beep2`, silent at 500 | | *Read* |
| Ten-second and final warnings | `C4.10Seconds` 1.0 (`ui/arm_bomb`), silent at 3000; `C4.ExplodeWarning` 0.8 (`WEAPON_SOUND_SPECIAL3`), `3000:0.71`; `C4.ExplodeTriggerTrip` 1.0 (`items/nvg_on`), `15:1.0 3000:0.61` | | *Read*, WPN 24372 |
| Defuse start / finish | `c4.disarmstart` / `c4.disarmfinish` 0.7 (`SPECIAL1`/`SPECIAL2`) | `200:1.0 657:0.46`, silent at **2000**; block 0.5 s | *Read*, WPN 23941 |
| Defuse with a kit | no separate event | | *Read* |
| Explosion | `c4.explode` 0.5, flat 1.0 to 1100 (block 0.5 s) | | *Read*, WPN 24061 |
| Shockwave (8 July 2026) | `c4.shockwave.boom` 1.0, `556:0 1434:1.0` (a far layer), child `c4.explode.close` 1.0, `233:1.0`, silent at 1500; `c4.shockwave.hit` 1.0, `579:0 1100:1.0`, child `.debris` 0.1 | | *Read*, WPN 46793, 47043; SS names them |
| Picking it up | `Player.PickupC4` 1.0 plus `.beep` 0.03, silent at 1100 | | *Read*, PLR 2363 |
| Dropping it (hits floor) | `weapon.C4.Impact` 1.5 (no curve) plus `weapon.C4Beep.Impact` 0.15, block 3 s within 300 | | *Read*, PHY |
| "Bomb has been planted" | `Event.BombPlanted` 0.7, mixgroup `VO`, `cs2_classic/bombpl` (and `Announcer.BombPlanted.CS2_Classic` 0.6 in `UI`) | not positional (*Inferred* from the mixgroup) | *Read*, ANN 3, 2871 |
| Music | `Music.BombPlanted`, `Music.BombTenSecCount` (per music kit); `snd_tensecondwarning_volume 0.04`, `snd_mapobjective_volume 0.04` | | *Read*, CS 22038-22039; CV 9339, 8910 |

Notes.
- *Community*, where Valve's notes are silent: the B-site beep is pitched
  lower than A's so a CT can tell the site by ear
  ([Fandom C4](https://counterstrike.fandom.com/wiki/C4_Explosive), undated
  search summary). The files agree: `PlantSoundB` has pitch 0.9 and its own
  file (*Read*).
- Valve's dated bomb changes (*Valve*):

  | Date | Valve's line | What it explains |
  |---|---|---|
  | 2026-07-20 | "The bomb damage health preview is now revealed when the bomb becomes audible." | The game has a notion of the bomb being audible to a player; *Inferred*: within the beep's 1300 units |
  | 2026-07-08 | "Re-designed effective range and extent of C4 explosion damage on all official defusal-mode maps." and "Explosion shockwave damage now rapidly expands from the center of the explosion instead of being applied instantly." | The `c4.shockwave.boom` / `.hit` events and their far-layer curves |
  | 2026-04-28 | "Fixed issue where C4 equip sound was not getting interrupted by other equip sounds." | `c4.draw` shares the draw limiter |
  | 2026-04-01 | "New c4 equip sound." | `c4.draw`, `c4.draw.grab`, `c4.draw.beep` |
  | 2024-06-26 | "Fixed an empty radio-command string which plays when planted C4 is within several seconds from detonation" | A radio line near detonation (round page) |
  | 2023-11-09 | "Brought back spark sound feedback when bomb defuse is cut short due to player spinning" | *Inferred* match: `DoSpark` 0.5, `physics/weapons/weapon_c4zap_impact_01-03`, `6:1.0`, silent at 1000, heard by everyone (*Read*, WPN 35152), sent as `CEntityMessageDoSpark` (*Read*, SS 11567) |
  | 2023-10-17 | "New sound for final 10 seconds of bomb beeping" | `C4.PlantSound_10sec` and `C4.PlantSoundB_10sec` |
- The beeps are client-side: `C4.PlantSound*` names are in client.dll only, with
  the debug line "C4 Sounds: Playing sound %s at %f..." and
  `snd_report_c4_sounds` (*Read*, CS 13310-13313; CV 9066). The cadence is in
  round-bomb-grenades.md 1.3. `bomb_beep` {entindex} is still a game event,
  and bots listen to it (section 7).
- Planting is loud to 4100 and a defuse start to 2000; the beeps themselves
  only to 1300 (*Read*). So a CT far from the bomb learns of the plant from the
  plant sound and the announcer, and of a defuse from up to 2000 units away.
- The planted bomb carries `m_nSourceSoundscapeHash` (*Read*, SCH
  `CPlantedC4.h` 6): its sounds take the room acoustics of where it lies.

## 6. Movement and the world, besides footsteps

Footsteps, landings, ladders, wading and the suit's gear rustle are in
`reference/research/footsteps.md` (sections 2 to 5). What that page does not
list:

| Sound | Event | Vol | Curve (silent at) | Source |
|---|---|---|---|---|
| Jump (launch) | `Default.WalkJump` 0.1, pitch 1.1, mixgroup `Footsteps`, `instance_limit 3`, block 0.4 s, `position_offset [0,0,30]`, **`broadcast_distance_override 98`** | `40:1.0 155:0.26`, silent at 493 | *Read*, PLR 2560; SS 15111 |
| Swimming | `Player.Swim` 0.55 | silent at 620 | *Read*, PLR 51 |
| Entering / leaving water | `Water.PlayerEnter` / `Exit` 0.2 (block 1 s / 200), `BaseEntity.EnterWater` 0.2, `Physics.WaterSplash` 0.9 | silent at 600 | *Read*, PHY |
| Doors | `Door.wood_start_open` 1.0, `Door.wood_full_open` 1.0, `..._close`; `Door.de_nuke_*`, `Door.de_vertigo_*`; `DoorHandles.Locked1` | silent at 1400, block 0.3 s / 100 | *Read*, WLD 3034; the door code's defaults `DoorSound.DefaultMove/Arrive/Locked` and `DoorMetal.*` are named in SS 15252-15263 |
| Breaking glass, props | see section 2.1 | 600 to 1200 | *Read*, PHY |
| Weapon selection foley | `Player.WeaponSelectionFoley`, `Player.WeaponSelected_CT/T`, `WeaponSelectionOpen/Close` | holder only | *Read*, PLR |
| Knife equip | `Weapon_Knife.Deploy`, `Weapon_Knife.Draw.*` | holder only | *Read*, WPN |
| Chickens | `Chicken.Idle/Panic/Fly/Death`, silent at 422 | | *Read*, WLD |

*Inferred* on the jump: its own curve reaches 493 units, yet it is given a
broadcast distance of 98, far below the 9000 of gunfire. If the broadcast
distance is the radius the server hands out for the sound (to other clients,
or as the `player_sound` radius on the radar and for bots, section 7), a jump
is effectively private beyond about 100 units. Local check L2.

Valve's notes in this area (*Valve*): "Changed jump land sounds to have the
same maximum audible distance as footstep sounds" and "Changed volume falloff
curve of jump landing sounds to better convey distance" (2023-11-09); "Mix
adjustments to help accentuate jump landing sounds during combat"
(2026-04-01); "Fixed a case where sounds would play incorrectly as players
move through water." (2025-09-03). No note mentions the jump's launch sound,
so the 98-unit broadcast is unexplained by Valve.

## 7. Who starts each sound and who is sent it

- **Two kinds of sender.** The server starts sound events through
  `CMsgSosStartSoundEvent` {soundevent_guid, soundevent_hash,
  source_entity_index, seed, packed_params, start_time} (*Read*, PB
  `gameevents.proto` 98-105) with a recipient filter (*Read*, SS
  `DoSetSoundEventParams@CSoundOpGameSystem ... IRecipientFilter`). The client
  starts its own for what it predicts or derives.
- **Gunfire is the fire-bullets message, not a sound message.**
  `CMsgTEFireBullets` carries `sound_type` and `sound_dsp_effect` beside the
  origin, angles, weapon, seed and tick (*Read*, CGE 20-45). *Inferred*: each
  client plays the shooter's shot from it, and the shooter plays his own shot
  when he predicts the shot. `broadcast_distance_override 9000` is read by
  the server (`public.broadcast_distance_override`, *Read*, SS 31492).
  *Inferred*: the server sends a shot to clients within 9000 units, which on
  any competitive map is everyone.
- **Weapon handling goes by `CCSUsrMsg_WeaponSound`** {entidx, origin_x/y/z,
  sound, game_timestamp, source_soundscapeid, stealth} (*Read*, UM 236-245).
  *Inferred*: the server sends the reload's and other handling sounds by name
  with the silent-reload flag, so the receiving client applies the 0.07 volume
  and x5 distance. `CCSUsrMsg_WeaponMagDrop` {entidx, secondary_data,
  server_event} is beside it (the dropped magazine) (*Read*, UM 247-251).
- **Footsteps** are the server's, sent within 1250 units
  (`mp_footsteps_serverside true`, `sv_max_distance_transmit_footsteps 1250`;
  footsteps.md section 1 and 4).
- **Server-named sounds** (*Read*, SS): the victim and onlooker damage and death
  sounds, `Player.Death/DeathFem`, `Player.DamageFall`, `Player.BurnDamage`,
  `Player.PickupC4`, `Player.PickupWeaponAudible`, `Player.PickupGrenadeAudible`,
  `Player.EquipArmor_*`, `Player.Swim`, `Player.Wade`, `Default.WalkJump`,
  `Default.ClipEmpty_*`, `Weapon.AutoSemiAutoSwitch`, `BaseGrenade.Explode`,
  `BaseGrenade.JumpThrow*`, every grenade's `Bounce`, `Flashbang.Explode`,
  `Flashbang.Ring.*`, `Molotov.*`/`IncGrenade.*` start, fizzle, flight loop,
  extinguish, `Inferno.*`, `Breakable.*`, `Glass.*`, the door sounds,
  `c4.shockwave.*`, the knife's heavy flesh hits.
- **Client-named sounds** (*Read*, CS): the attacker's hit feedback, the whiz
  (`BulletBy.*`), `FX_RicochetSound.Ricochet`, `FX_TracerSound`, the bomb's
  beeps and warnings (`C4.PlantSound*`, `C4.ExplodeWarning`,
  `C4.ExplodeTriggerTrip`), `SmokeGrenade.Clear`, all four knife hit flesh
  events, `Weapon_Taser.Single`, `Weapon_Taser.ChargeNotReady`,
  `Player.PickupWeaponSilent`, `Player.WeaponSelectionFoley`,
  `Player.DenyWeaponSelection`, `Player.FreezeCam`, `Player.Surf.*`.
- **Distance culling.** Besides the 1250 for steps and the 9000 for shots,
  the server reads each event's `public.distance_volume_mapping_curve`
  (*Read*, SS 31493). *Inferred*: it culls by the curve's end, so a client far
  outside a sound's range is not told of it (the anti-wallhack reason
  footsteps.md gives). On the client, a playing voice whose curve value is
  under `voice_culling_threshold 0.001` is culled (*Read*, STK).
- **Spectators** hear per `sv_spec_hear 3`: "0 only spectators, 1 all
  players, 2 spectated team, 3 self only, 4 nobody" (*Read*, CV 10701; this is
  voice chat, *Inferred*).
- **`player_sound`** {userid, radius, duration, step} is a server game event
  the client listens to (*Read*, GE 954; SS 31183, CS 38157). *Inferred*: it
  drives the radar's own-noise ring (`RadarPlayerSoundSnippet`, CS 24002) with
  a radius per sound; whether the radius is the curve's end or the broadcast
  distance is Local check L2. Valve "Fixed an issue where player sounds would
  not visualize correctly on the minimap." (*Valve*, 2025-09-03).
- **What Valve's notes say about prediction and sending** (*Valve*, newest
  first):

  | Date | Valve's line | What it tells us |
  |---|---|---|
  | 2025-10-29 | "Added scope in/out sound prediction to play immediately for local player." | Scope sounds: the holder predicts, others are sent them |
  | 2025-10-22 | "Fixed several server-only sound events to not start multiple times" | Some events are started by the server only (the server-named list above) |
  | 2024-11-13 | Damage prediction (section 3) | Hit feedback: predicted by the attacker's client when enabled, else from the server's hit message |
  | 2024-10-02 | "Fixed an issue where step sounds would play for the local player but fail to broadcast to other players and vice-versa" | Steps: predicted for oneself, sent by the server to others |
  | 2023-11-09 | "The visual and audio feedback from sub-tick input ... will now always render on the next frame" | Predicted sounds play on the next frame after the input, not the next tick |
  | 2023-11-02 | "Knife attacks no longer predict damage effects or sounds on the client" | Knife hits: server only |
  | 2023-06-06 | "Player's own footstep sounds are now predicted on the client for a latency-independent experience." | Steps, as above |

## 8. What bots hear

- **The competitive bot** (`CCSBot`) is told of noises through game events. Its
  manager's listeners (*Read*, SS 5728-8510, `*Event@CCSBotManager`):
  `weapon_fire`, `weapon_fire_on_empty`, `weapon_reload`, `weapon_zoom`,
  `bullet_impact`, `player_footstep`, `player_falldamage`, `door_moving`,
  `break_breakable`, `break_prop`, `grenade_bounce`, `hegrenade_detonate`,
  `flashbang_detonate`, `smokegrenade_detonate`, `molotov_detonate`,
  `decoy_firing`, `decoy_detonate`, `bomb_beep`, `bomb_planted`,
  `bomb_pickup`, `bomb_begindefuse`, `bomb_abortdefuse`, `bomb_defused`,
  `bomb_exploded`, `player_radio`, `player_death`, and round and hostage
  events. So a bot hears shots, dry fire, reloads, zooms, impacts, steps, fall
  damage, doors, breaking things, bounces, detonations, decoys and the bomb's
  beeps.
- **Not listened to** (*Read* by absence): `player_jump`, `silencer_on/off`,
  `item_pickup`, `inspect_weapon`, `inferno_startburn`, `grenade_thrown`.
  GE's own comment: `weapon_zoom_rifle` exists "because we don't use this event
  to notify bots", i.e. `weapon_zoom` does notify them (*Read*, GE 289-292).
- `weapon_fire` carries `silenced` (*Read*, GE 251-256). *Inferred*: the bot
  scales hearing down for a silenced shot. Whether a silent reload still sends
  `weapon_reload` is unknown (Local check L3).
- A bot keeps one noise: position, travel distance, time, source, and a
  "bent" position along the nav mesh (*Read*, SCH `server/CCSBot.h` 54-60);
  "Noise occurred off the nav mesh - ignoring!" and "Heard noise (%s from %s,
  pri %s, time %3.1f)" (*Read*, SS 70, 17103). Its hearing ranges are in no
  file read. round-hud-bots.md B4 and footsteps.md section 6 cover this.
- **The behaviour-tree bots** (deathmatch, arms race, practice and the new
  Rush mode of 22 Sep 2026) sense `NOISE` entities within a 3000-unit sphere,
  keeping any within 800 and picking at random by distance out to 3000
  (*Read*, BT `bt_memorize_noises.kv3`; `ai/rush/bt_default.kv3` 47-51 uses
  the same module). round-hud-bots.md B7 has the rest.

## 9. Ours against CS2

Ours is `main` at 3975eef (2026-09-23). The `src/` files cited are the same
on the research branch (95b7d4f, e218e23), so the line numbers hold on both.

| # | File:line | Ours | CS2 | Kind |
|---|---|---|---|---|
| 1 | `src/audio/weapon_sounds.gd:12-14, 34-36` | Volumes by ear (-6, -4, -3 dB); "the sound event definitions ... are not fetched" | The definitions are in GameTracking-CS2 as text (this page); `cs2-systems.md` S2 is answerable remotely | Level |
| 2 | `weapon_sounds.gd:59-62` | Inverse distance, 787-unit reference, cut at 11 811 units, one layer | Near layer to 2500 by the curve above, plus a distant layer from 800 (per gun, section 1.1) | Range |
| 3 | `weapon_sounds.gd:25-27` | The M4A1-S plays `m4a1_silencer_01` through the same player, so it carries as far as an AK | Silenced shots silent at 1400, no distant layer; unsilenced M4A1-S uses `m4a1_0N`/`m4a1_us_distant` | Range |
| 4 | `weapon_sounds.gd:51`, `_fire` polyphony 4 | Shots from one shooter overlap, up to 4 | `instance_limit 1` per shooter on the near layer: each shot stops the last (2 on the distant layer) | Behaviour |
| 5 | `weapon_sounds.gd:72-75`, `bot.gd:150` | A bot's draw plays spatially, so the player hears an enemy's weapon switch | Draws are `localplayeronly`: nobody else hears them | Missing rule |
| 6 | `bot.gd:383-384` | A bot's shot only; its reloads, dry fire and pickups are silent | Reloads (1100), dry fire (1100), pickups (1100) are heard by everyone | Missing |
| 7 | `weapon_sounds.gd:33, 109-110` | Kill plays `player/bodyshot_kill_01` | No CS2 event uses that file; a body kill is `Player.DeathBody.AttackerFeedback` (the mud thud, 1.0) or the kevlar version | Wrong file |
| 8 | `weapon_sounds.gd:33, 112` | Helmet headshot plays `player/headshot_armor_01` | That file is in `DeathHeadShotArmor.AttackerFeedback` at volume 0; the heard dink is `headshot_armor_e1` (0.5 damage, 0.6 kill) plus `headshot_armor_flesh` (0.3) | Wrong file |
| 9 | `weapon_sounds.gd:113-114` | An unarmoured body hit that does not kill plays nothing | `Player.DamageBody.AttackerFeedback` (1.0, pitch 1.3) | Missing |
| 10 | `weapon_sounds.gd:108` | Attacker only | Victim (flat, 1.5) and onlookers (to 1100) hear hits too | Missing |
| 11 | `src/combat/bullet_impacts.gd:70, 85-86` | -20 dB, 157-unit reference, cut at 3150 | Volume 1.0 (wood 0.3), full to 40, 0.33 at 219, silent at 600 (glass 1000) | Level and range |
| 12 | `bullet_impacts.gd:36` | Metal impact stem `physics/metal/metal_solid_impact_bullet` | `SolidMetal.BulletImpact` plays `physics/metal/bullet_metal_solid_01-06`; grates, vents, chain-link have their own | Wrong file |
| 13 | `bullet_impacts.gd:42-45` | Glass, rubber and plastic map to the default sound | `Glass.BulletImpact` (to 1000), `Rubber.`, `Plastic_*.` exist | Missing |
| 14 | `src/combat/` (none) | No whiz, no ricochet | `BulletBy.*` within 72 units, `FX_RicochetSound.Ricochet` to 236 | Missing |
| 15 | `src/grenades/grenade_view.gd` (whole file) | No grenade sounds | Throw 1100, bounce 1700, detonations and distant layers, fire loop 1200, flight loop 1275 | Missing |
| 16 | `src/grenades/flash_overlay.gd` | No ringing or muffle | `Flashbang.Ring.*` and DSP 134-136 | Missing |
| 17 | `src/bomb/c4_view.gd:16-19` | Stems guessed from CS:GO | Beep `c4_beep2` (A) / `c4_beep3` (B), `_10sec` versions; explode `c4_explode1` plus the shockwave set | Wrong file |
| 18 | `c4_view.gd:18` with `sound_bank.gd:46-49` | `weapons/c4/c4_beep` takes every file whose rest is a number or starts with `_`, so `c4_beep2` and `c4_beep3` are both picked at random; `c4_explode` likewise takes `c4_explode1` and `c4_explode_close_01` (*Inferred* from the prefix rule) | A plays one beep, B the other | Behaviour |
| 19 | `c4_view.gd:80-81, 171-173` | Beep 394-unit reference, explosion 2362, both cut at 11 811 | Beeps silent at 1300; explosion flat to 1100 and the shockwave layers | Range |
| 20 | `src/bomb/c4.gd:234-236` | Beep interval linear from 1.0 s to 0.1 s | round-bomb-grenades.md 1.3 already flags this (exponential, fraction-based) | (linked) |
| 21 | `c4_view.gd` | No plant, defuse, pickup or 10-second sounds | `c4.plant` to 4100, `c4.disarmstart` to 2000, `Player.PickupC4` to 1100, `C4.10Seconds` | Missing |
| 22 | `reference/systems/bomb.md:35-36` | "Sounds `c4_beep*` and `c4_explode*` guessed" | Settled by name here (section 5) | Doc |
| 23 | `weapon_sounds.gd:40-41` | Your own shot plays flat (2D), others' in 3D | Matches CS2's local-player handling in spirit (`is_tagged_1p_sound`, STK); fine | Same |

## 10. What players criticise and want

Each item: the complaint, its source and date, and whether it could apply to
ours as a measured option. Server cost is weighed first; anything that would
run per tick per player says so.

1. **Vertical direction is hard to hear** (above or below you, and front or
   back). *Community*: [critfeed audio guide 2026](https://critfeed.com/best-cs2-audio-settings/),
   [strafe.com](https://www.strafe.com/news/read/cs2-players-face-new-audio-bug/)
   (undated). Valve's own work on it (*Valve*): "Added unique audio occlusion
   layer to help with vertical sound positioning in Nuke." (2023-06-30);
   "Tuned the vertical audio occlusion of grenade sounds in Nuke and Vertigo"
   (2023-09-16); "Fixed an issue where some player-centric sounds were being
   perceived as originating from slightly behind the player" (2024-02-07);
   "Vertical occlusion is now more gradual at the edges of transition points
   in Nuke and Vertigo." (2026-04-01). So Valve treats vertical placement as a
   per-map occlusion layer, not a general fix.
   *Applies*: Godot's 3D audio has no HRTF, so ours starts worse. Option: a
   per-frame, client-only elevation cue (a low-pass or small gain drop for
   sources well below the listener, a slight brightening above), tested by a
   blind A/B of "above or below" on 20 recorded sounds. Server cost: none.
2. **Hits are hard to count at high fire rates**, and body hits were late.
   *Community*: [Steam discussion 4355621052302735838](https://steamcommunity.com/app/730/discussions/0/4355621052302735838)
   (undated). Valve reduced the attacker's body-shot delay and added the duck
   on 2025-05-15 (*Valve*, quoted in section 3), after "Various adjustments to
   bullet hit feedback." (*Valve*, 2024-11-07) and damage prediction
   (*Valve*, 2024-11-13).
   Players also ask for an optional hitsound
   ([Steam discussion 458604254458500232](https://steamcommunity.com/app/730/discussions/0/458604254458500232/),
   undated; community plugins such as [tickcount/hitsounds](https://github.com/tickcount/hitsounds)).
   *Applies*: ours already plays feedback on the shooter's own frame, which is
   CS2's post-May-2025 behaviour. Option: a short duck of the `Weapons` bus for
   about 100 ms on each feedback (Godot bus effect, client only), and an
   optional plain hitsound setting; measure hits counted correctly in a
   10-round spray. Server cost: none (the hit is already known).
3. **The flashbang's ringing is unpleasant** and an accessibility problem.
   *Community*: [dotesports](https://dotesports.com/counter-strike/news/cs2-players-are-begging-valve-to-add-black-flashbang-screens-and-remove-the-ringing-sound)
   and a console workaround `snd_remove_soundevent Flashbang.Ring.*`
   ([X post, Feb 2024](https://x.com/austincsgo_/status/1762231856953516059)).
   Valve's only change: "Lowered volume of flashbang ringing and volume
   ducking effect." (*Valve*, 2023-03-24); the notes have no ring setting.
   *Applies*: build the ring faithfully, and add a ring-volume setting that
   keeps the muffle (the muffle carries the gameplay, the ring is the
   discomfort). Server cost: none.
4. **An HE deafens too much**, and its damage sound reveals a hidden CT.
   *Community*: [Steam discussion 3881597531962761753](https://steamcommunity.com/app/730/discussions/0/3881597531962761753/)
   (undated); REZ's concern
   ([dotesports](https://dotesports.com/counter-strike/news/cs2-pro-explains-why-new-he-mechanic-might-hurt-ct-side),
   undated). *Applies*: the reveal is the onlooker damage sound (section 3);
   faithful is to keep it. The deafening strength is unmeasured (L4). Option:
   the lighter of the three shock presets for chip damage, measured by
   whether a listener can still identify a step 400 units away during the
   effect. Server cost: none beyond the damage event the server already sends.
5. **Distant gunfire is hard to place.** *Community*: Steam discussions
   ([3821921664847641425](https://steamcommunity.com/app/730/discussions/0/3821921664847641425),
   undated) call CS2's sound muffled and hard to pinpoint; others defend the
   vagueness as realism. *Applies*: the distant layers in section 1.1 are what
   carries direction beyond 1300 units. Option: keep them fully spatialised
   (not the flat stereo CS2 uses only within 60 to 80 units), measured by
   direction-guess error at 1500 and 2500 units. Server cost: none (the shot
   is already sent).
6. **Hearing through walls.** Valve lowered occlusion for gunfire, steps and
   reloads ("Lowered occlusion and distance effects for gunfire, footsteps
   and reloads", *Valve*, 2023-09-13), then "Further reduced occlusion
   effects" (*Valve*, 2024-02-07), and adjusted vertical occlusion on Nuke and
   Vertigo (*Valve*, 2023-09-16 and 2026-04-01, item 1). CS2's events ask
   for baked occlusion, but it is switched off (`snd_use_baked_occlusion 0`,
   *Read*, CV 9363), so the client traces its own rays (`audio-engine.md`
   section 3). *Applies*: Godot has none. Option: client-side, per frame, one ray
   from each audible source to the listener, capped (for example 16 rays a
   frame, nearest sources first), scaling the event's `occlusion_intensity`.
   Server cost: none; the server keeps sending by distance only.
7. **Silent reload (new).** Valve: "Players can now reload silently (but
   slowly) by pressing and holding the reload key." (*Valve*, 2026-09-22).
   *Community*, for the reaction only: players see it as a large change to
   clutches
   ([talkesport](https://www.talkesport.com/news/cs2/cs2-rush-hour-update-silent-reloads-premier-3v3-mode/),
   22 to 23 Sep 2026). *Applies*: it is CS2's rule now, so faithful means
   building it: a held-reload state on the weapon (server, per command, one
   bool), a `stealth` flag on the reload's sound events, and the 0.07 and x5
   on the listening side. Server cost: one comparison per reload command.
8. **Bomb sounds not heard** in some places. *Community*: Steam threads
   ([541907867765753045](https://steamcommunity.com/app/730/discussions/0/541907867765753045/),
   undated), and a fix quoted as "C4 defuse and planting sounds could not be
   heard in certain locations" (*Community*, dotesports patch list, undated).
   That line is not in Valve's CS2 notes from 2023-03-22 to 2026-09-22, so it
   is either CS:GO-era or misquoted; treat it as unconfirmed. Valve's nearest
   is "The bomb damage health preview is now revealed when the bomb becomes
   audible." (*Valve*, 2026-07-20). *Applies*: ours plays
   beeps from the plant time on each client, which cannot be missed by the
   network; keep it that way. Server cost: none.

A server-side option for all of them, from CS2's own design: cull each sound
event per recipient by its curve's end (one squared-distance compare per
recipient per event, done on the tick where the event happens, never per
tick per player). It saves bandwidth and denies sound-based wallhacks,
exactly as CS2 does for steps at 1250.

## Corrections for other docs and code

1. `reference/cs2-systems.md:450-451` (S2): the sound event definitions are
   readable remotely from GameTracking-CS2's text `.vsndevts` (build 2000915);
   S2 need not wait for Sid's machine. Mark it Remote, or done by this page.
2. `reference/systems/bomb.md:36`: replace "Guessed from CS:GO's names" with
   the events of section 5: `C4.PlantSound` (`c4_beep2`, A) and
   `C4.PlantSoundB` (`c4_beep3`, B), `_10sec` versions, `c4.explode`
   (`c4_explode1`) and the `c4.shockwave.*` set.
3. `src/bomb/c4_view.gd:18-19`: stems `weapons/c4/c4_beep2` and `c4_beep3`
   chosen by the bomb's site letter, and `c4_beep2_10sec`/`c4_beep3_10sec`
   under ten seconds; explosion `weapons/c4/c4_explode1`. As written, the
   `SoundBank` prefix rule mixes A and B beeps and pulls `c4_explode_close_01`
   into the explosion.
4. `src/bomb/c4_view.gd:80-81, 171-173`: beeps silent at 1300 units, not an
   inverse curve to 11 811.
5. `src/audio/weapon_sounds.gd:33`: `HIT_SETS` should be the CS2 feedback
   files: body `physics/surfaces/mud_impact_bullet` (damage and kill),
   kevlar `player/kevlar_0` (1-8), headshot `player/headshot_noarmor_0`,
   helmet `player/headshot_armor_e1` plus `player/headshot_armor_flesh`;
   drop `bodyshot_kill_01` and `headshot_armor_01` (volume 0 in CS2).
6. `weapon_sounds.gd:108-114`: play the unarmoured body feedback on every
   hit, not only kills; volumes from section 3 (body 1.0, kevlar 1.2,
   headshot 0.5, dink 0.5 to 0.6).
7. `weapon_sounds.gd:59-62`: replace the inverse curve with the event's own
   distance curve (near and distant layers), and route the M4A1-S and USP-S
   silenced shots through the silenced curve (silent at 1400).
8. `weapon_sounds.gd:51`: one near-layer instance per shooter (a new shot
   stops the last), two for the distant layer.
9. `weapon_sounds.gd:72-75`: play the draw only when not `spatial` (only
   the holder hears a draw), so `bot.gd:150` stops announcing bots' switches.
10. `src/bots/bot.gd:383-384`: bots' reloads, dry fire and pickups should be
    heard (1100 units), as CS2's are; that wants the sim to emit the events.
11. `src/combat/bullet_impacts.gd:36, 42-45, 70, 85-86`: the metal stem is
    `physics/metal/bullet_metal_solid_`; add glass
    `physics/glass/glass_impact_bullet`; volume from the event (1.0, wood
    0.3) and silent at 600 (glass 1000).
12. `reference/systems/grenades.md:158-162` (item 7): the grenade sounds are
    now tabled by name (section 4); a bounce is per grenade, not per surface.
    `reference/cs2-systems.md:387-389` (G6) can drop "a bounce per surface,
    if the game has one": it has none.
13. `reference/research/combat.md:331-333`: add that the distant layer's
    start varies by gun (90 units for the P90, 336 to 525 for eight guns, 800
    for the rest) and that the MP5-SD keeps the 9000 broadcast while the
    M4A1-S and USP-S do not.
14. `reference/research/round-bomb-grenades.md:476-478`: the three ring
    events are volume 0.1, flat to 2800, and the muffle is DSP presets 134 to
    136 (`dsp_presets.txt`); HE shock presets 137 to 139 exist.
15. `reference/research/round-bomb-grenades.md:657`: add `C4.PlantSoundB` is
    site B (pitch 0.9), and the ranges: plant 4100, defuse 2000, beeps 1300.
16. The silent reload (22 Sep 2026) belongs in `reference/weapons/TODO.md`
    and the roadmap as a new Remote item: a held-reload state, a slower
    reload, and the 0.07 volume and x5 distance on reload sounds. Cite
    Valve's note of 2026-09-22, not the news sites.
17. `reference/research/combat.md:374-376`: the knife sound change is Valve's
    note of 2026-01-21 ("Knife impact sounds are now unique based on primary
    fire or alt fire swings as well as front and rear attacks"); cite it in
    place of hltv.org/news/43689.
18. `reference/research/round-bomb-grenades.md:224-243`: the July 2026 bomb
    lines are in Valve's own notes, dated 2026-07-08 (shockwave), 2026-07-09
    (the three C4 fixes, quoted exactly as the page has them) and 2026-07-20
    ("The bomb damage health preview is now revealed when the bomb becomes
    audible."; so "20 or 21 July" is 20 July UTC). Cite Valve in place of
    Dust2.us, SteamAnalyst and insider-gaming; keep Fandom only for the blog
    text, which is not in the release notes.
19. Any page citing a news site for a CS2 patch line should cite Valve's
    note instead, from the archive in Sources (`ckreisl/cs-updates-as-json`
    656981c). Keep a community source only where Valve's notes say nothing.

## Local checks

What only someone with CS2 installed can settle, and how.

| # | Question | How |
|---|---|---|
| L1 | Is the distant gunfire layer heard past 2869 units (held at 0.10) or does it stop? Same for the HE, smoke and fire distant layers past 2800 | Private server, `sv_cheats 1`, a bot firing an AK at 2800, 3200 and 4500 units (`cl_showpos` for distance); record and compare levels; `snd_sos_show_soundevent_start 1` shows what starts |
| L2 | What `broadcast_distance_override` does: does a jump (98) reach a client 300 units away? Does the radar ring's size follow the curve's end or the broadcast distance? | Two clients on a LAN server, one jumping at 50, 150 and 300 units; `snd_sos_show_soundevent_start 1` on the listener; screenshot the radar ring after a jump, a step and a shot |
| L3 | The silent reload: how much slower, which sounds are suppressed, whether `weapon_reload` still fires (bots) | Hold R with each rifle, time the clip from a demo; listen at 50 and 200 units; `bot_quota 1`, watch whether the bot turns to a silent reload behind a wall |
| L4 | Which flash ring and muffle go with which blind length; whether and when an HE applies a shock preset | Flash at 3 distances facing and away; note `Flashbang.Ring.*` in `snd_sos_show_soundevent_start` and `dsp_player`'s value; take HE damage at 10, 40 and 90 HP lost |
| L5 | Which surfaces map to which `*.BulletImpact` on dust2 (the `.vsurf` is not in the checkout) | Decompile `surfaceproperties.vsurf_c` with Source 2 Viewer, or shoot each dust2 surface with `snd_sos_show_soundevent_start 1` |
| L6 | Whether the whiz is subsonic for any gun, and whether rounds without a tracer whiz | Stand 40 units beside a bot's line of fire for each gun class; log `BulletBy.*` starts |
| L7 | When the ricochet plays | Shoot metal and concrete at grazing and square angles from 100 units |
| L8 | Whether the victim hears `Player.Death` (the cry) and who else does | Die to a bot with a second client 300 and 1300 units away |
