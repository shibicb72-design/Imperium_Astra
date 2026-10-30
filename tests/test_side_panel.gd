extends TestCase
## P5 SIDE_PANEL_A1: the per-seat side panel (scripts/ui/side_panel.gd) and NetWorth
## (scripts/core/net_worth.gd); layout and state only, no animation (Main: tests/test_side_panel_main.gd).
## seat_view and NetWorth on rules-built fixtures against literal numbers worked out by hand from
## data/board.json and data/rules.json; the active seat across end_turn; the cards inside their own
## strip (SidePanel.layout_for / rect_for: one row or one column, full, compact or hidden, never below
## side_card_min_size), pinned in a table; card sizes from font string widths plus the data/ui.json
## side_* sizes; the hook contract (instant and exact, delta 0 on the first call and on repeats, the
## same nodes across refresh, resize and full / compact switches); structure (mouse filters,
## fx_layer, glow_frame, persistent badge nodes) and text contrast on the tinted cards in both packs.

const P := TurnController.Phase
const M := SidePanel.Mode
const ThemeTests := preload("res://tests/test_theme.gd")
## The committed probe sizes (test_ui.gd:530-540, test_match_gate.gd:500-501) and seat counts
## (data/ui.json setup_seat_counts, 5, and the rules maximum 6).
const SIZES: Array[Vector2] = [Vector2(411, 880), Vector2(411, 731), Vector2(360, 640), Vector2(875, 971),
	Vector2(820, 910), Vector2(898, 395), Vector2(917, 825), Vector2(1280, 720)]
const SEATS: Array[int] = [2, 3, 4, 5, 6]
## Every data/ui.json key the panel reads.
const SIDE_KEYS: Array[String] = ["side_card_min_size", "side_card_max_width", "side_card_max_height",
	"side_card_gap", "side_active_border_width", "side_card_padding", "side_token_size",
	"side_token_piece_min_size", "side_line_gap", "side_column_gap", "side_tint_alpha", "side_money_sample"]
## Full-card minimum per pack, measured at tip with the engine label font (Open Sans SemiBold 14 px,
## line 20, "$9999" 40): the longest seat name sets the width for "Commander N" (96), the worth line
## "worth $9999" (85) for "Pilot N" (43). The compact minimum is 50 x 50 in both.
const FULL_MIN := {"imperium_astra": Vector2(150, 94), "astra_alt": Vector2(139, 94)}


func teardown() -> void:
	UiStyle.reset_theme()


## Seat 1 a person, the rest bots (the setup default mix, as test_ui.gd _seats_main).
func _game(seats: int) -> TurnController:
	var tc := GameSetup.new_game(1234, GameSetup.seats(1, seats - 1))
	check_eq(tc.players.size(), seats, "fixture has %d seats" % seats)
	return tc


## As _game, with the seats named by the active pack's content overlay (as the setup screen names them).
func _pack_game(seats: int) -> TurnController:
	var content := UiStyle.content_overlay()
	var tc := GameSetup.new_game(1234, GameSetup.seats(1, seats - 1, content), content)
	check_eq(tc.players.size(), seats, "fixture has %d seats" % seats)
	return tc


func _panel(tc: TurnController) -> SidePanel:
	var panel := SidePanel.new()
	panel.setup(tc)
	return panel


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


## The free band after the board, less screen_margin: Main.layout_rects's band (the one function
## Main's strip carve uses), below the board in portrait, right of it otherwise, before the strip is
## carved. `insets` as DisplayScale.safe_insets (left, top, right, bottom). Two seats and the
## Commander minimums: the band follows them only where the dock rule moves the board, and at these
## sizes that rule (360x640) moves it the same for every seat count and pack.
func _band(s: Vector2, insets: Vector4 = Vector4.ZERO) -> Rect2:
	var m := UiStyle.num("screen_margin", 8.0)
	var origin := Vector2(insets.x + m, insets.y + m)
	var play := Rect2(origin, s - origin - Vector2(insets.z + m, insets.w + m))
	var band: Rect2 = Main.layout_rects(play, 2, Vector2(150, 94), Vector2(50, 50))["band"]
	return band.grow(-m)


## A strip `thickness` deep along the long side of `area`, at its top or left edge.
func _thin(area: Rect2, thickness: float) -> Rect2:
	if area.size.x > area.size.y:
		return Rect2(area.position, Vector2(area.size.x, thickness))
	return Rect2(area.position, Vector2(thickness, area.size.y))


## Ids of the active seats by the view-model, checked against the cards' active borders.
func _active_ids(tc: TurnController, panel: SidePanel) -> Array[int]:
	var out: Array[int] = []
	for p in tc.players:
		var on: bool = SidePanel.seat_view(tc, p)["active"]
		check_eq(panel.cards[p.id].glow_frame.visible, on, "card %d border follows seat_view" % p.id)
		if on:
			out.append(p.id)
	return out


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


# --- NetWorth and seat_view -------------------------------------------------------------------

## NetWorth.of, default definition (Shibi Oct 29 2026): cash + building sell-back + mortgage value
## of each unmortgaged deed. By hand: brown_1 / brown_2 list 60, mortgage 30, house 50
## (board.json:19, :21); gate_1 mortgage 100 (:23); light_blue_1 mortgage 50, house 50 (:24);
## utility_1 mortgage 75 (:30); building_sell_percent 50 (rules.json:17), so a house sells back for
## 25 and a hotel for 25 + 4 x 25 = 125 (building.gd:163-166). NetWorth reads these fields only, so
## the deed fixtures set them directly.
func test_net_worth_literals() -> void:
	var tc := _game(2)
	var p := tc.players[0]
	var q := tc.players[1]
	var cfg := tc.config
	check_eq(NetWorth.of(tc.board, p, cfg), 1500, "fresh seat: its cash")
	var brown_1 := tc.board.deed_at(1)
	brown_1.owner = p.id
	check_eq(NetWorth.of(tc.board, p, cfg), 1530, "cash 1500 + brown_1 mortgage value 30")
	brown_1.is_mortgaged = true
	check_eq(NetWorth.of(tc.board, p, cfg), 1500, "a mortgaged deed counts 0")
	brown_1.is_mortgaged = false
	var brown_2 := tc.board.deed_at(3)
	brown_2.owner = p.id
	brown_1.has_hotel = true
	brown_2.houses = 4
	tc.bank.hotels_remaining -= 1
	tc.bank.houses_remaining -= 4
	# 1500 + (30 + 125) + (30 + 4 x 25)
	check_eq(NetWorth.of(tc.board, p, cfg), 1785, "hotel and four houses on the full brown group")
	tc.board.deed_at(5).owner = q.id
	tc.board.deed_at(5).is_mortgaged = true
	tc.board.deed_at(12).owner = q.id
	tc.board.deed_at(6).owner = q.id
	tc.board.deed_at(6).houses = 2
	q.cash = 320
	# 320 + 0 (mortgaged gate) + 75 (utility) + 50 + 2 x 25 (light_blue_1 and its houses)
	check_eq(NetWorth.of(tc.board, q, cfg), 495, "mortgaged gate, utility and a built street")
	# Guard (passes at tip too): the default is the Bankruptcy.max_raisable sum.
	for pl in tc.players:
		check_eq(NetWorth.of(tc.board, pl, cfg), Bankruptcy.max_raisable(tc.board, pl, cfg),
				"seat %d: NetWorth.of == Bankruptcy.max_raisable" % pl.id)
	done()


