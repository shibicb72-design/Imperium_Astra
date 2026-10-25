extends TestCase
## P2-BOT: Bot decisions (scripts/core/bot.gd) and TurnController.bot_step / run_bots.
## Heuristic numbers come from data/bot.json (cash_buffer 200, trade_min_cash_percent 150).

const P := TurnController.Phase
const K := Bot.Kind


## Seed 1234 match with both seats as people unless told otherwise (tests choose the bots).
func _game(bots: Array[int] = []) -> TurnController:
	var tc := GameSetup.new_game(1234)
	for pl in tc.players:
		pl.is_bot = bots.has(pl.id)
	return tc


func _give(tc: TurnController, pid: int, indices: Array[int]) -> void:
	for i in indices:
		tc.board.deed_at(i).owner = pid


func test_default_setup_has_one_human_one_bot() -> void:
	var tc := GameSetup.new_game(1234)
	check(not tc.players[0].is_bot, "seat 1 human")
	check(tc.players[1].is_bot, "seat 2 bot")
	check(tc.bot_settings != null, "bot settings loaded from data/bot.json")
	var four := GameSetup.seats(1, 3)
	check_eq(four.size(), 4, "1 human + 3 bots")
	check(not bool(four[0]["is_bot"]) and bool(four[3]["is_bot"]), "humans first, then bots")
	var mixed := GameSetup.new_game(7, four)
	check_eq(mixed.players.size(), 4, "match built from seats")
	check(mixed.players[2].is_bot, "seat 3 is a bot")
	check(GameSetup.seats(0, 1).is_empty(), "below min_players refused")
	check(GameSetup.seats(4, 3).is_empty(), "above max_players refused")
	done()


func test_bot_actor_only_for_bots() -> void:
	var tc := _game([1])
	check_eq(tc.bot_actor(), -1, "human to roll: no bot acts")
	check(not tc.bot_step(), "bot_step does nothing on a human turn")
	tc.dice.force(1, 2)  # 0 -> 3 (60)
	tc.roll()
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "auction")
	check_eq(tc.bot_actor(), 1, "bot bids first, left of the current player")
	done()


func test_buys_when_buffer_stays() -> void:
	var tc := _game([0])
	tc.dice.force(1, 2)  # 0 -> 3 (60)
	tc.roll()
	check_eq(Bot.decide(tc, 0).kind, K.BUY, "1500 - 60 keeps the buffer")
	check(tc.bot_step(), "step applied")
	check_eq(tc.board.deed_at(3).owner, 0, "bot owns the deed")
	check_eq(tc.players[0].cash, 1440, "paid list price")
	done()


func test_declines_below_buffer() -> void:
	var tc := _game([0])
	tc.players[0].cash = 250
	tc.dice.force(1, 2)  # 0 -> 3 (60): 250 - 60 = 190 < 200
	tc.roll()
	check_eq(Bot.decide(tc, 0).kind, K.DECLINE, "would break the buffer")
	check(tc.bot_step(), "step applied")
	check_eq(tc.phase, P.AUCTION, "declined deed goes to auction")
	done()


func test_auction_bid_capped_by_buffer_and_price() -> void:
	var tc := _game([1])
	var bot := tc.players[1]
	bot.cash = 230  # limit = min(230 - 200, 60) = 30
	tc.dice.force(1, 2)  # 0 -> 3 (60)
	tc.roll()
	tc.decline()
	var first := Bot.decide(tc, 1)
	check_eq(first.kind, K.BID, "opens the bidding")
	check_eq(first.amount, tc.config.auction_min_bid, "opening bid is the rules minimum")
	check(tc.bot_step(), "bid applied")
	check(tc.auction_bid(29), "human raises to 29")
	var raise := Bot.decide(tc, 1)
	check_eq(raise.kind, K.BID, "30 is still within the cap")
	check_eq(raise.amount, 30, "raises by the $1 step")
	check(tc.bot_step(), "raise applied")
	check(tc.auction_bid(31), "human raises past the cap")
	check_eq(Bot.decide(tc, 1).kind, K.PASS_AUCTION, "31 would break the buffer")
	check(tc.bot_step(), "pass applied")
	check_eq(tc.board.deed_at(3).owner, 0, "human wins")
	check_eq(bot.cash, 230, "bot paid nothing")
	# Price cap: a rich bot stops at list price.
	var tc2 := _game([1])
	tc2.dice.force(1, 2)
	tc2.roll()
	tc2.decline()
	check(tc2.bot_step(), "rich bot opens")
	check(tc2.auction_bid(60), "human bids list price")
	check_eq(Bot.decide(tc2, 1).kind, K.PASS_AUCTION, "never above list price")
	done()


func _pardon(tc: TurnController) -> Card:
	for c in tc.chance.draw_pile:
		if c.is_goojf():
			tc.chance.draw_pile.erase(c)
			return c
	return null


