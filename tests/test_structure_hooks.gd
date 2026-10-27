extends TestCase
## P5 FABLE_STRUCTURE_HOOKS: presentation events and queue API the tile / event animations hang
## off (review A-9): utility card roll as a `rolled` event, mortgaged / unmortgaged, jail_stay and
## PieceState.in_jail, BoardView.queue_fx / fx_pose holding the busy gate, card opcode + numeric
## params, rent honesty (paid flag), `landed` outcomes for the silent landings, auction bid / pass,
## debt_started / debt_paid mirrors and rolled.streak. Presentation only: no rules outcome changes.

const P := TurnController.Phase
const FREE_PARKING_INDEX := 20


func _game() -> TurnController:
	var tc := GameSetup.new_game(1234)
	for pl in tc.players:
		pl.is_bot = false
	return tc


func _record(tc: TurnController) -> Array:
	var events := []
	tc.game_event.connect(func(kind: StringName, info: Dictionary) -> void: events.append([kind, info]))
	return events


func _of(events: Array, kind: StringName) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == kind)


## Payloads carry ids and numbers only: ints, floats, bools and StringName ids. Never String text.
func _ids_only(info: Dictionary, what: String, skip: Array = []) -> void:
	for k: String in info:
		if k in skip:
			continue
		var t := typeof(info[k])
		check(t in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING_NAME], "%s.%s is an id or number (got type %d)" % [what, k, t])


func test_utility_card_roll_emits_rolled() -> void:
	var tc := _game()
	var ev := _record(tc)
	var utility := tc.board.next_index_of_type(7, Space.Type.UTILITY)
	tc.board.deed_at(utility).owner = 1
	check(tc.chance.move_to_top(&"ch_nearest_utility"), "card found")
	tc.players[0].position = 4
	tc.dice.force(1, 2)  # 4 -> 7 Mission Brief
	tc.dice.force(3, 4)  # the card's utility throw
	tc.roll()
	var rolled := _of(ev, &"rolled")
	check_eq(rolled.size(), 2, "turn roll plus the utility throw")
	if rolled.size() == 2:
		check(not rolled[0][1].has("for") or rolled[0][1]["for"] != &"utility", "first roll is the turn roll")
		var u: Dictionary = rolled[1][1]
		check_eq(u.get("for"), &"utility", "second roll is for the utility")
		check_eq([u.get("player"), u.get("d1"), u.get("d2")], [0, 3, 4], "utility throw faces")
		check_eq(u.get("doubles"), false, "utility throw never counts as doubles")
		check_eq(u.get("streak"), 0, "utility throw carries streak 0")
		_ids_only(u, "rolled(utility)")
	var rent := _of(ev, &"rent")
	check_eq(rent.size(), 1, "one rent")
	if rent.size() == 1:
		check_eq(rent[0][1]["amount"], 70, "x10 rule unchanged")
	done()


func test_mortgage_unmortgage_emit_events() -> void:
	var tc := _game()
	tc.board.deed_at(1).owner = 0
	var ev := _record(tc)
	check(tc.mortgage(0, 1), "mortgage")
	var m := _of(ev, &"mortgaged")
	check_eq(m.size(), 1, "one mortgaged")
	if m.size() == 1:
		check_eq(m[0][1], {"player": 0, "space": 1, "amount": tc.board.deed_at(1).mortgage_value}, "mortgaged payload")
		_ids_only(m[0][1], "mortgaged")
	check(tc.unmortgage(0, 1), "unmortgage")
	var u := _of(ev, &"unmortgaged")
	check_eq(u.size(), 1, "one unmortgaged")
	if u.size() == 1:
		check_eq(u[0][1], {"player": 0, "space": 1, "amount": Rules.unmortgage_cost(tc.board.deed_at(1), tc.config)}, "unmortgaged payload")
		_ids_only(u[0][1], "unmortgaged")
	check(not tc.mortgage(1, 1), "refused mortgage")
	check_eq(_of(ev, &"mortgaged").size(), 1, "no event for a refused mortgage")
	done()


func test_piece_state_in_jail_and_jail_stay() -> void:
	var tc := _game()
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	bv.setup(tc)
	check("in_jail" in bv.piece_state(0), "PieceState has in_jail")
	var p := tc.players[0]
	p.set_position(tc.config.jail_index)
	p.in_jail = true
	check_eq(bv.piece_state(0).get("in_jail"), true, "jailed piece reads in_jail")
	check_eq(bv.piece_state(1).get("in_jail"), false, "free piece reads not in_jail")
	var ev := _record(tc)
	tc.dice.force(1, 2)  # no doubles: stays
	tc.roll()
	var stay := _of(ev, &"jail_stay")
	check_eq(stay.size(), 1, "one jail_stay")
	if stay.size() == 1:
		check_eq(stay[0][1], {"player": 0, "tries": 1}, "jail_stay payload")
		_ids_only(stay[0][1], "jail_stay")
	check(p.in_jail and p.position == tc.config.jail_index, "rules state unchanged: still jailed")
	check_eq(_of(ev, &"rolled")[0][1].get("streak"), 0, "jail roll streak 0")
	bv.free()
	done()


