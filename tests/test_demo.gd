extends TestCase
## P4-DEMO presentation tests: game_event hook coverage, dialogue data load and fallbacks, the
## DialogueBanner queue API, BoardView's animation queue (driven by advance(), no scene tree)
## and Main wiring. Motion itself is smoke-checked only: it never changes game state.

const P := TurnController.Phase
const DIALOGUE_KEYS: Array[String] = [
	"match_start", "roll", "roll_bot", "doubles", "passed_go", "landed_unowned", "bought",
	"auction_won", "auction_unsold", "rent_paid", "rent_owed", "tax", "card_chance", "card_community",
	"jail_enter", "jail_exit_fine", "jail_exit_pardon", "jail_exit_doubles", "jail_exit_forced",
	"bankrupt", "trade_proposed", "trade_accepted", "trade_rejected", "trade_countered",
	"trade_withdrawn", "game_over",
]


func _game() -> TurnController:
	return GameSetup.new_game(1234)


## Records every game_event as [kind, info].
func _record(tc: TurnController) -> Array:
	var events := []
	tc.game_event.connect(func(kind: StringName, info: Dictionary) -> void: events.append([kind, info]))
	return events


func _kinds(events: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in events:
		out.append(e[0])
	return out


func test_dialogue_file_has_every_key() -> void:
	var path := String(UiStyle.theme_data().get("dialogue_path", ""))
	check(path.begins_with("res://data/themes/"), "theme names its dialogue file")
	check(FileAccess.file_exists(path), "dialogue file exists")
	var d := DialogueLines.load_theme()
	for k in DIALOGUE_KEYS:
		check(d.lines.has(k), "theme dialogue has '%s'" % k)
		check(DialogueLines.FALLBACK.has(k), "fallback English has '%s'" % k)
		var options: Array = d.lines.get(k, [])
		check(not options.is_empty(), "'%s' has at least one line" % k)
	var text := JSON.stringify(JsonData.load_json(path))
	for k in ["\"opcode\"", "\"space_type\"", "\"price\":", "\"rents\""]:
		check(not text.contains(k), "dialogue JSON carries no rules key %s" % k)
	done()


func test_every_line_fills_its_placeholders() -> void:
	var d := DialogueLines.load_theme()
	var vars := {"name": "A", "other": "B", "owner": "B", "space": "S", "amount": "$1", "price": "$2",
		"text": "T", "deck": "D", "d1": 1, "d2": 2, "total": 3}
	for k: String in d.lines:
		for v in d.lines[k]:
			var out := String(v).format(vars)
			check(not out.contains("{"), "'%s' line fully filled: %s" % [k, out])
	done()


func test_fallback_and_unknown_keys() -> void:
	var d := DialogueLines.load_theme("res://data/themes/no_such_theme/dialogue.json")
	check(d.lines.is_empty(), "missing file keeps only the fallback")
	check_eq(d.line("bought", {"name": "A", "space": "S"}), "A buys S.", "fallback English")
	check_eq(d.line("no_such_key"), "", "unknown key is silent")
	check(d.has_key("rent_paid") and not d.has_key("no_such_key"), "has_key")
	done()


func test_roll_to_unowned_emits_events_and_lines() -> void:
	var tc := _game()
	var events := _record(tc)
	tc.dice.force(1, 2)  # 0 -> 3 (unowned street)
	tc.roll()
	check_eq(_kinds(events), [&"rolled", &"moved", &"landed_unowned"] as Array[StringName], "roll events in order")
	var moved: Dictionary = events[1][1]
	check_eq([moved["from"], moved["to"], moved["steps"]], [0, 3, 3], "move info")
	var d := DialogueLines.load_theme()
	var roll := DialogueLines.describe(tc, &"rolled", events[0][1])
	check_eq(roll["key"], "roll", "a person's roll")
	check_eq(roll["vars"]["total"], 3, "dice total")
	check(DialogueLines.describe(tc, &"moved", moved).is_empty(), "moves have no banner line")
	var line := d.event_line(tc, &"landed_unowned", events[2][1])
	check(line.contains(tc.board.spaces[3].display_name), "unowned line names the space: %s" % line)
	tc.buy()
	check_eq(_kinds(events)[-1], &"bought", "buy event")
	done()


func test_bot_roll_uses_bot_line() -> void:
	var tc := _game()
	tc.players[0].is_bot = true
	var events := _record(tc)
	tc.dice.force(1, 2)
	tc.roll()
	check_eq(DialogueLines.describe(tc, &"rolled", events[0][1])["key"], "roll_bot", "bot announces its move")
	done()


func test_tax_jail_card_rent_events() -> void:
	var tc := _game()
	var events := _record(tc)
	var p := tc.players[0]
	tc.dice.force(2, 2)  # 0 -> 4 (tax), doubles
	tc.roll()
	check(_kinds(events).has(&"tax"), "tax event")
	p.set_position(25)
	tc.dice.force(2, 3)  # 25 -> 30: sent to the Brig
	tc.roll()
	var jailed := events.filter(func(e: Array) -> bool: return e[0] == &"jailed")
	check_eq(jailed.size(), 1, "jail event")
	if jailed.size() == 1:
		check_eq([jailed[0][1]["from"], jailed[0][1]["to"]], [30, tc.config.jail_index], "jump from the corner to the Brig")
	tc.end_turn()
	var q := tc.current_player()
	q.set_position(4)
	tc.dice.force(1, 2)  # 4 -> 7 (Mission Brief / chance)
	tc.roll()
	var cards := events.filter(func(e: Array) -> bool: return e[0] == &"card")
	check_eq(cards.size(), 1, "card event")
	if cards.size() == 1:
		var d := DialogueLines.describe(tc, &"card", cards[0][1])
		check_eq(d["key"], "card_chance", "chance deck line")
		check_eq(d["vars"]["text"], tc.last_card.text, "card text comes from the card data")
	done()


func test_rent_and_release_events() -> void:
	var tc := _game()
	var events := _record(tc)
	tc.board.deed_at(3).owner = 1
	tc.dice.force(1, 2)  # 0 -> 3, owned by player 1
	tc.roll()
	check(_kinds(events).has(&"rent"), "rent event")
	var rent: Array = events.filter(func(e: Array) -> bool: return e[0] == &"rent")[0]
	check_eq(DialogueLines.describe(tc, &"rent", rent[1])["key"], "rent_paid", "rent line key")
	tc.end_turn()
	var q := tc.current_player()
	q.set_position(tc.config.jail_index)
	q.in_jail = true
	check(tc.pay_jail_fine(), "fine paid")
	var released: Array = events.filter(func(e: Array) -> bool: return e[0] == &"released")
	check_eq(released.size(), 1, "release event")
	if released.size() == 1:
		check_eq(DialogueLines.describe(tc, &"released", released[0][1])["key"], "jail_exit_fine", "release key")
	done()


func test_trade_events() -> void:
	var tc := _game()
	var events := _record(tc)
	var offer := Trade.propose(0, 1)
	offer.give_cash = 50
	check(tc.propose_trade(offer), "offer open")
	check(tc.reject_trade(1), "rejected")
	check_eq(_kinds(events), [&"trade_proposed", &"trade_rejected"] as Array[StringName], "trade events")
	var d := DialogueLines.load_theme()
	check(d.event_line(tc, &"trade_proposed", events[0][1]).contains(tc.players[0].display_name), "proposer named")
	done()


func test_banner_queue_api() -> void:
	var b := DialogueBanner.new()
	var shown: Array[String] = []
	var emptied := [0]
	b.line_shown.connect(func(t: String) -> void: shown.append(t))
	b.emptied.connect(func() -> void: emptied[0] += 1)
	check(not b.is_showing(), "starts empty")
	b.push("")
	check(not b.is_showing(), "empty text ignored")
	b.push("one")
	check(b.is_showing() and b.visible, "first line shows at once")
	check_eq(b.current_text(), "one", "current line")
	check(is_equal_approx(b.time_left(), UiStyle.num("banner_seconds", 2.2)), "full time when alone")
	b.push("two")
	b.push("three")
	check_eq(b.queue_size(), 2, "two waiting")
	check(b.time_left() <= UiStyle.num("banner_backlog_seconds", 1.2) + 0.001, "backlog shortens the line on screen")
	b.advance(10.0)
	check_eq(b.current_text(), "two", "auto-dismiss moves on")
	b.dismiss()
	check_eq(b.current_text(), "three", "tap-dismiss moves on")
	b.advance(0.1)
	check_eq(b.current_text(), "three", "short tick keeps the line")
	b.advance(10.0)
	check(not b.is_showing() and not b.visible, "queue drained, banner hidden")
	check_eq(emptied[0], 1, "emptied once")
	check_eq(shown, ["one", "two", "three"] as Array[String], "lines shown in order")
	var cap := int(UiStyle.num("banner_max_queue", 4))
	for i in cap + 3:
		b.push("l%d" % i)
	check_eq(b.queue_size(), cap, "backlog capped")
	check_eq(b.current_text(), "l0", "line on screen kept")
	b.dismiss()
	check_eq(b.current_text(), "l3", "oldest waiting lines dropped")
	b.clear()
	check(not b.is_showing() and b.queue_size() == 0, "clear")
	b.free()
	done()


func test_board_view_animation_queue() -> void:
	var tc := _game()
	var bv := BoardView.new()
	bv.setup(tc)
	bv.size = Vector2(440, 440)
	bv.animate = true  # driven by advance() here; Main enables it only inside the live tree
	var finished := [0]
	var called := []
	bv.animation_finished.connect(func() -> void: finished[0] += 1)
	var p := tc.players[0]
	tc.dice.force(1, 2)  # 0 -> 3, a plain unowned street
	tc.game_event.connect(func(kind: StringName, info: Dictionary) -> void:
		if kind == &"rolled":
			bv.queue_dice(info["d1"], info["d2"])
		elif kind == &"moved":
			bv.queue_move(info["player"], info["from"], info["steps"]))
	tc.roll()
	bv.queue_call(func() -> void: called.append(true))
	check_eq(p.position, 3, "game state moved at once")
	check(bv.is_animating(), "view still animating")
	check_eq(bv.shown_position(0), 0, "token waits at the start")
	check(called.is_empty(), "callback waits for the motion")
	bv.advance(UiStyle.num("dice_roll_seconds", 0.55) + UiStyle.num("pawn_step_seconds", 0.14) * 2.5)
	check_eq(bv.shown_dice(), Vector2i(1, 2), "dice settled after the tumble")
	check_eq(bv.shown_position(0), 0, "token mid-hop still counts from its start")
	bv.advance(5.0)
	check(not bv.is_animating(), "queue drained")
	check_eq(bv.shown_position(0), 3, "token arrived")
	check_eq(called.size(), 1, "callback ran after the move")
	check_eq(finished[0], 1, "animation_finished once")
	# Once the queue drains, tokens snap to the game state, so keep the game in step here.
	p.set_position(tc.config.jail_index)
	var mid := []
	bv.queue_jump(0, 3, tc.config.jail_index)
	bv.queue_call(func() -> void: mid.append(bv.shown_position(0)))
	bv.queue_move(0, 10, -3)
	bv.queue_call(func() -> void: mid.append(bv.shown_position(0)))
	bv.advance(UiStyle.num("pawn_jump_seconds", 0.6) * 0.5)
	check_eq(bv.shown_position(0), 3, "mid-jump still counts from its start")
	bv.advance(5.0)
	check_eq(mid, [tc.config.jail_index, 7], "jump lands in the Brig, then a backward move")
	check_eq(bv.shown_position(0), tc.config.jail_index, "drained queue snaps to the game")
	var long_move := 39
	bv.queue_move(0, 0, long_move)
	bv.advance(UiStyle.num("pawn_move_max_seconds", 1.8) + 0.01)
	check(not bv.is_animating(), "long moves are capped in time")
	bv.free()
	done()


func test_board_view_instant_without_animation() -> void:
	var tc := _game()
	var bv := BoardView.new()
	bv.setup(tc)
	var called := []
	bv.queue_dice(2, 5)
	bv.queue_move(1, 0, 6)
	bv.queue_call(func() -> void: called.append(true))
	check(not bv.is_animating(), "nothing queued when animate is off")
	check_eq(bv.shown_dice(), Vector2i(2, 5), "dice applied")
	check_eq(bv.shown_position(1), 6, "move applied")
	check_eq(called.size(), 1, "callback ran at once")
	bv.free()
	done()


func test_ui_fx_instant_outside_tree() -> void:
	var c := PanelContainer.new()
	UiFx.set_shown(c, false)
	check(not c.visible, "hidden at once")
	UiFx.set_shown(c, true)
	check(c.visible and is_equal_approx(c.modulate.a, 1.0), "shown at once, opaque")
	UiFx.fade_in(c)
	UiFx.pulse(c)
	check(is_equal_approx(c.modulate.a, 1.0), "fade / pulse are no-ops outside the tree")
	c.free()
	done()


func test_main_banner_and_summary() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = _game()
	main.start(null)
	var tc := main.controller
	check(main._banner.is_showing(), "opening line shown")
	check(main._banner.current_text().contains(tc.current_player().display_name), "opening line names the first commander")
	check(not main.is_busy(), "no motion outside the tree")
	tc.dice.force(1, 2)
	tc.roll()
	check(main._banner.queue_size() >= 1, "roll lines queued behind the opening line")
	tc.buy()
	check(main.press_slot(&"action") and main._overlay.visible, "Action opens the overlay")
	check(main._player_labels[0].text.contains("1 deed"), "overlay chip shows holdings: %s" % main._player_labels[0].text)
	check(main._overlay_title.text.contains(tc.players[0].display_name), "overlay title names the deciding seat")
	main.free()
	done()
