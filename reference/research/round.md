# How CS2 runs a round: research

Sid, 2026-09-24: "spin up a couple agents to do some research on how all
these systems work in the actual game." This covers the round: money and
buying, the bomb, grenades, dropping and picking up, round flow and its game
events, the round HUD, and how CS2's bots play a round. Guns, the knife, the
Zeus, being hit and hit registration online are in a separate piece of
research.

This page gives the findings that change what the project builds, and the
verdict on every guess the repo carries. The detail, with a source for every
claim, is in three files:

| File | Covers |
|---|---|
| `round-economy.md` | every `cash_` convar, the loss ladder, kills, suicides, planting, the short-handed bonus, half time and overtime; buying, refunds, the menu; round phases and timers, round-end reasons, MVP; CS2's game events against `reference/systems/contracts.md` |
| `round-bomb-grenades.md` | the bomb (plant, timer and beeps, defuse, the July 2026 blast and its baked file, carrying and dropping); every grenade convar and each grenade; what drops on death and how pickups work |
| `round-hud-bots.md` | the HUD element by element (kill feed, team counter, money, scoreboard, radar, win panel and MVP, death panel, alerts); bots: the two bot brains, profiles, buying, how the classic bot plays a round, sight, smoke, hearing, Valve's dust2 training tree |

None of this changes code. The systems' own pages (`reference/systems/`,
`reference/cs2-systems.md`) are left as they are; whoever next works on a
system takes the verdicts below into its page and code.

## Sources, and how far to trust them

- **GT** is SteamDatabase's GameTracking-CS2, dumps of CS2's own files, at
  commit `d45f52d` (2026-09-23):
  `https://github.com/SteamDatabase/GameTracking-CS2/blob/master/<path>`.
  Most settled answers come from here: `DumpSource2/convars.txt`, the
  `gamemode_competitive*.cfg` files, the entity schemas under
  `DumpSource2/schemas/`, the `.gameevents` files, the HUD's Panorama
  layouts, styles and scripts, `csgo_english.txt`, `botprofile.db`, the bot
  behaviour trees, and the strings compiled into `server.dll` and
  `client.dll` (`game/csgo/bin/win64/server_strings.txt`,
  `client_strings.txt`). GT's commit history dates changes (cited
  `GT@<sha>`).
- **ValveResourceFormat** (MIT) documents the bomb's baked damage file.
- **The web could be searched but mostly not read.** The session's proxy
  refused counter-strike.net, Steam, Liquipedia, Reddit, the Valve Developer
  wiki, HLTV, fandom and most community sites. Web claims are therefore from
  search-result summaries, marked as such with the page's URL, and weaker
  than a quote. No Valve release note is quoted word for word.
- Markers used in all four files: **Inferred** (a reading of a source, not
  what it states), **From memory** (no source found; kept rare),
  **Disputed** (sources disagree; both given).
- Valve's leaked CS:GO source was not read or used. One bomb-damage claim
  rests on a third party's reverse engineering of CS2's DLLs and is marked
  weak where used.

## Findings that change what the project builds

Each is checked against the file named; details and the rest of the
evidence are in the detail file.

**Money** (`round-economy.md` section 1)

1. **CTs get $50 for each dead T.** `cash_team_per_dead_enemy 50` (GT
   `DumpSource2/convars.txt`, competitive leaves the default) appeared with
   the 16 July 2025 update; the server sends it as team income "for N
   eliminated terrorists". The economy does not pay it.
2. **Money earned during a round is spent next round.** The controller keeps
   `m_iMoneyEarnedForNextRound` beside `m_iAccount` (GT
   `DumpSource2/schemas/server/CCSPlayerController_InGameMoneyServices.h`),
   and the game says "$X that you just earned cannot be spent this round"
   (GT `csgo_english.txt`, `Cstrike_TitlesTXT_Not_Enough_Money_NextRound`).
   The economy pays kill awards straight into the account, as CS:GO did.
3. **A suicide pays an enemy compensation** (GT `csgo_english.txt`,
   `Player_Cash_Award_ExplainSuicide_*`), and the suicider gets "+$0 penalty
   for suiciding". The repo's "a suicide moves no money" is wrong for
   suicides; who is paid, and how much, is still to measure.
