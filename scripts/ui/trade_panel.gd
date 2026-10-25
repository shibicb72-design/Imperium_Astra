class_name TradePanel
extends VBoxContainer
## Hotseat trade controls (core module: Trade). Official rules allow trades at any time, so any
## two active commanders can be picked. With no open offer the panel builds a draft (cash, deeds,
## pardon cards on each side); with an open offer the receiver accepts, rejects or counters and
## the proposer may withdraw. Enable states and the problem line come from Trade.validate.

const BUTTON_MIN_HEIGHT := 48.0

var _controller: TurnController
var _from_picker: OptionButton
var _to_picker: OptionButton
var _body: VBoxContainer
var _problem: Label
var _send_button: Button
var _draft: Trade.Offer
## True while the draft is a counter to the open offer (pickers are locked).
var _countering := false


func setup(controller: TurnController) -> void:
	_controller = controller
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Trade"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	var pickers := HFlowContainer.new()
	add_child(pickers)
	_from_picker = _make_picker(pickers)
	_to_picker = _make_picker(pickers)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	add_child(_body)
	_problem = _add_label(self, "")
	_problem.add_theme_color_override("font_color", Color("#ff9a8a"))
	_new_draft(0, 1 if controller.players.size() > 1 else 0)


func _make_picker(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	o.add_theme_font_size_override("font_size", 18)
	for p in _controller.players:
		o.add_item(p.display_name, p.id)
	o.item_selected.connect(_on_pick)
	parent.add_child(o)
	return o


func _on_pick(_index: int) -> void:
	_new_draft(_from_picker.get_selected_id(), _to_picker.get_selected_id())


func _new_draft(from_id: int, to_id: int) -> void:
	_countering = false
	_draft = Trade.propose(from_id, to_id)
	refresh()


func refresh() -> void:
	var tc := _controller
	for c in _body.get_children():
		_body.remove_child(c)
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
	_from_picker.disabled = true
	_to_picker.disabled = true
	_add_label(_body, "%s offers %s:" % [a.display_name, b.display_name])
	_add_label(_body, "%s gives: %s" % [a.display_name, _describe(offer.give_cash, offer.give_deeds, offer.give_cards)])
	_add_label(_body, "%s gives: %s" % [b.display_name, _describe(offer.get_cash, offer.get_deeds, offer.get_cards)])
	var interest := Trade.interest_due(tc.board, offer.give_deeds, tc.config)
	if interest > 0:
		_add_label(_body, "%s also pays the Bank $%d mortgage interest." % [b.display_name, interest])
	interest = Trade.interest_due(tc.board, offer.get_deeds, tc.config)
	if interest > 0:
		_add_label(_body, "%s also pays the Bank $%d mortgage interest." % [a.display_name, interest])
	_problem.text = tc.trade_problem(offer)
	var row := HFlowContainer.new()
	_body.add_child(row)
	_add_button(row, "Accept (%s)" % b.display_name, _problem.text.is_empty(),
		func() -> void: tc.accept_trade(b.id))
	_add_button(row, "Reject (%s)" % b.display_name, true, func() -> void: tc.reject_trade(b.id))
	_add_button(row, "Counter (%s)" % b.display_name, true, _start_counter)
	_add_button(row, "Withdraw (%s)" % a.display_name, true, func() -> void: tc.cancel_trade(a.id))


func _show_draft() -> void:
	var tc := _controller
	var a := tc.players[_draft.from_id]
	var b := tc.players[_draft.to_id]
	if a.id == b.id:
		_problem.text = "Pick two different commanders."
		return
	_add_side(a, true)
	_add_side(b, false)
	var row := HFlowContainer.new()
	_body.add_child(row)
	_send_button = _add_button(row, "Send counter" if _countering else "Propose", false, _send)
	if _countering:
		_add_button(row, "Back", true, _cancel_counter)
	_update_problem()


## One side of the draft: cash spin box, tradable deeds and pardon cards as check boxes.
func _add_side(p: Player, is_from: bool) -> void:
	var tc := _controller
	_add_label(_body, "%s gives:" % p.display_name)
	var cash := SpinBox.new()
	cash.prefix = "$"
	cash.max_value = p.cash
	cash.value = _draft.give_cash if is_from else _draft.get_cash
	cash.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	cash.value_changed.connect(func(v: float) -> void:
		if is_from:
			_draft.give_cash = int(v)
		else:
			_draft.get_cash = int(v)
		_update_problem())
	_body.add_child(cash)
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
		_add_check("Pardon card (%s)" % tc.board.term(String(deck_id)), on, true, func(checked: bool) -> void:
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
		parts.append("pardon card (%s)" % _controller.board.term(String(id)))
	return "nothing" if parts.is_empty() else ", ".join(parts)


func _add_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _add_check(text: String, pressed: bool, enabled: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.disabled = not enabled
	c.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(action)
	_body.add_child(c)
	return c


func _add_button(parent: Control, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
