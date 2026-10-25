class_name BotTrade
extends RefCounted
## Bot trading (P3-BOTTRADE). Pure decisions over Trade offers: Bot.decide() calls answer() for an
## open offer to a bot and proposal() on the bot's own turn. Nothing here changes state. Numbers
## come from data/bot.json (heuristics, docs/OPEN_QUESTIONS.md Q18).
##
## Scoring. A player's position = each deed's list price (mortgaged: list price minus the lift
## cost) + complete_set_bonus_percent of a color set's total list price for every full set. The gain
## of a trade for one side = its position change + cash and pardon cards (worth the jail fine) in -
## out - transfer interest - the set bonus of any set the other side completes + (buying from a
## person) monopoly_block_bonus_percent of a set's total for the one deed a third commander lacks.
##
## Answer (offer to a bot):
## - Reject outright: invalid; the bot would give a pardon card or a deed of a set it fully owns;
##   its cash would fall below cash_buffer; or the proposer completes a set and the bot does not
##   complete one at least as expensive.
## - Accept when gain > 0 and gain >= the margin: (trade_min_cash_percent - 100)% of the given deeds'
##   list prices when no deed comes back, (trade_swap_min_percent - 100)% when deeds come back.
## - Else counter once (never a counter-offer) asking the shortfall in cash, if it is at most
##   trade_counter_max_percent of the given deeds' list prices; else reject.
## Propose (own turn, no open offer, once per turn): buy the one deed missing from the bot's nearly
## complete set (from anyone), or the one deed another commander lacks for a set (from a person
## only: a bot holder never sells it to them anyway). Cash is priced so the seller's side clears the
## margin; when that would break cash_buffer, up to trade_max_surplus_deeds spare deeds are added.
## The best positive gain wins; no +EV deal means no proposal.


## Whole-percent share of a value, rounded up.
static func _pct(value: int, percent: int) -> int:
	return int(ceil(value * percent / 100.0))


## space_index -> owner for every deed.
static func _owners(board: Board) -> Dictionary:
	var out := {}
	for s in board.spaces:
		if s.deed != null:
			out[s.index] = s.deed.owner
	return out


static func _owners_after(board: Board, offer: Trade.Offer) -> Dictionary:
	var out := _owners(board)
	for i in offer.give_deeds:
		out[i] = offer.to_id
	for i in offer.get_deeds:
		out[i] = offer.from_id
	return out


static func group_price(board: Board, group_id: StringName) -> int:
	var total := 0
	for i: int in board.color_groups[group_id]:
		total += board.deed_at(i).list_price
	return total


