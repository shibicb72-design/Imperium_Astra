extends TestCase
## Building module (docs/classic_monopoly_structure.md 3.2): full set, even build/sell, stock, hotel.


func _game_with_brown(owner: int) -> TurnController:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(1).owner = owner
	tc.board.deed_at(3).owner = owner
	return tc


func test_build_requires_full_color_set() -> void:
	var tc := GameSetup.new_game(1234)
	tc.board.deed_at(1).owner = 0
	check(not tc.build(0, 1), "half a set cannot build")
	tc.board.deed_at(3).owner = 0
	check(tc.build(0, 1), "full set can build")
	check_eq(tc.board.deed_at(1).houses, 1, "one house")
	check_eq(tc.players[0].cash, 1500 - 50, "paid house cost")
	check_eq(tc.bank.houses_remaining, 31, "taken from Bank stock")
	check_eq(Rules.street_rent(tc.board, tc.board.deed_at(1)), 10, "1-house rent")
	done()


func test_build_evenly() -> void:
	var tc := _game_with_brown(0)
	check(tc.build(0, 1), "first house")
	check(not tc.build(0, 1), "cannot get two ahead")
	check(tc.build(0, 3), "level the set")
	check(tc.build(0, 1), "now the second house")
	check(not tc.build(1, 3), "only the owner builds")
	done()


func test_no_build_with_mortgaged_street_in_set() -> void:
	var tc := GameSetup.new_game(1234)
	for i in [6, 8, 9]:
		tc.board.deed_at(i).owner = 0
	tc.board.deed_at(9).is_mortgaged = true
	check(not tc.build(0, 6), "mortgaged street blocks the set")
	done()


func test_not_on_jump_gates() -> void:
	var tc := GameSetup.new_game(1234)
	for i in [5, 15, 25, 35]:
		tc.board.deed_at(i).owner = 0
	check(not tc.build(0, 5), "no buildings on railroads")
	done()


func test_hotel_returns_four_houses() -> void:
	var tc := _game_with_brown(0)
	tc.board.deed_at(1).houses = 4
	tc.board.deed_at(3).houses = 4
	tc.bank.houses_remaining = 32 - 8
	check(tc.build(0, 1), "upgrade to hotel")
	var d := tc.board.deed_at(1)
	check(d.has_hotel and d.houses == 0, "hotel replaces houses")
	check_eq(tc.bank.houses_remaining, 28, "4 houses back to the Bank")
	check_eq(tc.bank.hotels_remaining, 11, "hotel from stock")
	check_eq(tc.players[0].cash, 1450, "hotel cost = house cost")
	check(not tc.build(0, 1), "nothing above a hotel")
	check_eq(Rules.street_rent(tc.board, d), 250, "hotel rent")
	done()


func test_building_shortage_blocks() -> void:
	var tc := _game_with_brown(0)
	tc.bank.houses_remaining = 0
	check(not tc.build(0, 1), "no houses in the Bank")
	tc.board.deed_at(1).houses = 4
	tc.board.deed_at(3).houses = 4
	tc.bank.hotels_remaining = 0
	check(not tc.build(0, 1), "no hotels in the Bank")
	done()


func test_sell_half_price_evenly() -> void:
	var tc := _game_with_brown(0)
	tc.board.deed_at(1).houses = 2
	tc.board.deed_at(3).houses = 1
	tc.bank.houses_remaining = 29
	check(not tc.sell_building(0, 3), "must sell from the highest street")
	check(tc.sell_building(0, 1), "sell one")
	check_eq(tc.players[0].cash, 1525, "half of 50")
	check_eq(tc.board.deed_at(1).houses, 1, "one left")
	check_eq(tc.bank.houses_remaining, 30, "returned to stock")
	done()


func test_sell_hotel_and_group_liquidation() -> void:
	var tc := _game_with_brown(0)
	for i in [1, 3]:
		tc.board.deed_at(i).has_hotel = true
	tc.bank.hotels_remaining = 10
	tc.bank.houses_remaining = 3
	check(not tc.sell_building(0, 1), "Bank lacks 4 houses to break the hotel")
	tc.bank.houses_remaining = 4
	check(tc.sell_building(0, 1), "hotel back to 4 houses")
	check_eq(tc.board.deed_at(1).houses, 4, "four houses")
	check_eq(tc.players[0].cash, 1525, "half the hotel cost")
	check(tc.sell_group_buildings(0, &"brown"), "sell everything at once")
	# 4 houses (100) + hotel with its 4 houses (25 + 100)
	check_eq(tc.players[0].cash, 1525 + 225, "all at half price")
	check_eq(tc.bank.hotels_remaining, 12, "hotels back")
	check_eq(tc.bank.houses_remaining, 4, "houses back (4 traded out, 4 returned)")
	check(not Building.group_has_buildings(tc.board, &"brown"), "set cleared")
	done()
