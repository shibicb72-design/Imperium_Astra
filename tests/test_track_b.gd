extends TestCase


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
