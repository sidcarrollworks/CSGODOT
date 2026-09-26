# Every CS2 system, and what it takes to recreate it

Sid, 2026-09-22: buying and money are in, "just like in CS2", and the game
needs every system CS2 has: economy, UI, the bomb, all six grenades, dropping
guns, multiplayer netcode "and so on". This is that map. The order the work
goes in is in the project roadmap; this file is the detail behind it, for
the cloud threads and for Sid's local agent alike.

Each system says what CS2 does (with its numbers), what is built already, and
the work, split the way `reference/weapons/TODO.md` splits it:

- **Local** needs Sid's machine: CS2, Source2Viewer-CLI, the extracted
  `assets/`, or someone playing the game.
- **Remote** is code, data and headless tests a cloud thread can do.

The rules for both: branch and PR, never main; `assets/` is never committed;
every number comes from a file, a measurement written down in `reference/`,
or the sources below, never a guess. Valve's leaked CS:GO source is off
limits (not to read, not to copy, not to cite), as is copying Source SDK 2013
code, which is a spec only.

## Where the numbers come from

Checked 2026-09-22 against SteamDatabase's GameTracking-CS2 repository
(game-file dumps, last updated 2026-09-09), all under
`https://github.com/SteamDatabase/GameTracking-CS2/blob/master/`:

| Key | File |
|---|---|
| CFG | `game/csgo/cfg/gamemode_competitive.cfg`, the competitive settings |
| TMM | `game/csgo/cfg/gamemode_competitive_tmm.cfg`, run after it (Premier) |
| CV | `DumpSource2/convars.txt`, every cvar with its default and description |
| WV | `game/csgo/pak01_dir/scripts/weapons.vdata`, weapon and grenade data |
| IG | `game/csgo/pak01_dir/scripts/items/items_game.txt`, teams and loadout |
| FGD | `game/csgo/csgo.fgd`, the map entities |
| PB | `Protobufs/usercmd.proto`, `cs_usercmd.proto`, `netmessages.proto` |

Valve does not publish the server-side competitive config it runs on top of
CFG, so a live match could differ from it. Values marked **measure** are not
in any of these files; they are community figures to be checked in CS2 by
the Local task named beside them.

Research from 2026-09-24 into how CS2 runs a round (money, buying, the
bomb, grenades, drops, round flow and events, the HUD, bots) is in
`reference/research/round.md`. It settles or contradicts several values
below; this page is not yet updated to match.

---

## 1. Match and round flow

**CS2** (CFG unless marked)

| Rule | Value |
|---|---|
| Teams | 5 v 5 |
| Match | 24 rounds (MR12), sides swap after 12, a team can clinch at 13 |
| Overtime (Premier, TMM) | one MR3 overtime at 12-12, $10,000 each half; 15-15 is a draw |
| Warmup | 120 s (`mp_warmuptime`); none in an offline match (`mp_warmup_offline_enabled false`, `reference/research/audio-round.md` 1.2), which dust2 keeps for trying things |
| Freeze time | 15 s (20 in TMM) |
| Round time | 1:55 (`mp_roundtime_defuse 1.92`) |
| After a round | win panel 3 s, next round after 7 s (CV) |
| Death | no respawn; spectate your own team only; 2 s freeze cam |
| Friendly fire | on: bullets 33%, grenades 85%, your own grenades 100%, other 40% |
| Teammates | solid (`mp_solid_teammates 1`): you cannot walk through them |
| Half time | 15 s, money back to $800 |

A round ends when one side is dead, the bomb explodes (T), the bomb is
defused (CT), or time runs out with no bomb down (CT).

**Built:** spawn points by team and priority (`SourceEntities.player_spawns`),
and the match (`src/match/`, roadmap item 11): warmup, freeze time, rounds
ended by eliminations or the clock, the side swap and half time, the clinch,
one overtime and the draw, no respawn, spectating your own team after the
freeze cam, friendly fire for bullets, solid players, five a side on dust2
with bots filling the places. The list below says what is left of it.

**Remote**
- ~~A match state machine: warmup, freeze, live, round end, half time,
  overtime, match end, with the timers above and the score.~~ Done.
- ~~Spawning ten players on dust2's priority spawns each round; survivors keep
  their gear and health resets.~~ Done.
