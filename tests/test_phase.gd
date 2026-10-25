extends TestCase
## "Any time" actions and jail (docs/classic_monopoly_structure.md 3.2, 4.3, 6.3): building,
## selling, mortgaging and trading are open to every active commander in every phase but game
## over, on or off turn and in the Brig. Only rolling, buying, jail exits and ending the turn
## belong to the current player.

const P := TurnController.Phase


func _game() -> TurnController:
	return GameSetup.new_game(1234)


func test_off_turn_build_sell_mortgage_unmortgage() -> void:
	var tc := _game()
	tc.board.deed_at(1).owner = 1
	tc.board.deed_at(3).owner = 1
	tc.board.deed_at(12).owner = 1
	check_eq(tc.current_index, 0, "player 0 to move")
	check(tc.build(1, 1), "off-turn build")
	check(tc.build(1, 3), "off-turn build, evenly")
	check(tc.sell_building(1, 3), "off-turn sell")
	check(tc.sell_building(1, 1), "off-turn sell the rest")
	check(not Building.group_has_buildings(tc.board, tc.board.deed_at(1).color_group_id), "set cleared")
	check(tc.mortgage(1, 3), "off-turn mortgage")
	check(tc.unmortgage(1, 3), "off-turn unmortgage")
	check(tc.mortgage(1, 12), "off-turn mortgage utility")
	check_eq(tc.phase, P.AWAITING_ROLL, "turn state untouched")
	check_eq(tc.current_index, 0, "still player 0's turn")
	done()


func test_off_turn_actions_in_every_live_phase() -> void:
	var tc := _game()
	tc.board.deed_at(1).owner = 1
	tc.board.deed_at(3).owner = 1
	for ph: P in [P.AWAITING_ROLL, P.AWAITING_BUY_DECISION, P.AWAITING_END_TURN, P.AUCTION, P.RAISING_FUNDS]:
		tc.phase = ph
		check(tc.can_manage(1), "can manage in phase %d" % ph)
		check(tc.mortgage(1, 3), "mortgage in phase %d" % ph)
		check(tc.unmortgage(1, 3), "unmortgage in phase %d" % ph)
	tc.phase = P.GAME_OVER
	check(not tc.can_manage(1), "nothing after game over")
	check(not tc.mortgage(1, 3), "no mortgage after game over")
	done()


func test_off_turn_trade_proposer_and_receiver() -> void:
	var tc := _game()
	tc.board.deed_at(39).owner = 1
	var offer := Trade.propose(1, 0)  # off-turn player proposes to the current player
	offer.give_deeds = [39]
	offer.get_cash = 400
	check(tc.propose_trade(offer), "off-turn propose")
	check(tc.accept_trade(0), "current player accepts")
	check_eq(tc.board.deed_at(39).owner, 0, "deed moved")
	tc.board.deed_at(5).owner = 0
	var back := Trade.propose(0, 1)  # current player proposes; off-turn player accepts
	back.give_deeds = [5]
	back.get_cash = 200
	check(tc.propose_trade(back), "propose to off-turn player")
	check(tc.accept_trade(1), "off-turn accept")
	check_eq(tc.board.deed_at(5).owner, 1, "railroad moved")
	check_eq(tc.players[1].cash, 1500 + 400 - 200, "off-turn cash")
	done()


func test_off_turn_actions_during_auction() -> void:
	var tc := _game()
	tc.board.deed_at(12).owner = 1
	tc.dice.force(2, 3)  # 0 -> 5 (unowned railroad)
	tc.roll()
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "auction running")
	check(tc.mortgage(1, 12), "off-turn mortgage mid-auction")
	check_eq(tc.phase, P.AUCTION, "auction continues")
	done()


func test_creditor_builds_while_debtor_raises_funds() -> void:
	var tc := _game()
	tc.board.deed_at(1).owner = 1
	tc.board.deed_at(3).owner = 1
	tc.board.deed_at(39).owner = 0
	tc.players[0].cash = 1
	tc.dice.force(1, 2)  # 0 -> 3, rent to player 1
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "debtor raising funds")
	check(tc.build(1, 1), "off-turn creditor builds")
	check(tc.mortgage(0, 39), "debtor mortgages")
	check(tc.pay_debt(), "debt paid")
	check(tc.phase != P.RAISING_FUNDS, "debt cleared")
	done()


