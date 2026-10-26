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


## Dig 4a (teardown noise): UI code connects no lambda with CONNECT_DEFERRED. A lambda keeps a raw
## self, so a call still queued when its node is freed (tests free Main) ran against a dead or
## reused instance after the totals; a bound method's queued call is dropped instead.
func test_no_deferred_lambda_connections_in_ui() -> void:
	var dir := "res://scripts/ui"
	for fname in DirAccess.get_files_at(dir):
		if not fname.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string(dir.path_join(fname)).split("\n")
		for i in lines.size():
			var code := lines[i].strip_edges()
			if code.begins_with("#") or not code.contains("CONNECT_DEFERRED"):
				continue
			var start := i  # walk back to the .connect( line that opens this statement
			while start > 0 and not lines[start].contains(".connect("):
				start -= 1
			var statement := "\n".join(lines.slice(start, i + 1))
			check(not statement.contains("func("), "%s:%d connects no lambda deferred" % [fname, i + 1])
	done()


## Dig 5 (A1.5): the board takes the full short side in both orientations; the controls float over
## it (Dig 5a2 board overlay: inside the play area, clear of the dialogue banner) instead of taking room.
func test_board_side_keeps_room_for_controls() -> void:
	check_eq(Main.board_side_for(Vector2(395, 880)), 395.0, "portrait phone: full width")
	check_eq(Main.board_side_for(Vector2(898, 395)), 395.0, "landscape phone: full height")
	check_eq(Main.board_side_for(Vector2(917, 825)), 825.0, "unfolded Fold: board takes the full short side")
	check_eq(Main.board_side_for(Vector2(395, 700)), 395.0, "short portrait: board keeps the full width")
	for avail: Vector2 in [Vector2(917, 825), Vector2(395, 700)]:
		var play := Rect2(Vector2(8, 8), avail)
		var board := Rect2(play.position, Vector2.ONE * Main.board_side_for(avail))
		var banner := BoardView.banner_rect_in(board)
		var r := Main.overlay_rect_for(play, board, banner, Vector2(240, 240), true)
		check(play.encloses(r) and r.size.y >= 240.0, "overlay floats inside the play area at %s" % avail)
		check(not r.intersects(banner), "overlay clear of the banner at %s" % avail)
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
	check(not main._overlay.visible and main._board_view.custom_minimum_size.y == 395.0, "portrait: board fills the play width")
	check(main.gate() == MatchGate.State.AWAIT_DIE_TAP and main._board_view.die_ready, "die affordance live before rolling")
	check(not main._turn_panel.visible, "no turn panel (no End Turn) before rolling")
	_check_touch_sized(main, "main")
	main.controller.dice.force(2, 3)
	check(main.press_die(), "die press rolls")
	check(main._turn_panel.offers(&"buy") and main._turn_panel.offers(&"skip"), "panel Buy + Skip once the board settles")
	_check_touch_sized(main._turn_panel, "turn panel")
	main.press_slot(&"skip")
	for _i in 100:  # the bot bids first; then the person decides
		if main.controller.phase != P.AUCTION or main.controller.bot_actor() < 0 or not main.controller.bot_step():
			break
	check(main.gate() == MatchGate.State.AUCTION and main._overlay.visible and main._auction_panel.visible,
			"auction overlay for the person bidding")
	check_eq(main._board_view.custom_minimum_size.y, 395.0, "the overlay never resizes the board")
	check(not main._turn_panel.visible, "no turn panel during the auction")
	main.size = Vector2(898, 395)
	main._update_layout()
	check(main._overlay.visible and main._board_view.custom_minimum_size.x == 379.0, "landscape: board fills the play height under the overlay")
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
	check(main._overlay.visible, "answer overlay open for the receiver")
	for s: Vector2 in [Vector2(411, 731), Vector2(360, 640), Vector2(411, 880)]:
		main.size = s
		main._update_layout()
		check(main.overlay_fits(), "answer overlay fits clear of the banner at %s" % s)
		check_eq(main._board_view.custom_minimum_size.y, s.x - 16.0, "board keeps the full width at %s" % s)
	main.toggle_tab(Main.Section.TRADE)
	check(main.sections_open() and main._section == Main.Section.TRADE, "the open offer's Trade tab stays open while the answer waits")
	check(not _inside_scroll(main._trade_panel._actions), "trade answers not in a scroll")
	check(not _inside_scroll(main._auction_panel), "auction banner not in a scroll")
	check(not _inside_scroll(main._debt_panel), "debt banner not in a scroll")
	check(not _inside_scroll(main._turn_panel), "turn panel not in a scroll")
	main.free()
	done()


