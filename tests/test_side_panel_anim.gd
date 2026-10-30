extends TestCase
## SIDE_PANEL_B_ANIM: synchronous presentation motion, outside the tree like BoardView.

const ThemeTests := preload("res://tests/test_theme.gd")
const TIMINGS: Array[String] = ["side_popup_seconds", "side_tick_seconds", "side_glow_seconds",
	"side_badge_fade_seconds"]
var _panels: Array[SidePanel] = []
var _saved: Dictionary = {}


func teardown() -> void:
	for panel in _panels:
		panel.free()
	for key: String in _saved:
		UiStyle.data()[key] = _saved[key]
	UiStyle.reset_theme()


func _panel(compact: bool = false, moving: bool = true) -> SidePanel:
	var panel := SidePanel.new()
	panel.setup(GameSetup.new_game(1234, GameSetup.seats(1, 1)))
	_panels.append(panel)
	panel.place_in(_strip(compact))
	if moving:
		panel.animate = true
	return panel


func _strip(compact: bool) -> Rect2:
	return Rect2(0, 0, 108, 50) if compact else Rect2(0, 0, 408, 120)


func _seconds(key: String) -> float:
	return UiStyle.num(key, 0.0)


func _flags(jail: bool = false, bankrupt: bool = false, pardon: int = 0) -> Dictionary:
	return {"jail": jail, "bankrupt": bankrupt, "pardon": pardon, "bot": false}


func _white(card: SidePanel.SeatCard) -> void:
	check_eq(card.glow_frame.modulate, Color.WHITE, "glow neutral")
	check_eq(card.cash_label.modulate, Color.WHITE, "cash neutral")
	check_eq(card.worth_label.modulate, Color.WHITE, "worth neutral")
	for key: String in SidePanel.BADGE_KEYS:
		check_eq((card.badges[key] as Label).modulate, Color.WHITE, key + " neutral")
	check_eq(card.fx_layer.get_child_count(), 0, "no live popup")


func test_default_off_and_hidden_hooks_are_instant() -> void:
	var panel := _panel(false, false)
	var c := panel.cards[0]
	check(not panel.animate, "default fixture motion off")
	c.set_cash(12500, 11000)
	c.set_net_worth(125000)
	c.set_owned(3, 3)
	c.set_active(true)
	c.set_badges(_flags(true, false, 2))
	check_eq(c.cash_label.text, "$12500", "instant cash")
	check_eq(c.worth_label.text, "$125k", "instant worth")
	check_eq(c.owned_label.text, "3 deeds", "owned stays instant")
	check((c.badges.jail as Label).visible, "jail immediate")
	_white(c)
	panel.animate = true
	panel.set_panel_shown(false)
	c.set_cash(14000, 1500)
	c.set_net_worth(150000)
	c.set_badges(_flags(false, true))
	c.set_active(false)
	check_eq(c.cash_label.text, "$14000", "hidden cash")
	check_eq(c.worth_label.text, "$150k", "hidden worth")
	check((c.badges.bankrupt as Label).visible, "hidden badge state")
	_white(c)
	done()


