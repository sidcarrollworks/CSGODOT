# How a CS2 round sounds: round, interface, voice, music and ambience

Research for CSGODOT (Godot 4.7, single player against bots on de_dust2 first).
It covers every sound of a round's life, the radio and agent voices, music
kits, dust2's ambience, and what a Godot build needs. It is one of the
audio pages listed in `audio.md`: the mixer is in `audio-engine.md`, and the
bomb's and grenades' own sounds are in `audio-gameplay.md`; this page links to
them rather than repeating them.

Read first, and not repeated here: `reference/research/round.md`,
`round-hud-bots.md` (A8 alerts and the 10 s warning, A9 events, B bot
chatter), `round-bomb-grenades.md` (1.3 beeps, 2.x grenades),
`round-economy.md` (4.1 phases and timers, 4.4 half and match end, 5 events),
and `reference/cs2-systems.md` section 10 (S1, S2).

## Sources, newest first

| Mark | Source | Date or build |
|---|---|---|
| *Read* | SteamDatabase GameTracking-CS2, commit `d45f52d`: CS2 build 2000915, PatchVersion 1.41.8.3. Paths below are relative to its root (`game/csgo/pak01_dir/...` shortened to `pak01/...`). | 2026-09-23 |
| *Valve* | Valve's own CS2 release notes, archived in ckreisl/cs-updates-as-json at `656981c` (`data/cs2/updates_raw.json`, 231 posts). Each claim gives the post's date. | 2023-03-22 to 2026-09-22 |
| *Read* | The CSGODOT repository: `main` is at `3975eef`. The files were read from the research branch `claude/research-footsteps` (`95b7d4f`), whose `src/` is unchanged from `3975eef`. | 2026-09-24 |
| *Community* | Web search summaries only (pages refused fetches), used only where Valve's notes say nothing; each has its URL and the date where the summary showed one. | as given |
| *Inferred* | My reading of the Read sources. | |
| *SDK* | Source SDK 2013 behaviour, used only as a spec and said to be unconfirmed for CS2. | 2013 |

Valve's leaked CS:GO source was not used. Where a claim rests only on an
older or secondary source it says so beside the claim.

A number in this page is `volume` in the sound event unless it says
otherwise. CS2's heard level is roughly event volume, times the event's
convar (for music), times its mixgroup's level in the mixer, times the
master volume (*Inferred* from the fields; the mixer agent has the full
chain).

---

## 1. The round, in order

### 1.1 The volume settings (all *Read*, build 2000915)

The audio settings screen (`pak01/panorama/layout/settings/settings_audio.xml`)
binds each slider to a convar; labels are from `pak01/resource/csgo_english.txt`
lines 44581 to 44707; defaults and descriptions from `DumpSource2/convars.txt`.