## The consequences the Q-networth-definition row lists, through the real actions: a purchase lowers
## worth by list price - mortgage value, mortgaging leaves it, lifting the mortgage costs the 10%
## interest (Rules.unmortgage_cost rules.gd:57-58), a house costs its price - sell-back.
func test_net_worth_follows_the_rules() -> void:
	var tc := _game(2)
	var p := tc.players[0]
	var worth := func() -> int: return NetWorth.of(tc.board, p, tc.config)
	tc.dice.force(1, 2)  # 0 -> 3 brown_2, unclaimed: list 60, mortgage 30
	tc.roll()
	check_eq(tc.phase, P.AWAITING_BUY_DECISION, "offered brown_2")
	check_eq(worth.call(), 1500, "before the purchase")
	check(tc.buy(), "claimed")
	check_eq(worth.call(), 1470, "1440 cash + 30: a purchase costs 60 - 30")
	check(tc.mortgage(p.id, 3), "mortgaged")
	check_eq(worth.call(), 1470, "1470 cash + 0: mortgaging leaves it")
	check(tc.unmortgage(p.id, 3), "mortgage lifted")
	check_eq(worth.call(), 1467, "1437 cash + 30: lifting costs 30 + 3 interest")
	tc.board.deed_at(1).owner = p.id  # brown_1 completes the group
	check_eq(worth.call(), 1497, "1437 + 30 + 30")
	check(tc.build(p.id, 3), "one house on brown_2")
	check_eq(worth.call(), 1472, "1387 + 30 + 30 + 25: a house costs 50 - 25")
	done()


func test_seat_view_keys_and_fixtures() -> void:
	var tc := _game(2)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	var v := SidePanel.seat_view(tc, p0)
	check_eq(_sorted_keys(v), ["active", "badges", "cash", "color", "id", "name", "net_worth", "owned"], "view keys")
	check_eq(_sorted_keys(v["badges"]), ["bankrupt", "bot", "jail", "pardon"], "exactly the four badge keys")
	check_eq(v["id"], 0, "id")
	check_eq(v["name"], p0.display_name, "name")
	check_eq(v["color"], p0.color, "token colour")
	check_eq(v["cash"], 1500, "fresh cash")
	check_eq(v["owned"], 0, "fresh: owns nothing")
	check_eq(v["net_worth"], 1500, "fresh net worth")
	check_eq(v["active"], true, "seat 1 holds the turn")
	check_eq(v["badges"], {"jail": false, "bankrupt": false, "pardon": 0, "bot": false}, "fresh badges")
	var bot := SidePanel.seat_view(tc, p1)
	check_eq(bot["badges"]["bot"], true, "bot seat badge")
	check_eq(bot["active"], false, "seat 2 waits")
	# Jailed through the rules: 27 -> 30 Report to the Brig.
	p0.position = 27
	tc.dice.force(1, 2)
	tc.roll()
	check(p0.in_jail, "fixture: seat 1 is in the Brig")
	v = SidePanel.seat_view(tc, p0)
	check_eq(v["badges"]["jail"], true, "jail badge")
	check_eq(v["active"], true, "a jailed seat still holds its turn")
	check_eq(v["net_worth"], 1500, "jail changes no worth")
	# Pardon cards: the count, worth 0 each.
	check(tc.chance.move_to_top(&"ch_goojf"), "chance pardon found")
	p0.goojf_cards.append(tc.chance.draw())
	check_eq(SidePanel.seat_view(tc, p0)["badges"]["pardon"], 1, "one pardon card")
	check(tc.community_chest.move_to_top(&"cc_goojf"), "senate pardon found")
	p0.goojf_cards.append(tc.community_chest.draw())
	v = SidePanel.seat_view(tc, p0)
	check_eq(v["badges"]["pardon"], 2, "pardon card count")
	check_eq(v["net_worth"], 1500, "pardon cards count 0")
	# A mortgaged deed is still owned (the chips' "N deeds" count, main.gd:706-722) but worth 0.
	tc.board.deed_at(1).owner = p1.id
	tc.board.deed_at(1).is_mortgaged = true
	v = SidePanel.seat_view(tc, p1)
	check_eq(v["owned"], 1, "mortgaged deed counted as owned")
	check_eq(v["net_worth"], 1500, "mortgaged deed worth 0")
	# A hotel on the full brown group (worked out in test_net_worth_literals).
	tc.board.deed_at(1).is_mortgaged = false
	tc.board.deed_at(3).owner = p1.id
	tc.board.deed_at(1).has_hotel = true
	tc.board.deed_at(3).houses = 4
	v = SidePanel.seat_view(tc, p1)
	check_eq(v["owned"], 2, "two deeds")
	check_eq(v["net_worth"], 1785, "1500 + 155 + 130")
	done()


## Bankrupt through the rules (tc.declare_bankruptcy, as test_bankruptcy.gd:117), not by setting
## is_bankrupt (which would keep cash and deeds): badge on, worth 0, and not active although the
## seat stays current_player() until End Turn (turn_controller.gd:584-588).
func test_seat_view_bankrupt_through_rules() -> void:
	var tc := GameSetup.new_game(1234, GameSetup.seats(3, 0))
	var p1 := tc.players[1]
	tc.board.deed_at(1).owner = p1.id
	tc.board.deed_at(1).is_mortgaged = true
	check(tc.chance.move_to_top(&"ch_goojf"), "card found")
	p1.goojf_cards.append(tc.chance.draw())
	p1.cash = 50
	p1.position = 1
	tc.current_index = p1.id
	tc.dice.force(1, 2)  # 1 -> 4 Imperial Levy 200; could raise only 50 (the deed is mortgaged)
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "cannot pay the levy")
	var before := SidePanel.seat_view(tc, p1)
	check(before["active"], "the debtor still holds the turn")
	check_eq(before["net_worth"], 50, "cash 50 + mortgaged deed 0")
	check(tc.declare_bankruptcy(), "bankrupt to the Bank")
	check(tc.current_player() == p1, "the bankrupt seat stays current until End Turn")
	var v := SidePanel.seat_view(tc, p1)
	check_eq(v["badges"], {"jail": false, "bankrupt": true, "pardon": 0, "bot": false}, "bankrupt badge; pardon back to its deck")
	check_eq(v["active"], false, "a bankrupt seat is never active, even while current")
	check_eq(v["cash"], 0, "no cash left")
	check_eq(v["owned"], 0, "deeds back to the Bank")
	check_eq(v["net_worth"], 0, "bankrupt worth 0")
	done()


