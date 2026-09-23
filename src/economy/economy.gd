class_name Economy
extends RefCounted

## Money and buying, as the server keeps them: every player's account, what
## each round, kill, plant and defuse pays, and every purchase, checked and
## put into the buyer's inventory.
##
## It is one of the game's systems (GameSystems): stepped on the tick, and
## meeting the rest of the game only through the shared contracts
## (reference/systems/contracts.md). It learns what happened from game
## events (round_start, round_end, player_death, bomb_planted and the rest),
## and never calls the round code; a purchase goes into the buyer's
## Inventory and is announced with item_purchase. A purchase is CS2's own
## console command, "buy ak47", sent through GameSystems.command and carried
## out at the start of the next tick, as CS2's server carries out a
## client's; "sellback ak47" undoes one. What is drawn (the buy menu, the
## money on the HUD) only reads the economy and sends those commands.
##
## Every number is MoneyRules', and every one of those is CS2's.
## reference/systems/economy.md says where each comes from and which are
## guesses.

## Why a purchase was refused, as the buy menu says it; &"" when it was not.
const OK := &""
const NOT_SOLD := &"not_sold"
const NOT_PLAYING := &"not_playing"
const DEAD := &"dead"
const WRONG_TEAM := &"wrong_team"
const BUY_TIME_OVER := &"buy_time_over"
const NOT_IN_BUY_ZONE := &"not_in_buy_zone"
const ALREADY_HAVE := &"already_have"
const CANNOT_CARRY := &"cannot_carry"
const TYPE_LIMIT := &"type_limit"
const NO_MONEY := &"no_money"
const NOTHING_TO_UNDO := &"nothing_to_undo"

## What the menu says for each refusal, as CS2 says it.
const MESSAGES := {
	NOT_SOLD: "That item cannot be bought.",
	NOT_PLAYING: "Join a team to buy.",
	DEAD: "You can't buy while dead.",
	WRONG_TEAM: "Your team can't buy that.",
	BUY_TIME_OVER: "The buy time has ended.",
	NOT_IN_BUY_ZONE: "You are not in a buy zone.",
	ALREADY_HAVE: "You already have that.",
	CANNOT_CARRY: "You cannot carry any more.",
	TYPE_LIMIT: "You can't buy any more of those this round.",
	NO_MONEY: "You have insufficient funds!",
	NOTHING_TO_UNDO: "There is nothing to undo.",
}

var rules: MoneyRules
## Read for the length of regulation, to tell an overtime half from a
## regular one.
var match_rules: MatchRules
var zones: BuyZones
var game: GameSystems

## Money by userid.
var _accounts := {}
## Each side's place on the loss ladder, and for loss_aversion 2 whether its
## next win only holds it (the first win after a loss).
var _losses := {"T": 0, "CT": 0}
var _hold_next_win := {"T": false, "CT": false}
## The round so far: whether the bomb was planted, and who has died.
var _planted := false
var _dead := {}
var _rounds_played := 0
## Buying: open until _buy_ends_usec (-1 while freeze time or warmup runs,
## when it has no end yet).
var _buy_open := true
var _buy_ends_usec := -1
## Who is in their side's buy zone, as last sent with enter_buyzone and
## exit_buyzone.
var _in_zone := {}
## This round's purchases by userid, for undoing them: [{item, price,
## armor, helmet}], oldest first; and the purchases of each weapon type.
var _bought := {}
var _type_counts := {}


func _init(money_rules: MoneyRules = null, zones_by_side: BuyZones = null) -> void:
	rules = money_rules if money_rules != null else MoneyRules.new()
	zones = zones_by_side if zones_by_side != null else BuyZones.new()
	match_rules = MatchRules.new()
	_reset_ladders()


## Called by GameSystems when the economy joins it: where it listens.
func attach(game_systems: GameSystems) -> void:
	game = game_systems
	var events := game.events
	events.listen(&"begin_new_match", _on_begin_new_match)
	events.listen(&"announce_phase_end", _on_half)
	events.listen(&"round_start", _on_round_start)
	events.listen(&"round_freeze_end", _on_freeze_end)
	events.listen(&"round_end", _on_round_end)
	events.listen(&"player_death", _on_player_death)
	events.listen(&"bomb_planted", _on_bomb_planted)
	events.listen(&"bomb_defused", _on_bomb_defused)
	game.on_command(&"buy", _on_buy_command)
	game.on_command(&"sellback", _on_sellback_command)


func tick(t: SimTick) -> void:
	if _buy_open and _buy_ends_usec >= 0 and t.now_usec >= _buy_ends_usec:
		_buy_open = false
		game.events.send(&"buytime_ended", {})
	_update_zones()


