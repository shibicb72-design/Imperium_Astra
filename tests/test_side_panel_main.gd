extends TestCase
## P5 SIDE_PANEL_A2: Main wires the A1 side panel into the match screen. The shared pure layout
## (Main.layout_rects: the board, the band before the carve, the panel's strip at the play area's far
## edge and the floats' play less the strip) pinned in a table worked out by hand from data/ui.json
## (screen_margin 8, side_strip_pad 4, side_strip_full_keep_h 250 / side_strip_full_keep_w 400,
## side_dock_min_h 436) and the card minimums; the strip clear of the board, banner, die and both
## floats; the compact cash text (SeatCard.short_money_text); and, through Main outside the tree, the
## panel's place and structure, its rect clear of the board and the floats in the gate states,
## GAME_OVER hiding it with the strip kept, its values queued behind the board's motion and text
## contrast on the tinted cards in both packs. Off-tree geometry only: the live rects are the build/
## in-tree probe's (SIDE_PANEL_A2 report).

const M := SidePanel.Mode
const S := MatchGate.State
const ThemeTests := preload("res://tests/test_theme.gd")
const SEATS: Array[int] = [2, 3, 4, 5, 6]
## Full-card minimum per pack (tests/test_side_panel.gd FULL_MIN); compact 50 x 50 in both.
const FULL_MIN := {"imperium_astra": Vector2(150, 94), "astra_alt": Vector2(139, 94)}
## Overlay needs pinned at test_ui.gd:525-527 (trade, the collapsed card, stacked-picker Trade) and the
## turn panel heights (one / two button columns) of test_match_gate.gd:561.
const NEEDS: Array[Vector2] = [Vector2(395, 278), Vector2(315, 148), Vector2(374, 357)]
const PANEL_H_ONE := 236.0
const PANEL_H_TWO := 174.0
## The Main-level sizes and seat counts (setup offers 2-4; 6 is the rules maximum).
const MAIN_SIZES: Array[Vector2] = [Vector2(411, 880), Vector2(411, 731), Vector2(360, 640), Vector2(898, 395),
	Vector2(875, 971), Vector2(917, 825)]
const MAIN_SEATS: Array[int] = [2, 3, 4, 6]


func teardown() -> void:
	UiStyle.reset_theme()


## Seat 1 a person, the rest bots, named by the active pack (as the setup screen names them).
func _pack_game(seats: int) -> TurnController:
	var content := UiStyle.content_overlay()
	return GameSetup.new_game(1234, GameSetup.seats(1, seats - 1, content), content)


## Main at `s` (test_ui.gd _seats_main): outside the tree, laid out and refreshed at that size.
func _main(s: Vector2, tc: TurnController) -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = tc
	main.start(null)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_resize(main, s)
	return main


## Containers do not lay out outside the tree (test_match_gate.gd:18): the board view is put where
## the box would put it (the layout's square at the play area's top-left), then Main lays out again.
func _resize(main: Main, s: Vector2) -> void:
	main.size = s
	main._update_layout()
	var board: Rect2 = main._layout()["board"]
	main._board_view.size = board.size
	main._board_view.position = board.position - main._margin.position - main._box.position
	main._refresh()