## Bankrupt to a creditor (Bankruptcy.settle_to_player): the debtor's view empties and the creditor's
## takes its cash and deed. By hand: 37 mortgage 175, 39 mortgage 200 with a hotel (house 200, so it
## sells back for 100 + 4 x 100 = 500; board.json:55, :57), brown_1 mortgage 30.
func test_seat_view_bankrupt_to_a_creditor() -> void:
	var tc := _game(2)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	tc.board.deed_at(37).owner = p0.id
	tc.board.deed_at(39).owner = p0.id
	tc.board.deed_at(39).has_hotel = true
	tc.bank.hotels_remaining -= 1
	tc.board.deed_at(1).owner = p1.id
	p1.cash = 50
	p1.position = 36
	tc.current_index = p1.id
	tc.dice.force(1, 2)  # 36 -> 39: hotel rent 2000; could raise 50 + 30
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "cannot pay the hotel")
	check(tc.declare_bankruptcy(), "bankrupt to seat 1")
	var debtor := SidePanel.seat_view(tc, p1)
	check(debtor["badges"]["bankrupt"] and not debtor["active"], "debtor bankrupt, not active")
	check(debtor["cash"] == 0 and debtor["owned"] == 0 and debtor["net_worth"] == 0, "debtor emptied")
	var creditor := SidePanel.seat_view(tc, p0)
	check_eq(creditor["cash"], 1550, "creditor took the 50")
	check_eq(creditor["owned"], 3, "creditor took brown_1")
	check_eq(creditor["net_worth"], 2455, "1550 + 175 + (200 + 500) + 30")
	done()


func test_active_follows_end_turn_and_skips_bankrupt() -> void:
	var tc := GameSetup.new_game(1234, GameSetup.seats(3, 0))
	var panel := _panel(tc)
	check_eq(_active_ids(tc, panel), [0] as Array[int], "seat 1 starts active")
	tc.phase = P.AWAITING_END_TURN  # end_turn is a no-op otherwise (turn_controller.gd:666-667)
	tc.end_turn()
	panel.show_values(tc)
	check_eq(_active_ids(tc, panel), [1] as Array[int], "end_turn hands the border on")
	var p1 := tc.players[1]
	p1.cash = 50
	p1.position = 1
	tc.dice.force(1, 2)  # 1 -> 4 Imperial Levy 200
	tc.roll()
	check(tc.declare_bankruptcy(), "seat 2 goes bankrupt on its own turn")
	check_eq(tc.phase, P.AWAITING_END_TURN, "nothing to auction: the turn waits for End Turn")
	panel.show_values(tc)
	check_eq(_active_ids(tc, panel), [] as Array[int], "no border while the bankrupt seat is still current")
	check(panel.cards[1].badges["bankrupt"].visible and not panel.cards[1].glow_frame.visible,
			"the bankrupt badge and the dropped border arrive in the same refresh")
	tc.end_turn()
	panel.show_values(tc)
	check_eq(_active_ids(tc, panel), [2] as Array[int], "End Turn passes on")
	tc.phase = P.AWAITING_END_TURN
	tc.end_turn()
	panel.show_values(tc)
	check_eq(_active_ids(tc, panel), [0] as Array[int], "round the table")
	tc.phase = P.AWAITING_END_TURN
	tc.end_turn()
	panel.show_values(tc)
	check_eq(_active_ids(tc, panel), [2] as Array[int], "the bankrupt seat is skipped; exactly one active")
	panel.free()
	done()


# --- Layout inside the strip ------------------------------------------------------------------

func _check_layout(lay: SidePanel.Layout, strip: Rect2, seats: int, expected: int, full_min: Vector2,
		compact_min: Vector2, tag: String) -> void:
	check_eq(lay.mode, expected, "%s mode" % tag)
	check_eq(SidePanel.rect_for(strip, seats, full_min, compact_min), lay.rect, "%s rect_for is the layout rect" % tag)
	if expected == M.HIDDEN:
		check(lay.rect == Rect2() and lay.cards.is_empty(), "%s hidden: Rect2() and no cards" % tag)
		return
	check_eq(lay.cards.size(), seats, "%s one card per seat" % tag)
	check(strip.encloses(lay.rect), "%s panel inside its strip (%s in %s)" % [tag, lay.rect, strip])
	var need := full_min if expected == M.FULL else compact_min
	var lo := UiStyle.num("side_card_min_size", 50.0)
	var gap := UiStyle.num("side_card_gap", 4.0)
	var cap := Vector2(UiStyle.num("side_card_max_width", 200.0), UiStyle.num("side_card_max_height", 120.0))
	var row := strip.size.x > strip.size.y
	check_eq(lay.vertical, not row, "%s one row when wider than tall, else one column" % tag)
	var bound := Rect2()
	for i in seats:
		var c: Rect2 = lay.cards[i]
		bound = c if i == 0 else bound.merge(c)
		check(strip.encloses(c), "%s card %d inside the strip" % [tag, i])
		check(c.size.x >= lo and c.size.y >= lo, "%s card %d >= side_card_min_size both ways (%s)" % [tag, i, c.size])
		check(c.size.x >= need.x and c.size.y >= need.y, "%s card %d holds its content (%s >= %s)" % [tag, i, c.size, need])
		check(c.size.x <= cap.x and c.size.y <= cap.y, "%s card %d within the caps (%s)" % [tag, i, c.size])
		check(c.size == lay.cards[0].size, "%s cards share one size" % tag)
		if i > 0:
			var prev: Rect2 = lay.cards[i - 1]
			var step := c.position.x - prev.end.x if row else c.position.y - prev.end.y
			check(step >= gap - 0.01 and not c.intersects(prev), "%s card %d clear of card %d" % [tag, i, i - 1])
			check(c.position.y == prev.position.y if row else c.position.x == prev.position.x,
					"%s cards on one line" % tag)
	check(bound.is_equal_approx(lay.rect), "%s rect bounds the cards" % tag)
	var before := lay.rect.position - strip.position
	var after := strip.end - lay.rect.end
	check(absf(before.x - after.x) <= 1.0 and absf(before.y - after.y) <= 1.0, "%s cards centred (%s / %s)" % [tag, before, after])


