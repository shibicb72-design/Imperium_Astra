extends TestCase
## P5-FEEL A2/A3: build / sell game_event kinds (incl. sell_group_buildings), the existing
## bankrupt event, and BoardView's piece contract (piece_state, Node2D attach, bankrupt fade)
## with animate off: snaps at once, no orphan nodes. Presentation only; no rules change.

const P := TurnController.Phase


func _brown(owner: int) -> TurnController:
	var tc := GameSetup.new_game(1234)
	for pl in tc.players:
		pl.is_bot = false
	tc.board.deed_at(1).owner = owner
	tc.board.deed_at(3).owner = owner
	return tc


func _record(tc: TurnController) -> Array:
	var events := []
	tc.game_event.connect(func(kind: StringName, info: Dictionary) -> void: events.append([kind, info]))
	return events


func _of(events: Array, kind: StringName) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == kind)


## Presentation payloads carry ids and numbers only, never theme text.
func _check_ids_only(info: Dictionary, what: String) -> void:
	for k: String in info:
		var t := typeof(info[k])
		check(t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL, "%s.%s is an id or number" % [what, k])


func test_build_emits_built_house_and_hotel() -> void:
	var tc := _brown(0)
	var ev := _record(tc)
	check(tc.build(0, 1), "house")
	var b := _of(ev, &"built_house")
	check_eq(b.size(), 1, "one built_house")
	check_eq(b[0][1], {"player": 0, "space": 1, "houses": 1, "cost": 50}, "built_house payload")
	_check_ids_only(b[0][1], "built_house")
	tc.board.deed_at(1).houses = 4
	tc.board.deed_at(3).houses = 4
	check(tc.build(0, 1), "hotel")
	var h := _of(ev, &"built_hotel")
	check_eq(h.size(), 1, "one built_hotel")
	check_eq(h[0][1], {"player": 0, "space": 1, "cost": 50}, "built_hotel payload")
	_check_ids_only(h[0][1], "built_hotel")
	check(not tc.build(1, 3), "illegal build")
	check_eq(_of(ev, &"built_house").size() + _of(ev, &"built_hotel").size(), 2, "no event for a refused build")
	done()


func test_sell_emits_sold_house_and_hotel() -> void:
	var tc := _brown(0)
	tc.board.deed_at(1).has_hotel = true
	tc.board.deed_at(3).has_hotel = true
	tc.bank.hotels_remaining = 10
	var ev := _record(tc)
	check(tc.sell_building(0, 1), "hotel back for 4 houses")
	var h := _of(ev, &"sold_hotel")
	check_eq(h.size(), 1, "one sold_hotel")
	check_eq(h[0][1], {"player": 0, "space": 1, "houses": 4, "amount": 25}, "sold_hotel payload")
	_check_ids_only(h[0][1], "sold_hotel")
	tc.board.deed_at(3).has_hotel = false
	tc.board.deed_at(3).houses = 4
	check(tc.sell_building(0, 3), "a house")
	var s := _of(ev, &"sold_house")
	check_eq(s.size(), 1, "one sold_house")
	check_eq(s[0][1], {"player": 0, "space": 3, "count": 1, "houses": 3, "amount": 25}, "sold_house payload")
	_check_ids_only(s[0][1], "sold_house")
	check(not tc.sell_building(1, 1), "not the owner")
	check_eq(_of(ev, &"sold_house").size() + _of(ev, &"sold_hotel").size(), 2, "no event for a refused sale")
	done()


