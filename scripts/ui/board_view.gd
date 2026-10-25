class_name BoardView
extends Control
## Visual-only top-down board: 11x11 grid, the 40 spaces around the edge (theme short_name,
## auto-fitted to the cell), owner markers and player tokens as colored dots. Tapping a space
## selects it and shows its details in the empty board center; tapping again or the center
## clears it. Reads the TurnController; never changes game state. Scales to any size (square
## board fitted into its rect). Colors and chrome (group bar height, frame, corner tints and
## marks) come from the theme pack via UiStyle; the dice readout is drawn as two pip faces.

signal space_selected(index: int)

const GRID := 11
const MIN_LABEL_FONT := 6
const NO_SELECTION := -1
## Pip positions on a 3x3 grid (0..2) per die value.
const PIPS := {
	1: [Vector2i(1, 1)],
	2: [Vector2i(0, 0), Vector2i(2, 2)],
	3: [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)],
	4: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)],
	5: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2)],
	6: [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)],
}

var controller: TurnController = null
var selected_index: int = NO_SELECTION


func _init() -> void:
	custom_minimum_size = Vector2(200, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func setup(tc: TurnController) -> void:
	controller = tc
	queue_redraw()


## Grid cell (col, row) of a board index: GO bottom-right, clockwise (bottom row right-to-left,
## left column upward, top row left-to-right, right column downward).
static func cell_of(index: int) -> Vector2i:
	if index <= 10:
		return Vector2i(10 - index, 10)
	if index <= 20:
		return Vector2i(0, 10 - (index - 10))
	if index <= 30:
		return Vector2i(index - 20, 0)
	return Vector2i(10, index - 30)


## Inverse of cell_of; NO_SELECTION for the center or outside the grid.
static func index_of_cell(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= GRID or c.y >= GRID:
		return NO_SELECTION
	if c.y == 10:
		return 10 - c.x
	if c.x == 0:
		return 10 + (10 - c.y)
	if c.y == 0:
		return 20 + c.x
	if c.x == 10:
		return 30 + c.y
	return NO_SELECTION


func _board_rect() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


## Board index under a local position, or NO_SELECTION.
func index_at(local_pos: Vector2) -> int:
	var br := _board_rect()
	if not br.has_point(local_pos):
		return NO_SELECTION
	var cell := br.size.x / GRID
	var c := Vector2i(((local_pos - br.position) / cell).floor())
	return index_of_cell(c)


func select(index: int) -> void:
	selected_index = NO_SELECTION if index == selected_index else index
	space_selected.emit(selected_index)
	queue_redraw()


## Mouse buttons cover touch too (Godot emulates mouse from touch); no raw touch events.
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		select(index_at(mb.position))
		accept_event()


## Theme tint for a corner space_type (GO, JAIL_CORNER, ...); the plain cell color otherwise.
static func corner_tint(space_type: int) -> Color:
	var v: Variant = UiStyle.theme_data().get("board", {}).get("corner_colors", {}).get(Space.Type.keys()[space_type])
	return Color.html(String(v)) if v is String and Color.html_is_valid(v) else UiStyle.color("board_cell")


## Short glyph line drawn under a corner's label ("" when the theme has none).
static func corner_mark(space_type: int) -> String:
	return String(UiStyle.theme_data().get("board", {}).get("corner_marks", {}).get(Space.Type.keys()[space_type], ""))


func _draw() -> void:
	if controller == null:
		return
	var br := _board_rect()
	var cell := br.size.x / GRID
	var font := ThemeDB.fallback_font
	var gold := UiStyle.color("accent")
	var cell_color := UiStyle.color("board_cell")
	var border := UiStyle.color("board_border")
	var bar_share := UiStyle.theme_num("board", "group_bar_share", 0.24)
	draw_rect(br, UiStyle.color("board_center"))
	var here := controller.current_player().position
	for s in controller.board.spaces:
		var c := cell_of(s.index)
		var r := Rect2(br.position + Vector2(c) * cell, Vector2(cell, cell))
		var is_corner := s.index % 10 == 0
		draw_rect(r, corner_tint(s.space_type) if is_corner else cell_color)
		var top := 0.0
		if s.space_type == Space.Type.STREET:
			var g: Dictionary = controller.board.group_info.get(s.color_group_id, {})
			top = cell * bar_share
			draw_rect(Rect2(r.position, Vector2(cell, top)), g.get("color", Color.GRAY))
			draw_line(r.position + Vector2(0, top), r.position + Vector2(cell, top), Color.BLACK, 1.0)
		draw_rect(r, border, false, 1.0)
		if is_corner:
			_draw_label(font, Rect2(r.position + Vector2(2, cell * 0.12), Vector2(cell - 4, cell * 0.5)), s.short_name)
			var mark := corner_mark(s.space_type)
			if mark != "":
				var ms := maxi(MIN_LABEL_FONT, int(cell * 0.16))
				draw_string(font, r.position + Vector2(0, cell * 0.78), mark, HORIZONTAL_ALIGNMENT_CENTER, cell, ms, gold)
		else:
			_draw_label(font, Rect2(r.position + Vector2(1, top + 1), Vector2(cell - 2, cell * 0.78 - top)), s.short_name)
		if s.deed != null and s.deed.owner != PropertyDeed.BANK:
			var owner_color := controller.players[s.deed.owner].color
			if s.deed.is_mortgaged:
				owner_color = owner_color.darkened(0.6)
			draw_rect(Rect2(r.position + Vector2(cell * 0.06, cell * 0.8), Vector2(cell * 0.88, cell * 0.12)), owner_color)
			_draw_buildings(r, cell, s.deed)
		if s.index == here:
			draw_rect(r.grow(-1.0), controller.current_player().color, false, 2.0)
		if s.index == selected_index:
			draw_rect(r.grow(-2.0), gold, false, 3.0)
	var frame := UiStyle.theme_num("board", "frame_width", 3)
	draw_rect(br.grow(-frame * 0.5), UiStyle.color("board_frame"), false, frame)
	draw_rect(Rect2(br.position + Vector2(cell, cell), Vector2(cell, cell) * 9.0), UiStyle.color("accent_dim"), false,
			UiStyle.theme_num("board", "center_rule_width", 2))
	_draw_tokens(br, cell)
	_draw_center(br, cell, font)


## Largest font (up to a cap) at which every word of the label fits the cell width, wrapped
## to at most three lines. Drawn with a dark outline so it stays legible on any tint.
func _draw_label(font: Font, area: Rect2, text: String) -> void:
	var font_size := maxi(MIN_LABEL_FONT, int(area.size.x * 0.26))
	var words := text.split(" ", false)
	while font_size > MIN_LABEL_FONT:
		var fits := font.get_height(font_size) * mini(words.size(), 3) <= area.size.y
		for w in words:
			if font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > area.size.x:
				fits = false
				break
		if fits:
			break
		font_size -= 1
	var pos := area.position + Vector2(0, font.get_ascent(font_size) + 1)
	draw_multiline_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, 3,
			maxi(2, int(font_size * 0.25)), Color(0, 0, 0, 0.75))
	draw_multiline_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, 3, UiStyle.color("text"))


