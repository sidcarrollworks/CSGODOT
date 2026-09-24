# How CS2's accuracy on the move works: research

Sid, 2026-09-24: "have a couple agents research those as well", about the
research gaps listed in the project chat that morning. This page takes
accuracy on the move: how a gun's inaccuracy grows with the shooter's speed,
what the walk key does to that, and how landing from a jump or a drop costs
accuracy. It checks each against what `src/weapons/weapon.gd` does today.

How fast a player stops (deceleration, counter-strafing's timing), the jump
itself, stamina, crouching and sub-tick movement belong to the parallel
research on movement and are left to it. The guns' other numbers, being hit,
the knife, the Zeus and netcode are in `combat.md`, which this page builds
on and does not repeat.

It records what CS2 does and what is still unknown, says how Sid can measure
each unknown (Local), and changes no code.

## Sources

Research on 2026-09-24, rechecked the same day against the newest build.
Sid asked for the most up-to-date primary sources, so CS2's own files at
the newest build come first, then Valve's own notes, then community pages.
Where only an older or secondary source exists, the claim says so beside it.

**The newest build.** GameTracking-CS2's newest commit at 05:05 UTC on
2026-09-24 is d45f52d: CS2 **1.41.8.3**, build 2000915, dated 23 September
2026 (its `game/csgo/steam.inf`). Every file key below except WV is read at
that commit. `weapons.vdata` last changed at 10f3693 (1.41.8.2, 22
September 2026) and is unchanged in 1.41.8.3; `reference/weapons/vdata.csv`
was generated from 1.41.8.2, so it is the current file. Every value WV
gives below was checked against the file at d45f52d.

The keys follow `combat.md`'s:

| Key | Source | Date or build |
|---|---|---|
| WV | CS2's `scripts/weapons.vdata`, as `reference/weapons/vdata.csv` carries it. A pair `a\|b` is `[normal, alternate]` | 1.41.8.2, 22 Sep 2026 (current) |
| CV | GameTracking-CS2 `DumpSource2/convars.txt`, by line | 1.41.8.3, 23 Sep 2026 |
| CVH | The same file's 40 dumps in GameTracking-CS2's history from 6aba72a to d45f52d. "Since at least 22 May 2026" means present at the oldest of them | 22 May to 23 Sep 2026 |
| SCH | GameTracking-CS2 `DumpSource2/schemas/server/<Class>.h`, CS2's own class layouts | 1.41.8.3; every field cited here present since at least 22 May 2026 (CVH window) |
| PB | GameTracking-CS2 `Protobufs/cs_gameevents.proto` | 1.41.8.3 |
| SS | GameTracking-CS2 `game/csgo/bin/win64/{server,client}_strings.txt` (names and format strings only) | 1.41.8.3 |
| SH | Sid's community sheet, `reference/weapons/cs2_weapon_sheet.csv`. Secondary, and older than the game's file | 18 Mar 2026 |
| DP | demoparser2 (LaihoE/demoparser, MIT), `src/parser/src/maps.rs` on `main`: the properties it reads from a CS2 demo | read 24 Sep 2026 |
| VN | Valve's own CS2 release notes, the text of counter-strike.net/news/updates as archived by ckreisl/cs-updates-as-json @656981c (`data/cs2/updates_raw.json`), dated as posted. Every post was searched for accuracy, inaccuracy, crosshair, counter-strafe, moving, running, walking and landing | 231 posts, 22 Mar 2023 to 22 Sep 2026 |
| WS | A web search's summary of a named page, with that page's date. The proxy refused cs.money, the Counter-Strike fandom wiki, HLTV, Steam, SteamDB, fpshub and gist.github.com, so these are search summaries, not the pages. Re-read them before quoting them | per claim |

Valve's CS2 release notes are cited from the archive (VN), in Valve's
words. Only CS:GO-era notes, which the archive does not hold, still come
through search summaries, and they say so.

Labels: **inferred** means reasoned from names, fields or data, not stated
by Valve. **From memory** means not checked against any source reachable
here. Nothing on this page comes from Valve's leaked CS:GO source.

## What the repo does now (main at 3975eef)

- **Speed.** `Weapon.current_inaccuracy` (`src/weapons/weapon.gd:386-404`)
  adds nothing below 0.34 of the gun's `m_flMaxSpeed` and the whole
  `m_flInaccuracyMove` from 0.95 up (`MOVING_FROM`, `MOVING_FULL`,
  `weapon.gd:78-81`). Between, the share is the fourth root of how far along
  the speed is, or the share itself with the walk key down. The speed is the
  horizontal one (`player_sim.gd:630-633`, read only).
- **Landing.** On the tick the shooter touches ground, the penalty becomes
  at least the sheet's "Inaccuracy After Landing" less standing
  (`weapon.gd:264-267`), the same for every fall, and recovers on the
  standing or crouched recovery time. The game's own landing field is not
  used (`weapon_vdata.gd:12-14`).
- **Airborne.** The whole `m_flInaccuracyJump` while off the ground
  (`weapon.gd:390-391`). `m_flInaccuracyJumpInitial` and
  `m_flInaccuracyJumpApex` are not used.
- `reference/weapon_stats.md:100-104` and `movement_constants.md:23-24`
  describe the same model and give it as CS:GO's.

## Summary

| What the repo assumes | Verdict |
|---|---|
| No cost below 34% of the gun's top speed | **Community figure, 2026 guides** (WS). No primary source: no CS2 file states it, since it is a compiled constant |
| Full cost from 95% | **Unsourced** (from memory, CS:GO era). Nothing reachable here names it |
| Fourth-root rise between, steep early | **Open, and possibly backwards.** The only Valve statement on the shape is CS:GO's, from 10 July 2013; none of CS2's notes mentions it (VN). It calls the curve exponential, which usually means slow early, steep late (WS) |
| The walk key makes the rise linear | **Unconfirmed** (from memory). CS2 does track the walk key on the player (`m_bIsWalking`, SCH) |
| Landing costs the same for every fall | **Probably wrong.** The game's landing field is a coefficient about a thousand times smaller than every other inaccuracy, and CS2 keeps each landing's speed (WV, SCH; inferred) |
| The sheet's landing figure is the penalty landing puts on | **Probably wrong.** It cannot be rebuilt from the game's coefficient and any one fall speed; the factor between them runs from 1.5 to 484 and follows each gun's recovery time (below) |
| Jumping is one flat term | **Incomplete.** CS2 has three jump fields; see `combat.md` §R13 "Jumping" |

All three open questions come out of one demo on Sid's machine (last
section).