## The cards in their own strip (Shibi 6:07 PM: a rect nothing else draws in; A2 carves it out of the
## free band). Pinned modes, in both packs, per probe size and seats 2-6, for three strips: the whole
## free band (the most any carve can give), a strip side_card_min_size deep along the band's long
## side (the thinnest that shows cards: always compact) and one a unit thinner (always hidden); plus
## the bands of play rects with safe-area insets, a square strip and the exact thresholds. Expected
## modes worked out by hand from the FULL_MIN / 50 x 50 minimums, the 4-unit gap and the 200 x 120
## caps; one table holds for both packs' seat names (full cards 150 or 139 wide).
func test_layout_modes_pinned() -> void:
	for pack in UiStyle.theme_packs():
		var id := String(pack["id"])
		check(UiStyle.set_theme(id) and FULL_MIN.has(id), "%s: set_theme, full minimum pinned" % id)
		check_eq(_pinned_layout_cases(id), 8 * 5 * 3 + 2 * 5 * 2, "%s: every case ran" % id)
	done()


func _pinned_layout_cases(id: String) -> int:
	var F := M.FULL
	var C := M.COMPACT
	# One row per SIZES entry; seats 2 / 3 / 4 / 5 / 6.
	var band_modes: Array[Array] = [
		[F, F, F, C, C],  # 411x880: band 379x453, one column 200 wide: 120 / 120 / 110 / 87 / 72 tall
		[F, C, C, C, C],  # 411x731: band 379x304, one row 120 deep: 187 / 123 / 91 / 72 / 59 wide
		[F, F, C, C, C],  # 360x640: band 328x349 (A2 dock rule board 259, side_dock_min_h 436; 264 at 344), one column (taller than wide): 3 seats now full
		[C, C, C, C, C],  # 875x971: band 843x80, 80 deep, below the full 94
		[C, C, C, C, C],  # 820x910: band 788x74
		[F, F, C, C, C],  # 898x395: band 487x363, one row: 200 / 159 / 118 / 94 / 77 wide
		[C, C, C, C, C],  # 917x825: band 76x793, one column 76 wide
		[F, F, F, F, F],  # 1280x720: band 544x688, one column: 120 / 120 / 120 / 120 / 111 tall
	]
	check_eq(band_modes.size(), SIZES.size(), "one table row per committed probe size")
	var lo := UiStyle.num("side_card_min_size", 50.0)
	var gap := UiStyle.num("side_card_gap", 4.0)
	var mins := {}
	for n in SEATS:
		var panel := _panel(_pack_game(n))
		mins[n] = [panel.full_min_size(), panel.compact_min_size()]
		panel.free()
		check_eq(mins[n], [FULL_MIN[id], Vector2(50, 50)], "%s: %d-seat minimums (engine font Open Sans SemiBold 14)" % [id, n])
	var cases := 0
	for r in SIZES.size():
		var s := SIZES[r]
		var band := _band(s)
		for k in SEATS.size():
			var n := SEATS[k]
			var fm: Vector2 = mins[n][0]
			var cm: Vector2 = mins[n][1]
			var strips := [[band, int(band_modes[r][k]), "band"], [_thin(band, lo), C, "thin"],
					[_thin(band, lo - 1.0), M.HIDDEN, "under"]]
			for st: Array in strips:
				var strip: Rect2 = st[0]
				_check_layout(SidePanel.layout_for(strip, n, fm, cm), strip, n, st[1], fm, cm,
						"%s %s %d seats %s %s" % [id, s, n, st[2], strip])
				cases += 1
	# Play rects with safe-area insets: status and navigation bars on a phone (band 379x413, one column
	# 200 wide: 120 / 120 / 100 / 79 / 65 tall) and side cut-outs in landscape (band 464x688, one
	# column 200 wide: 120 tall for 2-5 seats, 111 for 6).
	var inset_rows: Array[Array] = [
		[Vector2(411, 880), Vector4(0, 24, 0, 16), Rect2(16, 435, 379, 413), [F, F, F, C, C]],
		[Vector2(1280, 720), Vector4(40, 0, 40, 0), Rect2(760, 16, 464, 688), [F, F, F, F, F]],
	]
	for row: Array in inset_rows:
		var band := _band(row[0], row[1])
		check(band.is_equal_approx(row[2]), "%s inset band %s (%s)" % [id, row[1], band])
		for k in SEATS.size():
			var n := SEATS[k]
			var fm: Vector2 = mins[n][0]
			var cm: Vector2 = mins[n][1]
			_check_layout(SidePanel.layout_for(band, n, fm, cm), band, n, int(row[3][k]), fm, cm,
					"%s insets %s %d seats band" % [id, row[1], n])
			_check_layout(SidePanel.layout_for(_thin(band, lo), n, fm, cm), _thin(band, lo), n, C, fm, cm,
					"%s insets %s %d seats thin" % [id, row[1], n])
			cases += 2
	# Thresholds: two full cards need 2 x full width + one gap at full height; six compact cards
	# need 6 x 50 + 5 gaps (the 328-unit row at 360x640 holds them, 51 each).
	var fm2: Vector2 = mins[2][0]
	var cm6: Vector2 = mins[6][1]
	var two := Vector2(2.0 * fm2.x + gap, fm2.y)
	_check_layout(SidePanel.layout_for(Rect2(Vector2.ZERO, two), 2, fm2, mins[2][1]), Rect2(Vector2.ZERO, two), 2, F,
			fm2, mins[2][1], "%s two full cards exactly" % id)
	var narrow := Rect2(Vector2.ZERO, two - Vector2(1, 0))
	_check_layout(SidePanel.layout_for(narrow, 2, fm2, mins[2][1]), narrow, 2, C, fm2, mins[2][1], "%s a unit too narrow for full" % id)
	var short := Rect2(Vector2.ZERO, two - Vector2(0, 1))
	_check_layout(SidePanel.layout_for(short, 2, fm2, mins[2][1]), short, 2, C, fm2, mins[2][1], "%s a unit too short for full" % id)
	var six := Rect2(Vector2(5, 7), Vector2(6.0 * cm6.x + 5.0 * gap, cm6.y))
	_check_layout(SidePanel.layout_for(six, 6, mins[6][0], cm6), six, 6, C, mins[6][0], cm6, "%s six compact cards exactly" % id)
	var six_short := Rect2(six.position, six.size - Vector2(1, 0))
	_check_layout(SidePanel.layout_for(six_short, 6, mins[6][0], cm6), six_short, 6, M.HIDDEN, mins[6][0], cm6,
			"%s a unit short of six compact cards" % id)
	# A square strip is not wider than tall: one column (two full 200 x 120 cards).
	var square := Rect2(0, 0, 400, 400)
	_check_layout(SidePanel.layout_for(square, 2, fm2, mins[2][1]), square, 2, F, fm2, mins[2][1], "%s square strip" % id)
	check_eq(SidePanel.layout_for(Rect2(), 2, fm2, mins[2][1]).mode, M.HIDDEN, "empty strip hides")
	# layout_for keeps side_card_min_size on its own, whatever minimums a caller passes.
	check_eq(SidePanel.layout_for(Rect2(0, 0, 40, 40), 2, Vector2.ZERO, Vector2.ZERO).mode, M.HIDDEN,
			"no 40-unit cards even with zero minimums")
	var floor_lay := SidePanel.layout_for(Rect2(0, 0, 2.0 * lo + gap, lo), 2, Vector2.ZERO, Vector2.ZERO)
	check(floor_lay.mode != M.HIDDEN and floor_lay.cards.all(func(r: Rect2) -> bool: return r.size.x >= lo and r.size.y >= lo),
			"zero minimums still give side_card_min_size cards")
	return cases


