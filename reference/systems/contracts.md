# The shared contracts: events, damage, items

Owned by the "Events, damage and items" thread. The bomb, grenades, and
buying and money build on these three contracts and on nothing of each
other's. Ask for changes through the coordinator; this file is kept current
with every change, and a copy goes in the repo as
`reference/systems/contracts.md`.

Status: built and checked (246 checks) on branch
`claude/game-contracts-vzefcv`, which is merged with PR #50 (the
GameWorld) and fits it; base work on it. Everything lives in
`src/game/`. Names in `code` are the classes and methods as they will be in
the repo.

## The rules every system follows

- Every system is server-side state, stepped on the 64 Hz tick, timed with
  `SimClock` (microseconds of simulation time, never the wall clock), taking
  its input from `UserCmd`s and from other systems' events.
- Systems never call each other. They meet in three places only:
  1. **Game events** (`GameEvents`): what happened, as plain data, with
     CS2's event names and keys.
  2. **Damage** (`DamageInfo`, `DamageInfo.deal`): the one way anything
     hurts a player, carrying who and what did it.
  3. **Items** (`ItemRegistry`, `Inventory`): every item named by its CS2
     class name, and what each player carries.
- Players are named by a `userid` (an int, see Roster below), never by a
  node, in anything that is sent, stored or compared. -1 is nobody (the
  world).
- Drawing and sound only read state and listen to events. Anything only seen
  or heard runs per frame, not per tick. Nothing reads the disk during a
  tick (the registries load once, before play). A cache hands out copies.

## 1. Game events

`GameEvents` is one queue per game. Simulation code sends named events into
it during the tick; at the end of the tick the owner of the tick calls
`flush()`, which hands every queued event, in the order sent, to its
listeners. An event sent by a listener during `flush()` is handed out in the
same flush, after the ones already queued, so a chain (a death, then the
money for it) settles within one tick.

One flush comes earlier: a round's start (`MatchState._start_round`)
hands out `round_prestart` at once, so the ground is cleared and the C4
taken back before anyone spawns. It runs after the players' commands and
before `game.step`, so everything queued so far that tick goes out with it
(the commands' events, `round_officially_ended`), while
`GameSystems.now_usec()` is still the last tick's: a listener that wants
the time takes `event.at_usec`. Anything later in a tick that must not act
past a round's end asks `events.is_pending(&"round_end")` (the bomb does,
so no plant lands on the tick a round ends).

```gdscript
var events := GameEvents.new()
events.send(&"player_death", {"userid": 3, "attacker": 1, "weapon": "weapon_ak47", "headshot": true})
events.listen(&"player_death", func(e: GameEvent) -> void: print(e.fields.attacker))
events.listen_all(callable)          # every event: the kill feed, a recorder, the network later
events.unlisten(&"player_death", callable)
events.flush()                       # the tick's owner, once, at the end of the tick
events.muted = true                  # re-running a tick (prediction): sends are dropped
```

- `GameEvent`: `name: StringName`, `tick: int`, `at_usec: int` (when in the
  tick it happened, for a shot or a detonation; the tick's end if not
  given), `fields: Dictionary` of plain values (int, float, bool, String).
  Listeners must not change `fields`.
- `send(name, fields, at_usec = -1) -> bool`. The name must be in
  `GameEvents.SCHEMA`, and every key in `fields` must be one of that event's
  keys; keys left out take the schema's default. Anything else is refused
  (returns false and prints an error), so the list below stays the truth.
  A new event is a line added to the schema and to this file.
- Listeners are called in the order they were added.

### Value conventions