## Fold bugfix, on the Dig 5a2 board overlay: the overlay and its sections sit on opaque panels, are
## closed at start and opened via Action; the open tab collapses them; a person's debt opens the
## debt overlay with Holdings for the debtor.
func test_main_sections_opaque_and_collapsible() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = _game()
	main.start(null)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(411, 880)
	main._update_layout()
	var sb := main._section_holder.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null and sb.draw_center and is_equal_approx(sb.bg_color.a, 1.0), "section backing opaque")
	var ob := main._overlay.get_theme_stylebox("panel") as StyleBoxFlat
	check(ob != null and ob.draw_center and is_equal_approx(ob.bg_color.a, 1.0), "overlay backing opaque")
	check(main._section_holder.clip_contents, "section area clips")
	var acting := main._holdings_panel.get_child(0).get_child(0) as Label
	check_eq(acting.autowrap_mode, TextServer.AUTOWRAP_OFF, "Acting label does not wrap")
	check(not main._overlay.visible and not main.sections_open(), "holdings closed at start")
	main.controller.dice.force(1, 2)
	main.press_die()
	check(main.press_slot(&"action") and main._overlay.visible, "Action opens the overlay")
	check(main.sections_open() and main._section == Main.Section.HOLDINGS, "Action opens holdings")
	main.toggle_tab(Main.Section.HOLDINGS)
	check(not main.sections_open(), "tapping the open tab collapses")
	check(not main._section_holder.visible, "section area hidden")
	check(main._tab_buttons.all(func(b: Button) -> bool: return not b.button_pressed), "no tab selected")
	main.toggle_tab(Main.Section.LOG)
	check(main.sections_open() and main._section == Main.Section.LOG, "another tab opens")
	check(main._tab_buttons[Main.Section.LOG].button_pressed, "log tab selected")
	main.toggle_tab(Main.Section.TRADE)
	check_eq(main._section, Main.Section.TRADE, "switching tabs keeps sections open")
	main.toggle_tab(Main.Section.TRADE)
	check(not main.sections_open(), "trade tab collapses too")
	main.close_action()
	check(not main._overlay.visible, "Done closes the overlay")
	var tc := main.controller
	var debtor := tc.players[0]
	main._holdings_panel.set_actor(1)
	debtor.cash = 10
	tc._charge(debtor, 1, 200)
	tc._continue()
	check(main.gate() == MatchGate.State.DEBT and main._overlay.visible and main._debt_panel.visible, "debt overlay for the person")
	check(main.sections_open() and main._section == Main.Section.HOLDINGS, "debt force-opens holdings")
	check_eq(main._holdings_panel.actor_id(), debtor.id, "debtor is the holdings actor")
	main.free()
	done()


## Visible all the way up to `root` (is_visible_in_tree() needs a live tree; as test_match_gate.gd).
func _shown(c: CanvasItem, root: Node) -> bool:
	var n: Node = c
	while n != null and n != root:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return n == root


## Main at a phone size, outside the tree (as test_main_sections_opaque_and_collapsible).
func _phone_main(s: Vector2) -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = _game()
	main.start(null)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = s
	main._update_layout()
	return main