func test_turn_bound_actions_refused_off_turn() -> void:
	var tc := _game()
	var off := tc.players[1]
	off.in_jail = true
	off.goojf_cards.append(_pardon(tc.chance))
	check(not tc.pay_jail_fine(), "off-turn jailed player cannot pay the fine")
	check(not tc.use_get_out_of_jail_card(), "off-turn jailed player cannot use a pardon")
	check(off.in_jail, "still jailed")
	tc.dice.force(1, 2)
	tc.roll()
	check_eq(tc.players[0].position, 3, "roll moves the current player only")
	check_eq(off.position, 0, "off-turn player did not move")
	check(tc.buy(), "current player buys")
	check_eq(tc.board.deed_at(3).owner, 0, "buy goes to the current player")
	done()


func test_jailed_player_can_manage_and_trade() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.in_jail = true
	p.set_position(tc.config.jail_index)
	tc.board.deed_at(1).owner = 0
	tc.board.deed_at(3).owner = 0
	tc.board.deed_at(39).owner = 0
	check(tc.build(0, 1), "jailed build")
	check(tc.sell_building(0, 1), "jailed sell")
	check(tc.mortgage(0, 39), "jailed mortgage")
	check(tc.unmortgage(0, 39), "jailed unmortgage")
	tc.players[1].goojf_cards.append(_pardon(tc.chance))
	var offer := Trade.propose(0, 1)  # buys a pardon card from the Brig
	offer.get_cards = [tc.chance.deck_id]
	offer.give_cash = 50
	check(tc.propose_trade(offer), "jailed propose")
	check(tc.accept_trade(1), "accepted")
	check(tc.use_get_out_of_jail_card(), "uses the bought pardon")
	check(not p.in_jail, "released")
	check_eq(tc.chance.draw_pile.back().card_id, &"test_goojf", "pardon back under the deck")
	done()


func test_off_turn_jailed_player_trades_and_mortgages() -> void:
	var tc := _game()
	var jailed := tc.players[1]
	jailed.in_jail = true
	tc.board.deed_at(12).owner = 1
	check(tc.mortgage(1, 12), "off-turn jailed mortgage")
	var offer := Trade.propose(1, 0)
	offer.give_deeds = [12]
	offer.get_cash = 100
	check(tc.propose_trade(offer), "off-turn jailed propose")
	check(tc.accept_trade(0), "accepted")
	check_eq(tc.board.deed_at(12).owner, 0, "deed moved")
	check(tc.board.deed_at(12).is_mortgaged, "Q13 default: stays mortgaged")
	check_eq(tc.players[0].cash, 1500 - 100 - 8, "Q13 default: receiver pays 10% of 75")
	check(jailed.in_jail, "still jailed")
	done()


func test_jailed_player_bids_and_collects_rent() -> void:
	var tc := _game()
	var jailed := tc.players[1]
	jailed.in_jail = true
	tc.board.deed_at(3).owner = 1
	tc.dice.force(2, 3)  # 0 -> 5 (unowned railroad)
	tc.roll()
	tc.decline()
	check_eq(tc.auction.current_bidder(), 1, "jailed player is a bidder")
	check(tc.auction_bid(10), "jailed player bids")
	check(tc.auction_pass(), "player 0 drops out")
	check_eq(tc.board.deed_at(5).owner, 1, "jailed player wins the auction")
	tc.phase = P.AWAITING_ROLL  # player 0 again, for brevity
	tc.players[0].set_position(0)
	var cash_before := jailed.cash
	tc.dice.force(1, 2)  # 0 -> 3, owned by the jailed player
	tc.roll()
	check_eq(jailed.cash, cash_before + Rules.rent_for(tc.board, 3, 3, tc.config), "rent collected in the Brig")
	done()


func test_jailed_player_raises_funds_for_fine() -> void:
	var tc := _game()
	var p := tc.players[0]
	p.in_jail = true
	p.set_position(tc.config.jail_index)
	p.jail_turns_tried = tc.config.max_jail_turns - 1
	p.cash = 10
	tc.board.deed_at(39).owner = 0
	tc.dice.force(1, 3)  # third failure: fine is due
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "owes the fine")
	check(tc.mortgage(0, 39), "mortgages to raise funds")
	check(tc.pay_debt(), "pays the fine")
	check_eq(p.cash, 10 + 200 - tc.config.jail_fine, "cash after fine")
	done()


func _pardon(deck: CardDeck) -> Card:
	var c := Card.new()
	c.card_id = &"test_goojf"
	c.deck_id = deck.deck_id
	c.opcode = &"GOOJF"
	return c
