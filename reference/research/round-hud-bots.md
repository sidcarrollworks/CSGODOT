# CS2's round HUD and CS2's bots: what the game's own files say

Research for roadmap item 15 (HUD for rounds) and items 23 and 24 (bots that
play the round), written 2026-09-24. It adds to `reference/cs2-systems.md`
sections 9, 11 and 14 rather than repeating them.

## How to read this

- **GT `<path>`** means a file in SteamDatabase's GameTracking-CS2, commit
  d45f52d (2026-09-23), a dump of CS2's own game files. The URL form is
  `https://github.com/SteamDatabase/GameTracking-CS2/blob/master/<path>`.
  The Panorama layouts (`.xml`), styles (`.css`) and scripts (`.js`) are the
  HUD's actual source as shipped, decompiled by Source 2 Viewer. They show what
  is drawn, where, how it is styled and animated, and what data each element
  takes. They do not show the C++ that decides when an element appears, which
  entries a list keeps, and so on. Where this note gives such a rule, it is
  marked.
- **Inferred** means worked out from the files and not stated in them.
  **From memory** means from my own knowledge of the game, with no source I
  could open (used sparingly). **Disputed** means two sources disagree.
- **Web access was mostly blocked** in this session. counter-strike.net,
  Steam, steamdb, developer.valvesoftware.com, Wikipedia, archive.org, GDC
  Vault (Booth's slides) and Liquipedia all returned "egress blocked". Only
  raw GitHub and the search engine's result snippets got through. So **CS2's
  release notes on bots from 2023 to 2026 could not be read directly**; see
  B9 for the little the snippets gave. Michael Booth's GDC 2004 talk
  (https://media.gdcvault.com/gdc04/slides/making_of_official.pdf) could not
  be opened either. The classic bot design in B4 therefore rests on what the
  dumped files show (CCSBot's fields, the convars, botchatter.db, the nav
  analysis keys already in the repo), plus clearly marked memory.
- Forbidden sources were not used. I also avoided ReGameDLL_CS, which is a
  reverse-engineered copy of Valve's CS 1.6/CZ game code, bot included.

---

# Part A. The round HUD

## A0. Where everything sits (the current HUD)

GT `game/csgo/pak01_dir/panorama/layout/hud/hud.xml` places each element in a
named region, and GT `game/csgo/pak01_dir/panorama/styles/hud/hud.css` aligns
the regions:

| Region (hud.xml) | Alignment (hud.css) | What it holds |
|---|---|---|
| `HudTopLeft` | top left, flows down | `CSGOHudRadar`, then `CSGOHudGameIcons` and mode panels |
| `HudTopCenter` | top centre, 2 px from the top | `CSGOHudTeamCounter`: the score, the timer, both teams' avatars |
| `HudTopRight` | top right, flows down | `CSGOHudDeathNotice` (the kill feed) |
| `HudLowerLeft` | bottom left | `CSGOMoneyPanel` (money), voice status |
| `HudBottomCenter` | bottom centre | `CSGOHudHealthAmmoCenter` (health, armour, ammo); floating above it: progress bar (plant and defuse), low-priority hint text, `CSGOHudAlerts`, high-priority hint text |
| `HudBottomRight` | bottom right | `CSGOHudWeaponSelection` (weapon and grenade row) |
| Full-screen | | `CSGOHudWinPanel`, `CSGOHudDeathPanel`, `CSGOScoreboardContainer`, the buy menu, chat |

**Disputed / changed since launch.** `reference/cs2-systems.md` section 9
puts health and armour bottom left and money top left. The current files put
health, armour and ammo in one cluster at the bottom centre (GT
`panorama/layout/hud/hudhealthammocenter.xml`). The cluster has health and
armour left of a 64 px circle holding the team's icon, and ammo to its right
(GT `panorama/styles/hud/hudhealthammocenter.css`, `.hud-HA-center`). Money
is in `HudLowerLeft`. **Inferred:** the HUD was reworked after the 2023 launch.
CS2's launch HUD, **from memory**, had health and armour bottom left, ammo
bottom right and money under the radar. The section 9 text describes that
launch layout. The rework's date could not be read from release notes.

The new cluster also holds things the old HUD did not:
- **Kill flags.** One icon per kill you made this round sits on the cluster
  (`hud-HA__kill-flag1`...). Each kill's icon has its own type: `default`,
  `headshot`, `blast`, `burn`, `slash`, `shock` (hudhealthammocenter.xml).
- **`ExpectedBombHealthBar`.** This is a preview on the health bar of how much
  health the planted bomb's blast would take. It pulses at the bomb's beep
  speed (`BombPlantedPulse__Slow/Medium/Fast`, hudhealthammocenter.css). A
  release-notes snippet from 2026-09-22 says "the bomb damage health preview is
  now revealed when the bomb becomes audible" (search snippet for
  https://www.steamanalyst.com/updates/counter-strike-2-update-2026-09-22 ,
  page itself blocked). This belongs with the bomb's July 2026 baked damage.
- The fire mode icon (single, burst, full auto) and a reserve-ammo icon per
  magazine type.

## A1. Kill feed (death notices)

**Layout**, from GT `panorama/layout/hud/huddeathnotice.xml`. One notice is a
single row that flows left to right, in this order:

1. `Revenge` icon, then `Domination` icon
2. `AttackerBlindIcon` (the attacker was flashed), placed *before* the attacker's name
3. **Attacker** name
4. `AssistParent`, shown only for a kill with an assist: a "+" label, a
   `Flashbang` icon (`flashbang_assist.vsvg`, only when the assist was a flash
   assist), and the **assister** name
5. `AttackerInAir` icon (`inairkill.vsvg`), sitting raised on the weapon icon
   (`margin-top: -14px`)
6. **Weapon** icon (24 px high, always shown except for a suicide)
7. `NoScopeIcon`, `ThroughSmokeIcon` (`smoke_kill.vsvg`), `Penetrate`
   (wallbang), `HeadShot`, `Suicide` (an icon in place of the weapon)
8. **Victim** name

Each icon is hidden by default and shown by a class on the notice
(`.DeathNoticeHeadShot #HeadShot`, `.noscope`, `.through-smoke`,
`.attacker-blind`, `.attackerinair`, `.DeathNoticeAssist`,
`.DeathNoticeFlashbang`, `.DeathNoticePenetrate`, `.DeathNoticeRevenge`,
`.DeathNoticeDomination`, `.DeathNoticeSuicide`), per GT
`panorama/styles/hud/huddeathnotice.css`. There is also a "squad wipe" strip
used by Danger Zone.

**The data** is the `player_death` game event (GT
`game/csgo/pak01_dir/resource/mod.gameevents`). Its fields are `userid`,
`attacker`, `assister`, `assistedflash`, `weapon`, `weapon_itemid`,
`weapon_fauxitemid`, `weapon_originalowner_xuid`, `headshot`, `dominated`,
`revenge`, `wipe`, `penetrated` ("number of objects shot penetrated before
killing target"), `noreplay`, `noscope` ("used for death notice icon"),
`thrusmoke` ("hitscan weapon went through smoke grenade"), `attackerblind`,
`distance` (in metres), `dmg_health`, `dmg_armor`, `hitgroup` and
`attackerinair`. The repo's `reference/systems/contracts.md` already lists these
keys and calls checking them against CS2's file a Local task. This dump
confirms them remotely: every key in the repo's `player_death` is in CS2's.

**Timing and styling**, from huddeathnotice.css:
- `DeathNoticeLifetime: 5.0`. An entry stays 5 s.
  `DeathNoticeLocalPlayerLifetimeMod: 1.5`: an entry involving you stays
  1.5 times as long, 7.5 s (**Inferred** from the names; the multiply is done
  in C++).
- `DeathNoticeFadeOutTime: 1.0s`: it then fades out over 1 s. New entries
  slide into place over 0.2 s (`transition-property: position`, ease-out).
- It sits under the top-right corner (`margin-top: 72px`,
  `padding-right: 10px`), right-aligned, the list flowing downward. The newest
  entry is at the bottom (**From memory**; the file only says `flow-children: down`).
- The number of entries shown at once is not in the files. It is set in C++.
  **From memory** it is about five to seven at 1080p. Treat it as a number to
  pick.
- **Team colours:** `CTColor: #6f9ce6` (blue), `TColor: #eabe54` (gold),
  `FadedColor: #888888`, set on each name label
  (`DeathNoticeCTColor`/`TColor`). Names are 16 px bold with a 1 px black
  shadow, cut off with an ellipsis past 160 px. `cl_show_clan_in_death_notice`
  (default true) prefixes the clan tag (GT `DumpSource2/convars.txt`).
- **Your own entries:** when you are the killer (`.DeathNotice_Killer`) the
  entry gets a **2 px solid red border `#e10000`** on a near-black background
  (`#000000e7`), with slightly heavier text (15 px, black weight). When you are
  the victim (`.DeathNotice_Victim`) the background is **dark red
  `#630606d2`**. Every other entry has the HUD's blurred translucent background.
- Related convars (convars.txt): `cl_drawhud_force_deathnotices` (draw them
  even with the HUD off), `cl_draw_only_deathnotices`,
  `cl_deathnotices_show_numbers`, `mp_display_kill_assists` (default true:
  "whether to display and score player assists"), and
  `sv_show_teammate_death_notification` (default false). The chat line
  `"Notice_Teammate_Death_Location" "%s1 died %s2"` (a teammate died at a
  place) is in GT `game/csgo/pak01_dir/resource/csgo_english.txt`.

## A2. The team counter (top centre)

From GT `panorama/layout/hud/hudteamcounter.xml`,
`panorama/scripts/hud/hudteamcounter.js` and
`panorama/styles/hud/hudteamcounter.css`:

- **Centre block (`ScoreAndTimeAndBomb`, 84 px wide).** The **timer** sits on
  top (`TimerText`, 28 px bold white, "0:00"). It gets the class
  `teamcounter_red_timer` to turn **red**. When that happens is decided in C++.
  **From memory** it is in the round's last seconds, and the repo's own 10 s
  warning (below) is the natural trigger. Under the timer are the two
  **scores**, `ScoreCT` left and `ScoreT` right, each 42 px wide.
  **Corrected 2026-09-25:** this note first said the sides follow your team.
  They do not. CS2's own styles (hudteamcounter.css, decompiled from the
  game) colour the left side's score, alive count and cards in color-CT
  `#B5D4EE` and the right side's in color-T `#EAD18A`, whoever you play
  (`.TeamScoreL`/`.TeamScoreR`, `.team__large_container--left`/`--right`, the
  containers `#TeamLargeCT` and `#TeamLargeT`), and CS2's screenshot playing
  a terrorist (`In_game_ui.webp`) has the terrorists on the right. The
  strings `left_side_alive`/`right_side_alive` are just positions.
  The reserve beside the ammo counts magazines for every gun whose
  `m_bReserveAmmoAsClips` is true in scripts/weapons.vdata (all but the Nova,
  XM1014 and Sawed-Off, which count shells): the screenshot's P90 reads 2.
- **Bomb status.** Once the bomb is planted, `BombPlanted` (an 80 px icon
  washed `#b80000`) and `BombPlantedLines` (rings that grow 1.0 to 1.4 times and
  fade) take the timer's place. They pulse faster as the bomb nears
  detonation: `BombPlantedPulse__Slow` 0.8 s, `__Medium` 0.5 s, `__Fast` 0.3 s
  per cycle. `BombDefused` (green `#45aa2e`) replaces them on a defuse. The
  string `"Time_Bomb_Planted" "Bomb planted"` exists (csgo_english.txt). That
  the clock stops being shown after the plant is **Inferred** from the icon
  sharing the clock's place (`#BombStatus`, `y: -23px`), and matches CS2
  (**From memory**).
- **Players alive:** a big number on each side (`{d:left_side_alive}` with a
  small "ALIVE" under it: `SFUI_PlayerCount_Alive_Left:f`), and a compact
  person-icon count (`PlayerCount`).
- **Avatars (`AvatarLargeSnippet`), one per player, the counter-terrorists
  on the left** (corrected 2026-09-25, above). Each has:
  - the player's colour (`cl_teammate_colors_show`, default 1; the five
    colours are `cl_teammate_color_1..5` = light blue 136,206,245 / green
    0,158,128 / yellow 241,228,65 / orange 230,128,42 / purple 189,44,150,
    convars.txt) and optionally a letter;
  - a health bar with the number;
  - **kill flags**: up to five small icons for kills this round, or one big
    icon with "x{count}" beyond five (`HTC__kills`), each popping in over 0.3 s;
  - a skull when dead, a bot icon, domination/nemesis icons;
  - a **C4 icon on the bomb carrier** (washed yellow 255,255,95) and a
    **defuse-kit icon** (washed light blue 119,221,255). **Inferred:** these
    show only on your own team's avatars, since enemies' equipment is hidden;
  - a speaking indicator;
  - an **equipment strip** (`snippet-equipment-info`): money, best weapon, up
    to six grenade icons, armour or armour-with-helmet, defuser, C4. In
    competitive it shows during the round's down time (`.ROUNDDOWNTIME`), when
    you are dead or spectating, or while the show-team-equipment key is held
    (`.SHOW-EQUIPINFO`), per GT
    `panorama/styles/hud/hudteamcounter-equipmentinfo.css` line 39. Player
    names under the avatars follow the same rule (hudteamcounter.css line 357).
  - `cl_teamcounter_playercount_instead_of_avatars` (default false) swaps the
    avatars for plain counts.
