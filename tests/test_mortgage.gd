extends TestCase
## Mortgage module (docs/classic_monopoly_structure.md 4.3).


func test_mortgage_and_unmortgage_with_interest() -> void:
	var tc := GameSetup.new_game(1234)
	var p := tc.players[0]
	tc.board.deed_at(39).owner = 0
	check(tc.mortgage(0, 39), "mortgage")
	check(tc.board.deed_at(39).is_mortgaged, "flagged")
	check_eq(p.cash, 1500 + 200, "collected mortgage value")
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(39)), 0, "no rent while mortgaged")
	check(not tc.mortgage(0, 39), "cannot mortgage twice")
	check(tc.unmortgage(0, 39), "lift")
	check_eq(p.cash, 1700 - 220, "paid value + 10%")
	check(not tc.board.deed_at(39).is_mortgaged, "cleared")
	done()


func test_no_mortgage_with_buildings_in_set() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(37).owner = 0
	tc.board.deed_at(39).owner = 0
	tc.board.deed_at(37).houses = 1
	tc.bank.houses_remaining = 31
	check(not tc.mortgage(0, 39), "sell the set's buildings first")
	check(tc.sell_building(0, 37), "sell")
	check(tc.mortgage(0, 39), "now allowed")
	check(not tc.build(0, 37), "cannot build with a mortgaged street in the set")
	done()


func test_unmortgage_needs_cash_and_ownership() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(5).owner = 0
	check(not tc.mortgage(1, 5), "only the owner")
	check(tc.mortgage(0, 5), "jump gate mortgage")
	check_eq(Rules.rent_for(tc.board, 5, 7, tc.config), 0, "mortgaged gate pays no toll")
	tc.players[0].cash = 109
	check(not tc.unmortgage(0, 5), "needs 110")
	tc.players[0].cash = 110
	check(tc.unmortgage(0, 5), "exactly enough")
	check_eq(tc.players[0].cash, 0, "spent")
	done()


func test_mortgage_any_time_off_turn() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(12).owner = 1
	check_eq(tc.current_index, 0, "player 0 to move")
	check(tc.mortgage(1, 12), "official: mortgage at any time")
	check_eq(tc.players[1].cash, 1575, "utility mortgage value")
	done()