func test_ticks_formats_retarget_repeats_and_worth() -> void:
	for compact in [false, true]:
		var panel := _panel(compact)
		var c := panel.cards[0]
		c.set_cash(9000, 0)
		c.set_cash(12500, 3500)
		var five_digits := RegEx.create_from_string("^\\$\\d{5,}$")
		for i in 12:
			panel.advance(_seconds("side_tick_seconds") / 11.0)
			if compact:
				check(five_digits.search(c.cash_label.text) == null, "compact tick stays short")
			else:
				var integer := int(c.cash_label.text.trim_prefix("$"))
				check(integer >= 9000 and integer <= 12500, "tick stays in integer interval")
				check_eq(c.cash_label.text, "$%d" % integer, "tick shows a whole number")
		check_eq(c.cash_label.text, c.cash_text(12500), "tick final form")
		c.set_cash(15000, 2500)
		panel.advance(_seconds("side_tick_seconds") * 0.25)
		var shown := c.cash_label.text
		var popup := c.fx_layer.get_child(c.fx_layer.get_child_count() - 1) as Label
		var popup_alpha := popup.modulate
		var popup_count := c.fx_layer.get_child_count()
		c.set_cash(15000, 0)
		check_eq(c.cash_label.text, shown, "zero delta keeps shown number")
		check_eq(popup.modulate, popup_alpha, "zero delta keeps popup fade")
		check_eq(c.fx_layer.get_child_count(), popup_count, "zero delta adds no popup")
		c.set_cash(8000, -7000)
		check_eq(c.cash_label.text, shown, "retarget starts at shown value")
		c.set_net_worth(125000)
		panel.advance(_seconds("side_tick_seconds") * 1.01)
		check_eq(c.cash_label.text, c.cash_text(8000), "retarget final")
		check_eq(c.worth_label.text, "$125k", "worth final")
		c.set_net_worth(160000)
		panel.advance(_seconds("side_tick_seconds") * 0.4)
		var worth_shown := c.worth_label.text
		c.set_net_worth(160000)
		check_eq(c.worth_label.text, worth_shown, "worth repeat keeps tick")
		c.set_net_worth(13000)
		check_eq(c.worth_label.text, worth_shown, "worth retarget keeps shown")
		panel.advance(_seconds("side_tick_seconds") * 1.01)
		check_eq(c.worth_label.text, "$13k", "worth retarget final")
	done()


func test_zero_delta_does_not_restart_or_cancel_tick_or_popup() -> void:
	var panel := _panel()
	var c := panel.cards[0]
	c.set_cash(1700, 200)
	panel.advance(_seconds("side_tick_seconds") * 0.7)
	c.set_cash(1700, 0)
	panel.advance(_seconds("side_tick_seconds") * 0.31)
	check_eq(c.cash_label.text, "$1700", "repeat does not restart tick clock")
	panel.advance(_seconds("side_popup_seconds") * 1.01)
	check_eq(c.fx_layer.get_child_count(), 0, "repeat does not retain popup")
	done()


func test_mode_switch_finishes_tick_same_mode_keeps_it() -> void:
	for compact in [true, false]:
		var panel := _panel(compact)
		var c := panel.cards[0]
		c.set_cash(12500, 11000)
		panel.advance(_seconds("side_tick_seconds") * 0.2)
		var shown := c.cash_label.text
		panel.place_in(_strip(compact))
		check_eq(c.cash_label.text, shown, "same mode preserves tick")
		panel.place_in(_strip(not compact))
		check_eq(c.cash_label.text, c.cash_text(12500), "switch finishes immediately")
		panel.advance(_seconds("side_tick_seconds") * 1.01)
		check_eq(c.cash_label.text, c.cash_text(12500), "switch stays final")
	done()


func test_popup_coalescing_sum_sign_color_and_removal() -> void:
	var panel := _panel()
	var c := panel.cards[0]
	check_eq(c.fx_layer.get_child_count(), 0, "no build popup")
	c.set_cash(1500, 0)
	check_eq(c.fx_layer.get_child_count(), 0, "no repeat popup")
	c.set_cash(1600, 100)
	panel.advance(_seconds("side_popup_coalesce_seconds") * 0.25)
	c.set_cash(1560, -40)
	check_eq(c.fx_layer.get_child_count(), 1, "coalesced")
	var popup := c.fx_layer.get_child(0) as Label
	check_eq(popup.text, "+$60", "sum text")
	check_eq(popup.label_settings.font_color, UiStyle.color("gain"), "sum gain color")
	check_eq(popup.label_settings.font, c.cash_label.label_settings.font, "popup card font")
	check_eq(popup.label_settings.font_size, UiStyle.font("small"), "popup font_small")
	check_eq(popup.mouse_filter, Control.MOUSE_FILTER_IGNORE, "popup ignores input")
	c.set_cash(1460, -100)
	check_eq(popup.text, "-$40", "sum crosses sign")
	check_eq(popup.label_settings.font_color, UiStyle.color("alert"), "sum loss color")
	c.set_cash(1500, 40)
	check_eq(c.fx_layer.get_child_count(), 0, "zero sum removed synchronously")
	c.set_cash(1600, 100)
	c.set_cash(1500, -100)
	check_eq(c.fx_layer.get_child_count(), 0, "+100 -100 removes")
	done()


