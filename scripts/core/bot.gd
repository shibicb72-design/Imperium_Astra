class_name Bot
extends RefCounted
## Simple hotseat opponent. Pure decisions: decide() reads the match and returns one Action; it
## never changes state. TurnController.bot_step() applies the Action through the same public
## actions a person uses, so bots obey every rule check. Numbers come from data/bot.json
## (heuristics, docs/OPEN_QUESTIONS.md Q18).
##
## Heuristics (classic-flavored, deliberately simple):
## - Buy unowned land if cash_buffer stays after paying; else decline (-> auction).
## - Auction: raise by the minimum step up to min(cash - cash_buffer, list price %); else drop out.
## - Manage (own turn, before rolling and before ending): lift mortgages while
##   unmortgage_min_cash_after stays, then build evenly on the cheapest street while cash_buffer stays.
## - Jail: pardon card, else pay the fine if cash_buffer stays, else roll; on the last try pay first.
## - Debt: pay if cash covers it; bankrupt if even full liquidation cannot; else sell buildings
##   (highest level first), then mortgage (deeds outside full sets first, cheapest first).
## - Trade: never proposes; accepts only plain cash-for-deed offers worth trade_min_cash_percent
##   of list price that do not hand the proposer a full color set. Everything else is rejected.

enum Kind {
	NONE, ROLL, PAY_JAIL_FINE, USE_PARDON, BUY, DECLINE, BID, PASS_AUCTION, BUILD, SELL_BUILDING,
	SELL_GROUP, MORTGAGE, UNMORTGAGE, PAY_DEBT, DECLARE_BANKRUPTCY, ACCEPT_TRADE, REJECT_TRADE,
	END_TURN,
}

const P := TurnController.Phase


## One decision. `space_index` for BUILD / SELL_BUILDING / MORTGAGE / UNMORTGAGE, `amount` for BID,
## `group_id` for SELL_GROUP.
class Action:
	var kind: Kind
	var player_id: int
	var space_index: int = -1
	var amount: int = 0
	var group_id: StringName = &""

	func _init(p_kind: Kind, p_player_id: int) -> void:
		kind = p_kind
		player_id = p_player_id


## Typed view of data/bot.json.
class Settings:
	var cash_buffer: int
	var auction_max_price_percent: int
	var unmortgage_min_cash_after: int
	var trade_min_cash_percent: int

	static func from_dict(d: Dictionary) -> Settings:
		var s := Settings.new()
		s.cash_buffer = int(d["cash_buffer"])
		s.auction_max_price_percent = int(d["auction_max_price_percent"])
		s.unmortgage_min_cash_after = int(d["unmortgage_min_cash_after"])
		s.trade_min_cash_percent = int(d["trade_min_cash_percent"])
		return s


## What player `pid` does next. Kind.NONE when the game is not waiting on them.
static func decide(tc: TurnController, pid: int) -> Action:
	var p := tc.players[pid]
	var s := tc.bot_settings
	if tc.phase == P.GAME_OVER:
		return Action.new(Kind.NONE, pid)
	if p.is_bankrupt:
		# Went bankrupt on its own turn: the turn still has to be handed on.
		var hand_on := tc.phase == P.AWAITING_END_TURN and tc.current_index == pid
		return Action.new(Kind.END_TURN if hand_on else Kind.NONE, pid)
	if tc.trade_offer != null and tc.trade_offer.to_id == pid:
		var ok := wants_trade(tc, tc.trade_offer)
		return Action.new(Kind.ACCEPT_TRADE if ok else Kind.REJECT_TRADE, pid)
	if tc.deciding_player() != pid:
		return Action.new(Kind.NONE, pid)
	match tc.phase:
		P.RAISING_FUNDS:
			return _raise_funds(tc, p)
		P.AUCTION:
			return _auction(tc, p, s)
		P.AWAITING_BUY_DECISION:
			var price := tc.board.deed_at(tc.pending_buy_index).list_price
			return Action.new(Kind.BUY if p.cash - price >= s.cash_buffer else Kind.DECLINE, pid)
		P.AWAITING_ROLL:
			var before_roll := _manage(tc, p, s)
			if before_roll != null:
				return before_roll
			if p.in_jail:
				return _jail(tc, p, s)
			return Action.new(Kind.ROLL, pid)
		P.AWAITING_END_TURN:
			var before_end := _manage(tc, p, s)
			return before_end if before_end != null else Action.new(Kind.END_TURN, pid)
	return Action.new(Kind.NONE, pid)


static func _jail(tc: TurnController, p: Player, s: Settings) -> Action:
	var fine := tc.config.jail_fine
	if not p.goojf_cards.is_empty():
		return Action.new(Kind.USE_PARDON, p.id)
	if p.cash - fine >= s.cash_buffer:
		return Action.new(Kind.PAY_JAIL_FINE, p.id)
	if p.jail_turns_tried >= tc.config.max_jail_turns - 1 and p.cash >= fine:
		return Action.new(Kind.PAY_JAIL_FINE, p.id)
	return Action.new(Kind.ROLL, p.id)


## Highest bid this bot will make on the running auction's deed.
static func auction_limit(tc: TurnController, p: Player, s: Settings) -> int:
	var price := tc.board.deed_at(tc.auction.space_index).list_price
	return mini(p.cash - s.cash_buffer, int(price * s.auction_max_price_percent / 100.0))


