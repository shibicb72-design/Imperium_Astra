class_name TurnController
extends RefCounted
## Turn state machine (docs/classic_monopoly_structure.md section 3, 6). Pure logic: the UI only
## calls the public actions below and listens to signals.
##
## Scope: roll/move, GO salary, buy, rent (auto-asked: the owner always asks in local play),
## taxes, cards, jail (fine / pardon card / doubles / third-turn fine), auctions, building,
## mortgaging, trades, debts and bankruptcy. The rules for those live in the Auction, Building,
## Mortgage, Trade and Bankruptcy modules; this class only sequences them.
##
## Payments go through _charge(): a payment the payer cannot cover becomes a queued Debt and the
## game enters RAISING_FUNDS until the debtor pays or goes bankrupt. After every step _continue()
## picks the next phase: debts first, then auctions, then the buy decision, then end of landing.
##
## Who may act (official "any time" rules, 3.2 / 4.3 / 6.3; tests/test_phase.gd):
## - Any time, any active commander, on or off turn and also while in the Brig, every phase but
##   GAME_OVER (gate: can_manage): build, sell_building, sell_group_buildings, mortgage,
##   unmortgage, propose/accept/reject/counter/cancel trade. Jail never blocks these.
## - Current player only, by design: roll (incl. the jail doubles try), pay_jail_fine and
##   use_get_out_of_jail_card (before rolling, AWAITING_ROLL), buy/decline, end_turn.
## - Auction bids follow the auction's own bidder order; jailed commanders bid too.
## - pay_debt / declare_bankruptcy belong to whoever owes pending_debts[0], on or off turn.
##
## Bots (Player.is_bot): bot_actor() names the bot the game is waiting on; bot_step() asks Bot for
## one decision and applies it through the public actions above; run_bots() loops that headless.
## The UI paces bot_step() on a timer so people can follow along.
##
## game_event(kind, info) is a presentation hook (pawn tweens, dice roll, dialogue banner). It
## carries ids and numbers only, never theme text; it changes no state. Kinds and info keys:
## rolled {player, d1, d2, doubles}, moved {player, from, to, steps}, passed_go {player, amount},
## landed_unowned {player, space, price}, bought {player, space, price}, rent {player, owner,
## space, amount}, tax {player, space, amount}, card {player, space, deck, text}, jailed {player,
## from, to}, released {player, how: fine|pardon|doubles|forced}, auction_won {player, space,
## amount}, auction_unsold {space}, building_auction_won {player, space, kind, amount},
## building_auction_unsold {kind}, built_house {player, space, houses, cost}, built_hotel {player,
## space, cost} (build or a won building lot), sold_house {player, space, count, houses, amount},
## sold_hotel {player, space, houses, amount} (houses = what stays on the street: 4 after a single
## hotel sale, 0 from sell_group_buildings, which emits one event per street it clears),
## bankrupt {player, creditor} (also covers the buildings a bankruptcy sells; no sold_* for those),
## trade_proposed / trade_accepted / trade_rejected / trade_countered / trade_withdrawn {player,
## other}, game_over {player}.

signal turn_started(player: Player)
signal turn_ended(player: Player)
signal doubles_extra_turn(player: Player)
signal sent_to_jail(player: Player, reason: String)
signal rent_requested(owner: Player, payer: Player, amount: int)
signal winner_declared(player: Player)
signal auction_started(space_index: int)
signal auction_ended(space_index: int, winner_id: int, amount: int)
## Building shortage auction (BuildingLotAuction); kind is Building.HOUSE / Building.HOTEL.
signal building_auction_started(kind: StringName)
## space_index is where it was built, or -1 (and winner_id Auction.NO_BIDDER) if unsold.
signal building_auction_ended(kind: StringName, space_index: int, winner_id: int, amount: int)
signal debt_started(debtor: Player, creditor_id: int, amount: int)
signal player_bankrupt(player: Player, creditor_id: int)
signal trade_proposed(offer: Trade.Offer)
signal trade_resolved(offer: Trade.Offer)
signal status(message: String)
signal state_changed
signal game_event(kind: StringName, info: Dictionary)

enum Phase {
	AWAITING_ROLL, AWAITING_BUY_DECISION, AWAITING_END_TURN, AUCTION, RAISING_FUNDS, GAME_OVER,
}

var config: RulesConfig
var board: Board
var bank: Bank
var dice := Dice.new()
var chance: CardDeck
var community_chest: CardDeck
var players: Array[Player] = []
var current_index: int = 0
var doubles_streak: int = 0
var phase: Phase = Phase.AWAITING_ROLL
var pending_buy_index: int = -1
var last_card: Card = null
var log_lines: Array[String] = []
## Running auction, or null.
var auction: Auction = null
## Oldest first; only pending_debts[0] is being raised for.
var pending_debts: Array[Bankruptcy.Debt] = []
## The open trade offer awaiting its receiver, or null. One at a time.
var trade_offer: Trade.Offer = null
## Heuristics for bot seats (data/bot.json); see Bot and bot_step().
var bot_settings: Bot.Settings = null
## The current (bot) player already tried a trade proposal this turn; reset by end_turn().
var bot_proposed_this_turn := false

