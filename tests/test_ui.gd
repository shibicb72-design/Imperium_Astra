extends TestCase
## UI smoke tests: panels instantiate against a real TurnController, show the right controls
## per phase, keep every button touch-sized, and keep trade / auction / debt answers pinned
## outside scroll areas. Also the pure helpers (DisplayScale, BoardView grid math, board sizing).

const P := TurnController.Phase


func _game() -> TurnController:
	return GameSetup.new_game(1234)


## Every button-like control under node (recursive).
func _buttons(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in node.get_children():
		if c is BaseButton or c is SpinBox:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func _check_touch_sized(node: Node, what: String) -> void:
	var buttons := _buttons(node)
	check(not buttons.is_empty(), "%s has buttons" % what)
	for b in buttons:
		check(b.custom_minimum_size.y >= UiStyle.touch(), "%s: '%s' is touch-sized" % [what, b.get("text")])


func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for b in _buttons(node):
		if b is Button and not b is OptionButton and b.visible:
			out.append((b as Button).text)
	return out


func test_display_scale_factor() -> void:
	check(is_equal_approx(DisplayScale.factor_for("Android", 420), 2.625), "Fold-class phone ~2.6x")
	check_eq(DisplayScale.factor_for("Windows", 420), 1.0, "desktop no-op")
	check_eq(DisplayScale.factor_for("Web", 300), 1.0, "web no-op")
	check_eq(DisplayScale.factor_for("Android", 0), 1.0, "unknown dpi")
	check_eq(DisplayScale.factor_for("Android", 100), 1.0, "never below 1")
	check_eq(DisplayScale.factor_for("iOS", 2000), 4.0, "capped")
	done()


func test_board_grid_round_trip() -> void:
	for i in 40:
		check_eq(BoardView.index_of_cell(BoardView.cell_of(i)), i, "round trip %d" % i)
	check_eq(BoardView.index_of_cell(Vector2i(5, 5)), BoardView.NO_SELECTION, "center")
	check_eq(BoardView.index_of_cell(Vector2i(11, 0)), BoardView.NO_SELECTION, "outside")
	done()


func test_board_view_tap_and_details() -> void:
	var tc := _game()
	tc.board.deed_at(39).owner = 1
	var bv := BoardView.new()
	bv.setup(tc)
	bv.size = Vector2(440, 440)
	check_eq(bv.index_at(Vector2(420, 220)), 35, "right column middle")
	check_eq(bv.index_at(Vector2(420, 380)), 39, "next to the start corner")
	check_eq(bv.index_at(Vector2(220, 220)), BoardView.NO_SELECTION, "center is not a space")
	bv.select(39)
	check_eq(bv.selected_index, 39, "selected")
	var lines := bv.space_details(39)
	check(lines[0] == tc.board.spaces[39].display_name, "full name in details")
	check(" ".join(lines).contains(tc.players[1].display_name), "owner in details")
	check(" ".join(lines).contains("Rent"), "rent table in details")
	bv.select(39)
	check_eq(bv.selected_index, BoardView.NO_SELECTION, "second tap clears")
	check(bv.space_details(BoardView.NO_SELECTION).is_empty(), "no details without selection")
	for s in tc.board.spaces:
		check(not s.short_name.is_empty(), "short name for %d" % s.index)
	bv.free()
	done()


func test_board_side_keeps_room_for_controls() -> void:
	check_eq(Main.board_side_for(Vector2(395, 880)), 395.0, "portrait phone: full width")
	check_eq(Main.board_side_for(Vector2(898, 395)), 395.0, "landscape phone: full height")
	var unfolded := Main.board_side_for(Vector2(917, 825))
	check(unfolded < 825.0 and unfolded > 400.0, "unfolded Fold: board shares the width")
	check(Main.board_side_for(Vector2(395, 700)) < 395.0, "short portrait: board shrinks")
	done()


func test_auction_panel_controls() -> void:
	var tc := _game()
	tc.dice.force(2, 3)  # 0 -> 5 (unowned jump gate)
	tc.roll()
	tc.decline()
	check_eq(tc.phase, P.AUCTION, "auction running")
	var panel := AuctionPanel.new()
	panel.setup(tc)
	panel.refresh()
	check(panel.visible, "visible in auction")
	_check_touch_sized(panel, "auction")
	var texts := _texts(panel)
	check(texts.any(func(t: String) -> bool: return t.begins_with("Drop Out")), "drop out shown")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Bid $")), "bid shown")
	panel._on_bid(0)
	check(tc.auction.has_winner(), "quick bid placed")
	tc.phase = P.AWAITING_END_TURN
	panel.refresh()
	check(not panel.visible, "hidden outside auction")
	panel.free()
	done()


func test_debt_panel_controls() -> void:
	var tc := _game()
	tc.board.deed_at(3).owner = 1
	tc.players[0].cash = 1
	tc.dice.force(1, 2)  # 0 -> 3, rent to player 1
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "raising funds")
	var panel := DebtPanel.new()
	panel.setup(tc)
	panel.refresh()
	check(panel.visible, "visible while raising funds")
	_check_touch_sized(panel, "debt")
	check(panel._pay_button.disabled, "cannot pay yet")
	check(panel._bankrupt_button.visible, "bankruptcy reachable")
	panel.free()
	done()


