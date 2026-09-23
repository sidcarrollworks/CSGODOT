# The equipment's files, numbers and timings

Written by `scripts/weapon_tables.gd` on 2026-09-23 from what `scripts/extract_assets.sh equipment` (the models, their clips and the clips' own data) and `sounds` extracted out of CS2 1.41.8.2, and the game's `scripts/weapons.vdata_c`. Do not edit by hand. The equipment is the bomb and the defuse kit, the six grenades, the two default knives and the Zeus; `vdata.csv` has their entries with the guns'.

## Files

Under the roots `models.md` gives. The sets are named as the guns' are. In third person the grenades but the molotov have only `grenade/_default_grenade`, and the molotov's own set is its draw, idle and pin, over that one's throws; the knives' own sets are the draw and the idle, over `knife/_default_knife`'s attacks and locomotion. The kit's is the defuse, a clip for each kind of weapon in hand.

| Class | Name | Model | First person | Third person | Skeleton | Sounds | Icon |
|---|---|---|---|---|---|---|---|
| `weapon_c4` | C4 Explosive | `c4/weapon_c4.gltf` | `equipment/c4` (6) | `equipment/c4` (19) | `c4` | `c4/` (42) | `c4.svg` |
| `item_defuser` | Defuse Kit | `defuser/defuser.gltf` | - | `shared/defuse` (18) | - | - | `defuser.svg` |
| `weapon_knife` | Knife (CT) | `knife/knife_default_ct/weapon_knife_default_ct.gltf` | `knife/_default_knife` (13) | `knife/default_ct` (4) | `knife_default_ct` | `knife/` (223) | `knife.svg` |
| `weapon_knife_t` | Knife (T) | `knife/knife_default_t/weapon_knife_default_t.gltf` | `knife/knife_default_t` (13) | `knife/default_t` (4) | `knife_default_t` | `knife/` (223) | `knife_t.svg` |
| `weapon_taser` | Zeus x27 | `taser/weapon_pist_taser.gltf` | `pistol/pistol_taser` (4) | `pistol/pistol_taser` (5) | `taser` | `taser/` (7) | `taser.svg` |
| `weapon_hegrenade` | HE Grenade | `grenade/hegrenade/weapon_hegrenade.gltf` | `grenade/grenade_hegrenade` (10) | `grenade/_default_grenade` (10) | `hegrenade` | `hegrenade/` (25) | `hegrenade.svg` |
| `weapon_flashbang` | Flashbang | `grenade/flashbang/weapon_flashbang.gltf` | `grenade/grenade_flashbang` (10) | `grenade/_default_grenade` (10) | `flashbang` | `flashbang/` (30) | `flashbang.svg` |
| `weapon_smokegrenade` | Smoke Grenade | `grenade/smokegrenade/weapon_smokegrenade.gltf` | `grenade/grenade_smokegrenade` (10) | `grenade/_default_grenade` (10) | `smokegrenade` | `smokegrenade/` (40) | `smokegrenade.svg` |
| `weapon_molotov` | Molotov | `grenade/molotov/weapon_molotov.gltf` | `grenade/grenade_molotov` (10) | `grenade/grenade_molotov` (6) | `molotov` | `molotov/` (48) | `molotov.svg` |
| `weapon_incgrenade` | Incendiary Grenade | `grenade/incendiary/weapon_incendiarygrenade.gltf` | `grenade/grenade_incendiary` (10) | `grenade/_default_grenade` (10) | `incendiary` | `incgrenade/` (29) | `incgrenade.svg` |
| `weapon_decoy` | Decoy Grenade | `grenade/decoy/weapon_decoy.gltf` | `grenade/_default_grenade` (10) | `grenade/_default_grenade` (10) | `decoy` | `decoy/` (26) | `decoy.svg` |

## The game's numbers

From each one's vdata entry; the T knife's are the knife's. The file is written out in full, each entry carrying every field, so some of these are defaults nothing reads: the knife's damage and reach are the game's code (its 50 and 4096 are the knife class's defaults), and the bomb's blast is the map's `bombradius`. What the grenades do when they go off (the flash's blinding, the smoke's cloud, the fire's spread) is the game's code too. A dash is a field the entry does not have: only the grenades have a throw speed. Top speed is the player's, holding it.

| Class | Price | Kill award | Damage | Armour ratio | Range | Thrown at | Top speed | Draw |
|---|---|---|---|---|---|---|---|---|
| `weapon_c4` | $0 | $300 | 50 | 1.0 | 4096 | - | 250 | 1.233333 s |
| `weapon_knife` | $0 | $1500 | 50 | 1.7 | 4096 | - | 250 | 1.0 s |
| `weapon_taser` | $200 | $100 | 500 | 2.0 | 120 | - | 230 | 1.0 s |
| `weapon_hegrenade` | $300 | $300 | 99 | 1.2 | 350 | 750 u/s | 245 | 1.0 s |
| `weapon_flashbang` | $200 | $300 | 50 | 1.0 | 4096 | 750 u/s | 245 | 1.0 s |
| `weapon_smokegrenade` | $300 | $300 | 50 | 1.0 | 4096 | 750 u/s | 245 | 1.0 s |
| `weapon_molotov` | $400 | $300 | 40 | 1.8 | 4096 | 750 u/s | 245 | 1.0 s |
| `weapon_incgrenade` | $500 | $300 | 40 | 1.475 | 4096 | 750 u/s | 245 | 1.0 s |
| `weapon_decoy` | $50 | $300 | 50 | 1.0 | 4096 | 750 u/s | 245 | 1.0 s |

## Timings

From the clips' own data, as the guns' (`timings.md`), first person: each clip's length and, for a throw, when its throw sound plays; for the plant, its key presses (the `c4.keypressquiet` sounds) and the last of its `WPN_BOMB_STAGE` marks. A clip of one frame is a pose held (the HE's and the decoy's throw charges). The idles and inspects are left out.

| Class | Set | Draw | The rest |
|---|---|---|---|
| `weapon_c4` | `equipment/c4` | 1.23 s | plant 4.00 s, 7 key presses from 0.67 s to 2.17 s, the last stage at 2.47 s |
| `weapon_knife` | `knife/_default_knife` | 1.00 s | heavy backstab 1.17 s; heavy hit1 1.17 s; heavy miss1 1.17 s; light backstab 1.17 s; light backstab2 1.17 s; light hit1 1.17 s; light hit2 1.17 s; light miss1 1.17 s; light miss2 1.17 s |
| `weapon_knife_t` | `knife/knife_default_t` | 1.00 s | heavy backstab 1.17 s; heavy hit1 1.17 s; heavy miss1 1.17 s; light backstab 1.17 s; light backstab2 1.17 s; light hit1 1.17 s; light hit2 1.17 s; light miss1 1.17 s; light miss2 1.17 s |
| `weapon_taser` | `pistol/pistol_taser` | 1.00 s | shoot1 0.40 s |
| `weapon_hegrenade` | `grenade/grenade_hegrenade` | 1.00 s | pullpin 0.97 s; throw overhand 0.77 s, throw sound at 0.07 s; throw underhand 0.50 s, throw sound at 0.13 s; throwcharge high one frame; throwcharge low one frame; throwcharge mid one frame |
| `weapon_flashbang` | `grenade/grenade_flashbang` | 1.00 s | pullpin 0.97 s; throw overhand 0.77 s, throw sound at 0.07 s; throw underhand 0.50 s, throw sound at 0.13 s; throwcharge high 1.00 s; throwcharge low 1.00 s; throwcharge mid 1.00 s |
| `weapon_smokegrenade` | `grenade/grenade_smokegrenade` | 1.00 s | pullpin 0.97 s; throw overhand 0.77 s, throw sound at 0.07 s; throw underhand 0.50 s, throw sound at 0.00 s; throwcharge high 1.00 s; throwcharge low 1.00 s; throwcharge mid 1.00 s |
| `weapon_molotov` | `grenade/grenade_molotov` | 1.00 s | pullpin 1.13 s; throw overhand 0.77 s, throw sound at 0.03 s; throw underhand 0.50 s, throw sound at 0.00 s; throwcharge high 1.00 s; throwcharge low 1.00 s; throwcharge mid 1.00 s |
| `weapon_incgrenade` | `grenade/grenade_incendiary` | 1.00 s | pullpin 0.97 s; throw overhand 0.77 s, throw sound at 0.03 s; throw underhand 0.50 s, throw sound at 0.00 s; throwcharge high 1.00 s; throwcharge low 1.00 s; throwcharge mid 1.00 s |
| `weapon_decoy` | `grenade/_default_grenade` | 1.00 s | pullpin 0.97 s; throw overhand 0.77 s, throw sound at 0.07 s; throw underhand 0.50 s, throw sound at 0.00 s; throwcharge high one frame; throwcharge low one frame; throwcharge mid one frame |

And in third person, the plant and the defuse, standing and crouched. The defuse enters, then loops for as long as it takes, with a clip for the kind of weapon in hand; the plant can turn from `WPN_C4_ALLOW_TURN` on.

| Clip | Length | Marks |
|---|---|---|
| `planting` | 3.30 s | `WPN_C4_ALLOW_TURN` at 0.57 s |
| `planting_crouch` | 3.30 s | `WPN_C4_ALLOW_TURN` at 0.57 s |
| `defuse_crouch_enter` | 1.00 s |  |
| `defuse_crouch_enter_knife` | 1.00 s |  |
| `defuse_crouch_enter_knife_talon` | 1.00 s |  |
| `defuse_crouch_enter_pistol` | 1.00 s |  |
| `defuse_crouch_enter_rifle` | 1.00 s |  |
| `defuse_crouch_loop` | 2.00 s |  |
| `defuse_crouch_loop_knife` | 2.00 s |  |
| `defuse_crouch_loop_knife_talon` | 2.00 s |  |
| `defuse_crouch_loop_pistol` | 2.00 s |  |
| `defuse_crouch_loop_rifle` | 2.00 s |  |
| `defuse_enter_knife` | 1.00 s |  |
| `defuse_enter_knife_talon` | 1.00 s |  |
| `defuse_enter_pistol` | 1.00 s | `WPN_IK_ACTION_ENDING` at 0.00 s |
| `defuse_enter_rifle` | 1.00 s |  |
| `defuse_loop_knife` | 2.00 s |  |
| `defuse_loop_knife_talon` | 2.00 s |  |
| `defuse_loop_pistol` | 2.00 s |  |
| `defuse_loop_rifle` | 2.00 s |  |

## The clips in each set

By the name the file carries, less the set's suffix, as in `models.md`.

| Class | First person | Third person |
|---|---|---|
| `weapon_c4` | draw, idle, lookat01, lookat02, lookat03, plant | draw, draw_crouch, idle, idle_crouch, planting, planting_crouch, turn_idle_loop, turn_left_loop_180, turn_left_loop_180_fast, turn_left_loop_23, turn_left_loop_34, turn_left_loop_45, turn_left_loop_90, turn_right_loop_180, turn_right_loop_180_fast, turn_right_loop_23, turn_right_loop_34, turn_right_loop_45, turn_right_loop_90 |
| `item_defuser` | - | defuse_crouch_enter, defuse_crouch_enter_knife, defuse_crouch_enter_knife_talon, defuse_crouch_enter_pistol, defuse_crouch_enter_rifle, defuse_crouch_loop, defuse_crouch_loop_knife, defuse_crouch_loop_knife_talon, defuse_crouch_loop_pistol, defuse_crouch_loop_rifle, defuse_enter_knife, defuse_enter_knife_talon, defuse_enter_pistol, defuse_enter_rifle, defuse_loop_knife, defuse_loop_knife_talon, defuse_loop_pistol, defuse_loop_rifle |
| `weapon_knife` | draw, heavy_backstab, heavy_hit1, heavy_miss1, idle2, idle, light_backstab2, light_backstab, light_hit1, light_hit2, light_miss1, light_miss2, lookat01 | draw_crouch, draw, idle_crouch, idle |
| `weapon_knife_t` | draw, heavy_backstab, heavy_hit1, heavy_miss1, idle2, idle, light_backstab2, light_backstab, light_hit1, light_hit2, light_miss1, light_miss2, lookat01 | draw_crouch, draw, idle_crouch, idle |
| `weapon_taser` | draw, idle, lookat01, shoot1 | draw_crouch, draw, idle_crouch, idle, shoot |
| `weapon_hegrenade` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | crouch_throw_far, crouch_throw_near, draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin, throw_overhand, throw_underhand |
| `weapon_flashbang` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | crouch_throw_far, crouch_throw_near, draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin, throw_overhand, throw_underhand |
| `weapon_smokegrenade` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | crouch_throw_far, crouch_throw_near, draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin, throw_overhand, throw_underhand |
| `weapon_molotov` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin |
| `weapon_incgrenade` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | crouch_throw_far, crouch_throw_near, draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin, throw_overhand, throw_underhand |
| `weapon_decoy` | draw, idle, lookat01, lookat02, pullpin, throw_overhand, throw_underhand, throwcharge_high, throwcharge_low, throwcharge_mid | crouch_throw_far, crouch_throw_near, draw_crouch, draw, idle_crouch, idle, pullpin_crouch, pullpin, throw_overhand, throw_underhand |
