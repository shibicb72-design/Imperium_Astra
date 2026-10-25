class_name TurnPanel
extends PanelContainer
## Post-move and jail turn panel (P5-FEEL Dig 5, OPEN_QUESTIONS Q23-Q25, Q28): the deciding seat's
## name and cash, a context line (the space on offer, or the jail), then the options
## MatchGate.PANEL_SLOTS lists for the gate state, each only when legal. GAME_OVER shows only the
## winner. Floats over the match screen: Main places it with rect_for() and the board never
## resizes for it. Never calls the controller: a press emits slot_pressed and Main applies the gate.

signal slot_pressed(slot: StringName)

## Button child order; refresh() moves the shown ones into PANEL_SLOTS order.
const SLOT_ORDER: Array[StringName] = [&"buy", &"skip", &"fine", &"pardon", &"action", &"end_turn"]
const GAP := 6

var _controller: TurnController
var _name: Label
var _info: Label
var _grid: GridContainer
var _buttons: Dictionary = {}
var _accepting_input := false
var _animate := false


func setup(controller: TurnController) -> void:
	_controller = controller
	visible = false
	add_theme_stylebox_override("panel", UiStyle.card_style(UiStyle.color("accent")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", GAP)
	add_child(v)
	_name = UiStyle.label(v, "", "title")
	_info = UiStyle.label(v, "", "small")
	for l: Label in [_name, _info]:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	v.add_child(_grid)
	for slot in SLOT_ORDER:
		var b := UiStyle.button(_grid, "", _on_slot.bind(slot))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.visible = false
		_buttons[slot] = b


func _on_slot(slot: StringName) -> void:
	if offers(slot):
		slot_pressed.emit(slot)


## Cosmetic fade only; the gate owns legality. Disable input before a fade-out keeps us visible.
func hide_panel() -> void:
	_accepting_input = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b: Button in _buttons.values():
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFx.set_shown(self, false, UiStyle.num("turn_panel_exit_seconds", 0.12) if _animate else 0.0)


## Shows the panel for gate `state` (hidden when the state has no options, except GAME_OVER) unless
## `suppressed` (the Action view is open).
func refresh(state: MatchGate.State, suppressed: bool = false, animated: bool = false) -> void:
	_animate = animated
	var slots := MatchGate.panel_slots(state)
	var shown := not suppressed and (not slots.is_empty() or state == MatchGate.State.GAME_OVER)
	if not shown:
		hide_panel()
		return
	_accepting_input = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiFx.set_shown(self, true, UiStyle.num("turn_panel_enter_seconds", 0.18) if _animate else 0.0)
	var tc := _controller
	var who: Player = winner(tc) if state == MatchGate.State.GAME_OVER else _decider()
	if state == MatchGate.State.GAME_OVER:
		_name.text = "%s wins!" % who.display_name if who != null else "Game over"
	else:
		_name.text = "%s  $%d" % [who.display_name, who.cash]
	_name.add_theme_color_override("font_color", who.color.lerp(Color.WHITE, 0.25) if who != null else UiStyle.color("accent"))
	_info.text = ""
	if state == MatchGate.State.BUY:
		_info.text = tc.board.spaces[tc.pending_buy_index].display_name
	elif state == MatchGate.State.JAIL_SET:
		_info.text = "In %s: tap the dice to roll for doubles" % tc.board.term("jail")
	_info.visible = _info.text != ""
	for slot: StringName in SLOT_ORDER:
		var b: Button = _buttons[slot]
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.visible = slot in slots and slot_shown(slot)
		if b.visible:
			b.text = slot_text(slot)
			b.disabled = not slot_enabled(slot)
	for i in slots.size():
		_grid.move_child(_buttons[slots[i]], i)


## The seat the panel serves (TurnController.deciding_player(); the current player in every panel
## state), or null at game over.
func _decider() -> Player:
	var id := _controller.deciding_player()
	return _controller.players[id] if id >= 0 else null


## Whether `slot` applies to the deciding seat right now (only the pardon depends on holdings).
func slot_shown(slot: StringName) -> bool:
	var p := _decider()
	if p == null:
		return false
	if slot == &"pardon":
		return not p.goojf_cards.is_empty()
	return true


## Whether `slot` can be paid for: Buy and the jail fine are disabled while cash is short.
func slot_enabled(slot: StringName) -> bool:
	var tc := _controller
	var p := _decider()
	if p == null:
		return false
	match slot:
		&"buy":
			return tc.pending_buy_index >= 0 and p.cash >= tc.board.deed_at(tc.pending_buy_index).list_price
		&"fine":
			return p.cash >= tc.config.jail_fine
	return true


## Q23 labels: themed terms for Buy, the jail fine and the pardon; Buy shows the price.
func slot_text(slot: StringName) -> String:
	var tc := _controller
	match slot:
		&"buy":
			var price := "" if tc.pending_buy_index < 0 else " $%d" % tc.board.deed_at(tc.pending_buy_index).list_price
			return tc.board.term("buy") + price
		&"skip":
			return "Skip"
		&"fine":
			return "Pay %s $%d" % [tc.board.term("jail_fine"), tc.config.jail_fine]
		&"pardon":
			return "Use " + tc.board.term("pardon")
		&"action":
			return "Action"
		&"end_turn":
			return "End Turn"
	return String(slot)


func button(slot: StringName) -> Button:
	return _buttons[slot]


## True when the panel is up and `slot`'s button is visible and enabled.
func offers(slot: StringName) -> bool:
	var b: Button = _buttons[slot]
	return _accepting_input and visible and b.visible and not b.disabled


func set_columns(columns: int) -> void:
	_grid.columns = columns


## Panel height with `columns` button columns (the name and context lines stay as they are).
func height_for(columns: int) -> float:
	var shown := 0
	for b: Button in _buttons.values():
		shown += 1 if b.visible else 0
	var rows := ceili(float(shown) / maxi(1, columns))
	var grid := rows * UiStyle.touch() + maxi(0, rows - 1) * GAP
	return get_combined_minimum_size().y - _grid.get_combined_minimum_size().y + grid


## The only seat not bankrupt, or null.
static func winner(tc: TurnController) -> Player:
	var alive := tc.players.filter(func(p: Player) -> bool: return not p.is_bankrupt)
	return alive[0] if alive.size() == 1 else null


## Width from which the buttons sit in two columns (data/ui.json turn_panel_two_column_width).
static func two_column_width() -> float:
	return UiStyle.num("turn_panel_two_column_width", 288.0)


## Where the panel floats, in the caller's coordinates (A1.5: the board never moves for it): the
## free band after the board (below it in portrait, right of it in landscape) when it is wide and
## tall enough, else the board center above the banner, else below it, so it stays clear of
## `banner` whenever one of those fits. It never covers `avoid` (the live die's hit rect in the jail
## set; empty otherwise): an area holding it keeps only its part below it. When nothing fits, the
## bottom of the play area, below `avoid` even if that covers the banner. `height_one` /
## `height_two`: heights with one / two button columns. Width: data/ui.json turn_panel_min_width ..
## turn_panel_max_width.
static func rect_for(play: Rect2, board: Rect2, banner: Rect2, height_one: float, height_two: float,
		avoid: Rect2 = Rect2()) -> Rect2:
	var pad := UiStyle.num("screen_margin", 8.0)
	var max_w := UiStyle.num("turn_panel_max_width", 432.0)
	var cell := board.size.x / BoardView.GRID
	var inner := Rect2(board.position + Vector2(cell, cell), Vector2(cell, cell) * (BoardView.GRID - 2))
	var band := Rect2(board.end.x, play.position.y, play.end.x - board.end.x, play.size.y)
	if play.size.y > play.size.x:
		band = Rect2(play.position.x, board.end.y, play.size.x, play.end.y - board.end.y)
	var areas: Array[Rect2] = [band,
		Rect2(inner.position.x, inner.position.y, inner.size.x, banner.position.y - inner.position.y),
		Rect2(inner.position.x, banner.end.y, inner.size.x, inner.end.y - banner.end.y)]
	for area in areas:
		var a := area
		if avoid.has_area() and a.intersects(avoid):
			a = Rect2(a.position.x, avoid.end.y, a.size.x, a.end.y - avoid.end.y)
		a = a.grow(-pad)
		var w := minf(a.size.x, max_w)
		if w < UiStyle.num("turn_panel_min_width", 192.0):
			continue
		var h := height_two if w >= two_column_width() else height_one
		if h <= a.size.y:
			return Rect2(a.get_center().x - w * 0.5, a.position.y + (a.size.y - h) * 0.5, w, h)
	var fw := clampf(play.size.x - 2.0 * pad, 0.0, max_w)
	var fh := height_two if fw >= two_column_width() else height_one
	var x := clampf(board.get_center().x - fw * 0.5, play.position.x + pad, play.end.x - pad - fw)
	var y := play.end.y - pad - fh
	if avoid.has_area():
		y = maxf(y, avoid.end.y + pad)
	return Rect2(x, y, fw, fh)