- **Post-round damage report on the avatars.** At round end, each enemy avatar
  you traded damage with shows "**{health_removed} in {num_hits}**" (damage
  you gave) and "{return_health_removed} in {return_num_hits}" (damage you
  took), from `prdr_health_removed`/`prdr_return_health_removed` in
  csgo_english.txt. Each line carries an icon for how the damage ended:
  `killtype_default/headshot/blast/burn/slash/shock`. The avatar gets a class
  `won` or `lost` for who dealt more. Avatars reveal one after another, 0.1 s
  apart (`delayDelta = 0.1` in hudteamcounter.js). A friendly-fire variant
  exists. The server sends it as `CCSUsrMsg_PostRoundDamageReport { other_xuid,
  given_kill_type, given_health_removed, given_num_hits, taken_kill_type,
  taken_health_removed, taken_num_hits }` (GT
  `Protobufs/cstrike15_usermessages.proto`).
- **Round history** is not on the team counter. It is on the scoreboard (A4).

## A3. Money readout (lower left)

From GT `panorama/layout/hud/hudmoney.xml`,
`panorama/scripts/hud/hudmoney.js` and `panorama/styles/hud/hudmoney.css`:

- The amount is drawn by a **rolling digit panel** (`DigitPanelFactory`) that
  rolls each digit to the new value. It is formatted by `"buymenu_money"
  "${d:r:money}"`, so "$" plus the number, sized for "$16000". The panel is
  fed by the event `UpdateHudMoney(amount, instant)`. The second argument skips
  the roll.
- A **buy-zone cart icon** (`buyzone.vsvg`, washed light green) and the use-key
  glyph appear next to the amount only while you are in a buy zone during buy
  time (`.money__in-buy-zone`).
- **No +/- line items in the classic HUD.** hudmoney.css defines green-add
  (`#8fff6f`), red-remove (`#fd3535`) and flash (`#d3e798`) animations, but
  only the `-survival` (Danger Zone) variants are wired. In competitive the
  amount just rolls. **Inferred** from the css.
- **The reasons are chat lines.** Each award is printed as a line of text
  (**From memory** that they appear in chat; the strings are in
  csgo_english.txt around lines 1996-2060). Per-player lines:
  `Player_Cash_Award_Killed_Enemy` " +$%s1 for neutralizing an enemy with the
  %s2", `_Bomb_Planted` " +$%s1 for planting the C4", `_Bomb_Defused`,
  `_Get_Killed` " +$%s1 for being eliminated", `_Kill_Teammate` " -$%s1
  penalty for killing a friendly", and the hostage ones. Team lines:
  `Team_Cash_Award_T_Win_Bomb` " +$%s1 team income for detonating bomb",
  `_Elim_Bomb` "...for eliminating the enemy team", `_Win_Time` "...for
  running down the clock", `_Win_Defuse_Bomb` "...for defusing the C4",
  `_Loser_Bonus` " +$%s1 team income for losing", `_Loser_Bonus_Neg`,
  `_Loser_Zero` " -$%s1 team income for dead players on losing team",
  `_Planted_Bomb_But_Defused` " +$%s1 team income for planting the bomb",
  `_Bonus_Shorthanded`, `Team_Cash_Award_no_income` " +$0 penalty for running
  out of time", `_no_income_suicide`, and `Team_Cash_Award_Dead_CTs:f` /
  `Dead_Terrorists:f` (per enemy killed, a Rush-style award). There are also
  notices such as `Cstrike_TitlesTXT_Not_Enough_Money_NextRound` "You have
  insufficient funds\n$%s1 that you just earned cannot be spent this round".
