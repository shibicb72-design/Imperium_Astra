class_name Main
extends Control
## Local hotseat match screen. BoardView plus a control column: turn header, player cash chips,
## status line, the turn action buttons (only the ones that apply), pinned Auction / Debt
## banners, then tabbed sections (Holdings, Trade, Log) filling the rest. Board above the column
## in portrait (phones, folded Fold), beside it in landscape; the board takes at most a data/ui.json
## share of the long side so controls keep room. One canvas unit is about 1 dp on mobile
## (DisplayScale). Input comes from touch/mouse buttons or InputMap actions only (roll_dice,
## buy_property, end_turn).

enum Section { HOLDINGS, TRADE, LOG }

const SECTION_NAMES: Array[String] = ["Holdings", "Trade", "Log"]
const MIN_BOARD_SIDE := 160.0

## Optional injected match (tests); otherwise a new local game from GameState.
var controller: TurnController = null

## DisplayScale factor; 0 when started without a window (tests), which keeps insets at zero.
var _scale := 0.0
var _insets := Vector4.ZERO
var _margin: MarginContainer
var _box: BoxContainer
var _side: VBoxContainer
var _board_view: BoardView
var _turn_label: Label
var _player_labels: Array[Label] = []
var _status_label: Label
var _actions: GridContainer
var _roll_button: Button
var _buy_button: Button
var _pass_button: Button
var _end_button: Button
var _fine_button: Button
var _pardon_button: Button
var _auction_panel: AuctionPanel
var _debt_panel: DebtPanel
var _tab_buttons: Array[Button] = []
var _sections: Array[Control] = []
var _section: Section = Section.HOLDINGS
var _holdings_panel: HoldingsPanel
var _trade_panel: TradePanel
var _log_label: Label
## Paces bot seats (TurnController.bot_step) so people can follow; data/ui.json bot_step_seconds.
var _bot_timer: Timer


func _ready() -> void:
	if controller != null:
		start(get_window())
	else:
		show_setup(get_window())


## Seat setup first (OPEN_QUESTIONS Q19); its Start builds the match and opens the board.
func show_setup(window: Window) -> SetupPanel:
	if window != null:
		_scale = DisplayScale.apply(window)
	theme = UiStyle.make_theme()
	var panel := SetupPanel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.setup(_scale)
	panel.start_requested.connect(func(seats: Array[Dictionary]) -> void:
		remove_child(panel)
		panel.queue_free()
		begin_match(seats, window))
	return panel


## New local match with the chosen seats (rng_seed < 0: random), then the board screen.
func begin_match(seats: Array[Dictionary], window: Window, rng_seed: int = -1) -> void:
	controller = GameSetup.new_game(rng_seed, seats)
	controller.determine_start_player()
	var gs := get_node_or_null("/root/GameState") if is_inside_tree() else null  # tests run outside the tree
	if gs != null:
		gs.controller = controller
	start(window)


## Builds the screen. Called from _ready; tests call it directly (window null: no DPI scaling).
func start(window: Window) -> void:
	if window != null:
		_scale = DisplayScale.apply(window)
	theme = UiStyle.make_theme()
	if controller == null:
		controller = GameState.new_local_game()
	_build_ui()
	_bot_timer = Timer.new()
	_bot_timer.one_shot = true
	_bot_timer.wait_time = UiStyle.num("bot_step_seconds", 0.4)
	_bot_timer.timeout.connect(_on_bot_timer)
	add_child(_bot_timer)
	controller.state_changed.connect(_refresh)
	controller.status.connect(_on_status)
	controller.turn_started.connect(func(p: Player) -> void: _holdings_panel.set_actor(p.id))
	controller.debt_started.connect(_on_debt_started)
	controller.trade_proposed.connect(func(_o: Trade.Offer) -> void: show_section(Section.TRADE))
	resized.connect(_update_layout)
	_update_layout()
	if not controller.log_lines.is_empty():
		_on_status(controller.log_lines[-1])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if controller.current_player().is_bot:
		return
	if event.is_action_pressed("roll_dice"):
		controller.roll()
	elif event.is_action_pressed("buy_property"):
		controller.buy()
	elif event.is_action_pressed("end_turn"):
		controller.end_turn()


