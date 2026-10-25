extends TestCase
## Plays many seeded random turns (buy when affordable, otherwise auction; build when possible;
## raise funds or go bankrupt when in debt) to exercise every space, card and P1 module path;
## the runner's done() check catches runtime script errors.

const P := TurnController.Phase


func test_random_play_keeps_invariants() -> void:
	var finished_games := 0
	for game_seed in [1, 2, 3, 4, 5]:
		var tc := GameSetup.new_game(game_seed)
		tc.determine_start_player()
		for step in 3000:
			var p := tc.current_player()
			match tc.phase:
				P.AWAITING_ROLL:
					if p.in_jail and p.cash >= 500 and step % 2 == 0:
						tc.pay_jail_fine()
					if step % 3 == 0:
						_try_build(tc, p)
					tc.roll()
				P.AWAITING_BUY_DECISION:
					if not tc.buy():
						tc.decline()
				P.AUCTION:
					var bidder := tc.players[tc.auction.current_bidder()]
					var price := tc.auction.min_next_bid()
					if step % 3 != 0 and bidder.cash >= price * 3:
						check(tc.auction_bid(price), "legal bid accepted")
					else:
						check(tc.auction_pass(), "pass accepted")
				P.RAISING_FUNDS:
					_handle_debt(tc)
				P.AWAITING_END_TURN:
					tc.end_turn()
				P.GAME_OVER:
					finished_games += 1
					break
			_check_invariants(tc)
		var owned := 0
		for pl in tc.players:
			owned += tc.board.deeds_owned_by(pl.id).size()
		check(owned > 0, "some deeds owned (seed %d)" % game_seed)
	print("  soak: %d of 5 seeded games reached a winner" % finished_games)
	done()


func _try_build(tc: TurnController, p: Player) -> void:
	for deed in tc.board.deeds_owned_by(p.id):
		if p.cash > 400:
			tc.build(p.id, deed.space_index)


func _handle_debt(tc: TurnController) -> void:
	if tc.pay_debt() or tc.declare_bankruptcy():
		return
	var debtor := tc.players[tc.current_debt().debtor]
	for gid: StringName in tc.board.color_groups:
		if tc.sell_group_buildings(debtor.id, gid):
			return
	for deed in tc.board.deeds_owned_by(debtor.id):
		if tc.mortgage(debtor.id, deed.space_index):
			return
	check(false, "debtor could neither pay, raise nor declare")


func _check_invariants(tc: TurnController) -> void:
	var houses := tc.bank.houses_remaining
	var hotels := tc.bank.hotels_remaining
	for s in tc.board.spaces:
		if s.deed != null:
			houses += s.deed.houses
			hotels += 1 if s.deed.has_hotel else 0
			if s.deed.owner == PropertyDeed.BANK:
				check(Building.level(s.deed) == 0 and not s.deed.is_mortgaged, "Bank deeds are clean")
	check_eq(houses, tc.config.houses_in_bank, "houses conserved")
	check_eq(hotels, tc.config.hotels_in_bank, "hotels conserved")
	for pl in tc.players:
		check(pl.position >= 0 and pl.position < 40, "position in range")
		check(pl.cash >= 0, "cash never negative (debts are queued)")
		if pl.is_bankrupt:
			check(tc.board.deeds_owned_by(pl.id).is_empty(), "bankrupt players own nothing")
	check(tc.chance.draw_pile.size() + _held(tc, &"chance") == 16, "chance cards conserved")
	check(tc.community_chest.draw_pile.size() + _held(tc, &"community_chest") == 16, "dispatch cards conserved")


func _held(tc: TurnController, deck: StringName) -> int:
	var n := 0
	for pl in tc.players:
		for c in pl.goojf_cards:
			if c.deck_id == deck:
				n += 1
	return n
