extends TestCase
## Rule tests against docs/classic_monopoly_structure.md. Dice are forced, so seeds do not matter.

const P := TurnController.Phase


func _game() -> TurnController:
	return GameSetup.new_game(1234)


func test_board_data_shape() -> void:
	var tc := _game()
	check_eq(tc.board.spaces.size(), 40, "space count")
	var props := 0
	var streets := 0
	for s in tc.board.spaces:
		if s.is_property():
			props += 1
		if s.space_type == Space.Type.STREET:
			streets += 1
	check_eq(props, 28, "title deeds")
	check_eq(streets, 22, "streets")
	check_eq(tc.board.color_groups.size(), 8, "color groups")
	check_eq(tc.chance.draw_pile.size(), 16, "mission brief cards")
	check_eq(tc.community_chest.draw_pile.size(), 16, "senate dispatch cards")
	check_eq(tc.players[0].cash, 1500, "starting cash")
	check_eq(tc.board.spaces[39].list_price, 400, "most expensive street")
	done()


func test_three_doubles_sends_to_jail() -> void:
	var tc := _game()
	var p := tc.players[0]
	tc.dice.force(2, 2)  # 0 -> 4 (Imperial Levy)
	tc.dice.force(3, 3)  # 4 -> 10 (Just Visiting)
	tc.dice.force(4, 4)  # third doubles: straight to the Brig, no move
	tc.roll()
	check_eq(tc.phase, P.AWAITING_ROLL, "extra roll after first doubles")
	tc.roll()
	check_eq(p.position, 10, "just visiting after second doubles")
	check(not p.in_jail, "just visiting is not in jail")
	check_eq(tc.phase, P.AWAITING_ROLL, "extra roll after second doubles")
	tc.roll()
	check(p.in_jail, "in jail after third doubles")
	check_eq(p.position, 10, "jail position")
	check_eq(tc.phase, P.AWAITING_END_TURN, "turn ends")
	check_eq(p.cash, 1500 - 200, "only the levy was paid; no GO salary")
	done()


func test_two_doubles_then_normal_roll_no_jail() -> void:
	var tc := _game()
	var p := tc.players[0]
	tc.dice.force(2, 2)
	tc.dice.force(3, 3)
	tc.dice.force(1, 2)  # 10 -> 13 (unowned street)
	tc.roll()
	tc.roll()
	tc.roll()
	check(not p.in_jail, "not in jail")
	check_eq(p.position, 13, "moved normally")
	check_eq(tc.phase, P.AWAITING_BUY_DECISION, "buy decision")
	done()


func test_pass_go_collects_salary() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 38
	tc.dice.force(1, 2)  # 38 -> 1
	tc.roll()
	check_eq(p.position, 1, "wrapped past GO")
	check_eq(p.cash, 1700, "+200 salary for passing GO")
	done()


func test_land_on_go_collects_salary() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 35
	tc.dice.force(2, 3)  # 35 -> 0
	tc.roll()
	check_eq(p.position, 0, "on GO")
	check_eq(p.cash, 1700, "+200 for landing on GO")
	check_eq(tc.phase, P.AWAITING_END_TURN, "nothing else to do")
	done()


func test_buy_unowned() -> void:
	var tc := _game()
	var p := tc.players[0]
	tc.dice.force(1, 2)  # 0 -> 3 (brown street, 60)
	tc.roll()
	check_eq(tc.phase, P.AWAITING_BUY_DECISION, "offered to buy")
	check(tc.buy(), "buy succeeds")
	check_eq(tc.board.deed_at(3).owner, p.id, "owner set")
	check_eq(p.cash, 1440, "paid list price")
	check_eq(tc.phase, P.AWAITING_END_TURN, "turn can end")
	done()


func test_cannot_buy_without_cash() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.cash = 10
	tc.dice.force(1, 2)
	tc.roll()
	check(not tc.buy(), "buy refused")
	check_eq(tc.board.deed_at(3).owner, PropertyDeed.BANK, "still the Bank's")
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "decline starts an auction")
	check(tc.auction_pass() and tc.auction_pass(), "everyone drops out")
	check_eq(tc.board.deed_at(3).owner, PropertyDeed.BANK, "no bids: stays with the Bank")
	check_eq(tc.phase, P.AWAITING_END_TURN, "decline ends decision")
	done()


func test_rent_with_monopoly() -> void:
	var tc := _game()
	var owner := tc.players[0]
	var payer := tc.players[1]
	tc.board.deed_at(1).owner = owner.id
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(1)), 2, "single street base rent")
	tc.board.deed_at(3).owner = owner.id
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(1)), 4, "color set doubles rent")
	tc.current_index = payer.id
	tc.dice.force(1, 2)  # 0 -> 3
	tc.roll()
	check_eq(payer.cash, 1500 - 8, "payer pays doubled rent 8")
	check_eq(owner.cash, 1500 + 8, "owner collects")
	done()