func test_queue_fx_exists_and_holds_busy() -> void:
	var tc := _game()
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	bv.setup(tc)
	check(bv.has_method("queue_fx"), "queue_fx exists")
	check(bv.has_method("fx_pose"), "fx_pose exists")
	if not bv.has_method("queue_fx") or not bv.has_method("fx_pose"):
		bv.free()
		done()
		return
	var called := []
	bv.queue_fx(&"siren", {"player": 0}, 0.5)  # animate off: finishes at once
	check(not bv.is_animating(), "headless: fx applies at once")
	bv.animate = true
	bv.queue_fx(&"siren", {"player": 0}, 0.5)
	bv.queue_call(func() -> void: called.append(true))
	check(bv.is_animating(), "fx holds the busy gate")
	var pose: Dictionary = bv.fx_pose(&"siren")
	check(pose.get("active", false) == true, "active pose while the fx plays")
	bv.advance(0.25)
	check(bv.is_animating() and called.is_empty(), "still busy mid-fx; later items wait")
	bv.advance(1.0)
	check(not bv.is_animating(), "drained after its duration")
	check_eq(called.size(), 1, "queued call ran after the fx")
	check(bv.fx_pose(&"siren").get("active", true) == false, "idle pose inactive")
	check(bv.fx_pose(&"no_such_fx") is Dictionary, "unknown kinds give a neutral pose")
	bv.free()
	done()


