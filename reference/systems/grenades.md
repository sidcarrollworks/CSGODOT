# Grenades

CS2's six grenades as server-side state, built on the shared contracts
(`reference/systems/contracts.md`: game events, `DamageInfo`, items by
class name, `SimEntity`). Roadmap items 17 to 20; `reference/cs2-systems.md`
section 7 has CS2's rules. This page says what is built, what each number
rests on, what it costs a tick, and what the files it does not own need to
do to wire it in.

## What is built

All in `src/grenades/`, checked by `tests/run_grenade_checks.gd`.

| File | What it is |
|---|---|
| `grenade_rules.gd` | Every number: the game's from `vdata.csv` (damage, reach, armour ratio, throw speed), the rest marked with the measurement that settles it |
| `grenade_flight.gd` | The throw (three strengths, the thrower's velocity, the release point) and the flight: 40% gravity, a sphere of radius 2 swept each tick, bounces keeping 45%, a floor leaving it under 20 u/s puts it down |
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

- **HE.** Goes off 1.5 s after the throw. 99 at the centre, falling along a
  bell curve to nothing at 350 (CS:GO's documented curve; G2), to anyone
  with a clear line from the blast to their middle, eyes or feet. `DMG_BLAST`,
  no zone, armour ratio 1.2 (kevlar lets 60% through). Clears the smoke
  within 128 units for 3 s.
- **Flashbang.** Goes off 1.5 s after the throw. Blinds anyone whose eyes it
  can see, the thrower and teammates too: up to 4.87 s looking at it close
  up, falling off past 250 units to nothing at 2000, less side-on, a fifth
  with your back to it. Held white, then fading over the last 3 s; seen
  weakly, grey rather than white. `player_blind` for each. Smoke does not
  stop it (as in CS:GO).
- **Smoke.** Pops at the first check (every 0.2 s from the throw) at which
  it lies still. 1,600 cubes of 16 units, about 300 across and 130 tall in
  the open, grown over 1 s, lasting 18 s. A fire it pops in goes out whole;
  flames it grows over go out one by one, and a fire cannot spread into it.
  A round cuts a tunnel that closes in a quarter of a second (from
  `bullet_impact`: the shooter's eyes to where it landed).
- **Molotov and incendiary.** Break on ground no steeper than 30 degrees, or
  in the air 2 s after the throw, the fire then falling on ground up to 128
  below. Into smoke they fizzle. The fire spreads a flame every 0.2 s
  (the incendiary every 0.02 s), burns 7 s (5.5 s), and hurts anyone
  standing within 30 units of a flame: 40 a second in 0.2 s steps, ramping
  from half to all of it over the first second in it. `DMG_BURN`, armour
  neither softens it nor wears. Credited to the thrower for as long as it
  burns, except that burns on the thrower's teammates are the thrower's only
  for the first 6 s and nobody's after (`inferno_friendly_fire_duration`).
- **Decoy.** Once still, fires its thrower's primary (else pistol) in bursts
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

CS:GO behaviour as documented by the community, for G1 to check: the throw
(750 x 0.9, times 0.3 to 1 by strength; 1.25 of your velocity; lifted 10
degrees at the horizon; 22 ahead, 12 lower for a lob), 40% gravity, 45%
kept per bounce (30% of that off a player), resting under 20 u/s on a floor,
the 1.5 s fuse, the 0.2 s check for a still smoke or decoy, the HE's bell
curve.

Guesses, each to be measured: the molotov's air-burst drop (G1), the fire's
spread interval for the molotov, its 30-unit reach and its ramp; the HE's
smoke hole and the round's tunnel (G4); the smoke's size, shape and 18 s
(G4); every flash figure (G3); the decoy's bursts and pop (G5).

## What a tick costs

Counted in the checks, for the performance rules:

- A grenade in flight: one shape cast a tick, and one more (and a rest-info
  query) for each surface it meets, at most four sweeps.
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

1. **dust2's `GameWorld`** adds the system to its game, as the range does:
   `world.game.add_system(GrenadeSystem.new())`, and a `GrenadeView` that
   `watch`es the game. At a round's start the entities
   are cleared (`entities.clear()`, as the contract says) and the system's
   blinding with them (`GrenadeSystem.clear()`). In a match,
   `team_damage_scale = GrenadeRules.TEAM_DAMAGE_IN_MATCH`.
2. **`player_sim.gd`: the throw from the hand.** *(Done: `_update_grenade`,
   with the throw at the release and the hand busy for the throw clip's
   length, 0.77 s overhand and 0.50 s underhand, before what is next is
   drawn.)* With a grenade in hand
   (`Inventory.in_hand_class()`), the attack buttons pull the pin and the
   release throws: the strength is from the buttons held at the release
   (`GrenadeRules.strength_for(left, right)`, from `UserCmd.ATTACK` and
   `UserCmd.ATTACK2`). The pin can be pulled once
   the draw (1 s) is over. At the release:
   `system.throw(userid, class, strength, space)`, or the command
   `throw <class> <strength>`; it takes the grenade from the inventory
   (`take_one`), refuses with none, and sends `grenade_thrown`. Then back to
   the last weapon. The throw clip's own
   timing (`reference/weapons/equipment.md`: the overhand throw's sound at
   0.07 s) says when after the release it leaves the hand; the throw here is
   at the tick of the command. Holding one caps the speed at 245
   (`WeaponData.max_player_speed` from `ItemRegistry.weapon_data`).
3. **Your view (`player_view.gd` or the HUD):** a `FlashOverlay` with your
   userid, on top of the HUD. The flashed ringing is a sound (below).
4. **`bot.gd`: sight.** `can_see` adds two checks after its wall trace:
   no sight when `game.query(&"smoke_length_between", [eyes, theirs], 0.0)`
   is over `GrenadeRules.BOT_MAX_VISIBLE_SMOKE_LENGTH`, and none (or firing
   wide) while `game.query(&"blind_share", [userid], 0.0)` is over a share
   (0.7 is where CS2 counts a blind kill; the bots' own threshold is a
   choice). Keeping out of fire asks
   `game.query(&"burning_at", [point], false)`.
5. **The kill feed's marks:** whatever fills `player_death.thrusmoke` asks
   `smoke_length_between` from the attacker's eyes to the victim (more than
   zero is through smoke), and `attackerblind` asks `blind_share` for the
   attacker; `assistedflash` is the last `player_blind` on the victim from
   someone on the killer's side.
6. **The map importer:** grenade clips are left out of the hull today
   (`hull_skip_hints` in `map_importer.gd`). They go on a body of their own
   on `GrenadeRules.GRENADE_CLIP_LAYER` (32), which grenades bounce off and
   nothing else does. Needs a run on Sid's machine with dust2.
7. **Sounds (Local):** the equipment's sounds are extracted (G6) but not
   tabled by name as the guns' are (`reference/weapons/sounds.md`). With a
   table, the view plays the bounce, each detonation, the fire's loop, the
   smoke's hiss and the flashed ringing, and a decoy's gunfire through
   `WeaponSounds` (it has only the AK-47's and M4A1-S's sets now).
8. **The HUD:** the grenade slot row and the lineup crosshair (held 2 s)
   are not built.