var _extra_turn_pending := false
var _auction_queue: Array[int] = []
## A building shortage auction interrupted AWAITING_ROLL; return there once it is settled.
var _resume_roll := false


func current_player() -> Player:
	return players[current_index]


## Official setup: everyone rolls both dice, highest starts (ties re-roll among the tied).
func determine_start_player() -> void:
	var contenders: Array[int] = []
	for p in players:
		contenders.append(p.id)
	while contenders.size() > 1:
		var best := -1
		var leaders: Array[int] = []
		for id in contenders:
			dice.roll()
			if dice.total() > best:
				best = dice.total()
				leaders = [id]
			elif dice.total() == best:
				leaders.append(id)
		contenders = leaders
	current_index = contenders[0]
	_say("%s rolls highest and starts." % current_player().display_name)
	turn_started.emit(current_player())
	state_changed.emit()


func roll() -> void:
	if phase != Phase.AWAITING_ROLL:
		return
	var p := current_player()
	dice.roll()
	_extra_turn_pending = false
	_say("%s rolled %d + %d." % [p.display_name, dice.d1, dice.d2])
	_event(&"rolled", {"player": p.id, "d1": dice.d1, "d2": dice.d2, "doubles": dice.is_doubles()})
	if p.in_jail:
		_roll_in_jail(p)
	elif dice.is_doubles() and doubles_streak + 1 >= config.doubles_to_jail:
		doubles_streak = 0
		_send_to_jail(p, "third doubles in a row")
	else:
		if dice.is_doubles():
			doubles_streak += 1
			_extra_turn_pending = true
		move_by(p, dice.total())
		_resolve_space(p, {"dice_total": dice.total()})
	_after_resolution()


## Section 6.3 option 1: pay the fine at the start of the turn, then roll normally.
func pay_jail_fine() -> bool:
	var p := current_player()
	if phase != Phase.AWAITING_ROLL or not p.in_jail or p.cash < config.jail_fine:
		return false
	bank.collect(p, config.jail_fine)
	_release(p)
	_say("%s pays $%d and leaves %s." % [p.display_name, config.jail_fine, board.term("jail")])
	_event(&"released", {"player": p.id, "how": &"fine"})
	state_changed.emit()
	return true


## Section 6.3 option 2: use a held pardon card; it returns to the bottom of its deck.
func use_get_out_of_jail_card() -> bool:
	var p := current_player()
	if phase != Phase.AWAITING_ROLL or not p.in_jail or p.goojf_cards.is_empty():
		return false
	var card: Card = p.goojf_cards.pop_front()
	_deck_for(card.deck_id).return_to_bottom(card)
	_release(p)
	_say("%s uses a %s and leaves %s." % [p.display_name, board.term("pardon"), board.term("jail")])
	_event(&"released", {"player": p.id, "how": &"pardon"})
	state_changed.emit()
	return true


func buy() -> bool:
	if phase != Phase.AWAITING_BUY_DECISION:
		return false
	var p := current_player()
	var deed := board.deed_at(pending_buy_index)
	if not bank.sell_property(p, deed):
		return false
	_say("%s %s %s for $%d." % [p.display_name, board.term("buys"), board.spaces[pending_buy_index].display_name, deed.list_price])
	_event(&"bought", {"player": p.id, "space": pending_buy_index, "price": deed.list_price})
	pending_buy_index = -1
	_continue()
	return true


## 3.1: declining (or being unable to pay) sends the deed to auction among all active players.
func decline() -> void:
	if phase != Phase.AWAITING_BUY_DECISION:
		return
	_auction_queue.append(pending_buy_index)
	pending_buy_index = -1
	_continue()


# --- Auction (module: Auction) -------------------------------------------------------------

## The current bidder raises to `amount` (at least auction.min_next_bid(), at most their cash).
func auction_bid(amount: int) -> bool:
	if phase != Phase.AUCTION or auction == null or auction.is_finished():
		return false
	var bidder := players[auction.current_bidder()]
	if not auction.bid(bidder.id, amount, bidder.cash):
		return false
	_say("%s bids $%d." % [bidder.display_name, amount])
	_after_auction_step()
	return true


## The current bidder drops out of the running auction.
func auction_pass() -> bool:
	if phase != Phase.AUCTION or auction == null or auction.is_finished():
		return false
	var bidder := players[auction.current_bidder()]
	if not auction.pass_turn(bidder.id):
		return false
	_say("%s drops out." % bidder.display_name)
	_after_auction_step()
	return true