func test_jail_choices() -> void:
	var tc := _game([0])
	var bot := tc.players[0]
	tc._send_to_jail(bot, "test")
	var card := _pardon(tc)
	check(card != null, "pardon card found")
	bot.goojf_cards.append(card)
	check_eq(Bot.decide(tc, 0).kind, K.USE_PARDON, "pardon first")
	bot.goojf_cards.clear()
	tc.chance.return_to_bottom(card)
	check_eq(Bot.decide(tc, 0).kind, K.PAY_JAIL_FINE, "cash ok: pay the fine")
	check(tc.bot_step(), "fine paid")
	check(not bot.in_jail, "out of jail")
	check_eq(bot.cash, 1450, "paid $50")
	tc._send_to_jail(bot, "test")
	bot.cash = 220  # 220 - 50 < 200
	check_eq(Bot.decide(tc, 0).kind, K.ROLL, "short on cash: roll for doubles")
	bot.jail_turns_tried = tc.config.max_jail_turns - 1
	check_eq(Bot.decide(tc, 0).kind, K.PAY_JAIL_FINE, "last try: pay")
	done()


func test_builds_evenly_within_buffer() -> void:
	var tc := _game([0])
	var bot := tc.players[0]
	_give(tc, 0, [1, 3])  # brown set, $50 houses
	bot.cash = 360  # three houses leave 210; a fourth would leave 160
	var builds := 0
	while Bot.decide(tc, 0).kind == K.BUILD and builds < 20:
		check(tc.bot_step(), "build applied")
		builds += 1
		var a := Building.level(tc.board.deed_at(1))
		var b := Building.level(tc.board.deed_at(3))
		check(absi(a - b) <= 1, "even building")
	check_eq(builds, 3, "stops at the buffer")
	check_eq(bot.cash, 210, "buffer kept")
	check_eq(Bot.decide(tc, 0).kind, K.ROLL, "then rolls")
	# Rich: builds through to hotels on both.
	bot.cash = 2000
	while Bot.decide(tc, 0).kind == K.BUILD and builds < 40:
		tc.bot_step()
		builds += 1
	check(tc.board.deed_at(1).has_hotel and tc.board.deed_at(3).has_hotel, "hotels when even")
	# No building with a mortgaged street in the set; lifts the mortgage first when comfortable.
	var tc2 := _game([0])
	_give(tc2, 0, [1, 3])
	tc2.board.deed_at(3).is_mortgaged = true
	tc2.players[0].cash = 400  # 400 - 33 < 500: keep the mortgage
	check_eq(Bot.decide(tc2, 0).kind, K.ROLL, "mortgaged set: no build, no lift")
	tc2.players[0].cash = 1000
	var lift := Bot.decide(tc2, 0)
	check_eq(lift.kind, K.UNMORTGAGE, "comfortable: lift the mortgage")
	check_eq(lift.space_index, 3, "the mortgaged deed")
	done()


func test_debt_sells_then_mortgages_then_pays() -> void:
	var tc := _game([1])
	var bot := tc.players[1]
	_give(tc, 1, [1, 3, 5])  # brown set + a railroad
	tc.board.deed_at(1).houses = 1
	tc.board.deed_at(3).houses = 1
	tc.bank.houses_remaining -= 2
	bot.cash = 0
	tc._charge(bot, PropertyDeed.BANK, 120)
	tc._continue()
	check_eq(tc.phase, P.RAISING_FUNDS, "bot in debt")
	check_eq(tc.bot_actor(), 1, "debtor bot acts off turn")
	var kinds: Array[int] = []
	while tc.phase == P.RAISING_FUNDS and kinds.size() < 10:
		kinds.append(Bot.decide(tc, 1).kind)
		check(tc.bot_step(), "debt step applied")
	check_eq(kinds, [K.SELL_BUILDING, K.SELL_BUILDING, K.MORTGAGE, K.PAY_DEBT] as Array[int],
		"houses first, then mortgage, then pay")
	check(tc.board.deed_at(5).is_mortgaged, "railroad (outside the set) mortgaged first")
	check(not tc.board.deed_at(1).is_mortgaged, "set kept")
	check_eq(bot.cash, 50 + 100 - 120, "paid")
	done()


func test_bankrupt_when_nothing_covers_debt() -> void:
	var tc := _game([1])
	var bot := tc.players[1]
	bot.cash = 10
	tc._charge(bot, PropertyDeed.BANK, 500)
	tc._continue()
	check_eq(Bot.decide(tc, 1).kind, K.DECLARE_BANKRUPTCY, "cannot raise enough")
	check(tc.bot_step(), "declared")
	check_eq(tc.phase, P.GAME_OVER, "human wins a 2-player match")
	done()


