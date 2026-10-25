extends TestCase


func test_roll_move_queue_keeps_panel_behind_settled_gate() -> void:
	var main := Main.new()
	main.controller = GameSetup.new_game(7)
	main.start(null)
	var tc := main.controller
	for p in tc.players:
		p.is_bot = false
	tc.current_player().set_position(0)
	main._board_view.sync_to_game()
	main._board_view.animate = true
	tc.dice.force(1, 2)
	main._refresh()
	check(main.press_die(), "tap handler accepts roll")
	check_eq(main._board_view.dice_look(), &"tumble", "roll starts with tumble")
	check_eq(Vector2i(tc.dice.d1, tc.dice.d2), Vector2i(1, 2), "presentation preserves outcome")
	var roll_seconds := UiStyle.num("dice_roll_seconds", 0.55)
	main._board_view.advance(roll_seconds * 0.1)
	var fast_interval := main._board_view._tumble_left
	main._board_view.advance(roll_seconds * 0.6)
	check(main._board_view._tumble_left > fast_interval, "tumble slows before settling")
	check_eq(Vector2i(tc.dice.d1, tc.dice.d2), Vector2i(1, 2), "visual RNG leaves rules dice intact")
	main._board_view.advance(roll_seconds * 0.3 + 0.01)
	main._refresh()
	check(main._board_view.piece_state(tc.current_player().id).moving, "piece starts after dice")
	check_eq(main.gate(), MatchGate.State.BUSY, "hop keeps gate busy")
	check(not main._turn_panel.offers(&"buy"), "no panel action mid-hop")
	main._board_view.advance(10.0)
	main._refresh()
	check_eq(main.gate(), MatchGate.State.BUY, "settled gate offers purchase")
	check(main._turn_panel.offers(&"buy"), "panel ready without waiting for finished signal")
	check_eq(main._board_view.piece_node(tc.current_player().id).position,
		main._board_view.piece_state(tc.current_player().id).point, "piece rests at landing")
	main.free()
	done()


func test_turn_panel_hide_blocks_stale_presses_and_reopens() -> void:
	var tc := GameSetup.new_game(7)
	for p in tc.players:
		p.is_bot = false
	var panel := TurnPanel.new()
	panel.setup(tc)
	var emitted: Array[StringName] = []
	panel.slot_pressed.connect(func(slot: StringName) -> void: emitted.append(slot))
	panel.refresh(MatchGate.State.END_TURN)
	check(panel.offers(&"end_turn"), "shown panel accepts input")
	panel.hide_panel()
	panel.visible = true  # simulate the visible portion of a fade-out
	panel.button(&"end_turn").pressed.emit()
	check(emitted.is_empty(), "stale signal cannot escape hiding panel")
	check(not panel.offers(&"end_turn"), "visible fade offers no action")
	check(panel.button(&"end_turn").disabled, "hidden buttons disabled immediately")
	panel.refresh(MatchGate.State.END_TURN)
	panel.button(&"end_turn").pressed.emit()
	check_eq(emitted, [&"end_turn"] as Array[StringName], "reopening restores input")
	panel.refresh(MatchGate.State.BUSY)
	check(not panel.visible, "animate off hides instantly")
	check_eq(panel.modulate.a, 1.0, "snap restores alpha")
	panel.free()
	done()


func test_piece_hops_follow_backward_wrap_and_queue_jump() -> void:
	var tc := GameSetup.new_game(7)
	var view := BoardView.new()
	view.setup(tc)
	view.size = Vector2(660, 660)
	view.animate = true
	view.queue_move(0, 0, -2)
	view.queue_jump(0, 38, 10)
	var observed: Array[int] = []
	view.queue_call(func() -> void: observed.append(view.shown_position(0)))
	view.advance(UiStyle.num("pawn_step_seconds", 0.14) * 0.25)
	var s := view.piece_state(0)
	check(s.moving and s.lift > 0.0, "backward wrap lifts piece")
	check_eq(view.piece_node(0).position, s.point, "Node2D follows eased wrap")
	view.advance(UiStyle.num("pawn_step_seconds", 0.14) * 1.75)
	check(view.is_animating() and observed.is_empty(), "jump and callback remain queued")
	view.advance(10.0)
	check_eq(observed, [10], "callback sees completed jump")
	check(not view.is_animating(), "queue drains completely")
	check(not view.piece_state(0).moving, "piece settles")
	view.free()
	done()