func _start_auction(space_index: int) -> void:
	var bidders: Array[int] = []
	for step in range(1, players.size() + 1):
		var other := players[(current_index + step) % players.size()]
		if not other.is_bankrupt:
			bidders.append(other.id)
	auction = Auction.new(space_index, bidders, config.auction_min_bid, config.auction_increment)
	bank.auction(board.deed_at(space_index))
	_say("Auction: %s, bids from $%d." % [board.spaces[space_index].display_name, config.auction_min_bid])
	auction_started.emit(space_index)


func _after_auction_step() -> void:
	if not auction.is_finished():
		state_changed.emit()
		return
	var a := auction
	auction = null
	if a.is_building_lot():
		_finish_building_auction(a as BuildingLotAuction)
		return
	var s := board.spaces[a.space_index]
	if a.has_winner():
		var winner := players[a.high_bidder]
		s.deed.owner = winner.id
		_say("%s wins %s for $%d." % [winner.display_name, s.display_name, a.high_bid])
		_event(&"auction_won", {"player": winner.id, "space": s.index, "amount": a.high_bid})
		# Cash was checked at bid time; anything spent since then becomes a debt to the Bank.
		_charge(winner, PropertyDeed.BANK, a.high_bid)
	else:
		_say("No bids; %s stays with %s." % [s.display_name, board.term("bank")])
		_event(&"auction_unsold", {"space": s.index})
	auction_ended.emit(a.space_index, a.high_bidder, a.high_bid)
	_continue()


## Building shortage (3.2, OFFICIAL): when several players want more houses / hotels than the Bank
## has, it auctions them from auction_min_bid. `claims` maps each claimant id to the street they
## would build on; every claim must be a legal next building of the same kind, and there must be
## more claimants than Bank stock of that kind (Building.is_contested). One building per auction,
## held out of stock while bidding runs; bidders in seat order left of the current player (as Q3).
## Otherwise returns false and build() stays first come, first served.
## Q10 `_placeholder`: nothing in the game calls this yet. Who counts as wanting a building (claim
## window, how people and bots declare interest) is Shibi's call; see docs/OPEN_QUESTIONS.md Q10.
func start_building_auction(claims: Dictionary[int, int]) -> bool:
	if auction != null or not pending_debts.is_empty():
		return false
	if phase not in [Phase.AWAITING_ROLL, Phase.AWAITING_BUY_DECISION, Phase.AWAITING_END_TURN]:
		return false
	var kind := &""
	for pid: int in claims:
		var i: int = claims[pid]
		if not can_manage(pid) or i < 0 or i >= board.spaces.size():
			return false
		var deed := board.deed_at(i)
		if not Building.can_place(board, players[pid], deed):
			return false
		var k := Building.next_kind(deed)
		if kind != &"" and k != kind:
			return false
		kind = k
	if not Building.is_contested(bank, kind, claims.size()):
		return false
	var bidders: Array[int] = []
	for step in range(1, players.size() + 1):
		var id := (current_index + step) % players.size()
		if claims.has(id):
			bidders.append(id)
	Building.take_lot(bank, kind)
	if phase == Phase.AWAITING_ROLL:
		_resume_roll = true
	auction = BuildingLotAuction.new(kind, claims, bidders, config.auction_min_bid, config.auction_increment)
	_say("%s shortage: one %s goes to auction, bids from $%d." % [
		board.term(String(kind)).capitalize(), board.term(String(kind)), config.auction_min_bid])
	building_auction_started.emit(kind)
	_continue()
	return true


func _finish_building_auction(a: BuildingLotAuction) -> void:
	var space := -1
	if a.has_winner():
		var winner := players[a.high_bidder]
		var i := a.claim_of(winner.id)
		if Building.place_lot(board, bank, winner, board.deed_at(i), a.kind):
			space = i
			_say("%s wins the %s for $%d and builds on %s." % [
				winner.display_name, board.term(String(a.kind)), a.high_bid, board.spaces[i].display_name])
			_event(&"building_auction_won", {"player": winner.id, "space": i, "kind": a.kind, "amount": a.high_bid})
			_built_event(winner, board.deed_at(i), a.high_bid)
			# As with deeds: cash was checked at bid time; any shortfall becomes a debt to the Bank.
			_charge(winner, PropertyDeed.BANK, a.high_bid)
		else:
			# TODO Q10: the winner's claim stopped being legal during bidding (e.g. they mortgaged a
			# street of the set). Placeholder: no sale, no charge, the building goes back to the Bank.
			_say("%s can no longer build on %s; the %s stays with %s." % [
				winner.display_name, board.spaces[i].display_name, board.term(String(a.kind)), board.term("bank")])
	else:
		_say("No bids; the %s stays with %s." % [board.term(String(a.kind)), board.term("bank")])
	if space < 0:
		Building.return_lot(bank, a.kind)
		_event(&"building_auction_unsold", {"kind": a.kind})
	building_auction_ended.emit(a.kind, space, a.high_bidder if space >= 0 else Auction.NO_BIDDER, a.high_bid if space >= 0 else 0)
	_continue()