## Exactly `section` of Holdings / Trade / Log is open and shown; the other two are not.
func _check_only(main: Main, section: int, what: String) -> void:
	check(main.sections_open() and main._section == section, "%s: section %d open" % [what, section])
	for i in main._sections.size():
		check_eq(_shown(main._sections[i], main), i == section, "%s: section %d shown only when picked" % [what, i])


## Q21 Fold fix (Bug 1): Main alone decides which section shows, so a refresh (any state change)
## after a tab is picked never re-shows Trade beside Holdings or Log in the one section area.
func test_main_sections_exclusive() -> void:
	for s: Vector2 in [Vector2(411, 880), Vector2(360, 640)]:
		var main := _phone_main(s)
		main.controller.dice.force(1, 2)
		main.press_die()
		check(main.press_slot(&"action"), "Action opens at %s" % s)
		main._refresh()
		_check_only(main, Main.Section.HOLDINGS, "Action at %s" % s)
		main.toggle_tab(Main.Section.LOG)
		main._refresh()
		_check_only(main, Main.Section.LOG, "Log tab at %s" % s)
		main.toggle_tab(Main.Section.TRADE)
		main._refresh()
		_check_only(main, Main.Section.TRADE, "Trade tab at %s" % s)
		main.close_action()
		var tc := main.controller
		var debtor := tc.players[0]
		debtor.cash = 10
		tc._charge(debtor, 1, 200)
		tc._continue()
		main._refresh()
		check(main.gate() == MatchGate.State.DEBT, "debt for the person at %s" % s)
		_check_only(main, Main.Section.HOLDINGS, "debt at %s" % s)
		main.free()
		main = _phone_main(s)
		var offer := Trade.propose(1, 0)
		offer.give_cash = 50
		check(main.controller.propose_trade(offer), "offer open at %s" % s)
		main._refresh()
		_check_only(main, Main.Section.TRADE, "offer to a person at %s" % s)
		main.toggle_tab(Main.Section.TRADE)
		main._refresh()
		_check_only(main, Main.Section.TRADE, "re-tapped offer at %s" % s)
		main.free()
	done()


## Q21 Fold fix: at phone widths the open section's rows fit the overlay's content width and the
## pickers stay touch-height boxes (outside the tree: minimum sizes; the Fold screencap is separate).
func test_main_sections_fit_phone_width() -> void:
	for s: Vector2 in [Vector2(411, 880), Vector2(360, 640)]:
		var main := _phone_main(s)
		main.controller.dice.force(1, 2)
		main.press_die()
		check(main.press_slot(&"action"), "Action opens at %s" % s)
		var styles := main._overlay.get_theme_stylebox("panel").get_minimum_size() \
				+ main._section_holder.get_theme_stylebox("panel").get_minimum_size()
		for tab: int in [Main.Section.HOLDINGS, Main.Section.TRADE]:
			if tab != main._section:
				main.toggle_tab(tab)
			main._refresh()
			_check_only(main, tab, "fit check at %s" % s)
			check(main.overlay_fits(), "overlay fits with section %d at %s" % [tab, s])
			var width := main._overlay_rect().size.x - styles.x
			var rows: Array[Control] = [main._holdings_panel.get_child(0) as Control]
			if tab == Main.Section.TRADE:
				rows = [main._trade_panel._from_picker.get_parent() as Control, main._trade_panel._actions]
			for row in rows:
				var need := row.get_combined_minimum_size().x
				check(need <= width, "%s fits at %s (%.1f <= %.1f)" % [row.get_class(), s, need, width])
			var tp := main._trade_panel
			check_eq(tp._pickers.vertical, tp.picker_row_width() > width, "pickers stack only where one row does not fit at %s" % s)
		for picker: OptionButton in [main._holdings_panel._actor_picker, main._trade_panel._from_picker,
				main._trade_panel._to_picker]:
			check(picker.get_combined_minimum_size().y <= UiStyle.touch() * 1.25, "picker stays one touch row at %s" % s)
		main.free()
	done()