# --- What the menu and the HUD read -----------------------------------------

func money(userid: int) -> int:
	return _accounts.get(userid, rules.start_money)


## Sets an account, clamped to what an account may hold: the test range's
## money, or a console command.
func set_money(userid: int, amount: int) -> void:
	_accounts[userid] = clampi(amount, 0, rules.max_money)


## Whether it is a time buying is open at all (the buy zone aside).
func buying_open() -> bool:
	return _buy_open and (_buy_ends_usec < 0 or game == null or game.now_usec() < _buy_ends_usec)


## Seconds of buying left, or INF while it has no end yet (freeze time,
## warmup), or 0 once it is over.
func buy_seconds_left(now_usec: int) -> float:
	if not _buy_open:
		return 0.0
	if _buy_ends_usec < 0:
		return INF
	return maxf(0.0, float(_buy_ends_usec - now_usec) / 1_000_000.0)


func in_buy_zone(userid: int) -> bool:
	if rules.buy_anywhere:
		return true
	var player := game.roster.player(userid) if game != null else null
	return player != null and zones.contains(_side(userid), player.global_position)


## A side's place on the loss ladder, and what its next loss would pay.
func losses(side: String) -> int:
	return _losses.get(side, 0)


func loss_bonus(side: String) -> int:
	return rules.loss_bonus + rules.loss_bonus_step * mini(losses(side), rules.loss_steps_max)


## What an item would cost this player now: the helmet alone over full
## kevlar, the vest alone under a helmet, anything else its price.
func price_for(userid: int, item_class: String) -> int:
	if not ItemRegistry.has(item_class):
		return 0
	var price := ItemRegistry.item(item_class).price
	if item_class == "item_assaultsuit" and game != null:
		var inv := game.inventory(userid)
		if inv != null:
			if inv.armor >= 100 and not inv.helmet:
				return rules.helmet_price
			if inv.helmet and inv.armor < 100:
				return ItemRegistry.item("item_kevlar").price
	return price


## Why this player may not buy anything now (not on a side, dead, buying
## over, out of the buy zone), or OK if they may shop.
func shop_refusal(userid: int) -> StringName:
	var side := _side(userid)
	if side != "T" and side != "CT":
		return NOT_PLAYING
	if not _alive(userid):
		return DEAD
	if not buying_open():
		return BUY_TIME_OVER
	if not in_buy_zone(userid):
		return NOT_IN_BUY_ZONE
	return OK


## Why this player may not buy this now, or OK if they may.
func refusal(userid: int, item_class: String) -> StringName:
	if not ItemRegistry.has(item_class):
		return NOT_SOLD
	var item := ItemRegistry.item(item_class)
	if not item.buyable:
		return NOT_SOLD
	if item_class == "item_assaultsuit" and rules.max_armor < 2 \
			or item_class == "item_kevlar" and rules.max_armor < 1:
		return NOT_SOLD
	var shopping := shop_refusal(userid)
	if shopping != OK:
		return shopping
	if not item.team.is_empty() and item.team != _side(userid):
		return WRONG_TEAM
	var inv := game.inventory(userid)
	if inv.has(item_class) and item.is_gun:
		return ALREADY_HAVE
	if inv.can_add(item_class) == Inventory.Can.FULL:
		return CANNOT_CARRY if item.slot == ItemDef.Slot.GRENADE else ALREADY_HAVE
	var limit := rules.zeus_purchases if item.type == "taser" else rules.type_purchases
	if limit >= 0 and _type_count(userid, item.type) >= limit:
		return TYPE_LIMIT
	if money(userid) < price_for(userid, item_class):
		return NO_MONEY
	return OK


## Whether this player could undo a purchase of this item now.
func can_undo(userid: int, item_class: String) -> bool:
	return _undo_refusal(userid, item_class) == OK


## Sends a player's buy command for an item; the next tick buys it or
## refuses.
func buy(userid: int, item_class: String) -> void:
	game.command(userid, "buy " + item_class)


## Sends a player's command to undo this round's purchase of an item.
func undo(userid: int, item_class: String) -> void:
	game.command(userid, "sellback " + item_class)


## The class an item is named by in a buy command: its class name, or the
## name CS2's own buy command takes ("ak47", "vesthelm", "defuser"); "" for
## nothing sold by that name.
static func item_named(name: String) -> String:
	var lower := name.to_lower()
	if ItemRegistry.has(lower):
		return lower
	match lower:
		"vest":
			return "item_kevlar"
		"vesthelm":
			return "item_assaultsuit"
	for prefix in ["weapon_", "item_"]:
		if ItemRegistry.has(prefix + lower):
			return prefix + lower
	return ""