# --- Building and mortgage (modules: Building, Mortgage); official: any time, any owner --------

func can_manage(player_id: int) -> bool:
	return (phase != Phase.GAME_OVER and player_id >= 0 and player_id < players.size()
		and not players[player_id].is_bankrupt)


func build(player_id: int, space_index: int) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var deed := board.deed_at(space_index)
	var had_houses := deed.houses
	var cost := Building.build(board, bank, p, deed)
	if cost < 0:
		return false
	var what := board.term("hotel") if deed.has_hotel else board.term("house")
	# "1 %s", not "a %s": a pack word may start with a vowel ("outpost module").
	_say("%s builds 1 %s on %s for $%d." % [p.display_name, what, board.spaces[space_index].display_name, cost])
	if had_houses == Building.MAX_HOUSES:
		_say("%d %s return to %s." % [Building.MAX_HOUSES, board.term("houses"), board.term("bank")])
	_built_event(p, deed, cost)
	state_changed.emit()
	return true


func sell_building(player_id: int, space_index: int) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var deed := board.deed_at(space_index)
	var was_hotel := deed.has_hotel
	var what := board.term("hotel") if was_hotel else board.term("house")
	var value := Building.sell(board, bank, p, deed, config)
	if value < 0:
		return false
	_say("%s sells 1 %s on %s for $%d." % [p.display_name, what, board.spaces[space_index].display_name, value])
	_sold_event(p, deed, was_hotel, 1, value)
	state_changed.emit()
	return true


## Sells every building in the group at once (needed when the Bank lacks houses to break a hotel).
func sell_group_buildings(player_id: int, group_id: StringName) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	# Snapshot what each street holds before the sale, for the per-street sold_* events.
	var cleared: Array[Array] = []
	for d in Building.group_deeds(board, group_id):
		if d.owner == p.id and Building.level(d) > 0:
			cleared.append([d, d.has_hotel, d.houses, Building.liquidation_value(d, config)])
	var value := Building.sell_group(board, bank, p, group_id, config)
	if value < 0:
		return false
	_say("%s sells all buildings in %s for $%d." % [
		p.display_name, board.group_info.get(group_id, {}).get("display_name", group_id), value])
	for c in cleared:
		_sold_event(p, c[0], c[1], 1 if c[1] else int(c[2]), int(c[3]))
	state_changed.emit()
	return true


## Presentation hook for a building just placed on `deed` (ids and numbers only).
func _built_event(p: Player, deed: PropertyDeed, cost: int) -> void:
	if deed.has_hotel:
		_event(&"built_hotel", {"player": p.id, "space": deed.space_index, "cost": cost})
	else:
		_event(&"built_house", {"player": p.id, "space": deed.space_index, "houses": deed.houses, "cost": cost})


## Presentation hook for buildings just sold back from `deed`; `count` houses or one hotel.
func _sold_event(p: Player, deed: PropertyDeed, was_hotel: bool, count: int, amount: int) -> void:
	if was_hotel:
		_event(&"sold_hotel", {"player": p.id, "space": deed.space_index, "houses": deed.houses, "amount": amount})
	else:
		_event(&"sold_house", {"player": p.id, "space": deed.space_index, "count": count, "houses": deed.houses,
				"amount": amount})


func mortgage(player_id: int, space_index: int) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var value := Mortgage.mortgage(board, bank, p, board.deed_at(space_index))
	if value < 0:
		return false
	_say("%s mortgages %s for $%d." % [p.display_name, board.spaces[space_index].display_name, value])
	state_changed.emit()
	return true


func unmortgage(player_id: int, space_index: int) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var cost := Mortgage.unmortgage(bank, p, board.deed_at(space_index), config)
	if cost < 0:
		return false
	_say("%s lifts the mortgage on %s for $%d." % [p.display_name, board.spaces[space_index].display_name, cost])
	state_changed.emit()
	return true


# --- Trade (module: Trade); official: any time, also while jailed or raising funds -------------

## Opens `offer` for its receiver. Fails while another offer is open or if the offer is invalid.
func propose_trade(offer: Trade.Offer) -> bool:
	if trade_offer != null or not can_manage(offer.from_id):
		return false
	if not Trade.is_valid(board, players, offer, config):
		return false
	trade_offer = offer
	_say("%s offers %s a trade." % [players[offer.from_id].display_name, players[offer.to_id].display_name])
	_event(&"trade_proposed", {"player": offer.from_id, "other": offer.to_id})
	trade_proposed.emit(offer)
	state_changed.emit()
	return true


## Why the open offer (or a draft) cannot go through, or "" if it can.
func trade_problem(offer: Trade.Offer) -> String:
	return Trade.validate(board, players, offer, config)