- The server can also send `CCSUsrMsg_AdjustMoney { amount }`
  (cstrike15_usermessages.proto).
- The scoreboard shows the loss bonus: `"Scoreboard_lossmoneybonus" "Loss
  Bonus"` and the tooltip "{team} will earn ${amount} with a round loss"
  (csgo_english.txt 51553, 51592).

## A4. Scoreboard (Tab)

From GT `panorama/layout/scoreboard.xml` (snippet
`snippet_scoreboard-classic__row--comp`, also used for premier and rush) and
GT `panorama/scripts/scoreboard.js`:

- **Row, left to right:** status (alive, dead or disconnected icon), ping,
  flair (medal), avatar, name, then **two stat sets the player cycles
  between**:
  - set 0: **Money, K, D, A, HS%**
  - set 1: **MVPs, utility damage, enemies flashed, K/D, ADR**
  - then **Damage** (total, always shown), then the report and commend buttons.
- The full stat list the script knows is `score, risc, mvps, kills, assists,
  deaths, damage, avgrisc, money, hsp, kdr, adr, utilitydamage,
  enemiesflashed, 3k, 4k, 5k, ping, knifekills, taserkills` and more
  (scoreboard.js line 131). `risc`/`avgrisc` are round impact scores (see A6).
- **Money is hidden for the other team.** The script hides the label when the
  server sends money as negative (scoreboard.js lines 984-1002). Enemies show
  every other stat. **Inferred:** the server sends -1 for players not on your
  team.
- **Round history timeline** (`id-sb-timeline__segments`). There is one column
  per round, marking the winner with an icon for how the round ended (`win`
  and the reason-specific images), and **casualty pips**: five per team per
  round, darkened for each player dead at round end (`players_alive_CT`,
  `players_alive_TERRORIST` per round). It also marks half time and overtime
  (scoreboard.js lines 1603-1745). The round-loss-bonus money is shown there
  too.
- Header strings: "Alive: {d:CT_alive}/{d:CT_total}" (csgo_english.txt 51657).
- `cl_radar_square_with_scoreboard` (default true) turns the radar square while
  the scoreboard is open (convars.txt).

## A5. Radar (top left)

From GT `panorama/layout/hud/hudradar.xml`,
`panorama/styles/hud/hudradar.css` and convars.txt:

- **Size:** a 300 px panel; the round radar is 250 px, the square one 290 px.
  The square form is used when spectating (`cl_radar_square_when_spectating`)
  and with the scoreboard open.
- **Behaviour convars (defaults):** `cl_radar_rotate true` (the map turns with
  your view), `cl_radar_always_centered true`, `cl_radar_scale 0.7`
  (0.25-1), `cl_radar_scale_alternate 1` (a toggled zoom),
  `cl_radar_scale_dynamic false`, `cl_radar_icon_scale_min 0.6`,
  `cl_hud_radar_scale 1` (0.8-1.3), `cl_hud_radar_background_alpha 0.627`,
  `cl_hud_radar_map_additive true`, `cl_radar_show_all_players_when_spectating
  true`, and `sv_disable_radar 0` (1 disables it, 2 disables it in warmup).