func test_popup_lifetime_cap_separation_and_money_forms() -> void:
	for compact in [true, false]:
		var panel := _panel(compact)
		var c := panel.cards[0]
		c.set_cash(0, -12500)
		var popup := c.fx_layer.get_child(0) as Label
		check_eq(popup.text, "-$12.5k" if compact else "-$12500", "absolute loss format")
		var origin := popup.position
		panel.advance(_seconds("side_popup_seconds") * 0.1)
		check(popup.position.y < origin.y, "popup floats up")
		check(popup.modulate.a < 1.0, "popup fades")
		panel.advance(_seconds("side_popup_coalesce_seconds") * 1.01)
		c.set_cash(100, 100)
		check_eq(c.fx_layer.get_child_count(), 2, "outside window new popup")
		var oldest := c.fx_layer.get_child(0).get_instance_id()
		var cap := int(_seconds("side_popup_max_per_card"))
		for i in cap + 2:
			panel.advance(_seconds("side_popup_coalesce_seconds") * 1.01)
			c.set_cash(200 + i, 1)
			check(c.fx_layer.get_child_count() <= cap, "live popup cap")
		check_eq(c.fx_layer.get_child_count(), cap, "cap reached with live deltas")
		for child in c.fx_layer.get_children():
			check(child.get_instance_id() != oldest, "oldest removed")
		panel.advance(_seconds("side_popup_seconds") * 1.01)
		check_eq(c.fx_layer.get_child_count(), 0, "expired popups leave immediately")
	done()


func test_glow_repeat_bankruptcy_hide_and_restart() -> void:
	var tc := GameSetup.new_game(1234, GameSetup.seats(1, 1))
	var panel := SidePanel.new()
	_panels.append(panel)
	panel.setup(tc)
	panel.animate = true
	panel.show_values(tc)
	var c := panel.cards[0]
	panel.advance(_seconds("side_glow_seconds") * 0.25)
	check(c.glow_frame.modulate != Color.WHITE, "first refresh starts pulse")
	var phase := c.glow_frame.modulate
	c.set_active(true)
	check_eq(c.glow_frame.modulate, phase, "active repeat preserves phase")
	panel.set_panel_shown(false)
	check(c.glow_frame.visible, "hide retains active state")
	_white(c)
	panel.set_panel_shown(true)
	panel.advance(_seconds("side_glow_seconds") * 0.25)
	check(c.glow_frame.modulate != Color.WHITE, "show restarts pulse without refresh")
	c.set_active(false)
	check(not c.glow_frame.visible, "inactive hidden")
	check_eq(c.glow_frame.modulate, Color.WHITE, "inactive neutral")
	c.set_active(true)
	panel.advance(_seconds("side_glow_seconds") * 0.25)
	tc.players[0].is_bankrupt = true
	panel.show_values(tc)
	check(not c.glow_frame.visible, "bankrupt refresh stops pulse")
	check_eq(c.glow_frame.modulate, Color.WHITE, "bankrupt neutral")
	done()