## 1. Speed to inaccuracy

### What CS2 stores

- Per gun and mode: `m_flInaccuracyMove` and `m_flMaxSpeed` (WV; SCH
  `CCSWeaponBaseVData`, both `CFiringModeFloat`, so the scoped or silenced
  mode has its own). The AK is 0.17506 and 215; the AWP 0.17648 at 200
  unscoped and 100 scoped; the M4A1-S 0.09288 with the silencer off and
  0.122 with it on (WV).
- **Every shot reports its movement term apart from the rest.**
  `CMsgTEFireBullets` carries `inaccuracy` and `spread`, and in its `Extra`
  part `inaccuracy_move` and `inaccuracy_air` (PB lines 20-45). So the total
  is built from separate terms, one of them the speed's, which is how the
  repo adds them (inferred from the field names).
- The server's debug line for a shot prints the speed beside the
  inaccuracy: `FireBullets @ %10f [ %s ]: inaccuracy=%f spread=%f max
  dispersion=%f mode=%2i vel=%10f seed=%3i` (SS). Inferred: the speed the
  movement term is read from is the one in effect when the round fires.
- **No convar sets the curve.** The only movement-accuracy convars are
  disabled experiments: `sv_strafing_inaccuracy_enabled false` with its
  bias 0.5 and scale 0.1, `sv_turning_inaccuracy_enabled false` with its
  angle 4 and decay 0.8 (CV 10758-10830), and the development-only
  `sv_extreme_strafe_accuracy_fishtail 0`, "degrees of aim 'fishtail' when
  making an extreme strafe direction change" (CV 10020). The weapon keeps
  their state (`m_flTurningInaccuracy`, `m_flTurningInaccuracyDelta`, SCH
  `CCSWeaponBase`), unused while they are off. The thresholds and the shape
  are compiled in; no strings file carries a float, so they cannot be read
  here.

