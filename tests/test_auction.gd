extends TestCase
## Auction module (docs/classic_monopoly_structure.md 3.1): bids from $10, $1 steps, any player.

const P := TurnController.Phase


func test_auction_module_turn_order_and_winner() -> void:
	var ids: Array[int] = [0, 1, 2]
	var a := Auction.new(3, ids, 10, 1)
	check_eq(a.current_bidder(), 0, "first bidder")
	check(not a.bid(0, 9, 1500), "below the opening bid")
	check(a.bid(0, 10, 1500), "opening bid")
	check(not a.bid(0, 11, 1500), "not your turn")
	check(a.pass_turn(1), "second drops out")
	check(not a.bid(2, 10, 1500), "must beat the high bid")
	check(a.bid(2, 20, 1500), "raise")
	check_eq(a.current_bidder(), 0, "back to the first bidder")
	check(a.pass_turn(0), "first drops out")
	check(a.is_finished(), "only the high bidder is left")
	check_eq(a.high_bidder, 2, "winner")
	check_eq(a.high_bid, 20, "price")
	done()


func test_auction_bid_limited_by_cash() -> void:
	var ids: Array[int] = [0, 1]
	var a := Auction.new(3, ids, 10, 1)
	check(not a.bid(0, 31, 30), "cannot bid more than cash")
	check(a.bid(0, 30, 30), "can bid all cash")
	done()


func test_declined_deed_goes_to_highest_bidder() -> void:
	var tc := GameSetup.new_game(1234)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	tc.dice.force(1, 2)  # 0 -> 3 (60)
	tc.roll()
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "auction running")
	check_eq(tc.auction.current_bidder(), p1.id, "bidding starts left of the current player")
	check(tc.auction_bid(10), "opening bid")
	check(not tc.auction_bid(10), "decliner must beat 10")
	check(tc.auction_bid(25), "decliner may bid too")
	check(tc.auction_pass(), "other player drops out")
	check_eq(tc.board.deed_at(3).owner, p0.id, "winner owns the deed")
	check_eq(p0.cash, 1500 - 25, "winner pays the bid, not list price")
	check_eq(p1.cash, 1500, "loser pays nothing")
	check(tc.auction == null, "auction closed")
	check_eq(tc.phase, P.AWAITING_END_TURN, "turn continues")
	done()


func test_auction_after_doubles_keeps_extra_roll() -> void:
	var tc := GameSetup.new_game(1234)
	tc.players[0].position = 4
	tc.dice.force(1, 1)  # 4 -> 6 (unowned), doubles
	tc.roll()
	tc.decline()
	tc.auction_pass()
	tc.auction_pass()
	check_eq(tc.board.deed_at(6).owner, PropertyDeed.BANK, "no bids")
	check_eq(tc.phase, P.AWAITING_ROLL, "doubles still give another roll")
	check_eq(tc.current_index, 0, "same player")
	done()