func test_badge_show_repeat_count_and_instant_hide() -> void:
	var panel := _panel()
	var c := panel.cards[0]
	c.set_badges(_flags(true, false, 1))
	var jail := c.badges.jail as Label
	check(jail.visible, "shown at once")
	check_eq(jail.modulate.a, 0.0, "fade begins transparent")
	panel.advance(_seconds("side_badge_fade_seconds") * 0.7)
	var alpha := jail.modulate
	c.set_badges(_flags(true, false, 2))
	check_eq(jail.modulate, alpha, "repeat leaves fade")
	check((c.badges.pardon as Label).text.ends_with("x2"), "pardon count immediate")
	panel.advance(_seconds("side_badge_fade_seconds") * 0.31)
	check_eq(jail.modulate, Color.WHITE, "fade done despite repeat")
	c.set_badges(_flags(false, true))
	check(not jail.visible, "hide immediate")
	check_eq(jail.modulate, Color.WHITE, "hide neutral")
	c.set_badges(_flags())
	check_eq((c.badges.bankrupt as Label).modulate, Color.WHITE, "hide during fade neutral")
	c.set_badges({"jail": false, "bankrupt": false, "pardon": 0, "bot": true})
	check((c.badges.bot as Label).visible, "bot badge shown at once")
	panel.advance(_seconds("side_badge_fade_seconds") * 1.01)
	check_eq((c.badges.bot as Label).modulate, Color.WHITE, "bot badge fade completes")
	done()


func test_popup_and_badge_motion_stays_per_card_and_preserves_layout_nodes() -> void:
	var panel := _panel()
	var still := _panel(false, false)
	var c := panel.cards[0]
	var s := still.cards[0]
	var glow_style := c.glow_frame.get_theme_stylebox("panel") as StyleBoxFlat
	var style_color := glow_style.border_color
	var style_width := glow_style.border_width_left
	var nodes := c.get_children()
	c.set_cash(1600, 100)
	panel.cards[1].set_cash(1460, -40)
	check_eq((c.fx_layer.get_child(0) as Label).text, "+$100", "seat 1 popup isolated")
	check_eq((panel.cards[1].fx_layer.get_child(0) as Label).text, "-$40", "seat 2 popup isolated")
	c.set_badges(_flags(true, true, 2))
	s.set_badges(_flags(true, true, 2))
	for key: String in SidePanel.BADGE_KEYS:
		var badge := c.badges[key] as Label
		var other := s.badges[key] as Label
		check_eq(Rect2(badge.position, badge.size), Rect2(other.position, other.size), "fade-in reflow instant")
	c.set_badges(_flags(false, true, 2))
	s.set_badges(_flags(false, true, 2))
	for key: String in SidePanel.BADGE_KEYS:
		var badge := c.badges[key] as Label
		var other := s.badges[key] as Label
		check_eq(Rect2(badge.position, badge.size), Rect2(other.position, other.size), "hide reflow instant")
	c.set_active(true)
	panel.advance(_seconds("side_glow_seconds") * 0.25)
	check_eq(c.get_children(), nodes, "persistent card child identity and order")
	check_eq(c.glow_frame.get_theme_stylebox("panel"), glow_style, "same glow StyleBox")
	check_eq(glow_style.border_color, style_color, "seat border color unchanged")
	check_eq(glow_style.border_width_left, style_width, "active border width unchanged")
	done()


func test_hide_finishes_all_motion_and_animate_off_drains() -> void:
	for hide in [true, false]:
		var panel := _panel()
		var c := panel.cards[0]
		c.set_cash(1600, 100)
		c.set_net_worth(12500)
		c.set_badges(_flags(true))
		c.set_active(true)
		panel.advance(_seconds("side_tick_seconds") * 0.1)
		if hide:
			panel.set_panel_shown(false)
		else:
			panel.animate = false
			panel.advance(0.0)
		check_eq(c.cash_label.text, "$1600", "stop cash final")
		check_eq(c.worth_label.text, "$12.5k", "stop worth final")
		_white(c)
	done()


