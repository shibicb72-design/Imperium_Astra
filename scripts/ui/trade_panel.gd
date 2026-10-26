class_name TradePanel
extends VBoxContainer
## Hotseat trade controls (core module: Trade). Official rules allow trades at any time, so any
## two active commanders can be picked. With no open offer the panel builds a draft (cash, deeds,
## pardon cards on each side); with an open offer the receiver accepts, rejects or counters and
## the proposer may withdraw. Enable states and the problem line come from Trade.validate.
## Layout: pickers, a scrolling body, then the problem line (hidden while empty) and action row
## pinned at the bottom so Accept / Reject / Withdraw / Back are always on screen. The pickers share
## one row, or stack where Main finds the overlay too narrow for it (set_stacked); in the body the
## cash steps and long deed names wrap where a row would be wider than the overlay (Q22 Fold).
## Main alone shows or hides this section (Q21: a refresh never re-shows Trade beside Holdings or Log).

var _controller: TurnController
var _from_picker: OptionButton
var _to_picker: OptionButton
var _pickers: BoxContainer
var _body: VBoxContainer
var _problem: Label
var _actions: HFlowContainer
var _send_button: Button
var _draft: Trade.Offer
var _cash_steps: Array[int] = []
## True while the draft is a counter to the open offer (pickers are locked).
var _countering := false
## Offer the body last faded in for, so only a new or closed offer animates.
var _faded_offer: Trade.Offer = null


func setup(controller: TurnController) -> void:
	_controller = controller
	_cash_steps = UiStyle.int_list("trade_cash_steps", [10, 100])
	add_theme_constant_override("separation", 6)
	_pickers = BoxContainer.new()
	add_child(_pickers)
	_from_picker = _make_picker(_pickers)
	var to_label := UiStyle.label(_pickers, "to", "body")
	to_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	to_label.autowrap_mode = TextServer.AUTOWRAP_OFF  # one word: never a 1 px column of letters (Q22)
	_to_picker = _make_picker(_pickers)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_problem = UiStyle.label(self, "", "small")
	_problem.add_theme_color_override("font_color", UiStyle.color("alert"))
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


## Width the pickers need side by side (Main stacks them where the overlay is narrower).
func picker_row_width() -> float:
	var w := float(_pickers.get_theme_constant("separation") * (_pickers.get_child_count() - 1))
	for c in _pickers.get_children():
		w += (c as Control).get_combined_minimum_size().x
	return w


## Pickers in one row, or stacked (from, "to", to) so they never crowd or clip (Fold cover).
func set_stacked(stacked: bool) -> void:
	if _pickers.vertical != stacked:
		_pickers.vertical = stacked


func refresh() -> void:
	var tc := _controller
	for parent: Control in [_body, _actions]:
		for c in parent.get_children():
			parent.remove_child(c)
			c.queue_free()
	_send_button = null
	_set_problem("")
	if tc.phase == TurnController.Phase.GAME_OVER:  # nothing to trade; Main owns the visibility
		return
	for p in tc.players:
		_from_picker.set_item_disabled(_from_picker.get_item_index(p.id), p.is_bankrupt)
		_to_picker.set_item_disabled(_to_picker.get_item_index(p.id), p.is_bankrupt)
	if tc.trade_offer != _faded_offer:  # a new or closed offer fades in (P4-DEMO panel motion)
		_faded_offer = tc.trade_offer
		UiFx.fade_in(_body, UiStyle.num("panel_fade_seconds", 0.18))
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
	_set_problem(tc.trade_problem(offer))
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
		_set_problem("Pick two different %s." % tc.board.term("players"))
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
## The row keeps the - steps, the field and the + steps in one line where it fits; narrower, the +
## steps wrap below as a pair (Q22: the row never sets the overlay's width).
func _add_side(p: Player, is_from: bool) -> void:
	var tc := _controller
	UiStyle.label(_body, "%s gives (cash $%d):" % [p.display_name, p.cash], "button")
	var cash_row := HFlowContainer.new()
	_body.add_child(cash_row)
	var minus := HBoxContainer.new()
	var plus := HBoxContainer.new()
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
		UiStyle.button(minus, "-%d" % step, func() -> void: cash.value -= step)
	for step in _cash_steps:
		UiStyle.button(plus, "+%d" % step, func() -> void: cash.value += step)
	for part: Control in [minus, cash, plus]:
		cash_row.add_child(part)
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


## The problem line, hidden while empty so it takes no room in the pinned rows (Q22 Fold).
func _set_problem(text: String) -> void:
	_problem.text = text
	_problem.visible = not text.is_empty()


func _update_problem() -> void:
	var problem := _controller.trade_problem(_draft)
	_set_problem("" if _draft.is_empty() else problem)
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
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long name wraps, never widens the overlay (Q22)
	c.custom_minimum_size = Vector2(0, UiStyle.touch())
	c.add_theme_font_size_override("font_size", UiStyle.font("body"))
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.toggled.connect(action)
	_body.add_child(c)
	return c
