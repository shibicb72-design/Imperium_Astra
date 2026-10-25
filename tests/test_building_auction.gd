extends TestCase
## Building shortage auction (docs/classic_monopoly_structure.md 3.2; OPEN_QUESTIONS Q10):
## Building lot helpers, the non-deed BuildingLotAuction variant and
## TurnController.start_building_auction. Who declares a claim is a Q10 `_placeholder`, so these
## tests pass claims in directly; nothing in normal play starts a shortage auction yet.

const P := TurnController.Phase


## Seat 0 owns brown (1, 3), seat 1 owns light blue (6, 8, 9); both people, Bank has `houses`.
func _contest(houses: int) -> TurnController:
	var tc := GameSetup.new_game(1234)
	for pl in tc.players:
		pl.is_bot = false
	for i in [1, 3]:
		tc.board.deed_at(i).owner = 0
	for i in [6, 8, 9]:
		tc.board.deed_at(i).owner = 1
	tc.bank.houses_remaining = houses
	return tc


func _claims(a: int, b: int) -> Dictionary[int, int]:
	var c: Dictionary[int, int] = {0: a, 1: b}
	return c


func test_stock_never_goes_negative() -> void:
	var tc := _contest(0)
	check(not Building.take_lot(tc.bank, Building.HOUSE), "nothing to take")
	check_eq(tc.bank.houses_remaining, 0, "stock stays at 0")
	check(not tc.build(0, 1), "no house to build")
	tc.bank.houses_remaining = 1
	check(tc.build(0, 1), "last house")
	check(not tc.build(1, 6), "Bank is out")
	check_eq(tc.bank.houses_remaining, 0, "stock at 0, not below")
	check(not tc.start_building_auction(_claims(3, 6)), "nothing left to auction")
	check_eq(tc.bank.houses_remaining, 0, "still 0")
	done()


func test_uncontested_build_stays_first_come() -> void:
	var tc := _contest(2)
	check(not Building.is_contested(tc.bank, Building.HOUSE, 2), "2 houses for 2 claimants")
	check(not tc.start_building_auction(_claims(1, 6)), "no shortage, no auction")
	check_eq(tc.bank.houses_remaining, 2, "stock untouched")
	tc.bank.houses_remaining = 1
	check(tc.build(1, 6), "first come gets the last house")
	check(tc.auction == null, "no auction opened by build()")
	check_eq(tc.phase, P.AWAITING_ROLL, "phase unchanged")
	check(not tc.build(0, 1), "second comer is out of luck")
	done()


func test_contested_last_house_goes_to_auction() -> void:
	var tc := _contest(1)
	check(Building.is_contested(tc.bank, Building.HOUSE, 2), "2 claimants, 1 house")
	check(tc.start_building_auction(_claims(1, 6)), "shortage auction opens")
	check_eq(tc.phase, P.AUCTION, "auction phase")
	check(tc.auction.is_building_lot(), "building lot variant")
	check_eq(tc.auction.space_index, -1, "not a deed auction")
	var lot := tc.auction as BuildingLotAuction
	check_eq(lot.kind, Building.HOUSE, "a house")
	check_eq(lot.min_bid, 10, "bids from $10 (rules.json auction_min_bid)")
	check_eq(lot.list_price_for(tc.board, 1), 50, "light blue house cost")
	check_eq(tc.bank.houses_remaining, 0, "lot held out of stock while bidding")
	check(not tc.build(0, 3), "nobody can build it first-come meanwhile")
	check(not tc.start_building_auction(_claims(1, 6)), "one auction at a time")
	check_eq(tc.auction.current_bidder(), 1, "seat order left of the current player")
	check(tc.auction_bid(10), "opening bid")
	check(tc.auction_bid(15), "raise")
	check(tc.auction_pass(), "seat 1 drops out")
	check(tc.auction == null, "closed")
	check_eq(tc.board.deed_at(1).houses, 1, "winner builds on the claimed street")
	check_eq(tc.board.deed_at(6).houses, 0, "loser builds nothing")
	check_eq(tc.players[0].cash, 1500 - 15, "winner pays the bid, not the list cost")
	check_eq(tc.players[1].cash, 1500, "loser pays nothing")
	check_eq(tc.bank.houses_remaining, 0, "stock spent, not negative")
	check_eq(tc.phase, P.AWAITING_ROLL, "back to the roll it interrupted")
	done()


func test_no_bids_returns_the_building() -> void:
	var tc := _contest(1)
	tc.phase = P.AWAITING_END_TURN  # after the landing, before ending the turn
	check(tc.start_building_auction(_claims(1, 6)), "opens after the roll too")
	tc.auction_pass()
	tc.auction_pass()
	check(tc.auction == null, "closed")
	check_eq(tc.bank.houses_remaining, 1, "unsold house back in stock")
	check(not Building.group_has_buildings(tc.board, &"brown"), "nothing built")
	check_eq(tc.phase, P.AWAITING_END_TURN, "phase restored")
	done()