- Friendly fire with the reductions above: bullets done; grenades done
  (on dust2, 2026-09-23); the rest come with what deals it. ~~Solid
  teammates in the movement solver.~~ Done.
- ~~Death: body stays (ragdoll), spectating teammates, the freeze cam.~~ Done.
- ~~Bots fill empty slots on either side.~~ Done.
- ~~The bomb's round ends (section 4) and money at half time and in
  overtime (section 2) plug into the match when they are built.~~ Done
  2026-09-23, through the match's game events.

**Local**
- **R1.** The round's announcements and beeps (`reference/research/audio-round.md`
  Local checks 1 and 2): with `net_showevents 2`, the tick each of
  `round_announce_match_start`, `_last_round_half`, `_match_point`,
  `_final`, `warmup_end` and `start_halftime` arrives, against
  `round_start` and `round_freeze_end`, and which comes when two hold
  (here: at `round_start`, one a round, final first); the freeze time's
  `cs_round_start_beep` and `cs_round_final_beep` (how many, when) and the
  clock at `round_time_warning`, which are not sent here until measured.

## 2. Economy

**CS2** (CFG)

| | Value |
|---|---|
| Start money | $800; cap $16,000 |
| Win: elimination or time | $3,250 each |
| Win: bomb exploded or defused | $3,500 each |
| Loss bonus | $1,400, then +$500 a loss up to $3,400 |
| Loss ladder | starts one step up (the first loss of a half pays $1,900); a win steps it down by one, it does not reset (`mp_consecutive_loss_aversion 1`, CV) |
| Planting | $300 to the planter; Ts who planted and lost get $600 each on top of the loss bonus |
| Defusing | $300 to the defuser |
| Kill award | from the weapon sheet's Kill Award column: knife $1,500, SMGs $600 (P90 $300), pump shotguns $900, XM1014 $600, AWP and Zeus $100, grenades, pistols and rifles $300 |
| Team kill | -$300; a suicide costs score, not money (`mp_suicide_penalty`, `contributionscore_suicide -2`, no `cash_` convar) |
| Short-handed | $1,000 bonus to a team down a player (`cash_team_bonus_shorthanded`; when it pays: **measure**, E1) |

**Built** (2026-09-23): every rule above, in `Economy` (`src/economy/`),
paid by game events, with half time and overtime ($10,000,
`mp_overtime_startmoney`), the ladder starting one step up
(`mp_starting_losses 1`, capped at `mp_consecutive_loss_max 4`) and kill
awards from vdata's `m_nKillAward`. Not built: the short-handed bonus.
The numbers, their sources and the guesses: `reference/systems/economy.md`.

**Remote**
- A money ledger per player with every rule above, driven by the match state
  machine's round-end reasons, reset at half and overtime.
- Tests that walk a half of wins and losses and check every balance against
  the rules, the loss ladder above all.

**Local**
- **E1.** Check the open amounts on a local server (`mp_logmoney 1`): that
  a suicide and a death in the bomb's blast move no money; when the short-handed bonus pays; that Ts alive when
  time runs out get no loss bonus; what a pistol-round winner that loses
  round 2 is paid ($1,400 expected); what `cash_team_per_dead_enemy 50`
  pays.

## 3. Buying

**CS2**
- Buy only in your team's `func_buyzone`, for the first 20 s of the round
  (whether the 20 s count from freeze time's start or its end: **measure**,
  E2). `sv_sellback_enabled 1`: a purchase can be undone in the buy menu while
  buying is open.
- Equipment prices (WV): kevlar $650, kevlar and helmet $1,000 (helmet alone on
  kevlar: **measure**, E2, commonly $350), defuse kit $400 (CT), Zeus $200,
  flashbang $200, smoke $300, HE $300, molotov $400 (T), incendiary $500 (CT),
  decoy $50.
- Grenades: four at most, two of them flashbangs, one of each other kind;
  molotov and incendiary share one slot.
- Team-only weapons (IG): T gets the Glock-18, Tec-9, MAC-10, Sawed-Off, Galil
  AR, AK-47, SG 553, G3SG1 and the molotov. CT gets the P2000, USP-S,
  Five-SeveN, MP9, MAG-7, FAMAS, M4A4, M4A1-S, AUG, SCAR-20, the incendiary
  and the defuse kit. The rest are for both.