- **What is drawn:**
  - you, with a view frustum (`ViewFrustrum`);
  - teammates (`CTOnMap`/`TOnMap`) in their player colour with number or
    letter;
  - an arrow at the edge for someone off the radar (`CTOffMap`...);
  - above and below markers (`PI_Above`/`PI_Below`) for height;
  - a death X (`CTDeath`...);
  - a **"ghost"** (`CTGhost`/`EnemyGhost`, 9 x 15 px, 80 % opacity);
  - spotted **enemies** in red (`PI_Color_Enemy: #ff1919`);
  - speaking and ping markers;
  - the **bomb**: `DroppedBomb`, `PlantedBomb` with three pulse speeds, and
    above/below variants;
  - the dropped defuser;
  - **bomb site letters** `BombZoneA`/`BombZoneB`, and hostage zones.
  - Under the radar, `DashboardLabel`, which **Inferred / From memory** shows
    the name of the place you stand in (the nav mesh's place name).
- **Ghost = last known position (Inferred / From memory).** The ghost icon is
  where an enemy was last spotted, left behind once they drop out of sight.
- **How enemies get on it.** A player is shown to the enemy team when
  `EntitySpottedState_t { m_bSpotted, m_bSpottedByMask[2] }` is set (GT
  `DumpSource2/schemas/server/EntitySpottedState_t.h`). That is, when anyone
  on the team has sight of them. The server also sends
  `CCSUsrMsg_ProcessSpottedEntityUpdate` with position, yaw, `defuser`,
  `player_has_defuser` and `player_has_c4` (cstrike15_usermessages.proto).
  **From memory:** the dropped bomb is always shown to Ts. CTs see it only when
  someone spots it. The carrier is shown to CTs with the C4 mark only when
  spotted.
- **Your own sound radius.** `PlayerSound` is a circle around you, 1 px
  white at 25 % alpha, that flashes (`player-sound-max`, 0.5 s) at its
  largest. A web source explains it: "The circle around your position in CS2
  indicates how far the sounds that you're making (footsteps, shooting, …) can
  be heard on the map"
  (https://primagames.com/tips/what-is-the-circle-around-you-on-the-cs2-map-radar-answered ,
  search snippet). So the radar draws the hearing range of your own noise.
  Enemy sounds are not drawn.
- The repo already has dust2's overview image and scale (`MapOverview`, B3).

## A6. Round end: the win panel and MVP

From GT `panorama/layout/hud/hudwinpanel.xml`,
`panorama/scripts/hud/hudwinpanel.js`, mod.gameevents and csgo_english.txt:

- **Layout.**
  - **Top section:** a title `{s:winpanel-title}` between double-arrow
    graphics, with a glitch and white-flash effect.
  - Under the title, **one "fun fact" line** (`{s:winpanel-funfact}`).
  - A surrender line.
  - **MVP section:** a 3D render of the MVP's agent in an "mvp-banner" pose on
    a small map scene, their avatar, the **MVP reason**, their name, and their
    music kit's name and StatTrak count.
- **Title strings:** `SFUI_WinPanel_CT_Win` "Counter-Terrorists Win",
  `SFUI_WinPanel_T_Win` "Terrorists Win", `SFUI_WinPanel_Round_Draw` "Round
  Draw", `SFUI_WinPanel_Team_Win_Team` "{team} Wins The Round" (named teams),
  and `WinPanel_RoundWon`/`RoundLost` "ROUND WON"/"ROUND LOST".
  The **reason** lines also exist, for the centre-screen notice and the
  history:
  - `SFUI_Notice_Target_Bombed` "Target successfully bombed"
  - `_Bomb_Defused` "The bomb has been defused"
  - `_Target_Saved` "Target has been saved"
  - `_Terrorists_Win`/`_CTs_Win`
  - `_Round_Draw`
  - `_Terrorists_Surrender`

  The short forms are `winpanel_end_target_bombed` "Bomb detonated",
  `winpanel_end_bomb_defused` "Bomb defused", `winpanel_end_target_saved`
  "Bombing failed", `winpanel_end_terrorists__kill` "CTs eliminated",
  `winpanel_end_cts_win` "Terrorists eliminated" (csgo_english.txt 2084-2101).
- **The event** `cs_win_panel_round` carries `show_timer_defend`,
  `show_timer_attack`, `timer_time`, `final_event` ("define in
  cs_gamerules.h"), and `funfact_token`, `funfact_player`,
  `funfact_data1..3` (mod.gameevents). **The fun facts** are about 50 tokens
  (csgo_english.txt 2104-2175). Examples: "{player} drew first blood {n}
  seconds into the round", "had no kills, but did {n} damage", "killed {n}
  enemies with headshots", "took {n} damage... from the earth", "That round
  took only {n} seconds!", "Counter-Terrorists won without taking any
  casualties", and "No players were killed prior to the bomb being planted".
  How the server chooses among them is not in the files.
- **MVP reasons** (`round_mvp { userid, reason, value, musickitmvps, nomusic,
  musickitid }`). hudwinpanel.js maps `reason` to a string:

  | reason | string (Panorama_winpanel_...) | text |
  |---|---|---|
  | 1 | `mvp_award_kills` | "MVP" (most eliminations) |
  | 2 | `mvp_award_bombplant` | "MVP for planting the bomb" |
  | 3 | `mvp_award_bombdefuse` | "MVP for defusing the bomb" |
  | 4 | `mvp_award_rescue` | "MVP for extracting a hostage" |
  | 5 | `mvp_award_gungame` | "MVP" |
  | 7, 12 | `mvp_winner` | "MVP" |
  | 9 | `mvp_award_ace` | "MVP for an Ace Round" |
  | 10 | `mvp_award_inferno` | "MVP for dealing a significant amount of fire damage" |
  | 11 | `mvp_award_blast` | "MVP for dealing a significant amount of explosive damage" |
  | 13 | `mvp_award_bombplant_clutch` | "MVP for planting and defending the bomb" |
  | 14 | `mvp_award_bombdefuse_clutch` | "MVP for a clutch defuse" |
  | 15 | `mvp_award_kills_three` | "MVP for most kills (3k)" |
  | 16 | `mvp_award_kills_four` | "MVP for most kills (4k)" |

  The rule that picks the MVP is server C++. **From memory**, for the defusal
  cases: the defuser when the bomb is defused, the planter when it explodes,
  and otherwise the winning side's player with the most kills. The "clutch"
  and damage variants above suggest CS2 has refined this, but the rule is not
  in the files. `sv_nomvp` and `sv_nowinpanel` exist (convars.txt).
- **How long it shows.** From round end until the next round starts, which is
  `mp_round_restart_delay` = **7 s** by default (convars.txt; casual sets 10).
  The script shuts its listeners at `mp_round_restart_delay + mp_freezetime - 1`
  (hudwinpanel.js `_ShowRoundEndReport`).
- **Round Impact Score / win chance.** hudwinpanel.js still carries code for
  a win-probability graph (`RisCanvas`), and there is a
  `hudwinpanel_roundimpactscore.css`. The graph starts from
  `init_conditions.terrorist_odds` (with each side's equipment value), steps
  at each kill or objective with the new `terrorist_odds`, labels each step
  "▲12%"/"win"/"loss", and adds your damage given and taken per enemy. The
  data is `CCSUsrMsg_RoundEndReportData` (cstrike15_usermessages.proto). The
  strings "Your Team's Win Chance" and "Rnd Score" also exist. **But the
  current hudwinpanel.xml has no `RisCanvas`, `RisPlotContainer` or
  `DamageContainer`.** hud.xml blurs a `RoundImpactScoreMain` panel that is
  not in the files, and scoreboard.js still lists the `risc` stat. So the
  graph is **Disputed / probably retired** from the classic HUD. Spectators
  still have `SFUIHUD_Spectate_WinChance` "Win Chance". Not a first-build
  item.

## A7. Death panel and damage report

From GT `panorama/layout/hud/huddeathpanel.xml`,
`panorama/scripts/hud/huddeathpanel.js`, mod.gameevents and csgo_english.txt:

- **When you die**, the server sends `show_deathpanel { victim, killer,
  killer_controller, hits_taken, damage_taken, hits_given, damage_given }`,
  and `hide_deathpanel` at the next round. The panel shows:
  - **the killer's avatar with a health bar** (how much health the killer
    has left), their name, and a domination or revenge icon;
  - a description, e.g. `Panorama_DeathPanel_Killer1_KillerWeapon` "killed you
    with their {weapon}", "killed you with your own {weapon}", "killed you
    with {other}'s {weapon}". There is also `DeathPanel_KilledSelf` "YOU KILLED
    YOURSELF", "You burned to death", "You were killed by the C4 explosion",
    and "You were killed by your own grenade";
  - **"Damage taken: {n} in {k} hits"** and **"Damage given: {n} in {k}
    hits"** (`Panorama_DeathPanel_DamageTaken:f`/`DamageGiven:f`), each with
    a progress bar. These are the damage between you and your killer only;
  - the killer's weapon image;
  - keys for the killer replay ("[R] Killer Replay") and skip.
- The server can also send `CCSUsrMsg_SendLastKillerDamageToClient {
  num_hits_given, damage_given, num_hits_taken, damage_taken,
  actual_damage_given, actual_damage_taken }` (proto). This distinguishes
  damage dealt from damage that actually came off health.
- **The full per-enemy damage report** is the team-counter one in A2, shown at
  round end. **From memory,** the console also prints a "Damage Given to /
  Damage Taken from" list. That is not in these files.

## A8. Alerts, the 10-second warning, hint text

- **Centre alerts** (`CSGOHudAlerts`, a bar with glitch sides, above the
  health cluster; GT `panorama/layout/hud/hudalerts.xml`) carry:
  - "MATCH POINT", "FINAL ROUND", "LAST ROUND OF FIRST HALF" (events
    `round_announce_match_point`, `_final`, `_last_round_half`);
  - "WARMUP {time}", "WARMUP ENDING", "MATCH STARTING IN {n}...", "MATCH
    START", "MATCH PAUSED", timeouts (csgo_english.txt 44088-44101 and
    49484-49500);
  - the round-end lines above;
  - `Cstrike_TitlesTXT_Bomb_Planted` "The bomb has been planted\n%s1 seconds
    till detonation" and `_Bomb_Defused`. **Inferred:** CS2 shows the planted
    message there as well as playing the "bomb has been planted" voice line.
- **The 10-second warning.** The game event `round_time_warning` (no fields)
  is in GT `game/csgo/pak01_dir/resource/game.gameevents`. So are
  `cs_round_start_beep` and `cs_round_final_beep` (mod.gameevents), the
  freeze-time countdown's beeps. When the warning fires is not in the files.
  **From memory**, the round timer's last 10 s turn red.
- **Hint text** (`CSGOHudHintText`, low and high priority, with info and alert
  icons; GT `panorama/layout/hud/hudhinttext.xml`) shows messages like "You
  picked up the bomb", "C4 must be planted at a bomb site", "You must be
  standing on the ground to plant the C4", "Defusing WITHOUT a defuse kit", and
  "You have insufficient funds" (csgo_english.txt 43909-43917). It stays
  `hinttext_displaytime` = **4 s** (convars.txt). The server sends
  `CCSUsrMsg_HintText { message }`.
- The plant and defuse **progress bar** is `CSGOHudProgressBar` in the same
  bottom-centre float. Defuse strings: "Defuse Time:", "You are defusing the
  bomb without a kit." (csgo_english.txt 43503-43507).

## A9. Game events the round HUD needs that the repo's schema lacks

The repo's `reference/systems/contracts.md` schema has most round events.
CS2's files add these, which the HUD listens to (mod.gameevents,
game.gameevents):
- `cs_win_panel_round` (see A6)
- `show_deathpanel`/`hide_deathpanel` (A7)
- `round_time_warning`
- `cs_round_start_beep`, `cs_round_final_beep`
- `round_announce_match_point`, `_final`, `_last_round_half`,
  `_match_start`, `_warmup`
- `round_end`'s extra `legacy`, `player_count` and `nomusic`
- `round_mvp`'s `musickitmvps`, `nomusic` and `musickitid` (not needed)
- `player_avenged_teammate`, `bomb_beep`
- `enter_bombzone`/`exit_bombzone` (the radar and hint)

## A10. The buy menu's agent

Read 2026-09-25 from the installed game with Source 2 Viewer (`-d`), not
from GT; built in `src/economy/buy_menu_agent.gd`.

- **The panel.** `panorama/layout/buymenu.xml` puts a
  `MapPlayerPreviewPanel` under the whole menu, full screen (`.buymenu-agent`
  is 100 % by 100 %): `map="ui/buy_menu"`, `camera="cam_buymenu"`,
  `playername="vanity_character"`, `animgraphcharactermode="buy-menu"`,
  `game-background="true"` (the game drawn behind the agent) and
  `pin-fov="vertical"` (the camera's field of view spans the screen's
  height, whatever its shape). `.buymenu` itself is `rgba(0, 0, 0, 0.95)`.