| Setting label | Convar | Default | Convar description |
|---|---|---|---|
| Master Volume | `volume` | (engine) | |
| Main Menu Ambience Volume | `snd_menumap_volume` | 1 | "Volume of background sounds for maps" (the menu's map backdrop, `UIPanorama.BG_de_dust2`) |
| Master Music Volume | `snd_musicvolume` | 1 | "Music volume" |
| Main Menu Volume | `snd_menumusic_volume` | 0.04 | "Volume of Menu / Non-gameplay music" |
| Round Start Volume | `snd_roundstart_volume` | **0** | "Volume of Round Start Music" |
| Round Action Volume | `snd_roundaction_volume` | **0** | "Volume of Move Action Music" |
| Round End Volume | `snd_roundend_volume` | 0.16 | "Volume of Won/Lost Music" |
| MVP Volume | `snd_mvp_volume` | 0.16 | "Volume of MVP Music" |
| Bomb/Hostage Volume | `snd_mapobjective_volume` | 0.04 | "Volume of Map Objective Music" |
| Ten Second Warning Volume | `snd_tensecondwarning_volume` | 0.04 | "Volume of Ten Second Warnings" |
| Death Camera Volume | `snd_deathcamera_volume` | 0.16 | "Volume of Deathcam Timers" |
| (Mute MVP music while both teams live) | `snd_mute_mvp_music_live_players` | false | "If set, MVP music is muted if players from both teams are still alive." |
| Other Player Voice Volume | `snd_voipvolume` | 1 | voice chat |
| (no slider) | `snd_gamevoicevolume` | 1 | "Game v.o. volume" |

- Each music convar has `_casual`, `_deathmatch`, `_armsrace` and `_rush`
  copies with their own defaults (round start 0.0225 in casual, map
  objective and ten-second 0.01 outside competitive). "Each game mode keeps
  its own set of music volumes" (`SFUI_Settings_Music_Mode_Tip`);
  `snd_music_mode 1` "Selects which per-game-mode set of music volume
  convars is live". *Inferred:* the unsuffixed set is competitive's, which is
  the one this build copies. *Valve*, 2026-09-22: "Players can now adjust
  music volume per game-mode", so these per-mode copies are one day older
  than the dump.
- Other dated changes behind today's settings (*Valve*): 2023-08-31 "Added
  music preview button to music volume sliders"; 2023-09-29 "Fixed missing
  win/loss/MVP music in Casual"; 2025-05-07 "Added 'Main Menu Ambience
  Volume' setting" (`snd_menumap_volume`); 2025-07-30 "Fixed a bug where the
  CS2 music kit was replaced by the CS:GO music kit".
- **So by CS2's own defaults a competitive round has no round-start and no
  round-action music at all**; you hear the bomb and ten-second cues at 0.04,
  round end, MVP and death camera at 0.16.
- *Community, disputed and stale:* csdb.gg and similar pages
  (https://csdb.gg/command/snd-tensecondwarning-volume/, no date shown) give
  `snd_tensecondwarning_volume` 0.05, round start 0.04, round end 0.04,
  death camera 0, MVP 0.03. These are CS:GO-era or older CS2 values; the
  build 2000915 dump wins. Valve's notes never state the defaults.

### 1.2 Timeline

"Who" is who hears it. "Trigger" is what starts it: a server game event the
client reacts to, or the client's own HUD. Event names are CS2's
(`pak01/resource/mod.gameevents`, `game.gameevents`,
`game/core/pak01_dir/resource/core.gameevents`). All sound event names are
*Read* from the `.vsndevts` named; where the file is not named it is
`pak01/soundevents/game_sounds_ui.vsndevts`.

| Moment | Sound event (file) | Vol, mixgroup | Scaled by | Who | Trigger |
|---|---|---|---|---|---|
| Warmup timer running out | `Alert.WarmupTimeoutBeep` (`sounds/ui/beep07`) | 0.74, UI | none | each client | client HUD (*Inferred*; referenced only in `client_strings.txt`). Offline competitive has no warmup: `mp_warmup_offline_enabled false` (convars) |
| Match start | `Music.MatchStart.<kit>` (`startofmatch`, 14.4 s) | 0.8, SelectedMusic | `snd_menumusic_volume` | each client, own kit | client; `round_announce_match_start` (*Inferred* from names) |
| Freeze time | `Music.StartRound.<kit>` (`startround_01`, loop 0.517 to 33.62 s) | 0.9, BuyMusic | `snd_roundstart_volume` (**0**) | each client | client at `round_start` (*Inferred*) |
| Freeze countdown | `UI.CounterBeep` (`sounds/ui/counter_beep`) then `UI.CounterDoneBeep` | 0.2, then 0.35, UI | none | each client | server events `cs_round_start_beep` and `cs_round_final_beep` (mod.gameevents); the pairing is *Inferred* from names (both sounds appear only in `client_strings.txt`); the repo's `round-economy.md` 4.1 has "a beep each second for the last 3 s" from memory |
| Freeze end, "Let's go" | agent line, concept `radio.letsgo`, `radio.locknload`, `radio.go` or `radio.moveout` (`server_strings.txt` lines 31597 to 31600; events like `sas.radio.letsgo01`, `phoenix.radio_locknload01` in `pak01/soundevents/vo/agents/`) | 1.0, VO | `snd_gamevoicevolume` | the speaker's team (*Inferred*, see 2.3) | server at `round_freeze_end` (*Inferred*: server-side concept names) |
| Round action | `Music.StartAction.<kit>` (`startaction_01/02`) | 0.9, no group | `snd_roundaction_volume` (**0**) | each client | client at `round_freeze_end`; `stop_at_time 10`, fades out over 3 s |
| Buy menu | `UIPanorama.buymenu_mouseover` 0.3, `buymenu_select` 0.5, `buymenu_purchase` 0.3 (`radial_menu_buy_03`), `buymenu_failure` 0.4 (`weapon_cant_buy`) | UI | none | self | client buy menu (the names `buymenu_open`, `buymenu_purchase`... are in `client_strings.txt` 30400 to 30404). Server events `buymenu_open`/`buymenu_close` exist. *Valve*: 2023-03-24 "Added some missing ui sounds"; 2025-05-12 "Remastered various UI sounds"; 2024-10-02 "Fixed a bug where UI sounds wouldn't position correctly when in-game" (UI sounds are 2D: `snd_ui_positional false`) |
| Buying an item | the world hears the item arrive: `Player.PickupWeapon` 0.7 (fades to 0 at 1000 u), `Player.EquipArmor_T` 0.3 / `_CT` 0.1 (game_sounds_player) | Foley | none | everyone near | server (`Player.PickupWeapon` is in `server_strings.txt`). Whether a buy plays the pickup: *Local check* |
| Picking up a dropped gun via the menu | `UIPanorama.buymenu_pickup_weapon` 0.5 | UI | none | self | server (`server_strings.txt` 22361). *Valve*, 2026-07-08: "Fixed case where picking up dropped weapons through the Buy Menu would fail to complete" |
| Buy preset refused | `BuyPreset.CantBuy`, `BuyPreset.AlreadyBought` (names in `server_strings.txt` 10547, 10548) | not in the dump's `.vsndevts` | | self | server |
| Refund (sell back) | no event of its own found | | | | *Local check*. *Valve*: 2023-06-06 "Players can now refund any purchase that was purchased in the same round and has not been used"; 2024-02-07 "Added a 'Refund All' button to the buy menu" |
| Bomb planted, voice | `Announcer.BombPlanted.CS2_Classic` (`vo/announcer/cs2_classic/bombpl`, 1.5 s) | 0.6, UI | none | everyone (*Inferred*; played by the client for all) | client at `bomb_planted`; the client builds the name from `Announcer.BombPlanted.%s` (`client_strings.txt` 12577), `%s` the announcer pack |
| Bomb planted, music | `Music.BombPlanted.<kit>` (39.1 s, loops) | 0.8 | `snd_mapobjective_volume` 0.04 | each client | client at `bomb_planted`; stops at the ten-second cue |
| Bomb 10 s left | `Music.BombTenSecCount.<kit>` (12.0 s) | 0.9 | `snd_tensecondwarning_volume` 0.04 | each client | client, from the bomb's timer (`m_bTenSecWarning`, `round-bomb-grenades.md` 1.3); `stop_bomb_planted`. The C4's own faster beeps are separate (`C4.PlantSound_10sec`; *Valve*, 2023-10-17: "New sound for final 10 seconds of bomb beeping") |
| Round 10 s left | `Music.TenSecCount.<kit>` (`roundtenseccount`, 12.0 s) | 0.9 | `snd_tensecondwarning_volume` 0.04 | each client | server event `round_time_warning` (game.gameevents, no fields) is the likely trigger (*Inferred*); its threshold is in no file. *Valve*, 2023-06-08: "Fixed a regression where 10-second music cue was sometimes not playing" |
| Round won or lost | `Music.WonRound.<kit>` (6.2 s) or `Music.LostRound.<kit>` (7.3 s) | 1.0 | `snd_roundend_volume` 0.16 | each client, by own team | client at `round_end`; skipped when `round_end.nomusic` is set ("don't play round end music, because action is still on-going", mod.gameevents) and blocked by an MVP anthem |
| Round won, announcer | `Announcer.CTWin.CS2_Classic` "Counter-Terrorists win", `Announcer.TWin.CS2_Classic` "Terrorists win", `Announcer.RoundDraw.CS2_Classic` | 0.6, UI | none | everyone | client at `round_end` (`client_strings.txt` 12578 to 12580) |
| Bomb defused, announcer | `Announcer.BombDefused.CS2_Classic` 0.6, UI, or one of `Event.BombDefused_Legacy1..3` ("yesss", "that's the way", "this is my house"...) 0.5, VO | | none | everyone | client; *Inferred:* `round_end.legacy` ("server-generated legacy value") picks the legacy line |
| Round report panel | `UIPanorama.round_report_line_up/_down` (1.0), `round_report_odds_up` 1.0 / `_dn` 0.5 / `_none` 1.0, `round_report_round_won` 0.7 / `_lost` 0.6 | UI | none | self | client HUD, `pak01/panorama/scripts/hud/hudwinpanel.js` lines 232 to 245 and 434 to 435 |
| MVP | `Music.MVPAnthem.<MVP's kit>` (10.9 s) | 0.9 | `snd_mvp_volume` 0.16 | everyone, the MVP's kit ("Playing {s1}'s MVP Anthem", `SFUI_WinPanel_Playing_MVP_MusicKit`) | client at `round_mvp` unless `round_mvp.nomusic`; `block_won_lost`: the anthem replaces the won/lost music (*Valve*, 2024-02-28: "Fixed some cases where MVP music would not play or would play over round end music"). *Valve*, 2026-05-14: NIGHTMODE II kits got a second anthem, `roundmvpanthem_02`, "which plays at 1:5 ratio"; the default kit has one |
| Death camera | `Music.DeathCam.<kit>` (7.3 s) | 1.0, DuckingMusic | `snd_deathcamera_volume` 0.16 | self | client on its own death (`check_for_classic_deathcam`); `Player.FreezeCam` (deathcam stinger) is volume 0, silent. *Valve*: 2026-04-01 "Fixed bug where DeathCam music cue was causing volume ducking for too long"; 2026-04-28 "Removed first-person death sound effect that played in the case of music kit death cue being inaudible", so a muted death cue now means silence |
| Last round of the half | `Music.Match.LastRoundHalf` (`sounds/ui/lastroundhalf`) | 0.3, UI | none | everyone | client at `round_announce_last_round_half` (*Inferred*) |
| Match point, final round | `Music.Match.MatchPoint`, `Music.Match.FinalRound` (both `sounds/music/cs_stinger`) | 0.2, UI | none | everyone | client at `round_announce_match_point`, `round_announce_final` (*Inferred*) |
| Half time | no sound of its own found; the side swap sends `announce_phase_end` and `start_halftime` | | | | `round-economy.md` 4.4 |
| Match end | `Music.MatchEnd.<kit>` (44.4 s) plus `UIPanorama.gameover_show` 0.5 | 0.8 SelectedMusic; UI | `snd_menumusic_volume` 0.04 | each client | client at `cs_win_panel_match` (*Inferred*) |
| Kill feed line | `UI.DeathNotice` 0.1 exists but no binary names it | UI | | | *Inferred* unused |

Notes on the table:

- **Every music cue is client-side** and uses the listener's own kit,
  except the MVP anthem, which uses the MVP's (*Read*: `client_strings.txt`
  holds every `Music.*` name and `server_strings.txt` none; the MVP text
  above). Offline, bots have no kit; which anthem a bot MVP plays is a
  *Local check*.
- **The announcer is client-side too** (`Announcer.*` only in
  `client_strings.txt`). The older `Event.BombPlanted`, `Event.CTWin`,
  `Event.TERWin`, `Event.RoundDraw` (VO mixgroup, in the same announcer file)
  are named by neither binary, so *Inferred* unused.
- The music cues pre-empt each other by `priority`: start round and action
  2, bomb and ten-second 3, won and lost 4, MVP 5; and by flags
  (`stop_start_round`, `stop_tensec_count`, `stop_bomb_planted`,
  `stop_music_except_mvp`, `block_won_lost`, `test_mvp_block`) (*Read*,
  `pak01/soundevents/music/valve_cs2_01/game_sounds_music.vsndevts`).
- **Ducking.** The death camera cue sits in the `DuckingMusic` mixgroup,
  which drives `DuckingMusicLayer` in `pak01/scripts/soundmixers.txt`:
  world, weapons, footsteps, foley, physics, explosions and ambient to 0.5,
  other music to 0.1; the event's `time_mixlayer_amount_curve` takes that
  layer from 1 to 0 over 1.5 s. Match-start and match-end music sit in
  `SelectedMusic`, whose layer mutes `Music` and halves the world. On death
  the client also applies `DeathFadeLayer` (world, physics, ambient 0.01;
  weapons, footsteps 0.5) through `cl_deathcam_audio_mix_phase1_fade_amount
  0.15` over `_time 2` s and `phase2_fade_amount 0.5` over `0.4` s (convars).
  Details belong to the mixer page.

### 1.3 The default kit

- CS2's default kit is **`valve_cs2_01`**, "Valve, Counter-Strike 2", "The
  official music kit of Counter-Strike 2" (*Read*: `pak01/scripts/items/items_game.txt`
  line 45551, music definition 1; `csgo_english.txt` 5912). CS:GO's defaults
  remain as `valve_01` (definition 70) and `valve_02` (definition 2).
  *Valve*, 2025-07-30: "Fixed a bug where the CS2 music kit was replaced by
  the CS:GO music kit".