4. The loss ladder the repo reads from the convars is the game's own formula
   (GT `panorama/scripts/scoreboard.js`, `_RoundLossBonusMoneyForTeam`).

**The bomb** (`round-bomb-grenades.md` section 1)

5. **The baked blast file can be read** (C2): per site seven floats (box and
   `BombPower`), per point three int16s, per site and point a `Phase`
   (uint16) and a yaw and pitch byte; damage is
   `clamp(100 - 100 * (Phase - BombPower) / min(Phase, 1800), 0, 255)`
   (ValveResourceFormat's `BombDamage*.cs`). Whether that damage passes
   through armour is open: a weak source says it ignores it.
6. **Drops are thrown at 300** (`m_flDropSpeed`, the class default in GT
   `DumpSource2/schemas/server/CCSWeaponBaseVData.h`, overridden by no
   weapon, the C4 included), and the dropper waits 1.5 s before taking it
   back, anyone else 1.3 s. That replaces the bomb's "lands at the feet"
   and the contract's 200 forward and 100 up.
7. **Defusing uses the use key's reach**, `player_use_radius 80` (GT
   convars), not 90. Since October 2025 the defuser's gun is lowered, they
   cannot scope, and their first shot after stopping waits 150 ms; a bomb no
   longer goes off after the match ends or at half time.
8. **The beeps speed up exponentially**, not steadily: about 1 a second at
   the plant to about 7.8 at the end, by the fraction of the timer gone,
   with their own sounds in the last ten seconds (CS:GO's community fit;
   CS2's client still schedules by the fraction).

**Grenades** (`round-bomb-grenades.md` section 2)

9. **Fire goes out whole** once more than a third of its flames are in
   smoke, not flame by flame (GT `server_strings.txt`).
10. **Fire spreads by the convars**, not a fixed 0.2 s: the first flames
    every 0.02 s, later generations slower up to 0.5 s, 3 s a flame, four
    generations, the incendiary ten times faster (GT convars `inferno_*`).
11. **The grenade collision sphere is off by default**
    (`sv_grenade_collision_sphere false`, GT convars); the repo uses a
    radius-2 sphere.
12. **A throw soon after a jump is a jump-throw**: CS2 stores the throw's
    angles, position and velocity at the jump. The window is disputed.

**Round flow and events** (`round-economy.md` sections 4 and 5)

13. The round-end reasons, their numbers and CS2's strings are tabled; the
    project's six cover all that matter but the two surrenders.
14. CS2's events differ from the contract in small ways: `grenade_bounce`
    has only `userid`; `round_end.player_count` is players alive, not the
    roster; `player_death.distance` is in metres; the bomb events carry a
    `c4` field. The contract lacks `cs_win_panel_round`,
    `round_announce_*`, `start_halftime`, `round_time_warning`,
    `show_deathpanel`, `item_pickup_failed`, `buymenu_open` and
    `buymenu_close`, which the HUD listens to.

**HUD** (`round-hud-bots.md` part A)

15. **Today's HUD is not the launch HUD** that `reference/cs2-systems.md`
    section 9 describes: health, armour and ammo sit together at the bottom
    centre, money bottom left (GT `panorama/layout/hud/hud.xml`,
    `hudhealthammocenter.xml`). Which to follow is Sid's call.
16. **The kill feed is fully specified by the files**: icon order, 5 s a
    line (1.5 times that when you are in it) and a 1 s fade, CT `#6f9ce6`,
    T `#eabe54`, your kills a 2 px `#e10000` border and your death a
    `#630606` background (GT `panorama/styles/hud/huddeathnotice.css`).
    The repo's `player_death` already carries every key it needs.
17. **Radar dots are server state**: an enemy shows only while spotted, a
    flag with a per-team mask on each player.
18. The win panel stays for `mp_round_restart_delay` (7 s); the MVP reasons
    and their strings are tabled; the round-end team counter shows damage
    given and taken per enemy ("N in K hits").

**Bots** (`round-hud-bots.md` part B)

19. **Competitive still runs the classic Turtle Rock bot**; deathmatch, arms
    race, rush and Valve's dust2 training run readable behaviour trees (GT
    `game/csgo/cfg/gamemode_*.cfg`, `mp_bot_ai_bt`).
