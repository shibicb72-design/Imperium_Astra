class_name HoldingsPanel
extends VBoxContainer
## Build / sell / mortgage controls (core modules: Building, Mortgage). Official rules allow these
## at any time, so in hotseat play any commander can be picked as the actor. One card per deed
## (group color on the left edge); rows are rebuilt on every refresh and enable states come
## straight from the module checks. The main screen puts this panel in a scroll list.

var _controller: TurnController
var _actor_picker: OptionButton
var _summary: Label
var _rows: VBoxContainer
var _actor_id: int = 0


func setup(controller: TurnController) -> void:
	_controller = controller
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	add_child(top)
	UiStyle.label(top, "Acting:", "body")
	_actor_picker = UiStyle.picker(top)
	_actor_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in controller.players:
		_actor_picker.add_item(p.display_name, p.id)
	_actor_picker.item_selected.connect(_on_actor_selected)
	_summary = UiStyle.label(self, "", "small")
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	add_child(_rows)
	set_actor(controller.current_player().id)


func _on_actor_selected(index: int) -> void:
	set_actor(_actor_picker.get_item_id(index))


func set_actor(player_id: int) -> void:
	_actor_id = player_id
	_actor_picker.select(_actor_picker.get_item_index(player_id))
	refresh()


func actor_id() -> int:
	return _actor_id


func refresh() -> void:
	var tc := _controller
	for p in tc.players:
		_actor_picker.set_item_disabled(_actor_picker.get_item_index(p.id), p.is_bankrupt)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if not tc.can_manage(_actor_id):
		_summary.text = ""
		UiStyle.label(_rows, "No actions available.")
		return
	var p := tc.players[_actor_id]
	var deeds := tc.board.deeds_owned_by(p.id)
	_summary.text = "Cash $%d  |  %d holdings" % [p.cash, deeds.size()]
	if deeds.is_empty():
		UiStyle.label(_rows, "No holdings yet.")
	for deed in deeds:
		_add_deed_card(p, deed)
	for gid: StringName in tc.board.color_groups:
		if tc.board.owns_full_group(p.id, gid) and Building.group_has_buildings(tc.board, gid):
			var group_name := String(tc.board.group_info.get(gid, {}).get("display_name", gid))
			UiStyle.button(_rows, "Sell all buildings: %s" % group_name,
				func() -> void: tc.sell_group_buildings(p.id, gid))


func _add_deed_card(p: Player, deed: PropertyDeed) -> void:
	var tc := _controller
	var board := tc.board
	var s := board.spaces[deed.space_index]
	var accent := UiStyle.color("panel_border")
	if s.space_type == Space.Type.STREET:
		accent = board.group_info.get(deed.color_group_id, {}).get("color", accent)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.card_style(accent))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	_rows.add_child(card)
	var v := VBoxContainer.new()
	card.add_child(v)
	var state := ""
	if deed.has_hotel:
		state = " - %s" % board.term("hotel")
	elif deed.houses > 0:
		state = " - %d %s" % [deed.houses, board.term("houses") if deed.houses > 1 else board.term("house")]
	if deed.is_mortgaged:
		state += " - mortgaged"
	UiStyle.label(v, s.display_name + state, "button")
	var row := HFlowContainer.new()
	v.add_child(row)
	var i := deed.space_index
	if s.space_type == Space.Type.STREET:
		if not deed.has_hotel:
			var cost := deed.hotel_cost if deed.houses == Building.MAX_HOUSES else deed.house_cost
			UiStyle.button(row, "Build -$%d" % cost, func() -> void: tc.build(p.id, i),
				Building.can_build(board, tc.bank, p, deed))
		if Building.level(deed) > 0:
			var value := Building.sell_value(deed.hotel_cost if deed.has_hotel else deed.house_cost, tc.config)
			UiStyle.button(row, "Sell +$%d" % value, func() -> void: tc.sell_building(p.id, i),
				Building.can_sell(board, tc.bank, p, deed))
	if deed.is_mortgaged:
		UiStyle.button(row, "Unmortgage -$%d" % Rules.unmortgage_cost(deed, tc.config),
			func() -> void: tc.unmortgage(p.id, i), Mortgage.can_unmortgage(p, deed, tc.config))
	else:
		UiStyle.button(row, "Mortgage +$%d" % deed.mortgage_value, func() -> void: tc.mortgage(p.id, i),
			Mortgage.can_mortgage(board, p, deed))