## Card sizes from font string widths plus the data/ui.json side_* sizes (test_ui.gd:611-631 style;
## off-tree container minimums are no evidence, so the card lays out its own nodes): the minimums,
## then every node inside the card's content inset and clear of the others at the smallest full and
## compact sizes, labels one font line high, figures whole.
func test_card_min_sizes_and_contents() -> void:
	var tc := _game(6)
	var panel := _panel(tc)
	var card := panel.cards[0]
	var font := card.cash_label.label_settings.font
	var fs := card.cash_label.label_settings.font_size
	var w := func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := font.get_height(fs)
	check(fs >= UiStyle.font("small"), "no text below font_small")
	var hud := UiStyle.make_theme()
	check(font == ThemeDB.fallback_font and hud.default_font == null and not hud.has_font("font", "Label"),
			"cards use the engine label font, as the HUD theme sets none (a HUD font needs the panel set up inside Main)")
	# The labels' own minimum is the font's, outside the tree too (LabelSettings, not theme overrides).
	check_eq(card.cash_label.get_combined_minimum_size(), Vector2(w.call(card.cash_label.text), h), "cash label minimum = font metrics")
	var inset := UiStyle.num("side_active_border_width", 3.0) + UiStyle.num("side_card_padding", 1.0)
	var token := UiStyle.num("side_token_size", 20.0)
	var lg := UiStyle.num("side_line_gap", 2.0)
	var cg := UiStyle.num("side_column_gap", 6.0)
	var lo := UiStyle.num("side_card_min_size", 50.0)
	var sample := SidePanel.SeatCard.money_text(int(UiStyle.num("side_money_sample", 9999.0)))
	var deeds := 0
	for sp in tc.board.spaces:
		deeds += 1 if sp.deed != null else 0
	var name_w := 0.0
	for p in tc.players:
		name_w = maxf(name_w, w.call(p.display_name))
	var block := Vector2(maxf(token, w.call(sample)), token + lg + h)
	var details := Vector2(maxf(name_w, maxf(w.call(SidePanel.SeatCard.owned_text(deeds)),
			w.call(SidePanel.WORTH_LABEL_PLACEHOLDER) + w.call(" ") + w.call(sample))), 4.0 * h + 3.0 * lg)
	var full := (Vector2(block.x + cg + details.x, maxf(block.y, details.y)) + Vector2.ONE * 2.0 * inset).ceil().max(Vector2.ONE * lo)
	var compact := (block + Vector2.ONE * 2.0 * inset).ceil().max(Vector2.ONE * lo)
	check_eq(panel.full_min_size(), full, "full minimum from string widths")
	check_eq(panel.compact_min_size(), compact, "compact minimum from string widths")
	# Measured at tip (Open Sans SemiBold 14 px: line 20, "$9999" 40, "Commander 6" 96).
	check_eq(full, FULL_MIN["imperium_astra"], "full minimum at tip (engine font Open Sans SemiBold 14)")
	check_eq(compact, Vector2(50, 50), "compact minimum at tip (Shibi: about 50)")
	var gap := UiStyle.num("side_card_gap", 4.0)
	for compact_mode in [false, true]:
		var cell: Vector2 = compact if compact_mode else full
		var strip := Rect2(Vector2(3, 5), Vector2(6.0 * cell.x + 5.0 * gap, cell.y))
		var placed := panel.place_in(strip)
		check(placed.is_equal_approx(strip), "six %s cards fill their exact strip (%s)" % [compact_mode, placed])
		check_eq(panel.mode, M.COMPACT if compact_mode else M.FULL, "mode applied")
		check(_rect(panel).is_equal_approx(strip), "panel takes the cards' rect")
		for c in panel.cards:
			c.set_badges({"jail": true, "bankrupt": true, "pardon": 2, "bot": true})
			var tag := "seat %d %s" % [c.player_id, "compact" if compact_mode else "full"]
			check(c.size.is_equal_approx(cell), "%s card at the minimum (%s)" % [tag, c.size])
			check_eq(c.compact, compact_mode, "%s compact flag" % tag)
			var content := Rect2(Vector2.ONE * inset, c.size - Vector2.ONE * 2.0 * inset)
			var tr := _rect(c.token)
			var cr := _rect(c.cash_label)
			check(content.encloses(tr) and content.encloses(cr), "%s token and cash inside the inset" % tag)
			check(not tr.intersects(cr), "%s cash under the token" % tag)
			check(cr.position.y >= tr.end.y, "%s cash below the token" % tag)
			check(cr.size.x + 0.5 >= w.call(c.cash_label.text), "%s figure shows whole" % tag)
			check_eq(c.cash_label.size.y, h, "%s cash one line high" % tag)
			check(c.token.uses_piece(), "%s token is the seat piece" % tag)
			check_eq(c.details.visible, not compact_mode, "%s details only on full cards" % tag)
			if compact_mode:
				continue
			var dr := _rect(c.details)
			check(content.encloses(dr), "%s details inside the inset" % tag)
			check(not dr.intersects(tr) and not dr.intersects(cr), "%s details beside the token block" % tag)
			var inner := Rect2(Vector2.ZERO, c.details.size)
			var rows: Array[Control] = [c.name_label, c.owned_label, c.worth_caption, c.worth_label]
			for k in rows.size():
				check(inner.encloses(_rect(rows[k])), "%s %s inside the details" % [tag, rows[k].name])
				check_eq(rows[k].size.y, h, "%s %s one line high" % [tag, rows[k].name])
				for j in k:
					check(not _rect(rows[k]).intersects(_rect(rows[j])), "%s %s clear of %s" % [tag, rows[k].name, rows[j].name])
			check(c.name_label.size.x + 0.5 >= w.call(c.name_label.text), "%s name whole at the minimum" % tag)
			check(c.worth_label.size.x + 0.5 >= w.call(c.worth_label.text), "%s worth whole" % tag)
			var shown: Array[Label] = []
			for key: String in SidePanel.BADGE_KEYS:
				var b: Label = c.badges[key]
				check(b.visible, "%s %s badge on" % [tag, key])
				check(inner.encloses(_rect(b)), "%s %s badge inside the details (%s)" % [tag, key, _rect(b)])
				for o in shown:
					check(not _rect(b).intersects(_rect(o)), "%s badge %s clear of %s" % [tag, key, o.name])
				for r in rows:
					check(not _rect(b).intersects(_rect(r)), "%s badge %s clear of %s" % [tag, key, r.name])
				shown.append(b)
	# Badge widths with no slack (an ellipsis label narrower than its text trims it): on the smallest
	# full card (details 96 wide) each badge alone shows whole; jail + bot (70 + 6 + 32 > 96) keep the
	# shorter bot tag whole and give jail the rest, ending in an ellipsis.
	panel.place_in(Rect2(Vector2.ZERO, Vector2(6.0 * full.x + 5.0 * gap, full.y)))
	var c0 := panel.cards[0]
	var room := c0.details.size.x
	check_eq(room, 96.0, "details width on the smallest full card")
	for key: String in SidePanel.BADGE_KEYS:
		c0.set_badges({"jail": key == "jail", "bankrupt": key == "bankrupt", "pardon": 1 if key == "pardon" else 0,
				"bot": key == "bot"})
		var b: Label = c0.badges[key]
		check(b.size.x >= w.call(b.text) and b.position.x == 0.0, "%s badge alone shows whole (%s >= %s)" % [key, b.size.x, w.call(b.text)])
	c0.set_badges({"jail": true, "bankrupt": false, "pardon": 0, "bot": true})
	var bot: Label = c0.badges["bot"]
	var jail: Label = c0.badges["jail"]
	check_eq(bot.size.x, w.call(bot.text), "the shorter badge stays whole")
	check_eq(jail.size.x, room - UiStyle.num("side_column_gap", 6.0) - w.call(bot.text), "the longer badge takes the rest")
	check(jail.position.x + jail.size.x <= bot.position.x and bot.position.x + bot.size.x <= room, "jail then bot, inside the line")
	# A figure wider than side_money_sample shows short on the 50-unit compact card (SIDE_PANEL_A2,
	# Shibi Oct 29 2026 7:20 PM: "$10k", not A1's 48-wide "$10000"), whole, centred under the token.
	panel.place_in(Rect2(Vector2.ZERO, Vector2(6.0 * compact.x + 5.0 * gap, compact.y)))
	c0.set_cash(10000, 0)
	var big := _rect(c0.cash_label)
	check(c0.cash_label.text == "$10k" and big.size.x >= w.call("$10k"), "five-digit figure short and whole (%s)" % big)
	check(absf(big.get_center().x - _rect(c0.token).get_center().x) <= 0.5, "centred under the token")
	check(Rect2(Vector2.ZERO, c0.size).encloses(big), "still on the card (%s)" % big)
	panel.free()
	done()


