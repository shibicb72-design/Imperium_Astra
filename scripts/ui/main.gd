extends Control
## Local hotseat match screen: BoardView plus a HUD panel (turn, cash, status, action buttons).
## Side-by-side in landscape, stacked in portrait (phones / folded Fold). Input comes from
## touch/mouse buttons or InputMap actions only (roll_dice, buy_property, end_turn).

const BUTTON_MIN_HEIGHT := 64.0

var _controller: TurnController
var _box: BoxContainer
var _board_view: BoardView
var _turn_label: Label
var _cash_labels: Array[Label] = []
var _status_label: Label
var _roll_button: Button
var _buy_button: Button
var _pass_button: Button
var _end_button: Button
var _fine_button: Button
var _pardon_button: Button


func _ready() -> void:
	_controller = GameState.new_local_game()
	_build_ui()
	_controller.state_changed.connect(_refresh)
	_controller.status.connect(_on_status)
	resized.connect(_update_orientation)
	_update_orientation()
	if not _controller.log_lines.is_empty():
		_on_status(_controller.log_lines[-1])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("roll_dice"):
		_controller.roll()
	elif event.is_action_pressed("buy_property"):
		_controller.buy()
	elif event.is_action_pressed("end_turn"):
		_controller.end_turn()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#070b1a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)

	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	margin.add_child(_box)

	_board_view = BoardView.new()
	_board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_view.size_flags_stretch_ratio = 2.0
	_box.add_child(_board_view)
	_board_view.setup(_controller)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	_turn_label = _make_label(v, 22)
	for p in _controller.players:
		var l := _make_label(v, 18)
		l.add_theme_color_override("font_color", p.color)
		_cash_labels.append(l)
	_status_label = _make_label(v, 16)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(200, 72)

	_roll_button = _make_button(v, "Roll Dice", _controller.roll)
	_buy_button = _make_button(v, "Claim", func() -> void: _controller.buy())
	_pass_button = _make_button(v, "Pass (to auction)", _controller.decline)
	_end_button = _make_button(v, "End Turn", _controller.end_turn)
	_fine_button = _make_button(v, "Pay Brig Fine", func() -> void: _controller.pay_jail_fine())
	_pardon_button = _make_button(v, "Use Pardon Card", func() -> void: _controller.use_get_out_of_jail_card())


func _make_label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _make_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _update_orientation() -> void:
	if _box != null:
		_box.vertical = size.y > size.x


func _on_status(message: String) -> void:
	_status_label.text = message


func _refresh() -> void:
	var tc := _controller
	var p := tc.current_player()
	var phase := tc.phase
	_turn_label.text = "%s's turn%s" % [p.display_name, " (in the Brig)" if p.in_jail else ""]
	for i in tc.players.size():
		var pl := tc.players[i]
		var owned := tc.board.deeds_owned_by(pl.id).size()
		_cash_labels[i].text = "%s: $%d  | %d holdings | %s" % [
			pl.display_name, pl.cash, owned, tc.board.spaces[pl.position].display_name]
	var awaiting_roll := phase == TurnController.Phase.AWAITING_ROLL
	var deciding := phase == TurnController.Phase.AWAITING_BUY_DECISION
	_roll_button.disabled = not awaiting_roll
	_buy_button.disabled = not deciding
	_pass_button.disabled = not deciding
	if deciding:
		var deed := tc.board.deed_at(tc.pending_buy_index)
		_buy_button.text = "Claim %s ($%d)" % [tc.board.spaces[tc.pending_buy_index].display_name, deed.list_price]
		_buy_button.disabled = p.cash < deed.list_price
	else:
		_buy_button.text = "Claim"
	_end_button.disabled = phase != TurnController.Phase.AWAITING_END_TURN
	_fine_button.disabled = not (awaiting_roll and p.in_jail and p.cash >= tc.config.jail_fine)
	_pardon_button.disabled = not (awaiting_roll and p.in_jail and not p.goojf_cards.is_empty())
	_board_view.queue_redraw()
