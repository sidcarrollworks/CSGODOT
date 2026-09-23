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

---

## 1. Match and round flow

**CS2** (CFG unless marked)

| Rule | Value |
|---|---|
| Teams | 5 v 5 |
| Match | 24 rounds (MR12), sides swap after 12, a team can clinch at 13 |
| Overtime (Premier, TMM) | one MR3 overtime at 12-12, $10,000 each half; 15-15 is a draw |
| Warmup | 120 s |
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
a player who dies and respawns after 3 s, two bots of one side.

**Remote**
- A match state machine: warmup, freeze, live, round end, half time,
  overtime, match end, with the timers above and the score.
- Spawning ten players on dust2's priority spawns each round; survivors keep
  their gear and health resets.
- Friendly fire with the reductions above; solid teammates in the movement
  solver.
- Death: body stays (ragdoll), spectating teammates, the freeze cam.
- Bots fill empty slots on either side.

**Local:** none.

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
| Team kill | -$300; suicides are penalised (amount: **measure**, E1) |
| Short-handed | $1,000 bonus to a team down a player (`cash_team_bonus_shorthanded`; when it pays: **measure**, E1) |

**Built:** nothing yet. Price and Kill Award are in the weapon sheet and in
the game's weapons.vdata (`reference/weapons/vdata.csv`); nothing loads them.

**Remote**
- A money ledger per player with every rule above, driven by the match state
  machine's round-end reasons, reset at half and overtime.
- Tests that walk a half of wins and losses and check every balance against
  the rules, the loss ladder above all.

**Local**
- **E1.** Check the two open amounts on a local server: a suicide's penalty,
  and when the short-handed bonus pays.

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

**Built:** nothing. The number keys give the AK and the M4 for testing.

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
  hud`)* The weapon icons and the buy menu's sounds; the sounds are still to
  find.
- **E2.** Measure when buy time ends and the helmet-only price.

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

**Built:** one weapon at a time; swapping it (1 and 2) rebuilds it.

**Remote**
- An inventory per player with the slots above; switching with draw times;
  the weapon on the ground as a rigid body with its ammo kept; pick up and
  swap; drops on death.
- Scroll wheel: CS2 cycles weapons with it, and here scroll up jumps (Sid's
  choice). Keep scroll for jumping unless Sid says otherwise.

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

**Built:** nothing yet. The sites' volumes are read (`BrushVolume.bomb_sites`,
with each site's `bomb_damage_power`: A 1929, B 3234) and the map's
`bombradius` (700 damage, reaching 2,450 under the old rule;
`SourceEntities.bomb_radius`). A plant is tested against the site's volume
(`contains`), not the baked box, which for A takes in its L's notch.

**Remote**
- The bomb as an item: carry, drop, pick up, plant with its animation lock,
  the timer and beeps, defuse and the kit, the round-end rules, the rewards.
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
- **C3.** Extract the bomb (world and first-person), the defuse kit, their
  animations (plant, defuse), the sounds (beeps, plant, defuse, explosion,
  "bomb has been planted") and the explosion's particle textures.

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

**Built:** the map's grenade clip is imported and separated; nothing else.

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
- **G6.** Extract all six grenades (first-person with their pull, throw and
  lob animations, and the world models), their sounds (pin, throw, bounce per
  surface, each detonation, the fire loop, "flashed" ringing) and the
  particle and smoke textures. CS2's particle systems (`.vpcf`) do not run in
  Godot, so the textures are rebuilt into Godot particles remotely.

## 8. Knife and Zeus

**CS2:** the knife (WV) is armour ratio 1.7 and pays $1,500 a kill; its swing
damage is not in the file (commonly cited: 40 then 25 for left swings, 65 for
the right stab, backstabs 90 and 180: **measure**, K1). Holding it you run at
250. The Zeus x27 (WV) does 500 at up to 120 units, one charge that
recharges after 30 s (`mp_taser_recharge_time`), $200, $100 a kill; up to 5 a
round in competitive.

**Remote:** melee traces (swing range and arc), backstab from behind, the
Zeus as a short-range hitscan with its recharge.

**Local**
- **K1.** Measure knife damage (front and back, left and right, with and
  without armour) and swing range.
- **K2.** Extract the default knives (T and CT) and the Zeus, with their
  animations and sounds.

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

**Built:** the weapon, footstep, hit and impact sounds.

**Local**
- **S1.** Extract the round sounds: round start and end, the bomb and grenade
  sounds (C3, G6), radio and agent voice lines ("bomb has been planted",
  "counter-terrorists win", "fire in the hole"), the buy sound, the
  10-second warning.
- **S2.** The sound event files (`soundevents/*.vsndevts_c`) with the game's
  volumes and distances, which today are set by ear.

**Remote:** play them from the systems above through `SoundBank`.

## 11. Bots that play CS

**Today:** bots see and shoot the local player, walking straight lines.
dust2's own nav mesh is read (`SourceNavMesh`, N1), so everything below can
start.

**Remote**
- Paths on dust2's nav mesh (`SourceNavMesh.find_path`, pulled taut; crouch
  where an area is marked crouch-only, jump where a link rises past a step),
  teams of bots fighting each other.
- Buying: an economy plan per round (full buy, force, eco, save), dropping
  for teammates.
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
  already does the same, at 128 Hz.
- A shot also carries the moment the client was looking at: which two server
  ticks it drew and how far between them (`input_history` in
  `cs_usercmd.proto`), so the server checks the hit against what the shooter
  saw. That is CS2's lag compensation, rewinding up to 1 s
  (`sv_maxunlag 1`).
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
