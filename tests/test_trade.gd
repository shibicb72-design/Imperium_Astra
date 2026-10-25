extends TestCase
## Trade module (docs/classic_monopoly_structure.md 3.2, 4.3 item 5).


func _pardon(deck: CardDeck) -> Card:
	var c := Card.new()
	c.card_id = &"test_goojf"
	c.deck_id = deck.deck_id
	c.opcode = &"GOOJF"
	return c


func test_cash_and_deed_swap() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	tc.board.deed_at(5).owner = 1
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	offer.give_cash = 100
	offer.get_deeds = [5]
	check(tc.propose_trade(offer), "propose")
	check(not tc.accept_trade(0), "only the receiver accepts")
	check(tc.accept_trade(1), "accept")
	check_eq(tc.board.deed_at(39).owner, 1, "deed to receiver")
	check_eq(tc.board.deed_at(5).owner, 0, "deed to proposer")
	check_eq(tc.players[0].cash, 1400, "proposer paid cash")
	check_eq(tc.players[1].cash, 1600, "receiver got cash")
	check_eq(offer.status, Trade.Status.ACCEPTED, "status")
	check(tc.trade_offer == null, "offer closed")
	done()


func test_goojf_transfer() -> void:
	var tc := GameSetup.new_game(1234)
	tc.players[0].goojf_cards.append(_pardon(tc.chance))
	var offer := Trade.propose(0, 1)
	offer.give_cards = [tc.chance.deck_id]
	offer.get_cash = 50
	check(tc.propose_trade(offer), "propose")
	check(tc.accept_trade(1), "accept")
	check_eq(tc.players[0].goojf_cards.size(), 0, "card left proposer")
	check_eq(tc.players[1].goojf_cards.size(), 1, "card with receiver")
	check_eq(tc.players[1].goojf_cards[0].deck_id, tc.chance.deck_id, "same card")
	check_eq(tc.players[0].cash, 1550, "sold for 50")
	var bad := Trade.propose(0, 1)
	bad.give_cards = [tc.community_chest.deck_id]
	check(not tc.propose_trade(bad), "cannot offer a card not held")
	done()


func test_mortgaged_deed_charges_ten_percent_to_bank() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	tc.board.deed_at(39).is_mortgaged = true  # mortgage value 200
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	offer.get_cash = 300
	check(tc.propose_trade(offer), "propose")
	check(tc.accept_trade(1), "accept")
	check_eq(tc.board.deed_at(39).owner, 1, "new owner")
	check(tc.board.deed_at(39).is_mortgaged, "stays mortgaged")
	check_eq(tc.players[1].cash, 1500 - 300 - 20, "paid price + 10% of mortgage value to the Bank")
	check_eq(tc.players[0].cash, 1800, "seller got the price only")
	check(tc.pending_debts.is_empty(), "no debt")
	done()


func test_mortgage_interest_must_be_affordable() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	tc.board.deed_at(39).is_mortgaged = true
	tc.players[1].cash = 100
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	offer.get_cash = 90
	check(tc.trade_problem(offer) != "", "100 - 90 cannot cover 20 interest")
	check(not tc.propose_trade(offer), "rejected up front")
	offer.get_cash = 80
	check(tc.propose_trade(offer), "100 - 80 covers 20")
	check(tc.accept_trade(1), "accept")
	check_eq(tc.players[1].cash, 0, "spent exactly")
	done()


func test_reject_is_no_op() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	tc.players[1].goojf_cards.append(_pardon(tc.community_chest))
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	offer.get_cash = 400
	offer.get_cards = [tc.community_chest.deck_id]
	check(tc.propose_trade(offer), "propose")
	check(not tc.reject_trade(0), "only the receiver rejects")
	check(tc.reject_trade(1), "reject")
	check_eq(offer.status, Trade.Status.REJECTED, "status")
	check_eq(tc.board.deed_at(39).owner, 0, "deed unchanged")
	check_eq(tc.players[0].cash, 1500, "cash unchanged")
	check_eq(tc.players[1].cash, 1500, "cash unchanged")
	check_eq(tc.players[1].goojf_cards.size(), 1, "card unchanged")
	check(not tc.accept_trade(1), "closed offer cannot be accepted")
	done()


