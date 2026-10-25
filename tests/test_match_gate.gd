extends TestCase
## P5-FEEL Dig 5a1 (board-first): the MatchGate table, the die affordance (die_pressed) and the
## InputMap actions behind the same gate, the floating turn panel (Buy / Skip / Action / End Turn
## and the jail set), the off-turn overlays and a no-stall soak. Main runs outside the tree here,
## so animate stays off unless a test turns it on and drives BoardView.advance() itself.

const P := TurnController.Phase
const S := MatchGate.State


func _main(tc: TurnController) -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = tc
	main.start(null)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(411, 880)
	main._update_layout()
	main._board_view.size = Vector2(440, 440)  # containers do not lay out outside the tree
	return main


## A left press at `pos` on the board, as Godot delivers a tap (mouse emulated from touch).
func _tap(bv: BoardView, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	bv._gui_input(ev)


func _key(main: Main, action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	main._unhandled_input(ev)


## Visible all the way up to `root` (is_visible_in_tree() needs a live tree).
func _shown(c: CanvasItem, root: Node) -> bool:
	var n: Node = c
	while n != null and n != root:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return n == root


func _live(b: BaseButton, root: Node) -> bool:
	return b != null and not b.disabled and _shown(b, root)


func _live_buttons(node: Node, root: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for c in node.get_children():
		if c is BaseButton and _live(c, root):
			out.append(c)
		out.append_array(_live_buttons(c, root))
	return out


func _button_starting(node: Node, root: Node, prefixes: Array[String]) -> Button:
	for b in _live_buttons(node, root):
		for prefix in prefixes:
			if b is Button and (b as Button).text.begins_with(prefix):
				return b
	return null


## A4.1(a): every row of the settled table, and BUSY for every combination while the board moves.
func test_gate_table_every_row() -> void:
	var rows := [
		# phase, decider is a person, decider jailed, open offer to a person -> settled state
		[P.AWAITING_ROLL, true, false, false, S.AWAIT_DIE_TAP],
		[P.AWAITING_ROLL, true, true, false, S.JAIL_SET],
		[P.AWAITING_BUY_DECISION, true, false, false, S.BUY],
		[P.AWAITING_END_TURN, true, false, false, S.END_TURN],
		[P.AWAITING_END_TURN, true, true, false, S.END_TURN],  # failed jail roll, no move
		[P.AUCTION, true, false, false, S.AUCTION],
		[P.AUCTION, true, true, false, S.AUCTION],  # jailed commanders bid too
		[P.RAISING_FUNDS, true, false, false, S.DEBT],
		[P.AWAITING_ROLL, false, false, false, S.BOT],
		[P.AWAITING_ROLL, false, true, false, S.BOT],
		[P.AWAITING_BUY_DECISION, false, false, false, S.BOT],
		[P.AWAITING_END_TURN, false, false, false, S.BOT],
		[P.AUCTION, false, false, false, S.BOT],
		[P.RAISING_FUNDS, false, false, false, S.BOT],
		[P.AWAITING_ROLL, false, false, true, S.TRADE_ANSWER],  # a bot's offer: the bots wait
		[P.AWAITING_END_TURN, true, false, true, S.TRADE_ANSWER],
		[P.AUCTION, false, false, true, S.TRADE_ANSWER],
		[P.RAISING_FUNDS, true, false, true, S.TRADE_ANSWER],
		[P.GAME_OVER, true, false, false, S.GAME_OVER],
		[P.GAME_OVER, false, true, true, S.GAME_OVER],
	]
	for row: Array in rows:
		var label := "%s person=%s jailed=%s offer=%s" % [P.keys()[row[0]], row[1], row[2], row[3]]
		check_eq(MatchGate.state_for(row[0], row[1], row[2], row[3], false), row[4], "settled " + label)
	for phase: int in P.values():
		for flags in 8:
			check_eq(MatchGate.state_for(phase, flags & 1 != 0, flags & 2 != 0, flags & 4 != 0, true), S.BUSY,
					"busy %s flags %d" % [P.keys()[phase], flags])
	check_eq(MatchGate.panel_slots(S.JAIL_SET), [&"fine", &"pardon", &"action"], "jail set slots (Q25)")
	check_eq(MatchGate.panel_slots(S.BUY), [&"buy", &"skip", &"action"], "buy slots (Q23)")
	check_eq(MatchGate.panel_slots(S.END_TURN), [&"action", &"end_turn"], "end-turn slots (Q23)")
	for s: int in S.values():
		var panel: bool = s in [S.JAIL_SET, S.BUY, S.END_TURN]
		check_eq(not MatchGate.panel_slots(s).is_empty(), panel, "panel only in its states: %s" % S.keys()[s])
		check_eq(MatchGate.die_live(s), s in [S.AWAIT_DIE_TAP, S.JAIL_SET], "die only before a person's roll: %s" % S.keys()[s])
		check_eq(MatchGate.is_forced(s), s in [S.AUCTION, S.DEBT, S.TRADE_ANSWER], "forced inputs: %s" % S.keys()[s])
	var tc := GameSetup.new_game(1234)
	check_eq(MatchGate.of(tc, false), S.AWAIT_DIE_TAP, "live match: person to roll")
	check_eq(MatchGate.of(tc, true), S.BUSY, "live match: busy board")
	tc.current_index = 1
	check_eq(MatchGate.of(tc, false), S.BOT, "live match: bot to roll")
	done()


## A4.1(b): die press, panel hidden while the board moves, settled panel after advance + _refresh,
## then Buy -> End Turn.
func test_gate_main_flow_buy_then_end_turn() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	var bv := main._board_view
	bv.animate = true
	tc.dice.force(1, 2)  # 0 -> 3, a plain unowned street
	check_eq(main.gate(), S.AWAIT_DIE_TAP, "person waits to roll")
	_tap(bv, bv.die_hit_rect().get_center())
	check_eq(tc.players[0].position, 3, "the die press rolled; the rules moved at once")
	check(bv.is_animating(), "board still moving")
	check_eq(main.gate(), S.BUSY, "rolling / moving")
	check(not main._turn_panel.visible and not bv.die_ready, "panel and die inert while the board moves")
	check(not main.press_slot(&"buy") and tc.phase == P.AWAITING_BUY_DECISION, "Buy ignored while busy")
	var board_size := bv.custom_minimum_size
	bv.advance(UiStyle.num("dice_roll_seconds", 0.55) + 0.05)
	main._refresh()
	check(bv.is_animating() and not main._turn_panel.visible, "no panel mid-hop")
	bv.advance(10.0)
	check(not bv.is_animating(), "board settled")
	main._refresh()  # animation_finished reaches Main deferred; the synchronous runner never flushes it
	check_eq(main.gate(), S.BUY, "buy decision once settled")
	var panel := main._turn_panel
	check(panel.visible and panel._name.text.contains(tc.players[0].display_name), "panel names the deciding seat")
	check(panel._name.text.contains("$%d" % tc.players[0].cash), "panel shows the seat's cash (Q28)")
	check(panel.offers(&"buy") and panel.offers(&"skip") and panel.offers(&"action"), "Buy / Skip / Action")
	check(panel.button(&"buy").text.begins_with(tc.board.term("buy")), "Buy keeps the themed term")
	check(panel.button(&"buy").text.contains("$%d" % tc.board.deed_at(3).list_price), "Buy shows the price")
	check(not panel.button(&"end_turn").visible, "no End Turn before deciding")
	check_eq(bv.custom_minimum_size, board_size, "the board does not resize for the panel")
	panel.button(&"buy").pressed.emit()
	check_eq(tc.board.deed_at(3).owner, 0, "bought through the panel")
	check_eq(main.gate(), S.END_TURN, "end of turn next")
	check(panel.offers(&"action") and panel.offers(&"end_turn") and not panel.button(&"buy").visible, "Action / End Turn after Buy")
	panel.button(&"end_turn").pressed.emit()
	check_eq(tc.current_index, 1, "turn handed on")
	check_eq(main.gate(), S.BOT, "bot's turn")
	check(not panel.visible and not bv.die_ready and not main._overlay.visible, "bot turn stays chrome-free")
	main.free()
	done()


## A4.1(c): after a doubles roll the rules are back in AWAITING_ROLL at once; a second press while
## the piece moves is ignored; after the hop the die is back and no panel shows (Q26).
func test_gate_doubles_second_press_ignored() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	var bv := main._board_view
	bv.animate = true
	tc.dice.force(2, 2)  # doubles: 0 -> 4
	check(main.press_die(), "first press rolls")
	check_eq(tc.phase, P.AWAITING_ROLL, "rules already back in AWAITING_ROLL")
	var log_size := tc.log_lines.size()
	tc.dice.force(3, 4)
	bv.advance(UiStyle.num("dice_roll_seconds", 0.55) + 0.1)
	check(bv.is_animating(), "mid-hop")
	_tap(bv, bv.die_hit_rect().get_center())
	check(not main.press_die(), "second press mid-hop ignored")
	_key(main, &"roll_dice")
	check_eq(tc.players[0].position, 4, "no second roll while the piece moves")
	check_eq(tc.log_lines.size(), log_size, "nothing happened")
	bv.advance(10.0)
	main._refresh()
	check_eq(main.gate(), S.AWAIT_DIE_TAP, "after the hop: the die again")
	check(bv.die_ready and not main._turn_panel.visible, "die and no panel between doubles rolls")
	check(main.press_die() and tc.players[0].position == 11, "the extra roll works once settled")
	main.free()
	done()


## A4.1(d): the jail set before the roll (Q25), the pardon only with a card, and a failed roll
## (no move) -> End Turn panel after the dice; fine / pardon never after the roll.
func test_gate_jail_set_then_failed_roll() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	var bv := main._board_view
	var panel := main._turn_panel
	var p := tc.players[0]
	p.in_jail = true
	p.set_position(tc.config.jail_index)
	main._refresh()
	check_eq(main.gate(), S.JAIL_SET, "jailed person: jail set")
	check(panel.offers(&"fine") and panel.offers(&"action"), "Pay fine / Action before the roll")
	check(panel.button(&"fine").text.contains(tc.board.term("jail_fine")), "fine keeps the themed term")
	check(not panel.button(&"pardon").visible, "no pardon without a card")
	check(not panel.button(&"end_turn").visible and not panel.button(&"buy").visible, "no post-move options yet")
	check(bv.die_ready, "the die rolls for doubles")
	var card: Card = null
	for c in tc.chance.draw_pile:
		if c.is_goojf():
			card = c
	tc.chance.draw_pile.erase(card)
	p.goojf_cards.append(card)
	main._refresh()
	check(panel.offers(&"pardon") and panel.button(&"pardon").text.contains(tc.board.term("pardon")), "pardon with a card")
	panel.button(&"pardon").pressed.emit()
	check(not p.in_jail and p.goojf_cards.is_empty(), "pardon used")
	check_eq(main.gate(), S.AWAIT_DIE_TAP, "released: die only")
	check(not panel.visible, "no panel after the release")
	p.in_jail = true
	main._refresh()
	tc.dice.force(1, 2)  # not doubles: stays, no move
	_tap(bv, bv.die_hit_rect().get_center())
	check(p.in_jail and p.position == tc.config.jail_index, "failed roll: still jailed, no move")
	check_eq(main.gate(), S.END_TURN, "End Turn panel after the dice")
	check(panel.offers(&"end_turn") and not panel.button(&"fine").visible and not panel.button(&"pardon").visible,
			"End Turn; fine / pardon only before the roll")
	main.free()
	done()


## A4.1(e): input a person owes off turn has a surface: a bid in an auction a bot's decline opened,
## a debt on a bot's turn (with Holdings for the debtor), and an answer to a bot's trade offer.
func test_gate_off_turn_overlays() -> void:
	var tc := GameSetup.new_game(1234)  # seat 1 person, seat 2 bot
	tc.current_index = 1
	var main := _main(tc)
	check_eq(main.gate(), S.BOT, "bot's turn")
	tc.dice.force(2, 3)
	tc.roll()
	tc.decline()
	check(tc.phase == P.AUCTION and tc.deciding_player() == 0, "the bot's decline opened an auction; the person bids")
	check_eq(main.gate(), S.AUCTION, "auction state for the person")
	check(_shown(main._auction_panel, main) and not _live_buttons(main._auction_panel, main).is_empty(), "auction overlay with live bids")
	check(not main._turn_panel.visible and not main._board_view.die_ready, "no turn panel or die off turn")
	main.free()

	tc = GameSetup.new_game(1234)
	tc.current_index = 1
	main = _main(tc)
	tc.players[0].cash = 10
	tc._charge(tc.players[0], 1, 200)
	tc._continue()
	check(tc.phase == P.RAISING_FUNDS and tc.current_index == 1, "a person owes on the bot's turn")
	check_eq(main.gate(), S.DEBT, "debt state for the person")
	check(_shown(main._debt_panel, main) and _live(main._debt_panel._bankrupt_button, main), "debt overlay with a live control")
	check(_shown(main._holdings_panel, main) and main._holdings_panel.actor_id() == 0, "Holdings open for the debtor")
	main.free()

	tc = GameSetup.new_game(1234)
	tc.current_index = 1
	main = _main(tc)
	var offer := Trade.propose(1, 0)
	offer.give_cash = 50
	check(tc.propose_trade(offer), "bot offers the person a trade")
	check_eq(tc.bot_actor(), -1, "bots wait until the person answers")
	check_eq(main.gate(), S.TRADE_ANSWER, "answer state for the receiver")
	check(_button_starting(main._trade_panel._actions, main, ["Reject"]) != null, "answer overlay with Reject")
	main.free()
	done()


## The fixed person policy over what is on screen: die, else Skip, else End Turn, else the
## overlay's pass / pay / reject / bankrupt control, else (a debtor who can do neither) a raise-funds
## control in the Holdings the debt overlay opens. Returns what it pressed, or &"" for nothing.
func _policy(main: Main) -> StringName:
	var bv := main._board_view
	if bv.die_ready and _shown(bv, main):
		_tap(bv, bv.die_hit_rect().get_center())
		return &"die"
	for slot: StringName in [&"skip", &"end_turn"]:
		if main._turn_panel.offers(slot) and _shown(main._turn_panel, main):
			main._turn_panel.button(slot).pressed.emit()
			return slot
	var picks := {
		&"pass": main._auction_panel._pass_button,
		&"pay": main._debt_panel._pay_button,
		&"reject": _button_starting(main._trade_panel._actions, main, ["Reject"]),
		&"bankrupt": main._debt_panel._bankrupt_button,
		&"raise": _button_starting(main._holdings_panel, main, ["Sell", "Mortgage"]),
	}
	for kind: StringName in picks:
		var b: BaseButton = picks[kind]
		if _live(b, main):
			b.pressed.emit()
			return kind
	return &""


## A4.1(f): 1 person + 2 bots, animate off. Whenever bot_actor() < 0 outside GAME_OVER, the deciding
## person has a visible, enabled control and the policy finds it.
func test_gate_no_stall_soak() -> void:
	var steps := 0
	var person_steps := 0
	var games := 0
	var seen := {}
	var main: Main = null
	while person_steps < 300 and steps < 20000:
		if main == null or main.controller.phase == P.GAME_OVER or main.controller.players[0].is_bankrupt:
			if main != null:
				if main.controller.phase == P.GAME_OVER:
					check(main.gate() == S.GAME_OVER and main._turn_panel.visible, "game over shows the winner")
				main.free()
			games += 1
			var fresh := GameSetup.new_game(100 + games, GameSetup.seats(1, 2))
			fresh.determine_start_player()
			main = _main(fresh)
			continue
		steps += 1
		var tc := main.controller
		if tc.bot_actor() >= 0:
			if not tc.bot_step():
				check(false, "bot step applies (step %d)" % steps)
				break
			continue
		person_steps += 1
		var pick := _policy(main)
		if pick == &"":
			check(false, "the person has a visible, enabled control (step %d, phase %s, gate %s)" % [
					steps, P.keys()[tc.phase], S.keys()[main.gate()]])
			break
		seen[pick] = true
	if main != null:
		main.free()
	print("  gate soak: %d steps, %d by the person, %d games, controls %s" % [steps, person_steps, games, seen.keys()])
	check(person_steps >= 300, "soak length: %d steps, %d by the person" % [steps, person_steps])
	for kind: StringName in [&"die", &"skip", &"end_turn", &"pass"]:
		check(seen.has(kind), "policy used %s" % kind)
	done()


## A4.1(g): game over shows only the winner's name; no die, no actions.
func test_gate_game_over_shows_winner() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	tc.players[1].is_bankrupt = true
	tc._check_winner()
	main._refresh()
	check_eq(main.gate(), S.GAME_OVER, "game over")
	check(main._turn_panel.visible and main._turn_panel._name.text.contains(tc.players[0].display_name), "winner named")
	check(_live_buttons(main._turn_panel, main).is_empty(), "no actions at game over")
	check(not main._board_view.die_ready and not main.press_die() and not main.press_slot(&"end_turn"), "no die, presses ignored")
	main.free()
	done()


## A2.3: a die press rolls once in AWAIT_DIE_TAP and selects no space; it is ignored in any other
## state, while the board moves and for a bot.
func test_die_press_rolls_once_only_when_gated() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	var bv := main._board_view
	var rolls := [0]
	tc.game_event.connect(func(kind: StringName, _info: Dictionary) -> void:
		if kind == &"rolled":
			rolls[0] += 1)
	tc.dice.force(1, 2)
	_tap(bv, bv.die_hit_rect().get_center())
	check_eq(rolls[0], 1, "one roll")
	check_eq(bv.selected_index, BoardView.NO_SELECTION, "the die press selected no space")
	check_eq(main.gate(), S.BUY, "buy decision")
	check(not bv.die_ready and not main.press_die(), "ignored in the buy decision")
	main.press_slot(&"skip")
	check(not main.press_die(), "ignored during the auction")
	check_eq(rolls[0], 1, "still one roll")
	main.free()

	main = _main(GameSetup.new_game(1234))
	bv = main._board_view
	bv.animate = true
	main.controller.dice.force(1, 2)
	check(main.press_die(), "rolls")
	check(not main.press_die(), "ignored while the board moves")
	main.free()

	tc = GameSetup.new_game(1234)
	tc.current_index = 1
	main = _main(tc)
	bv = main._board_view
	_tap(bv, bv.die_hit_rect().get_center())
	check(not main.press_die() and tc.players[1].position == 0, "ignored for a bot")
	main.free()
	done()


## A2.3: a press outside the die still selects a space, and the die hit area is touch-sized.
func test_die_press_outside_rect_selects_space() -> void:
	var main := _main(GameSetup.new_game(1234))
	var bv := main._board_view
	check(bv.die_ready, "die-ready")
	check(not bv.die_hit_rect().has_point(Vector2(420, 220)), "a side space is outside the die")
	_tap(bv, Vector2(420, 220))
	check_eq(bv.selected_index, 35, "a press outside the die selects the space")
	check_eq(main.controller.players[0].position, 0, "and does not roll")
	for side: float in [160.0, 300.0, 440.0, 800.0]:
		bv.size = Vector2(side, side)
		var hit := bv.die_hit_rect()
		check(hit.size.x >= UiStyle.touch() and hit.size.y >= UiStyle.touch(), "die hit area touch-sized at %d" % side)
		check(hit.encloses(bv.dice_rect()), "hit area covers the dice at %d" % side)
		if side >= 300.0:
			check(not hit.intersects(bv.banner_rect()), "die clear of the banner at %d" % side)
	main.free()
	done()


## A2.3: each InputMap action calls the same gated handler and is ignored outside its state.
func test_input_actions_follow_gate() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	tc.dice.force(1, 2)
	_key(main, &"buy_property")
	_key(main, &"end_turn")
	check(tc.phase == P.AWAITING_ROLL and tc.players[0].position == 0, "buy / end turn ignored before the roll")
	_key(main, &"roll_dice")
	check_eq(tc.phase, P.AWAITING_BUY_DECISION, "roll_dice rolled")
	tc.dice.force(1, 1)
	_key(main, &"roll_dice")
	_key(main, &"end_turn")
	check(tc.phase == P.AWAITING_BUY_DECISION and tc.players[0].position == 3, "roll / end turn ignored in the buy decision")
	main.press_slot(&"action")
	_key(main, &"buy_property")
	check_eq(tc.board.deed_at(3).owner, PropertyDeed.BANK, "keys ignored while the Action view is open")
	main.close_action()
	_key(main, &"buy_property")
	check_eq(tc.board.deed_at(3).owner, 0, "buy_property bought")
	_key(main, &"roll_dice")
	_key(main, &"buy_property")
	check(tc.phase == P.AWAITING_END_TURN and tc.players[0].position == 3, "roll / buy ignored at end of turn")
	_key(main, &"end_turn")
	check_eq(tc.current_index, 1, "end_turn ended the turn")
	_key(main, &"roll_dice")
	check_eq(tc.players[1].position, 0, "keys ignored on a bot's turn")
	main.free()
	done()


## Q24: Action opens Holdings / Trade / Log for the deciding seat (Dig 5a2: the board overlay) and
## Done brings the panel back; nothing of it shows before then.
func test_action_opens_holdings_for_acting_seat() -> void:
	var main := _main(GameSetup.new_game(1234))
	var tc := main.controller
	check(not main._overlay.visible and not _shown(main._holdings_panel, main), "Holdings closed at start")
	tc.dice.force(1, 2)
	main.press_die()
	main._holdings_panel.set_actor(1)
	check(main.press_slot(&"action"), "Action pressed")
	check(main.action_open() and not main._turn_panel.visible, "Action view replaces the panel")
	check(_shown(main._holdings_panel, main) and main._holdings_panel.actor_id() == 0, "Holdings for the deciding seat")
	check(_live(main._done_button, main) and not main._board_view.die_ready, "Done offered")
	check_eq(main._done_button.get_index(), 0, "Done leads the tab row (stays on screen in a narrow column)")
	main._done_button.pressed.emit()
	check(not main.action_open() and not main._overlay.visible, "Done closes the view")
	check(main._turn_panel.offers(&"buy") and main._turn_panel.offers(&"skip"), "the panel is back")
	main.press_slot(&"action")
	main.press_slot(&"skip")
	check_eq(tc.phase, P.AWAITING_BUY_DECISION, "panel presses ignored while Action is open")
	main.free()
	done()


## The die-ready look is distinct from the last-roll readout: drawn before any roll (faces 0) and
## on turn 1 after the start-order roll; tinted with the current seat's colour (Q27).
func test_die_ready_look_distinct() -> void:
	var main := _main(GameSetup.new_game(1234))
	var bv := main._board_view
	check(main.controller.dice.d1 == 0 and bv.dice_look() == &"ready", "die-ready before any roll")
	check_eq(bv._die_tint, main.controller.current_player().color, "tinted with the seat colour")
	bv.set_die_ready(false)
	check_eq(bv.dice_look(), &"none", "no readout without a roll")
	main.free()
	var tc := GameSetup.new_game(1234)
	tc.determine_start_player()
	tc.current_index = 0  # the person opens
	main = _main(tc)
	bv = main._board_view
	check(tc.dice.d1 > 0, "the start-order roll left faces")
	check_eq(bv.dice_look(), &"ready", "turn 1 shows the die-ready look, not the start-order roll")
	bv.set_die_ready(false)
	check_eq(bv.dice_look(), &"faces", "readout once not die-ready")
	main.free()
	done()


## Dig 5a2 (A0.3 / A1.5): each overlay (Action, auction bid, debt + Holdings, trade answer) names the
## seat it serves, opens Holdings for that seat (not a stale actor such as the bot whose turn it is)
## and floats inside the play area at its full minimum size, clear of the dialogue banner, on every
## phone size; the board keeps its full short side under it.
func test_overlays_float_without_reflow() -> void:
	var phones: Array[Vector2] = [Vector2(411, 880), Vector2(411, 731), Vector2(360, 640), Vector2(898, 395),
		Vector2(917, 825), Vector2(1280, 720)]
	for kind: StringName in [&"action", &"auction", &"debt", &"trade"]:
		var tc := GameSetup.new_game(1234)  # seat 1 person, seat 2 bot
		if kind != &"action":
			tc.current_index = 1  # the bot's turn: the overlay must name the person, not the current seat
		var main := _main(tc)
		main._holdings_panel.set_actor(1)
		match kind:
			&"action":
				tc.dice.force(1, 2)
				main.press_die()
				main.press_slot(&"action")
			&"auction":
				main.show_section(Main.Section.LOG)  # stale: opened while no overlay shows (e.g. a bot's debt)
				tc.dice.force(2, 3)
				tc.roll()
				tc.decline()  # the bot's decline: the person bids
			&"debt":
				tc.players[0].cash = 10
				tc._charge(tc.players[0], 1, 200)
				tc._continue()
			&"trade":
				var offer := Trade.propose(1, 0)
				offer.give_cash = 50
				tc.propose_trade(offer)
		check(main._overlay.visible and main._overlay_title.text.begins_with(tc.players[0].display_name),
				"%s overlay names the person it serves" % kind)
		check_eq(main._holdings_panel.actor_id(), 0, "%s overlay: Holdings acts for that person" % kind)
		var opens := {&"action": Main.Section.HOLDINGS, &"debt": Main.Section.HOLDINGS, &"trade": Main.Section.TRADE}
		if opens.has(kind):
			check(main.sections_open() and main._section == opens[kind], "%s overlay opens its section" % kind)
		else:
			check(not main.sections_open(), "auction overlay opens with its sections closed")
		for s: Vector2 in phones:
			main.size = s
			main._update_layout()
			var bm := main._board_view.custom_minimum_size
			check_eq(bm.y if s.y > s.x else bm.x, Main.board_side_for(s - Vector2(16, 16)),
					"board keeps its side under the %s overlay at %s" % [kind, s])
			check(main.overlay_fits(), "%s overlay inside the play area, clear of the banner at %s" % [kind, s])
		main.free()
	done()


## A0.3 / A1.5: the panel floats clear of the dialogue banner and inside the play area, and never
## covers the live die (jail set), even on small windows where it must cover the banner instead.
func test_turn_panel_clear_of_banner() -> void:
	var tc := GameSetup.new_game(1234)
	var bv := BoardView.new()
	bv.setup(tc)
	var margin := UiStyle.num("screen_margin", 8.0)
	var phones: Array[Vector2] = [Vector2(411, 880), Vector2(360, 640), Vector2(898, 395), Vector2(917, 825), Vector2(1280, 720)]
	for screen: Vector2 in phones + [Vector2(480, 360), Vector2(360, 480)]:
		var play := Rect2(Vector2(margin, margin), screen - Vector2(margin, margin) * 2.0)
		var side := Main.board_side_for(play.size)
		bv.size = Vector2(side, side)
		var board := Rect2(play.position, Vector2(side, side))
		var banner := Rect2(play.position + bv.banner_rect().position, bv.banner_rect().size)
		var die := Rect2(play.position + bv.die_hit_rect().position, bv.die_hit_rect().size)
		for avoid: Rect2 in [Rect2(), die]:
			var r := TurnPanel.rect_for(play, board, banner, 236.0, 174.0, avoid)
			check(play.encloses(r), "panel inside the play area at %s" % screen)
			check(not r.intersects(die) or not avoid.has_area(), "panel never covers the live die at %s" % screen)
			check(r.size.x >= UiStyle.num("turn_panel_min_width", 192.0), "panel wide enough at %s" % screen)
			if screen in phones:
				check(not r.intersects(banner), "panel clear of the banner at %s" % screen)
	bv.free()
	done()