const ROLL_LINE := "The augurs read 5 and 1 for Commander 2."
## "Mission Brief: " + the data/cards.json ch_nearest_utility text (a long card line).
const CARD_LINE := "Mission Brief: Advance to the nearest power or water plant. If owned, roll the dice and pay the owner 10 times the roll. If unclaimed, you may buy it."


## `text` wrapped at the banner reservation's text width, measured with the banner label's own
## font, font size and line spacing: (widest line, total height).
func _toast_text_size(main: Main, text: String) -> Vector2:
	var label: Label = main._banner._label
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var margins := main._banner.get_theme_stylebox("panel").get_minimum_size()
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var t := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
			main._board_view.banner_rect().size.x - margins.x, fs, -1, flags)
	var lines := roundi(t.y / font.get_height(fs))
	return Vector2(t.x, t.y + label.get_theme_constant("line_spacing") * maxi(0, lines - 1))


## Main at `s`, its board view set to the board side by hand (containers do not lay out outside the
## tree, as test_match_gate.gd does), with `text` alone on the banner.
func _toast_main(s: Vector2, text: String) -> Main:
	var main := _phone_main(s)
	main._board_view.size = Vector2.ONE * Main.board_side_for(main._play_rect().size)
	main._banner.clear()
	main._banner.push(text)
	main._place_banner()
	return main


## Q21 Fold fix (Bug 2): the roll line's banner is a compact toast sized to its wrapped text, not the
## whole reservation; it stays centered in BoardView.banner_rect() (which overlays and the turn panel
## keep clear of) and off the die.
func test_banner_toast_compact() -> void:
	for s: Vector2 in [Vector2(411, 880), Vector2(360, 640), Vector2(898, 395), Vector2(917, 825)]:
		var main := _toast_main(s, ROLL_LINE)
		var b := Rect2(main._banner.position, main._banner.size)
		var reserve := main._board_view.banner_rect()
		var t := _toast_text_size(main, ROLL_LINE) + main._banner.get_theme_stylebox("panel").get_minimum_size()
		check(b.size.y >= t.y and b.size.y <= t.y + 2.0, "toast height fits its text at %s (%.1f vs %.1f)" % [s, b.size.y, t.y])
		check(b.size.x >= t.x and b.size.x <= t.x + 2.0, "toast width fits its text at %s (%.1f vs %.1f)" % [s, b.size.x, t.x])
		if s == Vector2(411, 880):
			var side := main._board_view.size.x
			check(b.size.y <= 0.18 * side, "toast at most 18%% of the board high (%.1f)" % b.size.y)
			check(b.size.x * b.size.y <= 0.12 * side * side, "toast covers at most 12%% of the board (%.0f)" % (b.size.x * b.size.y))
		check(reserve.grow(1.0).encloses(b), "toast inside the banner reservation at %s" % s)
		check(absf(b.get_center().x - reserve.get_center().x) <= 1.0, "toast centered at %s" % s)
		check(not b.intersects(main._board_view.die_hit_rect()), "toast clear of the die at %s" % s)
		main.free()
	done()


## Q21: every shown line re-places the toast: a long card line takes the full reservation width from
## its top and no more (Q22 truncate-to-reserve: the lines past it are cut with an ellipsis); the
## next short line shrinks it back.
func test_banner_toast_follows_line() -> void:
	for s: Vector2 in [Vector2(411, 880), Vector2(360, 640)]:
		var main := _toast_main(s, ROLL_LINE)
		var reserve := main._board_view.banner_rect()
		var short := main._banner.size
		main._banner.push(CARD_LINE)
		main._banner.dismiss()
		check_eq(main._banner.current_text(), CARD_LINE, "card line shown at %s" % s)
		var margins := main._banner.get_theme_stylebox("panel").get_minimum_size()
		check(absf(main._banner.size.x - reserve.size.x) <= 0.5, "card line takes the reservation width at %s" % s)
		check(absf(main._banner.position.y - reserve.position.y) <= 0.5, "card line grows down from the reservation top at %s" % s)
		check(reserve.grow(1.0).encloses(Rect2(main._banner.position, main._banner.size)),
				"card line toast inside the reservation at %s (%.1f)" % [s, main._banner.size.y])
		var lines := _banner_lines(main._banner._label)
		if _toast_text_size(main, CARD_LINE).y + margins.y > reserve.size.y:
			check(lines.x < lines.y, "card line past the reservation shows %d of %d lines at %s" % [lines.x, lines.y, s])
		check_eq(main._banner._label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
				"card line ends in an ellipsis at %s" % s)
		main._banner.push(ROLL_LINE)
		main._banner.dismiss()
		check(main._banner.size.is_equal_approx(short), "the roll line shrinks the toast back at %s" % s)
		main.free()
	done()