func test_holdings_panel_actions_call_modules() -> void:
	var tc := _game()
	tc.board.deed_at(1).owner = 0
	tc.board.deed_at(3).owner = 0
	var panel := HoldingsPanel.new()
	panel.setup(tc)
	panel.set_actor(0)
	_check_touch_sized(panel, "holdings")
	var texts := _texts(panel)
	check_eq(texts.filter(func(t: String) -> bool: return t.begins_with("Build")).size(), 2, "build per street")
	check_eq(texts.filter(func(t: String) -> bool: return t.begins_with("Mortgage")).size(), 2, "mortgage per deed")
	panel.set_actor(1)
	check(_texts(panel).is_empty(), "other commander has no deed buttons")
	check_eq(panel.actor_id(), 1, "actor switched")
	panel.free()
	done()


func test_trade_panel_answers_pinned() -> void:
	var tc := _game()
	var panel := TradePanel.new()
	panel.setup(tc)
	check(_texts(panel._actions).has("Propose"), "draft has Propose")
	check_eq(panel._actions.get_parent(), panel, "draft actions pinned outside the scroll")
	var offer := Trade.propose(0, 1)
	offer.give_cash = 100
	check(tc.propose_trade(offer), "offer open")
	panel.refresh()
	check(panel.has_open_offer(), "open offer")
	var texts := _texts(panel._actions)
	check_eq(texts.size(), 4, "accept, reject, counter, withdraw")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Reject")), "reject pinned")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Withdraw")), "withdraw pinned")
	_check_touch_sized(panel, "trade")
	panel._start_counter()
	check(_texts(panel._actions).has("Back"), "counter has Back")
	panel.free()
	done()


func test_main_scene_smoke() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = _game()
	main.start(null)  # outside the tree: the test runner's root is not live yet
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(411, 880)
	main._update_layout()
	check(main._box.vertical, "portrait stacks the board")
	check(main._roll_button.visible, "roll offered")
	check(not main._end_button.visible, "end turn hidden before rolling")
	_check_touch_sized(main, "main")
	main.controller.dice.force(2, 3)
	main.controller.roll()
	check(main._buy_button.visible and main._pass_button.visible, "claim / pass offered")
	main.controller.decline()
	check(main._auction_panel.visible, "auction banner shown")
	check(not main._actions.visible, "no turn actions during the auction")
	main.size = Vector2(898, 395)
	main._update_layout()
	check(not main._box.vertical, "landscape side by side")
	main.show_section(Main.Section.LOG)
	check(not main._log_label.text.is_empty(), "log filled")
	main.free()
	done()


func _inside_scroll(node: Node) -> bool:
	var n := node.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


func test_main_pinned_rows_fit_short_portrait() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = _game()
	main.start(null)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var offer := Trade.propose(1, 0)
	offer.give_cash = 50
	check(main.controller.propose_trade(offer), "offer open")
	check_eq(main._section, Main.Section.TRADE, "trade tab opened for the offer")
	for s: Vector2 in [Vector2(411, 731), Vector2(360, 640), Vector2(411, 880)]:
		main.size = s
		main._update_layout()
		check(main.side_fits(), "controls fit at %s" % s)
	check(not _inside_scroll(main._trade_panel._actions), "trade answers not in a scroll")
	check(not _inside_scroll(main._auction_panel), "auction banner not in a scroll")
	check(not _inside_scroll(main._debt_panel), "debt banner not in a scroll")
	check(not _inside_scroll(main._actions), "turn actions not in a scroll")
	main.free()
	done()
