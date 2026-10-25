extends TestCase
## P3-BOTTRADE: bot trade proposals and answers (scripts/core/bot_trade.gd).
## Numbers from data/bot.json: cash_buffer 200, trade_min_cash_percent 150, trade_swap_min_percent 110,
## complete_set_bonus_percent 100, monopoly_block_bonus_percent 50, trade_counter_max_percent 50.
## Board: brown 1/3 ($60), railroad 5 ($200), light blue 6/8 ($100) + 9 ($120), pink 11/13 ($140),
## utility 12 ($150).

const P := TurnController.Phase
const K := Bot.Kind


## Seed 1234 match; `bots` are bot seats, the rest people. `seats` > 2 builds a bigger table.
func _game(bots: Array[int], seats: int = 2) -> TurnController:
	var tc := GameSetup.new_game(1234, GameSetup.seats(seats, 0)) if seats > 2 else GameSetup.new_game(1234)
	for pl in tc.players:
		pl.is_bot = bots.has(pl.id)
	return tc


func _give(tc: TurnController, pid: int, indices: Array[int]) -> void:
	for i in indices:
		tc.board.deed_at(i).owner = pid


func _offer(from_id: int, to_id: int, give: Array[int], get: Array[int], cash: int = 0) -> Trade.Offer:
	var o := Trade.propose(from_id, to_id)
	o.give_deeds = give
	o.get_deeds = get
	o.give_cash = cash
	return o


func test_proposes_cash_to_complete_set() -> void:
	var tc := _game([1])
	tc.current_index = 1
	_give(tc, 1, [6, 8])
	_give(tc, 0, [9])
	var a := Bot.decide(tc, 1)
	check_eq(a.kind, K.PROPOSE_TRADE, "missing light blue deed held by a person")
	check_eq(a.offer.to_id, 0, "asks the holder")
	check_eq(a.offer.get_deeds, [9] as Array[int], "wants the missing deed")
	check(a.offer.give_deeds.is_empty(), "cash covers it: no deeds offered")
	check_eq(a.offer.give_cash, 180, "150% of the $120 list price")
	check(tc.bot_step(), "proposal applied")
	check(tc.trade_offer != null and tc.trade_offer.from_id == 1, "offer open")
	check_eq(tc.bot_actor(), -1, "bots pause until the person answers")
	check(tc.accept_trade(0), "person accepts")
	check(tc.board.owns_full_group(1, &"light_blue"), "bot completed the set")
	check_eq(tc.players[1].cash, 1500 - 180, "paid the offer")
	done()


func test_proposes_surplus_deed_when_cash_is_short() -> void:
	var tc := _game([1])
	tc.current_index = 1
	_give(tc, 1, [6, 8, 5])
	_give(tc, 0, [9])
	tc.players[1].cash = 300  # $180 would leave $120 < $200 buffer
	var a := Bot.decide(tc, 1)
	check_eq(a.kind, K.PROPOSE_TRADE, "still proposes")
	check_eq(a.offer.give_deeds, [5] as Array[int], "adds the spare railroad")
	check_eq(a.offer.give_cash, 0, "the railroad alone clears the margin")
	check(not a.offer.give_deeds.has(6) and not a.offer.give_deeds.has(8), "never strips its own set")
	# Nothing spare and too little cash: no proposal, it just rolls.
	var tc2 := _game([1])
	tc2.current_index = 1
	_give(tc2, 1, [6, 8])
	_give(tc2, 0, [9])
	tc2.players[1].cash = 300
	check_eq(Bot.decide(tc2, 1).kind, K.ROLL, "no +EV deal within the buffer")
	done()


func test_one_proposal_per_turn() -> void:
	var tc := _game([1])
	tc.current_index = 1
	_give(tc, 1, [6, 8])
	_give(tc, 0, [9])
	check(tc.bot_step(), "proposal applied")
	check(tc.bot_proposed_this_turn, "attempt recorded")
	check(tc.reject_trade(0), "person rejects")
	check_eq(Bot.decide(tc, 1).kind, K.ROLL, "no second proposal this turn")
	tc.phase = P.AWAITING_END_TURN
	check_eq(Bot.decide(tc, 1).kind, K.END_TURN, "still none before ending the turn")
	check(tc.bot_step(), "turn ended")
	check(not tc.bot_proposed_this_turn, "reset for the next turn")
	done()