func test_trades_only_clear_cash_for_deed() -> void:
	var tc := _game([1])
	_give(tc, 1, [3, 6])
	var fair := Trade.propose(0, 1)
	fair.give_cash = 90  # 150% of 60
	fair.get_deeds = [3] as Array[int]
	check(tc.propose_trade(fair), "offer open")
	check_eq(tc.bot_actor(), 1, "bot answers the offer first")
	check_eq(Bot.decide(tc, 1).kind, K.ACCEPT_TRADE, "clearly +EV")
	check(tc.bot_step(), "accepted")
	check_eq(tc.board.deed_at(3).owner, 0, "deed moved")
	var cheap := Trade.propose(0, 1)
	cheap.give_cash = 140  # deed 6 lists at 100: needs 150
	cheap.get_deeds = [6] as Array[int]
	check(tc.propose_trade(cheap), "cheap offer open")
	check(tc.bot_step(), "answered")
	check_eq(tc.board.deed_at(6).owner, 1, "lowball refused")
	var swap := Trade.propose(0, 1)
	swap.give_deeds = [3] as Array[int]
	swap.get_deeds = [6] as Array[int]
	swap.give_cash = 500
	check(tc.propose_trade(swap), "swap open")
	check_eq(Bot.decide(tc, 1).kind, K.REJECT_TRADE, "deed swaps are too complex")
	tc.bot_step()
	# Completing the proposer's color set is refused at any price.
	var tc2 := _game([1])
	_give(tc2, 0, [1])
	_give(tc2, 1, [3])
	var monopoly := Trade.propose(0, 1)
	monopoly.give_cash = 1000
	monopoly.get_deeds = [3] as Array[int]
	check(tc2.propose_trade(monopoly), "monopoly offer open")
	check_eq(Bot.decide(tc2, 1).kind, K.REJECT_TRADE, "would hand over a full set")
	done()


func test_bot_vs_bot_soak_reaches_winner() -> void:
	var finished := 0
	var games := 0
	for game_seed in range(1, 11):
		games += 1
		var tc := GameSetup.new_game(game_seed, GameSetup.seats(0, 2))
		tc.determine_start_player()
		var steps := 0
		while steps < 60000 and tc.bot_step():
			steps += 1
			if steps % 50 == 0:
				_check_invariants(tc)
		_check_invariants(tc)
		if tc.phase == P.GAME_OVER:
			finished += 1
		else:
			check(steps == 60000, "a bot step failed before the cap (seed %d, phase %s)" % [
				game_seed, P.keys()[tc.phase]])
	print("  bot soak: %d of %d seeded 2-bot games reached a winner" % [finished, games])
	check(finished * 2 >= games, "at least half of the 2-bot games finish (%d/%d)" % [finished, games])
	# 4 bots smoke: runs without errors or stalls (a bankrupt bot still hands its turn on).
	for game_seed in [99, 100, 101]:
		var tc4 := GameSetup.new_game(game_seed, GameSetup.seats(0, 4))
		tc4.determine_start_player()
		var steps := tc4.run_bots(30000)
		check(tc4.phase == P.GAME_OVER or steps == 30000, "4 bots never stall (seed %d, phase %s)" % [
			game_seed, P.keys()[tc4.phase]])
		_check_invariants(tc4)
	done()


func test_bankrupt_bot_hands_turn_on() -> void:
	var tc := GameSetup.new_game(1234, GameSetup.seats(0, 3))
	var bot := tc.players[0]
	bot.cash = 10
	tc._charge(bot, PropertyDeed.BANK, 500)
	tc._continue()
	check(tc.bot_step(), "bankruptcy declared")
	check(bot.is_bankrupt, "bot out")
	check_eq(tc.phase, P.AWAITING_END_TURN, "its turn is still open")
	check_eq(Bot.decide(tc, 0).kind, K.END_TURN, "hands the turn on")
	check(tc.bot_step(), "turn ended")
	check_eq(tc.current_index, 1, "next bot's turn")
	done()


func test_main_hides_turn_buttons_on_bot_turn() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var tc := GameSetup.new_game(1234)  # default: seat 2 is a bot
	tc.current_index = 1
	main.controller = tc
	main.start(null)  # outside the tree: the bot timer stays idle
	check(not main._roll_button.visible, "no Roll button for the bot")
	check(not main._actions.visible, "no turn actions for the bot")
	check(main._player_labels[1].text.contains("(bot)"), "bot seat marked")
	check(main._bot_timer.is_stopped(), "timer idle outside the tree")
	main.free()
	done()


func _check_invariants(tc: TurnController) -> void:
	var houses := tc.bank.houses_remaining
	var hotels := tc.bank.hotels_remaining
	for s in tc.board.spaces:
		if s.deed != null:
			houses += s.deed.houses
			hotels += 1 if s.deed.has_hotel else 0
	check_eq(houses, tc.config.houses_in_bank, "houses conserved")
	check_eq(hotels, tc.config.hotels_in_bank, "hotels conserved")
	for pl in tc.players:
		check(pl.cash >= 0, "cash never negative")
