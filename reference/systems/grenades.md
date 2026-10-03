# Grenades

CS2's six grenades as server-side state, built on the shared contracts
(`reference/systems/contracts.md`: game events, `DamageInfo`, items by
class name, `SimEntity`). Roadmap items 17 to 20; `reference/cs2-systems.md`
section 7 has CS2's rules. This page says what is built, what each number
rests on, what it costs a tick, and what the files it does not own need to
do to wire it in.

**October 2 audit:** [current CS2 binary and graph findings](../research/grenade-audit-2026-10-02.md)
now verify launch, strength, release/jump timing, box collision, substeps,
bounces, fuses and parts of HE/flash behavior. The [implementation follow-up](../research/grenade-port-2026-10-02.md)
ports throw strength, delayed release and jump parameters, launch/flight
boxes, substeps, surface bounce/rest, activation and one-time enemy body
hits. `ProjectileTrace` separates contact fraction from normal clearance
with an opt-in Box3D query. G1 still needs recorded lineups; HE/flash
effects, water, spin and additional entity filters remain open.

## What is built

In `src/grenades/` and `src/physics/projectile_trace.gd`, checked by
`run_grenade_checks.gd`, `run_grenade_port_checks.gd`,
`run_projectile_trace_checks.gd` and the hand/jump integration in `run_sim_checks.gd`.