- **The map** (`game/csgo/maps/ui/buy_menu.vpk`,
  `maps/ui/buy_menu/entities/default_ents.vents`). `cam_buymenu`, a
  `point_camera_vertical_fov`: at (-60, -136, 28), angles (0, 90, 0),
  vertical field of view 30, znear 4. The agent (`csgo_player_previewmodel`
  `vanity_character`): at (-27.14, 16.05, -22.30), yaw 255. One
  `light_environment`: brightness 2.3, colour 245 238 232, angles (54.18,
  87.80, -0.25), sky 211 226 248 at 0.96, bounce 151 151 151, baked
  (directlight 1: its light reaches the agent through the map's probes).
  An `env_cubemap_box` with `materials/fx/inspect_agents_custom_cubemap.vtex`.
  The menu's post-processing (`lighting/postprocessing/effects/in_buy_menu.vpost`)
  has no layers, and its colour table is the identity.
- **The poses** (`animation/graphs/ui/uimodel.vnmgraph`, its BuyMenu
  state). A CT and a T state machine, each item's state entered on
  `weapon_type`, the item's class (`kevlar_vest` and `kevlar_and_helmet`
  share the armour's, `weapon_defuse_kit` is the kit, the knife state takes
  every knife but `weapon_knife_push`), every transition 0 s. Each state
  plays one single-frame clip from `animation/anims/ui_anims/buy_menu/`
  (`ct/`, `t/`, `shared/` for the grenades, armour, kit, knife and bomb).
  The CT's M4A4 state plays `ct_buymenu_m4a1`, the M4A1-S's
  (`ct_buymenu_m4a4` is in the files, unused). Over every pose the state adds
  `ui_anims/additive_anims/t/t_idle_layer01`, a 7.1 s breath, for both
  sides, and a Snap Weapon node puts the item in the hand. The table is
  `BuyMenuAgent.POSES`.
- **The item's own bones.** The clips carry the item's rig too, rooted at
  the scene's origin. A single-handed item's root snaps to the hand's `wpn`
  bone. In the two-handed items' poses (the Molotov and its lighter, the
  Shadow Daggers) `wpn` sits at the origin in the root's own frame, and the
  item's `weapon_hand_r` and `_l` land on the body's hands to the
  millimetre. Some clips move the item's parts: the Dual Berettas one to
  each hand and their holster (`eholster`, which the model calls
  `elite_holster`) out of sight, the R8's loader aside, the XM1014's loaded
  shells scaled to nothing, the bomb's offset in the hand.
- **Measured** on Sid's screenshots of the menu (2026-09-25, 2000 by 1125,
  scaled to 1920 by 1080): the agent's head top 182 down and the AK-47's
  muzzle 1752 across, where the map's camera puts them; the world behind
  lightly blurred (a sign's letters still read), nothing in it darker than
  about 30 or brighter than about 68 of 255.

---

# Part B. How CS2's bots play a round

## B1. Two bot brains in CS2

- **Competitive, casual and wingman** use the classic **CCSBot**, the bot
  Michael Booth and Turtle Rock wrote for Condition Zero and Source.
  botprofile.db and botchatter.db still carry the header "Author: Michael S.
  Booth, Turtle Rock Studios" (GT `game/csgo/pak01_dir/botprofile.db`, GT
  `game/csgo/pak01_dir/botchatter.db`). Its state is laid out in GT
  `DumpSource2/schemas/server/CCSBot.h` and `CBot.h`.