- `userid`, `attacker`, `assister`: a player's userid; -1 for nobody.
- Teams: `"T"` and `"CT"` (the project's own strings; CS2 sends 2 and 3).
- Items: the full CS2 class name, `"weapon_ak47"`, `"weapon_hegrenade"`,
  `"item_defuser"`. CS2's own `player_death` and `player_hurt` drop the
  `weapon_` prefix; here it is always kept, so every system keys on the
  same string as the registry.
- Bomb sites: `"A"` or `"B"` (CS2 sends the `func_bomb_target`'s entity
  index).
- `entityid`, `entindex`: the id `SimEntities` gave the thing (grenade,
  dropped bomb), -1 for none.
- Positions: `x`, `y`, `z` floats in Source units, as CS2 sends them.
- `round_end.reason`: CS2's round end reason by name: `"TargetBombed"`,
  `"BombDefused"`, `"CTsWin"` (Ts eliminated), `"TerroristsWin"` (CTs
  eliminated), `"TargetSaved"` (time ran out), `"RoundDraw"`.
  `GameEvents.round_end_reason(MatchState.Reason)` converts.
- `hitgroup`: CS2's numbers: 0 generic (a blast, a fall), 1 head, 2 chest,
  3 stomach, 4 left arm, 5 right arm, 6 left leg, 7 right leg.
- Damage amounts (`dmg_health`, `dmg_armor`) and `health`, `armor` are
  ints, as CS2 sends them: rounded from the float the damage worked out.

### The schema (name: keys, defaults 0 / "" / false / -1 for ids)

The names and keys are CS2's game events, written from what CS2 and CS:GO
send; checking them against CS2's own `game.gameevents` is a Local task
for Sid's machine. Keys CS2 has that nothing here can fill yet (xuids,
item ids, pawn handles) are left out.

Players
- `player_spawn`: userid
- `player_team`: userid, team, oldteam, disconnect, silent, isbot
- `player_hurt`: userid, attacker, health, armor, weapon, dmg_health, dmg_armor, hitgroup
- `player_death`: userid, attacker, assister, assistedflash, weapon, headshot, penetrated, noscope, thrusmoke, attackerblind, attackerinair, distance, dmg_health, dmg_armor, hitgroup, dominated, revenge, wipe
- `player_blind`: userid, attacker, entityid, blind_duration
- `player_jump`: userid
- `player_footstep`: userid
- `player_falldamage`: userid, damage

Weapons
- `weapon_fire`: userid, weapon, silenced
- `weapon_fire_on_empty`: userid, weapon
- `weapon_reload`: userid
- `weapon_zoom`: userid
- `bullet_impact`: userid, x, y, z

Items
- `item_purchase`: userid, team, loadout, weapon
- `item_pickup`: userid, item, silent
- `item_remove`: userid, item
- `item_equip`: userid, item, canzoom, hassilencer, issilenced, weptype
- `ammo_pickup`: userid, item, index
- `enter_buyzone` / `exit_buyzone`: userid, canbuy
- `buytime_ended`: (none)

Rounds and the match
- `round_prestart`, `round_poststart`, `round_freeze_end`, `round_officially_ended`, `begin_new_match`, `round_announce_warmup`, `warmup_end`, `start_halftime`, `cs_win_panel_match`: (none)
- `round_announce_match_start`, `round_announce_last_round_half`, `round_announce_match_point`, `round_announce_final`: (none); what CS2 announces of a round as it starts, sent after `round_start` (`MatchState.announce_round`; the moment is inferred from their names)
- `round_start`: timelimit, fraglimit, objective
- `round_end`: winner, reason, message, legacy, player_count, nomusic (`nomusic` set: no round-end music, the action goes on)
- `round_mvp`: userid, reason, value, nomusic
- Every round event here, with these keys, is CS2's: its `core.gameevents`,
  `mod.gameevents` and `game.gameevents`, which GameTracking-CS2 keeps as
  text (read 2026-09-24).
- `announce_phase_end`: sent as every half's last round ends: half time,
  regulation into overtime (no swap there), and each overtime half. What
  follows a half (the swap, the money) comes at the next round's start
  (`round_prestart`). Half time, and each overtime half's swap, sends
  `start_halftime` after it. A new match is `begin_new_match`, warmup
  `round_announce_warmup`, and its end `warmup_end`. Whether the half
  starting is overtime is known from the round count against `MatchRules`
  (money does this itself).