- The loadout: the buy menu shows five pistols, five mid-tier (SMGs, shotguns,
  machine guns) and five rifles (rifles and snipers), chosen from the
  inventory. The old paired slots (M4A4 or M4A1-S, CZ75 or Tec-9) are gone;
  only the starting pistol is fixed (Glock-18 for T, P2000 or USP-S for CT).
- Buying for a teammate is done by dropping.

**Built** (2026-09-23): buy zones, buy time, CS2's buy menu with the
default loadout (items_game's `flexible_loadout_slot`), undoing a purchase,
armour, the helmet, the kit, grenades, the Zeus, team-only weapons, five
purchases of a type a round (`mp_weapons_allow_typecount`), all in
`src/economy/`, on the test range and, since 2026-09-23, on dust2: its buy
zones, the money and buy time on the HUD, warmup's $16,000, a gun bought
taken in hand, and the bots buying as CS2's classic bot does
(`reference/systems/economy.md`, Bots buying). Not built: choosing another
loadout.

**Remote**
- Buy zones and buying time; the buy menu (CS2's wheel and grid, keyboard
  shortcuts); undoing a purchase; the loadout as a settings page with CS2's
  defaults; buying armour, the kit, grenades and the Zeus.
- Buying only inside your side's buy zone: `BrushVolume.buy_zones` gives
  them, with shapes for an `Area3D` (B1).

**Local**
- **B1. Buy zone and bomb site volumes.** *(done 2026-09-22: each brush
  entity is a model of its own, named by the entity, which
  `scripts/extract_assets.sh volumes` exports and `BrushVolume` reads; one
  buy zone a side holding that side's 15 spawns, sites A and B, and the 43
  callouts; `reference/asset-pipeline.md` lists which model is which)* They
  are brush entities: the entity lump names them (`func_buyzone` with
  `TeamNum`, `func_bomb_target`).
- **B2. Buy menu art.** *(icons done with L4:
  `panorama/images/icons/equipment/`, fetched by `scripts/extract_assets.sh
  hud`)* The weapon icons and the buy menu's sounds. The sounds are found
  (`reference/research/audio-round.md` 1.2): `UIPanorama.buymenu_mouseover`
  0.3, `buymenu_select` 0.5, `buymenu_purchase` 0.3 (`radial_menu_buy_03`)
  and `buymenu_failure` 0.4 (`weapon_cant_buy`), 2D, the buyer's own, in
  `game_sounds_ui.vsndevts`; and a purchase of armour is heard by others
  to 1000 units (`Player.EquipArmor_T` 0.3, `_CT` 0.1,
  `audio-gameplay.md` 1.3). Left: extracting `sounds/ui/` and
  `sounds/items/`, then playing them (the menu locally, the armour from
  `item_purchase` in a view); and audio-round.md's Local check 6: buy a
  rifle, armour and a grenade near a second client, refund one, and note
  what each hears (`snd_sos_show_soundevent_start 1`), whether a buy plays
  a pickup to the world, and whether the rifle comes into the hand.
- **E2.** Measure when buy time ends (the guess: 20 s after freeze time),
  the helmet-only price (the guess: $350), warmup's money, and the buy
  menu's key order.

## 4. Inventory: slots, switching, dropping, picking up

**CS2**
- Slots: 1 primary, 2 pistol, 3 knife (and the Zeus beside it), 4 grenades
  (cycled by pressing 4 again), 5 bomb. Q swaps to the last weapon, the
  scroll wheel cycles.
- G drops the weapon in hand; the knife cannot be dropped; grenades can
  (CV). Walking over a weapon picks it up if its slot is free; E swaps with the
  one in hand.
- On death: the best gun (`mp_death_drop_gun 1`), the grenade in hand or the
  best one, the kit, the Zeus and the bomb all drop.
- Draw time and a weapon's own movement speed apply on every switch.

**Built:** every player carries an `Inventory` (the items contract,
`reference/systems/contracts.md`), you and the bots alike: a spawn's knife
and side's pistol (the Glock-18, the CTs' P2000), 1 to 5 and Q through the command
(`UserCmd.weapon_select`), each gun its own `Weapon` keeping its rounds, the
item's draw time before it fires or a pin is pulled, its speed, a switch
stopping a reload. G sends `drop`, which throws the gun or grenade in hand
from the hand as it was held (`HeldPose`: CS2's hold measured level from
its third-person clips, turned with the aim's pitch, as CS2's AimCS bends
the body with it) at CS2's 300 u/s where you look, turning end over end,
bouncing and coming to rest; walking over a gun takes it after CS2's owner
waits; a death drops the best gun and a grenade (`ItemDrops`), the gun from
the hand, moving as the body was. A bot's body shows the gun in its hand
and lets go of it at its death. Grenades are thrown
from the hand: the attack buttons pull the pin, letting go throws it (the
right alone underhand), and the hand is busy for the throw clip's length
before what is next is drawn. The bomb is planted with it in hand and the
attack button held, and E defuses. What is dropped is a body on its own
physics hull, turning about its centre of mass and lying as it comes to
rest (`DroppedItem`, `ItemPhysics`, reference/weapons/physics.csv; issue 2
of reference/playtest-2026-09-25.md). Every item has its own first-person
model, built as it comes into the inventory and kept while it is carried,
so a switch builds nothing.

