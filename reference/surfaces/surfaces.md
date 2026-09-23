# CS2's surfaces

Written by `scripts/surface_tables.gd` from CS2 1.41.8.2's `surfaceproperties/surfaceproperties.vsurf` and
`scripts/surfaceproperties_game.txt` (`scripts/extract_assets.sh surfaces`); `surfaces.csv` has
the same values as the files give them, blank where a surface takes its parent's. Here they are resolved:
each surface's own, else its parent's, and so on up to `default`. Player friction is the physics
friction times 1.25, at most 1, as Source's `CGameMovement::CategorizeGroundSurface` makes it
(`gamemovement.cpp`, Source SDK 2013): it scales ground friction and acceleration.

| Surface | Parents | Material | Friction | Player friction | Jump | Speed | Penetration reach | Penetration damage | Smoke through |
|---|---|---|---|---|---|---|---|---|---|
| default | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| solidmetal | - | M | 0.8 | 1 | 1.0 | 1.0 | 0.27 | 0.3 |  |
| metal | solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_barrelSoundOverride | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_vehicleSoundOverride | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_survivalCase | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_survivalCase_unpunchable | metal_survivalCase > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metaldogtags | solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metalgrate | - | G | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| Metal_Box | solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| metal_bouncy | solidmetal | M | 0.0 | 0 | 1.0 | 1.0 | 0.27 | 0.3 |  |
| slipperymetal | metal > solidmetal | M | 0.1 | 0.125 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| grate | metalgrate | G | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| metalvent | Metal_Box > solidmetal | V | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.45 |  |
| metalpanel | metal > solidmetal | V | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.45 |  |
| dirt | - | D | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| mud | dirt | 11 | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| slipperyslime | dirt | D | 0.1 | 0.125 | 0.7 | 1.0 | 0.6 | 0.3 |  |
| grass | dirt | J | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| slowgrass | dirt | J | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| sugarcane | dirt | J | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| tile | - | T | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.3 |  |
| tile_survivalCase | tile | T | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.3 |  |
| tile_survivalCase_GIB | tile | T | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.3 |  |
| Wood | - | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_lowdensity | Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Box | Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Basket | Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Crate | Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Plank | Wood_Box > Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.85 | 0.6 |  |
| Wood_Solid | Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.8 | 0.6 |  |
| Wood_Furniture | Wood_Box > Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Panel | Wood_Crate > Wood | W | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| Wood_Dense | Wood | 13 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| water | - | S | 0.8 | 1 | 1.0 | 1.0 | 0.3 | 0.5 |  |
| wet | - | S | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| puddle | - | 10 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| slime | - | S | 0.9 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| quicksand | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.2 | 0.5 |  |
| wade | water | X | 0.8 | 1 | 1.0 | 1.0 | 0.3 | 0.5 |  |
| ladder | metal > solidmetal | X | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| Wood_Ladder | Wood | X | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.6 |  |
| glass | - | Y | 0.5 | 0.625 | 1.0 | 1.0 | 0.99 | 0.5 |  |
| glassfloor | - | Y | 0.8 | 1 | 1.0 | 1.0 | 0.99 | 0.5 |  |
| computer | Metal_Box > solidmetal | P | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.45 |  |
| weapon_magazine | computer > Metal_Box > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.45 |  |
| concrete | no_decal | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| asphalt | concrete > no_decal | Q | 0.8 | 1 | 1.0 | 1.0 | 0.55 | 0.3 |  |
| rock | concrete > no_decal | 3 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| porcelain | rock > concrete > no_decal | 3 | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.25 |  |
| boulder | rock > concrete > no_decal | 3 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| brick | rock > concrete > no_decal | R | 0.8 | 1 | 1.0 | 1.0 | 0.47 | 0.3 |  |
| concrete_block | concrete > no_decal | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| stucco | concrete > no_decal | 2 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| chainlink | - | G | 0.8 | 1 | 1.0 | 1.0 | 0.99 | 0.99 | true |
| chain | chainlink | G | 0.8 | 1 | 1.0 | 1.0 | 0.99 | 0.99 | true |
| flesh | - | F | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.5 |  |
| bloodyflesh | flesh | B | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.5 |  |
| alienflesh | flesh | H | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.5 |  |
| armorflesh | flesh | M | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| ice | - | C | 0.1 | 0.125 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| carpet | dirt | 7 | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.3 |  |
| dufflebag_survivalCase | carpet > dirt | 7 | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.3 |  |
| upholstery | dirt | 9 | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.3 |  |
| plaster | dirt | 2 | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.6 |  |
| sheetrock | dirt | 5 | 0.8 | 1 | 1.0 | 1.0 | 0.85 | 0.6 |  |
| cardboard | dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| plastic_barrel | - | L | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.5 |  |
| Plastic_Box | - | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| plastic | Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| plastic_survivalCase | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| sand | dirt | N | 0.8 | 1 | 1.0 | 1.0 | 0.3 | 0.25 |  |
| rubber | dirt | 4 | 0.8 | 1 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| rubbertire | rubber > dirt | 4 | 1.0 | 1 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| jeeptire | rubber > dirt | 4 | 1.337 | 1 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| slidingrubbertire | rubber > dirt | 4 | 0.2 | 0.25 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| brakingrubbertire | rubber > dirt | 4 | 0.6 | 0.75 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| slidingrubbertire_front | rubber > dirt | 4 | 0.2 | 0.25 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| slidingrubbertire_rear | rubber > dirt | 4 | 0.2 | 0.25 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| glassbottle | glass | Y | 0.4 | 0.5 | 1.0 | 1.0 | 0.99 | 0.0 |  |
| pottery | glassbottle > glass | 1 | 0.4 | 0.5 | 1.0 | 1.0 | 0.95 | 0.6 |  |
| clay | tile | 1 | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.6 |  |
| canister | metalpanel > metal > solidmetal | V | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.45 |  |
| metal_barrel | metal > solidmetal | 12 | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.01 |  |
| metal_barrel_explodingSurvival | metal_barrel > metal > solidmetal | 12 | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.01 |  |
| floating_metal_barrel | metal_barrel > metal > solidmetal | 12 | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.01 |  |
| plastic_barrel_buoyant | plastic_barrel | L | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.5 |  |
| roller | metalpanel > metal > solidmetal | V | 0.7 | 0.875 | 1.0 | 1.0 | 0.5 | 0.45 |  |
| popcan | Metal_Box > solidmetal | M | 0.3 | 0.375 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| paintcan | popcan > Metal_Box > solidmetal | M | 0.3 | 0.375 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| paper | cardboard > dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| papercup | paper > cardboard > dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| ceiling_tile | cardboard > dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| foliage | Wood_Solid > Wood | O | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.6 |  |
| slipperyslide | solidmetal | M | 0.1 | 0.125 | 0.7 | 1.0 | 0.27 | 0.3 |  |
| strongman_bell | solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.27 | 0.3 |  |
| watermelon | wet | S | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.6 |  |
| item | Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| floatingstandable | dirt | D | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| grenade | metalpanel > metal > solidmetal | V | 0.9 | 1 | 1.0 | 1.0 | 0.5 | 0.45 |  |
| weapon | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_shield | metal > solidmetal | 14 | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| default_silent | - | X | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| player | - | C | 0.5 | 0.625 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| player_control_clip | - | I | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 1.0 |  |
| no_decal | - | - | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| soccerball | - | - | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| gravel | rock > concrete > no_decal | 3 | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.25 |  |
| snow | - | K | 0.8 | 1 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| metalvehicle | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| brass_bell_large | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| brass_bell_medium | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| brass_bell_small | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| brass_bell_smallest | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| metal_sand_barrel | solidmetal | 12 | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.01 |  |
| blockbullets | - | X | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.001 |  |
| jalopytire | jeeptire > rubber > dirt | 4 | 0.8 | 1 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| slidingrubbertire_jalopyfront | jalopytire > jeeptire > rubber > dirt | 4 | 0.15 | 0.188 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| slidingrubbertire_jalopyrear | jalopytire > jeeptire > rubber > dirt | 4 | 0.15 | 0.188 | 1.0 | 1.0 | 0.85 | 0.5 |  |
| jalopy | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| Balloon | default | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| metal_ventslat | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| metal_sheetmetal | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| plasticbottle | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| concrete_polished | concrete > no_decal | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.25 |  |
| plastic_dumpster | Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| metal_dumpster | metal_barrel > metal > solidmetal | 12 | 0.8 | 1 | 1.0 | 1.0 | 0.01 | 0.01 |  |
| Cloth | carpet > dirt | 7 | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.3 |  |
| plaster_drywall | plaster > dirt | 2 | 0.8 | 1 | 1.0 | 1.0 | 0.7 | 0.6 |  |
| Wood_Tree | Wood_Dense > Wood | 13 | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.3 |  |
| beans | mud > dirt | 11 | 0.8 | 1 | 1.0 | 1.0 | 0.6 | 0.3 |  |
| WeaponHeavy | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponPistol | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponSMG | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponRifle | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponC4 | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponShotgun | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| Defuser | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponMolotov | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponFlashbang | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponSniper | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponHEGrenade | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| WeaponIncendiary | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| cardboard_smallbox | cardboard > dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| papertowel | paper > cardboard > dirt | U | 0.8 | 1 | 1.0 | 1.0 | 0.95 | 0.99 |  |
| potterylarge | glassbottle > glass | 1 | 0.4 | 0.5 | 1.0 | 1.0 | 0.95 | 0.6 |  |
| plastic_tape | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| playerflesh | flesh | F | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.5 |  |
| fruit | player | F | 0.8 | 1 | 1.0 | 1.0 | 0.9 | 0.5 |  |
| WeaponMagazine | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| audioblocker | - | X | 0.0 | 0 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| wet_sand | wet | S | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| plastic_autoCover | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| plastic_milkCrate | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.75 | 0.5 |  |
| WeaponKnife | weapon > metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
| brass_bell_smallest_g | - | C | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| metalrailing | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 | true |
| plastic_solid | plastic > Plastic_Box | L | 0.8 | 1 | 1.0 | 1.0 | 0.0 | 0.5 |  |
| wet_concrete | wet | S | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| wet_mud | wet | S | 0.8 | 1 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| audioblocker_inneredge | audioblocker | X | 0.0 | 0 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| audioblocker_middleedge | audioblocker | X | 0.0 | 0 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| audioblocker_outeredge | audioblocker | X | 0.0 | 0 | 1.0 | 1.0 | 0.5 | 0.5 |  |
| metal_sheet_corrugated | metal > solidmetal | M | 0.8 | 1 | 1.0 | 1.0 | 0.4 | 0.3 |  |