static func _full_sets(board: Board, own: Dictionary, pid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for gid: StringName in board.color_groups:
		if _missing(board, own, gid, pid).is_empty():
			out.append(gid)
	return out


## Deeds of the set `pid` does not own under `own`.
static func _missing(board: Board, own: Dictionary, group_id: StringName, pid: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in board.color_groups[group_id]:
		if own[i] != pid:
			out.append(i)
	return out


## The single deed `pid` lacks for the set, or -1.
static func _missing_one(board: Board, own: Dictionary, group_id: StringName, pid: int) -> int:
	var m := _missing(board, own, group_id, pid)
	return m[0] if m.size() == 1 else -1


## Sets `pid` fully owns after but not before.
static func _new_sets(board: Board, before: Dictionary, after: Dictionary, pid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var had := _full_sets(board, before, pid)
	for gid in _full_sets(board, after, pid):
		if not had.has(gid):
			out.append(gid)
	return out


static func _best_set_price(board: Board, sets: Array[StringName]) -> int:
	var best := 0
	for gid in sets:
		best = maxi(best, group_price(board, gid))
	return best


static func position(tc: TurnController, pid: int, own: Dictionary) -> int:
	var v := 0
	for i: int in own:
		if own[i] == pid:
			var d := tc.board.deed_at(i)
			v += d.list_price - (Rules.unmortgage_cost(d, tc.config) if d.is_mortgaged else 0)
	for gid in _full_sets(tc.board, own, pid):
		v += _pct(group_price(tc.board, gid), tc.bot_settings.complete_set_bonus_percent)
	return v


## True when deed `i` is the one deed some commander other than `pid` and `other` lacks for its set.
static func _blocks(tc: TurnController, own: Dictionary, i: int, pid: int, other: int) -> bool:
	var gid := tc.board.deed_at(i).color_group_id
	if not tc.board.color_groups.has(gid):
		return false
	for x in tc.players:
		if x.id != pid and x.id != other and not x.is_bankrupt and _missing_one(tc.board, own, gid, x.id) == i:
			return true
	return false


# --- One side of an offer --------------------------------------------------------------------

static func _deeds_in(offer: Trade.Offer, pid: int) -> Array[int]:
	return offer.get_deeds if pid == offer.from_id else offer.give_deeds


static func _deeds_out(offer: Trade.Offer, pid: int) -> Array[int]:
	return offer.give_deeds if pid == offer.from_id else offer.get_deeds


static func _cash_in(offer: Trade.Offer, pid: int) -> int:
	return offer.get_cash if pid == offer.from_id else offer.give_cash


static func _cash_out(offer: Trade.Offer, pid: int) -> int:
	return offer.give_cash if pid == offer.from_id else offer.get_cash


static func _list_total(board: Board, indices: Array[int]) -> int:
	var total := 0
	for i in indices:
		total += board.deed_at(i).list_price
	return total


## What the trade is worth to `pid` (see the class doc). `rival_sets` false leaves out the penalty
## for sets the other side completes (used to price an offer to a person).
static func gain(tc: TurnController, pid: int, offer: Trade.Offer, rival_sets: bool = true) -> int:
	var other := offer.to_id if pid == offer.from_id else offer.from_id
	var before := _owners(tc.board)
	var after := _owners_after(tc.board, offer)
	var deeds_in := _deeds_in(offer, pid)
	var cards_in := offer.get_cards.size() if pid == offer.from_id else offer.give_cards.size()
	var cards_out := offer.give_cards.size() if pid == offer.from_id else offer.get_cards.size()
	var g := position(tc, pid, after) - position(tc, pid, before)
	g += _cash_in(offer, pid) - _cash_out(offer, pid) - Trade.interest_due(tc.board, deeds_in, tc.config)
	g += (cards_in - cards_out) * tc.config.jail_fine
	if rival_sets:
		for gid in _new_sets(tc.board, before, after, other):
			g -= _pct(group_price(tc.board, gid), tc.bot_settings.complete_set_bonus_percent)
	if not tc.players[other].is_bot:
		for i in deeds_in:
			if _blocks(tc, before, i, pid, other):
				g += _pct(group_price(tc.board, tc.board.deed_at(i).color_group_id),
					tc.bot_settings.monopoly_block_bonus_percent)
	return g


## Least gain `pid` asks for: a premium over the list price of the deeds it gives.
static func margin(tc: TurnController, pid: int, offer: Trade.Offer) -> int:
	var s := tc.bot_settings
	var percent := s.trade_min_cash_percent if _deeds_in(offer, pid).is_empty() else s.trade_swap_min_percent
	return _pct(_list_total(tc.board, _deeds_out(offer, pid)), percent - 100)


## Reasons `pid` refuses whatever the price (see the class doc).
static func refuses(tc: TurnController, pid: int, offer: Trade.Offer) -> bool:
	if not Trade.is_valid(tc.board, tc.players, offer, tc.config):
		return true
	var cards_out := offer.give_cards if pid == offer.from_id else offer.get_cards
	if not cards_out.is_empty():
		return true
	for i in _deeds_out(offer, pid):
		if tc.board.owns_full_group(pid, tc.board.deed_at(i).color_group_id):
			return true
	var p := tc.players[pid]
	var pays := _cash_out(offer, pid) + Trade.interest_due(tc.board, _deeds_in(offer, pid), tc.config)
	if pays > 0 and p.cash + _cash_in(offer, pid) - pays < tc.bot_settings.cash_buffer:
		return true
	var other := offer.to_id if pid == offer.from_id else offer.from_id
	var before := _owners(tc.board)
	var after := _owners_after(tc.board, offer)
	var theirs := _new_sets(tc.board, before, after, other)
	if theirs.is_empty():
		return false
	return _best_set_price(tc.board, _new_sets(tc.board, before, after, pid)) < _best_set_price(tc.board, theirs)


static func accepts(tc: TurnController, pid: int, offer: Trade.Offer) -> bool:
	if refuses(tc, pid, offer):
		return false
	var g := gain(tc, pid, offer)
	return g > 0 and g >= margin(tc, pid, offer)


## The bot's answer to the open offer made to it: ACCEPT_TRADE, COUNTER_TRADE or REJECT_TRADE.
static func answer(tc: TurnController, offer: Trade.Offer) -> Bot.Action:
	var pid := offer.to_id
	if accepts(tc, pid, offer):
		return Bot.Action.new(Bot.Kind.ACCEPT_TRADE, pid)
	var reject := Bot.Action.new(Bot.Kind.REJECT_TRADE, pid)
	if offer.is_counter or refuses(tc, pid, offer):
		return reject
	var given := _list_total(tc.board, offer.get_deeds)
	var short := maxi(maxi(margin(tc, pid, offer), 1) - gain(tc, pid, offer), 1)
	if given == 0 or short > _pct(given, tc.bot_settings.trade_counter_max_percent):
		return reject
	# Same terms back, with the shortfall taken off the bot's cash first, then asked from the proposer.
	var reply := Trade.mirror(offer)
	var cut := mini(reply.give_cash, short)
	reply.give_cash -= cut
	reply.get_cash += short - cut
	if not accepts(tc, pid, reply):
		return reject
	var a := Bot.Action.new(Bot.Kind.COUNTER_TRADE, pid)
	a.offer = reply
	return a


# --- Proposals -------------------------------------------------------------------------------

## The best +EV deal for bot `p` this turn, or null.
static func proposal(tc: TurnController, p: Player) -> Trade.Offer:
	var own := _owners(tc.board)
	var best: Trade.Offer = null
	var best_gain := 0
	for gid: StringName in tc.board.color_groups:
		var target := _missing_one(tc.board, own, gid, p.id)
		var completes := target >= 0
		if not completes:
			target = _block_target(tc, own, gid, p.id)
		if target < 0:
			continue
		var seller := int(own[target])
		if seller < 0 or seller == p.id or tc.players[seller].is_bankrupt:
			continue
		var offer := _priced_offer(tc, p, seller, target, completes, own)
		if offer == null:
			continue
		var g := gain(tc, p.id, offer)
		if g > best_gain:
			best = offer
			best_gain = g
	return best


## The deed another commander lacks for this set when a person (not that commander, not `pid`)
## holds it, or -1.
static func _block_target(tc: TurnController, own: Dictionary, group_id: StringName, pid: int) -> int:
	for x in tc.players:
		if x.id == pid or x.is_bankrupt:
			continue
		var m := _missing_one(tc.board, own, group_id, x.id)
		if m < 0:
			continue
		var holder := int(own[m])
		if holder >= 0 and holder != pid and not tc.players[holder].is_bot:
			return m
	return -1


## Cheapest workable offer for `target`: cash only, then with 1..trade_max_surplus_deeds spare deeds.
## A bot seller must accept it as priced; a person decides for themselves.
static func _priced_offer(tc: TurnController, p: Player, seller: int, target: int, completes: bool,
		own: Dictionary) -> Trade.Offer:
	var s := tc.bot_settings
	var spare := _spare_deeds(tc, p.id, seller, completes, own)
	var seller_is_bot := tc.players[seller].is_bot
	for k in range(0, mini(spare.size(), s.trade_max_surplus_deeds) + 1):
		var offer := Trade.propose(p.id, seller)
		offer.get_deeds = [target] as Array[int]
		for j in k:
			offer.give_deeds.append(spare[j])
		var seller_gain := gain(tc, seller, offer, seller_is_bot)
		offer.give_cash = maxi(0, maxi(margin(tc, seller, offer), 1) - seller_gain)
		if refuses(tc, p.id, offer) or gain(tc, p.id, offer) <= 0:
			continue
		if seller_is_bot and not accepts(tc, seller, offer):
			continue
		return offer
	return null


## Deeds bot `pid` can spare, best first: a deed completing the seller's set (only when the bot
## completes its own set in return), then cheapest. Never mortgaged deeds, deeds of a full set, or
## deeds of a set the bot lacks one deed for (unless it completes the seller's set as above).
static func _spare_deeds(tc: TurnController, pid: int, seller: int, completes: bool, own: Dictionary) -> Array[int]:
	var swaps: Array[int] = []
	var plain: Array[PropertyDeed] = []
	for d in tc.board.deeds_owned_by(pid):
		if d.is_mortgaged or not Trade.can_trade_deed(tc.board, pid, d.space_index):
			continue
		var gid := d.color_group_id
		if tc.board.color_groups.has(gid):
			if tc.board.owns_full_group(pid, gid):
				continue
			if _missing_one(tc.board, own, gid, seller) == d.space_index:
				if completes:
					swaps.append(d.space_index)
				continue
			if _missing_one(tc.board, own, gid, pid) >= 0:
				continue
		plain.append(d)
	plain.sort_custom(func(a: PropertyDeed, b: PropertyDeed) -> bool: return a.list_price < b.list_price)
	for d in plain:
		swaps.append(d.space_index)
	return swaps