func accept_trade(player_id: int) -> bool:
	var offer := trade_offer
	if offer == null or not can_manage(player_id):
		return false
	var a_interest := Trade.interest_due(board, offer.get_deeds, config)
	var b_interest := Trade.interest_due(board, offer.give_deeds, config)
	if not Trade.accept(board, bank, players, offer, player_id, config):
		return false
	trade_offer = null
	_say("%s accepts the trade with %s." % [players[offer.to_id].display_name, players[offer.from_id].display_name])
	_event(&"trade_accepted", {"player": offer.to_id, "other": offer.from_id})
	if a_interest > 0:
		_say("%s pays $%d interest to keep the mortgages." % [players[offer.from_id].display_name, a_interest])
	if b_interest > 0:
		_say("%s pays $%d interest to keep the mortgages." % [players[offer.to_id].display_name, b_interest])
	trade_resolved.emit(offer)
	state_changed.emit()
	return true


func reject_trade(player_id: int) -> bool:
	var offer := trade_offer
	if offer == null or not Trade.reject(offer, player_id):
		return false
	trade_offer = null
	_say("%s rejects the trade." % players[player_id].display_name)
	_event(&"trade_rejected", {"player": player_id, "other": offer.from_id})
	trade_resolved.emit(offer)
	state_changed.emit()
	return true


## The receiver replaces the open offer with `reply`, a new offer back to the proposer.
func counter_trade(reply: Trade.Offer) -> bool:
	var offer := trade_offer
	if offer == null or not can_manage(reply.from_id):
		return false
	if not Trade.counter(board, players, offer, reply, config):
		return false
	trade_offer = reply
	_say("%s makes a counter-offer." % players[reply.from_id].display_name)
	_event(&"trade_countered", {"player": reply.from_id, "other": reply.to_id})
	trade_resolved.emit(offer)
	trade_proposed.emit(reply)
	state_changed.emit()
	return true


## The proposer withdraws the open offer.
func cancel_trade(player_id: int) -> bool:
	var offer := trade_offer
	if offer == null or player_id != offer.from_id:
		return false
	offer.status = Trade.Status.REJECTED
	trade_offer = null
	_say("%s withdraws the trade offer." % players[player_id].display_name)
	_event(&"trade_withdrawn", {"player": player_id, "other": offer.to_id})
	trade_resolved.emit(offer)
	state_changed.emit()
	return true


# --- Debts and bankruptcy (module: Bankruptcy) ------------------------------------------------

func current_debt() -> Bankruptcy.Debt:
	if pending_debts.is_empty():
		return null
	return pending_debts[0]


## The debtor pays the oldest debt once they have raised enough cash.
func pay_debt() -> bool:
	var debt := current_debt()
	if phase != Phase.RAISING_FUNDS or debt == null:
		return false
	var debtor := players[debt.debtor]
	if debtor.cash < debt.amount:
		return false
	pending_debts.pop_front()
	_pay(debtor, debt.creditor, debt.amount)
	_say("%s pays the $%d owed to %s." % [debtor.display_name, debt.amount, _creditor_name(debt.creditor)])
	_continue()
	return true


func can_declare_bankruptcy() -> bool:
	var debt := current_debt()
	return (phase == Phase.RAISING_FUNDS and debt != null
		and Bankruptcy.can_declare(board, players[debt.debtor], debt.amount, config))


## 4.4: only when even selling every building and mortgaging every deed would not cover the debt.
func declare_bankruptcy() -> bool:
	if not can_declare_bankruptcy():
		return false
	var debt := current_debt()
	var debtor := players[debt.debtor]
	var to_player := debt.creditor != PropertyDeed.BANK and not players[debt.creditor].is_bankrupt
	var remaining: Array[Bankruptcy.Debt] = []
	for d in pending_debts:
		if d.debtor != debtor.id:
			remaining.append(d)
	pending_debts = remaining
	if trade_offer != null and debtor.id in [trade_offer.from_id, trade_offer.to_id]:
		trade_offer.status = Trade.Status.REJECTED
		trade_offer = null
	if to_player:
		var creditor := players[debt.creditor]
		var interest := Bankruptcy.settle_to_player(board, bank, debtor, creditor, config)
		_say("%s is bankrupt; everything goes to %s." % [debtor.display_name, creditor.display_name])
		if interest > 0:
			_say("%s pays $%d interest to keep the inherited mortgages." % [creditor.display_name, interest])
			_charge(creditor, PropertyDeed.BANK, interest)
	else:
		var decks: Array[CardDeck] = [chance, community_chest]
		_auction_queue.append_array(Bankruptcy.settle_to_bank(board, bank, debtor, decks))
		_say("%s is bankrupt; holdings return to %s for auction." % [debtor.display_name, board.term("bank")])
	if debtor == current_player():
		pending_buy_index = -1
		_extra_turn_pending = false
	_event(&"bankrupt", {"player": debtor.id, "creditor": debt.creditor if to_player else PropertyDeed.BANK})
	player_bankrupt.emit(debtor, debt.creditor if to_player else PropertyDeed.BANK)
	_check_winner()
	if phase == Phase.GAME_OVER:
		pending_debts.clear()
		_auction_queue.clear()
		auction = null
		trade_offer = null
		state_changed.emit()
		return true
	_continue()
	return true


