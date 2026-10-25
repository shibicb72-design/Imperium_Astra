class_name HoldingsPanel
extends VBoxContainer
## Build / sell / mortgage controls (core modules: Building, Mortgage). Official rules allow these
## at any time, so in hotseat play any commander can be picked as the actor. Rows are rebuilt on
## every refresh; enable states come straight from the module checks.

const BUTTON_MIN_HEIGHT := 48.0

var _controller: TurnController
var _actor_picker: OptionButton
var _rows: VBoxContainer
var _actor_id: int = 0


func setup(controller: TurnController) -> void:
	_controller = controller
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Holdings"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	_actor_picker = OptionButton.new()
	_actor_picker.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	_actor_picker.add_theme_font_size_override("font_size", 18)
	for p in controller.players:
		_actor_picker.add_item(p.display_name, p.id)
	_actor_picker.item_selected.connect(_on_actor_selected)
	add_child(_actor_picker)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)
	set_actor(controller.current_player().id)


func _on_actor_selected(index: int) -> void:
	set_actor(_actor_picker.get_item_id(index))


func set_actor(player_id: int) -> void:
	_actor_id = player_id
	_actor_picker.select(_actor_picker.get_item_index(player_id))
	refresh()


func refresh() -> void:
	var tc := _controller
	for p in tc.players:
		_actor_picker.set_item_disabled(_actor_picker.get_item_index(p.id), p.is_bankrupt)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if not tc.can_manage(_actor_id):
		_add_label(_rows, "No actions available.")
		return
	var p := tc.players[_actor_id]
	var deeds := tc.board.deeds_owned_by(p.id)
	if deeds.is_empty():
		_add_label(_rows, "No holdings.")
	for deed in deeds:
		_add_deed_row(p, deed)
	for gid: StringName in tc.board.color_groups:
		if tc.board.owns_full_group(p.id, gid) and Building.group_has_buildings(tc.board, gid):
			var group_name := String(tc.board.group_info.get(gid, {}).get("display_name", gid))
			_add_button(_rows, "Sell all buildings: %s" % group_name, true,
				func() -> void: tc.sell_group_buildings(p.id, gid))


func _add_deed_row(p: Player, deed: PropertyDeed) -> void:
	var tc := _controller
	var board := tc.board
	var s := board.spaces[deed.space_index]
	var state := ""
	if deed.has_hotel:
		state = " - %s" % board.term("hotel")
	elif deed.houses > 0:
		state = " - %d %s" % [deed.houses, board.term("houses") if deed.houses > 1 else board.term("house")]
	if deed.is_mortgaged:
		state += " - mortgaged"
	var label := _add_label(_rows, s.display_name + state)
	if s.space_type == Space.Type.STREET:
		var g: Dictionary = board.group_info.get(deed.color_group_id, {})
		label.add_theme_color_override("font_color", g.get("color", Color.WHITE))
	var row := HFlowContainer.new()
	_rows.add_child(row)
	var i := deed.space_index
	if s.space_type == Space.Type.STREET:
		var cost := deed.hotel_cost if deed.houses == Building.MAX_HOUSES else deed.house_cost
		_add_button(row, "Build $%d" % cost, Building.can_build(board, tc.bank, p, deed),
			func() -> void: tc.build(p.id, i))
		if Building.level(deed) > 0:
			var value := Building.sell_value(deed.hotel_cost if deed.has_hotel else deed.house_cost, tc.config)
			_add_button(row, "Sell +$%d" % value, Building.can_sell(board, tc.bank, p, deed),
				func() -> void: tc.sell_building(p.id, i))
	if deed.is_mortgaged:
		_add_button(row, "Lift -$%d" % Rules.unmortgage_cost(deed, tc.config),
			Mortgage.can_unmortgage(p, deed, tc.config), func() -> void: tc.unmortgage(p.id, i))
	else:
		_add_button(row, "Mortgage +$%d" % deed.mortgage_value, Mortgage.can_mortgage(board, p, deed),
			func() -> void: tc.mortgage(p.id, i))


func _add_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _add_button(parent: Control, text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
