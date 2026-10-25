class_name TradePanel
extends VBoxContainer
## Hotseat trade controls (core module: Trade). Official rules allow trades at any time, so any
## two active commanders can be picked. With no open offer the panel builds a draft (cash, deeds,
## pardon cards on each side); with an open offer the receiver accepts, rejects or counters and
## the proposer may withdraw. Enable states and the problem line come from Trade.validate.
## Layout: pickers, a scrolling body, then the problem line and action row pinned at the bottom
## so Accept / Reject / Withdraw / Back are always on screen.

const PROBLEM_COLOR := Color("#ff9a8a")

var _controller: TurnController
var _from_picker: OptionButton
var _to_picker: OptionButton
var _body: VBoxContainer
var _problem: Label
var _actions: HFlowContainer
var _send_button: Button
var _draft: Trade.Offer
var _cash_steps: Array[int] = []
## True while the draft is a counter to the open offer (pickers are locked).
var _countering := false


func setup(controller: TurnController) -> void:
	_controller = controller
	_cash_steps = UiStyle.int_list("trade_cash_steps", [10, 100])
	add_theme_constant_override("separation", 6)
	var pickers := HBoxContainer.new()
	add_child(pickers)
	_from_picker = _make_picker(pickers)
	UiStyle.label(pickers, "to", "body")
	_to_picker = _make_picker(pickers)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_problem = UiStyle.label(self, "", "small")
	_problem.add_theme_color_override("font_color", PROBLEM_COLOR)
	_actions = HFlowContainer.new()
	add_child(_actions)
	_new_draft(0, 1 if controller.players.size() > 1 else 0)


func _make_picker(parent: Control) -> OptionButton:
	var o := UiStyle.picker(parent)
	o.custom_minimum_size.x = UiStyle.touch() * 2.0
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in _controller.players:
		o.add_item(p.display_name, p.id)
	o.item_selected.connect(_on_pick)
	return o


func _on_pick(_index: int) -> void:
	_new_draft(_from_picker.get_selected_id(), _to_picker.get_selected_id())


func _new_draft(from_id: int, to_id: int) -> void:
	_countering = false
	_draft = Trade.propose(from_id, to_id)
	refresh()


## True when an offer is waiting for an answer (main screen flags the Trade tab).
func has_open_offer() -> bool:
	return _controller.trade_offer != null


func refresh() -> void:
	var tc := _controller
	for parent: Control in [_body, _actions]:
		for c in parent.get_children():
			parent.remove_child(c)
			c.queue_free()
	_send_button = null
	_problem.text = ""
	visible = tc.phase != TurnController.Phase.GAME_OVER
	if not visible:
		return
	for p in tc.players:
		_from_picker.set_item_disabled(_from_picker.get_item_index(p.id), p.is_bankrupt)
		_to_picker.set_item_disabled(_to_picker.get_item_index(p.id), p.is_bankrupt)
	if tc.trade_offer != null and not _countering:
		_show_open_offer(tc.trade_offer)
		return
	if tc.trade_offer == null and _countering:
		_countering = false
	_from_picker.select(_from_picker.get_item_index(_draft.from_id))
	_to_picker.select(_to_picker.get_item_index(_draft.to_id))
	_from_picker.disabled = _countering
	_to_picker.disabled = _countering
	_show_draft()


func _show_open_offer(offer: Trade.Offer) -> void:
	var tc := _controller
	var a := tc.players[offer.from_id]
	var b := tc.players[offer.to_id]
	_from_picker.select(_from_picker.get_item_index(offer.from_id))
	_to_picker.select(_to_picker.get_item_index(offer.to_id))
	_from_picker.disabled = true
	_to_picker.disabled = true
	UiStyle.label(_body, "%s offers %s:" % [a.display_name, b.display_name], "button")
	UiStyle.label(_body, "%s gives: %s" % [a.display_name, _describe(offer.give_cash, offer.give_deeds, offer.give_cards)])
	UiStyle.label(_body, "%s gives: %s" % [b.display_name, _describe(offer.get_cash, offer.get_deeds, offer.get_cards)])
	var interest := Trade.interest_due(tc.board, offer.give_deeds, tc.config)
	if interest > 0:
		UiStyle.label(_body, "%s also pays %s $%d mortgage interest." % [b.display_name, tc.board.term("bank"), interest])
	interest = Trade.interest_due(tc.board, offer.get_deeds, tc.config)
	if interest > 0:
		UiStyle.label(_body, "%s also pays %s $%d mortgage interest." % [a.display_name, tc.board.term("bank"), interest])
	_problem.text = tc.trade_problem(offer)
	UiStyle.button(_actions, "Accept (%s)" % b.display_name, func() -> void: tc.accept_trade(b.id),
		_problem.text.is_empty())
	UiStyle.button(_actions, "Reject (%s)" % b.display_name, func() -> void: tc.reject_trade(b.id))
	UiStyle.button(_actions, "Counter (%s)" % b.display_name, _start_counter)
	UiStyle.button(_actions, "Withdraw (%s)" % a.display_name, func() -> void: tc.cancel_trade(a.id))