## Payer owes `amount` to a player id or PropertyDeed.BANK. Paid at once when cash covers it and
## nothing older is owed; otherwise queued as a Debt (raise funds or go bankrupt, section 4.4).
func _charge(payer: Player, creditor_id: int, amount: int) -> void:
	if amount <= 0 or payer.is_bankrupt:
		return
	var owes_already := false
	for d in pending_debts:
		if d.debtor == payer.id:
			owes_already = true
	if payer.cash >= amount and not owes_already:
		_pay(payer, creditor_id, amount)
		return
	pending_debts.append(Bankruptcy.Debt.new(payer.id, creditor_id, amount))
	_say("%s owes %s $%d and must raise funds." % [payer.display_name, _creditor_name(creditor_id), amount])
	debt_started.emit(payer, creditor_id, amount)


func _pay(payer: Player, creditor_id: int, amount: int) -> void:
	if creditor_id == PropertyDeed.BANK or players[creditor_id].is_bankrupt:
		bank.collect(payer, amount)
	else:
		payer.add_cash(-amount)
		players[creditor_id].add_cash(amount)


func _creditor_name(creditor_id: int) -> String:
	return board.term("bank") if creditor_id == PropertyDeed.BANK else players[creditor_id].display_name


## Next phase after any step: open debts, then auctions, then the buy decision, then end of landing.
func _continue() -> void:
	if phase == Phase.GAME_OVER:
		state_changed.emit()
		return
	if not pending_debts.is_empty():
		phase = Phase.RAISING_FUNDS
		state_changed.emit()
		return
	if auction == null and not _auction_queue.is_empty():
		_start_auction(_auction_queue.pop_front())
		if auction.is_finished():  # nobody left to bid
			_after_auction_step()
			return
	if auction != null:
		phase = Phase.AUCTION
		state_changed.emit()
		return
	if pending_buy_index >= 0:
		phase = Phase.AWAITING_BUY_DECISION
		state_changed.emit()
		return
	if _resume_roll:
		_resume_roll = false
		if not current_player().is_bankrupt:
			phase = Phase.AWAITING_ROLL
			_check_winner()
			state_changed.emit()
			return
	_post_landing()


func end_turn() -> void:
	if phase != Phase.AWAITING_END_TURN:
		return
	turn_ended.emit(current_player())
	doubles_streak = 0
	bot_proposed_this_turn = false
	for step in range(1, players.size() + 1):
		var next := (current_index + step) % players.size()
		if not players[next].is_bankrupt:
			current_index = next
			break
	phase = Phase.AWAITING_ROLL
	_say("%s's turn." % current_player().display_name)
	turn_started.emit(current_player())
	state_changed.emit()


## Moves forward (or backward when steps < 0). Passing or landing on GO pays salary only forward.
func move_by(p: Player, steps: int) -> void:
	var from := p.position
	var passes := Rules.passes_go(p.position, steps)
	if passes:
		bank.pay(p, config.go_salary)
		_say("%s passes %s: +$%d." % [p.display_name, board.spaces[0].display_name, config.go_salary])
	p.set_position(posmod(p.position + steps, Board.SPACE_COUNT))
	_event(&"moved", {"player": p.id, "from": from, "to": p.position, "steps": steps})
	if passes:
		_event(&"passed_go", {"player": p.id, "amount": config.go_salary})


func move_to(p: Player, target: int) -> void:
	move_by(p, posmod(target - p.position, Board.SPACE_COUNT))


func _roll_in_jail(p: Player) -> void:
	if dice.is_doubles():
		# 6.3 option 3: doubles free you; move with that roll; no extra turn.
		_release(p)
		_say("Doubles! %s leaves %s." % [p.display_name, board.term("jail")])
		_event(&"released", {"player": p.id, "how": &"doubles"})
	else:
		p.jail_turns_tried += 1
		if p.jail_turns_tried < config.max_jail_turns:
			_say("%s stays in %s." % [p.display_name, board.term("jail")])
			return
		# 6.4: third failed try: pay the fine and move with this roll.
		_charge(p, PropertyDeed.BANK, config.jail_fine)
		_release(p)
		_say("%s pays $%d after the third try." % [p.display_name, config.jail_fine])
		_event(&"released", {"player": p.id, "how": &"forced"})
	move_by(p, dice.total())
	_resolve_space(p, {"dice_total": dice.total()})