| File | What it is |
|---|---|
| `grenade_rules.gd` | Every number: the game's from `vdata.csv` (damage, reach, armour ratio, throw speed), the rest marked with the measurement that settles it |
| `grenade_flight.gd` | Pawn-center launch with a ±2.02 box, 16 units ahead; ±2 flight box, two 1/128 s steps at 64 Hz, midpoint gravity, clip-push/restitution and floor rest |
| `grenade_throw_state.gd` | Gradual held strength, middle snap, 0.1 s release scheduling, one jump deferral and movement-finish snapshot with a 0.2 s age limit |
| `../physics/projectile_trace.gd` | Original collider/RID/shape, geometric flight fraction, separate 0.01-inch normal clearance and conservative blocked starts |
| `smoke_voxels.gd` | The smoke's cloud: 16-unit cubes filled from where it stopped, round walls and through doors, over a 1 s bloom; holes from HE, tunnels from rounds; how much of a line is in smoke |
| `fire_spread.gd` | A molotov's or incendiary's flames spreading over the ground, up to 16, 42 apart, within 150 (110) units, never through walls or into smoke |
| `flash_blind.gd` | How a flash blinds one player (by distance and facing, not through walls) and how it wears off |
| `decoy_bursts.gd` | When a decoy fires, from its seed |
| `grenade_entity.gd` | A grenade in the world (`SimEntity`): flies, then goes off by what it is, sending CS2's events and dealing damage through `DamageInfo` |
| `inferno_entity.gd` | A fire (`SimEntity`, CS2's `inferno`): spreads, burns in 0.2 s steps, goes out |
| `grenade_system.gd` | The system (`GameSystems.add_system`): the throw, and the queries `smoke_length_between`, `blindness`, `blind_share`, `burning_at` |
| `grenade_view.gd`, `flash_overlay.gd` | What is drawn: the grenades (the game's world models where extracted), the cloud, the flames, a light where one goes off, the white-out. They only read |

On the range, `maps/test_range/grenade_lane.gd` keeps you in four, the most
you can carry (an HE, a flash, a smoke and your side's fire grenade), and
hands back each one you throw; a spawn stocks you again. Throwing is the
hand's (item 2 below): 4 takes one out, again for the next, and the attack
buttons pull the pin and throw it on letting go. The readout at the bottom
says what the last ones did. O clears them. The system is in the range's
game, its `GameWorld`'s, which steps it after the players each tick.

## What each does

- **HE.** Deadline 1.5 s after projectile spawn, detonating when a
  0.2 s think finds time strictly beyond it. 99 at the centre, falling along a
  bell curve to nothing at 350 (CS:GO's documented curve; G2), to anyone
  with a clear line from the blast to their middle, eyes or feet. `DMG_BLAST`,
  no zone, armour ratio 1.2 (kevlar lets 60% through). Clears the smoke
  within 128 units for 3 s.
- **Flashbang.** Uses the same spawn-based deadline and think schedule as HE. Blinds anyone whose eyes it
  can see, the thrower and teammates too: up to 4.87 s looking at it close
  up, falling off past 250 units to nothing at 2000, less side-on, a fifth
  with your back to it. Held white, then fading over the last 3 s; seen
  weakly, grey rather than white. `player_blind` for each. Smoke does not
  stop it (as in CS:GO).
- **Smoke.** Checks every tick; activates at speed <= 0.1 u/s and age
  >= 1.188 s. 1,600 cubes of 16 units, about 300 across and 130 tall in
  the open, grown over 1 s, lasting 18 s. A fire it pops in goes out whole;
  flames it grows over go out one by one, and a fire cannot spread into it.
  A round cuts a tunnel that closes in a quarter of a second (from
  `bullet_impact`: the shooter's eyes to where it landed).
- **Molotov and incendiary.** Break on ground no steeper than 30 degrees, or
  on a think strictly past the 2 s spawn-based air deadline, or after
  more than 0.5 s at speed <= 5 u/s. A one-time enemy body hit extends the
  deadline by 4 s. The airburst ray starts 10 units above and ends 128 below. Into smoke they fizzle. The fire spreads a flame every 0.2 s
  (the incendiary every 0.02 s), burns 7 s (5.5 s), and hurts anyone
  standing within 30 units of a flame: 40 a second in 0.2 s steps, ramping
  from half to all of it over the first second in it. `DMG_BURN`, armour
  neither softens it nor wears. Credited to the thrower for as long as it
  burns, except that burns on the thrower's teammates are the thrower's only
  for the first 6 s and nobody's after (`inferno_friendly_fire_duration`).
- **Decoy.** First thinks 2 s after spawn, then every 0.2 s until speed
  <= 0.2 u/s activates it. Fires its thrower's primary (else pistol) in bursts
  of 1 to 5 at the gun's own rate with 0.5 to 2 s between, for 15 s
  (`decoy_firing`, at the moment in the tick each round falls), then pops
  for 5 to the other side within 64 units.
- **Team damage.** `GrenadeSystem.team_damage_scale`: 1 alone, 0.85 in a
  match (`GrenadeRules.TEAM_DAMAGE_IN_MATCH`); the thrower always takes all
  of their own. The decoy's pop hurts nobody on the thrower's side.

Events use the contract's keys; positions are Godot's axes, as
`Hitscan.fire_as` sends `bullet_impact`.

## The numbers, and what settles them

The game's own: damage 99 (HE), 40 (fire, per second), reach 350, armour
ratios, throw speed 750, prices, 245 u/s holding one, 1 s draw. From CS2's
convars (`reference/cs2-systems.md`): the molotov's 2 s air time and 30
degree slope, 16 flames 42 apart, 150 and 110 reach, 7 s and 5.5 s, the
incendiary ten times faster, 6 s of team-damage credit, `bot_max_visible_smoke_length`
200, `sv_flashed_amount_for_blind_kill` 0.7, grenades' 85% team damage.

Numbers originally taken from CS:GO community descriptions: the throw
(750 x 0.9, times 0.3 to 1 by strength; 1.25 of your velocity; lifted 10
degrees at the horizon; 22 ahead, 12 lower for a lob), 40% gravity, 45%
kept per bounce (30% of that off a player), resting under 20 u/s on a floor,
the 1.5 s fuse, the 0.2 s check for a still smoke or decoy, the HE's bell
curve. The October 2 audit confirms the velocity scaling/share, pitch lift,
drop, gravity, 0.45 elasticity and HE's sigma=radius/3, but supersedes the
22-unit launch, sphere collision, player bounce multiplier and shared
smoke/decoy rest rule. The port replaces those and adds delayed release,
gradual strength, jump snapshots and 1/128 s flight steps. HE/flash deadlines start at
projectile spawn; normal smoke activation needs age >= 1.188 s and speed
<= 0.1 u/s, while decoy activation needs speed <= 0.2 u/s.

Remaining guesses/comparisons: the fire's
spread interval for the molotov, its 30-unit reach and its ramp; the HE's
smoke hole and the round's tunnel (G4); the smoke's size, shape and 18 s
(G4); flash presentation and partial-cover behavior (G3); the decoy's
weapon-dependent bursts and pop (G5). The audit verifies the fire grenade's
airburst trace from position +10 up to position -128 down, and a one-time
enemy body hit adds 4 s to its fuse. Its flash server curve reaches 3,000
units, uses four facing bins and separate hold/fade/network clocks;
`flash_blind.gd` still uses the older figures described above.

## What a tick costs

Counted in the checks, for the performance rules:

- A moving grenade: normally two box sweeps per 64 Hz tick, up to four
  sweeps per substep when rebounding. Each native sweep supplies contact
  and fraction in one adapter query. A player-owned moving grenade also
  queries a radius-3 enemy-body overlap once per tick until its first hit;
  settled grenades do neither. The 0.001-inch query slop is local to this
  cast; it does not change the player or rigid-body solver.
- Paired timings and a ten-grenade Dust2 workload are recorded in the
  [port validation](../research/grenade-port-2026-10-02.md).
- A smoke while it blooms: about 37 ray traces a tick for its first second
  (2,386 for the whole cloud in the open), none after. Asking how much smoke
  a line crosses walks the line in half-cube steps inside the cloud's box
  only: no traces.
- A fire: two ray traces per try at a new flame (the molotov tries every
  0.2 s, the incendiary every 0.02 s, until 16), none to burn.
- A flash: one ray per living player when it goes off. An HE: up to three
  per player in reach. A decoy's pop: the same, within 64 units.
- Nothing reads the disk during a tick (the world models load when the view
  is made).

## What the files it does not own need, to wire it in

For the GameWorld (`src/sim/game_world.gd`, PR #50) and whoever owns the
files named:

1. *(Done 2026-09-23.)* **dust2's `GameWorld`** adds the system to its
   game, as the range does: `world.game.add_system(GrenadeSystem.new())`,
   and a `GrenadeView` that `watch`es the game. At a round's start
   (`round_prestart`) the grenades and fires are removed and the system's
   blinding with them (`GrenadeSystem.clear()`). In a match,
   `team_damage_scale = GrenadeRules.TEAM_DAMAGE_IN_MATCH`.
2. **`player_sim.gd`: the throw from the hand (ported 2026-10-02).**
   Attack pulls the pin once drawn. The first hold assigns strength directly;
   later button changes approach by 0.0203124992549 per eligible hold tick.
   Release starts the hand clip and a separate 0.1 s simulation timer.
   A qualifying first jump consume can defer once by another 0.1 s. Movement
   schedules the jump stash from actual takeoff plus 0.1 s, inserts a movement
   boundary at that deadline, and captures eye, collision center, aim and velocity
   after that collision-aware step, before the tick's remainder. Launch uses the snapshot while its
   age is >0 and <=0.2 s.
   Inventory removal and `grenade_thrown` occur at projectile spawn.
   The hand stays busy for its clip (0.77 s overhand, 0.50 s underhand),
   then draws the next item. Holding one caps speed at 245 u/s.
   Explicit console/range/bot `throw <class> <strength>` commands still
   request an immediate spawn; they do not simulate pulling a pin.
   The [Xbox lineup regression](../research/grenade-jump-lineup-2026-10-02.md)
   catches a late snapshot that previously left the smoke below the box.
   The [mid-door regression](../research/grenade-sky-clipping-2026-10-02.md#mid-door-landing-reference)
   previously reached the open door top for a quarter-tick jump; the new
   movement misses that landing, so exact CS2 lineup parity remains open.
   The [subtick audit](../research/grenade-subtick-snapshot-2026-10-03.md)
   verifies that CS2 uses segment time and explicitly splits movement at the
   snapshot deadline. The port now implements it, together with the ordinary
   jump's gravity correction, at Sid's request for local playtest. General
   jump feel and the mid-door landing remain to be assessed before merge.
3. **Your view (`player_view.gd` or the HUD):** a `FlashOverlay` with your
   userid, on top of the HUD *(done on dust2 2026-09-23)*. The flashed ringing is a sound (below).
   Practice and the test range also enable `GrenadeTrail`: a green overlay
   follows the actual flight, with orange dots at contacts, visible through
   geometry. Completed paths remain for eight seconds and fade during the
   last two. Only the last eight throws are retained; round starts clear
   them. Trail tips use the grenade model's interpolation, and completed
   segments include actual tick contact points. No prediction or extra
   physics queries are performed. Competitive play omits trails by default;
   `--grenade-trails` enables them, and `--no-grenade-trails` disables them
   for ordinary play or performance comparisons.
4. **`bot.gd`: sight.** *(Done 2026-09-24, except keeping out of fire:
   `Bot.can_see` and `Bot.is_blind`, blinded past 0.7; blinded, it fires
   where it last saw the one it was engaging, or backs off; checks in
   `tests/run_bot_sight_checks.gd`.)* `can_see` adds two checks after its wall trace:
   no sight when `game.query(&"smoke_length_between", [eyes, theirs], 0.0)`
   is over `GrenadeRules.BOT_MAX_VISIBLE_SMOKE_LENGTH`, and none (or firing
   wide) while `game.query(&"blind_share", [userid], 0.0)` is over a share
   (0.7 is where CS2 counts a blind kill; the bots' own threshold is a
   choice). Keeping out of fire asks
   `game.query(&"burning_at", [point], false)`.
5. **The kill feed's marks.** *(Done 2026-09-28, #140: `KillCredit`,
   `src/game/kill_credit.gd`, fills each `player_death` as it is sent; the
   rules are in `reference/systems/contracts.md`, player_death.)*
   `thrusmoke`, for a gun's kill, asks `smoke_length_between` from the
   killer's eyes to the victim's chest (more than zero is through smoke),
   and `attackerblind` is the killer's `blind_share` at 0.7 or more. A flash
   assist goes only where no enemy did the 25 damage of an assist: to the
   victim's last flasher, if an enemy of theirs and not the killer, while
   the victim is still under it.
6. **The map importer (done 2026-10-02):** `grenadeclip` shapes are retained
   in a separate `GrenadeClip` body on layer 32. They stop grenade queries,
   are excluded from camera occluders, and leave player clips on layer 8.
   `physics_sky` brushes retain their separate conditional interaction on
   layer 64. They do not bounce grenades: [the sky clipping follow-up](../research/grenade-sky-clipping-2026-10-02.md)
   verifies the installed mask and the second T-spawn screenshot's bad bounce.
   Recorded Dust2 lineup comparison remains Local work.
7. **Sounds (done 2026-09-28, playtest issue 19):** `GrenadeSounds`
   (`src/audio/grenade_sounds.gd`) plays every grenade event through CS2's
   own sound events (`reference/sounds/`): the throw, the bounce, the
   bottle in flight, each detonation with its distant layer, the fire's
   loop, ignites, fade and hiss, the smoke's clearing, and a decoy's gunfire
   as the gun it imitates; `FlashMuffle` the flashed ringing and muffle;
   `HitSounds` the burn. Left Local: the listen beside CS2
   (`reference/playtest-2026-09-25.md` issue 19, step 5).
8. **The HUD:** `WeaponSelection` shows the carried grenade slot row;
   ground grenades use the shared E pickup prompt (PR #163). The lineup
   crosshair (held 2 s) remains open.