## Every Control under `node` (recursive).
func _controls(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in node.get_children():
		if c is Control:
			out.append(c)
		out.append_array(_controls(c))
	return out


func _rect(c: Control) -> Rect2:
	return Rect2(c.position, c.size)


func _at_least(size: Vector2, least: Vector2) -> bool:
	return size.x + 0.001 >= least.x and size.y + 0.001 >= least.y


# --- Main.layout_rects ------------------------------------------------------------------------

## Per play rect: its board, its band before the carve, the compact strip, the full strip (Rect2()
## where none) and the seat counts that get full cards. Worked out by hand: B = the play's long side
## less the board side (full short side); FULL depth = full minimum across + 2 x 4 (row 94 + 8 = 102;
## column 150 / 139 + 8 = 158 / 147), COMPACT depth = 50 + 8 = 58. FULL where B >= FULL, B - FULL -
## 2 x 8 >= 250 (portrait) / 400 (landscape) and the strip less its pad holds full cards (387 x 94:
## two of 191, three of 126 < 139). The board shrinks only where B < 58 (to the long side less 58) and,
## in portrait with the returned play still portrait, where the open dock (play bottom less the banner
## top, 0.438909 of the board side below it, less 2 x 8) would be under 436: only 360x640 here
## (574 - 158.98 - 16 = 399.0, so the board goes 344 -> 259: 574 - 113.68 - 16 = 436.3; 260 gives 435.9).
## Docks at the other portrait sizes: 411x880 572.6 (2 seats) / 616.6, 411x731 467.6, 875x971 504.0,
## 820x910 467.1, the inset phone 532.6 / 576.6.
func _layout_table() -> Array[Array]:
	return [
		# label, play, board, band, compact strip, full strip, seat counts with full cards
		["411x880", Rect2(8, 8, 395, 864), Rect2(8, 8, 395, 395), Rect2(8, 403, 395, 469),
			Rect2(8, 814, 395, 58), Rect2(8, 770, 395, 102), [2]],  # B 469: 469 - 102 - 16 = 351
		["411x731", Rect2(8, 8, 395, 715), Rect2(8, 8, 395, 395), Rect2(8, 403, 395, 320),
			Rect2(8, 665, 395, 58), Rect2(), []],  # B 320: 320 - 102 - 16 = 202 < 250
		["360x640", Rect2(8, 8, 344, 624), Rect2(8, 8, 259, 259), Rect2(8, 267, 344, 365),
			Rect2(8, 574, 344, 58), Rect2(), []],  # B 280: 162 < 250; the dock rule: board 344 -> 259
		["875x971", Rect2(8, 8, 859, 955), Rect2(8, 8, 859, 859), Rect2(8, 867, 859, 96),
			Rect2(8, 905, 859, 58), Rect2(), []],  # B 96 < 102
		["820x910", Rect2(8, 8, 804, 894), Rect2(8, 8, 804, 804), Rect2(8, 812, 804, 90),
			Rect2(8, 844, 804, 58), Rect2(), []],  # B 90 < 102
		["898x395", Rect2(8, 8, 882, 379), Rect2(8, 8, 379, 379), Rect2(387, 8, 503, 379),
			Rect2(832, 8, 58, 379), Rect2(), []],  # B 503: 503 - 158 / 147 - 16 = 329 / 340 < 400
		["917x825", Rect2(8, 8, 901, 809), Rect2(8, 8, 809, 809), Rect2(817, 8, 92, 809),
			Rect2(851, 8, 58, 809), Rect2(), []],  # B 92 < 147
		["1280x720", Rect2(8, 8, 1264, 704), Rect2(8, 8, 704, 704), Rect2(712, 8, 560, 704),
			Rect2(1214, 8, 58, 704), Rect2(), []],  # B 560: 560 - 158 / 147 - 16 = 386 / 397 < 400
		# 411x880 with status and navigation bars (insets 0, 24, 0, 16): B 429, 429 - 102 - 16 = 311.
		["411x880 insets", Rect2(8, 32, 395, 824), Rect2(8, 32, 395, 395), Rect2(8, 427, 395, 429),
			Rect2(8, 798, 395, 58), Rect2(8, 754, 395, 102), [2]],
		# Near-square windows, B 40 < 58: the board gives up 18 (484 -> 466) and the returned play reads
		# as the other orientation (landscape 540x500: play 466 x 484; portrait 500x540: 484 x 466, so
		# no bottom dock in it and no dock rule).
		["540x500", Rect2(8, 8, 524, 484), Rect2(8, 8, 466, 466), Rect2(474, 8, 58, 484),
			Rect2(474, 8, 58, 484), Rect2(), []],
		["500x540", Rect2(8, 8, 484, 524), Rect2(8, 8, 466, 466), Rect2(8, 474, 484, 58),
			Rect2(8, 474, 484, 58), Rect2(), []],
	]


## The pinned table in both packs: board, band, strip, its depth T and the card mode; the board
## square at the play's top-left; the strip clear of the board, its banner and die and of the turn
## panel and overlay rects the helpers give in the returned play (pinned needs, both panel heights,
## with and without the live die); every card at least its mode's minimum, inside the strip less pad.
func test_layout_rects_pinned() -> void:
	var cases := 0
	for pack in UiStyle.theme_packs():
		var id := String(pack["id"])
		check(UiStyle.set_theme(id) and FULL_MIN.has(id), "%s: set_theme, full minimum pinned" % id)
		cases += _check_layout_table(id)
	check_eq(cases, 2 * 11 * SEATS.size(), "every case ran")
	done()


func _check_layout_table(id: String) -> int:
	var pad := UiStyle.num("side_strip_pad", 0.0)
	check_eq(pad, 4.0, "side_strip_pad (the table is worked out with 4)")
	var bv := BoardView.new()
	bv.setup(GameSetup.new_game(1234))
	var cases := 0
	for n in SEATS:
		var panel := SidePanel.new()
		panel.setup(_pack_game(n))
		var fm := panel.full_min_size()
		var cm := panel.compact_min_size()
		panel.free()
		check(fm == FULL_MIN[id] and cm == Vector2(50, 50), "%s: %d-seat card minimums %s / %s" % [id, n, fm, cm])
		for row: Array in _layout_table():
			var tag := "%s %s %d seats" % [id, row[0], n]
			var play: Rect2 = row[1]
			var portrait := play.size.y > play.size.x
			var full := n in (row[6] as Array)
			var strip: Rect2 = row[5] if full else row[4]
			var lay := Main.layout_rects(play, n, fm, cm)
			check_eq(lay.keys().size(), 4, "%s: keys board, band, strip, play" % tag)
			var board: Rect2 = lay["board"]
			var got_strip: Rect2 = lay["strip"]
			var rest: Rect2 = lay["play"]
			check(board.is_equal_approx(row[2]), "%s: board %s (got %s)" % [tag, row[2], board])
			check((lay["band"] as Rect2).is_equal_approx(row[3]), "%s: band %s (got %s)" % [tag, row[3], lay["band"]])
			check(got_strip.is_equal_approx(strip), "%s: strip %s (got %s)" % [tag, strip, got_strip])
			var t := strip.size.y if portrait else strip.size.x
			check_eq(t, (fm.y if portrait else fm.x) + 2.0 * pad if full else 58.0, "%s: strip depth T" % tag)
			var less := Rect2(play.position, play.size - (Vector2(0, t) if portrait else Vector2(t, 0)))
			check(rest.is_equal_approx(less), "%s: play less the strip %s (got %s)" % [tag, less, rest])
			check(board.position == play.position and board.size.x == board.size.y, "%s: board square at the play's top-left" % tag)
			var banner := BoardView.banner_rect_in(board)
			bv.size = board.size
			var die := Rect2(board.position + bv.die_hit_rect().position, bv.die_hit_rect().size)
			for r: Rect2 in [board, banner, die]:
				check(not got_strip.intersects(r), "%s: strip clear of %s" % [tag, r])
			for avoid: Rect2 in [Rect2(), die]:
				var tp := TurnPanel.rect_for(rest, board, banner, PANEL_H_ONE, PANEL_H_TWO, avoid)
				check(rest.encloses(tp) and not tp.intersects(got_strip), "%s: turn panel %s in the play, clear of the strip" % [tag, tp])
			for need in NEEDS:
				for fill: bool in [true, false]:
					var r := Main.overlay_rect_for(rest, board, banner, need, fill)
					check(rest.encloses(r) and not r.intersects(got_strip), "%s: overlay %s (need %s) clear of the strip" % [tag, r, need])
			var cards := SidePanel.layout_for(got_strip.grow(-pad), n, fm, cm)
			check_eq(cards.mode, M.FULL if full else M.COMPACT, "%s: card mode" % tag)
			check_eq(cards.cards.size(), n, "%s: a card per seat" % tag)
			for c: Rect2 in cards.cards:
				check(_at_least(c.size, fm if full else cm) and got_strip.grow(-pad).encloses(c),
						"%s: card %s at least its minimum, inside the strip less its pad" % [tag, c])
			cases += 1
	bv.free()
	return cases


## Edges (short windows, none of the probe sizes): where the strip cannot hold every seat's compact
## card it is not carved (the board-first layout); the dock rule takes whatever board the dock needs
## (Shibi Oct 30 2026; a floor is OPEN_QUESTIONS Q38), but where even no board would leave the dock
## side_dock_min_h it shrinks nothing (a zero board has no die to roll).
func test_layout_rects_edges() -> void:
	var fm := Vector2(150, 94)
	var cm := Vector2(50, 50)
	var play := Rect2(8, 8, 284, 464)  # 300x480: six compact cards need 6 x 50 + 5 x 4 = 320 > 276
	var lay := Main.layout_rects(play, 6, fm, cm)
	check_eq(lay["strip"], Rect2(), "no strip for six cards across 276")
	check_eq(lay["play"], play, "the floats keep the whole play area")
	check_eq(lay["board"], Rect2(8, 8, 284, 284), "the board keeps the full short side")
	check_eq(lay["band"], Rect2(8, 292, 284, 180), "the band after it")
	# Two cards fit (136 each); the dock below a strip at 414 could reach 414 - 8 - 16 = 390 < 436 at
	# best, so the board keeps its side.
	var two := Main.layout_rects(play, 2, fm, cm)
	check_eq(two["strip"], Rect2(8, 414, 284, 58), "two compact cards fit the same strip")
	check_eq(two["board"], Rect2(8, 8, 284, 284), "no board size gives the dock 436: no shrink")
	# 400x540: the dock under the strip (top 474) holds 436 only below a board of at most
	# (474 - 16 - 436 - 8) / 0.438909 = 31.9: the board gives up the rest, as the rule says.
	var short := Main.layout_rects(Rect2(8, 8, 384, 524), 2, fm, cm)
	check_eq(short["strip"], Rect2(8, 474, 384, 58), "400x540: compact strip (B 140)")
	check_eq(short["board"], Rect2(8, 8, 31, 31), "400x540: the board gives the dock what it needs")
	var top := BoardView.banner_rect_in(short["board"]).position.y
	check(474.0 - top - 16.0 >= 436.0, "400x540: dock %.1f" % (474.0 - top - 16.0))
	done()


## The new data/ui.json keys (A2 brief values, `_placeholder`, described in side_panel_doc) and every
## side_* key main.gd reads (UiStyle.num falls back silently, so a renamed key would pass unseen).
func test_strip_keys_in_ui_json() -> void:
	var d := UiStyle.data()
	var keys := {"side_strip_pad": 4.0, "side_strip_full_keep_h": 250.0, "side_strip_full_keep_w": 400.0,
		"side_dock_min_h": 436.0}
	var doc := String(d.get("side_panel_doc", ""))
	for k: String in keys:
		check(d.has(k) and float(d[k]) == float(keys[k]), "data/ui.json %s = %s" % [k, keys[k]])
		check(doc.contains(k), "side_panel_doc describes %s" % k)
	check(doc.contains("_placeholder"), "side_panel_doc marks the placeholder picks")
	check(not doc.contains("Main places it from A2"), "side_panel_doc no longer says A2 is to come")
	var src := FileAccess.get_file_as_string("res://scripts/ui/main.gd")
	var re := RegEx.create_from_string("\"(side_[a-z_]+)\"")
	var read := 0
	for m in re.search_all(src):
		read += 1
		check(d.has(m.get_string(1)), "main.gd reads %s, which data/ui.json has" % m.get_string(1))
	check(read >= keys.size(), "main.gd reads the strip keys by name (%d reads)" % read)
	done()


# --- Compact cash ------------------------------------------------------------------------------

## Shibi Oct 29 2026 7:20 PM: three significant digits, truncated toward zero, "k" below 1000000 and
## "M" from it, trailing zeros after the point dropped; money_text up to side_money_sample. Each figure
## measured with the card's own label font at font_small fits side_card_min_size (50).
func test_short_money_text_pinned() -> void:
	var pinned := [[10000, "$10k"], [12500, "$12.5k"], [99999, "$99.9k"], [100000, "$100k"], [125000, "$125k"],
		[999999, "$999k"], [1000000, "$1M"], [1250000, "$1.25M"],
		[10001, "$10k"], [12599, "$12.5k"], [99950, "$99.9k"], [1999999, "$1.99M"]]  # truncated, never rounded up
	var panel := SidePanel.new()
	panel.setup(GameSetup.new_game(1234))
	var ls := panel.cards[0].cash_label.label_settings
	check_eq(ls.font_size, UiStyle.font("small"), "the card figure is at font_small")
	var lo := UiStyle.num("side_card_min_size", 0.0)
	for p: Array in pinned:
		var text := SidePanel.SeatCard.short_money_text(int(p[0]))
		check_eq(text, String(p[1]), "short_money_text(%d)" % p[0])
		var w := ls.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size).x
		check(w <= lo, "'%s' is %.0f wide, at most %.0f (card font %s %d)" % [text, w, lo, ls.font.get_font_name(), ls.font_size])
	for v: int in [0, 1500, 9999]:
		check_eq(SidePanel.SeatCard.short_money_text(v), SidePanel.SeatCard.money_text(v), "%d keeps money_text" % v)
	panel.free()
	done()