func test_contest_rejected_unless_legal() -> void:
	var tc := _contest(1)
	var one: Dictionary[int, int] = {0: 1}
	check(not tc.start_building_auction(one), "a single claimant just builds")
	check(not tc.start_building_auction(_claims(1, 11)), "seat 1 has no set at 11")
	check(not tc.start_building_auction(_claims(1, 5)), "no buildings on jump gates")
	tc.board.deed_at(1).houses = 1
	check(not tc.start_building_auction(_claims(1, 6)), "uneven: 1 is ahead of 3")
	tc.board.deed_at(1).houses = 0
	for i in [1, 3]:
		tc.board.deed_at(i).houses = 4
	check(not tc.start_building_auction(_claims(1, 6)), "hotel claim and house claim differ in kind")
	check_eq(tc.bank.houses_remaining, 1, "nothing taken")
	check(tc.auction == null and tc.phase == P.AWAITING_ROLL, "no auction")
	done()


func test_contested_last_hotel() -> void:
	var tc := _contest(10)
	for i in [1, 3, 6, 8, 9]:
		tc.board.deed_at(i).houses = 4
	tc.bank.hotels_remaining = 1
	check(tc.start_building_auction(_claims(1, 6)), "last hotel contested")
	check_eq((tc.auction as BuildingLotAuction).kind, Building.HOTEL, "a hotel")
	check_eq(tc.bank.hotels_remaining, 0, "hotel held out of stock")
	check(tc.auction_bid(10), "seat 1 bids")
	check(tc.auction_pass(), "seat 0 drops out")
	var d := tc.board.deed_at(6)
	check(d.has_hotel and d.houses == 0, "hotel placed on the claim")
	check_eq(tc.bank.houses_remaining, 14, "its 4 houses go back to the Bank")
	check_eq(tc.bank.hotels_remaining, 0, "stock 0, not negative")
	check_eq(tc.players[1].cash, 1490, "paid the bid")
	done()


func test_claim_lost_during_bidding_is_not_sold() -> void:
	var tc := _contest(1)
	check(tc.start_building_auction(_claims(1, 6)), "opens")
	check(tc.auction_bid(10), "seat 1 bids")
	check(tc.mortgage(1, 8), "seat 1 mortgages a street of its set mid-auction")
	var cash := tc.players[1].cash
	check(tc.auction_pass(), "seat 0 drops out; seat 1 wins")
	check_eq(tc.board.deed_at(6).houses, 0, "claim no longer legal: not built")
	check_eq(tc.players[1].cash, cash, "not charged (Q10 TODO placeholder)")
	check_eq(tc.bank.houses_remaining, 1, "house back in stock")
	done()


func test_winner_short_of_cash_owes_the_bank() -> void:
	var tc := _contest(1)
	check(tc.start_building_auction(_claims(1, 6)), "opens")
	check(tc.auction_bid(100), "seat 1 bids")
	tc.players[1].cash = 40  # spent elsewhere after bidding
	check(tc.auction_pass(), "seat 0 drops out")
	check_eq(tc.board.deed_at(6).houses, 1, "built")
	check_eq(tc.phase, P.RAISING_FUNDS, "debt to the Bank, as with deed auctions")
	tc.players[1].cash = 200
	check(tc.pay_debt(), "pays")
	check_eq(tc.phase, P.AWAITING_ROLL, "then back to the roll")
	done()


func test_bots_bid_on_building_lots() -> void:
	var tc := _contest(1)
	for pl in tc.players:
		pl.is_bot = true
	check(tc.start_building_auction(_claims(1, 6)), "opens")
	check(Bot.auction_limit(tc, tc.players[1], tc.bot_settings) <= 50, "bot caps at the house cost")
	var guard := 0
	while tc.auction != null and guard < 200:
		check(tc.bot_step(), "bot step applies")
		guard += 1
	check(tc.auction == null, "bots settle the auction")
	check_eq(tc.bank.houses_remaining, 0, "one house sold, stock 0")
	var built := tc.board.deed_at(1).houses + tc.board.deed_at(6).houses
	check_eq(built, 1, "exactly one house built")
	done()


func test_auction_panel_shows_building_lot() -> void:
	var tc := _contest(1)
	check(tc.start_building_auction(_claims(1, 6)), "opens")
	var panel := AuctionPanel.new()
	panel.setup(tc)
	panel.refresh()
	check(panel.visible, "panel shown for a building lot")
	check(panel._info.text.contains(tc.board.term("house")), "names the building")
	check(panel._info.text.contains(tc.board.spaces[6].display_name), "names the bidder's claim")
	panel._on_bid(0)
	check(tc.auction == null or tc.auction.has_winner(), "quick bid works on a lot")
	panel.free()
	done()