func test_cannot_trade_what_you_do_not_own() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 1
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	check(not tc.propose_trade(offer), "deed owned by the other side")
	offer.give_deeds = [1]  # Bank-owned street
	check(not tc.propose_trade(offer), "deed owned by the Bank")
	offer.give_deeds = [0]  # GO: no deed
	check(not tc.propose_trade(offer), "not a deed")
	offer.give_deeds = []
	offer.give_cash = 1501
	check(not tc.propose_trade(offer), "more cash than held")
	offer.give_cash = 0
	check(not tc.propose_trade(offer), "empty offer")
	check(tc.trade_offer == null, "nothing opened")
	done()


func test_no_trade_with_buildings_in_set() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(37).owner = 0
	tc.board.deed_at(39).owner = 0
	tc.board.deed_at(37).houses = 1
	tc.bank.houses_remaining = 31
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	check(not tc.propose_trade(offer), "sell the set's buildings first")
	check(tc.sell_building(0, 37), "sell")
	check(tc.propose_trade(offer), "now allowed")
	done()


func test_bankrupt_players_cannot_trade() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	tc.players[1].is_bankrupt = true
	var offer := Trade.propose(0, 1)
	offer.give_deeds = [39]
	check(not tc.propose_trade(offer), "receiver bankrupt")
	var back := Trade.propose(1, 0)
	back.get_deeds = [39]
	check(not tc.propose_trade(back), "proposer bankrupt")
	done()


func test_counter_offer() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	var offer := Trade.propose(1, 0)
	offer.get_deeds = [39]
	offer.give_cash = 300
	check(tc.propose_trade(offer), "propose")
	var reply := Trade.mirror(offer)
	reply.get_cash = 450
	check(tc.counter_trade(reply), "counter")
	check_eq(offer.status, Trade.Status.COUNTERED, "original closed")
	check(tc.trade_offer == reply, "reply is open")
	check(not tc.accept_trade(0), "the counter goes back to the first proposer")
	check(tc.accept_trade(1), "accept the counter")
	check_eq(tc.board.deed_at(39).owner, 1, "deed moved")
	check_eq(tc.players[0].cash, 1950, "countered price")
	check_eq(tc.players[1].cash, 1050, "countered price")
	done()


## Hotseat UI smoke test: build a cash + deed draft in TradePanel, propose, accept via its button.
func test_trade_panel_hotseat_flow() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(39).owner = 0
	var panel := TradePanel.new()
	panel.setup(tc)
	panel._draft.give_deeds.append(39)
	panel._draft.get_cash = 250
	panel._update_problem()
	check(panel._send_button != null and not panel._send_button.disabled, "propose enabled")
	panel._send_button.pressed.emit()
	check(tc.trade_offer != null, "offer open")
	panel.refresh()
	var accept: Button = null
	for row in panel._body.get_children():
		if row is HFlowContainer:
			accept = row.get_child(0) as Button
	check(accept != null and accept.text.begins_with("Accept"), "accept button shown")
	if accept != null:
		accept.pressed.emit()
	check_eq(tc.board.deed_at(39).owner, 1, "deed moved")
	check_eq(tc.players[0].cash, 1750, "cash moved")
	panel.free()
	done()


func test_trade_any_time_off_turn_and_one_at_a_time() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(12).owner = 1
	check_eq(tc.current_index, 0, "player 0 to move")
	var offer := Trade.propose(1, 0)
	offer.give_deeds = [12]
	offer.get_cash = 150
	check(tc.propose_trade(offer), "official: trade at any time")
	var other := Trade.propose(0, 1)
	other.give_cash = 10
	check(not tc.propose_trade(other), "one open offer at a time")
	check(not tc.cancel_trade(0), "only the proposer withdraws")
	check(tc.cancel_trade(1), "withdraw")
	check(tc.propose_trade(other), "slot free again")
	done()