- **Deathmatch, arms race, rush and the new-player training** run a
  **behaviour tree** named by `mp_bot_ai_bt` ("Use the specified behavior tree
  file to drive the bot behavior", convars.txt). The cfgs set it:
  - `gamemode_deathmatch.cfg` and `gamemode_dm_freeforall.cfg`:
    `scripts/ai/deathmatch/bt_default.kv3`
  - `gamemode_armsrace.cfg`: `armsrace/...`
  - `gamemode_rush.cfg`: `rush/...`
  - `gamemode_new_user_training.cfg`: `scripts/ai/practice/newplayer_dust2_01.kv3`
    ("Dust II Only")

  All are in GT `game/csgo/cfg/`. `gamemode_competitive.cfg` and
  `gamemode_casual.cfg` set no tree. **Inferred:** the classic bot is what plays
  a competitive round. The trees are text files in GT
  `game/csgo/pak01_dir/scripts/ai/` and are a direct, readable model of how
  Valve now builds bot behaviour (B8).

## B2. Profiles: what each field means

GT `game/csgo/pak01_dir/botprofile.db`. A profile inherits from `Default`,
then from each template named before its name, in order. Its own lines then
override. The comments in quotes below are the file's own.

| Field | Default | Meaning |
|---|---|---|
| `Skill` | 50 | 0-100 overall skill. **From memory**: it scales the bot's decision quality, e.g. how well it chooses to hold or push and whether it uses grenades well. `bot_prefix` can show it ("<skill> will be replaced with a 0-100 representation of the bot's skill", convars.txt). |
| `Aggression` | 50 | 0-100. **From memory**: it decides how often it rushes and hunts rather than holding or hiding, and whether it pushes after a kill. |
| `ReactionTime` | 0.3 | Seconds between an enemy becoming visible and the bot "seeing" it. CCSBot keeps a queue of sightings with timestamps (`m_enemyQueueIndex`, `m_enemyQueueCount`, `m_enemyQueueAttendIndex`, `m_lastValidReactionQueueFrame`). **Inferred:** the bot acts on what it saw ReactionTime ago. |
| `AttackDelay` | 0 | Extra seconds after reacting before it opens fire (Tough 0.7, Normal 0.8, Fair 0.9, Easy 0.7). |
| `Teamwork` | 75 | 0-100. **From memory**: how readily it follows radio orders and teammates. No template changes it. |
| `AimFocusInitial` | 20 | "initial focus spread in degrees (from desired center)" |
| `AimFocusDecay` | 0.7 | "how much focus shrinks per second (.25 = 25% of size after 1 sec)" |
| `AimFocusOffsetScale` | 0.30 | "controls accuracy when tracking to target (0 == perfect, should always be < 1)" |
| `AimfocusInterval` | 0.8 | "how often focus is adjusted (smaller intervals means better movement tracking)" |
| `WeaponPreference` | none | An ordered list of weapons it tries to buy |
| `Cost` | 0 | Its "cost" in the old CZ career mode's team budget; Elite and Expert 4, the AWP Expert "Operator" 5. Not used in a normal match (**From memory**). |
| `Difficulty` | NORMAL | Which `bot_difficulty` tier the profile belongs to (EASY, NORMAL, HARD, EXPERT) |
| `VoicePitch`, `Skin` | 100, 0 | Chatter pitch and model variant |
| `LookAngleMaxAccelNormal`/`StiffnessNormal`/`DampingNormal` | 2000 / 100 / 25 | The bot's view turns like a damped spring: acceleration capped, a spring toward the goal angle, damping (`m_lookYaw`, `m_lookYawVel`, `m_lookPitch`, `m_lookPitchVel` in CCSBot.h) |
| `...Attacking` versions | 3000 / 150 / 30 | A stiffer, faster spring while attacking |

**How the aim fields combine (Inferred** from the comments and from CCSBot's
`m_aimFocus`, `m_aimFocusInterval`, `m_aimFocusNextUpdate`, `m_aimError`,
`m_aimGoal`, `m_targetSpot`, `m_targetSpotVelocity`,
`m_targetSpotPredicted`**).**
1. On acquiring a target, the aim "focus" starts at `AimFocusInitial` degrees.
2. The focus shrinks by the factor `AimFocusDecay` per second.
3. Every `AimfocusInterval` seconds the bot picks a new random aim error
   within the focus. It also adds a tracking error, the target's angular motion
   times `AimFocusOffsetScale`.
4. The spring turns the view toward aim goal plus error.

So a low interval and a fast decay mean quick, tight aim that tracks
movement. This maps cleanly onto the project's two honest knobs, reaction
time and aim error (roadmap item 23).

**The skill templates:**

| Template | Skill | Aggr. | Reaction s | AttackDelay s | AimFocusInitial ° | Decay | OffsetScale | Interval s | Difficulty | Profiles |
|---|---|---|---|---|---|---|---|---|---|---|
| Easy | 5 | 10 | 0.60 | 0.70 | 20 | 0.7 | 0.6 | 0.70 | EASY | 38 |
| Fair | 25 | 15 | 0.60 | 0.90 | 17 | 0.6 | 0.5 | 0.70 | NORMAL | 24 |
| Normal | 50 | 30 | 0.60 | 0.80 | 12 | 0.5 | 0.35 | 0.60 | NORMAL | 23 |
| Tough | 60 | 45 | 0.50 | 0.70 | 10 | 0.4 | 0.25 | 0.50 | HARD | 21 |
| Hard | 75 | 60 | 0.40 | 0 | 10 | 0.4 | 0.20 | 0.40 | HARD | 15 |
| VeryHard | 80 | 70 | 0.30 | 0 | 5 | 0.3 | 0.17 | 0.30 | HARD | 4 |
| Expert | 90 | 80 | 0.20 | 0 | 2 | 0.2 | 0.15 | 0.20 | EXPERT | 10 |
| Elite | 100 | 95 | 0.05 | 0 | 0.5 | 0.1 | 0.05 | 0.05 | EXPERT | 12 |

That is 147 named profiles in all: EASY 38, NORMAL 47, HARD 40, EXPERT 22.
Names map to tiers only through the template each is declared with. For
example, `Elite+Rifle Muhlik`, `Expert+Sniper Operator` and `Easy Yuri`. When a
bot is added at `bot_difficulty` N, the game picks a profile whose
`Difficulty` matches (**From memory**).

**Weapon templates** (WeaponPreference, in order of preference):
- `Rifle`: m4a1, ak47, famas, galilar, mp7
- `RifleT`: ak47, m4a1, galilar, famas, mp7
- `Punch`/`PunchT`: aug, sg556, famas, galilar, mp7
- `Sniper`: awp, scar20, g3sg1, ssg08, famas, galilar, mp7
- `Power`: m249, xm1014, nova, famas, galilar, mp7
- `Shotgun`: xm1014, nova, famas, galilar, mp7
- `Spray`: p90, mp9, mac10, mp7

Of the profiles: Rifle 25, RifleT 12, Sniper 8, PunchT 6, Spray 5, Punch 4,
Shotgun 4, Power 2. The rest have no preference. **Inferred:** a bot walks
its list and buys the first weapon its side can buy and it can afford.
Team-only weapons are skipped, so a CT "Rifle" buys the m4a1 and a T one the
ak47.

**Difficulty convars** (convars.txt, GT `game/csgo/cfg/gamemode_*.cfg`):
- `bot_difficulty` "0=easy, 1=normal, 2=hard, 3=expert". Competitive and
  deathmatch set 2, casual 1.
- `custom_bot_difficulty 2` "Bot difficulty for offline play".
- `sv_auto_adjust_bot_difficulty true` "Adjust the difficulty of bots each
  round based on contribution score". It works with
  `bot_autodifficulty_threshold_high/low`, "bound above/below Average Human
  Contribution Score" (the mode cfgs set 0.0 and -2.0).
- `sv_bots_get_easier_each_win 0`.

**The behaviour-tree bots use a second, richer difficulty table:** GT
`game/csgo/pak01_dir/scripts/ai/deathmatch/bt_config.kv3`, with tiers `low`,
`fair`, `normal`, `tough`, `hard`, `very_hard`, `expert` and `elite`. Examples:

| Tier | reaction_time s | aim_target_acquisition_lerp_time s | tracking focus interval s | aim_punch_angle_reaction_chance | combat_crouch_chance | rifle burst s (duration / cooldown) |
|---|---|---|---|---|---|---|
| low | 0.5 | 0.5 | 0.35 | 0.35 | 0 | 0.95 / 0.75 |
| normal | 0.4 | 0.4 | 0.275 | 0.55 | 0.1 | 0.22 / 0.45 |
| hard | 0.3 | 0.35 | 0.2 | 0.65 | 0.22 | 0.225 / 0.25 |
| expert | 0.2 | 0.25 | 0.15 | 0.75 | 0.33 | 0.225 / 0.15 |
| elite | 0.12 | 0.15 | 0.06 | 0.95 | 0.33 | 0.155 / 0.15 |

Each tier also sets:
- an **acquisition angle penalty** (5-7° plus or minus 1.5-2, which shrinks
  as it lines up);
- `aim_ready_angle_tolerance 3°` (it fires only once within 3°);
- `aim_new_target_angle_tolerance 30°`;
- `look_around_awareness_yaw_range` 50-60° and pitch range 10-20°;
- a combat dodge ("strafe") command duration of about 1 s;
- a per-weapon-class **burst table** of duration, deviation, cadence (pistol
  tap spacing), cooldown and cooldown deviation. For example, a normal bot's
  rifle fires 0.22 s bursts with 0.45 s pauses, and its pistol taps every 0.5 s.

This is the cleanest set of numbers to copy for bot aim and firing, even
though it drives the deathmatch bots and not the classic ones.

## B3. Buying and saving

From convars.txt:
- `bot_eco_limit 2000`: "If nonzero, bots will not buy if their money falls
  below this amount."
- `sv_bot_buy_grenade_chance 33`: "Chance bots will buy a grenade with
  leftover money (after prim, sec and armor)". The type is weighted by
  `sv_bot_buy_hegrenade_weight 6`, `_flash_weight 1`, `_smoke_weight 1`,
  `_molotov_weight 1` and `_decoy_weight 1`. So an HE is 6 times as likely as
  each other kind, a 60 % share.
- `bot_allow_pistols`, `_shotguns`, `_sub_machine_guns`, `_rifles`,
  `_machine_guns`, `_snipers` and `_grenades` (all true) filter what bots may
  use.
- `bot_randombuy` (cheat) ignores preferences.
- `bot_loadout` (cheat) gives items at round start.

So the stock buy order is: **primary** (by WeaponPreference), **secondary**,
**armour**, then with the leftover money a **33 % chance of one grenade**
(weighted as above). That order is stated in the convar's own description.
**From memory,** CTs also buy a defuse kit when they can afford it, and bots
pick up better weapons from the ground (`m_lookForWeaponsOnGroundTimer` in
CCSBot.h).

**Saving:** the only saving rule in the files is the flat $2000 `bot_eco_limit`.
The classic bot has no team-wide economy plan; a community plugin lists
"Bots consider their money as a team and will often eco-rush together" as
something it *adds* (https://github.com/Fujinrock/CSS-BotBehaviors README).
The behaviour trees have a `decorator_buy_service` and an `action_buy` with
nothing configurable in the tree. Buying 3 s into the round is from
deathmatch/bt_default.kv3's `action_wait` of 3 s before `action_buy`.
**Inferred:** a team economy plan (full buy, force, eco, save; the repo's own
item 24) goes beyond CS2's bots, which is in line with CLAUDE.md's "CS2 is the
starting point, not the limit".

## B4. How the classic bot plays a round

What the files show directly:
- **Nav mesh analysis.** The repo's N3 already lists the analysis blocks in
  dust2's `.nav`: hiding spots (pos, flags), spot encounters (from, fromdir,
  todir, order), approach areas, and earliest occupy time per team. The
  convars confirm what they are for:
  - `bot_show_occupy_time`: "Show when each nav area can first be reached by
    each team."
  - `bot_show_battlefront`: "Show areas where rushing players will initially
    meet."
  - `bot_path_require_reachable_goal`: "bots refuse to path to a nav area that
    the nav build did not reach from a player spawn."
  - `bot_defense_rush_chance 33` (cheat): "Are the defense bots going to rush."
- **CCSBot.h's fields.** They name the behaviours the bot has:

| Fields | What they reveal |
|---|---|
| `m_isRogue`, `m_rogueTimer`; `bot_allow_rogues` "Rogue bots do not obey radio commands, nor pursue scenario goals" | Some bots sometimes go it alone for a while. |
| `m_safeTime`, `m_wasSafe` | **Inferred**: a per-round "safe time", the time before any enemy could arrive, from the earliest occupy times. Before it the bot moves fast and does not check corners. |
| `m_hurryTimer`, `m_alertTimer`, `m_sneakTimer`, `m_panicTimer`, `m_mustRunTimer`, `m_waitTimer` | Moods that change how it moves (run, walk quietly, wait). |
| `m_isFollowing`, `m_leader`, `m_followTimestamp`, `m_allowAutoFollowTime`; `bot_auto_follow` "bots with high co-op may automatically follow a nearby human player" | Following a human. |
| `m_taskEntity`, `m_goalPosition`, `m_goalEntity` | Its current task and goal (a site, the bomb, a spot). |
| `m_hasVisitedEnemySpawn` | The hunt state heads to the enemy spawn (**Inferred**; the Fujinrock README says stock bots hunt toward "enemy spawns or the least recently checked areas"). |
| `m_noisePosition`, `m_noiseTravelDistance`, `m_noiseTimestamp`, `m_noiseSource`, `m_noiseBendTimer`, `m_bentNoisePosition` | **The hearing model**: it remembers the last noise heard, its path distance, when and who. It "bends" the noise's position to where along the mesh it would be heard coming from. It investigates it. |
| `m_lookAroundStateTimestamp`, `m_lookAheadAngle`, `m_lookAtSpot*`, `m_peripheralTimestamp`, `m_approachPointCount`, `m_approachPointViewPosition`, `m_spotCheckTimestamp`, `m_checkedHidingSpotCount`, `m_viewSteadyTimer` | **Where it looks**: while moving it looks at encounter spots along its path, at approach points when holding, glances at the periphery, and counts hiding spots it has checked. |
| `m_enemy`, `m_isEnemyVisible`, `m_visibleEnemyParts`, `m_lastEnemyPosition`, `m_firstSawEnemyTimestamp`, `m_lastSawEnemyTimestamp`, `m_currentEnemyAcquireTimestamp`, `m_nearbyEnemyCount`, `m_bomber` | **Sight**: which body parts of the enemy it can see (a bitmask), when it first and last saw them, where it last saw them, how many enemies are near, and who carries the bomb. |
| `m_isEnemySniperVisible`, `m_sawEnemySniperTimer` | It treats AWPers specially (chatter "SniperWarning"). |
| `m_attacker`, `m_attackedTimestamp`, `m_surpriseTimer` | It reacts to being shot, including from behind (a surprise). |
| `m_blindFire` | It fires blind when flashed (**Inferred**). |
| `m_tossGrenadeTimer`, `m_isAvoidingGrenade`, `m_burnedByFlamesTimer` | It throws grenades, dodges incoming ones and flees fire. |
| `m_isRapidFiring`, `m_zoomTimer`, `m_equipTimer`, `m_fireWeaponTimestamp`, `m_combatRange` | Firing cadence, scoping, weapon switch timing, preferred fighting range. |
| `m_avoidFriendTimer`, `m_isFriendInTheWay`, `m_politeTimer`, `m_isWaitingBehindFriend` | It waits politely behind teammates in corridors. |
| `m_isStuck`, `m_stuckSpot`, `m_wiggleTimer`, `m_stuckJumpTimer`, `m_avgVel[10]` | Getting unstuck: it notices from its average speed, wiggles, then jumps. |
| `m_playerTravelDistance[64]`, `m_updateTravelDistanceTimer` | It keeps the path distance to every player, updated in phases. |
| `m_lastRadioRecievedTimestamp`, `m_lastRadioSentTimestamp`, `m_radioSubject`, `m_radioPosition`, `m_voiceEndTimestamp` | Radio orders in and out. |
| `m_diedLastRound`, `m_friendDeathTimestamp`, `m_enemyDeathTimestamp`, `m_isLastEnemyDead` | Round memory used in decisions and chatter. |
| `m_isOpeningDoor`, `m_pathLadderEnd`, `m_repathTimer` | Doors, ladders, re-planning its path. |

- **Chatter concepts** (GT `game/csgo/pak01_dir/botchatter.db`). They list
  the bomb-mode behaviours the bot reports:
  - GoingToPlantBomb, PlantingBomb, PlantedBombPlace
  - SpottedBomber, SpottedLooseBomb, TheyPickedUpTheBomb
  - **GoingToGuardLooseBomb / GuardingLooseBomb** (CTs camp a dropped bomb)
  - GoingToDefendBombsite, DefendingBombsite, BombsiteClear, BombsiteSecure
  - DefusingBomb, **WaitingForHumanToDefuseBomb** (and its Panic version),
    BarelyDefused, BombTickingDown
  - WhereIsTheBomb, HeardNoise, Blinded, PinnedDown, CoverMe, OnMyWay,
    WaitingHere, NoEnemiesLeft, OneEnemyLeft (and Two, Three), SniperWarning,
    LastManStanding

  Each maps to a standard radio event when chatter is set to radio only.
  **Places** are the map's place names (103 in the file). They are used as "Bridge"
  ... "There's the bomber" ... "Need help!" (the file's own example). In CS2
  the wav entries are `null.wav` and `bot_chatter_use_rr true` ("1 = Use
  response rules") routes speech through the response-rules system.
  `bot_chatter` is off, radio, minimal ("Important" phrases only) or normal.
- **Scenario etiquette:** `bot_defer_to_human_goals` ("If nonzero and there is
  a human on the team, the bots will not do the scenario tasks"; competitive
  sets 1, casual 0), `bot_defer_to_human_items` (1: bots will not take
  scenario items such as the bomb when a human is on the team), and the
  "[E] Take Bomb" prompt on a bot carrying it (`SFUIHUD_botid_request_bomb`).

**The round, as the classic bot plays it (From memory** of the CS:S/CS:GO bot,
consistent with every field and phrase above; Booth's slides could not be
opened to cite**):**
- It runs a **state machine**: Idle, Buy, MoveTo, Hunt, Attack,
  InvestigateNoise, Hide, FetchBomb, PlantBomb, DefuseBomb, EscapeFromBomb,
  Follow, UseEntity, OpenDoor.
- **Buy** in freeze time, then Idle picks a task by side and scenario.
- **T carrier:** picks a site and MoveTo it, then PlantBomb. Other Ts escort,
  or Hunt (Aggression), or Hide near the chosen site.
- **Bomb dropped:** a T goes to fetch it. CTs who see it guard it.
- **CTs:** each either rushes (`bot_defense_rush_chance`, 33 %) or goes to
  **defend a site**, where it takes a **hiding spot** facing the site's
  **approach areas**. Snipers prefer spots flagged as sniper spots.
- **After a plant:** CTs head for the bomb and defuse. A CT that knows it
  cannot defuse in time runs away (EscapeFromBomb). Ts guard the planted bomb
  from hiding spots around it.
- **On the move:** a bot looks at the **encounter spots** its path passes (the
  places an enemy could first appear), unless before its safe time.
- **Hearing:** footsteps and gunfire within earshot become a noise it may
  investigate.
- **Seeing an enemy:** after ReactionTime, it Attacks, strafing and crouching
  by skill.
- **After a kill or when lost:** it hunts.
- **Late in the round:** bots hurry (`m_hurryTimer`).

## B5. Vision, smoke and flashes

- **Distance:** `bot_max_vision_distance_override -1` means no override of the
  map's vision distance ("Max distance bots can see targets", convars.txt).
  `bot_coop_idle_max_vision_distance 1400` applies to co-op.
- **Field of view:** the classic bot's FOV is not in the files. The tree's
  vision sensor is `sensor_shape_fov`, looking at enemies within **1500
  units** (`decorator_picker_nearby cutoff_distance = 1500`) and requiring
  `decorator_picker_visible`, then the reaction delay. That comes from GT
  `game/csgo/pak01_dir/scripts/ai/modules/bt_memorize_enemies_vision.kv3`.
  **From memory** the classic bot's FOV is about 90° either side, with a
  peripheral check (`m_peripheralTimestamp`). Measure it before relying on it.
- **Smoke:** `bot_max_visible_smoke_length 200` (replicated, release): "Bots
  will see players through smoke clouds up to this length." A bot's line of
  sight is blocked only once it passes through more than **200 units** of
  smoke. Thin edges do not block it. That fits the repo's voxel smoke: sum the
  length of the line of sight inside smoke voxels and compare with 200. The
  practice tree also has `bt_attack_damage_inflictor_smoke.kv3`: shoot back
  into the smoke you were hit from.
- **Flashes:** the classic bot has `m_blindFire` and the "Blinded" chatter.
  **From memory** a flashed bot cannot see, may fire at the last known enemy
  position, and moves aimlessly or backs off until it recovers. The repo's
  flash code should give bots the same blind time as players (`player_blind`
  carries `blind_duration`).
- **Molotovs and HEs:** the tree modules `bt_memorize_area_damage_grenades`,
  `_infernos` and `_current` plus `bt_flee_area_damage_threats` show the newer
  bots remember incoming grenades and burning areas and move out. The classic
  bot has `m_isAvoidingGrenade` and `m_burnedByFlamesTimer` to the same end.

## B6. Grenade use

- Buying: B3.
- Throwing: the classic bot has `m_tossGrenadeTimer` and `bot_allow_grenades`.
  **From memory** it throws HE and flashes at an enemy's last known position,
  or where it expects the enemy to come from, and rarely uses smokes well. It
  has no lineups. Throws such as smokes for a site execute are not in stock
  bots. The community's "Bot Improver" lists "Situational Smoke, Flashbang,
  HE grenade, and Molotov throwing" as its addition
  (https://github.com/ed0ard/CS2-Bot-Improver README). The repo's plan of a
  table of known dust2 lineups (N2) therefore goes beyond stock CS2.

## B7. Hearing in numbers

The tree's hearing (GT `scripts/ai/modules/bt_memorize_noises.kv3`):
- a sensor sphere of **3000 units** for `NOISE` entities;
- noises weighted by distance, picked at random between **800 and 3000
  units** (`decorator_picker_random_by_distance`);
- de-duplicated against memory within 100 units;
- delayed by the reaction time;
- then stored in long-term memory.

Memory lifetimes (deathmatch/bt_default.kv3): **ShortTermAttackMemory 0.7 s**,
**LongTermMemory 10 s / 500 units**, **ShortTermInvestigateMemory 3 s / 200
units**. The priority order the tree runs every tick is:
1. buy;
2. face whoever damaged it;
3. attack a remembered visible enemy (nearest first; switch to the best weapon;
   rush with the knife; otherwise combat positioning; aim; fire when aim-ready);
4. heal;
5. investigate the nearest remembered event;
6. look around or hunt.

**Inferred:** the 800 figure means sounds closer than 800 units are always
picked up. Beyond it, the chance falls with distance up to 3000.

## B8. The dust2 training tree: a model for "playing the round"

GT `game/csgo/pak01_dir/scripts/ai/practice/newplayer_dust2_01.kv3` and its
modules are Valve's own scripted dust2 round for new players:
- Each bot takes a **slot** (`t_1`...`t_5`, `ct_1`...`ct_5`, via a
  `decorator_token_service`). A random strategy number picks its route.
- Routes are **lists of world positions** walked with `action_move_to`
  (`BT_ACTION_MOVETO_RUN`, `FASTEST_ROUTE`, `auto_look_adjust = 1`). For
  example, `bt_goto_a_via_cat_from_t.kv3` is four points from T spawn through
  mid to catwalk to A. Routes often start with a 4.5-5.5 s wait
  (`bt_wait.kv3`).
- Named routes: `goto_a_bombsite_via_long_doors_from_t`,
  `goto_a_via_cat_from_t`, `goto_b_site_from_t`, `goto_mid_b`, `goto_a_car`,
  `goto_a_corner`, `goto_b_car_from_ct`, `goto_b_site_from_ct`.
- Separate modules: `bt_plant_bomb_if_covered`, `bt_plant_bomb_if_owned`,
  `bt_pickup_bomb_if_nearby`, `bt_defuse_bomb_if_nearby`,
  `bt_clear_threats_within_fov`, and a `decorator_hiding_spot_service`.
- `bt_plant_bomb_if_covered` is the carrier's rule: when engaged while
  carrying C4 and at least **2 teammates** are engaging the same enemies
  (`decorator_tag_threshold amount = 2`), choose a site at random (index 0-1),
  pick a random waypoint in it, and go plant.

**Inferred:** this is close to what roadmap item 24 needs. It amounts to fixed
per-slot routes on dust2 with timed waits, sites chosen by a random strategy,
and small reactive modules layered on top. The dust2 coordinates in these
files are in the same world units the repo already uses and can be read as a
starting route table.

## B9. What changed for bots in CS2 (2023-2026)

Release notes could not be opened (counter-strike.net and Steam were blocked).
Search snippets gave only this:
- "June 16, 2024: fixed rare cases where the bots would suddenly stop moving
  whilst in rush mode" (snippet from a search over CS2 patch-note aggregators).
- "In October 2025 ... dead or idle bots now getting replaced first to make
  room for players" (https://hellagood.marketing/blog/cs2-update/ , snippet).
- The same snippet source claims bots since 2024 "are now less predictable,
  they will flank ... no longer have short-sightedness and can see far away
  enemies, and they react instantly when holding grenades". This comes from a
  marketing blog and is unverified: **Disputed / weak**.

The files show what exists now: behaviour-tree bots for deathmatch, arms race,
rush and the dust2 training; `sv_bot_buy_*` grenade weights;
`sv_auto_adjust_bot_difficulty`; response-rules chatter; and a behaviour-tree
debug draw (`cv_bot_ai_bt_debug_target`, `cv_bot_ai_bt_hiding_spot_show`,
`cv_bot_ai_bt_moveto_show_next_hiding_spot`). The dated changelog is a
**Local** task. Sid can read counter-strike.net/news/updates, or Steam's news
for app 730, and grep for "bot".

---

# What this means for the project

- **Firm, copy as is (from CS2's files):**
  - the kill feed's order and icons;
  - its 5 s life (times 1.5 when you are in it) and 1 s fade;
  - its CT/T colours `#6f9ce6`/`#eabe54`;
  - the red border when you are the killer and red background when you are
    the victim;
  - the scoreboard's two stat sets plus Damage, with enemy money hidden;
  - the post-round damage report "N in K hits" per enemy;
  - the death panel's damage given and taken to your killer;
  - the MVP reason table;
  - the win panel lasting `mp_round_restart_delay` (7 s);
  - hint text lasting 4 s.

  All of it is in A1 to A8 with paths.
- **Round HUD, build first:**
  1. the team counter: timer, scores, alive counts, and the bomb icon replacing
     the clock with its three pulse speeds;
  2. the kill feed, fed by the repo's `player_death` event, which already has
     every key CS2 uses;
  3. the money readout, rolling, with the buy-zone icon;
  4. the round-end title with its reason line.

  Then the scoreboard, the radar dots (teammates always; enemies only while
  `spotted`), the win panel with the MVP, and last the damage reports and
  death panel.
- **Update `reference/cs2-systems.md` section 9.** Its layout is CS2's launch
  HUD. Today's files put health, armour and ammo in one bottom-centre cluster
  with per-round kill flags and a bomb-damage preview, and money in the lower
  left. Sid should say which layout to follow. A playtest screenshot on his
  machine settles it.
- **Add the HUD's missing events to the `GameEvents` schema** (A9):
  `cs_win_panel_round` (fun fact is optional), `show_deathpanel` with hit and
  damage totals, `round_time_warning`, `round_announce_*`, and a per-round,
  per-pair damage tally on the world, from which the post-round report and
  death panel read. That tally is server state, kept on the tick.
- **Radar spotting is server state.** Keep CS2's `m_bSpotted` plus a per-team
  spotted-by mask on each player, set on the tick from the same sight checks
  bots use. The radar only reads it. Add the "own noise" circle once footstep
  ranges exist.
- **Bots, firm numbers to start from:**
  - botprofile.db's eight skill tiers (reaction, attack delay, aim focus
    initial, decay, offset and interval; look-spring stiffness and damping)
    map directly onto the repo's two knobs;
  - bt_config.kv3's per-tier burst tables and acquisition times give firing
    cadence per weapon class;
  - smoke blocks a bot's sight past **200 units** of smoke along the line;
  - hearing is **3000 units**, with memories lasting 0.7 s, 10 s and 3 s.
- **Bots, build first for item 24:**
  1. per-slot scripted routes on dust2, in the style of Valve's
     newplayer_dust2_01 tree, with its coordinates as a seed;
  2. the carrier plants at a randomly chosen site;
  3. CTs hold hiding spots facing approach areas;
  4. after a plant, CTs go defuse (or leave if too late) and Ts guard;
  5. buy by preference list, then armour, then 33 % one grenade (HE-weighted),
     and save below $2000.

  Reading the nav analysis (N3, Local) upgrades steps 3 and 4 from
  hand-placed spots to CS2's own.
- **Beyond stock CS2, as options:** a team economy plan (eco, force, full), and
  known grenade lineups. Stock bots have neither. They would be CLAUDE.md's
  "measured improvement", so propose them as such.
- **Still unknown, measure Local:**
  - how many kill-feed entries show;
  - when the timer turns red;
  - how the MVP is chosen in edge cases;
  - which fun fact is picked;
  - the classic bot's FOV;
  - the dated list of CS2 bot changes (release notes blocked here).
