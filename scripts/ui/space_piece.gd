class_name SpacePiece
extends Node2D
## Original procedural explorer: helmet, visor, suit and numbered chest badge.
## Follows BoardView's PieceState only; never owns movement or rules.

var tint := Color.WHITE
var seat := 0
var _cell := 30.0
var _lift := 0.0
var _alpha := 1.0


func apply_piece_state(state: BoardView.PieceState) -> void:
	_cell = state.cell
	_lift = state.lift
	_alpha = state.alpha
	queue_redraw()


func _draw() -> void:
	var unit := _cell * 0.22
	if unit <= 0.0:
		return
	var suit := tint.lerp(Color(0.55, 0.55, 0.55), 1.0 - _alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * unit)
	draw_circle(Vector2(0, 0.55 + _lift), 0.75, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-0.7, -0.2, 1.4, 0.9), suit.darkened(0.3))
	draw_line(Vector2(-0.32, 0.3), Vector2(-0.45, 0.85), suit, 0.35, true)
	draw_line(Vector2(0.32, 0.3), Vector2(0.45, 0.85), suit, 0.35, true)
	draw_circle(Vector2(0, -0.55), 0.7, suit.lightened(0.35))
	draw_arc(Vector2(0, -0.55), 0.7, 0, TAU, 24, Color.BLACK, 0.08, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-0.5, -0.8), Vector2(0.5, -0.8), Vector2(0.4, -0.35), Vector2(-0.4, -0.35)]), UiStyle.color("board_center"))
	draw_line(Vector2(-0.3, -0.68), Vector2(0.15, -0.68), Color(0.7, 0.9, 1), 0.08, true)
	for i in seat + 1:
		draw_circle(Vector2(-0.4 + i * 0.16, 0.15), 0.055, Color.WHITE)