### The threshold

- Community guides for CS2 give 34% of top speed as where moving starts to
  cost accuracy, "roughly 88 units/s with a rifle" (WS: steamanalyst.com,
  metabot.gg, both 2026). **Secondary only**: no current primary source
  gives it. 34% of the AK's 215 is 73 u/s; 88 would be 34% of 260, so the
  guide's figure is loose. Same threshold as the repo.
- A coincidence worth knowing: the duck speed is 0.34 of top speed
  (`movement_constants.md:24`; **CS:GO's value**, not checked against CS2). Crouch-walking at full crouch speed
  therefore sits exactly at the threshold and costs nothing (inferred; it
  holds if both numbers are CS2's).
- **Which top speed.** The repo divides by the gun's `m_flMaxSpeed` for the
  current mode. CS2 also keeps the player's own current top speed
  (`m_flMaxspeed`, SCH `CPlayer_MovementServices`), which differs from the
  gun's when tagged (`m_flVelocityModifier`, SCH `CCSPlayerPawn`) or on the
  Negev, whose `m_flAttackMovespeedFactor` 0.5 is the only one not 1.0 (WV;
  inferred: it halves speed while firing). Which one the threshold uses is
  unknown. Either way a tagged player slows and so shoots straighter, since
  the cost follows speed (inferred).

### The shape between

- **Only an older source exists.** CS:GO's release notes of 10 July 2013:
  "Adjusted the function that maps movement speed to weapon inaccuracy. The
  linear portion of this function is now exponential." Players at the time
  read it as changing only the stretch from standing to moving accuracy,
  not the running figure (WS: HLTV news 10954, a Steam discussion of
  7/10/13). This is CS:GO's, 13 years before today's build. None of CS2's
  231 posted notes, March 2023 to 22 September 2026, mentions the curve,
  the walk key's effect on accuracy or landing inaccuracy (VN), and CS2's files cannot show it (the
  constants are compiled in), so whether CS2 kept the 2013 shape is
  unknown.
- "Exponential" in everyday use means slow at first and steep near the top.
  The repo's fourth root is the opposite: steep at first, flat near the top.
  For the AK at 80 u/s, just past the threshold, the repo gives 5.2 degrees
  of a full run's 10.3; a curve that rises late would give well under 1. How
  a counter-strafe feels in its last few ticks depends on which is right.
  The repo's shape came into PR #23 without a cited source (from memory).
- The community's "0.95" and the fourth root are not in any file or search
  result this pass reached.

## 2. The walk key

- CS2 keeps whether the player is walking on the pawn, `m_bIsWalking` (SCH
  `CCSPlayerPawn`), and demos carry it (`is_walking`, and the `WALK` button
  bit 1 << 16, DP). Inferred: it is networked because something the client
  predicts reads it, and the weapon's inaccuracy is the obvious candidate.
- The walk speed is 0.52 of top speed in the repo (**CS:GO's value**,
  `movement_constants.md:23`, not checked against CS2); 112 u/s for the AK, above the 73 u/s
  threshold. So a walking AK is never at standing accuracy while it moves.
  Whether CS2's walk is still 0.52 is the movement research's to settle.
- **What the key does to the curve is unconfirmed.** The repo's reading
  (linear while walking, fourth root otherwise) is from memory. Two other
  readings fit what players say ("walking is more accurate"): the key does
  nothing to the curve and walking only helps by being slower; or walking
  uses its own curve. At the AK's full walk speed the three give 3.4
  degrees (the repo's linear), 7.8 (the repo's running curve at walking
  speed), or something else. Guides only say walking is better than running
  and worse than standing (WS: csmarket.gg, 2025; cs.money, a CS:GO-era
  article updated for CS2, undated in the summary).
- The test that separates them holds the speed and flips only the key (see
  the last section).

## 3. Landing

### What CS2 stores

- **`m_flInaccuracyLand` is a coefficient, not a cone.** The AK's is
  0.000242; its standing inaccuracy is 0.00641 and its running term 0.17506
  (WV). Across the guns it runs from 0.000043 (Deagle) to 0.000409 (Negev),
  a thousand times smaller than the other inaccuracies. Inferred: it is
  multiplied by something about the landing, most plausibly the fall speed
  in units a second, which is in the hundreds.
- **CS2 keeps each landing's speed.** `CPlayer_MovementServices_Humanoid`
  has `m_flFallVelocity`; the modern jump keeps `m_nLastLandedTick`,
  `m_flLastLandedFrac` and `m_flLastLandedVelocityX/Y/Z`
  (`CCSPlayerModernJump`); the pawn keeps `m_lastLandTime`,
  `m_flLandingTimeSeconds` and `m_bOnGroundLastTick` (SCH). Demos carry
  `m_flFallVelocity` as `fall_velo` (DP). demoparser2 also names a
  `m_flMaxFallVelocity`, which today's schema no longer has.
- **One penalty per gun.** `CCSWeaponBase` has a single accumulating
  `m_fAccuracyPenalty` with its `m_flLastAccuracyUpdateTime` (SCH), and
  demos carry it per tick as `accuracy_penalty` (DP). Inferred: landing
  adds to this penalty, as firing does, and it recovers on the gun's
  recovery times like the rest. The repo already keeps one penalty
  (`_inaccuracy`) but sets the landing figure as a floor instead of adding
  to it.
- `weapon_land_dip_amt 20`, "the amount the gun should dip when the player
  lands after a jump" (CV 11793), is the view model's dip only: cosmetic.
- **Only an older source exists.** The Deagle's April 2020 change also
  shortened "the time to recover accuracy after the player lands" (WS:
  CS:GO release notes, April 2020). That is CS:GO's; no CS2 note mentions
  landing accuracy (VN). The nearest CS2 change is to movement, not
  accuracy: "Landing vertical velocity now affects landing speed penalties
  similar to sv_legacy_jump stamina" (VN, 22 Jan 2026), after "Landing time
  is now calculated with subtick precision" (VN, 21 Jan 2026). So CS2 does
  scale one landing effect by the fall; that the landing's accuracy cost
  does the same is still inferred. With no landing-recovery field in WV,
  inferred: that was done through the coefficient or the recovery time,
  not a separate timer.

### What a fall-scaled landing would give

A jump on flat ground lands at about its take-off speed, 302 u/s
(`sv_jump_impulse 301.993` and `sv_gravity 800` in CS2 today, CV 10179,
10092; the repo has the same); a drop of 100 units lands at
about 400 u/s. Coefficient times fall speed, if that is the rule (inferred):

| Gun | Coefficient (WV) | Flat jump, x 302 | 100-unit drop, x 400 | Sheet's excess over standing (SH) |
|---|---|---|---|---|
| AK-47 | 0.000242 | 73.1 (4.2°) | 96.8 (5.5°) | 26.6 (1.5°) |
| M4A1-S, silencer on | 0.000197 | 59.5 (3.4°) | 78.8 (4.5°) | 16.6 (1.0°) |
| AWP, scoped | 0.0001 | 30.2 (1.7°) | 40.0 (2.3°) | 17.8 (1.0°) |
| Desert Eagle | 0.000043 | 13.0 (0.7°) | 17.2 (1.0°) | 20.8 (1.2°) |
| Glock-18 | 0.000185 | 55.9 (3.2°) | 74.0 (4.2°) | 3.1 (0.2°) |
| SSG 08, scoped | 0.000215 | 64.9 (3.7°) | 86.0 (4.9°) | 0.3 (0.02°) |

Figures in thousandths (the sheet's unit), degrees in brackets. A step
down a small ledge would cost almost nothing under such a rule; the repo
charges it the full figure.

### What the sheet's landing figure is

`vdata.md` calls the sheet's figure a composite "of another kind", the
game's term scaled by the fall. It does not fit one fall speed. Taking the
sheet's figure less standing inaccuracy and spread, and dividing by the
game's coefficient, gives a factor that is the same for a gun's two modes
(the AWP excepted: 80 unscoped, 178 scoped) and for guns sharing a
recovery time (MP7 and MP5-SD 142.2; G3SG1 and SCAR-20 217.3; Nova and
Sawed-Off 158.4 and 158.2, with coefficients 0.000236 and 0.000108), but
runs from 1.5 (SSG 08) and 16.8 (Glock, Five-SeveN) through 110 (AK) to
398 (M249) and 484 (Deagle). It correlates with `m_flRecoveryTimeStand` at
r = 0.97 and with no other field above 0.86 (all 33 guns, computed here).

Inferred: the sheet's figure is not the penalty at the moment of landing
but what is left of it some time later, after the gun's own recovery has
worked on it; a slow-recovering gun (Deagle, M249) keeps more, a fast one
(SSG 08, Glock) almost none. No single fall speed and delay reproduces all
33 exactly, so the sheet's method is still unknown. Either way the repo
puts that already-recovered figure on at landing and then recovers it
again, so its landing penalty is likely too small at first and gone too
soon for most guns, and too large for the Deagle.

## 4. Jumping, as it bears on landing

`combat.md` §R13 "Jumping" covers the three fields. Only what matters for
landing: `m_flInaccuracyJumpInitial` (AK 0.10094) is, by its name, the cost
at take-off (inferred); if it goes into the same penalty it is still
recovering when a short hop lands. The Deagle's apex term has a flag on
the movement service, `m_bJumpApexPending` (SCH
`CCSPlayer_MovementServices`), so the game marks the apex as an event
(inferred). `weapon_air_spread_scale 1` scales the airborne term (CV 11772).

## What players criticise, and what could apply here

Sid, 2026-09-24: "While researching keep track of critiques and improvements
players want to see." Newest first, CS2-era before CS:GO-era. Forum and news
pages refuse fetches from here, so players' words are search summaries
(WS); Valve's changes are quoted from its own notes (VN); its date is the page's or the event's. His standing rule
applies: CS2 is the starting point, not the limit, and anything proposed
must be measurable and weigh a server's cost per tick first.

| When | What players or Valve said | What it means for us |
|---|---|---|
| 22 Sep 2026 (1.41.8.2) | **Valve made the Dynamic Quad the default crosshair**: "Updated the default crosshair to "Dynamic Quad," which better represents weapon accuracy" (VN, 22 Sep 2026). In the files: `cl_crosshairstyle` defaults to 7, and "Styles 0, 1 and 7 track the weapon's actual inaccuracy" (CV 1005-1006, 1.41.8.3); the Dynamic Quad arrived in 1.41.8.2 (CVH). Pros mostly keep static crosshairs (WS: refrag.gg, 2026) | Players could not see when moving had cost them accuracy, and Valve's answer is to show the cone by default. Our `Crosshair` draws four fixed ticks and only draws the cone as a debug circle on the range (`src/ui/crosshair.gd:26-40`). The match HUD could default to ticks that open with `current_inaccuracy`, keeping static as an option. It reads state per frame; nothing per tick |
| 2026 guides | **Players cannot tell whether they had stopped** when they fired: "shooting too early" before speed drops under the threshold is the common mistake, "difficult to self-diagnose" (WS: nextfrag.gg, metabot.gg) | A training aid CS2 only has behind cheats (`cl_weapon_debug_show_accuracy`, CV 2332): on the range, show the speed and movement cost of each shot beside the hit log. It reads what the shot already records; nothing per tick |
| 1 Oct 2025 | "Added inaccuracy representation in sniper scopes" (VN); `cl_sniper_show_inaccuracy true` (CV 2128) | The same direction as the crosshair: Valve shows the cone. Belongs with the scope work (weapons TODO R4) |
| 28 Jul 2025 | "Improvements to damage prediction when shooting while moving" (VN) | What the shooter's own client predicts about a hit while moving; netcode (roadmap item 25), nothing to change in single player |
| 28 Jan and 16 Jul 2025 | Valve tunes accuracy per gun, not the rules: "Reduced crouching accuracy for the MP9, MP5-SD, and MP7", "FAMAS accuracy improved" (VN, 28 Jan 2025); "MP9 - increased recoil magnitude and substantially reduced jumping accuracy" (VN, 16 Jul 2025) | Already in: we read these numbers from the current `weapons.vdata` (WV). It also says where Valve answers complaints, in each gun's figures, which is where any deliberate change of ours should go too |
| 19 Oct 2024 | **Running accuracy ranked fourth** of the problems more than 40 pros named in Thour's survey, after performance, sub-tick networking and view-model bob (WS: esports.gg, dust2.us) | The complaint is that running shots land too often. Part of it is how CS2 feels online, not the numbers: on the victim's screen the shooter is still running when they had already stopped on their own (WS: Steam discussions, 2023), which is the interpolation delay `CLAUDE.md` names as a known weakness, and that belongs to the netcode (roadmap item 25). The rest is the curve, which the demo below measures. A measurable proposal once it is in: hit rate of first shots fired above the threshold, CS2 against ours, at the same range |
| 19 Aug 2024 to 28 Jan 2025 | **Valve banned counter-strafe automation.** "Certain types of movement/shooting input automation such as hardware-assisted counter strafing will now be detected on Valve official servers, resulting in a kick from the match" (VN, 19 Aug 2024); detection options for other servers, "the sv_auto_cstrafe family" (VN, 9 Sep 2024); "Counter-strafe summaries are now available in game server log data" (VN, 28 Jan 2025). The convars define it: a counter-strafe counts only when the player moves faster than 135.2 u/s, and is "a success (counter-strafing took place within a single tick), an overlap (both directions were held for 1+ ticks) or an underlap (neither direction was held for 1+ ticks)" (CV 9726-9745, 1.41.8.3). Players had been using Snap Tap and null binds (WS: dust2.us, pcgamesn.com, Aug 2024) | Counter-strafing is meant to be a skill of timing, so the accuracy cost of speed has to stay. Single player needs nothing. For multiplayer, CS2's rule is a per-command count of key overlaps above 135.2 u/s: cheap next to a hull trace, and a policy for Sid to decide later. The same success/overlap/underlap count would make a good range readout for practising counter-strafes |
| 7 Sep 2023 (CS2 limited test) | **Pimp's video of running pistol kills**, "the running accuracy is out of this world"; later judged less severe (WS: win.gg, n4g.com). No CS2 note answers it directly (VN) | By CS2's own numbers pistols lose little while running: the Glock's move term is 0.01 and the Deagle's 0.0481, against the AK's 0.17506 (WV, current). We read the same numbers, so we inherit this. Changing it would depart from CS2 on purpose; the numbers are there if Sid wants to |
| 28 Apr 2016 (**CS:GO era**) | "Most weapons are almost 100% accurate right after landing from a jump", the Deagle the exception; a crouch-jump AWP shot lands accurate. The poster asked for a landing penalty that lingers about half a second for every gun (WS: Steam discussion "Accuracy after jumping fix") | An old observation, but it fits the small landing coefficients better than the fall-speed reading's large first-tick figures in section 3, which is one more reason to measure before changing our landing. If CS2 still lands this accurately, a longer landing penalty would be a deliberate improvement to propose, measured as the cone 100, 200 and 300 ms after a flat jump |

## Corrections other docs and code need

For whoever takes these on; this PR makes none of them.

1. `src/weapons/weapon.gd:78-81`, `:392-404`: the 0.95 and the fourth root
   are unsourced, and the one public description of the shape suggests a
   late rise. Keep them until the demo below, then fit the measured curve.
   The comments that say "as CS does" should say "CS:GO's, unconfirmed"
   until then.
2. `src/weapons/weapon.gd:264-267`: landing should add the game's
   coefficient times the landing speed to the penalty, not floor it at the
   sheet's figure, once the demo confirms the rule. The shooter state would
   need the landing speed, which `player_sim.gd` (the local agent's) would
   pass; a hook to list in `reference/systems/` rather than edit here. No
   extra traces: the speed is the velocity already in hand on the landing
   tick.
3. `src/weapons/weapon_vdata.gd:12-14` and `reference/weapons/README.md:14`,
   `:95`: the landing is "a coefficient the game scales by the fall" holds;
   add that the sheet's figure looks like the penalty after some recovery,
   not at landing.
4. `reference/weapon_stats.md:96-104`: "as in CS:GO" for the thresholds and
   the fourth root should say unconfirmed, and the landing sentence should
   point here.
5. `reference/movement_constants.md:23-24`: the walk and duck modifiers
   matter to accuracy too (the duck one sits exactly on the threshold);
   note it beside them.
6. `reference/research/combat.md` §R13 "Jumping": add
   `m_bJumpApexPending` and the landing fields above.
7. `src/ui/crosshair.gd`: CS2's default crosshair has tracked the
   weapon's inaccuracy since 1.41.8.2 (22 September 2026). Whoever builds
   the match HUD (roadmap item 15) should make ours follow
   `Weapon.current_inaccuracy` by default, with static as an option.
8. `tests/run_tests.gd` phase 9 (counter-strafe timings) measures when the
   cone closes; the 78 ms and 203 ms it prints depend on the curve's shape
   and will move when the curve does.

## Measuring in CS2 (Local)

Only Sid has CS2. One demo answers everything above. Record on a local
64-tick server with `sv_cheats 1` (`record moving`), and parse it with
demoparser2 (MIT), which reads per tick `velocity`, `is_walking`,
`is_airborne`, `fall_velo` and `accuracy_penalty`, and per shot the
`fire_bullets` event with `inaccuracy`, `spread`, `inaccuracy_move` and
`inaccuracy_air` (DP; PB). `combat.md`'s last section has the bot and
placement commands.

| Unknown | How |
|---|---|
| Threshold, full point and shape of the speed curve | AK, `weapon_accuracy_nospread 0`; hold fire and let go of a run key so the speed falls through the whole range; repeat by strafing and by releasing. Plot `inaccuracy_move` against horizontal speed from `velocity` |
| Whose top speed sets the threshold | The same with the AWP scoped (100) and unscoped (200); and with a tagged player (`velo_modifier` below 1) |
| What the walk key does | `sv_maxspeed 110`, so running and walking both top out at the same speed; run and walk at it with the AK and compare `inaccuracy_move`. Different at the same speed means the key changes the curve |
| Walk speed | `cl_showpos 1`, or `velocity` in the demo, walking at full speed with the knife and the AK |
| Landing rule | Drop from heights of 0, 16, 32, 64, 128 and 256 units (`setpos_exact`) with the AK; read `accuracy_penalty` on the landing tick and the tick before, and `fall_velo` just before landing. A fall-scaled rule makes the jump in penalty a straight line in fall speed; check its slope against 0.000242 |
| Whether landing adds or floors | Fire a few rounds, then land while the penalty is still up; compare with a landing from rest |
| What the sheet's landing figure is | The AK's penalty 0.2, 0.3 and 0.4 s after a flat jump's landing, against the sheet's 26.6 thousandths less standing |
| Take-off cost | `accuracy_penalty` on the take-off tick of a standing jump, against `m_flInaccuracyJumpInitial` |
| Crouch-walking | Crouch-walk at full speed; `inaccuracy_move` should be 0 if the duck speed is 0.34 |

Until these are in, the repo's curve and landing stay as they are:
changing them on a guess would only swap one guess for another.