## A card holding 12500 shows "$12.5k" right after place_in makes it compact and "$12500" right after
## place_in makes it full again, with no hook call between; a layout pass that keeps the mode leaves
## the figure's text alone (SIDE_PANEL_B_ANIM's tick owns it between hooks); the hook's stored values
## never change.
func test_compact_switch_rerenders_cash() -> void:
	var panel := SidePanel.new()
	panel.setup(GameSetup.new_game(1234))
	var fm := panel.full_min_size()
	var gap := UiStyle.num("side_card_gap", 4.0)
	var full_strip := Rect2(Vector2.ZERO, Vector2(2.0 * fm.x + gap, fm.y))
	var compact_strip := Rect2(Vector2.ZERO, Vector2(2.0 * 50.0 + gap, 50.0))
	check(panel.place_in(full_strip).has_area() and panel.mode == M.FULL, "full cards")
	var c := panel.cards[0]
	c.set_cash(12500, 11000)
	check_eq(c.cash_label.text, "$12500", "a full card keeps money_text")
	check_eq(c.cash_text(12500), "$12500", "cash_text follows the full mode")
	check(panel.place_in(compact_strip).has_area() and panel.mode == M.COMPACT, "compact cards")
	check_eq(c.cash_label.text, "$12.5k", "compact right after place_in, no hook call")
	check_eq(c.cash_text(12500), "$12.5k", "cash_text follows the compact mode")
	var font := c.cash_label.label_settings.font
	var fs := c.cash_label.label_settings.font_size
	var cr := _rect(c.cash_label)
	check(cr.size.x + 0.5 >= font.get_string_size("$12.5k", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			and Rect2(Vector2.ZERO, c.size).encloses(cr), "the short figure shows whole on the card (%s)" % cr)
	c.cash_label.text = "$12.3k"  # a tick in flight
	panel.place_in(compact_strip)
	check_eq(c.cash_label.text, "$12.3k", "same mode: the text is left alone")
	check(panel.place_in(full_strip).has_area() and panel.mode == M.FULL, "full again")
	check_eq(c.cash_label.text, "$12500", "full right after place_in, no hook call")
	check(c.last_cash == 12500 and c.last_cash_delta == 11000, "stored hook values unchanged")
	panel.free()
	done()


## N-11 (Shibi Oct 30 2026): a Pilot full card at its minimum (139 wide) with worth 12500 shows
## "worth $12.5k" inside the card ("worth $12500" ran about 4 past it).
func test_pilot_full_card_short_worth() -> void:
	check(UiStyle.set_theme("astra_alt"), "set_theme astra_alt")
	var panel := SidePanel.new()
	panel.setup(_pack_game(2))
	var fm := panel.full_min_size()
	check_eq(fm, FULL_MIN["astra_alt"], "Pilot full minimum")
	panel.place_in(Rect2(Vector2.ZERO, Vector2(2.0 * fm.x + UiStyle.num("side_card_gap", 4.0), fm.y)))
	var c := panel.cards[0]
	check(panel.mode == M.FULL and c.size == fm, "a full card at its minimum (%s)" % c.size)
	c.set_net_worth(12500)
	check_eq("%s %s" % [c.worth_caption.text, c.worth_label.text], "worth $12.5k", "short worth on the full card")
	var ls := c.worth_label.label_settings
	var r := Rect2(c.details.position + c.worth_label.position, c.worth_label.size)
	check(r.size.x + 0.5 >= ls.font.get_string_size(c.worth_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size).x,
			"the figure shows whole")
	check(Rect2(Vector2.ZERO, c.size).encloses(r), "inside the card (%s in %s)" % [r, c.size])
	c.set_net_worth(9999)
	check_eq(c.worth_label.text, "$9999", "up to side_money_sample the worth keeps money_text")
	panel.free()
	done()


# --- Through Main ------------------------------------------------------------------------------

## The panel is a direct child of Main (not in the margin / board box), before the overlay and the
## turn panel; every node ignores the mouse; set up once: the same SeatCards through refresh, resize
## and the full / compact switch; animate follows the board's.
func test_main_panel_structure() -> void:
	var main := _main(Vector2(411, 880), GameSetup.new_game(1234, GameSetup.seats(1, 1)))
	var panel := main._side_panel
	check(panel != null and panel.get_parent() == main, "the side panel is a child of Main")
	check(not main._margin.is_ancestor_of(panel), "outside the margin and the board box")
	check(panel.get_index() < main._overlay.get_index() and main._overlay.get_index() < main._turn_panel.get_index(),
			"before the overlay and the turn panel")
	check_eq(panel.animate, main._board_view.animate, "animate set with the board's")
	for c: Control in [panel as Control] + _controls(panel):
		check_eq(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % c.name)
	var cards := panel.cards.duplicate()
	var children := panel.get_child_count()
	check(cards.size() == 2 and children == 2, "a card per seat")
	check_eq(panel.mode, M.FULL, "411x880, 2 seats: full cards")
	main.controller.dice.force(1, 3)
	main.press_die()
	_resize(main, Vector2(411, 731))
	check_eq(panel.mode, M.COMPACT, "411x731: compact cards")
	_resize(main, Vector2(411, 880))
	check_eq(panel.mode, M.FULL, "full again")
	check(panel.cards == cards and panel.get_child_count() == children, "the same cards, none added")
	for i in cards.size():
		check(panel.get_child(i) == cards[i], "card %d still in seat order" % i)
	main.free()
	done()


## Main in gate `state` with `seats` seats (seat 1 the person; animate off outside the tree):
## AWAIT_DIE_TAP at the start, BUY on Vesta Outpost (0 -> 3), END_TURN after buying it with Action
## open (the overlay), TRADE_ANSWER for the bot's offer to the person (the overlay).
func _main_in(state: int, seats: int) -> Main:
	var main := _main(MAIN_SIZES[0], GameSetup.new_game(1234, GameSetup.seats(1, seats - 1)))
	var tc := main.controller
	if state == S.BUY or state == S.END_TURN:
		tc.dice.force(1, 2)
		main.press_die()
		if state == S.END_TURN:
			main.press_slot(&"buy")
			main.press_slot(&"action")
	elif state == S.TRADE_ANSWER:
		var offer := Trade.propose(1, 0)
		offer.give_cash = 50
		tc.propose_trade(offer)
	main._refresh()
	return main


## In each gate state, seat count and size: the panel shows in its strip, its rect and cards clear of
## the board (the layout's square, which the board view takes), the turn panel and the overlay;
## overlay_fits() wherever the placed overlay holds its need. GAME_OVER hides it and keeps the strip.
func test_main_panel_clear_in_gate_states() -> void:
	var pad := UiStyle.num("side_strip_pad", 4.0)
	var states: Array[int] = [S.AWAIT_DIE_TAP, S.BUY, S.END_TURN, S.TRADE_ANSWER]
	for seats in MAIN_SEATS:
		for state in states:
			var main := _main_in(state, seats)
			check_eq(main.gate(), state, "%d seats: gate state %d" % [seats, state])
			check_eq(main._overlay.visible, state == S.END_TURN or state == S.TRADE_ANSWER, "%d seats state %d: overlay" % [seats, state])
			check_eq(main._turn_panel.visible, state == S.BUY, "%d seats state %d: turn panel" % [seats, state])
			for s in MAIN_SIZES:
				_resize(main, s)
				_check_main_panel(main, "%d seats state %d at %s" % [seats, state, s], pad)
			main.free()
		# Game over: the panel hides, the strip stays carved and empty (no reflow), here and after resizes.
		var over := _main_in(S.AWAIT_DIE_TAP, seats)
		var tc := over.controller
		var before: Dictionary = over._layout()
		var placed := _rect(over._side_panel)
		for i in range(1, seats):
			tc.players[i].is_bankrupt = true
		tc._check_winner()
		over._refresh()
		check_eq(over.gate(), S.GAME_OVER, "%d seats: game over" % seats)
		check(not over._side_panel.visible, "%d seats: game over hides the panel" % seats)
		check_eq(over._layout(), before, "%d seats: the strip stays carved, nothing reflows" % seats)
		check_eq(_rect(over._side_panel), placed, "%d seats: the hidden panel keeps its rect" % seats)
		for s in MAIN_SIZES:
			_resize(over, s)
			var lay: Dictionary = over._layout()
			var strip: Rect2 = lay["strip"]
			check(not over._side_panel.visible and strip.has_area(), "%d seats at %s: hidden, strip kept" % [seats, s])
			check(strip.grow(-pad).encloses(_rect(over._side_panel)), "%d seats at %s: still placed in its strip" % [seats, s])
			check(over._turn_panel.visible and not _rect(over._turn_panel).intersects(strip),
					"%d seats at %s: the winner panel clear of the strip" % [seats, s])
		over.free()
	done()


func _check_main_panel(main: Main, tag: String, pad: float) -> void:
	var lay: Dictionary = main._layout()
	var board: Rect2 = lay["board"]
	var strip: Rect2 = lay["strip"]
	var panel := main._side_panel
	var r := _rect(panel)
	check(panel.visible and r.has_area(), "%s: panel shown" % tag)
	check(strip.grow(-pad).encloses(r), "%s: panel %s inside its strip %s" % [tag, r, strip])
	check(not r.intersects(board), "%s: panel clear of the board" % tag)
	check_eq(main._board_view.custom_minimum_size, board.size, "%s: the board view takes the layout's square" % tag)
	var mins := panel.full_min_size() if panel.mode == M.FULL else panel.compact_min_size()
	for c in panel.cards:
		check(_at_least(c.size, mins) and Rect2(Vector2.ZERO, r.size).encloses(_rect(c)), "%s: card %s at least %s" % [tag, c.size, mins])
	if main._turn_panel.visible:
		check(not r.intersects(_rect(main._turn_panel)), "%s: panel clear of the turn panel %s" % [tag, _rect(main._turn_panel)])
	if main._overlay.visible:
		var o := _rect(main._overlay)
		check(not r.intersects(o), "%s: panel clear of the overlay %s" % [tag, o])
		if _at_least(o.size, main._overlay.get_combined_minimum_size()):
			check(main.overlay_fits(), "%s: overlay fits where it holds its need" % tag)


## Values change through _refresh only, behind the board's queued motion: with animate on, the card
## keeps the old cash while the dice, the hops and the tax fly play (and through another _refresh)
## and shows the new figure once advance() drains the queue; with animate off, at once. (Every
## _refresh queues one show_values, so a change arrives with its delta and repeats follow with 0.)
func test_main_panel_values_follow_the_board() -> void:
	var main := _main(Vector2(411, 880), GameSetup.new_game(1234, GameSetup.seats(2, 0)))
	var tc := main.controller
	var bv := main._board_view
	var cards := main._side_panel.cards
	check(not bv.animate, "outside the tree start() leaves animate off")
	tc.dice.force(1, 3)  # 0 -> 4, Imperial Levy: tax 200
	check(main.press_die(), "seat 1 rolls")
	check_eq(tc.players[0].cash, 1300, "the rules took the tax")
	check(cards[0].cash_label.text == "$1300" and cards[0].last_cash == 1300, "animate off: the card shows it at once")
	check(main.press_slot(&"end_turn"), "seat 1 ends the turn")
	bv.animate = true
	tc.dice.force(1, 3)
	check(main.press_die(), "seat 2 rolls")
	check(bv.is_animating() and tc.players[1].cash == 1300, "the board is moving; the rules took the tax")
	check(cards[1].cash_label.text == "$1500" and cards[1].last_cash == 1500, "animate on: the old cash while the board moves")
	main._refresh()
	check_eq(cards[1].cash_label.text, "$1500", "still the old cash after another _refresh")
	bv.advance(10.0)
	check(not bv.is_animating(), "the queue drained")
	check(cards[1].cash_label.text == "$1300" and cards[1].last_cash == 1300, "the new cash once the board settles")
	check_eq(cards[0].cash_label.text, "$1300", "the other card unchanged")
	main.free()
	done()


## Both packs, six seats through Main: every text on each tinted card (name, figures, captions,
## badges) against the card's background at AAA (test_theme.gd:145), the disc digit on the seat
## colour at AA, for all six seat colours.
func test_main_panel_contrast_both_packs() -> void:
	for pack in UiStyle.theme_packs():
		var id := String(pack["id"])
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var main := _main(Vector2(1280, 720), _pack_game(6))
		var seen := {}
		for c in main._side_panel.cards:
			var seat := main.controller.players[c.player_id].color
			seen[seat.to_html(false)] = true
			var bg := (c.background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
			for l: Control in _controls(c):
				if l is Label:
					var fc := (l as Label).label_settings.font_color
					check(ThemeTests.contrast(fc, bg) >= 7.0, "%s: %s on seat #%s card (%.2f)" % [id, l.name,
							seat.to_html(false), ThemeTests.contrast(fc, bg)])
			check(ThemeTests.contrast(c.token.disc_color(), seat) >= 4.5, "%s: disc digit on #%s" % [id, seat.to_html(false)])
		check_eq(seen.size(), 6, "%s: six seat colours" % id)
		check_eq(main._side_panel.cards[0].name_label.text, main.controller.players[0].display_name, "%s: pack seat names" % id)
		main.free()
	done()
