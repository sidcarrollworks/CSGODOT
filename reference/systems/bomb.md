# The bomb

The C4 as CS2 has it, built as server-side state in `src/bomb/`, and what
the files it does not own need, to wire it into the match and dust2. Roadmap
item 16; `reference/cs2-systems.md` section 6 has CS2's rules.

## What is built

| File | What it is |
|---|---|
| `src/bomb/c4.gd` (`C4`) | The bomb's state, stepped once a tick after the players: carried, dropped, planting, planted and counting, defusing, defused, exploded. Knows players only as userids and what each did that tick (`C4.Actor`). Sends CS2's events and one damage record per player the blast reaches. `save_state()` and `load_state()` copy it whole; every timer is a deadline in simulation microseconds. |
| `src/bomb/c4_rules.gd` (`C4Rules`) | Its numbers (below). |
| `src/bomb/bomb_site.gd` (`BombSite`) | A place it can be planted: a map's `func_bomb_target` (`BombSite.from_volumes(BrushVolume.bomb_sites(...))`) or a box. |
| `src/bomb/c4_view.gd` (`C4View`) | What is seen and heard: the bomb on the ground, its light blinking with each beep, the beeps, the blast. Reads a `C4` per frame, never changes it. CS2's model and sounds when extracted, a tan box and silence when not. |
| `src/bomb/bomb_system.gd` (`BombSystem`) | The bomb as one of the game's systems: joins `C4` to the roster, inventories, commands, events, entities and `DamageInfo` (below). |
| `tests/run_bomb_checks.gd`, `tests/run_bomb_system_checks.gd` | Their checks, and a plant on the test range. |

The test range carries it: you hold it from the start, site A is marked on
the floor behind the spawn, 5 takes it out and the attack button held on
the site plants, E held looking at it defuses, L gives or takes the kit,
and O, the range's reset, hands you another. You plant as a T and defuse
as a CT. Its blast is dust2's (700).

## The numbers

| | Value | Where from |
|---|---|---|
| Timer | 40 s | `mp_c4timer` |
| Defuse | 10 s, 5 s with a kit | CS2 |
| Blast | `bombradius` at the bomb (500 by default, 700 on dust2), reaching 3.5 times that, falling off as a bell curve with a third of the reach as its standard deviation; walls do not shield | The rule before the July 2026 shockwave: cs2-systems.md; the curve is the community's published formula for CS:GO's C4 |
| Plant | 3.0 s held | **Guess**: CS:GO's arming time and the community's CS2 figure; cs2-systems.md says "about 3.2 s". C1 measures it |
| Defuse reach | eyes within 90 units of the bomb, aim within 40 degrees of it | **Guess**, C1 |
| Pickup | a terrorist's feet within 24 units across and 54 up or down | **Guess** from the hull's size: CS2 picks it up on touch |
| Dropping it | lands at the dropper's feet; they cannot pick it back up for 1 s | **Guess**: CS2 throws it clear |
| Beeps | once a second at the plant, closing in steadily to ten a second at the end | **Guess**, C1 |
| Sounds | `sounds/weapons/c4/c4_beep*` and `c4_explode*` | **Guessed** from CS:GO's names; the extraction's `c4/` folder is not listed in `reference/weapons/sounds.md` yet |

Not built: CS2's July 2026 shockwave (walls block it, corners weaken it,
damage baked per map in `baked_bomb_damage.vdata`, whose values C2 has not
decoded). `BombSite.damage_power` keeps each site's `bomb_damage_power` for
it.

## Its rules, as the checks hold them

- Only a terrorist carrying it plants it: holding attack with it in hand,
  on the ground, inside a site. Letting go, leaving the ground or leaving
  the site aborts the plant and loses it. It cannot be dropped mid-plant.
- The planter and the defuser are held still (`C4.holds_still(userid)`).
- Planted, it goes off 40 s later unless defused. A living CT on the ground,
  close and looking at it, holding use, defuses it; one at a time, the
  nearest first. Letting go, jumping or dying aborts the defuse, which then
  starts over. A defuse that would end after the bomb goes off loses to it.
- The carrier dying drops it where they fell; a living T touching it picks
  it up; a CT never does.
- The blast reaches every living player, the planter and their team included,
  with no team damage scaling.

## Wiring it in

`BombSystem` (`src/bomb/bomb_system.gd`) is the bomb's system on the shared
contracts (`reference/systems/contracts.md`), checked in
`tests/run_bomb_system_checks.gd`. Added to the world's game
(`world.game.add_system(BombSystem.new(sites, rules))`), it runs on the
GameWorld's tick after the players and the match, and:

- builds a `C4.Actor` for each player on the roster: plant is the command's
  attack held with `weapon_c4` in hand (`inv.in_hand_class()`), use is
  `UserCmd.USE`, the kit is `inv.has_defuser`;
