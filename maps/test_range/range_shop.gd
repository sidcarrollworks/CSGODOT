class_name RangeShop
extends Node3D

## Money and buying on the test range: a buy zone round the spawn, $16,000,
## and CS2's buy menu on B.
##
## The economy is the game's own (Economy), a system in the range's
## GameSystems like any other; the range only sets it up for trying things:
## buying never closes (no round is played here, so buy time never starts
## counting), and O fills the account again. Everything else is the rule as
## a match has it: the zone, the prices, the sides, what can be carried,
## undoing a purchase.
##
## Until the player carries an inventory of their own (the GameWorld's work,
## reference/systems/economy.md), what you hold is kept in step with it
## here: a gun you buy is put in your hands, and undoing the one in your
## hands puts the best one left there. Armour goes straight onto your body.

## The buy zone: a box on the floor round the spawn, drawn so it can be
## seen, for either side.
const ZONE := AABB(Vector3(-192.0, 0.0, -192.0), Vector3(384.0, 160.0, 384.0))
const ZONE_COLOUR := Color(0.3, 0.8, 0.4, 0.25)

var economy: Economy
var menu: BuyMenu
var game: GameSystems
var player: PlayerController
var userid: int = GameEvents.NOBODY


## Puts the economy into the range's game and the menu on its HUD layer.
func setup(range_game: GameSystems, you: PlayerController, hud: CanvasLayer) -> void:
	game = range_game
	player = you
	userid = game.roster.userid_of(player)
	if userid == GameEvents.NOBODY:
		userid = game.add_player(player, player.hit_target)

	var zones := BuyZones.new()
	zones.add_box("T", ZONE)
	zones.add_box("CT", ZONE)
	economy = Economy.new(MoneyRules.new(), zones)
	game.add_system(economy)
	economy.set_money(userid, economy.rules.max_money)
	game.events.listen(&"item_purchase", _on_purchase)
	game.events.listen(&"item_remove", _on_remove)

	# The inventory starts as what you are holding: the knife, your side's
	# pistol, and the rifle the range hands you.
	var inv := game.inventory(userid)
	if inv.entries().is_empty():
		inv.give_starting_items(player.team)
		if player.weapon != null and not player.weapon.data.item_class.is_empty():
			inv.add(player.weapon.data.item_class)

	menu = BuyMenu.new()
	menu.economy = economy
	menu.userid = userid
	hud.add_child(menu)
	_draw_zone()


## O: the account full again.
func reset() -> void:
	economy.set_money(userid, economy.rules.max_money)


## The readout's lines: money, whether you can buy here, and what you carry.
func readout() -> PackedStringArray:
	var inv := game.inventory(userid)
	var carried := PackedStringArray()
	for entry in inv.entries():
		carried.append(entry.item.name + ("" if entry.count <= 1 else " x%d" % entry.count))
	if inv.has_defuser:
		carried.append("Defuse Kit")
	var why := economy.shop_refusal(userid)
	return PackedStringArray([
		"money      $%d   %s" % [economy.money(userid),
			"B: buy menu" if why == Economy.OK else Economy.MESSAGES.get(why, "")],
		"carrying   %s" % ", ".join(carried),
	])


func _on_purchase(event: GameEvent) -> void:
	if event.fields["userid"] != userid:
		return
	var data := ItemRegistry.weapon_data(String(event.fields["weapon"]))
	if data != null:
		player.equip(data)


func _on_remove(event: GameEvent) -> void:
	if event.fields["userid"] != userid or player.weapon == null:
		return
	if player.weapon.data.item_class != String(event.fields["item"]):
		return
	var best := game.inventory(userid).best_gun()
	if best != null:
		player.equip(ItemRegistry.weapon_data(best.item_class()))


func _draw_zone() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(ZONE.size.x, 1.0, ZONE.size.z)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = ZONE_COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material
	mesh.position = ZONE.get_center() * Vector3(1.0, 0.0, 1.0) + Vector3(0.0, 0.6, 0.0)
	add_child(mesh)
	var label := Label3D.new()
	label.text = "buy zone: B"
	label.font_size = 96
	label.pixel_size = 0.25
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.4, 1.0, 0.5)
	label.position = Vector3(ZONE.position.x + 48.0, 40.0, ZONE.position.z + 16.0)
	add_child(label)