func test_sell_group_emits_one_event_per_street() -> void:
	var tc := _brown(0)
	var group := tc.board.deed_at(1).color_group_id
	tc.board.deed_at(1).has_hotel = true
	tc.board.deed_at(3).has_hotel = true
	tc.bank.hotels_remaining = 10
	tc.bank.houses_remaining = 0  # hotel break: a single sale cannot get its 4 houses
	check(not tc.sell_building(0, 1), "single hotel sale blocked by house stock")
	var ev := _record(tc)
	var cash := tc.players[0].cash
	check(tc.sell_group_buildings(0, group), "sell the whole group")
	var h := _of(ev, &"sold_hotel")
	check_eq(h.size(), 2, "one sold_hotel per street")
	check_eq(h[0][1], {"player": 0, "space": 1, "houses": 0, "amount": 125}, "street 1 cleared")
	check_eq(h[1][1], {"player": 0, "space": 3, "houses": 0, "amount": 125}, "street 3 cleared")
	check_eq(int(h[0][1]["amount"]) + int(h[1][1]["amount"]), tc.players[0].cash - cash, "amounts add up to the sale")
	for e in h:
		_check_ids_only(e[1], "sold_hotel")
	tc.board.deed_at(1).houses = 4
	tc.board.deed_at(3).houses = 3
	ev.clear()
	check(tc.sell_group_buildings(0, group), "sell houses as a group")
	var s := _of(ev, &"sold_house")
	check_eq(s.size(), 2, "one sold_house per street")
	check_eq(s[0][1], {"player": 0, "space": 1, "count": 4, "houses": 0, "amount": 100}, "4 houses")
	check_eq(s[1][1], {"player": 0, "space": 3, "count": 3, "houses": 0, "amount": 75}, "3 houses")
	ev.clear()
	check(not tc.sell_group_buildings(0, group), "nothing left")
	check(ev.is_empty(), "no event when nothing sold")
	done()


func test_won_building_lot_emits_built_house() -> void:
	var tc := _brown(0)
	for i in [6, 8, 9]:
		tc.board.deed_at(i).owner = 1
	tc.bank.houses_remaining = 1
	var claims: Dictionary[int, int] = {0: 1, 1: 6}
	check(tc.start_building_auction(claims), "shortage auction")
	var ev := _record(tc)
	check(tc.auction_bid(10), "bid")
	check(tc.auction_bid(15), "raise")
	check(tc.auction_pass(), "close")
	var b := _of(ev, &"built_house")
	check_eq(b.size(), 1, "built_house after the lot is placed")
	check_eq(b[0][1], {"player": 0, "space": 1, "houses": 1, "cost": 15}, "cost is the winning bid")
	done()


func test_bankrupt_event_reused_ids_only() -> void:
	var tc := _brown(0)
	var p0 := tc.players[0]
	var p1 := tc.players[1]
	tc.board.deed_at(39).owner = p0.id
	tc.board.deed_at(37).owner = p0.id
	tc.board.deed_at(39).has_hotel = true
	tc.bank.hotels_remaining = 11
	p1.cash = 10
	p1.position = 36
	tc.current_index = p1.id
	var ev := _record(tc)
	tc.dice.force(1, 2)  # 36 -> 39: hotel rent
	tc.roll()
	check_eq(tc.phase, P.RAISING_FUNDS, "debt")
	check(tc.declare_bankruptcy(), "declared")
	var b := _of(ev, &"bankrupt")
	check_eq(b.size(), 1, "one bankrupt event")
	check_eq(b[0][1], {"player": p1.id, "creditor": p0.id}, "bankrupt payload")
	_check_ids_only(b[0][1], "bankrupt")
	check(_of(ev, &"bankrupt_settled").is_empty(), "no extra settle event")
	done()


func test_piece_state_matches_token_math() -> void:
	var tc := GameSetup.new_game(1234)
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	check(not bv.piece_state(0).visible, "nothing before setup")
	bv.setup(tc)
	var br := Rect2(Vector2.ZERO, Vector2(440, 440))
	var cell := 440.0 / BoardView.GRID
	var s := bv.piece_state(1)
	check(s.visible and not s.moving, "resting piece")
	check_eq(s.point, BoardView.token_point(br, cell, 1, 0), "resting point is token_point")
	check(is_equal_approx(s.alpha, 1.0) and is_equal_approx(s.lift, 0.0), "opaque, on the ground")
	check(not bv.piece_state(99).visible, "unknown id is hidden")
	bv.animate = true
	tc.players[0].set_position(5)
	bv.queue_move(0, 0, 5)
	bv.advance(UiStyle.num("pawn_step_seconds", 0.14) * 0.5)
	var m := bv.piece_state(0)
	check(m.moving and m.lift > 0.5, "mid-hop piece is lifted")
	check(m.point.y < m.rest.y, "lifted above its ground point")
	bv.advance(10.0)
	check_eq(bv.piece_state(0).point, BoardView.token_point(br, cell, 0, 5), "lands on the new space")
	bv.free()
	done()