## Houses as small squares in the color strip; a hotel as one wide gold bar.
func _draw_buildings(r: Rect2, cell: float, deed: PropertyDeed) -> void:
	var pip := cell * 0.14
	var y := r.position.y + cell * 0.03
	if deed.has_hotel:
		var bar := Rect2(Vector2(r.position.x + cell * 0.3, y), Vector2(cell * 0.4, pip))
		draw_rect(bar, UiStyle.color("accent"))
		draw_rect(bar, Color.BLACK, false, 1.0)
		return
	for i in deed.houses:
		var sq := Rect2(Vector2(r.position.x + cell * (0.08 + 0.22 * i), y), Vector2(pip, pip))
		draw_rect(sq, UiStyle.color("text"))
		draw_rect(sq, Color.BLACK, false, 1.0)


func _draw_tokens(br: Rect2, cell: float) -> void:
	var radius := cell * 0.12
	for p in controller.players:
		if p.is_bankrupt:
			continue
		var c := cell_of(p.position)
		var origin := br.position + Vector2(c) * cell
		var offset := Vector2(cell * (0.25 + 0.25 * (p.id % 3)), cell * (0.62 - 0.22 * floorf(p.id / 3.0)))
		var center := origin + offset
		draw_circle(center, radius, p.color)
		draw_arc(center, radius, 0.0, TAU, 24, Color.WHITE, 2.0 if p == controller.current_player() else 1.0)
		if p.in_jail:
			draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color.BLACK, 2.0)