func teardown() -> void:
	UiStyle.reset_theme()


func test_product_picker_switch_and_match() -> void:
	var main := Main.new()
	var panel := main.show_setup(null)
	panel.save_path = ""
	check(panel.theme_picker.item_count >= 2, "two shipped choices")
	var stars := StarfieldBackground.make_stars()
	var old_picker := panel.theme_picker
	for i in old_picker.item_count:
		if old_picker.get_item_metadata(i) == "astra_alt":
			old_picker.item_selected.emit(i)
			break
	check_eq(UiStyle.theme_data()["id"], "astra_alt", "picker selects product pack")
	check_eq(panel._seat_labels[0].text, "Pilot 1", "live setup seat relabeled")
	check_eq(panel.theme_picker.get_item_metadata(panel.theme_picker.selected), "astra_alt", "rebuilt picker retains selection")
	check(StarfieldBackground.make_stars() != stars, "live setup rebuild uses alternate starfield")
	check_eq(main._lines.line("match_start", {"name": "P"}), "Flight roster ready. P takes the helm.", "fresh dialogue loaded")
	var style := main.theme.get_stylebox("normal", "Button") as StyleBoxFlat
	check_eq(style.bg_color, UiStyle.color("button"), "live chrome re-themed")
	var seats := panel.seats()
	main.remove_child(panel)
	panel.free()
	main._setup_panel = null
	main.begin_match(seats, null, 7)
	check_eq(main.controller.players[0].display_name, "Pilot 1", "selected seat reaches match")
	check_eq(main.controller.board.spaces[0].display_name, "Departure Dock", "selected space reaches match")
	check_eq(main.controller.board.term("hotel"), "Starbase", "selected term reaches match")
	check(main._board_view.piece_node(0) is SpacePiece, "match uses explorer Node2D")
	check(UiStyle.display_font() != ThemeDB.fallback_font, "display font loads")
	main.free()
	done()


func test_piece_motion_build_and_bankrupt_feedback() -> void:
	var main := Main.new()
	main.controller = GameSetup.new_game(7)
	main.start(null)
	var view := main._board_view
	view.size = Vector2(660, 660)
	view.queue_move(0, 0, 3)
	check_eq(view.shown_position(0), 3, "headless snaps movement")
	check_eq(view.piece_node(0).position, view.piece_state(0).point, "attached piece follows snap")
	view.animate = true
	view.queue_move(0, 3, 2)
	view.advance(0.03)
	check(view.piece_state(0).moving, "queue drives hop")
	check_eq(view.piece_node(0).position, view.piece_state(0).point, "piece follows hop")
	view.advance(10)
	view.queue_jump(0, 5, 10)
	view.advance(0.1)
	check(view.piece_state(0).lift > 0, "queue drives jail arc")
	view.advance(10)
	for kind in [&"built_house", &"built_hotel", &"sold_house", &"sold_hotel"]:
		main._on_game_event(kind, {"player": 0, "space": 1, "count": 2, "houses": 0})
	check_eq(view._building_fx.size(), 4, "build and per-street sell events produce FX including zero buildings")
	check(not view.is_animating(), "building FX do not block rules")
	view.advance_building_fx(10)
	check(view._building_fx.is_empty(), "building FX expire")
	main.controller.players[0].is_bankrupt = true
	main._on_game_event(&"bankrupt", {"player": 0, "creditor": -1})
	main._refresh()
	check(view.is_fading(0), "bankruptcy event starts fade")
	check(main._player_labels[0].text.contains("bankrupt"), "overlay chip reflects rules immediately")
	view.advance_fades(UiStyle.num("bankrupt_fade_seconds", 0.8) * 0.5)
	check(view.piece_node(0).visible and view.piece_node(0).modulate.a < 1, "piece fades before disappearing")
	view.advance_fades(10)
	check(not view.piece_node(0).visible, "fade finishes")
	view.animate = false
	view.fade_out_piece(0, 1)
	check(not view.is_fading(0), "headless bankruptcy snaps")
	view.setup(main.controller)
	check_eq(view._pieces.size(), main.controller.players.size(), "re-setup replaces pieces")
	main.free()
	done()