- The match's order at a round's start, CS2's: `round_officially_ended`
  (after a round's end), `round_prestart`, handed out at once so the
  ground is cleared and the C4 taken back before anyone spawns, then the
  swap and the spawns, then `round_start` and `round_poststart`.

The bomb (as the bomb thread asked, with CS2's `entindex` added to `bomb_dropped`)
- `player_given_c4`: userid
- `bomb_pickup`: userid
- `bomb_dropped`: userid, entindex
- `bomb_beginplant` / `bomb_abortplant` / `bomb_planted`: userid, site
- `bomb_begindefuse`: userid, haskit
- `bomb_abortdefuse`: userid
- `bomb_defused` / `bomb_exploded`: userid, site
- `enter_bombzone` / `exit_bombzone`: userid, hasbomb, isplanted
- `defuser_dropped`: entityid
- `defuser_pickup`: entityid, userid
- No `bomb_beep`: the beeps follow from the plant time, so whatever plays
  them works them out per frame.

Grenades
- `grenade_thrown`: userid, weapon
- `grenade_bounce`: userid, x, y, z
- `hegrenade_detonate`, `flashbang_detonate`, `smokegrenade_detonate`, `smokegrenade_expired`, `decoy_started`, `decoy_detonate`, `decoy_firing`: userid, entityid, x, y, z
- `molotov_detonate`: userid, x, y, z
- `inferno_startburn`, `inferno_expire`, `inferno_extinguish`: entityid, x, y, z

## 2. Damage

Every source of damage (bullets, the knife, the Zeus, HE, fire, the bomb,
falling) fills one `DamageInfo` and calls `DamageInfo.deal`. The victim's
`HitTarget.take_damage(info)` applies armour, fills in what happened, and
`deal` sends `player_hurt`, and `player_death` if it killed.

```gdscript
var info := DamageInfo.new()
info.attacker = thrower_id            # userid, -1 for the world
info.inflictor = "hegrenade_projectile"   # the entity that did it
info.weapon = "weapon_hegrenade"      # the item credited: kill award, kill feed
info.damage = 57.0                    # before armour; after range, hit group, walls, team scale
info.damage_type = DamageInfo.DMG_BLAST
info.origin = grenade_position        # where it came from
info.position = victim_centre         # where it landed
info.direction = (victim_centre - grenade_position).normalized()
info.armor_penetration = 0.5          # the share of damage armour lets through
DamageInfo.deal(victim_hit_target, info, events)   # events may be null
if info.killed: ...
```

Fields the source fills:
- `attacker: int`, `inflictor: String` (entity class: `"weapon_ak47"`,
  `"hegrenade_projectile"`, `"inferno"`, `"planted_c4"`, `"worldspawn"` for
  a fall), `weapon: String` (item class credited, `""` for the world).
- `damage: float` before armour, with everything else already applied.
  Team damage scaling is the source's job (bullets get CS2's third in a
  match; the bomb ignores it).
- `damage_type: int`: Source's bits, `DMG_GENERIC 0`, `DMG_BULLET 2`,
  `DMG_SLASH 4`, `DMG_BURN 8`, `DMG_FALL 32`, `DMG_BLAST 64`,
  `DMG_SHOCK 256`.
- `zone: StringName` (`&"head"`, `&"chest"`, `&"stomach"`, `&"arm"`,
  `&"leg"`, or `&""` for none) and `side` (`&"left"`, `&"right"`, `&""`);
  `hitgroup` is worked out from them (0 when there is no zone).
- `origin`, `position`, `direction: Vector3`; `at_usec: int` (sim time).
- `armor_penetration: float` (a gun's `WeaponData.armor_penetration`, the
  game's armour ratio halved), `armor_wear: float = 0.5` (armour points lost
  per point it absorbs, as `HitTarget` does now).
- `walls: int` gone through; `headshot` follows from the zone.

Filled by the victim: `victim` (its userid), `health_taken`, `armor_taken`,
`armored`, `health_left`, `armor_left`, `killed`.

- Armour covers every zone but the legs; the head only with a helmet. A
  hit with no zone (a blast, fire) is armoured whenever there is armour.
  Falling ignores armour (`DMG_FALL`), as in CS2.
- A death carries its killing record: `HitTarget.killing_damage`, beside
  `HitTarget.last_damage` for every hit. The existing `died` signal and the
  `last_hit_*` fields stay, filled from the record, until the local agent's
  GameWorld moves `player_sim.gd` onto the record.
- Bullets go through it now: `Hitscan.fire_as(space, shot, data, shooter)`
  takes a `Hitscan.Shooter` (userid, team, team damage scale, the RIDs to
  leave out, the events queue) and sends `bullet_impact` for each surface
  it meets. `Hitscan.fire_at` keeps its signature and calls it with nobody
  as the shooter.
- `player_death` is sent with what the record knows (attacker, weapon,
  headshot, penetrated, noscope, distance, hitgroup, damage; noscope is
  a round from a scoped gun fired unscoped, `Weapon.Shot.noscope`).
  Assists, flash assists, through smoke and blind attackers are filled by
  whoever knows them later (a kill-credit system listening to
  `player_hurt`, the grenades' smoke query).

## 3. Items and inventories

### The registry

`ItemRegistry` holds every item by CS2 class name, loaded once from
`reference/weapons/vdata.csv` (price, kill award, slot, type, weight,
deploy time, ammo) and `reference/weapons/models.md` (display name, model,
clip sets), plus the few things neither carries (team, grenade limits,
kevlar and the kit), written by hand from `reference/cs2-systems.md`.

```gdscript
var ak: ItemDef = ItemRegistry.item("weapon_ak47")
ak.price           # 2700
ak.kill_award      # 300
ak.slot            # ItemDef.Slot.PRIMARY
ak.team            # "T"
ItemRegistry.has("weapon_ak47")
ItemRegistry.all()                    # a copy, in CS2's order
ItemRegistry.guns()                   # the 34 guns
ItemRegistry.load_all()               # reads everything, before play (GameSystems.new() calls it)
ItemRegistry.buyable("CT")            # what a CT may buy
var data: WeaponData = ItemRegistry.weapon_data("weapon_mp9")   # a copy of the gun's WeaponData, built before play
```

`ItemDef` fields: `item_class`, `name` (CS2's English name), `slot`
(`PRIMARY 0`, `PISTOL 1`, `KNIFE 2`, `GRENADE 3`, `C4 4`, `EQUIPMENT -1` for
kevlar, helmet and kit), `slot_position` (the Zeus sits beside the knife),
`type` (`"pistol"`, `"smg"`, `"shotgun"`, `"rifle"`, `"sniper"`,
`"machinegun"`, `"knife"`, `"taser"`, `"grenade"`, `"c4"`, `"equipment"`),
`price`, `kill_award`, `team` (`""` for both), `max_carried` (2
flashbangs, otherwise 1), `grenade_group` (the molotov and incendiary share
`"firebomb"`), `weight` (CS2's `m_iWeight`, which picks the best gun),
`deploy_seconds`, `max_speed`, `buyable`, `droppable` (not the knife),
`is_gun`, `silenced_by_default` (M4A1-S, USP-S).

Items: the 34 guns, `weapon_knife`, `weapon_taser`, the six grenades
(`weapon_hegrenade`, `weapon_flashbang`, `weapon_smokegrenade`,
`weapon_molotov`, `weapon_incgrenade`, `weapon_decoy`), `weapon_c4`,
`item_kevlar` ($650), `item_assaultsuit` ($1,000), `item_defuser` ($400,
CT). The helmet on its own (commonly $350 on kevlar) is a buying rule, not
an item; the buying thread decides it (E2 in cs2-systems.md is its
measurement).

### The inventory

One `Inventory` per player: what they carry, what is in hand, armour and
the kit. It checks the carrying rules and nothing else; money, buy zones,
buy time and team restrictions are buying's to check before it calls `add`.

```gdscript
var inv := Inventory.new(userid, hit_target)   # hit_target holds armour; null in tests
inv.can_add("weapon_flashbang")   # Inventory.OK, REPLACES (slot taken; add hands back what it replaced), or FULL
var replaced: Array[Inventory.Entry] = inv.add("weapon_ak47")    # for the dropped-weapon entity
inv.add("weapon_ak47", picked_up_weapon)      # a picked-up gun keeps its ammo
inv.has("weapon_c4"); inv.count("weapon_flashbang")
inv.item_in(ItemDef.Slot.PRIMARY)  # the Entry in a slot, or null; items_in(slot) for grenades
inv.entries()                    # a copy of every Entry
inv.in_hand()                    # the Entry held; inv.in_hand_class() -> "weapon_c4"
inv.select("weapon_c4"); inv.select_slot(ItemDef.Slot.GRENADE); inv.select_last()
inv.take_one("weapon_hegrenade") # a throw: one fewer, gone at none; false if none
var e: Inventory.Entry = inv.remove("weapon_c4")   # dropping or planting it
inv.armor; inv.helmet; inv.has_defuser
var dropped := inv.drops_on_death()   # takes out and returns what falls
inv.strip()                          # everything gone (a death, a new match)
inv.give_starting_items("T")         # knife and the side's pistol
var saved := inv.save_state(); inv.load_state(saved)
```

- `Inventory.Entry`: `item: ItemDef`, `weapon: Weapon` (a gun's own
  instance, so ammo and recoil survive switching and dropping; null for
  anything else), `count` (grenades).
- Carrying rules (CS2): one primary, one pistol, the knife, the Zeus; four
  grenades at most, two of them flashbangs, one of each other kind, one of
  the molotov and incendiary; one C4; kevlar tops armour up to 100, the
  suit also gives the helmet, and either is FULL when there is nothing to
  add; one kit.
- Armour and the kit live on the player, as CS2 keeps them on the pawn:
  armour points and the helmet on the player's `HitTarget` (which damage
  wears down), the kit beside them. The inventory is the one way to read
  and change them: `armor` and `helmet` read and write the `HitTarget`
  when one was given (their own fields when not, in tests), and adding
  `item_kevlar`, `item_assaultsuit` or `item_defuser` sets them rather than
  filling a slot.
- Dropped on death (CS2's `mp_death_drop_gun 1`, `mp_death_drop_grenade`,
  `mp_death_drop_defuser`, `mp_death_drop_taser`): the best gun (primary,
  else pistol), the grenade in hand or else the best one (best is a guess:
  the firebomb, HE, smoke, flash, decoy), the Zeus and the kit.
  `drops_on_death()` leaves the C4 out: the bomb system takes it and drops
  it itself when its carrier dies. A dead player's inventory keeps the
  rest until they next spawn (`strip()` then), so every system hearing
  `player_death` still sees what they carried.
- Starting items: the knife, and the Glock-18 for T or the P2000 for CT
  (CS2's `mp_t_default_secondary` and `mp_ct_default_secondary`, and the
  default loadout's first pistol place; the USP-S is the CT alternative
  once there is a loadout page). No armour (`mp_free_armor 0`,
  `MatchRules.free_armor`).
- Nothing here sends events; the system that caused the change does
  (`item_purchase`, `item_pickup`, `bomb_dropped`, `grenade_thrown`).
- `item_remove` {userid, item} is sent once, by whoever takes the item out
  of the inventory, and for nothing else: `ItemDrops` for `drop`, the shop
  for `sellback` and for the gun a purchase replaces. `DroppedItem.drop`
  only puts a thing on the ground and announces nothing, so a drop is
  never announced twice. A death sends `player_death` and no
  `item_remove` for what falls (the kit alone also gets `defuser_dropped`).

### Items on the ground

`DroppedItem` (a `SimEntity`, class the item's own: `"weapon_ak47"`,
`"item_defuser"`) holds the carried `Inventory.Entry`, so a gun keeps its
ammo, and a `basis` (the world model's axes: +Z the muzzle, +Y the top) and
spin; it flies under gravity, turning (one ray a tick while it moves),
bounces off the world, and rests; drawn, it lies on its thinnest side the
way it was heading (`DroppedItemView`). `DroppedItem.drop(game, userid,
entry, velocity)` puts one on the ground at a player's middle: buying uses
it for the gun a purchase replaced. `DroppedItem.drop_from(game, userid,
entry, from, velocity, spin)` starts it from a transform: a drop and a
death let the gun in hand go from the hand as it was held
(`HeldPose.of(node, item_class)`: CS2's hold, level, measured from its
third-person clips, turned with the view's pitch as CS2's AimCS bends the
upper body with the aim (`reference/research/hitboxes-aim.md`; how far and
about what point is a stand-in until measured), from the player's
position, view and crouch alone, never an animated bone), at 300 u/s
where they look, a little lifted, with their own motion;
a death with the body's motion as it died (`PlayerSim.death_velocity`,
since the body stops before `player_death` is handed out).
`ItemDrops`, the items contract's own system (GameSystems adds it first):
- hears `player_death` and drops what `drops_on_death()` gives
  (`defuser_dropped` for the kit);
- takes the `drop` command for what is in hand, grenades too, never the
  knife and never the C4 (`item_remove`);
- picks an item up for a living player standing on it (32 units across,
  72 up) whose slot is free (`item_pickup`, or `defuser_pickup`, and only
  CTs take the kit). Swapping with the gun in hand (E) waits for a use-key
  handler; CS2's other way, taking a dropped gun from the buy menu
  (`UIPanorama.buymenu_pickup_weapon`), is not built. Pickups are silent
  here: CS2 plays `Player.PickupWeaponAudible` (and `PickupGrenadeAudible`,
  `PickupPistol`) to everyone within 1100 units and the picker's own
  `Player.PickupWeapon` (`reference/research/audio-gameplay.md` 1.3), which
  a view will play from `item_pickup` once the files are extracted;
- clears what lies on the ground at `round_prestart`.
The C4 on the ground is the bomb's own entity, not a `DroppedItem`.

CS2's values, from its convar dump (SteamDatabase's `DumpSource2/convars.txt`)
and `game/csgo/cfg/gamemode_competitive.cfg`, sent by Sid's local agent
on 2026-09-23 and checked against both files:

| Convar | CS2 | Here |
|---|---|---|
| `mp_weapon_prev_owner_touch_time` | 1.5 | whoever dropped it waits 1.5 s |
| `mp_weapon_next_owner_touch_time` | 1.3 | anyone else waits 1.3 s; no description, read from its name (measure) |
| `pickup_check_period` | 0.25 | an item looks for players every 0.25 s, first when anyone may take it |
| `mp_drop_grenade_enable`, `mp_drop_knife_enable` | true, false | `drop` takes grenades, never the knife |
| `mp_death_drop_gun` | 1 (best) | the best gun |
| `mp_death_drop_grenade` | 2 (current or best) | the grenade in hand, or else the best; one |
| `mp_death_drop_taser`, `_defuser`, `_c4` | true | the Zeus and the kit; the C4 is the bomb's |
| `weapon_auto_cleanup_time`, `weapon_max_before_cleanup` | 0, 0 | nothing is cleaned up before the round ends |
| `mp_shoot_dropped_grenades` | false | bullets pass through items on the ground |

In no file (measure): the throw's split between forward and up
(`ItemDrops.THROW_LIFT`; the speed is CS2's `m_flDropSpeed` 300), the
spin (by eye), the pickup reach, which grenade counts as best, a gun's
mass and bounce on the ground, and how blasts and bullets push it. The bomb's dropped C4 takes
the same two waits if it follows CS2.

## 4. The tick, and how systems join it

PR #50 (the local agent's GameWorld, `src/sim/game_world.gd`) owns the
tick; this branch is merged with it and fits it. Each tick the GameWorld:

1. counts the tick (`GameWorld.tick`, which `SimClock.current_tick()`
   reads, so events carry it);
2. runs each player's command, in the order they joined;
3. runs the match (`MatchState.tick`);
4. calls `world.game.step(tick, space)`: the players' queued commands,
   then every entity, then every system in the order added, then the
   tick's events handed out.

`world.game` is the one `GameSystems`. `GameWorld.add_player` puts the
player on its `Roster` (and `remove_player` takes them off), so a system
never adds players itself. On the range it is also `test_range.game`;
grenades, the bomb and buying add their systems there
(`range.game.add_system(...)`). Nothing a system does runs in a
`_physics_process` of its own (CLAUDE.md).

- `GameSystems`: `events`, `entities`, `roster`, `inventory(userid)`,
  `add_system(system)` (anything with `tick(t: SimTick)`; `attach(game)`
  is called when added, where it listens), `systems()`, `last_tick` and
  `now_usec()` (for what happens between ticks, an event being handed out),
  commands and queries below.
- `SimTick`: `tick`, `start_usec`, `now_usec`, `dt`, `space` (null with no
  world), `game`, and `t.events`, `t.entities`, `t.roster`.
- `SimEntity` (RefCounted): a simulated thing that is not a player.
  `id` (from `SimEntities`), `entity_class` (CS2's:
  `"hegrenade_projectile"`, `"smokegrenade_projectile"`, `"inferno"`,
  `"planted_c4"`, `"weapon_c4"` dropped, `"weapon_ak47"` dropped),
  `owner_id` (userid), `position`, `previous_position` (kept for you each
  tick, for drawing between ticks), `spawned_tick`, `tick(t)`, `remove()`,
  `save_state()` / `load_state()` (call `super`).
- `SimEntities`: `spawn(entity) -> id` (from 1), `find(id)`,
  `of_class(name)` and `all()` (copies, in spawn order), `size()`,
  `tick_all(t)`; one spawned during a tick first runs on the next; removed
  ones go after the tick. Signals `spawned(entity)` and `removed(entity)`
  for presenters. `clear()` at a round's start.
- `Roster`: `add(player, hit_target) -> userid` (0, 1, 2 ... in join
  order), `remove(userid)`, `player(userid)`, `hit_target(userid)` (the
  player's own `hit_target` once it has one; sets `HitTarget.userid`),
  `userid_of(node)`, `ids()`, `team_of(userid)` (the node's `team`),
  `on_team(team)`. Use it, not group scans.

### Buttons

A held button is a bit of `UserCmd.buttons` (and a `SubtickStep`'s
button): `ATTACK 1`, `JUMP 2`, `DUCK 4`, `WALK 8`, `RELOAD 16`, `USE 32`
(E: plant, defuse; Source's `IN_USE` bit), `ATTACK2 64` (right button:
underhand throw, scope, silencer). A new button is a line in
`src/sim/user_cmd.gd` and here, never a private bit. Wiring keys to them is
the local agent's (PlayerInput, bots).

### Commands

What CS2 sends as a console command rather than a held button ("buy ak47",
"drop") goes to `game.command(userid, "buy ak47")`, queued and run at the
start of the next `step`, in the order sent. A system takes a command with
`game.on_command(&"buy", handler)`; `handler(userid: int, args:
PackedStringArray, t: SimTick) -> bool` returns whether it took it.
Handlers of one command are asked in the order added until one takes it,
so each takes only its own case: `drop` is `ItemDrops`' for what is in
hand, and the bomb's when the C4 is in hand. Commands so far:
- `buy <item>` (buying): CS2's short names (`ak47`, `vest`, `vesthelm`,
  ...) or a class name.
- `sellback <item>` (buying): undoes a purchase made this round, while
  buying is still open.
- `drop` (`ItemDrops`; the bomb's with the C4 in hand).
- `throw <class> [strength]` (grenades, `GrenadeSystem`): throws that
  grenade from the player's eyes at the start of the next step; strength
  0 to 1, default 1. The hand sends it on letting go of the attack buttons
  (`player_sim.gd`); bots' lineups and a console can too.
A new command is a line here.

### Queries

A question one system answers about its state, by name, so nobody holds
the system that answers: `game.provide(&"name", callable)` (the answering
system, in `attach`), `game.query(&"name", [args], fallback)`,
`game.provides(&"name")`. With no provider the fallback comes back.
- `smoke_length_between(from: Vector3, to: Vector3) -> float`: units of
  smoke a line crosses (grenades; bots' sight, `player_death.thrusmoke`).
  Fallback 0.0.
- `blindness(userid: int) -> Dictionary` {`duration`, `peak`} and
  `blind_share(userid: int) -> float` (0 to 1, how blind now; grenades;
  bots, `player_death.attackerblind`). Fallbacks {} and 0.0.
- `burning_at(point: Vector3) -> bool`: whether fire covers that point
  (grenades; bots keep out of it). Fallback false.
- `holds_still(userid: int) -> bool`: true while that player is planting
  or defusing (the bomb). `player_sim` reads it to stop moving and firing
  without touching `frozen`, which the match owns. Fallback false.
- `money(userid: int) -> int`: that player's account (the economy). Bots
  read it before they shop. Fallback 0.
- `can_buy(userid: int) -> bool`: whether that player may shop now: on a
  side, alive, buying open, in their buy zone (the economy's
  `shop_refusal` is OK). Fallback false, so with no economy a bot never
  buys.
A new query is a line here.

## 5. What the local agent's files need, to wire this in

None of these are changed by the contract threads; this branch changes
`game_world.gd` only to own and step `game` and keep its roster.

- *(Done.)* `player_sim.gd`: `_try_shoot` calls `Hitscan.fire_as` with a
  `Shooter` carrying the player's `userid` and `world.game.events`, and
  sends `weapon_fire` for each round and `weapon_reload`; every player
  carries an `Inventory` of their own (`PlayerSim.inventory`), which
  `GameWorld.add_player` hands the game as theirs
  (`world.game.inventory(userid)` is the same object); 1 to 5 and Q select
  from it, each gun keeping its `Weapon`; a spawn sends `player_spawn` and
  strips a dead player (`PlayerSim._loadout`: the knife, the side's pistol
  and `starting_gun`, which a match leaves empty); a drawn body holds what
  is in hand (`PlayerModel.hold`); `weapon.press_trigger()` per press (R2); it reads
  `holds_still` (the range no longer sets `frozen`) and throws on the
  attack buttons with a grenade in hand, as `grenades.md` describes.
- `player_sim.gd`, still to do: `_on_hit` and `_fall` read
  `hit_target.last_damage` in place of the `last_hit_*` fields; `killed`
  passes `hit_target.killing_damage`.
- `bot.gd`: *(done)* the inventory through PlayerSim, `bot.arm()` now
  handing it its starting gun; *(done 2026-09-23)* buying in freeze time
  through `buy` commands, after the `can_buy` and `money` queries
  (`BotBuying`), and its best gun taken out. Still to do: USE and ATTACK2
  when bots plant and throw; the `burning_at` and `smoke_length_between`
  queries to keep out of fire and see through smoke.
- *(Done 2026-09-23.)* `match_state.gd`: sends `round_announce_warmup`,
  `begin_new_match`, `round_prestart` (handed out at once), `round_start`,
  `round_poststart`, `round_freeze_end`, `round_end` (with
  `GameEvents.round_end_reason` and `round_end_message`),
  `round_officially_ended`, `announce_phase_end` at the end of each half,
  `cs_win_panel_match`, into the events `GameWorld.match_state` hands it;
  `_arm` hands out nothing but a spawn's knife and pistol; a planted bomb
  holds the round's clock and a dead T side, and `bomb_exploded` and
  `bomb_defused` end the round. The bomb system hands out the C4 itself on
  `round_start`.
- *(Done.)* `player_spawn` {userid} goes out on every spawn, from
  `PlayerSim` (a respawn, and a survivor put at a spawn point by the
  match).
- *(Done.)* `PlayerInput`: G sends `drop`, E and the right button set `USE`
  and `ATTACK2`, 3 to 5 and Q select; the buy menu sends `buy`. The
  range's never-die moved to `[` (`reference/binds.md`), and the grenade
  lane's keys are gone.
  `PlayerInput.ensure_actions` adds any of these keys the input map lacks
  (a `project.godot` an open editor wrote back over).
- `de_dust2.gd`: *(done 2026-09-23)* the economy, the bomb and the
  grenades added to `world.game`, and their drawing (grenades, smoke and
  fire, the flash's white-out, the bomb). Still to do: the kill feed.

## Asked for by the other threads

- The bomb (22:36): its events are in the schema as it gave them, plus
  CS2's `entindex` on `bomb_dropped`. The explosion deals one `DamageInfo`
  per player in reach (no attacker, `GameEvents.NOBODY` -1, so the kill
  feed shows the C4 and the victim and the planter gets no kill or award;
  inflictor `"planted_c4"`, weapon `"weapon_c4"`, `DMG_BLAST`, no zone,
  origin the bomb, armour as a grenade's, no team scaling). No attacker is
  from playing CS2, not measured; the bomb's Local item C1 in
  `reference/cs2-systems.md` can confirm it. `weapon_c4` and
  `item_defuser` are items; "carries the C4", "has a kit" and "C4 in hand"
  are `inv.has("weapon_c4")`, `inv.has_defuser` and
  `inv.in_hand_class() == "weapon_c4"`.

- Buying and money (22:39): every event it listens to is in the schema:
  `begin_new_match`, `round_start`, `round_freeze_end`, `round_end`
  (winner, and the reason by CS2's name: map `MatchState.Reason` with
  `GameEvents.round_end_reason`), `player_death` (weapon as the full class
  name), `bomb_planted`, `bomb_defused`, and `announce_phase_end` for the
  side swap (above). Who was alive at the round's end: `round_end` does
  not carry it in CS2 either; count `player_death` since `round_start`
  against the roster. A team kill: `GameSystems.roster.team_of(userid)` for
  both players (sides never change mid-round). It sends `item_purchase`
  {userid, team, loadout, weapon}. The inventory gives it everything on its
  list: `count`, `item_in(slot)`, `can_add`, `add` (handing back what a
  new primary or pistol replaced, for it to drop), `remove` (undoing a
  purchase), `armor`, `helmet`, `has_defuser`. Accounts key on the userid.

- Grenades (22:46): needs no new events or keys. Its flash state and smoke
  are answered through queries on `GameSystems` (section 4):
  `smoke_length_between` and `blindness` / `blind_share`, provided by the
  grenade system in `attach`, asked by bots and by whatever fills
  `player_death.thrusmoke` and `attackerblind`.

- The bomb (22:49): (1) `drops_on_death()` leaves the C4 out; the bomb
  drops it. (2) `player_given_c4` and `round_prestart` are in the schema.
  (3) Buttons are part of the contract: `USE 32`, `ATTACK2 64` in
  `UserCmd` (section 4). (4) Drop and buy are commands (section 4); the
  bomb takes `drop` with the C4 in hand.

- Buying, grenades and the bomb (23:10, approved by the coordinator):
  commands `buy` (short names or classes), `sellback`, `throw`; queries
  `burning_at` and `holds_still`; `item_remove` sent once by whoever takes
  the item out of the inventory.
