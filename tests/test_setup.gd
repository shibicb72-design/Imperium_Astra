extends TestCase
## P2-SETUP: seat setup screen (scripts/ui/setup_panel.gd), GameSetup.seats_for and Main's
## setup -> match hand-off. Defaults from data/ui.json: 2 seats, seat 1 Human, seat 2 Bot,
## at least one person to start (all-bot stays possible in GameSetup for headless soak).

const SAVE_PATH := "user://test_setup.cfg"


func _panel(path: String = "") -> SetupPanel:
	var panel := SetupPanel.new()
	panel.save_path = path
	panel.setup()
	return panel


func _bots(seats: Array[Dictionary]) -> Array[bool]:
	var out: Array[bool] = []
	for s in seats:
		out.append(bool(s["is_bot"]))
	return out


func _seats_with_flags(flags: Array[bool]) -> Array[Dictionary]:
	return GameSetup.seats_for(flags)


func test_seats_for_keeps_seat_order() -> void:
	var seats := _seats_with_flags([true, false, true])
	check_eq(seats.size(), 3, "three seats")
	check_eq(_bots(seats), [true, false, true] as Array[bool], "bot flags in seat order")
	check_eq(String(seats[1]["display_name"]), "Commander 2", "names from seat_pool")
	check(_seats_with_flags([false]).is_empty(), "one seat refused (min_players 2)")
	var seven: Array[bool] = [false, false, false, false, false, false, false]
	check(_seats_with_flags(seven).is_empty(), "seven seats refused (max_players 6)")
	check_eq(_seats_with_flags([true, true]).size(), 2, "all-bot allowed in core (soak)")
	done()


func test_defaults_one_human_one_bot() -> void:
	var panel := _panel()
	check_eq(panel.count, 2, "two seats by default")
	check_eq(_bots(panel.seats()), [false, true] as Array[bool], "seat 1 human, seat 2 bot")
	check(panel.can_start(), "default can start")
	check(not panel._start_button.disabled, "Start enabled")
	check_eq(panel._seat_toggles[0].text, "Human", "seat 1 toggle")
	check_eq(panel._seat_toggles[1].text, "Bot", "seat 2 toggle")
	check(not panel._seat_rows[2].visible and not panel._seat_rows[3].visible, "seats 3-4 hidden")
	for b in [panel._start_button] + panel._count_buttons + panel._seat_toggles:
		check((b as Button).custom_minimum_size.y >= UiStyle.touch(), "'%s' touch-sized" % b.text)
	panel.free()
	done()


func test_count_and_toggles_apply() -> void:
	var panel := _panel()
	panel.set_count(4)
	check(panel._seat_rows[3].visible, "seat 4 shown")
	check(panel._count_buttons[2].button_pressed, "4 highlighted")
	panel._seat_toggles[2].pressed.emit()  # seat 3: Bot -> Human
	check_eq(panel._seat_toggles[2].text, "Human", "toggle label follows")
	check_eq(_bots(panel.seats()), [false, true, false, true] as Array[bool], "4 seats, mixed")
	panel.set_count(5)
	check_eq(panel.count, 4, "count not offered is ignored")
	panel.set_count(3)
	check_eq(panel.seats().size(), 3, "back to three")
	panel.free()
	done()


func test_start_emits_seats_and_refuses_no_humans() -> void:
	var panel := _panel()
	var got: Array = []
	panel.start_requested.connect(func(seats: Array[Dictionary]) -> void: got.append(seats))
	panel.set_bot(0, true)
	check(not panel.can_start(), "no person: cannot start")
	check(panel._start_button.disabled, "Start disabled")
	check(panel._hint_label.visible, "hint shown")
	panel.start()
	check(got.is_empty(), "start refused with zero humans")
	panel.set_bot(0, false)
	panel.set_bot(1, false)
	panel._start_button.pressed.emit()
	check_eq(got.size(), 1, "start emitted once")
	if got.size() == 1:
		check_eq(_bots(got[0]), [false, false] as Array[bool], "two people")
	panel.free()
	done()


func test_choice_persists() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var panel := _panel(SAVE_PATH)
	panel.set_count(3)
	panel.set_bot(1, false)
	panel.start()
	panel.free()
	var again := _panel(SAVE_PATH)
	check_eq(again.count, 3, "count restored")
	check_eq(_bots(again.seats()), [false, false, true] as Array[bool], "flags restored")
	again.free()
	var cfg := ConfigFile.new()
	cfg.set_value(SetupPanel.SECTION, "count", 9)
	cfg.set_value(SetupPanel.SECTION, "bots", ["x", 3])
	cfg.save(SAVE_PATH)
	var bad := _panel(SAVE_PATH)
	check_eq(bad.count, 2, "bad saved count ignored")
	check_eq(_bots(bad.seats()), [false, true] as Array[bool], "bad saved flags ignored")
	bad.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	done()


func test_main_setup_then_match() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var panel := main.show_setup(null)
	panel.save_path = ""
	check(main.controller == null, "no match before Start")
	panel.set_count(3)
	panel.set_bot(2, false)  # human, bot, human
	panel.start()
	check(main.controller != null, "Start built the match")
	if main.controller != null:
		var tc := main.controller
		check_eq(tc.players.size(), 3, "three players")
		check(not tc.players[0].is_bot and tc.players[1].is_bot and not tc.players[2].is_bot,
			"human / bot flags applied per seat")
		check(main._board_view != null, "board screen built")
	check(panel.get_parent() == null, "setup removed")
	main.free()
	panel.free()
	done()