# --- Hooks ------------------------------------------------------------------------------------

## Off-tree, this catches only fade state (modulate, UiFx metas): Tweens start only inside the tree,
## where the scratch probe found none, and the no-Tween / no-UiFx rule for A1's code is the report's
## grep gate (a source scan here would block SIDE_PANEL_B_ANIM, which animates in these hooks).
func _check_no_motion(node: Node, tag: String) -> void:
	for c in [node] + _controls(node):
		var ci := c as CanvasItem
		check(not ci.has_meta(UiFx.TWEEN_META) and not ci.has_meta(UiFx.HIDING_META), "%s: no UiFx state on %s" % [tag, ci.name])
		check(ci.modulate == Color.WHITE, "%s: %s not faded" % [tag, ci.name])


## The hook contract (instant in A1; B animates inside these and changes nothing else): every hook
## shows its value at once and exactly (outside the tree here; the hooks have no tree branch, no
## Tween and no UiFx call), set_cash / set_owned get delta = value - the last value given, 0 on the
## first call at build and on unchanged repeats.
func test_hooks_instant_and_exact() -> void:
	var tc := _game(2)
	var panel := _panel(tc)
	check_eq(panel.animate, false, "animate defaults off (Main sets it, A2)")
	var c0 := panel.cards[0]
	var c1 := panel.cards[1]
	check_eq(c0.cash_label.text, "$1500", "cash at build")
	check_eq(c0.last_cash, 1500, "last cash at build")
	check_eq(c0.last_cash_delta, 0, "no delta on the first call (a new match shows no popup)")
	check_eq(c0.last_owned_delta, 0, "no owned delta at build")
	check_eq(c0.worth_label.text, "$1500", "net worth at build")
	check_eq(c0.owned_label.text, "0 deeds", "owned at build")
	check_eq(c0.worth_caption.text, SidePanel.WORTH_LABEL_PLACEHOLDER, "net worth caption")
	check(c0.glow_frame.visible and not c1.glow_frame.visible, "active border on the turn seat only")
	check(c1.badges["bot"].visible and not c0.badges["bot"].visible, "bot badge on the bot seat")
	panel.show_values(tc)
	check_eq(c0.last_cash_delta, 0, "unchanged repeat: delta 0")
	tc.players[0].add_cash(-200)
	tc.board.deed_at(1).owner = 0
	panel.show_values(tc)
	check_eq(c0.cash_label.text, "$1300", "cash refreshed")
	check_eq(c0.last_cash_delta, -200, "delta = value - last value")
	check_eq(c0.last_owned_delta, 1, "owned delta")
	check_eq(c0.owned_label.text, "1 deed", "one deed")
	check_eq(c0.worth_label.text, "$1330", "worth refreshed (1300 + 30)")
	check_eq(c1.last_cash_delta, 0, "the other seat's figure did not change")
	panel.show_values(tc)
	check_eq(c0.last_cash_delta, 0, "repeat after a change: delta 0")
	c0.set_cash(1234, 7)
	check_eq(c0.cash_label.text, "$1234", "set_cash shows the value at once")
	check(c0.last_cash == 1234 and c0.last_cash_delta == 7, "set_cash keeps what it was given")
	c0.set_net_worth(4321)
	check_eq(c0.worth_label.text, "$4321", "set_net_worth at once")
	c0.set_owned(3, 2)
	check(c0.owned_label.text == "3 deeds" and c0.last_owned == 3 and c0.last_owned_delta == 2, "set_owned at once")
	c0.set_badges({"jail": true, "bankrupt": false, "pardon": 2, "bot": true})
	check(c0.badges["jail"].visible and not c0.badges["bankrupt"].visible and c0.badges["pardon"].visible
			and c0.badges["bot"].visible, "set_badges toggles each badge node")
	check_eq(c0.badges["pardon"].text, "%s x2" % tc.board.term("pardon"), "pardon count")
	c0.set_badges({"jail": false, "bankrupt": false, "pardon": 1, "bot": false})
	check_eq(c0.badges["pardon"].text, tc.board.term("pardon"), "one pardon card")
	check(not c0.badges["jail"].visible and not c0.badges["bot"].visible, "badges off again")
	c0.set_active(false)
	check(not c0.glow_frame.visible, "set_active(false) at once")
	c0.set_active(true)
	check(c0.glow_frame.visible, "set_active(true) at once")
	panel.set_panel_shown(false)
	check(not panel.visible, "set_panel_shown(false) hides at once")
	panel.set_panel_shown(true)
	check(panel.visible, "set_panel_shown(true) shows at once")
	_check_no_motion(panel, "after every hook")
	panel.free()
	done()