func _draw_center(br: Rect2, cell: float, font: Font) -> void:
	var inner := Rect2(br.position + Vector2(cell, cell) * 1.2, Vector2(cell, cell) * 8.6)
	var title_size := maxi(12, int(cell * 0.45))
	var body_size := maxi(10, int(cell * 0.32))
	var text := UiStyle.color("text")
	var muted := UiStyle.color("text_muted")
	var y := inner.position.y + font.get_ascent(title_size)
	draw_string(font, Vector2(inner.position.x, y), String(ProjectSettings.get_setting("application/config/name", "")).to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, title_size, UiStyle.color("accent"))
	y += font.get_descent(title_size)
	draw_line(Vector2(inner.get_center().x - cell * 1.5, y), Vector2(inner.get_center().x + cell * 1.5, y),
			UiStyle.color("accent_dim"), 1.0)
	if controller.dice.d1 > 0:
		var face := cell * 0.85
		var gap := cell * 0.3
		var left := inner.get_center().x - face - gap * 0.5
		y += cell * 0.2
		_draw_die(Rect2(Vector2(left, y), Vector2(face, face)), controller.dice.d1)
		_draw_die(Rect2(Vector2(left + face + gap, y), Vector2(face, face)), controller.dice.d2)
		y += face
	y += font.get_height(title_size) * 0.4
	var lines := space_details(selected_index)
	if lines.is_empty():
		draw_string(font, Vector2(inner.position.x, inner.end.y - font.get_descent(body_size)),
				"Tap a space for details", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, body_size, muted)
		return
	var s := controller.board.spaces[selected_index]
	if s.space_type == Space.Type.STREET:
		var g: Dictionary = controller.board.group_info.get(s.color_group_id, {})
		draw_rect(Rect2(Vector2(inner.position.x, y), Vector2(inner.size.x, cell * 0.12)), g.get("color", Color.GRAY))
	y += cell * 0.12
	for i in lines.size():
		var fs := title_size if i == 0 else body_size
		y += font.get_height(fs)
		if y > inner.end.y:
			break
		draw_string(font, Vector2(inner.position.x, y), lines[i], HORIZONTAL_ALIGNMENT_CENTER,
				inner.size.x, fs, text if i == 0 else muted)


## One die face: rounded ivory square with dark pips (theme dice_face / dice_pip).
func _draw_die(r: Rect2, value: int) -> void:
	var face := UiStyle.flat_box(UiStyle.color("dice_face"), UiStyle.color("accent"), 2, int(r.size.x * 0.18), 0)
	face.draw(get_canvas_item(), r)
	var step := r.size.x / 4.0
	for p: Vector2i in PIPS.get(value, []):
		draw_circle(r.position + Vector2(step * (p.x + 1), step * (p.y + 1)), r.size.x * 0.09, UiStyle.color("dice_pip"))


## Text lines describing a space for the center readout (empty for NO_SELECTION).
func space_details(index: int) -> PackedStringArray:
	var out := PackedStringArray()
	if controller == null or index < 0 or index >= controller.board.spaces.size():
		return out
	var board := controller.board
	var s := board.spaces[index]
	out.append(s.display_name)
	if s.space_type == Space.Type.STREET:
		out.append(String(board.group_info.get(s.color_group_id, {}).get("display_name", s.color_group_id)))
	if s.tax_amount > 0:
		out.append("Pay $%d" % s.tax_amount)
	var deed := s.deed
	if deed == null:
		return out
	var owner := "Unowned" if deed.owner == PropertyDeed.BANK else "Owner: %s" % controller.players[deed.owner].display_name
	out.append("Price $%d  |  %s" % [deed.list_price, owner])
	if deed.has_hotel:
		out.append("1 %s" % board.term("hotel"))
	elif deed.houses > 0:
		out.append("%d %s" % [deed.houses, board.term("houses") if deed.houses > 1 else board.term("house")])
	if deed.is_mortgaged:
		out.append("Mortgaged")
	if not deed.rent_by_houses.is_empty():
		var parts := PackedStringArray()
		for r in deed.rent_by_houses:
			parts.append(str(r))
		out.append("Rent " + " / ".join(parts))
		out.append("Build $%d  |  Mortgage $%d" % [deed.house_cost, deed.mortgage_value])
	else:
		out.append("Mortgage $%d" % deed.mortgage_value)
	return out