**Remote**
- The weapon on the ground as a rigid body (blasts and rounds push it; its
  own physics hull is extracted beside each model, `*_physics.gltf`), and E
  to swap with the one in hand.
- Scroll wheel: CS2 cycles weapons with it, and here scroll up jumps (Sid's
  choice). Keep scroll for jumping unless Sid says otherwise.
- **Measure** in CS2: whether a release throws before the pin-pull clip
  (0.97 s) has finished; how long the hand is busy after a throw (here the
  throw clip's length, 0.77 s overhand and 0.50 s underhand); whether a gun
  bought is taken in hand (here it is).
- **Measure** in CS2 (I3), a drop: on flat ground, standing still and
  looking level, how far ahead an AK lands (with no lift about 130 units,
  with this lift of 0.25 about 156); the same running at 250 (whether the
  thrower's speed is added); how many turns it makes in the air; where a
  killed bot's gun lands, standing and running.
- **Measure** in CS2, during `reference/research/hitboxes-aim.md` section
  7's pitch sweep (a bot mimicking you, side on): where the gun is (its
  `wpn` bone, `ent_skeleton`) at pitch -89, -45, 0, 45 and 89, standing and
  crouched, with an AK-47, a Glock-18 and a grenade, against
  `HeldPose.of`'s offset from the eye. If CS2 turns the gun less than the
  whole pitch, or about a point lower than the eye, `HeldPose` follows.
- Sounds of the items, not built (`reference/research/audio-gameplay.md`
  1.3): a pickup heard by everyone to 1100 units, a dropped gun's
  `weapon.<Type>.Impact` as it lands (every bounce or the first, not
  known), from `item_pickup` and the item's landing in a view; the files
  (`sounds/items/`, the physics impacts) are still to extract.

**Local**
- **I1.** Every weapon's world model (the dropped one), with L1 in
  `reference/weapons/TODO.md`.
- **I2.** *(done with L5: every gun's draw clip is in
  `reference/weapons/timings.md` and its deploy time in `vdata.md`, both
  from the game's files)* Measure draw times, with L5 there.

## 5. Armour

**CS2:** 100 armour points, a helmet protects only the head (and not a leg,
which kevlar never covers), no free armour in competitive. Armour
penetration per weapon is in the sheet; WV's `m_flArmorRatio` is the same
figure doubled (AK 1.55, sheet 77.5%).

**Built:** `HitTarget` already takes armour, helmet, the zones it covers and
the half-point-per-damage wear, and the range dummy switches it with K.

**Built** (2026-09-23): none at a spawn from nothing in a match
(`MatchRules.free_armor`, CS2's `mp_free_armor 0`), warmup included; bought
through the buy menu, lost with the round when you die, kept by a survivor.

**Remote:** bought through the buy menu, lost with the round when you die.
Armour is on the HUD (PR #27). Whether armour softens tagging is open
(**measure**, A1); here it does not, while it does soften the flinch.

**Local**
- **A1.** In CS2, compare the slowdown from a body shot with and without
  kevlar.

## 6. The bomb

**CS2**

| Rule | Value |
|---|---|
| Who has it | one random T at spawn; only Ts can pick it up; dropped on death; an idle carrier drops it after 15 s (CV) |
| Planting | inside a `func_bomb_target` only, on the ground, held still while it plants; takes about 3.2 s (**measure**, C1) |
| Timer | 40 s (`mp_c4timer`), beeping faster as it runs down (cadence: **measure**, C1) |
| Defusing | 10 s, 5 s with a kit; letting go starts it over; the bomb still goes off if the timer ends first |
| Explosion | since the 8 July 2026 update, a shockwave that walls block and corners weaken, with damage worked out ahead of time for each official map, and the health bar shows the damage you would take. Before it: damage and reach from `info_map_parameters` `bombradius` (default 500 damage, reaching 3.5 times that) |
| Round | a plant turns the round timer into the bomb timer; explosion wins for T, defuse for CT |

**Built** (2026-09-23, `src/bomb/`, `reference/systems/bomb.md`): the bomb
as server-side state: carried, dropped on death and picked up by Ts,
planted only on a site (3.0 s, a guess), the 40 s timer, the defuse (10 s,
5 with a kit, started over when let go), the explosion by the old radius
rule, CS2's bomb events, and a view with the beeps (cadence a guess). Tried
on the test range, and since 2026-09-23 in dust2's match: a plant holds
the round's clock, and the blast or the defuse ends the round. The sites' volumes
are read (`BrushVolume.bomb_sites`,
with each site's `bomb_damage_power`: A 1929, B 3234) and the map's
`bombradius` (700 damage, reaching 2,450 under the old rule;
`SourceEntities.bomb_radius`). A plant is tested against the site's volume
(`contains`), not the baked box, which for A takes in its L's notch. The
bomb and the kit are extracted (C3), with their clips' timings in
`reference/weapons/equipment.md`: the first-person plant clip is 4 s, its
seven key presses from 0.67 to 2.17 s; the third-person one 3.3 s. Neither
says when the plant completes, which is still C1's to measure.

**Remote**
- ~~The bomb as an item: carry, drop, pick up, plant with its animation lock,
  the timer and beeps, defuse and the kit.~~ Built; the round-end rules and
  the rewards are written down for the match and money
  (`reference/systems/bomb.md`) and wait on the GameWorld.
- The explosion. C2 found the baked per-map damage, but its damage values
  are not worked out, so start with the old radius rule, or approximate the
  shockwave by tracing from the bomb to each player, scaled by the site's
  `bomb_damage_power`; read the bake once it is understood.
- HUD: the carrier's icon, the planted and defusing states, the defuse bar.

**Local**
- **C1.** Measure plant time, the beep cadence against the timer, and the
  explosion's damage at a few spots on each site (with and without armour).
- **C2.** *(done as far as it goes, 2026-09-22: it is
  `maps/de_dust2/baked_bomb_damage.vdata`, extracted by `volumes`; its site
  boxes and 85,697-point grid are read and checked, its 8 bytes of damage a
  point are not worked out; `bombradius` is 700)* Look for the baked bomb
  damage in dust2's VPK and extract it if it is a file; read dust2's
  `bombradius` from the entity lump. Still open: decode the damage values,
  against the damage C1 measures at known spots.
- **C3.** *(done but for the particles, 2026-09-23: `scripts/extract_assets.sh
  equipment` and `sounds`; the voice line is S1's)* Extract the bomb (world
  and first-person), the defuse kit, their animations (plant, defuse), the
  sounds (beeps, plant, defuse, explosion, "bomb has been planted") and the
  explosion's particle textures.

## 7. Grenades

**Shared (WV and CV):** every grenade costs its price above, is thrown at 750
(the base speed; left click, right click and both give three strengths),
takes 1 s to draw, holds you to 245 u/s, and pays $300 for a kill. The
throw adds a share of your own velocity, which is what makes running and
jump throws work. There is no trajectory preview in matchmaking; CS2 has a
lineup crosshair that appears after holding the pin 2 s
(`cl_grenadecrosshair_*`). Grenades collide with the hull and with
`physics_csgo_grenadeclip`, which the importer already keeps apart, bounce
losing speed each time, and stop on floors.

The throw speeds per button, the share of your velocity, the gravity and the
bounce are CS:GO behaviour the community has documented and CS2 is thought
to keep. They go in as **measure** (G1) until checked.

**HE (WV):** 99 damage at the centre, 350 units radius, falling off smoothly
to nothing at the edge (the curve: **measure**, G2), cut by walls between;
armour ratio 1.2, so kevlar takes a share but a helmet adds nothing. Goes
off 1.5 s after the throw (**measure**, G1).

**Flashbang:** blinds anyone who can see it, teammates too, for longer the
closer you are and the more directly you face it, less through a partial
line of sight, not at all behind a wall. Goes off 1.5 s after the throw. A
kill on a player flashed past 70% counts as a blind kill
(`sv_flashed_amount_for_blind_kill 0.7`). Durations by distance and angle:
**measure**, G3 (community figure: up to about 5 s fully white).

**Smoke:** CS2's smokes are a volume of voxels the server fills out from
where it lands, flowing around walls and through doors, with a random seed
(`m_nRandomSeed`) so everyone sees the same cloud. It pops once it stops
moving. An HE blows a hole in it that refills in a few seconds; bullets cut
thin tunnels that close almost at once. It puts out fire it lands on, and a
molotov into a smoke fizzles. Bots see through at most 200 units of it
(`bot_max_visible_smoke_length`). Duration (18 or 20 s) and size:
**measure**, G4.

**Molotov (T) and incendiary (CT), CV:** go off on touching ground no steeper
than about 30 degrees, or in the air after 2 s (`molotov_throw_detonate_time`).
Up to 16 flames 42 units apart spread over the ground; the molotov reaches
150 units and burns about 7 s, the incendiary 110 units and 5.5 s, spreading
ten times faster. 40 damage a second in 0.2 s steps, ramping up, and armour
does not stop fire. Team damage from it is the thrower's for 6 s.

**Decoy:** once it stops, plays its thrower's primary weapon firing in
bursts for about 15 s, then pops for a few points of damage; no team damage
from the pop (`ff_damage_decoy_explosion false`). Timing and burst lengths:
**measure**, G5.

**Built:** the six grenades are extracted (G6), their numbers and clips'
timings in `reference/weapons/equipment.md`. All six are server-side
systems on the shared contracts (`src/grenades/`), thrown on the range
from your eyes; `reference/systems/grenades.md` says what each does, which
numbers are guesses, and what the player, the bots and the importer need
to wire them in. The importer still leaves the map's grenade clip out.

**Remote**
- The throw (three strengths, your velocity added, the release point) and a
  projectile on its own fixed-step physics with bounce and rest, colliding
  with the hull and the grenade clip, not player clips.
- HE: damage with falloff and walls, into `HitTarget` with the blast's
  armour rule.
- Flash: the blind amount per viewer, a white screen that fades, the flashed
  sound; bots blinded too.
- Molotov and incendiary: flames spreading over the hull, damage in 0.2 s
  steps, put out by smoke.
- Smoke: the voxel fill (a flood fill from the landing point through the
  hull, capped by volume), drawn with Godot's volumetric fog or a ray-marched
  volume, holes from HE and bullets, blocking sight for players and bots.
  The fill passes through what the game marks `allowsmokethrough`:
  chain-link and metal railings, and chain, which takes chain-link's
  (`SurfaceProperties.text(surface, "smoke_through")`).
  The biggest single item here.
- Decoy: fake gunfire through the weapon sounds.
- Grenade HUD: the slot row, the lineup crosshair.

**Local**
- **G1.** Measure the throw: left, right and both, standing and running, into
  the range's wall and floor, to fix speeds and gravity; and the fuse times.
- **G2.** HE damage at 50, 100, 200 and 300 units, with and without kevlar.
- **G3.** Flash: blind time at a few distances facing it, side-on and away.
- **G4.** Smoke: duration, and the cloud's size in open ground.
- **G5.** Decoy: how long, how its bursts go, the pop's damage.
- **G6.** *(done but for the textures, 2026-09-23: `scripts/extract_assets.sh
  equipment` and `sounds`; the sounds are each grenade's folder, so a bounce
  per surface, if the game has one, is not among them)* Extract all six
  grenades (first-person with their pull, throw and lob animations, and the
  world models), their sounds (pin, throw, bounce per surface, each
  detonation, the fire loop, "flashed" ringing) and the particle and smoke
  textures. CS2's particle systems (`.vpcf`) do not run in Godot, so the
  textures are rebuilt into Godot particles remotely.

## 8. Knife and Zeus

**CS2:** the knife (WV) is armour ratio 1.7 and pays $1,500 a kill; its swing
damage is not in the file (commonly cited: 40 then 25 for left swings, 65 for
the right stab, backstabs 90 and 180: **measure**, K1). Holding it you run at
250. The Zeus x27 (WV) does 500 at up to 120 units, one charge that
recharges after 30 s (`mp_taser_recharge_time`), $200, $100 a kill; up to 5 a
round in competitive.

**Built:** the default knives and the Zeus are extracted (K2) and build in
first person; nothing hands them to a player yet.

**Remote:** melee traces (swing range and arc), backstab from behind, the
Zeus as a short-range hitscan with its recharge.

**Local**
- **K1.** Measure knife damage (front and back, left and right, with and
  without armour) and swing range.
- **K2.** *(done 2026-09-23: `scripts/extract_assets.sh equipment` and
  `sounds`, listed in `reference/weapons/equipment.md`)* Extract the default
  knives (T and CT) and the Zeus, with their animations and sounds.

## 9. HUD and UI

**CS2's HUD:** health and armour (bottom left), money (top left, flashing on
change), ammo and reserve (bottom right), the weapon and grenade row (right),
the round timer and score with each side's players alive (top centre), the kill
feed (top right, with headshot, wallbang, blind, smoke and noscope icons), the
radar (top left), the bomb carrier and planted states, the damage direction
arcs, the flashbang white-out, the buy menu, the scoreboard on Tab, the
round-end panel with the MVP, the spectator bar, chat, and the crosshair
with its settings.

**Built:** crosshair, health, armour (with the helmet), ammo, the damage
direction arcs (PR #27), the death countdown.

**Remote:** every element above, one at a time as its system lands. The
radar has B3 (`MapOverview`).

**Local**
- **B3.** *(done 2026-09-22: `scripts/extract_assets.sh radar`,
  `MapOverview`; the spawns and sites fall where the overview marks them)*
  dust2's radar: the overview image and its position and scale.
- **B4.** The HUD's icons (weapons, kill feed, bomb) and fonts, for looks.
  Optional: the HUD can be drawn with Godot's own shapes.

## 10. Sound for the new systems

**Built:** the weapon, footstep, hit and impact sounds. The shooter's hit
feedback is CS2's since 2026-09-24: its attacker feedback events, read from
`game_sounds_player.vsndevts` in GameTracking-CS2, with their files,
volumes, pitches, delays and distance curves (`WeaponSounds.FEEDBACK`;
`reference/research/audio-gameplay.md` 3). What the one hit hears (flat,
`Player.Damage*.Victim` and `Death*.Victim`), what those near hear from the
body (`.Onlooker`, to about 1100 units) and the death groan everyone near
hears (`Player.Death`, `death1-6`, 0.5, silent at 1400) are CS2's too
(`HitSounds`, from the game's `player_hurt` and `player_death`, played on
the frame after). The shooter hears only their own feedback, not an
onlooker's on top (inferred). Not built: fire's (`Player.BurnDamage`),
a fall's (`Player.DamageFall`), a Zeus kill's yelp (`Player.DeathTaser`)
and the spectator versions.

**Local**
- **S1.** Extract the round sounds: round start and end (the bomb's and the
  grenades' came with C3 and G6), radio and agent voice lines ("bomb has
  been planted", "counter-terrorists win", "fire in the hole"), the buy
  sound, the 10-second warning.
- **S2.** The sound event files (`soundevents/*.vsndevts_c`) with the game's
  volumes and distances, which today are set by ear.

**Remote:** play them from the systems above through `SoundBank`.

## 11. Bots that play CS

**Today:** bots see and shoot the local player, and walk dust2's own nav
mesh (`SourceNavMesh.walk_path`: pulled taut, crouching where an area is
marked crouch-only, jumping where a link rises past a step; roadmap item
22), from their spawn to a bomb site and back.

**Remote**
- Teams of bots fighting each other.
- *(Done 2026-09-23.)* Buying as CS2's stock bot does: nothing below
  `bot_eco_limit` $2,000, a primary by its `botprofile.db` template,
  armour, a CT's kit, a third of the time one grenade (`BotBuying`).
- Buying beyond it: an economy plan per round (full buy, force, eco,
  save), dropping for teammates.
- The objective: carry and plant (T), rotate, retake and defuse (CT), save
  when a round is lost.
- Utility: a small table of known smokes, flashes and molotovs for dust2,
  plus reacting to being flashed and avoiding fire.

**Local**
- **N1.** *(done 2026-09-22)* Extract dust2's nav mesh: `maps/de_dust2.nav`,
  read by `SourceNavMesh` (`reference/asset-pipeline.md` has what is in it).
- **N3.** Read the nav mesh's analysis, the last KV3 block in the file (246
  KB of zstd, 2.3 MB unpacked). Its keys say what it holds per area: hiding
  spots (`hidingspotdata`: `pos`, `flags`), spot encounters
  (`spotencounterdata`: `from`, `fromdir`, `todir`, `order`), approach areas
  (`approachdata`: `prev`, `here`, `next` and how each leads to the next) and
  `earliestoccupytime` per team. That is what CS bots use to choose where to
  hide, where to look on the way in, and when to expect the other side.
  Needs a binary KV3 reader (Source 2 Viewer's `BinaryKV3.cs` is the
  reference; Godot unpacks zstd itself); the layout is learned against
  dust2's file, after which the reader can be tested on fixtures anywhere.
- **N2.** Record grenade lineups for the bots' table (throw position, angle,
  button, where it lands), a few per site.

## 12. Multiplayer

**CS2**
- The server is in charge; clients send input and draw what the server says.
  Official matches run on Valve's dedicated servers; playing offline with
  bots is a listen server (the server inside your own game).
- 64 ticks a second, and every input carries the instant within the tick it
  happened (`CSubtickMoveStep` with a `when` fraction, PB). This project
  does the same, at 64 Hz too (128 until 2026-09-23).
- A shot also carries the moment the client was looking at: which two server
  ticks it drew and how far between them (`input_history` in
  `cs_usercmd.proto`), so the server checks the hit against what the shooter
  saw. That is CS2's lag compensation, rewinding up to 200 ms: the
  engine's default is `sv_maxunlag 1`, but the game's own `gameinfo.gi`
  sets 0.200 (`reference/research/combat.md`, correction 1).
- The client predicts its own movement and firing and corrects when the
  server disagrees. It draws everyone else between the last two snapshots it
  has, one or two ticks behind (`cl_net_buffer_ticks 0-2`, CV). Snapshots go as
  deltas over UDP; inputs are sent more than once in case one is lost.
- Blood and the kill ragdoll can be predicted on the shooter's screen before
  the server confirms (`cl_predict_*` cvars, since November 2024).

**Godot 4.7:** ENet (`ENetMultiplayerPeer`) carries UDP with reliable and
unreliable channels. Its `MultiplayerSynchronizer` and `MultiplayerSpawner`
copy state from server to clients, but none of it predicts, rewinds or
buffers snapshots, so a shooter builds its own on top: a fixed tick,
numbered input commands with sub-tick times, the server's simulation,
prediction with replay on the client, an interpolation buffer, and a ring of
past hitbox positions for rewinding.

**What that means for everything above.** The cheapest time to decide is
before the round, economy, bomb and grenade code is written. Each system can
be written from the start as server-side state that clients only draw: the
match, money, inventory, bomb and grenades live in one simulation that takes
players' input commands, and single player is that simulation running inside
the game with bots. Retrofitting it later means rewriting each system. The
player's input, simulation and drawing are already split (PlayerSim and
PlayerView, PR #24), so the next step is the server-side state.

**Remote (all of it):** the simulation and presentation split; the command
and snapshot protocol over ENet; prediction and reconciliation for movement
and shooting; interpolation of other players; lag compensation with the
sub-tick shot time; a dedicated server build (headless Godot); a way to
connect (address and port; no Steam matchmaking); tests that run a server and
two clients headless and compare their states.

**Local:** playtests across two machines, and later over the internet.

## 13. Menus, settings and a build

Already on the roadmap: main menu, settings (sensitivity in CS2's units,
crosshair, viewmodel, binds, audio, video), an exported build. With
multiplayer: host, join, a server list or address box, team select.

## 14. CS2 features to decide on later

Not asked for yet; listed so nothing is forgotten. Warmup deathmatch, pings
and radio commands, voice chat, text chat, votes and timeouts, the
end-of-match stats and MVP music, the damage report after death, casual and
deathmatch modes, hostage maps, other maps, spectator and demo recording,
anti-cheat, and skins (not needed: the default models are enough).