## (lines the banner label shows, lines its text wraps to) at its placed size, by the Label's own
## rule: a line shows while the lines so far fit its height. Font metrics, because outside the tree
## Label.get_line_count() and get_visible_line_count() both return 1 (the build/ in-tree probe
## reads the Label's own counts).
func _banner_lines(label: Label) -> Vector2i:
	var style := label.get_theme_stylebox("normal").get_minimum_size()
	var para := TextParagraph.new()
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.width = label.size.x - style.x
	para.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	var spacing := float(label.get_theme_constant("line_spacing"))
	var shown := 0
	var h := 0.0
	for i in para.get_line_count():
		h += para.get_line_size(i).y + spacing
		if h > label.size.y - style.y + spacing:
			break
		shown += 1
	return Vector2i(shown, para.get_line_count())


func _near(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) <= 0.5 and absf(a.position.y - b.position.y) <= 0.5 \
			and absf(a.size.x - b.size.x) <= 0.5 and absf(a.size.y - b.size.y) <= 0.5


## Q22 1B (Shibi, Oct 26 2026) on the pure placement, with needs from the in-tree probe (Action ->
## Trade after the Trade fixes, the collapsed Action card, stacked-picker Trade): in portrait where
## the free band cannot hold need.y the overlay docks at the bottom, collapsed at the play bottom
## below the banner, open from the banner's top to the play bottom over it. Phones whose band holds
## the card and every landscape size keep the tip placement; the board stays square (2A).
func test_overlay_rect_docks_bottom_1b() -> void:
	var pad := UiStyle.num("screen_margin", 8.0)
	var trade := Vector2(395, 278)
	var closed := Vector2(315, 148)
	var stacked := Vector2(374, 357)
	# size, need, fill, expected rect, docks at the bottom (1B)
	var cases: Array[Array] = [
		[Vector2(875, 971), trade, true, Rect2(157.5, 393.0, 560, 562.0), true],
		[Vector2(875, 971), closed, false, Rect2(157.5, 807.0, 560, 148), true],
		[Vector2(820, 910), trade, true, Rect2(130, 368.9, 560, 525.1), true],
		[Vector2(820, 910), closed, false, Rect2(130, 746.0, 560, 148), true],
		[Vector2(411, 731), stacked, true, Rect2(16, 189.4, 379, 525.6), true],
		[Vector2(360, 640), Vector2(328, 357), true, Rect2(16, 167.0, 328, 457.0), true],
		[Vector2(411, 880), stacked, true, Rect2(16, 411, 379, 453), false],
		[Vector2(411, 731), closed, false, Rect2(16, 489, 379, 148), false],
		[Vector2(898, 395), trade, true, Rect2(395, 16, 487, 363), false],
		[Vector2(917, 825), trade, true, Rect2(178.5, 16, 560, 339.1), false],
		[Vector2(1280, 720), trade, true, Rect2(720, 16, 544, 688), false],
	]
	for c: Array in cases:
		var s: Vector2 = c[0]
		var need: Vector2 = c[1]
		var fill: bool = c[2]
		var docked: bool = c[4]
		var play := Rect2(Vector2(8, 8), s - Vector2(16, 16))
		var board := Rect2(play.position, Vector2.ONE * Main.board_side_for(play.size))
		var banner := BoardView.banner_rect_in(board)
		var r := Main.overlay_rect_for(play, board, banner, need, fill)
		var tag := "%s need %s fill %s" % [s, need, fill]
		check(_near(r, c[3]), "%s placed at %s (got %s)" % [tag, c[3], r])
		check(play.encloses(r) and r.size.x >= need.x and r.size.y >= need.y, "%s inside the play area at its need" % tag)
		check_eq(Main.docks_at_bottom(play, board, need), docked, "%s docks at the bottom" % tag)
		check_eq(r.intersects(banner), fill and docked, "%s over the banner only when docked open" % tag)
		if docked:
			check(absf(r.end.y - (play.end.y - pad)) <= 0.5, "%s sits on the play bottom" % tag)
		if docked and fill:
			check(absf(r.position.y - (banner.position.y + pad)) <= 0.5, "%s opens from the banner top" % tag)
	done()


