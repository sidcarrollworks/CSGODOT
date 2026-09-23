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
| `tests/run_bomb_checks.gd` | Its checks, and a plant on the test range. |

The test range carries it: you hold it from the start, site A is marked on
the floor behind the spawn, 5 held on the site plants, E held looking at it
defuses, L gives or takes the kit, and 5 again after it is spent hands you
another. You plant as a T and defuse as a CT. Its blast is dust2's (700).

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

Nothing here edits `player_sim.gd`, `bot.gd`, `match_state.gd` or
`de_dust2.gd`, which the GameWorld's work owns, nor the shared `UserCmd`.
This is what they need.

### A bomb system on the shared contracts

The contracts (`reference/systems/contracts.md`, `src/game/`, from the
"Events, damage and items" thread) were drafted while this was built, and
their code is not on `main` yet. `C4` is kept free of them so it runs and is
checked on its own; a small `BombSystem` (RefCounted, `tick(t: SimTick)`,
`attach(game)`) joins the two once `src/game/` lands:

- Each tick, one `C4.Actor` per player in `game.roster`:
  `C4.Actor.of_player(player, userid)`, then
  - `plant_held`: the command holds `UserCmd.ATTACK` and
    `inv.in_hand_class() == "weapon_c4"`, the draw (`m_flDeployDuration`,
    1.23 s) finished, and the match is live;
  - `use_held`: the command holds use (a new `UserCmd.USE` bit, E);
  - `drop`: the command asks to drop with the bomb in hand (CS2's G);
  - `has_kit`: `inv.has_defuser`.
- `C4.tick(t.now_usec, actors, sites)`, then every event from
  `take_events()` into `game.events.send(name, fields)` (the names and keys
  are the schema's: `player_given_c4`, `bomb_pickup`, `bomb_dropped`,
  `bomb_beginplant`, `bomb_abortplant`, `bomb_planted`, `bomb_begindefuse`,
  `bomb_abortdefuse`, `bomb_defused`, `bomb_exploded`, `enter_bombzone`,
  `exit_bombzone`).
- Every record from `take_blast()` as a `DamageInfo`: attacker the planter,
  inflictor `"planted_c4"`, weapon `"weapon_c4"`, `DMG_BLAST`, no zone, the
  amount, origin the bomb, position the victim's middle, armour as a
  grenade's (`armor_penetration` 0.5), dealt with `DamageInfo.deal`.
- The inventory follows the bomb: `bomb_dropped` and `bomb_planted` take
  `weapon_c4` out of the carrier's inventory, `bomb_pickup` puts it in.
- The dropped and planted bomb as `SimEntity`s (`"weapon_c4"`,
  `"planted_c4"`) for the presenters and `bomb_dropped`'s `entindex`.

### `player_sim.gd`

- Held still while planting or defusing, as freeze time holds it: no
  moving, jumping or firing, free to look and crouch. A flag beside
  `frozen` (`held_still = bomb.holds_still(userid)`), set by the
  GameWorld before the player runs.
- The bomb in hand fires nothing: attack with `weapon_c4` in hand is the
  plant.
- `UserCmd` gains `USE` (E) and a drop request (G); `PlayerInput` fills
  them.

### `match_state.gd`

- **Handing it out.** At each round's start, one random terrorist (from the
  match's seeded numbers) gets `weapon_c4` in their inventory and
  `bomb.give_to(userid, spawn)`, which sends `player_given_c4`. No
  terrorist, no bomb (`bomb.reset()`). Warmup has no bomb.
- **Planting only while live.** Freeze time holds everyone already; after
  the round is won nobody plants.
- **The clock.** From `bomb_planted` the round's time no longer ends the
  round: the HUD shows the bomb's (`bomb.seconds_left`). Time running out
  with the bomb not down is a CT win (`TIME_RAN_OUT`, "TargetSaved"), a
  plant in progress included.
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
and $600 a head on top of the loss bonus to Ts who planted and lost. Whether
a kill by the blast earns the planter the C4's $300 kill award
(`m_nKillAward` in vdata) is open: C1 can check it.

### `de_dust2.gd`

- The sites: `BombSite.from_volumes(BrushVolume.bomb_sites(entities, root))`.
- The blast: `C4Rules.bomb_damage = SourceEntities.bomb_radius(entities)`
  (700).
- A `C4View` for the bomb, as the range adds one.

### Bots (`bot.gd`, later)

The carrier walks to a site and plants; a CT hears `bomb_planted` and goes
to defuse. The events carry what they need.

### The HUD

The carrier's icon, the planted state and the bomb's clock in place of the
round's, the defuse bar (`bomb.defuse_progress`), and "you are in a bomb
zone" from `enter_bombzone`. The range's readout shows the same for now.