func _resolve_space(p: Player, ctx: Dictionary) -> void:
	var s := board.spaces[p.position]
	match s.space_type:
		Space.Type.STREET, Space.Type.RAILROAD, Space.Type.UTILITY:
			_resolve_property(p, s, ctx)
		Space.Type.CHANCE:
			_draw_card(p, chance)
		Space.Type.COMMUNITY_CHEST:
			_draw_card(p, community_chest)
		Space.Type.INCOME_TAX, Space.Type.LUXURY_TAX:
			_say("%s pays %s: $%d." % [p.display_name, s.display_name, s.tax_amount])
			_event(&"tax", {"player": p.id, "space": s.index, "amount": s.tax_amount})
			_charge(p, PropertyDeed.BANK, s.tax_amount)
		Space.Type.GO_TO_JAIL:
			_send_to_jail(p, s.display_name)
		Space.Type.FREE_PARKING:
			# Official rules: nothing happens. The jackpot house rule is not implemented.
			if config.free_parking_jackpot:
				push_warning("free_parking_jackpot is a house rule and is not implemented")
			_say("%s rests at %s." % [p.display_name, s.display_name])
		_:
			pass


func _resolve_property(p: Player, s: Space, ctx: Dictionary) -> void:
	var deed := s.deed
	if deed.owner == PropertyDeed.BANK:
		pending_buy_index = s.index
		phase = Phase.AWAITING_BUY_DECISION
		_say("%s is %s: $%d." % [s.display_name, board.term("unowned"), deed.list_price])
		_event(&"landed_unowned", {"player": p.id, "space": s.index, "price": deed.list_price})
		return
	if deed.owner == p.id or deed.is_mortgaged:
		return
	var amount: int
	if ctx.has("dice_multiplier"):
		dice.roll()  # card says throw the dice for this utility rent
		amount = dice.total() * int(ctx["dice_multiplier"])
	else:
		amount = Rules.rent_for(board, s.index, int(ctx.get("dice_total", 0)), config)
		amount *= int(ctx.get("rent_multiplier", 1))
	var owner := players[deed.owner]
	_say("%s owes %s $%d rent." % [p.display_name, owner.display_name, amount])
	_event(&"rent", {"player": p.id, "owner": owner.id, "space": s.index, "amount": amount})
	rent_requested.emit(owner, p, amount)
	_charge(p, owner.id, amount)


func _draw_card(p: Player, deck: CardDeck) -> void:
	var card := deck.draw()
	if card == null:
		return
	last_card = card
	_say("%s: %s" % [board.spaces[p.position].display_name, card.text])
	_event(&"card", {"player": p.id, "space": p.position, "deck": card.deck_id, "text": card.text})
	if card.is_goojf():
		p.goojf_cards.append(card)
	else:
		deck.return_to_bottom(card)
		_apply_card(p, card)


func _apply_card(p: Player, card: Card) -> void:
	var prm := card.params
	match card.opcode:
		&"ADVANCE_TO":
			move_to(p, int(prm["target"]))
			_resolve_space(p, {"dice_total": dice.total()})
		&"MOVE_RELATIVE":
			move_by(p, int(prm["steps"]))
			_resolve_space(p, {"dice_total": dice.total()})
		&"MOVE_NEAREST":
			move_to(p, board.next_index_of_type(p.position, Space.type_from_string(String(prm["space_type"]))))
			var ctx := {"dice_total": dice.total()}
			if prm.has("rent_multiplier"):
				ctx["rent_multiplier"] = int(prm["rent_multiplier"])
			if prm.has("dice_multiplier"):
				ctx["dice_multiplier"] = int(prm["dice_multiplier"])
			_resolve_space(p, ctx)
		&"COLLECT_BANK":
			bank.pay(p, int(prm["amount"]))
		&"PAY_BANK":
			_charge(p, PropertyDeed.BANK, int(prm["amount"]))
		&"PAY_EACH_PLAYER":
			for other in _other_active_players(p):
				_charge(p, other.id, int(prm["amount"]))
		&"COLLECT_FROM_EACH":
			for other in _other_active_players(p):
				_charge(other, p.id, int(prm["amount"]))
		&"REPAIRS":
			_charge(p, PropertyDeed.BANK, Rules.repairs_cost(board, p.id, int(prm["per_house"]), int(prm["per_hotel"])))
		&"GO_TO_JAIL":
			_send_to_jail(p, "card")
		_:
			push_error("TurnController: unknown card opcode %s" % card.opcode)


func _send_to_jail(p: Player, reason: String) -> void:
	var from := p.position
	p.set_position(config.jail_index)
	p.in_jail = true
	p.jail_turns_tried = 0
	doubles_streak = 0
	_extra_turn_pending = false
	_say("%s is sent to %s (%s)." % [p.display_name, board.spaces[config.jail_index].display_name, reason])
	_event(&"jailed", {"player": p.id, "from": from, "to": config.jail_index})
	sent_to_jail.emit(p, reason)