## Q22 1B through Main at the unfolded Fold sizes (outside the tree: the overlay's cached minimum
## size, not device evidence; the build/ in-tree probe is): Action's open card docks from the
## banner's top to the play bottom and still fits (the named banner exception); collapsed it sits at
## the play bottom clear of the banner; at 411x880 the open card stays in the free band.
func test_main_overlay_docks_bottom_fold() -> void:
	var pad := UiStyle.num("screen_margin", 8.0)
	for s: Vector2 in [Vector2(875, 971), Vector2(820, 910), Vector2(411, 880)]:
		var main := _phone_main(s)
		main.controller.dice.force(1, 2)
		main.press_die()
		check(main.press_slot(&"action") and main.sections_open(), "Action opens Holdings at %s" % s)
		main._update_layout()
		var play := main._play_rect()
		var board := Rect2(play.position, Vector2.ONE * Main.board_side_for(play.size))
		var banner := BoardView.banner_rect_in(board)
		var fold := s.x > 600.0
		var r := Rect2(main._overlay.position, main._overlay.size)
		check(main.overlay_fits(), "open card fits at %s" % s)
		check_eq(r.intersects(banner), fold, "open card over the banner only when docked at %s" % s)
		if fold:
			check(absf(r.position.y - (banner.position.y + pad)) <= 0.5 and absf(r.end.y - (play.end.y - pad)) <= 0.5,
					"open card from the banner top to the play bottom at %s (%s)" % [s, r])
		main.toggle_tab(main._section)
		main._update_layout()
		r = Rect2(main._overlay.position, main._overlay.size)
		check(not main.sections_open() and main.overlay_fits(), "collapsed card fits at %s" % s)
		check(not r.intersects(banner), "collapsed card clear of the banner at %s" % s)
		if fold:
			check(absf(r.end.y - (play.end.y - pad)) <= 0.5, "collapsed card on the play bottom at %s (%s)" % [s, r])
		main.free()
	done()