func test_proposes_block_only_from_a_person() -> void:
	# 3 seats: people 0 and 1, bot 2. Seat 0 lacks only deed 9 for light blue; seat 1 holds it.
	var tc := _game([2], 3)
	tc.current_index = 2
	_give(tc, 0, [6, 8])
	_give(tc, 1, [9])
	var a := Bot.decide(tc, 2)
	check_eq(a.kind, K.PROPOSE_TRADE, "blocks the light blue monopoly")
	check_eq(a.offer.to_id, 1, "buys from the holder, not the would-be monopolist")
	check_eq(a.offer.get_deeds, [9] as Array[int], "the blocking deed")
	check(BotTrade.gain(tc, 2, a.offer) > 0, "+EV only thanks to the block bonus")
	# A bot holder already blocks: no proposal.
	var tc2 := _game([1, 2], 3)
	tc2.current_index = 2
	_give(tc2, 0, [6, 8])
	_give(tc2, 1, [9])
	check_eq(Bot.decide(tc2, 2).kind, K.ROLL, "bot holder never sells it to seat 0 anyway")
	done()


func test_rejects_underpay_that_completes_opponent_set() -> void:
	var tc := _game([1])
	_give(tc, 0, [6, 8])
	_give(tc, 1, [9])
	var offer := _offer(0, 1, [], [9], 600)
	check(tc.propose_trade(offer), "offer open")
	check_eq(Bot.decide(tc, 1).kind, K.REJECT_TRADE, "hands over light blue for cash: reject, no counter")
	# Both complete, the bot's set worth at least as much: accepted.
	var tc2 := _game([1])
	_give(tc2, 1, [6, 8, 1])
	_give(tc2, 0, [9, 3])
	var mutual := _offer(0, 1, [9], [1])
	check(tc2.propose_trade(mutual), "mutual offer open")
	check_eq(Bot.decide(tc2, 1).kind, K.ACCEPT_TRADE, "light blue ($320) for brown ($120)")
	# Reverse: the proposer gets the dearer set.
	var tc3 := _game([1])
	_give(tc3, 1, [9, 1])
	_give(tc3, 0, [6, 8, 3])
	var worse := _offer(0, 1, [3], [9], 300)
	check(tc3.propose_trade(worse), "worse offer open")
	check_eq(Bot.decide(tc3, 1).kind, K.REJECT_TRADE, "brown for light blue is not equal-or-better")
	done()


func test_accepts_fair_cash_for_deed() -> void:
	var tc := _game([1])
	_give(tc, 1, [11])
	check(tc.propose_trade(_offer(0, 1, [], [11], 210)), "offer open")  # 150% of 140
	check_eq(Bot.decide(tc, 1).kind, K.ACCEPT_TRADE, "fair premium")
	check(tc.bot_step(), "accepted")
	check_eq(tc.board.deed_at(11).owner, 0, "deed moved")
	check_eq(tc.players[1].cash, 1500 + 210, "paid")
	done()


func test_uneven_multi_deed_counters_once_then_rejects() -> void:
	var tc := _game([1])
	_give(tc, 1, [6, 11])
	_give(tc, 0, [1, 12])
	# Bot gives $240 of deeds for $210: gain -30, swap margin 24 -> asks $54 (<= 50% of 240).
	check(tc.propose_trade(_offer(0, 1, [1, 12], [6, 11])), "offer open")
	var a := Bot.decide(tc, 1)
	check_eq(a.kind, K.COUNTER_TRADE, "small cash fix makes it fair")
	check_eq(a.offer.get_cash, 54, "asks the shortfall")
	check_eq(a.offer.give_deeds, [6, 11] as Array[int], "same deeds back")
	check(tc.bot_step(), "counter applied")
	check(tc.trade_offer.is_counter and tc.trade_offer.to_id == 0, "counter waits on the person")
	# The person counters back cheaper: a bot never counters a counter.
	var back := Trade.mirror(tc.trade_offer)
	back.give_cash = 20
	check(tc.counter_trade(back), "person counters")
	check_eq(Bot.decide(tc, 1).kind, K.REJECT_TRADE, "still short and already countered: reject")
	check(tc.bot_step(), "rejected")
	# Far too uneven for a cash tweak: reject.
	check(tc.propose_trade(_offer(0, 1, [1], [6, 11])), "lopsided offer open")
	check_eq(Bot.decide(tc, 1).kind, K.REJECT_TRADE, "shortfall above 50% of the deeds given")
	done()


func test_never_gives_deed_from_full_set() -> void:
	var tc := _game([1])
	_give(tc, 1, [1, 3])
	check(tc.propose_trade(_offer(0, 1, [], [3], 1000)), "offer open")
	check_eq(Bot.decide(tc, 1).kind, K.REJECT_TRADE, "keeps its full brown set")
	done()