20. **`botprofile.db` gives eight skill tiers** of reaction time, attack
    delay, aim focus and view turning, and 147 named bots; they map onto the
    repo's bot knobs.
21. **Bots buy a primary by preference, then a pistol, then armour, and a
    grenade a third of the time** (HE weighted six to one); they have no
    team economy plan and no grenade lineups, so both would be improvements
    beyond CS2 to propose as such.
22. **Valve's dust2 training tree** gives each bot a route of world
    coordinates and plant, defuse and pick-up modules: seed data for bots
    that play the round.

## The repo's guesses, settled or not

| Guess (where) | Verdict |
|---|---|
| Loss ladder arithmetic (economy.md) | Settled: the game's formula |
| Ts alive at time-out get no loss bonus (economy.md) | Settled that the rule exists |
| A death credited to nobody moves no money (economy.md) | Contradicted for suicides; blast and fall deaths still open |
| Helmet alone $350 (economy.md) | Community figure; whether the vest must be whole is disputed |
| Buy time counts from freeze time's end (economy.md) | Community agrees; the files only say "after round start" |
| Warmup money $800 (economy.md) | Contradicted by the community ($16,000); offline play has no warmup at all (`mp_warmup_offline_enabled false`) |
| Menu keys 1 pistols to 5 grenades, undo by right-click (economy.md) | Likely wrong: the menu runs equipment, pistols, mid-tier, rifles, grenades, each item with its own refund button, Delete refunds all |
| `cash_team_per_dead_enemy` pays nothing known (economy.md) | Settled: $50 to CTs per dead T |
| Plant 3.0 s (bomb.md) | Disputed (3.2 in CS2 guides); C1 |
| Defuse reach 90 units (bomb.md) | Contradicted: 80, the use radius; the cone is C1's |
| Bomb pickup reach (bomb.md) | Still to measure |
| Dropped bomb at the feet, 1 s wait (bomb.md) | Contradicted: thrown at 300, waits 1.5 s and 1.3 s |
| Beeps rise steadily to 10 a second (bomb.md) | Contradicted: exponential, to about 7.8 |
| Blast by the old radius rule (bomb.md) | Superseded; the baked file is now readable |
| Blast armour like a grenade's (bomb.md) | Contradicted by a weak source; C1 |
| Blast deaths credit nobody (bomb.md) | Settled (server log line) |
| Fire spreads every 0.2 s (grenades.md) | Contradicted: build from the convars |
| Smoke puts out flames one by one (grenades.md) | Contradicted: a third covered puts out the whole fire |
| Fire's 30-unit reach and its ramp (grenades.md) | A ramp exists; its length and the reach are still to measure |
| Smoke 18 s, its size (grenades.md) | Disputed 18 or 20 s; G4 |
| Flash figures (grenades.md) | 4.87 s straight on and the hold-then-fade shape supported; the curve is G3's |
| Grenades' 85% team damage (grenades.md) | Settled for HE and flash; whether fire counts as a grenade (0.85) or "other" (0.4) is open |
| Throw speeds and velocity share (grenades.md) | Nothing CS2-specific found; G1 |
| Decoy (grenades.md) | 15 or about 18 s disputed; G5 |

The detail files' closing sections hold the full tables, with the evidence
for each line.

## What still needs Sid's machine

Suggested additions to the Local checks, in the files' own words where
they are long:

- **E1** (`mp_logmoney 1`): the $50 per dead T (CTs only? counted for a
  bomb death or a suicide?), when kill money becomes spendable, who a
  suicide pays and how much, a fall and a blast death, the loss count in
  overtime and after a draw, and what a same-tick wipe ends as.
- **E2**: warmup money, the helmet on damaged kevlar, the menu's key
  labels, how many grenades a round can be bought, and refunds outside the
  buy zone.
- **C1**: plant time, a few beep intervals, the blast at three to five
  spots a site standing, crouched and facing away, with and without armour,
  to check the baked file's decoder and the armour question.
- **G1 to G5** as listed, plus the jump-throw window.
- **HUD**: how many kill-feed lines show, when the timer turns red, which
  layout to follow.
- **Bots**: the classic bot's field of view, and CS2's bot changes since
  2023 (the release notes could not be read here).