func _release(p: Player) -> void:
	p.in_jail = false
	p.jail_turns_tried = 0


func _after_resolution() -> void:
	_continue()


func _post_landing() -> void:
	var p := current_player()
	if _extra_turn_pending and not p.in_jail and not p.is_bankrupt:
		phase = Phase.AWAITING_ROLL
		_say("Doubles: %s rolls again." % p.display_name)
		doubles_extra_turn.emit(p)
	else:
		phase = Phase.AWAITING_END_TURN
	_extra_turn_pending = false
	_check_winner()
	state_changed.emit()


func _other_active_players(p: Player) -> Array[Player]:
	var out: Array[Player] = []
	for other in players:
		if other != p and not other.is_bankrupt:
			out.append(other)
	return out


func _check_winner() -> void:
	var alive: Array[Player] = []
	for p in players:
		if not p.is_bankrupt:
			alive.append(p)
	if alive.size() == 1:
		phase = Phase.GAME_OVER
		_say("%s wins!" % alive[0].display_name)
		_event(&"game_over", {"player": alive[0].id})
		winner_declared.emit(alive[0])


func _deck_for(deck_id: StringName) -> CardDeck:
	return chance if deck_id == chance.deck_id else community_chest


# --- Bots (decisions: Bot) ------------------------------------------------------------------

## Who the game waits on: the debtor, the auction bidder, else the current player (-1 at game over).
func deciding_player() -> int:
	match phase:
		Phase.GAME_OVER:
			return -1
		Phase.RAISING_FUNDS:
			return current_debt().debtor
		Phase.AUCTION:
			return auction.current_bidder()
	return current_index


## The bot that must act now, or -1. A trade offer to a bot is answered first; a bot's offer to a
## person pauses the bots until that person answers.
func bot_actor() -> int:
	if phase == Phase.GAME_OVER:
		return -1
	if trade_offer != null and players[trade_offer.to_id].is_bot:
		return trade_offer.to_id
	if trade_offer != null and players[trade_offer.from_id].is_bot:
		return -1
	var id := deciding_player()
	return id if id >= 0 and players[id].is_bot else -1


## One bot decision, applied through the public actions. False if no bot is up or it failed.
func bot_step() -> bool:
	var id := bot_actor()
	if id < 0 or bot_settings == null:
		return false
	var action := Bot.decide(self, id)
	if _apply_bot_action(action):
		return true
	push_warning("Bot %d could not apply action %s in phase %s" % [id, Bot.Kind.keys()[action.kind], Phase.keys()[phase]])
	return false


## Steps bots until a person is up, the game ends, a step fails or max_steps run out.
## Returns the number of steps taken.
func run_bots(max_steps: int = 100000) -> int:
	var steps := 0
	while steps < max_steps and bot_step():
		steps += 1
	return steps


func _apply_bot_action(a: Bot.Action) -> bool:
	var pid := a.player_id
	match a.kind:
		Bot.Kind.ROLL:
			if phase != Phase.AWAITING_ROLL:
				return false
			roll()
			return true
		Bot.Kind.PAY_JAIL_FINE:
			return pay_jail_fine()
		Bot.Kind.USE_PARDON:
			return use_get_out_of_jail_card()
		Bot.Kind.BUY:
			return buy()
		Bot.Kind.DECLINE:
			if phase != Phase.AWAITING_BUY_DECISION:
				return false
			decline()
			return true
		Bot.Kind.BID:
			return auction_bid(a.amount)
		Bot.Kind.PASS_AUCTION:
			return auction_pass()
		Bot.Kind.BUILD:
			return build(pid, a.space_index)
		Bot.Kind.SELL_BUILDING:
			return sell_building(pid, a.space_index)
		Bot.Kind.SELL_GROUP:
			return sell_group_buildings(pid, a.group_id)
		Bot.Kind.MORTGAGE:
			return mortgage(pid, a.space_index)
		Bot.Kind.UNMORTGAGE:
			return unmortgage(pid, a.space_index)
		Bot.Kind.PAY_DEBT:
			return pay_debt()
		Bot.Kind.DECLARE_BANKRUPTCY:
			return declare_bankruptcy()
		Bot.Kind.ACCEPT_TRADE:
			return accept_trade(pid)
		Bot.Kind.REJECT_TRADE:
			return reject_trade(pid)
		Bot.Kind.PROPOSE_TRADE:
			bot_proposed_this_turn = true
			return propose_trade(a.offer)
		Bot.Kind.COUNTER_TRADE:
			return counter_trade(a.offer)
		Bot.Kind.END_TURN:
			if phase != Phase.AWAITING_END_TURN:
				return false
			end_turn()
			return true
	return false


func _event(kind: StringName, info: Dictionary) -> void:
	game_event.emit(kind, info)


func _say(message: String) -> void:
	log_lines.append(message)
	status.emit(message)