func test_card_event_carries_opcode_params() -> void:
	var tc := _game()
	var ev := _record(tc)
	check(tc.chance.move_to_top(&"ch_nearest_utility"), "card found")
	tc.players[0].position = 4
	tc.dice.force(1, 2)  # 4 -> 7 Mission Brief
	tc.roll()
	var cards := _of(ev, &"card")
	check_eq(cards.size(), 1, "one card event")
	if cards.size() == 1:
		var c: Dictionary = cards[0][1]
		check_eq(c.get("opcode"), &"MOVE_NEAREST", "card carries its opcode")
		check_eq(c.get("card_id"), &"ch_nearest_utility", "card carries its id")
		check(c.get("params") is Dictionary, "card carries params")
		var prm: Dictionary = c.get("params", {})
		check_eq(prm.get("dice_multiplier"), 10, "numeric params kept")
		check(not prm.has("space_type"), "string theme-ish params dropped")
		for k: String in prm:
			check(typeof(prm[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL], "params.%s numeric" % k)
		check_eq(c.get("text"), tc.last_card.text, "text contract kept for the banner")
		_ids_only(c, "card", ["text", "params"])  # params checked numeric above
	done()


func test_rent_paid_flag_or_post_charge() -> void:
	var tc := _game()
	var ev := _record(tc)
	tc.board.deed_at(3).owner = 1
	tc.dice.force(1, 2)  # 0 -> 3, rent 4
	tc.roll()
	var rent := _of(ev, &"rent")
	check_eq(rent.size(), 1, "rent event")
	if rent.size() == 1:
		check_eq(rent[0][1].get("paid"), true, "cash covered: paid")
		check(tc.pending_debts.is_empty(), "no debt")
		check_eq(DialogueLines.describe(tc, &"rent", rent[0][1])["key"], "rent_paid", "paid line key")
	var tc2 := _game()
	var ev2 := _record(tc2)
	tc2.board.deed_at(39).owner = 1
	tc2.players[0].cash = 5
	tc2.players[0].position = 36
	tc2.dice.force(1, 2)  # 36 -> 39, rent 50 > cash
	tc2.roll()
	var owed := _of(ev2, &"rent")
	check_eq(owed.size(), 1, "rent event when owed")
	check_eq(tc2.phase, P.RAISING_FUNDS, "debt queued")
	if owed.size() == 1:
		check_eq(owed[0][1].get("paid"), false, "debt: not paid")
		var d := DialogueLines.describe(tc2, &"rent", owed[0][1])
		check_eq(d.get("key"), "rent_owed", "owed line key")
		for lines in [DialogueLines.load_theme("res://data/themes/imperium_astra/dialogue.json"),
				DialogueLines.load_theme("res://data/themes/astra_alt/dialogue.json")]:
			check(lines.lines.has("rent_owed"), "theme dialogue has rent_owed")
			var line: String = lines.event_line(tc2, &"rent", owed[0][1])
			check(line != "" and not line.contains("{"), "owed line fills: %s" % line)
	done()


func test_landed_silent_outcomes() -> void:
	var own := _game()
	var ev := _record(own)
	own.board.deed_at(3).owner = 0
	own.dice.force(1, 2)
	own.roll()
	var l := _of(ev, &"landed")
	check_eq(l.size(), 1, "own: one landed")
	if l.size() == 1:
		check_eq(l[0][1], {"player": 0, "space": 3, "outcome": &"own"}, "own payload")
		_ids_only(l[0][1], "landed(own)")
	check(_of(ev, &"rent").is_empty() and _of(ev, &"landed_unowned").is_empty(), "own: no rent / unowned")

	var mort := _game()
	ev = _record(mort)
	mort.board.deed_at(3).owner = 1
	mort.board.deed_at(3).is_mortgaged = true
	mort.dice.force(1, 2)
	mort.roll()
	l = _of(ev, &"landed")
	check_eq(l.size(), 1, "mortgaged: one landed")
	if l.size() == 1:
		check_eq(l[0][1], {"player": 0, "space": 3, "outcome": &"mortgaged"}, "mortgaged payload")
	check(_of(ev, &"rent").is_empty(), "mortgaged: no rent")

	var visit := _game()
	ev = _record(visit)
	visit.players[0].position = visit.config.jail_index - 3
	visit.dice.force(1, 2)
	visit.roll()
	l = _of(ev, &"landed")
	check_eq(l.size(), 1, "visiting: one landed")
	if l.size() == 1:
		check_eq(l[0][1], {"player": 0, "space": visit.config.jail_index, "outcome": &"visiting"}, "visiting payload")
	check(not visit.players[0].in_jail, "just visiting")

	var park := _game()
	ev = _record(park)
	park.players[0].position = FREE_PARKING_INDEX - 3
	park.dice.force(1, 2)
	park.roll()
	l = _of(ev, &"landed")
	check_eq(l.size(), 1, "free parking: one landed")
	if l.size() == 1:
		check_eq(l[0][1], {"player": 0, "space": FREE_PARKING_INDEX, "outcome": &"free_parking"}, "free parking payload")
	check_eq(park.players[0].cash, park.config.starting_cash, "no jackpot")
	done()


func test_rolled_carries_streak() -> void:
	var tc := _game()
	var ev := _record(tc)
	tc.dice.force(2, 2)  # 0 -> 4, first doubles
	tc.roll()
	check_eq(tc.phase, P.AWAITING_ROLL, "extra turn")
	tc.dice.force(3, 3)  # 4 -> 10, second doubles
	tc.roll()
	tc.dice.force(1, 1)  # third doubles: to the Brig
	tc.roll()
	var rolled := _of(ev, &"rolled")
	check_eq(rolled.size(), 3, "three rolls")
	if rolled.size() == 3:
		check_eq(rolled[0][1].get("streak"), 1, "first doubles: streak 1")
		check_eq(rolled[1][1].get("streak"), 2, "second doubles: streak 2")
		check_eq(rolled[2][1].get("streak"), tc.config.doubles_to_jail, "third doubles carries the threshold")
		check(rolled[2][1]["doubles"], "still flagged doubles")
	check(tc.players[0].in_jail, "rule unchanged: jailed on the third doubles")
	check_eq(tc.doubles_streak, 0, "rules counter reset as before")
	var plain := _game()
	var ev2 := _record(plain)
	plain.dice.force(1, 2)
	plain.roll()
	check_eq(_of(ev2, &"rolled")[0][1].get("streak"), 0, "no doubles: streak 0")
	done()


func test_auction_and_debt_events() -> void:
	var tc := _game()
	var ev := _record(tc)
	tc.dice.force(1, 2)  # 0 -> 3 (unowned)
	tc.roll()
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "auction running")
	check(tc.auction_bid(10), "seat 1 bids")
	check(tc.auction_pass(), "seat 0 drops out")
	var bids := _of(ev, &"auction_bid")
	var passes := _of(ev, &"auction_pass")
	check_eq(bids.size(), 1, "one auction_bid")
	check_eq(passes.size(), 1, "one auction_pass")
	if bids.size() == 1:
		check_eq(bids[0][1], {"player": 1, "space": 3, "amount": 10}, "bid payload")
		_ids_only(bids[0][1], "auction_bid")
	if passes.size() == 1:
		check_eq(passes[0][1], {"player": 0, "space": 3}, "pass payload")
		_ids_only(passes[0][1], "auction_pass")
	check_eq(tc.board.deed_at(3).owner, 1, "rules unchanged: high bidder wins")

	var d := _game()
	var ev2 := _record(d)
	d.board.deed_at(39).owner = 1
	d.board.deed_at(5).owner = 0
	d.players[0].cash = 5
	d.players[0].position = 36
	d.dice.force(1, 2)  # 36 -> 39, rent 50
	d.roll()
	var started := _of(ev2, &"debt_started")
	check_eq(started.size(), 1, "debt_started mirrored as a game_event")
	if started.size() == 1:
		check_eq(started[0][1], {"player": 0, "creditor": 1, "amount": 50}, "debt_started payload")
		_ids_only(started[0][1], "debt_started")
	check(d.mortgage(0, 5), "raise funds")
	check(d.pay_debt(), "pay")
	var paid := _of(ev2, &"debt_paid")
	check_eq(paid.size(), 1, "one debt_paid")
	if paid.size() == 1:
		check_eq(paid[0][1], {"player": 0, "creditor": 1, "amount": 50}, "debt_paid payload")
		_ids_only(paid[0][1], "debt_paid")
	check_eq(d.phase, P.AWAITING_END_TURN, "rules unchanged")
	done()
