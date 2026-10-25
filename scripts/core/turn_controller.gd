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

signal turn_started(player: Player)
signal turn_ended(player: Player)
signal doubles_extra_turn(player: Player)
signal sent_to_jail(player: Player, reason: String)
signal rent_requested(owner: Player, payer: Player, amount: int)
signal winner_declared(player: Player)
signal auction_started(space_index: int)
signal auction_ended(space_index: int, winner_id: int, amount: int)
signal debt_started(debtor: Player, creditor_id: int, amount: int)
signal player_bankrupt(player: Player, creditor_id: int)
signal trade_proposed(offer: Trade.Offer)
signal trade_resolved(offer: Trade.Offer)
signal status(message: String)
signal state_changed

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

var _extra_turn_pending := false
var _auction_queue: Array[int] = []


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
	_say("%s pays $%d and leaves the Brig." % [p.display_name, config.jail_fine])
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
	_say("%s uses a pardon and leaves the Brig." % p.display_name)
	state_changed.emit()
	return true


func buy() -> bool:
	if phase != Phase.AWAITING_BUY_DECISION:
		return false
	var p := current_player()
	var deed := board.deed_at(pending_buy_index)
	if not bank.sell_property(p, deed):
		return false
	_say("%s claims %s for $%d." % [p.display_name, board.spaces[pending_buy_index].display_name, deed.list_price])
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
	var s := board.spaces[a.space_index]
	if a.has_winner():
		var winner := players[a.high_bidder]
		s.deed.owner = winner.id
		_say("%s wins %s for $%d." % [winner.display_name, s.display_name, a.high_bid])
		# Cash was checked at bid time; anything spent since then becomes a debt to the Bank.
		_charge(winner, PropertyDeed.BANK, a.high_bid)
	else:
		_say("No bids; %s stays with the Bank." % s.display_name)
	auction_ended.emit(a.space_index, a.high_bidder, a.high_bid)
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
	_say("%s builds a %s on %s for $%d." % [p.display_name, what, board.spaces[space_index].display_name, cost])
	if had_houses == Building.MAX_HOUSES:
		_say("%d %s return to the Bank." % [Building.MAX_HOUSES, board.term("houses")])
	state_changed.emit()
	return true


func sell_building(player_id: int, space_index: int) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var deed := board.deed_at(space_index)
	var what := board.term("hotel") if deed.has_hotel else board.term("house")
	var value := Building.sell(board, bank, p, deed, config)
	if value < 0:
		return false
	_say("%s sells a %s on %s for $%d." % [p.display_name, what, board.spaces[space_index].display_name, value])
	state_changed.emit()
	return true


## Sells every building in the group at once (needed when the Bank lacks houses to break a hotel).
func sell_group_buildings(player_id: int, group_id: StringName) -> bool:
	if not can_manage(player_id):
		return false
	var p := players[player_id]
	var value := Building.sell_group(board, bank, p, group_id, config)
	if value < 0:
		return false
	_say("%s sells all buildings in %s for $%d." % [
		p.display_name, board.group_info.get(group_id, {}).get("display_name", group_id), value])
	state_changed.emit()
	return true


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
		_say("%s is bankrupt; holdings return to the Bank for auction." % debtor.display_name)
	if debtor == current_player():
		pending_buy_index = -1
		_extra_turn_pending = false
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
	return "the Bank" if creditor_id == PropertyDeed.BANK else players[creditor_id].display_name


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
	_post_landing()


func end_turn() -> void:
	if phase != Phase.AWAITING_END_TURN:
		return
	turn_ended.emit(current_player())
	doubles_streak = 0
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
	if Rules.passes_go(p.position, steps):
		bank.pay(p, config.go_salary)
		_say("%s passes %s: +$%d." % [p.display_name, board.spaces[0].display_name, config.go_salary])
	p.set_position(posmod(p.position + steps, Board.SPACE_COUNT))


func move_to(p: Player, target: int) -> void:
	move_by(p, posmod(target - p.position, Board.SPACE_COUNT))


func _roll_in_jail(p: Player) -> void:
	if dice.is_doubles():
		# 6.3 option 3: doubles free you; move with that roll; no extra turn.
		_release(p)
		_say("Doubles! %s leaves the Brig." % p.display_name)
	else:
		p.jail_turns_tried += 1
		if p.jail_turns_tried < config.max_jail_turns:
			_say("%s stays in the Brig." % p.display_name)
			return
		# 6.4: third failed try: pay the fine and move with this roll.
		_charge(p, PropertyDeed.BANK, config.jail_fine)
		_release(p)
		_say("%s pays $%d after the third try." % [p.display_name, config.jail_fine])
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
		_say("%s is unclaimed: $%d." % [s.display_name, deed.list_price])
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
	rent_requested.emit(owner, p, amount)
	_charge(p, owner.id, amount)


func _draw_card(p: Player, deck: CardDeck) -> void:
	var card := deck.draw()
	if card == null:
		return
	last_card = card
	_say("%s: %s" % [board.spaces[p.position].display_name, card.text])
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
	p.set_position(config.jail_index)
	p.in_jail = true
	p.jail_turns_tried = 0
	doubles_streak = 0
	_extra_turn_pending = false
	_say("%s is sent to %s (%s)." % [p.display_name, board.spaces[config.jail_index].display_name, reason])
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
		winner_declared.emit(alive[0])


func _deck_for(deck_id: StringName) -> CardDeck:
	return chance if deck_id == chance.deck_id else community_chest


func _say(message: String) -> void:
	log_lines.append(message)
	status.emit(message)