# --- Buying ------------------------------------------------------------------

func _on_buy_command(userid: int, args: PackedStringArray, _t: SimTick) -> bool:
	if args.is_empty():
		return false
	_buy(userid, item_named(args[0]))
	return true


func _on_sellback_command(userid: int, args: PackedStringArray, _t: SimTick) -> bool:
	if args.is_empty():
		return false
	_undo(userid, item_named(args[0]))
	return true


func _buy(userid: int, item_class: String) -> void:
	if refusal(userid, item_class) != OK:
		return
	var inv := game.inventory(userid)
	var price := price_for(userid, item_class)
	var record := {"item": item_class, "price": price, "armor": inv.armor, "helmet": inv.helmet}
	var replaced := inv.add(item_class)
	_accounts[userid] = money(userid) - price
	if not _bought.has(userid):
		_bought[userid] = []
	_bought[userid].append(record)
	var type := ItemRegistry.item(item_class).type
	_type_counts[userid] = _type_counts.get(userid, {})
	_type_counts[userid][type] = _type_count(userid, type) + 1
	var side := _side(userid)
	game.events.send(&"item_purchase", {
		"userid": userid, "team": side,
		"loadout": Loadout.index_of(side, item_class), "weapon": item_class,
	})
	# A gun it replaced falls at the buyer's feet.
	for entry in replaced:
		DroppedItem.drop(game, userid, entry)
		game.events.send(&"item_remove", {"userid": userid, "item": entry.item.item_class})


func _undo_refusal(userid: int, item_class: String) -> StringName:
	if not rules.sellback or not buying_open() or not _alive(userid) or not in_buy_zone(userid):
		return NOTHING_TO_UNDO
	if _last_purchase(userid, item_class) < 0:
		return NOTHING_TO_UNDO
	var inv := game.inventory(userid)
	match item_class:
		"item_kevlar", "item_assaultsuit":
			# Only armour as it was bought: a hit since has worn it.
			return OK if inv.armor >= 100 else NOTHING_TO_UNDO
		"item_defuser":
			return OK if inv.has_defuser else NOTHING_TO_UNDO
	return OK if inv.count(item_class) > 0 else NOTHING_TO_UNDO


## Undoing a purchase: the item comes out of the inventory, its price back
## into the account, and item_remove says so. A gun it replaced stays where
## it was dropped.
func _undo(userid: int, item_class: String) -> void:
	if _undo_refusal(userid, item_class) != OK:
		return
	var index := _last_purchase(userid, item_class)
	var record: Dictionary = _bought[userid][index]
	_bought[userid].remove_at(index)
	var inv := game.inventory(userid)
	match item_class:
		"item_kevlar", "item_assaultsuit":
			inv.armor = record["armor"]
			inv.helmet = record["helmet"]
		"item_defuser":
			inv.has_defuser = false
		_:
			if ItemRegistry.item(item_class).slot == ItemDef.Slot.GRENADE:
				inv.take_one(item_class)
			else:
				inv.remove(item_class)
	_accounts[userid] = mini(money(userid) + int(record["price"]), rules.max_money)
	var type := ItemRegistry.item(item_class).type
	_type_counts[userid][type] = maxi(_type_count(userid, type) - 1, 0)
	game.events.send(&"item_remove", {"userid": userid, "item": item_class})


func _last_purchase(userid: int, item_class: String) -> int:
	var records: Array = _bought.get(userid, [])
	for i in range(records.size() - 1, -1, -1):
		if records[i]["item"] == item_class:
			return i
	return -1


func _type_count(userid: int, type: String) -> int:
	return (_type_counts.get(userid, {}) as Dictionary).get(type, 0)


## Tells each player when they step into or out of their buy zone, as CS2's
## enter_buyzone and exit_buyzone do.
func _update_zones() -> void:
	for userid in game.roster.ids():
		var inside := in_buy_zone(userid) and _alive(userid)
		if inside == bool(_in_zone.get(userid, false)):
			continue
		_in_zone[userid] = inside
		game.events.send(&"enter_buyzone" if inside else &"exit_buyzone",
			{"userid": userid, "canbuy": inside and buying_open()})


# --- Money -------------------------------------------------------------------

func _on_begin_new_match(_event: GameEvent) -> void:
	_rounds_played = 0
	_reset_accounts(rules.start_money)
	_reset_ladders()


## Half time, and each half of overtime: everyone back to the half's money,
## the ladders back to where a half starts.
func _on_half(_event: GameEvent) -> void:
	var overtime := _rounds_played >= match_rules.max_rounds
	_reset_accounts(rules.overtime_start_money if overtime else rules.start_money)
	_reset_ladders()