static func _auction(tc: TurnController, p: Player, s: Settings) -> Action:
	var next := tc.auction.min_next_bid()
	if next <= auction_limit(tc, p, s) and next <= p.cash:
		var a := Action.new(Kind.BID, p.id)
		a.amount = next
		return a
	return Action.new(Kind.PASS_AUCTION, p.id)


## Lift a mortgage, else build one level; null when there is nothing worth doing.
static func _manage(tc: TurnController, p: Player, s: Settings) -> Action:
	var best_lift: PropertyDeed = null
	var best_lift_cost := 0
	for d in tc.board.deeds_owned_by(p.id):
		if not d.is_mortgaged:
			continue
		var cost := Rules.unmortgage_cost(d, tc.config)
		if p.cash - cost >= s.unmortgage_min_cash_after and (best_lift == null or cost < best_lift_cost):
			best_lift = d
			best_lift_cost = cost
	if best_lift != null:
		var a := Action.new(Kind.UNMORTGAGE, p.id)
		a.space_index = best_lift.space_index
		return a
	var target := build_target(tc, p, s)
	if target != null:
		var a := Action.new(Kind.BUILD, p.id)
		a.space_index = target.space_index
		return a
	return null


## Cheapest legal next building (lowest level, then lowest cost) that keeps cash_buffer, or null.
## Building.can_build enforces full set, no mortgages and even building.
static func build_target(tc: TurnController, p: Player, s: Settings) -> PropertyDeed:
	var best: PropertyDeed = null
	for d in tc.board.deeds_owned_by(p.id):
		if not Building.can_build(tc.board, tc.bank, p, d):
			continue
		var cost := d.hotel_cost if d.houses == Building.MAX_HOUSES else d.house_cost
		if p.cash - cost < s.cash_buffer:
			continue
		if best == null or Building.level(d) < Building.level(best) or (
				Building.level(d) == Building.level(best) and d.house_cost < best.house_cost):
			best = d
	return best


static func _raise_funds(tc: TurnController, p: Player) -> Action:
	var debt := tc.current_debt()
	if p.cash >= debt.amount:
		return Action.new(Kind.PAY_DEBT, p.id)
	if tc.can_declare_bankruptcy():
		return Action.new(Kind.DECLARE_BANKRUPTCY, p.id)
	# 1) Sell buildings, highest level first.
	var sell: PropertyDeed = null
	var stuck_group := &""
	for d in tc.board.deeds_owned_by(p.id):
		if Building.level(d) == 0:
			continue
		if Building.can_sell(tc.board, tc.bank, p, d):
			if sell == null or Building.level(d) > Building.level(sell):
				sell = d
		else:
			stuck_group = d.color_group_id
	if sell != null:
		var a := Action.new(Kind.SELL_BUILDING, p.id)
		a.space_index = sell.space_index
		return a
	if stuck_group != &"":
		# No single building can be sold (a hotel the Bank cannot break into houses): sell the group.
		var a := Action.new(Kind.SELL_GROUP, p.id)
		a.group_id = stuck_group
		return a
	# 2) Mortgage: deeds outside full color sets first, then the cheapest.
	var pick: PropertyDeed = null
	for d in tc.board.deeds_owned_by(p.id):
		if not Mortgage.can_mortgage(tc.board, p, d):
			continue
		if pick == null or _mortgage_rank(tc, p, d) < _mortgage_rank(tc, p, pick):
			pick = d
	if pick != null:
		var a := Action.new(Kind.MORTGAGE, p.id)
		a.space_index = pick.space_index
		return a
	return Action.new(Kind.NONE, p.id)


static func _mortgage_rank(tc: TurnController, p: Player, d: PropertyDeed) -> int:
	var in_set := tc.board.owns_full_group(p.id, d.color_group_id)
	return (100000 if in_set else 0) + d.mortgage_value


## True only for a plain cash-for-deed offer to this bot: cash in, deeds out, nothing else, at
## least trade_min_cash_percent of list price, and no deed that completes the proposer's color set.
static func wants_trade(tc: TurnController, offer: Trade.Offer) -> bool:
	if not offer.give_deeds.is_empty() or not offer.give_cards.is_empty():
		return false
	if offer.get_cash != 0 or not offer.get_cards.is_empty() or offer.get_deeds.is_empty():
		return false
	if not Trade.is_valid(tc.board, tc.players, offer, tc.config):
		return false
	var value := 0
	for i in offer.get_deeds:
		var d := tc.board.deed_at(i)
		value += d.list_price
		if tc.board.owns_full_group(offer.to_id, d.color_group_id):
			return false
		if _completes_set(tc, offer.from_id, d.color_group_id, offer.get_deeds):
			return false
	return offer.give_cash * 100 >= value * tc.bot_settings.trade_min_cash_percent


static func _completes_set(tc: TurnController, buyer_id: int, group_id: StringName, incoming: Array[int]) -> bool:
	if not tc.board.color_groups.has(group_id):
		return false
	for i: int in tc.board.color_groups[group_id]:
		if tc.board.deed_at(i).owner != buyer_id and not incoming.has(i):
			return false
	return true
