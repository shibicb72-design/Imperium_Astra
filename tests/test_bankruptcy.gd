extends TestCase
## Debts and bankruptcy (docs/classic_monopoly_structure.md 4.4).

const P := TurnController.Phase


func _three_player_game() -> TurnController:
	var tc := GameSetup.new_game(1234)
	var p := Player.new()
	p.id = 2
	p.display_name = "Commander 3"
	p.cash = tc.config.starting_cash
	tc.players.append(p)
	return tc


func test_raise_funds_then_pay_rent() -> void:
	var tc := GameSetup.new_game(1234)
	var owner := tc.players[0]
	var payer := tc.players[1]
	tc.board.deed_at(39).owner = owner.id
	tc.board.deed_at(5).owner = payer.id
	payer.cash = 5
	payer.position = 36
	tc.current_index = payer.id
	tc.dice.force(1, 2)  # 36 -> 39, rent 50
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "cannot cover rent")
	check_eq(payer.cash, 5, "nothing paid yet")
	check(not tc.can_declare_bankruptcy(), "assets cover the debt: no bankruptcy")
	check(not tc.pay_debt(), "not enough cash yet")
	tc.end_turn()
	check_eq(tc.phase, P.RAISING_FUNDS, "cannot end turn with a debt")
	check(tc.mortgage(payer.id, 5), "mortgage to raise money")
	check(tc.pay_debt(), "debt paid")
	check_eq(payer.cash, 105 - 50, "payer cash")
	check_eq(owner.cash, 1550, "owner collected")
	check_eq(tc.phase, P.AWAITING_END_TURN, "turn continues")
	done()


func test_off_turn_debtor_raises_funds() -> void:
	var tc := GameSetup.new_game(1234)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	check(tc.community_chest.move_to_top(&"cc_birthday"), "card found")
	p1.cash = 5
	tc.board.deed_at(1).owner = p1.id
	p0.position = 14
	tc.dice.force(1, 2)  # 14 -> 17 Senate Dispatch: collect 10 from each
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "other player owes")
	check_eq(tc.current_debt().debtor, p1.id, "debtor is not the current player")
	check(tc.mortgage(p1.id, 1), "debtor mortgages")
	check(tc.pay_debt(), "pays")
	check_eq(p0.cash, 1510, "collected")
	check_eq(tc.current_index, p0.id, "still player 0's turn")
	check_eq(tc.phase, P.AWAITING_END_TURN, "back to the turn")
	done()


func test_bankrupt_to_player_gets_everything() -> void:
	var tc := GameSetup.new_game(1234)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	var hotel := tc.board.deed_at(39)
	hotel.owner = p0.id
	tc.board.deed_at(37).owner = p0.id
	hotel.has_hotel = true
	tc.bank.hotels_remaining = 11
	for i in [6, 8, 9]:
		tc.board.deed_at(i).owner = p1.id
		tc.board.deed_at(i).houses = 1
	tc.bank.houses_remaining = 29
	tc.board.deed_at(5).owner = p1.id
	tc.board.deed_at(5).is_mortgaged = true
	tc.chance.move_to_top(&"ch_goojf")
	p1.goojf_cards.append(tc.chance.draw())
	p1.cash = 10
	p1.position = 36
	tc.current_index = p1.id
	tc.dice.force(1, 2)  # 36 -> 39: hotel rent 2000
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "debt")
	# max raisable: 10 cash + 3 x 25 houses + 50 + 50 + 60 mortgages = 245 < 2000
	check(tc.can_declare_bankruptcy(), "cannot cover")
	check(tc.declare_bankruptcy(), "declared")
	check(p1.is_bankrupt, "out")
	check_eq(p1.cash, 0, "no cash left")
	for i in [5, 6, 8, 9]:
		check_eq(tc.board.deed_at(i).owner, p0.id, "deed %d to creditor" % i)
	check(tc.board.deed_at(5).is_mortgaged, "mortgaged deed stays mortgaged")
	check_eq(tc.board.deed_at(6).houses, 0, "buildings sold to the Bank")
	check_eq(tc.bank.houses_remaining, 32, "houses back in stock")
	check_eq(p0.goojf_cards.size(), 1, "pardon card to creditor")
	# 1500 + 10 cash + 75 building sales - 10 interest on the mortgaged gate
	check_eq(p0.cash, 1575, "creditor cash")
	check_eq(tc.phase, P.GAME_OVER, "last player standing wins")
	done()


func test_bankrupt_to_bank_auctions_holdings() -> void:
	var tc := _three_player_game()
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	var p2 := tc.players[2]
	tc.board.deed_at(6).owner = p1.id
	tc.board.deed_at(6).is_mortgaged = true
	tc.community_chest.move_to_top(&"cc_goojf")
	p1.goojf_cards.append(tc.community_chest.draw())
	p1.cash = 50
	p1.position = 1
	tc.current_index = p1.id
	tc.dice.force(1, 2)  # 1 -> 4 Imperial Levy 200
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "cannot pay the levy")
	check(tc.declare_bankruptcy(), "bankrupt to the Bank")
	check(p1.is_bankrupt, "out")
	check_eq(tc.community_chest.draw_pile.size(), 16, "pardon back in its deck")
	check_eq(tc.phase, P.AUCTION, "Bank auctions the deeds")
	check(not tc.board.deed_at(6).is_mortgaged, "mortgage cancelled")
	check_eq(tc.auction.active_bidders().size(), 2, "bankrupt player does not bid")
	check_eq(tc.auction.current_bidder(), p2.id, "bidding starts left of the bankrupt player")
	check(tc.auction_bid(10), "player 3 bids")
	check(tc.auction_pass(), "player 1 drops out")
	check_eq(tc.board.deed_at(6).owner, p2.id, "sold")
	check_eq(p2.cash, 1490, "paid the bid")
	check_eq(tc.phase, P.AWAITING_END_TURN, "bankrupt player's turn is over")
	tc.end_turn()
	check_eq(tc.current_index, p2.id, "bankrupt seat is skipped")
	check_eq(p0.cash, 1500, "untouched")
	done()


func test_card_payments_queue_per_creditor() -> void:
	var tc := _three_player_game()
	var p0 := tc.players[0]
	check(tc.chance.move_to_top(&"ch_chairman"), "card found")
	p0.cash = 60
	p0.position = 4
	tc.dice.force(1, 2)  # 4 -> 7 Mission Brief: pay each player 50
	tc.roll()
	check_eq(p0.cash, 10, "first payment made")
	check_eq(tc.players[1].cash, 1550, "first creditor paid")
	check_eq(tc.phase, P.RAISING_FUNDS, "second payment owed")
	check_eq(tc.current_debt().creditor, 2, "owed to the next player")
	check(tc.declare_bankruptcy(), "nothing to raise")
	check_eq(tc.players[2].cash, 1510, "creditor takes the remaining cash")
	check(tc.pending_debts.is_empty(), "debts cleared")
	check_eq(tc.phase, P.AWAITING_END_TURN, "game goes on with two players")
	done()