## Board side length for the space left after margins: up to the full short side, but at most
## the data/ui.json share of the long side.
static func board_side_for(avail: Vector2) -> float:
	if avail.y > avail.x:
		return minf(avail.x, avail.y * UiStyle.num("board_max_share_portrait", 0.48))
	return minf(avail.y, avail.x * UiStyle.num("board_max_share_landscape", 0.58))


func _build_ui() -> void:
	add_child(StarfieldBackground.new())

	var m := int(UiStyle.num("screen_margin", 8.0))
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_apply_margins()

	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", m)
	_margin.add_child(_box)

	_board_view = BoardView.new()
	_board_view.size_flags_horizontal = Control.SIZE_FILL
	_board_view.size_flags_vertical = Control.SIZE_FILL
	_box.add_child(_board_view)
	_board_view.setup(controller)

	var side := VBoxContainer.new()
	_side = side
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	_box.add_child(side)

	_turn_label = UiStyle.label(side, "", "title")
	var chips := HFlowContainer.new()
	side.add_child(chips)
	for p in controller.players:
		var l := UiStyle.label(chips, "", "small")
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_color_override("font_color", p.color)
		_player_labels.append(l)
	_status_label = UiStyle.label(side, "", "small")
	_status_label.max_lines_visible = 2

	_actions = GridContainer.new()
	_actions.columns = 2
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	side.add_child(_actions)
	_roll_button = _action_button("Roll Dice", controller.roll)
	_buy_button = _action_button(controller.board.term("buy"), func() -> void: controller.buy())
	_pass_button = _action_button("Pass (to auction)", controller.decline)
	_fine_button = _action_button("Pay fine", func() -> void: controller.pay_jail_fine())
	_pardon_button = _action_button("Use " + controller.board.term("pardon"),
		func() -> void: controller.use_get_out_of_jail_card())
	_end_button = _action_button("End Turn", controller.end_turn)

	_auction_panel = AuctionPanel.new()
	_auction_panel.setup(controller)
	side.add_child(_auction_panel)
	_debt_panel = DebtPanel.new()
	_debt_panel.setup(controller)
	side.add_child(_debt_panel)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	side.add_child(tabs)
	var group := ButtonGroup.new()
	for i in SECTION_NAMES.size():
		var b := UiStyle.button(tabs, SECTION_NAMES[i], show_section.bind(i))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons.append(b)

	var holder := VBoxContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(holder)
	_holdings_panel = HoldingsPanel.new()
	_holdings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holdings_panel.setup(controller)
	_sections.append(_wrap_scroll(holder, _holdings_panel))
	_trade_panel = TradePanel.new()
	_trade_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_panel.setup(controller)
	holder.add_child(_trade_panel)
	_sections.append(_trade_panel)
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("font_size", UiStyle.font("small"))
	_sections.append(_wrap_scroll(holder, _log_label))
	show_section(Section.HOLDINGS)


func _action_button(text: String, action: Callable) -> Button:
	var b := UiStyle.button(_actions, text, action)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