- Its files (all under `sounds/music/valve_cs2_01/`): `mainmenu` 207.2 s,
  `chooseteam` 46.8 s, `startofmatch` 14.4 s, `startround_01` 35.7 s (looped
  0.517 to 33.62 on a 2.069 s grid of sync points), `startaction_01/_02`
  25.3 s, `bombplanted` 39.1 s, `bombtenseccount` 12.0 s, `roundtenseccount`
  12.0 s, `wonround` 6.2 s, `lostround` 7.3 s, `deathcam` 7.3 s,
  `roundmvpanthem_01` 10.9 s, `endofmatch` 44.4 s.

---

## 2. Radio, voice and callouts

### 2.1 The radio menus and the chat wheel (*Read*)

- **Keys** (`game/csgo/cfg/user_keys_default.vcfg`): `z` "radio", `c`
  "+radialradio", `v` "+radialradio2", `MOUSE3` "player_ping", `MOUSE4`
  "+voicerecord". CS:GO's `x` radio is gone: `x` is "slot12". The repo's
  `reference/binds.md` already lists these.
- **The classic menu** (`pak01/resource/ui/radiopanel.txt`, drawn by
  `CSGOHudRadio`, `panorama/layout/hud/hudradio.xml`), each group timing out
  after 5 s (*Valve*, 2023-03-31: "Restored radio command functionality"):
  Common (Roger, Negative, Cheer, Hold this position, Follow me,
  Thanks), Command (Go, Fall back, Stick together, Hold position, Follow me),
  Standard (Roger, Negative, Cheer, Compliment, Thanks), Report (Enemy
  spotted, Need backup, You take the point, Sector clear, I'm in position).
  The server's radio concepts are `Radio.Affirmitive` [sic], `Radio.Cheer`,
  `Radio.Compliment`, `Radio.CoverMe`, `Radio.EnemyDown`,
  `Radio.EnemySpotted`, `Radio.FollowMe`, `Radio.GetOutOfThere`,
  `Radio.GoGoGo`, `Radio.HoldPosition`, `Radio.InPosition`,
  `Radio.NeedBackup`, `Radio.Negative`, `Radio.Regroup`,
  `Radio.ReportInTeam`, `Radio.ReportingIn`, `Radio.Roger`,
  `Radio.SectorClear`, `Radio.StickTogether`, `Radio.TakingFire`,
  `Radio.TeamFallBack`, `Radio.Thanks`, `Radio.YouTakeThePoint`
  (`server_strings.txt` 20031 to 20053), with matching `EVENT_RADIO_*` bot
  events (15635 to 15661).
- **The radial wheel** (`panorama/layout/radialradio.xml`,
  `CSGORadialRadio`): three tabs of eight, set by
  `cl_radial_radio_tab_<t>_text_<n>` (convars). Tab 0 by default: Need quiet,
  We should save, Ping Site B, Request a weapon, Ping Middle, Bomb was
  dropped, Ping Site A, We should buy. Tabs 1 and 2: Bomb carrier spotted,
  We should save, Multiple enemies here, Request a weapon, Rotate to me, Bomb
  picked up, One enemy here, We should buy. `csgo_english.txt` has 101
  `Chatwheel_*` strings for the rest. A wheel message plays
  `PanoramaUI.Chatwheel.Alert` (0.4, UI) (*Inferred* from the name).
- **Pings** (`player_ping {userid, entityid, x, y, z, urgent}`,
  `player_ping_stop`): `UI.PlayerPing` 1.0 and `UI.PlayerPingUrgent` 1.0,
  UI, client-side. Five tokens, one back every `player_ping_token_cooldown`
  20 s ("they get 5 tokens"). *Valve*: 2023-12-04 "Player pings will now be
  displayed in the player's color"; 2024-02-07 "Player pings are no longer
  blocked by invisible geometry". `cl_player_ping_mute 0` (description: "If 1,
  player pinging will make a sound, if 0, pings will be silent", which reads
  inverted; *Local check*).
