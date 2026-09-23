class_name ItemDef
extends RefCounted

## One kind of item, by its CS2 class name: a gun, the knife, the Zeus, a
## grenade, the C4, kevlar, the suit or the defuse kit. What the game says
## about it (ItemRegistry reads it), shared by everyone who carries one; what
## one player's copy is doing (its ammo, its recoil) is that player's
## Inventory.Entry.

## Where it is carried: CS2's gear slots, numbered as the number keys pick
## them less one. Kevlar, the suit and the kit are worn, not carried in a slot.
enum Slot { EQUIPMENT = -1, PRIMARY = 0, PISTOL = 1, KNIFE = 2, GRENADE = 3, C4 = 4 }

## CS2's class name: "weapon_ak47", "weapon_hegrenade", "item_defuser".
var item_class: String = ""
## CS2's English name: "AK-47".
var name: String = ""
var slot: Slot = Slot.EQUIPMENT
## Where in its slot it sits: the Zeus is beside the knife.
var slot_position: int = 0
## "pistol", "smg", "shotgun", "rifle", "sniper", "machinegun", "knife",
## "taser", "grenade", "c4" or "equipment".
var type: String = ""
var price: int = 0
## What a kill with it pays the killer.
var kill_award: int = 0
## The side that may buy it: "T", "CT", or "" for both.
var team: String = ""
## How many one player may carry: two flashbangs, one of anything else.
var max_carried: int = 1
## Grenades that share one place: the molotov and the incendiary are both
## "firebomb", so a player carries one or the other.
var grenade_group: String = ""
## CS2's m_iWeight: the heavier gun is the better one, which is the one
## dropped on death and switched to.
var weight: int = 0
## How long it takes to draw, in seconds.
var deploy_seconds: float = 0.0
## The fastest its carrier runs with it in hand, in units a second.
var max_speed: float = 250.0
var buyable: bool = true
## The knife stays with its owner.
var droppable: bool = true
## Whether it fires rounds through the firing model (Weapon, WeaponData).
var is_gun: bool = false
## Where it comes in ItemRegistry.all(): what orders a slot's contents.
var order: int = 0
## Carried with its silencer on: the M4A1-S and the USP-S.
var silenced_by_default: bool = false


func is_grenade() -> bool:
	return slot == Slot.GRENADE


func _to_string() -> String:
	return item_class