func _show_draft() -> void:
	var tc := _controller
	var a := tc.players[_draft.from_id]
	var b := tc.players[_draft.to_id]
	if a.id == b.id:
		_problem.text = "Pick two different commanders."
		return
	_add_side(a, true)
	_body.add_child(HSeparator.new())
	_add_side(b, false)
	_send_button = UiStyle.button(_actions, "Send counter" if _countering else "Propose", _send, false)
	if _countering:
		UiStyle.button(_actions, "Back", _cancel_counter)
	else:
		UiStyle.button(_actions, "Clear", func() -> void: _new_draft(_draft.from_id, _draft.to_id))
	_update_problem()


## One side of the draft: cash field with +/- steps, tradable deeds and pardon cards as check boxes.
func _add_side(p: Player, is_from: bool) -> void:
	var tc := _controller
	UiStyle.label(_body, "%s gives (cash $%d):" % [p.display_name, p.cash], "button")
	var cash_row := HBoxContainer.new()
	_body.add_child(cash_row)
	# Cash may have dropped since the draft was built; keep the draft in line with the field.
	if is_from:
		_draft.give_cash = mini(_draft.give_cash, p.cash)
	else:
		_draft.get_cash = mini(_draft.get_cash, p.cash)
	var cash := SpinBox.new()
	cash.prefix = "$"
	cash.max_value = p.cash
	cash.value = _draft.give_cash if is_from else _draft.get_cash
	cash.custom_minimum_size = Vector2(UiStyle.touch() * 2.0, UiStyle.touch())
	cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash.value_changed.connect(func(v: float) -> void:
		if is_from:
			_draft.give_cash = int(v)
		else:
			_draft.get_cash = int(v)
		_update_problem())
	for k in range(_cash_steps.size() - 1, -1, -1):
		var step := _cash_steps[k]
		UiStyle.button(cash_row, "-%d" % step, func() -> void: cash.value -= step)
	cash_row.add_child(cash)
	for step in _cash_steps:
		UiStyle.button(cash_row, "+%d" % step, func() -> void: cash.value += step)
	var deeds: Array[int] = _draft.give_deeds if is_from else _draft.get_deeds
	for deed in tc.board.deeds_owned_by(p.id):
		var i := deed.space_index
		var s := tc.board.spaces[i]
		var text := s.display_name + (" (mortgaged)" if deed.is_mortgaged else "")
		var box := _add_check(text, deeds.has(i), Trade.can_trade_deed(tc.board, p.id, i),
			func(on: bool) -> void:
				if on and not deeds.has(i):
					deeds.append(i)
				elif not on:
					deeds.erase(i)
				_update_problem())
		if s.space_type == Space.Type.STREET:
			var g: Dictionary = tc.board.group_info.get(deed.color_group_id, {})
			box.add_theme_color_override("font_color", g.get("color", Color.WHITE))
	var cards: Array[StringName] = _draft.give_cards if is_from else _draft.get_cards
	var picked := cards.duplicate()
	for k in p.goojf_cards.size():
		var deck_id := p.goojf_cards[k].deck_id
		var on := picked.has(deck_id)
		if on:
			picked.erase(deck_id)
		_add_check("%s (%s)" % [tc.board.term("pardon"), tc.board.term(String(deck_id))], on, true,
			func(checked: bool) -> void:
				if checked:
					cards.append(deck_id)
				else:
					cards.erase(deck_id)
				_update_problem())


func _send() -> void:
	var tc := _controller
	var ok := tc.counter_trade(_draft) if _countering else tc.propose_trade(_draft)
	if ok:
		_countering = false
		_draft = Trade.propose(_draft.from_id, _draft.to_id)
	refresh()


func _start_counter() -> void:
	_draft = Trade.mirror(_controller.trade_offer)
	_countering = true
	refresh()


func _cancel_counter() -> void:
	_countering = false
	_draft = Trade.propose(_draft.from_id, _draft.to_id)
	refresh()


func _update_problem() -> void:
	var problem := _controller.trade_problem(_draft)
	_problem.text = "" if _draft.is_empty() else problem
	if _send_button != null:
		_send_button.disabled = not problem.is_empty()


func _describe(cash: int, deeds: Array[int], cards: Array[StringName]) -> String:
	var parts: Array[String] = []
	if cash > 0:
		parts.append("$%d" % cash)
	for i in deeds:
		var deed := _controller.board.deed_at(i)
		parts.append(_controller.board.spaces[i].display_name + (" (mortgaged)" if deed.is_mortgaged else ""))
	for id in cards:
		parts.append("%s (%s)" % [_controller.board.term("pardon"), _controller.board.term(String(id))])
	return "nothing" if parts.is_empty() else ", ".join(parts)


func _add_check(text: String, pressed: bool, enabled: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.disabled = not enabled
	c.custom_minimum_size = Vector2(0, UiStyle.touch())
	c.add_theme_font_size_override("font_size", UiStyle.font("body"))
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.toggled.connect(action)
	_body.add_child(c)
	return c