func test_words_and_money_text() -> void:
	check_eq(SidePanel.SeatCard.money_text(1500), "$1500", "the chips' $ form, no space")
	check_eq(SidePanel.SeatCard.money_text(0), "$0", "zero")
	check_eq(SidePanel.SeatCard.owned_text(0), "0 deeds", "none")
	check_eq(SidePanel.SeatCard.owned_text(1), "1 deed", "one")
	check_eq(SidePanel.SeatCard.owned_text(12), "12 deeds", "many")
	check_eq(SidePanel.BADGE_KEYS, ["jail", "bankrupt", "pardon", "bot"] as Array[String], "badge keys in order")
	var tc := _game(2)
	var panel := _panel(tc)
	var c := panel.cards[0]
	check_eq(c.badges["jail"].text, "in %s" % tc.board.term("jail"), "jail badge: the overlay title's words")
	check_eq(c.badges["jail"].text, "in the Brig", "jail badge with the shared board.json term")
	check_eq(c.badges["pardon"].text, "Pardon card", "pardon badge with the shared board.json term")
	check_eq(c.badges["bankrupt"].text, "bankrupt", "bankrupt badge: the chips' word")
	check_eq(c.badges["bot"].text, "(bot)", "bot badge: the chips' tag")
	check_eq(c.name_label.text, tc.players[0].display_name, "the seat's name")
	panel.free()
	done()


## Cards are built once and never freed or rebuilt (B's running motion stays attached): the same
## SeatCard and child nodes survive refreshes, resizes, full / compact switches and a strip too
## small to show (the panel keeps its cards; Main hides it, A2).
func test_cards_survive_refresh_resize_and_mode_switch() -> void:
	var tc := _game(4)
	var panel := _panel(tc)
	var ids: Array[int] = []
	for c in panel.cards:
		for n: Node in [c, c.background, c.token, c.cash_label, c.details, c.name_label, c.owned_label,
				c.worth_caption, c.worth_label, c.glow_frame, c.fx_layer] + c.badges.values():
			ids.append(n.get_instance_id())
	var full := panel.place_in(Rect2(0, 0, 4 * 160 + 3 * 4, 100))
	check_eq(panel.mode, M.FULL, "full in a wide strip (%s)" % full)
	tc.players[2].add_cash(50)
	panel.show_values(tc)
	panel.place_in(Rect2(0, 0, 300, 60))
	check_eq(panel.mode, M.COMPACT, "compact in a thin strip")
	check(panel.cards.all(func(c: SidePanel.SeatCard) -> bool: return c.compact and not c.details.visible), "every card compact")
	check_eq(panel.place_in(Rect2(0, 0, 100, 40)), Rect2(), "too small: Rect2()")
	check(panel.visible, "place_in never hides; set_panel_shown does")
	panel.place_in(Rect2(10, 20, 210, 700))
	check_eq(panel.mode, M.FULL, "full in a column")
	check(not panel.cards.any(func(c: SidePanel.SeatCard) -> bool: return c.compact), "every card full again")
	var after: Array[int] = []
	for c in panel.cards:
		for n: Node in [c, c.background, c.token, c.cash_label, c.details, c.name_label, c.owned_label,
				c.worth_caption, c.worth_label, c.glow_frame, c.fx_layer] + c.badges.values():
			after.append(n.get_instance_id())
	check_eq(after, ids, "the same nodes throughout")
	check_eq(panel.get_child_count(), 4, "one card per seat, nothing added")
	panel.free()
	done()


# --- Structure and theme ----------------------------------------------------------------------