- takes the `drop` command when the C4 is in hand (`ItemDrops` takes it for
  anything else, and `Inventory.drops_on_death()` leaves the C4 to the
  bomb);
- sends the C4's events on `game.events`, `bomb_dropped` with its entity's
  id;
- keeps `weapon_c4` in the carrier's inventory, out of it once dropped or
  planted, back in on a pickup, and the bomb on the ground as a
  `"weapon_c4"` or `"planted_c4"` `SimEntity`;
- deals the blast as a `DamageInfo` per player: no attacker (CS2 credits
  a bomb death to nobody: the kill feed shows the C4 alone), inflictor `"planted_c4"`, weapon `"weapon_c4"`, `DMG_BLAST`, no zone,
  armour as a grenade's (`armor_penetration` 0.5), no team scaling;
- hands the bomb on `round_start` to a random living terrorist (seeded from
  the tick): a human one when there is one, since competitive sets
  `bot_defer_to_human_items 1` (`C4Rules`, `BombSystem.may_be_given`, read
  from `PlayerSim.is_bot`); a bot only on a side of bots. While a human T
  lives, bots also leave a dropped bomb for them (seen in CS2 by Sid,
  2026-09-26; playtest-2026-09-25.md issue 18). It allows plants from `round_freeze_end` to `round_end`, and
  clears it on `round_prestart`. With no match (the range) plants are
  always allowed.

The test range adds one to `test_range.game`. It reads your command as a
match's would, and adds only the side you plant or defuse as (a terrorist
until it is down, then a counter-terrorist), wrapping the default
`BombSystem.input_of`.

### `player_sim.gd` and `PlayerInput` *(done)*

- Held still while planting or defusing, as freeze time holds it: no
  moving, jumping or firing, free to look and crouch. The bomb answers the
  game's `holds_still` query (`game.query(&"holds_still", [userid], false)`),
  which `player_sim.gd` reads beside `frozen`, the match's, and keeps as
  `held_still` for the view (the plant clip).
- The bomb in hand fires nothing: attack with `weapon_c4` in hand is the
  plant, once the bomb is drawn (`m_flDeployDuration`, 1.23 s;
  `PlayerSim.hand_ready`).
- `PlayerInput` sets `UserCmd.USE` from E and sends `drop` on G; 5 selects
  the bomb.

Not done yet, in files this does not edit (`match_state.gd` and
`de_dust2.gd` done 2026-09-23, as below):

### `match_state.gd` *(done 2026-09-23)*

- **Handing it out** is the bomb system's, from the match's `round_prestart`,
  `round_start`, `round_freeze_end` and `round_end` events, which the
  match sends. Warmup sends no `round_start`, so it has no bomb.
- **The clock.** From `bomb_planted` the round's time no longer ends the
  round (the HUD showing the bomb's, `bomb.seconds_left`, is still to do).
  Time running out with the bomb not down is a CT win (`TIME_RAN_OUT`,
  "TargetSaved"), a plant in progress included.
- **Who wins, once it is down:**
  - `bomb_exploded`: Ts, `BOMB_EXPLODED` ("TargetBombed").
  - `bomb_defused`: CTs, `BOMB_DEFUSED` ("BombDefused").
  - Every CT dead: Ts at once (`CT_ELIMINATED`); the bomb keeps counting.
  - Every T dead: nothing yet. The CTs still have to defuse it, or lose
    when it goes off.
- **After the round.** A bomb still counting goes on counting through the
  pause and can go off and hurt people, but it no longer decides anything;
  the next round's start resets it (`bomb.reset()`) and removes its
  entity. A defuse or an explosion after the round is decided changes
  nothing in the score.

### Money (the "Buying and money" thread)

From cs2-systems.md section 2: $300 to the planter on `bomb_planted`, $300
to the defuser on `bomb_defused`, $3,500 a head for a round won by the bomb,
and $600 a head on top of the loss bonus to Ts who planted and lost. A kill
by the blast earns nobody anything: its `player_death` has no attacker, so
the C4's $300 `m_nKillAward` in vdata is never paid. That is from memory of
CS2's kill feed, not measured; C1 can confirm it.

### `de_dust2.gd` *(done 2026-09-23)*

- `world.game.add_system(BombSystem.new(sites, rules))` with the sites from
  `BombSite.from_volumes(BrushVolume.bomb_sites(entities, root))` and
  `rules.bomb_damage = SourceEntities.bomb_radius(entities)` (700); with no
  sites extracted there is no bomb, and the map says so.
- A `C4View` reading `bomb_system.bomb`, as the range adds one.

### Bots (`bot.gd`, later)

The carrier walks to a site and plants; a CT hears `bomb_planted` and goes
to defuse. The events carry what they need.

### The HUD

The carrier's icon, the planted state and the bomb's clock in place of the
round's, the defuse bar (`bomb.defuse_progress`), and "you are in a bomb
zone" from `enter_bombzone`. The range's readout shows the same for now.