func test_zero_durations_are_instant_and_tunables_documented() -> void:
	for key in TIMINGS:
		_saved[key] = UiStyle.data().get(key, 0.0)
		UiStyle.data()[key] = 0.0
	var panel := _panel()
	var c := panel.cards[0]
	c.set_cash(1600, 100)
	c.set_net_worth(12500)
	c.set_active(true)
	c.set_badges(_flags(true))
	check_eq(c.cash_label.text, "$1600", "zero cash duration")
	check_eq(c.worth_label.text, "$12.5k", "zero worth duration")
	_white(c)
	var keys := TIMINGS.duplicate()
	keys.append_array(["side_popup_coalesce_seconds", "side_popup_max_per_card", "side_popup_rise", "side_glow_min_alpha"])
	for key: String in keys:
		var doc := String(UiStyle.data().get(key + "_doc", ""))
		check(doc.contains("_placeholder") and doc.ends_with("TODO Q21: tune on Fold"), key + " documented")
	done()


func test_process_steps_motion_and_layout_is_identical() -> void:
	var panel := _panel()
	var other := _panel()
	var still := _panel(false, false)
	panel.cards[0].set_cash(1600, 100)
	other.cards[0].set_cash(1600, 100)
	panel.cards[0].set_active(true)
	other.cards[0].set_active(true)
	panel._process(_seconds("side_tick_seconds") * 0.4)
	other.advance(_seconds("side_tick_seconds") * 0.4)
	check_eq(panel.cards[0].cash_label.text, other.cards[0].cash_label.text, "process steps tick")
	check_eq(panel.cards[0].glow_frame.modulate, other.cards[0].glow_frame.modulate, "process steps pulse")
	check_eq((panel.cards[0].fx_layer.get_child(0) as Label).modulate,
		(other.cards[0].fx_layer.get_child(0) as Label).modulate, "process steps popup")
	for compact in [false, true, false]:
		check_eq(panel.place_in(_strip(compact)), still.place_in(_strip(compact)), "same panel rect")
		for i in panel.cards.size():
			var c := panel.cards[i]
			var s := still.cards[i]
			check_eq(Rect2(c.position, c.size), Rect2(s.position, s.size), "same card fit")
			check_eq(c.token.position, s.token.position, "same token position")
			check_eq(c.min_size(compact), s.min_size(compact), "same minimum")
	done()


func test_gain_loss_contrast_both_packs_all_seats() -> void:
	for pack in UiStyle.theme_packs():
		UiStyle.set_theme(String(pack.id))
		var tc := GameSetup.new_game(1234, GameSetup.seats(1, 5))
		var panel := SidePanel.new()
		_panels.append(panel)
		panel.setup(tc)
		for key in ["gain", "alert"]:
			var color := UiStyle.color(key)
			check(ThemeTests.contrast(color, UiStyle.color("panel")) >= 4.5, key + " on panel")
			for c in panel.cards:
				var bg := (c.background.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
				check(ThemeTests.contrast(color, bg) >= 4.5, "%s %s seat %d" % [pack.id, key, c.player_id])
	done()


func test_main_panel_motion_never_blocks_human_or_bot_gate() -> void:
	for bot in [false, true]:
		var tc := GameSetup.new_game(1234, GameSetup.seats(1, 1))
		if bot:
			tc.current_index = 1
		var main: Main = load("res://scenes/main.tscn").instantiate()
		main.controller = tc
		main.start(null)
		main.set_anchors_preset(Control.PRESET_TOP_LEFT)
		main.size = Vector2(411, 880)
		main._update_layout()
		var board: Rect2 = main._layout()["board"]
		main._board_view.size = board.size
		main._board_view.position = board.position - main._margin.position - main._box.position
		main._refresh()
		var before := main.gate()
		check_eq(before, MatchGate.State.BOT if bot else MatchGate.State.AWAIT_DIE_TAP, "fixture gate")
		main._side_panel.animate = true
		var c := main._side_panel.cards[tc.current_index]
		var old_text := c.cash_label.text
		tc.current_player().cash += 100
		main._refresh()
		check_eq(c.fx_layer.get_child_count(), 1, "Main popup alive")
		check_eq(c.cash_label.text, old_text, "Main tick still running")
		check(not main.is_busy(), "panel does not make Main busy")
		check(not main._board_view.is_animating(), "board idle during panel motion")
		check_eq(main.gate(), before, "gate unchanged")
		main.free()
	done()
