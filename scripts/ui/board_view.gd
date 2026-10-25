class_name BoardView
extends Control
## Visual-only top-down board: 11x11 grid, the 40 spaces around the edge, owner markers and
## player tokens as colored dots. Reads the TurnController; never changes game state.
## Scales to any size (square board fitted into its rect).

const GRID := 11
const CELL_COLOR := Color("#141a33")
const CORNER_COLOR := Color("#1f2850")
const BORDER_COLOR := Color("#5b6aa8")
const TEXT_COLOR := Color("#e6ecff")
const CENTER_COLOR := Color("#0b1026")
const GOLD := Color("#d4af37")

var controller: TurnController = null


func _init() -> void:
	custom_minimum_size = Vector2(320, 320)
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


func _board_rect() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _draw() -> void:
	if controller == null:
		return
	var br := _board_rect()
	var cell := br.size.x / GRID
	var font := ThemeDB.fallback_font
	var font_size := maxi(7, int(cell * 0.14))
	draw_rect(br, CENTER_COLOR)
	for s in controller.board.spaces:
		var c := cell_of(s.index)
		var r := Rect2(br.position + Vector2(c) * cell, Vector2(cell, cell))
		var is_corner := s.index % 10 == 0
		draw_rect(r, CORNER_COLOR if is_corner else CELL_COLOR)
		if s.space_type == Space.Type.STREET:
			var g: Dictionary = controller.board.group_info.get(s.color_group_id, {})
			draw_rect(Rect2(r.position, Vector2(cell, cell * 0.2)), g.get("color", Color.GRAY))
		draw_rect(r, BORDER_COLOR, false, 1.0)
		draw_multiline_string(font, r.position + Vector2(2, cell * 0.2 + font_size), s.display_name,
				HORIZONTAL_ALIGNMENT_CENTER, cell - 4, font_size, 4, TEXT_COLOR)
		if s.deed != null and s.deed.owner != PropertyDeed.BANK:
			var owner_color := controller.players[s.deed.owner].color
			if s.deed.is_mortgaged:
				owner_color = owner_color.darkened(0.6)
			draw_rect(Rect2(r.position + Vector2(cell * 0.06, cell * 0.8), Vector2(cell * 0.88, cell * 0.12)), owner_color)
			_draw_buildings(r, cell, s.deed)
	_draw_tokens(br, cell)
	_draw_center(br, cell, font)


## Houses as small squares in the color strip; a hotel as one wide gold bar.
func _draw_buildings(r: Rect2, cell: float, deed: PropertyDeed) -> void:
	var pip := cell * 0.14
	var y := r.position.y + cell * 0.03
	if deed.has_hotel:
		draw_rect(Rect2(Vector2(r.position.x + cell * 0.3, y), Vector2(cell * 0.4, pip)), GOLD)
		return
	for i in deed.houses:
		draw_rect(Rect2(Vector2(r.position.x + cell * (0.08 + 0.22 * i), y), Vector2(pip, pip)), TEXT_COLOR)


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
	var mid := br.position + br.size * 0.5
	var title_size := maxi(12, int(cell * 0.5))
	draw_string(font, Vector2(br.position.x + cell, mid.y - cell * 0.5), "IMPERIUM ASTRA",
			HORIZONTAL_ALIGNMENT_CENTER, cell * 9, title_size, GOLD)
	if controller.dice.d1 > 0:
		var dice_text := "%d  %d" % [controller.dice.d1, controller.dice.d2]
		draw_string(font, Vector2(br.position.x + cell, mid.y + cell * 0.6), dice_text,
				HORIZONTAL_ALIGNMENT_CENTER, cell * 9, title_size, TEXT_COLOR)