func test_attached_piece_follows_and_snaps_headless() -> void:
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var tc := GameSetup.new_game(1234)
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	bv.setup(tc)
	var piece := Node2D.new()
	bv.attach_piece(1, piece)
	check(piece.get_parent() == bv, "piece is a child of the board")
	check(bv.piece_node(1) == piece, "lookup")
	check_eq(piece.position, bv.piece_state(1).point, "positioned on attach")
	bv.queue_move(1, 0, 7)  # animate off: snaps at once
	check(not bv.is_animating(), "nothing queued")
	check_eq(piece.position, bv.piece_state(1).point, "snapped with the move")
	check_eq(bv.piece_state(1).index, 7, "shown index from the queue, not rules state")
	tc.players[1].set_position(10)
	bv.queue_jump(1, 7, 10)
	check_eq(piece.position, BoardView.token_point(Rect2(Vector2.ZERO, bv.size), 40.0, 1, 10), "jump snaps")
	var replacement := Node2D.new()
	bv.attach_piece(1, replacement)
	check(bv.piece_node(1) == replacement and not is_instance_valid(piece), "old piece freed on replace")
	var taken := bv.detach_piece(1)
	check(taken == replacement and taken.get_parent() == null, "detach hands the node back")
	taken.free()
	bv.attach_piece(0, Node2D.new())
	bv.attach_piece(1, Node2D.new())
	bv.clear_pieces()
	check(bv.piece_node(0) == null and bv.get_child_count() == 0, "clear frees every piece")
	bv.attach_piece(0, Node2D.new())
	bv.free()  # frees its pieces with it
	check_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans_before, "no orphan nodes")
	done()


func test_bankrupt_fade_hook() -> void:
	var tc := GameSetup.new_game(1234)
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	bv.setup(tc)
	var piece := Node2D.new()
	bv.attach_piece(1, piece)
	tc.players[1].is_bankrupt = true
	bv.fade_out_piece(1, 0.5)  # animate off: hidden at once
	check(not bv.is_fading(1) and not piece.visible, "headless: bankrupt piece hidden at once")
	bv.animate = true
	bv.fade_out_piece(1, 0.5)
	check(bv.is_fading(1) and piece.visible, "fading piece still shown")
	bv.advance_fades(0.25)
	check(is_equal_approx(piece.modulate.a, 0.5), "half faded")
	bv.advance_fades(1.0)
	check(not bv.is_fading(1) and not piece.visible, "gone once the fade ends")
	check(tc.players[1].is_bankrupt, "rules state untouched")
	bv.free()
	done()


## P5 structure hooks: mortgage / unmortgage are presentation events like build / sell (ids only).
func test_feel_mortgage_events_ids_only() -> void:
	var tc := _brown(0)
	var ev := _record(tc)
	check(tc.mortgage(0, 3), "mortgage")
	check(tc.unmortgage(0, 3), "unmortgage")
	var m := _of(ev, &"mortgaged")
	var u := _of(ev, &"unmortgaged")
	check_eq(m.size(), 1, "one mortgaged")
	check_eq(u.size(), 1, "one unmortgaged")
	if m.size() == 1:
		check_eq(m[0][1]["amount"], tc.board.deed_at(3).mortgage_value, "mortgage value")
		_check_ids_only(m[0][1], "mortgaged")
	if u.size() == 1:
		check(int(u[0][1]["amount"]) > int(m[0][1]["amount"]), "unmortgage costs value plus interest")
		_check_ids_only(u[0][1], "unmortgaged")
	done()


## P5 structure hooks: the piece contract carries the jail look flag (no art required yet).
func test_feel_piece_state_in_jail_flag() -> void:
	var tc := GameSetup.new_game(1234)
	var bv := BoardView.new()
	bv.size = Vector2(440, 440)
	bv.setup(tc)
	var piece := SpacePiece.new()
	bv.attach_piece(0, piece)
	check_eq(bv.piece_state(0).get("in_jail"), false, "free piece")
	tc.players[0].set_position(tc.config.jail_index)
	tc.players[0].in_jail = true
	bv.sync_to_game()
	check_eq(bv.piece_state(0).get("in_jail"), true, "jailed piece reads the flag")
	check_eq(piece.get("_in_jail"), true, "SpacePiece stores the flag from apply_piece_state")
	check(not bv.piece_state(99).get("in_jail"), "unknown id: not jailed")
	bv.free()
	done()