func _on_round_start(_event: GameEvent) -> void:
	_planted = false
	_dead.clear()
	_bought.clear()
	_type_counts.clear()
	_buy_open = true
	_buy_ends_usec = -1


func _on_freeze_end(event: GameEvent) -> void:
	_buy_ends_usec = event.at_usec + int(roundf(rules.buy_seconds * 1_000_000.0))


func _on_player_death(event: GameEvent) -> void:
	var victim: int = event.fields["userid"]
	var attacker: int = event.fields["attacker"]
	_dead[victim] = true
	if not rules.player_cash_awards:
		return
	if attacker < 0 or attacker == victim:
		_pay(attacker if attacker >= 0 else victim, rules.suicide)
	elif _side(attacker) == _side(victim):
		_pay(attacker, rules.team_kill)
	else:
		_pay(attacker, _kill_award(String(event.fields["weapon"])))


func _on_bomb_planted(event: GameEvent) -> void:
	_planted = true
	if rules.player_cash_awards:
		_pay(event.fields["userid"], rules.bomb_planted)


func _on_bomb_defused(event: GameEvent) -> void:
	if rules.player_cash_awards:
		_pay(event.fields["userid"], rules.bomb_defused)


## A round won: the winners' reward by how they won it, the losers' loss
## bonus by their ladder, and the ladders moved.
func _on_round_end(event: GameEvent) -> void:
	_rounds_played += 1
	_buy_open = false
	var winner := String(event.fields["winner"])
	var reason := String(event.fields["reason"])
	if winner != "T" and winner != "CT":
		return
	var loser := "CT" if winner == "T" else "T"
	if rules.team_cash_awards:
		var won := win_reward(reason)
		var bonus := loss_bonus(loser)
		for userid in game.roster.ids():
			var side := _side(userid)
			if side == winner:
				_pay(userid, won)
			elif side == loser:
				_pay(userid, _loser_pay(userid, loser, reason, bonus))
	_losses[loser] = mini(losses(loser) + 1, rules.loss_steps_max)
	_hold_next_win[loser] = true
	_step_down(winner)


## What each winner gets for a round won this way (a CS2 round end reason).
func win_reward(reason: String) -> int:
	match reason:
		"TargetBombed":
			return rules.win_bomb_exploded
		"BombDefused":
			return rules.win_bomb_defused
		"TargetSaved":
			return rules.win_time
	return rules.win_elimination


## One loser's money for the round: the loss bonus, the planters' extra, or
## nothing for a terrorist who lived through a round lost on time.
func _loser_pay(userid: int, loser: String, reason: String, bonus: int) -> int:
	if loser == "T" and reason == "TargetSaved" and rules.no_bonus_for_time_survivors \
			and not _dead.has(userid):
		return 0
	if loser == "T" and _planted:
		return bonus + rules.planted_but_lost
	return bonus


## A win moves the winners' ladder by loss_aversion: back to the bottom
## (0), one step down (1), or one step down from the second win in a row
## (2).
func _step_down(side: String) -> void:
	match rules.loss_aversion:
		0:
			_losses[side] = 0
		2:
			if _hold_next_win[side]:
				_hold_next_win[side] = false
			else:
				_losses[side] = maxi(losses(side) - 1, 0)
		_:
			_losses[side] = maxi(losses(side) - 1, 0)


func _kill_award(weapon_class: String) -> int:
	var award := -1
	if ItemRegistry.has(weapon_class):
		award = ItemRegistry.item(weapon_class).kill_award
	if award < 0:
		return rules.kill_award_default
	return roundi(award * rules.kill_award_factor)


func _pay(userid: int, amount: int) -> void:
	if userid < 0 or amount == 0:
		return
	_accounts[userid] = clampi(money(userid) + amount, 0, rules.max_money)


func _reset_accounts(amount: int) -> void:
	if game == null:
		return
	for userid in game.roster.ids():
		_accounts[userid] = mini(amount, rules.max_money)


func _reset_ladders() -> void:
	for side in ["T", "CT"]:
		_losses[side] = clampi(rules.starting_losses, 0, rules.loss_steps_max)
		_hold_next_win[side] = rules.starting_losses > 0


func _side(userid: int) -> String:
	return game.roster.team_of(userid) if game != null else ""


func _alive(userid: int) -> bool:
	if _dead.has(userid):
		return false
	var player := game.roster.player(userid) if game != null else null
	return player != null and bool(player.get("alive") if "alive" in player else true)