func test_monopoly_double_survives_mortgaged_sibling() -> void:
	var tc := _game()
	for i in [6, 8, 9]:
		tc.board.deed_at(i).owner = 0
	tc.board.deed_at(9).is_mortgaged = true
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(6)), 12, "unmortgaged street still doubled")
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(9)), 0, "mortgaged street pays nothing")
	done()


func test_house_and_hotel_rent() -> void:
	var tc := _game()
	var deed := tc.board.deed_at(39)
	deed.owner = 0
	deed.houses = 3
	check_eq(Rules.street_rent(tc.board, deed), 1400, "3 houses")
	deed.has_hotel = true
	check_eq(Rules.street_rent(tc.board, deed), 2000, "hotel")
	done()


func test_railroad_and_utility_rent() -> void:
	var tc := _game()
	tc.board.deed_at(5).owner = 0
	check_eq(Rules.rent_for(tc.board, 5, 7, tc.config), 25, "one gate")
	tc.board.deed_at(15).owner = 0
	tc.board.deed_at(25).owner = 0
	check_eq(Rules.rent_for(tc.board, 5, 7, tc.config), 100, "three gates")
	tc.board.deed_at(12).owner = 1
	check_eq(Rules.rent_for(tc.board, 12, 7, tc.config), 28, "one utility 4x")
	tc.board.deed_at(28).owner = 1
	check_eq(Rules.rent_for(tc.board, 12, 7, tc.config), 70, "both utilities 10x")
	done()


func test_free_parking_no_payout() -> void:
	var tc := _game()
	var p := tc.players[0]
	check(not tc.config.free_parking_jackpot, "jackpot rule off")
	# Taxes go to the Bank (not a pot), so landing afterwards still pays nothing.
	p.position = 1
	tc.dice.force(1, 2)  # 1 -> 4 Imperial Levy
	tc.roll()
	check_eq(p.cash, 1300, "levy paid to the Bank")
	tc.end_turn()
	tc.current_index = 0
	tc.phase = P.AWAITING_ROLL
	p.position = 17
	tc.dice.force(1, 2)  # 17 -> 20 Deep Space Anchorage
	tc.roll()
	check_eq(p.position, 20, "on free parking")
	check_eq(p.cash, 1300, "no payout on free parking")
	check_eq(tc.phase, P.AWAITING_END_TURN, "turn continues normally")
	done()


func test_go_to_jail_space() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 27
	tc.dice.force(1, 2)  # 27 -> 30
	tc.roll()
	check(p.in_jail, "in jail")
	check_eq(p.position, 10, "moved to the Brig")
	check_eq(p.cash, 1500, "no GO salary")
	done()


func test_jail_doubles_release_no_extra_turn() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 10
	p.in_jail = true
	tc.dice.force(2, 2)  # 10 -> 14
	tc.roll()
	check(not p.in_jail, "released")
	check_eq(p.position, 14, "moved with the doubles roll")
	tc.decline()
	tc.auction_pass()
	tc.auction_pass()
	check_eq(tc.phase, P.AWAITING_END_TURN, "no extra roll after leaving jail on doubles")
	done()


func test_jail_third_failure_pays_and_moves() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 10
	p.in_jail = true
	p.jail_turns_tried = 2
	tc.dice.force(1, 3)  # 10 -> 14
	tc.roll()
	check(not p.in_jail, "released on third try")
	check_eq(p.cash, 1450, "paid fine")
	check_eq(p.position, 14, "moved with last roll")
	done()


func test_pay_jail_fine() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.position = 10
	p.in_jail = true
	check(tc.pay_jail_fine(), "fine accepted")
	check(not p.in_jail, "released")
	check_eq(p.cash, 1450, "paid 50")
	done()


func test_card_returns_to_bottom_and_goojf_is_held() -> void:
	var tc := _game()
	var p := tc.players[0]
	check(tc.chance.move_to_top(&"ch_dividend"), "card found")
	p.position = 4
	tc.dice.force(1, 2)  # 4 -> 7 Mission Brief
	tc.roll()
	check_eq(p.cash, 1550, "dividend collected")
	check_eq(tc.chance.draw_pile[-1].card_id, &"ch_dividend", "card at bottom")
	check(tc.chance.move_to_top(&"ch_goojf"), "pardon found")
	tc.end_turn()
	tc.current_index = 0
	tc.phase = P.AWAITING_ROLL
	p.position = 4
	tc.dice.force(1, 2)
	tc.roll()
	check_eq(p.goojf_cards.size(), 1, "pardon held")
	check_eq(tc.chance.draw_pile.size(), 15, "pardon left the deck")
	done()