## Q22 Fold (Bug 2) in the Trade section: "to" keeps one line and its text width (picker_row_width
## counts it), the empty problem line takes no room ("Pick two different ..." still shows), and at
## 360x640 every freshly built body row, with the seat holding every deed mortgaged (the longest:
## the water utility), fits the overlay's content width, so the Trade card keeps the play width.
func test_trade_panel_rows_fit_narrow() -> void:
	var main := _phone_main(Vector2(360, 640))
	var tc := main.controller
	for i in tc.board.spaces.size():
		var deed := tc.board.deed_at(i)
		if deed != null:
			deed.owner = 0
			deed.is_mortgaged = true
	var tp := main._trade_panel
	tp.refresh()
	var to_label := tp._pickers.get_child(1) as Label
	var to_w := to_label.get_theme_font("font").get_string_size("to", HORIZONTAL_ALIGNMENT_LEFT, -1,
			to_label.get_theme_font_size("font_size")).x
	check_eq(to_label.autowrap_mode, TextServer.AUTOWRAP_OFF, "'to' does not wrap")
	check(to_label.get_combined_minimum_size().x + 0.5 >= to_w,
			"'to' keeps its text width (%.1f >= %.1f)" % [to_label.get_combined_minimum_size().x, to_w])
	check(tp.picker_row_width() + 0.5 >= tp._from_picker.get_combined_minimum_size().x
			+ tp._to_picker.get_combined_minimum_size().x + to_w, "picker row counts the 'to' text")
	check(not tp._problem.visible, "empty problem line takes no room")
	tp._new_draft(0, 0)
	check(tp._problem.visible and tp._problem.text.begins_with("Pick two different"), "same seat twice: problem shown")
	tp._new_draft(0, 1)
	check(not tp._problem.visible, "a fresh draft hides the problem line again")
	var styles := main._overlay.get_theme_stylebox("panel").get_minimum_size().x \
			+ main._section_holder.get_theme_stylebox("panel").get_minimum_size().x
	var room := main._play_rect().size.x - 2.0 * UiStyle.num("screen_margin", 8.0)
	var water := false
	for row: Control in tp._body.get_children():
		var w := row.get_combined_minimum_size().x + styles
		var text := String(row.get("text")) if row is Button or row is Label else row.get_class()
		check(w <= room, "'%s' fits 360x640 (%.1f <= %.1f)" % [text, w, room])
		water = water or (text.begins_with("Aquaeductus") and text.ends_with("(mortgaged)"))
	check(water, "the mortgaged water utility is listed")
	check(not _inside_scroll(tp._actions), "Propose / Clear stay pinned outside the scroll")
	main.free()
	done()


## Q22 Bug 3 (truncate-to-reserve): each shown line's toast, placed, lies inside the banner
## reservation at phone, landscape and unfolded sizes, the long card line too, and every
## data/cards.json line ("Mission Brief: " + text) at 411x880 and 360x640; a line too long for it
## takes the whole reservation and shows fewer lines than it wraps to. The roll line keeps its Q21
## compact caps at 411x880.
func test_banner_toast_clamped_to_reserve() -> void:
	var sweep: Array[String] = [ROLL_LINE, CARD_LINE]
	var cards := JsonData.load_json("res://data/cards.json")
	for deck: Variant in cards.values():
		if deck is Array:
			for card: Dictionary in deck:
				sweep.append("Mission Brief: " + String(card["text"]))
	for s: Vector2 in [Vector2(411, 880), Vector2(360, 640), Vector2(898, 395), Vector2(917, 825)]:
		var main := _toast_main(s, ROLL_LINE)
		var reserve := main._board_view.banner_rect()
		# Trimmed, the label's minimum height is 1 px: in the tree it must fill the toast, not shrink.
		check((main._banner._label.size_flags_vertical & Control.SIZE_FILL) != 0, "banner text fills the toast at %s" % s)
		if s == Vector2(411, 880):
			var side := main._board_view.size.x
			var t := main._banner.size
			check(t.y <= 0.18 * side and t.x * t.y <= 0.12 * side * side, "roll line keeps its compact caps (%s)" % t)
		var texts: Array[String] = [ROLL_LINE, CARD_LINE]
		if s.y > s.x:
			texts = sweep
		var cut := 0
		for text in texts:
			main._banner.push(text)
			main._banner.dismiss()
			var b := Rect2(main._banner.position, main._banner.size)
			check(reserve.grow(1.0).encloses(b), "'%s' toast inside the reservation at %s (%s)" % [text.left(28), s, b])
			var lines := _banner_lines(main._banner._label)
			if lines.x < lines.y:
				cut += 1
				check(b.is_equal_approx(reserve), "a cut line takes the whole reservation at %s" % s)
		if s.y > s.x:
			check(cut > 0, "long card lines are cut to the reservation at %s (%d of %d)" % [s, cut, texts.size()])
		main.free()
	done()