- **Throttle.** `sv_radio_throttle_window 10` "The number of seconds before
  radio command tokens refresh", and the pawn keeps `GameTime_t[3]
  m_flRadioTokenSlots` (`DumpSource2/schemas/server/CCSPlayer_RadioServices.h`).
  *Inferred:* three radio commands per 10 s. The same component has
  `m_bIgnoreRadio` (the `ignorerad` command) and talk timers for plant,
  defuse and hostage lines. `sv_playerradio_use_allowlist true` limits
  `playerradio` to an allow list; *Valve*, 2023-03-30 (under SOUND): "Fixed
  chat wheel lines to be restricted to legitimate chat wheel lines that can
  be configured in game options".
- *Valve*, 2024-06-26: "Fixed an empty radio-command string which plays when
  planted C4 is within several seconds from detonation". *Inferred:* a radio
  line is sent automatically in the bomb's last seconds (the agents'
  `bombtickingdown` or `ct_bombexploding` lines).
- The radio event for other code is `player_radio {userid, slot}`
  (mod.gameevents).

### 2.2 Agent voice lines (*Read*)

- Every agent voice is a file under `pak01/soundevents/vo/agents/` (28 files:
  `sas`, `phoenix`, `leet`, `seal`, `swat`, `fbihrt`, `gsg9`, `balkan`,
  `professional`, `jungle`, `gendarmerie`, and `_epic`/`_fem` variants). An
  agent names its set by `vo_prefix` in `items_game.txt`. The defaults this
  repo uses are `customplayer_ctm_sas` (item 5600, "ct_map_based") and
  `customplayer_tm_phoenix` (item 5200, "t_map_based"), matching
  `src/player/view_model.gd:24-25`. *Valve*, 2023-10-17: "Added missing KSK
  agent voice" (the only voice-line change in the notes).
- **Shape of every line** (checked on all 494 SAS events): volume 1.0,
  mixgroup `VO`, a flat distance curve (1.0 at 0 and at 300 units, so no
  fall-off with distance), `position_offset [0, 0, 60]` (at the speaker's
  head), and `distance_unfiltered_stereo_mapping_curve` 1.0 to 25 units,
  0 from 30. *Inferred:* your own lines play as plain stereo, a teammate's are
  placed in his direction but at full level wherever he is: a radio, not a
  shout. The `VO` mixgroup sits at 0.34 in `Default_Mix`.
- **Concepts a set carries** (SAS; Phoenix has the T twins): throw callouts
  `ct_grenade`, `ct_flashbang`, `ct_smoke`, `ct_molotov`, `ct_decoy` (Phoenix
  `t_grenade`, `t_flashbang`, `t_smoke`, `t_molotov`, `t_decoy`); the radio
  commands (`radio.enemyspotted`, `radio.followme`, `radio.letsgo`,
  `radio.locknload`, `radio.needbackup`, `radio.takingfire`, affirmative,
  negative, thanks...); bot chatter concepts (`enemydown`, `niceshot`,
  `onarollbrag`, `oneenemyleft`, `twoenemiesleft`, `threeenemiesleft`,
  `lastmanstanding`, `noenemiesleft`, `noenemiesleftbomb`, `sniperwarning`,
  `sniperkilled`, `spottedbomber`, `spottedloosebomb`, `whereisthebomb`,
  `bombtickingdown`, `defusingbomb`, `waitingforhumantodefusebomb`,
  `plantingbomb`, `goingtoplantbomba/b`, `heardnoise`, `blinded`,
  `pinneddown`, `incombat`, `friendlyfire`, `killedfriend`, `scaredemote`,
  `radiobotendclean/close/solid` for round-end remarks); place names
  (`ctmap_cs_source*`, `tmap_de_dust*`); `ct_death`/`t_death` and
  `ct_bombexploding`.
- **Selection is by response rules.** `bot_chatter_use_rr true` ("1 = Use
  response rules"); the rules scripts are not in the dump, so which concept
  fires on a kill, a reload or a spot, and how often, is a *Local check*.
  Community summaries say the agent speaks its own voice over the standard
  radio calls, including "Fire in the hole", plants and defuses, and that
  some agents talk more than others at round start (*Community*:
  https://critfeed.com/best-agent-voice-lines-cs2/, no date shown;
  https://steamcommunity.com/app/730/discussions/0/3821914572253340980/, no
  date shown).
- A player's death cry is not a voice line: `Player.Death` (0.5,
  PlayerDamage, 1.0 at 0 to 0.59 at 114 to 0 at 1400 units) and
  `Player.DeathFem` (game_sounds_player). The combat agent covers it.

### 2.3 Throw callouts and who hears what

- On a throw the thrower's agent says the callout for that grenade
  ("Fire in the hole!" is `Cstrike_TitlesTXT_Fire_in_the_hole`, 
  `csgo_english.txt` 1119). `sv_ignoregrenaderadio` "Turn off Fire in the
  hole messages", default false, and `gamemode_competitive.cfg` line 80 sets
  0. *Inferred:* server-side, on the throw (the repo already sends
  `grenade_thrown`, `src/grenades/grenade_system.gd:108`).
- **Enemies do not hear radio or agent callouts; teammates do, at full
  level** (*Community*:
  https://www.esports.net/news/counter-strike/fire-in-the-hole-meaning/ and
  the Fandom radio page https://counterstrike.fandom.com/wiki/Radio_Commands,
  no dates shown; consistent with the flat VO curve above, *Inferred*). The
  announcer, music and HUD cues are per client. What enemies do hear is the
  world: the pin, the throw, footsteps, the pickup and armour foley.
- `ignorerad` mutes incoming radio for the listener (*Community*:
  https://vredux.com/articles/radio-commands-in-cs2, no date shown;
  `m_bIgnoreRadio` is *Read*).

### 2.4 Bot chatter (*Read*, extends `round-hud-bots.md` B)

- `bot_chatter "normal"` ("Control how bots talk. Allowed values: 'off',
  'radio', 'minimal', or 'normal'"), set to normal again by
  `gamemode_competitive.cfg` line 3 and `gamemode_competitive_offline.cfg`.
- Bots speak through the same agent voice events and response rules as
  players (`bot_chatter_use_rr`), so a bot's chatter is team radio like a
  player's (*Inferred*). The classic bot keeps `m_lastRadioSentTimestamp`,
  `m_voiceEndTimestamp` (`round-hud-bots.md`), and the server has
  `SendRadioMessage` debug output and `chatter_outnumbered_threshold`
  (`server_strings.txt`).

### 2.5 Voice chat rules (competitive, *Read*)

| Convar | Default | Competitive | Meaning |
|---|---|---|---|
| `sv_alltalk` | false | not set | all players hear all voice |
| `sv_deadtalk` | false | **1** | "Dead players can speak (voice, text) to the living" |
| `sv_talk_enemy_living` / `_dead` | false | 0 / 0 | |
| `sv_auto_full_alltalk_during_warmup_half_end` | | 0 | |
| `sv_talk_after_dying_time` | 0 | | |
| `sv_full_alltalk` | false | | |
| `sv_voice_proximity` | -1 | | undocumented |
| `cl_mute_enemy_team` | false | | client |

Single player against bots needs none of these. For the record (*Valve*):
2023-09-13 "Allow adjusting individual player voice volumes"; 2023-11-17
"Fixed the Mute Enemy Team and Mute All But Friends settings failing to
mute voice".

---

## 3. Music kits

- 102 kits under `pak01/soundevents/music/`, and every one has the same 19
  events (*Read*, counted): `Background`, `MVPPreview`, `Selection`,
  `MatchFound`, `LoadingScreen`, `MatchStart`, `StartRound`,
  `StartRound_GG`, `StartAction`, `BombPlanted`, `BombTenSecCount`,
  `GotHostage`, `HostageNearRescue`, `TenSecCount`, `WonRound`, `LostRound`,
  `DeathCam`, `MVPAnthem`, `MatchEnd`. The client builds the name as
  `Music.%s.%s` (`client_strings.txt` 22033). Parameters are identical across
  the two Valve kits compared; only the files differ.
- The per-event parameters for `valve_cs2_01` (*Read*):

| Event | Vol | Convar | Priority | Fade in / out | Stops at | Notes |
|---|---|---|---|---|---|---|
| StartRound | 0.9 | roundstart | 2 | 12 / 1.5 s | | loop, BuyMusic, `stop_music` |
| StartAction | 0.9 | roundaction | 2 | 12 / 3 s | 10 s | loop |
| BombPlanted | 0.8 | mapobjective | 3 | 6 / | | loop, stopped by ten-second |
| BombTenSecCount | 0.9 | tensecondwarning | 3 | / 0.5 s | | stops BombPlanted |
| TenSecCount | 0.9 | tensecondwarning | 3 | / 0.5 s | | |
| WonRound, LostRound | 1.0 | roundend | 4 | / 1.6 s | | `skip_if_muted`, `test_mvp_block`, stops all music but MVP |
| MVPAnthem | 0.9 | mvp | 5 | / 1.6 s | | `block_won_lost` |
| DeathCam | 1.0 | deathcamera | | | | DuckingMusic, ducking curve 1.5 s |
| MatchStart, MatchEnd, Selection | 0.8 | menumusic | | 8 / 1 s | | SelectedMusic |

  "Fade in" is `volume_fade_initial_input_max`; *Inferred* seconds.
- *Valve*, 2023-10-17 (SOUND): "New sound for final 10 seconds of bomb
  beeping". That change is to the C4's beeps (`C4.PlantSound_10sec`), not
  to the music; the kit's `Music.BombTenSecCount` is older and still plays
  alongside. (A community write-up dated 2023-10-18 calls it "ten-second
  countdown music"; Valve's wording is the one to follow.)
- Kit changes in Valve's notes are mostly new kits for sale. The ones that
  touch playback: 2023-06-30 "Added music cues to Match Accept and Loading
  screens" (`MatchFound`, `LoadingScreen`); 2024-02-17 "Normalized volume of
  NIGHTMODE music kits"; 2024-02-28 "Adjusted various music kit cues in
  NIGHTMODE Music Kit box"; 2025-08-27 a kit that looped incorrectly;
  2026-05-14 a second MVP anthem at a 1:5 ratio for NIGHTMODE II.

---

## 4. dust2's ambience (*Read*: `pak01/soundevents/ambience/game_sounds_dust2.vsndevts`)

- **How it plays.** Soundscape script files are retired: "default maps no
  longer uses soundscape script files and instead uses regular soundevents"
  (`pak01/scripts/soundscapes_manifest.txt`, every entry commented out).
  The map places `snd_soundscape` entities (`CEnvSoundscape`: `m_flRadius`,
  `m_soundEventName`, `m_positionNames[8]`, `m_bDisabled`;
  `DumpSource2/schemas/server/CEnvSoundscape.h`), plus triggerable and proxy
  kinds and `trigger_soundscape`. Each names one of the container events
  below. *SDK (2013, not confirmed for CS2):* the client takes the nearest
  soundscape entity within its radius that it can see, and cross-fades on a
  change. *Inferred:* the containers' `fadetime_volume_mapping_curve` (1 to
  0 over 2 s) is that cross-fade and the `time_volume_mapping_curve` (0 to 1
  over 0.36 s) the fade-in.
- **Dated changes** (*Valve*): 2023-03-24 "Lowered volume of some dust2
  ambience"; 2026-01-21 "Ambient sounds no longer restart from the beginning
  when transitioning between zones" (so a zone change must not restart a
  loop shared by both zones, such as `dust2.outdoors`'s wind); 2026-04-01
  "Minor adjustments to ambient sound levels"; 2025-05-15 "Body shot impact
  sounds from the attacker perspective will momentarily reduce the volume of
  weapon fire and ambience" (the mixer page's ducking). The 2024-11-14 radio
  sound change and the 2025-08-18 "daytime soundscape" changes are Train's
  and Ancient's, not dust2's.
- **Mixgroup** `Dust2`, child of `Ambient`, at 0.4 in `Default_Mix`
  (Ambient itself 0.45) (`pak01/scripts/soundmixers.txt`).
- **Containers** (event, DSP preset, children):

| Soundscape | DSP preset | Plays |
|---|---|---|
| `dust2.outdoors` | reverb_21_outsideStreet | wind loop 0.15 (`common/wind/csgo_dust_wind_lp_02`), `wind_sand` loop (volume unset), sand gusts 0.4 (+0 to 0.2) every 3 to 35 s within 300 u of you (12 files), airplanes every 15 to 60 s, 2000 to 10000 u away in the upper hemisphere, one at a time |
| `dust2.TStart` | reverb_20_outsideAlley | distant city 0.7 twice, trees and birds 1.0 twice, sand car 0.7 twice (every 13 to 35 s, gone by 552 u), a radio playing music 0.3 (`music_attribution_01`, gone by 1200 u), plus outdoors |
| `dust2.ctstart` | reverb_9_mediumChamber | distant city 1.0 (gone by 604 u), rock falls 0.3 every 13 to 35 s, creaks 0.1 every 13 to 35 s 120 to 1000 u away, a light hum 0.3 (gone by 400 u), plus indoors |
| `dust2.LongA`, `dust2.OutsideLong` | reverb_21_outsideStreet | distant city 0.7 to 0.8, trees and birds 1.0, sand car 0.7, rock falls 0.3, plus outdoors |
| `dust2.ABomb` | reverb_22_outsideOpen (container volume 0.5) | distant city 0.7, rock falls 0.3 and sand in baskets 0.3 every 13 to 35 s, plus outdoors |
| `dust2.Bbomb` | reverb_22_outsideOpen | distant city 0.7 twice, trees and birds 1.0, sand car 0.7, rock falls 0.3, plus outdoors |
| `dust2.Bdoors` | reverb_20_outsideAlley | cable stress 0.1 every 3 to 7 s, sand car, plus outdoors |
| `dust2.OutsideTunnel` | reverb_22_outsideOpen | trees and birds, sand car, plus outdoors |
| `dust2.UpperTunnel`, `UpperTunnelTun` | reverb_12_mediumBright, reverb_11_smallBright | alley wind 0.2, plus indoors |
| `dust2.LowerTunnel` | reverb_11_smallBright | interior tone 0.1, tunnel tone 0.2, two lights 0.1 |
| `dust2.LongTunnel` | reverb_6_largeRoom | alley wind 0.55, sand gusts 0.5, rock falls 0.3 |
| `dust2.TopMidTunnel` | reverb_17_smallConcrete | alley wind 0.2, tunnel interior 0.3, rock falls 0.3 |
| `dust2.indoors` | reverb_6_largeRoom (volume 0.4) | interior 0.05, tunnel 0.2, rock falls 0.3 every 13 to 35 s |
| `dust2.UnderA`, `LongDoors`, `MidDoors`, `Middle`, `ShortStairs`, `TopMid`, `LongACave`, `outdoors_dsp` | alley, concrete or street reverbs | outdoors plus a few creaks (0.01), birds or gusts |

- The one-shots with a fall-off (rock falls, gusts, birds, distant city)
  fade to 0 by 1400 units; loops (wind, tones) are flat. Emitters are set
  by `randomize_position_*` around the listener
  (`position_relative_to_player`) or at the soundscape's positions.
- Where each soundscape entity sits, and its radius, is in dust2's entity
  lump (`default_ents.vents_c`, already extracted on Sid's machine,
  `reference/asset-pipeline.md` line 29): a *Local check*.
- The main menu's dust2 backdrop is separate: `UIPanorama.BG_de_dust2`
  (1.0, `UI_Amb`, `snd_menumap_volume`).

---

## 5. What the Godot build needs

### 5.1 Server events against the repo's schema

`src/game/game_events.gd` SCHEMA (read-only here) has `round_start`,
`round_freeze_end`, `round_end {winner, reason, message, player_count}`,
`round_mvp {userid, reason, value}`, `announce_phase_end`,
`cs_win_panel_match`, `bomb_planted`, `grenade_thrown`, `item_purchase` and
`buytime_ended`. For the round's sounds it lacks (*Read*, the files above):

| Event | Why a sound needs it |
|---|---|
| `round_time_warning` | round ten-second music |
| `cs_round_start_beep`, `cs_round_final_beep` | freeze countdown beeps |
| `round_announce_match_point`, `_final`, `_last_round_half`, `_match_start`, `_warmup`; `warmup_end` | match stingers and match-start music |
| `start_halftime` | half-time presentation |
| `cs_win_panel_round` | the round report sounds |
| `round_end.nomusic`, `round_end.legacy` | skip round-end music; pick the legacy defuse line |
| `round_mvp.nomusic` (and `musickitid`, `musickitmvps`) | skip or choose the anthem |
| `player_radio {userid, slot}` | radio commands and callouts |
| `player_ping`, `player_ping_stop` | ping sounds |
| `buymenu_open`, `buymenu_close` | menu (the menu's own sounds need no event) |

**Server side** (decides who says what, once, on the tick): the throw
callout on `grenade_thrown`, the freeze-end "let's go", radio commands and
their token throttle, bot chatter choice and its timers, and every event
above. These are cheap: a handful of events a round, no traces.

**Client side** (per frame, reads events and state, never per tick): all
music, the announcer, the buy menu clicks, the round report, pings' sounds,
the freeze countdown beeps, the ducking, and the ambience (which needs only
the listener's position and the soundscape entities; no server work).

### 5.2 The minimal set to make an offline round sound like CS2

In order of what a player notices:

1. Announcer on `round_end` and `bomb_planted`: `Announcer.CTWin/TWin/
   RoundDraw/BombPlanted/BombDefused.CS2_Classic`, UI, volume 0.6, 2D.
2. Round-end music by the listener's side (`Music.WonRound`/`LostRound`,
   1.0 × `snd_roundend_volume` 0.16), skipped on `nomusic`, replaced by the
   MVP anthem (0.9 × 0.16) when there is an MVP.
3. Bomb music: `Music.BombPlanted` (0.8 × 0.04) then `Music.BombTenSecCount`
   (0.9 × 0.04) at 10 s left; and `Music.TenSecCount` at `round_time_warning`.
4. Throw callouts from the thrower's agent set (SAS or Phoenix), team only,
   2D-ish at full level with a direction; `sv_ignoregrenaderadio` as a rule.
5. The buy menu's four UI sounds, and the pickup/armour foley the world
   hears.
6. dust2's soundscape: `dust2.outdoors` everywhere outdoors plus the few
   zone containers, at the Dust2 group's 0.4.
7. Death camera music with the 1.5 s duck, and the freeze countdown beeps.
8. Match point, last-round-of-half and final-round stingers.

Round-start and round-action music are silent by CS2's defaults and can
wait. Bot chatter can start at `bot_chatter radio` level (the radio concepts
only), then grow.

### 5.3 The repo today (*Read*, `main` at `3975eef`)

- No round, interface, voice, music or ambient sound exists. The only sound
  code is `src/audio/sound_bank.gd` (files by stem, a randomizer),
  `footsteps.gd`, `weapon_sounds.gd`, `src/combat/bullet_impacts.gd`, and the
  bomb's `src/bomb/c4_view.gd` (beep and blast, stems guessed at lines 16 to
  19). There is no audio bus layout, so there is nowhere yet to hang
  CS2's mixgroups or the music convars.
- **`MatchState` never sends the round events.** `src/match/match_state.gd:181`
  emits the `round_ended` signal and `:275` `round_started`; nothing in
  `src/` connects them and nothing sends `round_start`, `round_freeze_end` or
  `round_end` to `GameEvents` (only `tests/` do). `src/economy/economy.gd:94-97`
  and `src/bomb/bomb_system.gd:44-46` listen for them. A sound listener
  would hear nothing. Check again before building on it, in case a later
  merge to `main` fixes it.
- `SoundBank` loads a set on first use by reading the directory
  (`sound_bank.gd:32-55`), which is right for a client-side player of the
  cues above as long as `load_sets` preloads them; none of these cues should
  run in the tick.

---

## 6. What players criticise and want

Search summaries only; the pages themselves refused fetches. Each item says
whether it fits this build and at what cost.

| Critique or wish | Source | Applies to our build |
|---|---|---|
| The bomb ten-second music is a "meta": you must keep music on but very low to hear when 10 s are left; it should be removed or made a proper cue. | *Community*: WarOwl, https://x.com/TheWarOwl/status/1471878281154777090 (December 2021, CS:GO era); Steam thread https://steamcommunity.com/app/730/discussions/0/1629665087675277851/ (no date shown), which also calls it "insanely overpowered" knowing whether a 10 s or 5 s defuse still fits. | Yes, as an option: a dedicated "bomb 10 s" cue independent of music volume (a HUD tick or its own volume slider). Client only, zero server cost. Measure by whether defuse decisions change in playtests. CS2 itself partly did this in October 2023 with the faster C4 beeps. |
| The ten-second warning sometimes does not play. | *Community*: https://github.com/ValveSoftware/csgo-osx-linux/issues/3369 (no date shown); *Valve* fixed one cause on 2023-06-08 ("Fixed a regression where 10-second music cue was sometimes not playing") | Our cue should be driven by the replicated bomb timer, not a one-off event, so a late or lost event cannot skip it. Free. |
| Music everywhere (menu, before rounds, last 10 s) is unwanted; players mute all music to hear footsteps. | *Community*: https://steamcommunity.com/app/730/discussions/0/3881597531965470136/ and https://csdb.gg/guides/audio-guide/ (no dates shown) | Keep CS2's per-cue sliders and its low defaults (round start and action 0). Free. |
| MVP music too quiet at maximum for some players. | *Community*: https://steamcommunity.com/app/730/discussions/0/3085520348627895655/ (no date shown) | Our convar × event volume chain should reach 1.0 at the slider's top; test the top of the range. Free. |
| Bot and teammate radio spam is annoying; players use `ignorerad` or `bot_chatter off`. | *Community*: https://critfeed.com/cs2-radio-commands/, https://steamcommunity.com/app/730/discussions/0/3647273545680679079/ (no dates shown) | Yes: offer `bot_chatter` levels and an ignore-radio toggle from the start; keep CS2's 3 per 10 s throttle for bots too. Server cost: a timer per bot, checked on events, not per tick traces. |
| Some agents are chattier than others, and some agents lack voiced lines. | *Community*: https://critfeed.com/best-agent-voice-lines-cs2/, https://steamcommunity.com/app/730/discussions/0/3821914572253340980/ (no dates shown) | Only two agents here (SAS, Phoenix); keep one frequency rule for all voices. Free. |
| dust2's wind is distracting and ambience can make a rush sound farther away than it is. | *Community*: https://steamcommunity.com/app/730/discussions/0/357287935540876317/ (no date shown) | An "ambience volume" slider for the in-game soundscape (CS2 only has one for the menu backdrop), default at CS2's level. Client only, free. Measure footstep audibility with and without it. |
| Radio callouts in CS2 are team-only; enemies cannot hear "fire in the hole". | *Community*: esports.net page above (no date shown) | Not a critique; confirms the team-only routing to build. |

---

## Corrections for other docs and code

1. `reference/cs2-systems.md:446-449` (S1): "counter-terrorists win" is not
   an agent or radio line but the announcer, `Announcer.CTWin.CS2_Classic`,
   played by each client at round end (UI, 0.6); "bomb has been planted" is
   `Announcer.BombPlanted.CS2_Classic`. "The buy sound" is
   `UIPanorama.buymenu_purchase` (client, 0.3) plus the world's pickup
   foley. "The 10-second warning" is music-kit music (`Music.TenSecCount`,
   `Music.BombTenSecCount`) scaled by `snd_tensecondwarning_volume` 0.04,
   not a beep.
2. `reference/cs2-systems.md:450-451` (S2): the sound event files are
   already readable as text in GameTracking-CS2 (`pak01/soundevents/**.vsndevts`,
   with volumes, curves and mixgroups); only the audio files themselves need
   Sid's machine. S2 can move to Remote for the event data.
3. `reference/research/round-hud-bots.md:459-463` and
   `round-economy.md:479-483`: add that the round ten-second cue is
   `Music.TenSecCount` (12 s file) and the freeze countdown sounds are
   *Inferred* to be `UI.CounterBeep` and `UI.CounterDoneBeep`.
4. `reference/research/round-hud-bots.md:458`: the planted voice line is
   the client's announcer (`Announcer.BombPlanted.%s`), not a server radio
   line.
5. `reference/cs2-systems.md:544-545`: "the end-of-match stats and MVP
   music" can cite this page: MVP anthem is the MVP's kit, 0.9 ×
   `snd_mvp_volume` 0.16, replacing won/lost music.
6. `src/game/game_events.gd:79` and `:81`: `round_end` lacks `nomusic` and
   `legacy`; `round_mvp` lacks `nomusic`. SCHEMA lacks the events in 5.1.
   (Code change for whoever owns the schema.)
7. `src/match/match_state.gd:181` and `:275`: the round's game events are not
   sent, only signals; `round_start`, `round_freeze_end` and `round_end`
   listeners in `src/economy/economy.gd:95-97` and `src/bomb/bomb_system.gd:44-46`
   never fire outside tests (if `main` has not fixed it since `3975eef`).
8. `src/bomb/c4_view.gd:16-19`: the stems are guesses; the event names are
   `C4.PlantSound`, `C4.PlantSoundB`, `C4.PlantSound_10sec`,
   `C4.PlantSoundB_10sec` and `c4.explode` (`round-bomb-grenades.md` 1.3);
   the bomb-planted announcer and music are missing from any view.

## Local checks (need CS2 installed)

1. **Freeze countdown**: in an offline competitive match with
   `snd_roundstart_volume 0`, record the last 5 s of freeze time; count the
   beeps and confirm which files they are (`counter_beep`,
   `counter_beep_done`).
2. **Round ten-second cue**: with `snd_tensecondwarning_volume 1` and all
   other music at 0, note the round timer when `roundtenseccount` starts
   (the `round_time_warning` threshold is in no file). `net_showevents 2` or
   a demo's event list shows when `round_time_warning` fires.
3. **Who hears the callouts**: two clients (or `bot_add` and spectating a
   bot with `sv_spec_hear`): does an enemy near a thrower hear "fire in the
   hole"? Does a teammate across the map hear it at full level and from his
   direction?
4. **Which concept fires when**: `bot_chatter normal`, play five rounds and
   log the console (`developer 1`); note the lines on round start, throws,
   kills, reloads, spotting, plant and defuse, and how often.
5. **Bot MVP anthem**: when a bot is MVP, which kit's anthem plays?
6. **Buy sounds**: buy a rifle, armour and a grenade, then refund one; which
   sounds play for you, and does a nearby player hear the pickup?
7. **dust2 soundscapes**: decompile `default_ents.vents_c` and list every
   `snd_soundscape*` and `trigger_soundscape` entity with origin, radius and
   soundscape name; this is what places the table in section 4.
8. **Ping sound**: whether `cl_player_ping_mute 0` pings with sound (the
   convar's description reads inverted).
9. **Levels**: record the announcer, a won-round cue and dust2's outdoor
   wind at default settings through the same output, to calibrate our
   buses against CS2 by ear and meter.