func _wrap_scroll(parent: Control, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	parent.add_child(scroll)
	return scroll


func show_section(section: int) -> void:
	_section = section as Section
	for i in _sections.size():
		_sections[i].visible = i == section
		_tab_buttons[i].set_pressed_no_signal(i == section)
	if _section == Section.TRADE:
		_trade_panel.refresh()
	_update_layout()


## Margins = screen margin + safe-area insets, re-read on every layout so rotation moves them.
func _apply_margins() -> void:
	_insets = DisplayScale.safe_insets(_scale) if _scale > 0.0 else Vector4.ZERO
	var m := int(UiStyle.num("screen_margin", 8.0))
	_margin.add_theme_constant_override("margin_left", m + int(_insets.x))
	_margin.add_theme_constant_override("margin_top", m + int(_insets.y))
	_margin.add_theme_constant_override("margin_right", m + int(_insets.z))
	_margin.add_theme_constant_override("margin_bottom", m + int(_insets.w))


## In portrait the board also gives way to the control column's minimum height (banners,
## pinned trade row), so pinned buttons never fall off the bottom.
func _update_layout() -> void:
	if _box == null:
		return
	_apply_margins()
	var m := UiStyle.num("screen_margin", 8.0)
	var avail := size - Vector2(_insets.x + _insets.z + 2.0 * m, _insets.y + _insets.w + 2.0 * m)
	var portrait := avail.y > avail.x
	_box.vertical = portrait
	var board_side := board_side_for(avail)
	if portrait:
		var room := avail.y - _side.get_combined_minimum_size().y - m
		board_side = maxf(MIN_BOARD_SIDE, minf(board_side, room))
	_board_view.custom_minimum_size = Vector2(0, board_side) if portrait else Vector2(board_side, 0)


## True when board + control column minimum heights fit the screen in portrait (tests: pinned
## rows stay on screen).
func side_fits() -> bool:
	if not _box.vertical:
		return true
	var m := UiStyle.num("screen_margin", 8.0)
	var avail_y := size.y - _insets.y - _insets.w - 2.0 * m
	return _board_view.custom_minimum_size.y + m + _side.get_combined_minimum_size().y <= avail_y + 0.5


## The debtor (maybe not the current player) becomes the Holdings actor so they can raise funds.
func _on_debt_started(debtor: Player, _creditor_id: int, _amount: int) -> void:
	_holdings_panel.set_actor(debtor.id)
	show_section(Section.HOLDINGS)


## Starts the bot timer when a bot must act (only in the live tree; tests drive bots directly).
func _schedule_bot() -> void:
	if is_inside_tree() and _bot_timer.is_stopped() and controller.bot_actor() >= 0:
		_bot_timer.start()


func _on_bot_timer() -> void:
	if controller.bot_step():  # a failed step waits for the next state change instead of spinning
		_schedule_bot()


func _on_status(message: String) -> void:
	_status_label.text = message


func _refresh() -> void:
	var tc := controller
	var p := tc.current_player()
	var phase := tc.phase
	_turn_label.text = "%s's turn%s" % [p.display_name, " (in %s)" % tc.board.term("jail") if p.in_jail else ""]
	if phase == TurnController.Phase.GAME_OVER:
		_turn_label.text = "Game over"
	for i in tc.players.size():
		var pl := tc.players[i]
		var mark := "> " if pl == p else ""
		var bot := " (bot)" if pl.is_bot else ""
		if pl.is_bankrupt:
			_player_labels[i].text = "%s%s: bankrupt" % [pl.display_name, bot]
		else:
			_player_labels[i].text = "%s%s%s $%d" % [mark, pl.display_name, bot, pl.cash]
	# A bot's own-turn buttons stay hidden; the bot timer plays for it.
	var awaiting_roll := phase == TurnController.Phase.AWAITING_ROLL and not p.is_bot
	var deciding := phase == TurnController.Phase.AWAITING_BUY_DECISION and not p.is_bot
	_roll_button.visible = awaiting_roll
	_roll_button.text = "Roll for doubles" if p.in_jail else "Roll Dice"
	_buy_button.visible = deciding
	_pass_button.visible = deciding
	if deciding:
		var s := tc.board.spaces[tc.pending_buy_index]
		_buy_button.text = "%s %s $%d" % [tc.board.term("buy"), s.short_name, s.deed.list_price]
		_buy_button.disabled = p.cash < s.deed.list_price
	_end_button.visible = phase == TurnController.Phase.AWAITING_END_TURN and not p.is_bot
	_fine_button.visible = awaiting_roll and p.in_jail
	_fine_button.text = "Pay %s $%d" % [tc.board.term("jail_fine"), tc.config.jail_fine]
	_fine_button.disabled = p.cash < tc.config.jail_fine
	_pardon_button.visible = awaiting_roll and p.in_jail and not p.goojf_cards.is_empty()
	_actions.visible = _actions.get_children().any(func(c: Node) -> bool: return (c as Control).visible)
	_auction_panel.refresh()
	_debt_panel.refresh()
	_holdings_panel.refresh()
	_trade_panel.refresh()
	_tab_buttons[Section.TRADE].text = "Trade (offer)" if _trade_panel.has_open_offer() else "Trade"
	var lines := tc.log_lines.slice(-int(UiStyle.num("log_lines_shown", 60.0)))
	lines.reverse()
	_log_label.text = "\n".join(PackedStringArray(lines))
	_board_view.queue_redraw()
	_update_layout()
	_schedule_bot()