func test_structure_and_mouse_filters() -> void:
	var tc := _game(6)
	var panel := _panel(tc)
	panel.place_in(Rect2(0, 0, 210, 700))
	check_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "display-only panel")
	for c in _controls(panel):
		check_eq(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % c.name)
	check_eq(panel.cards.size(), 6, "one card per seat")
	var border_w := int(UiStyle.num("side_active_border_width", 3.0))
	var tint := UiStyle.num("side_tint_alpha", 0.2)
	for i in panel.cards.size():
		var c := panel.cards[i]
		var p := tc.players[i]
		check(panel.get_child(i) == c and c.player_id == p.id, "card %d in seat order" % i)
		check_eq(c.get_child(c.get_child_count() - 1), c.fx_layer, "fx_layer on top")
		check_eq(c.get_child(c.get_child_count() - 2), c.glow_frame, "glow_frame over the content")
		check_eq(c.fx_layer.get_class(), "Control", "fx_layer is a plain Control, not a Container")
		check(not c.fx_layer.clip_contents, "popups may leave the card")
		check(_rect(c.fx_layer).is_equal_approx(Rect2(Vector2.ZERO, c.size)), "fx_layer covers the card")
		check(c.glow_frame is Panel and _rect(c.glow_frame).is_equal_approx(Rect2(Vector2.ZERO, c.size)), "glow_frame covers the card")
		var glow := c.glow_frame.get_theme_stylebox("panel") as StyleBoxFlat
		check(glow != null and glow.border_color == p.color and not glow.draw_center
				and glow.border_width_left == border_w and glow.border_width_bottom == border_w,
				"glow_frame: its own seat-coloured border, no fill")
		var bg := c.background.get_theme_stylebox("panel") as StyleBoxFlat
		check(bg != null and bg.bg_color.is_equal_approx(UiStyle.color("panel").lerp(p.color, tint)), "seat tint over the panel colour")
		check(bg != null and bg.border_color == p.color, "seat-coloured card border")
		check(glow != bg, "the glow border is its own StyleBox")
		check_eq(_sorted_keys(c.badges), ["bankrupt", "bot", "jail", "pardon"], "one node per badge key")
		for key: String in SidePanel.BADGE_KEYS:
			check(c.badges[key] is Label and c.badges[key].get_parent() == c.details, "%s badge lives in the details" % key)
		check(c.token.piece is SpacePiece and c.token.piece.tint == p.color and c.token.piece.seat == p.id,
				"card %d token: the seat's SpacePiece" % i)
		for l: Control in _controls(c):
			if l is Label:
				var ls := (l as Label).label_settings
				check_eq((l as Label).autowrap_mode, TextServer.AUTOWRAP_OFF, "%s keeps one line" % l.name)
				check(ls != null and ls.font_size >= UiStyle.font("small"), "%s at least font_small" % l.name)
				check(ls != null and ls.font_color == UiStyle.color("text"), "%s in theme text, not the seat colour" % l.name)
	panel.free()
	done()


## The token is the seat's SpacePiece; where it cannot render at card size (below
## side_token_piece_min_size) a colour disc with the seat number (id + 1) stands in.
func test_token_piece_with_disc_fallback() -> void:
	var tc := _game(3)
	var panel := _panel(tc)
	var t := panel.cards[2].token
	var full := UiStyle.num("side_token_size", 20.0)
	var floor_px := UiStyle.num("side_token_piece_min_size", 16.0)
	check(full >= floor_px, "the shipped token size shows the piece")
	check(t.size == Vector2.ONE * full and t.uses_piece(), "token sized at build, before any placement")
	panel.place_in(Rect2(0, 0, 3 * 160 + 2 * 4, 100))
	check(t.uses_piece() and t.piece.visible, "piece at the card's token size")
	t.fit(floor_px - 1.0)
	check(not t.uses_piece() and not t.piece.visible, "disc below the piece floor")
	check_eq(t.disc_text(), "3", "disc shows seat id + 1")
	t.fit(full)
	check(t.uses_piece() and t.piece.visible, "piece again at full size")
	# TokenView scales the piece by SpacePiece's own unit (space_piece.gd:24); trips if that changes.
	check(FileAccess.get_file_as_string("res://scripts/ui/space_piece.gd").contains(
			"_cell * %s" % SidePanel.TokenView.PIECE_UNIT_PER_CELL), "SpacePiece still draws one unit as _cell * 0.22")
	panel.free()
	done()


## Text on the seat-tinted cards meets the body-text bar of test_text_contrast (test_theme.gd:145,
## AAA 7:1 on panels) for all six seat_pool colours in both packs; the disc digit meets AA on its
## seat colour. A full-strength seat colour behind theme "text" would fail (the seat colours are
## light: #e6ecff on #4fc3f7 is about 1.7:1), so the tint must stay light.
func test_text_contrast_on_tinted_cards_both_packs() -> void:
	for pack in UiStyle.theme_packs():
		var id := String(pack["id"])
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var content := UiStyle.content_overlay()
		var tc := GameSetup.new_game(1234, GameSetup.seats(1, 5, content), content)
		var panel := _panel(tc)
		var text := UiStyle.color("text")
		var full_strength_fails := false
		for c in panel.cards:
			var seat := tc.players[c.player_id].color
			var bg := (c.background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
			full_strength_fails = full_strength_fails or ThemeTests.contrast(text, seat) < 7.0
			for l: Control in _controls(c):
				if l is Label:
					var fc := (l as Label).label_settings.font_color
					check(ThemeTests.contrast(fc, bg) >= 7.0, "%s: %s on seat #%s card (%.2f)" % [id, l.name,
							seat.to_html(false), ThemeTests.contrast(fc, bg)])
			check(ThemeTests.contrast(c.token.disc_color(), seat) >= 4.5, "%s: disc digit on #%s" % [id, seat.to_html(false)])
		check(full_strength_fails, "%s: a full-strength seat colour would fail (non-vacuous)" % id)
		check_eq(panel.cards[0].name_label.text, tc.players[0].display_name, "%s: pack seat name" % id)
		panel.free()
	done()


## Every side_* number the panel reads is in data/ui.json (UiStyle.num falls back silently, and the
## tests read the same fallbacks, so a renamed key would otherwise pass on both sides), positive,
## with Shibi's two picks as given and the rest marked as placeholders in side_panel_doc.
func test_side_keys_in_ui_json() -> void:
	var d := UiStyle.data()
	for k in SIDE_KEYS:
		check(d.has(k) and (d[k] is float or d[k] is int) and float(d[k]) > 0.0, "data/ui.json %s is a positive number" % k)
	check_eq(UiStyle.num("side_card_min_size", 0.0), 50.0, "Shibi: cards about 50")
	check_eq(UiStyle.num("side_tint_alpha", 0.0), 0.2, "Shibi Oct 29 2026: seat tint 0.2")
	check(UiStyle.num("side_card_padding", 0.0) >= 1.0, "the active border never covers content")
	check(String(d.get("side_panel_doc", "")).contains("_placeholder"), "side_panel_doc marks the placeholder picks")
	var src := FileAccess.get_file_as_string("res://scripts/ui/side_panel.gd")
	var keys := RegEx.create_from_string("\"(side_[a-z_]+)\"")
	var read := 0
	for m in keys.search_all(src):
		read += 1
		check(m.get_string(1) in SIDE_KEYS, "side_panel.gd reads %s, which this test checks" % m.get_string(1))
	check(read >= SIDE_KEYS.size(), "the panel reads its keys by name (%d reads)" % read)
	done()
