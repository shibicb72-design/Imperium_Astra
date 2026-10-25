class_name BoardView
extends Control
## Visual-only top-down board: 11x11 grid, the 40 spaces around the edge (theme short_name,
## auto-fitted to the cell), owner markers and player tokens as colored dots. Tapping a space
## selects it and shows its details in the empty board center; tapping again or the center
## clears it. Reads the TurnController; never changes game state. Scales to any size (square
## board fitted into its rect). Colors and chrome (group bar height, frame, corner tints and
## marks) come from the theme pack via UiStyle; the dice readout is drawn as two pip faces.
##
## Motion (P4-DEMO): the game resolves a roll instantly, so the view keeps its own animation queue
## played in order: dice tumble (queue_dice), pawn hops space by space along the track
## (queue_move), a straight arc to the Brig (queue_jump) and callbacks (queue_call; Main uses it
## so a banner line appears when the pawn arrives, not before). Tokens are drawn at their shown
## positions, which catch up with the game as the queue plays. With `animate` off (headless
## tests, outside the tree) everything applies at once. Timings: data/ui.json dice_roll_seconds,
## pawn_step_seconds, pawn_move_max_seconds, pawn_jump_seconds, pawn_hop_height.
##
## Piece contract (P5-FEEL A3): piece_state(player_id) is where a player's piece should be drawn
## this frame (board-local point, lift 0..1, moving, visible, alpha), from the same math as the
## drawn tokens. A Node2D attached with attach_piece() becomes a child of this view and replaces
## that player's drawn token; it is positioned from piece_state() every time the view updates
## (each animation frame, on resize, and at once when animate is off). If the node has
## apply_piece_state(state: PieceState) that is called too (lift, jail look, art). No physics
## bodies: pieces only follow. The queue stays the single sequencer; queue_move / queue_jump drive
## the shown board index and no rules state lives here. fade_out_piece() is the bankrupt-fade hook
## (presentation-only fading set; call it on the existing `bankrupt` game_event); rules never wait.
##
## Die affordance (P5-FEEL Dig 5): while Main sets die_ready, the dice area shows a die-ready look
## (blank faces ringed in the seat colour, OPEN_QUESTIONS Q27) instead of the last-roll readout, so
## it reads as "tap to roll" even before any roll and on turn 1 after the start-order roll. A press
## inside die_hit_rect() (at least UiStyle.touch() each way) emits die_pressed and selects no
## space; Main applies its gate and rolls. This view still never calls the controller.

signal space_selected(index: int)
signal animation_finished
signal die_pressed

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


## Where one player's piece should be drawn this frame (see piece_state()).
class PieceState extends RefCounted:
	var player_id: int = -1
	## Board index the piece counts as standing on (the shown position, not the game's).
	var index: int = 0
	## Board-local draw point, already raised by the lift.
	var point := Vector2.ZERO
	## Ground point under the piece (for a shadow).
	var rest := Vector2.ZERO
	## 0 on the ground .. 1 at the top of a hop or jump.
	var lift := 0.0
	var moving := false
	var visible := false
	## 1 normally; falls to 0 while a bankrupt piece fades out.
	var alpha := 1.0
	## Board cell size, for scaling art to the board.
	var cell := 0.0

var controller: TurnController = null
var selected_index: int = NO_SELECTION
## Play queued motion over time; off = apply at once. Main turns it on inside the live tree.
var animate := false
## Die-ready look and die presses on (set_die_ready); Main sets it from its gate.
var die_ready := false
var _die_tint := Color.WHITE

## Board index each token is drawn at (player id -> index); catches up as the queue plays.
var _shown_pos: Dictionary = {}
## Dice faces drawn in the center (0 = none yet); set when a queued roll finishes tumbling.
var _shown_dice := Vector2i.ZERO
var _queue: Array[Dictionary] = []
var _item: Dictionary = {}
var _t := 0.0
var _tumble := Vector2i.ONE
var _tumble_left := 0.0
var _rng := RandomNumberGenerator.new()
## Attached piece nodes (player id -> Node2D child).
var _pieces: Dictionary = {}
## Bankrupt pieces still fading out (player id -> [seconds left, total seconds]).
var _fading: Dictionary = {}
## Transient building feedback, independent of the movement queue.
var _building_fx: Array[Dictionary] = []


func _init() -> void:
	custom_minimum_size = Vector2(200, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	resized.connect(update_pieces)


func setup(tc: TurnController) -> void:
	clear_pieces()
	_building_fx.clear()
	controller = tc
	sync_to_game()
	for player in tc.players:
		var piece := SpacePiece.new()
		piece.tint = player.color
		piece.seat = player.id
		attach_piece(player.id, piece)


## Redraws board chrome from the active theme pack (after UiStyle.set_theme). Queued motion is kept.
func refresh_theme() -> void:
	queue_redraw()


## Snaps tokens and dice to the game state and drops any queued motion.
func sync_to_game() -> void:
	_queue.clear()
	_item = {}
	_shown_pos.clear()
	_fading.clear()
	if controller != null:
		for p in controller.players:
			_shown_pos[p.id] = p.position
		_shown_dice = Vector2i(controller.dice.d1, controller.dice.d2)
	queue_redraw()
	update_pieces()


func is_animating() -> bool:
	return not _item.is_empty() or not _queue.is_empty()


## Board index a token is drawn at right now.
func shown_position(player_id: int) -> int:
	return int(_shown_pos.get(player_id, controller.players[player_id].position))


func shown_dice() -> Vector2i:
	return _shown_dice


## Turns the die-ready look and die presses on or off; `tint` rings the faces (current seat colour).
func set_die_ready(on: bool, tint: Color = Color.WHITE) -> void:
	if on == die_ready and tint == _die_tint:
		return
	die_ready = on
	_die_tint = tint
	queue_redraw()


## What the dice area draws now: &"tumble" (a roll playing), &"ready" (die-ready look), &"faces"
## (last-roll readout) or &"none" (no roll yet).
func dice_look() -> StringName:
	if _rolling():
		return &"tumble"
	if die_ready:
		return &"ready"
	return &"faces" if _faces().x > 0 else &"none"


func _rolling() -> bool:
	return not _item.is_empty() and _item["type"] == &"dice"


func _faces() -> Vector2i:
	if _rolling():
		return _tumble
	return _shown_dice if is_animating() else Vector2i(controller.dice.d1, controller.dice.d2)


## The two dice in the board center (local): under the title line, as drawn by _draw_center().
func dice_rect() -> Rect2:
	var br := _board_rect()
	var cell := br.size.x / GRID
	var font := UiStyle.display_font()
	var title_size := maxi(12, int(cell * 0.45))
	var inner := Rect2(br.position + Vector2(cell, cell) * 1.2, Vector2(cell, cell) * 8.6)
	var face := cell * 0.85
	var gap := cell * 0.3
	var y := inner.position.y + font.get_ascent(title_size) + font.get_descent(title_size) + cell * 0.2
	return Rect2(inner.get_center().x - face - gap * 0.5, y, face * 2.0 + gap, face)


## Press area of the die-ready look: the dice, grown to at least UiStyle.touch() each way.
func die_hit_rect() -> Rect2:
	var r := dice_rect()
	var t := UiStyle.touch()
	var gx := maxf(0.0, (t - r.size.x) * 0.5)
	var gy := maxf(0.0, (t - r.size.y) * 0.5)
	return r.grow_individual(gx, gy, gx, gy)


func queue_dice(d1: int, d2: int) -> void:
	_enqueue({"type": &"dice", "d1": d1, "d2": d2, "dur": UiStyle.num("dice_roll_seconds", 0.55)})


## Hop `steps` spaces (negative: backward) from `from`. Long moves speed up to fit
## pawn_move_max_seconds.
func queue_move(player_id: int, from: int, steps: int) -> void:
	if steps == 0:
		return
	var per := UiStyle.num("pawn_step_seconds", 0.14)
	per = minf(per, UiStyle.num("pawn_move_max_seconds", 1.8) / absi(steps))
	_enqueue({"type": &"move", "player": player_id, "from": from, "steps": steps, "per": per,
			"dur": per * absi(steps)})


## Straight arc from `from` to `to` (sent to the Brig).
func queue_jump(player_id: int, from: int, to: int) -> void:
	_enqueue({"type": &"jump", "player": player_id, "from": from, "to": to,
			"dur": UiStyle.num("pawn_jump_seconds", 0.6)})


## Runs `fn` once everything queued before it has played (at once when idle).
func queue_call(fn: Callable) -> void:
	_enqueue({"type": &"call", "fn": fn, "dur": 0.0})


func _enqueue(item: Dictionary) -> void:
	if not animate or (not is_animating() and float(item["dur"]) <= 0.0):
		_finish_item(item)
		return
	_queue.append(item)
	if _item.is_empty():
		_start_next()


func _start_next() -> void:
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		if float(item["dur"]) <= 0.0:
			_finish_item(item)
			continue
		_item = item
		_t = 0.0
		_tumble_left = 0.0
		queue_redraw()
		return
	_item = {}
	if controller != null:  # anything that moved without an event snaps into place
		for p in controller.players:
			_shown_pos[p.id] = p.position
	queue_redraw()
	update_pieces()
	animation_finished.emit()


func _finish_item(item: Dictionary) -> void:
	match item["type"]:
		&"dice":
			_shown_dice = Vector2i(int(item["d1"]), int(item["d2"]))
		&"move":
			_shown_pos[int(item["player"])] = posmod(int(item["from"]) + int(item["steps"]), Board.SPACE_COUNT)
		&"jump":
			_shown_pos[int(item["player"])] = int(item["to"])
		&"call":
			(item["fn"] as Callable).call()
	queue_redraw()
	update_pieces()


## Plays the queue forward by `delta` seconds; called from _process, or by tests.
func advance(delta: float) -> void:
	while not _item.is_empty() and delta > 0.0:
		var left := float(_item["dur"]) - _t
		if delta < left:
			_t += delta
			if _item["type"] == &"dice":
				_tumble_left -= delta
				if _tumble_left <= 0.0:
					_tumble = Vector2i(_rng.randi_range(1, 6), _rng.randi_range(1, 6))
					_tumble_left = 0.07
			queue_redraw()
			update_pieces()
			return
		delta -= left
		var done := _item
		_item = {}
		_finish_item(done)
		_start_next()


func _process(delta: float) -> void:
	advance_building_fx(delta)
	if not _item.is_empty():
		advance(delta)
	if not _fading.is_empty():
		advance_fades(delta)


# --- Piece contract (P5-FEEL A3) ----------------------------------------------------------------

## Makes `node` the piece for `player_id` (a child of this view, replacing its drawn token). Any
## previous piece for that player is freed. Positioned at once.
func attach_piece(player_id: int, node: Node2D) -> void:
	var old := piece_node(player_id)
	if old == node:
		return
	if old != null:
		remove_child(old)
		old.free()
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	add_child(node)
	_pieces[player_id] = node
	update_pieces()
	queue_redraw()


## Removes and returns the piece for `player_id` (null if none); the caller owns it afterwards.
func detach_piece(player_id: int) -> Node2D:
	var node := piece_node(player_id)
	_pieces.erase(player_id)
	if node != null:
		remove_child(node)
	queue_redraw()
	return node


## The attached piece for `player_id`, or null (also once it has been freed elsewhere).
func piece_node(player_id: int) -> Node2D:
	var v: Variant = _pieces.get(player_id)
	if not is_instance_valid(v):
		_pieces.erase(player_id)
		return null
	return v as Node2D


## Frees every attached piece; the view draws plain tokens again.
func clear_pieces() -> void:
	for pid: int in _pieces.keys():
		var node := detach_piece(pid)
		if node != null:
			node.free()


## Where `player_id`'s piece should be drawn now. Invisible for unknown ids, before setup(), and
## for bankrupt players once any fade has finished.
func piece_state(player_id: int) -> PieceState:
	var s := PieceState.new()
	s.player_id = player_id
	if controller == null or player_id < 0 or player_id >= controller.players.size():
		return s
	var br := _board_rect()
	var cell := br.size.x / GRID
	s.cell = cell
	s.index = shown_position(player_id)
	s.point = token_point(br, cell, player_id, s.index)
	s.rest = s.point
	if not _item.is_empty() and _item["type"] in [&"move", &"jump"] and int(_item["player"]) == player_id:
		var mp := _moving_point(br, cell)
		s.point = mp[0]
		s.lift = mp[1]
		s.rest = s.point + Vector2(0, UiStyle.num("pawn_hop_height", 0.3) * cell * s.lift)
		s.moving = true
	s.visible = true
	if controller.players[player_id].is_bankrupt:
		if _fading.has(player_id):
			var f: Array = _fading[player_id]
			s.alpha = clampf(float(f[0]) / float(f[1]), 0.0, 1.0)
		else:
			s.visible = false
			s.alpha = 0.0
	return s


## Bankrupt-fade hook: keep `player_id`'s piece showing and fade it out over `seconds` instead of
## hiding it at once. Presentation only; with animate off (or seconds <= 0) it is hidden at once.
func fade_out_piece(player_id: int, seconds: float) -> void:
	if animate and seconds > 0.0:
		_fading[player_id] = [seconds, seconds]
	else:
		_fading.erase(player_id)
	update_pieces()
	queue_redraw()


func is_fading(player_id: int) -> bool:
	return _fading.has(player_id)


## Plays bankrupt fades forward by `delta` seconds; called from _process, or by tests.
func advance_fades(delta: float) -> void:
	for pid: int in _fading.keys():
		var f: Array = _fading[pid]
		f[0] = float(f[0]) - delta
		if float(f[0]) <= 0.0:
			_fading.erase(pid)
	update_pieces()
	queue_redraw()


## Moves every attached piece to its piece_state(); safe headless and outside the tree.
func update_pieces() -> void:
	for pid: int in _pieces.keys():
		var node := piece_node(pid)
		if node == null:
			continue
		var s := piece_state(pid)
		node.position = s.point
		node.visible = s.visible
		node.modulate.a = s.alpha
		node.z_index = 1 if s.moving else 0
		if node.has_method(&"apply_piece_state"):
			node.call(&"apply_piece_state", s)


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


## The square board inside this view (local).
func board_rect() -> Rect2:
	return _board_rect()


## Area for the dialogue banner: the lower middle of the empty board center, below the dice.
func banner_rect() -> Rect2:
	var br := _board_rect()
	var cell := br.size.x / GRID
	var inner := Rect2(br.position + Vector2(cell, cell) * 1.3, Vector2(cell, cell) * 8.4)
	return Rect2(inner.position + Vector2(0, inner.size.y * 0.42), Vector2(inner.size.x, inner.size.y * 0.36))


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


## Mouse buttons cover touch too (Godot emulates mouse from touch); no raw touch events. While
## die-ready, a press on the dice is a die press, not a space selection.
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if die_ready and die_hit_rect().has_point(mb.position):
			die_pressed.emit()
		else:
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
	var font := UiStyle.display_font()
	var gold := UiStyle.color("accent")
	var cell_color := UiStyle.color("board_cell")
	var border := UiStyle.color("board_border")
	var bar_share := UiStyle.theme_num("board", "group_bar_share", 0.24)
	draw_rect(br, UiStyle.color("board_center"))
	var here := shown_position(controller.current_player().id)
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
			_draw_corner_icon(r, s.space_type, gold)
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
	_draw_building_fx(br, cell)
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


## Resting spot of a player's token inside the cell of board index `index`.
static func token_point(br: Rect2, cell: float, player_id: int, index: int) -> Vector2:
	var origin := br.position + Vector2(cell_of(posmod(index, Board.SPACE_COUNT))) * cell
	return origin + Vector2(cell * (0.25 + 0.25 * (player_id % 3)), cell * (0.62 - 0.22 * floorf(player_id / 3.0)))


## Where the token of the moving player is mid-animation, plus its lift (0..1) for drawing.
func _moving_point(br: Rect2, cell: float) -> Array:
	var pid := int(_item["player"])
	var hop := UiStyle.num("pawn_hop_height", 0.3) * cell
	if _item["type"] == &"jump":
		var u := clampf(_t / float(_item["dur"]), 0.0, 1.0)
		var a := token_point(br, cell, pid, int(_item["from"]))
		var b := token_point(br, cell, pid, int(_item["to"]))
		var lift := sin(PI * u)
		return [a.lerp(b, u) - Vector2(0, hop * 3.0 * lift), lift]
	var per := float(_item["per"])
	var dir := signi(int(_item["steps"]))
	var k := mini(int(_t / per), absi(int(_item["steps"])) - 1)
	var u2 := clampf((_t - k * per) / per, 0.0, 1.0)
	var i0 := int(_item["from"]) + dir * k
	var p0 := token_point(br, cell, pid, i0)
	var p1 := token_point(br, cell, pid, i0 + dir)
	var lift2 := sin(PI * u2)
	return [p0.lerp(p1, u2) - Vector2(0, hop * lift2), lift2]


## Plain circle tokens for players without an attached piece node (same math as piece_state()).
func _draw_tokens(_br: Rect2, cell: float) -> void:
	var radius := cell * 0.12
	var moving: PieceState = null
	for p in controller.players:
		if piece_node(p.id) != null:
			continue
		var s := piece_state(p.id)
		if not s.visible:
			continue
		if s.moving:
			moving = s
			continue
		_draw_token(s.point, radius, p, s.alpha)
	if moving != null:  # drawn last so it passes over the others, with a soft shadow below it
		draw_circle(moving.rest, radius * (1.0 - 0.3 * moving.lift), Color(0, 0, 0, 0.35 * moving.alpha))
		_draw_token(moving.point, radius * (1.0 + 0.35 * moving.lift), controller.players[moving.player_id], moving.alpha)


func _draw_token(center: Vector2, radius: float, p: Player, alpha: float = 1.0) -> void:
	draw_circle(center, radius, Color(p.color, p.color.a * alpha))
	draw_arc(center, radius, 0.0, TAU, 24, Color(Color.WHITE, alpha), 2.0 if p == controller.current_player() else 1.0)
	if p.in_jail:
		draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(Color.BLACK, alpha), 2.0)


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
	var look := dice_look()
	var dice := dice_rect()
	var face := dice.size.y
	if look == &"ready":
		y = _draw_die_ready(dice, face, font, body_size)
	elif look != &"none":
		var faces := _faces()
		var j1 := Vector2.ZERO
		var j2 := Vector2.ZERO
		if look == &"tumble":  # tumbling: faces flicker and the dice rattle a little
			var shake := cell * 0.12 * (1.0 - _t / float(_item["dur"]))
			j1 = Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake))
			j2 = Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake))
		_draw_die(Rect2(dice.position + j1, Vector2(face, face)), faces.x)
		_draw_die(Rect2(Vector2(dice.end.x - face, dice.position.y) + j2, Vector2(face, face)), faces.y)
		y = dice.end.y
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


## Die-ready look: the press area lit in the seat colour, two blank faces ringed in it and a
## "Tap to roll" caption; no pips, so it never reads as a roll already made. Returns the caption's
## bottom edge.
func _draw_die_ready(dice: Rect2, face: float, font: Font, body_size: int) -> float:
	var hit := die_hit_rect()
	UiStyle.flat_box(Color(_die_tint, 0.14), Color(_die_tint, 0.7), 1, int(minf(hit.size.y, hit.size.x) * 0.25), 0).draw(get_canvas_item(), hit)
	for x: float in [dice.position.x, dice.end.x - face]:
		UiStyle.flat_box(UiStyle.color("dice_face"), _die_tint, maxi(2, int(face * 0.1)), int(face * 0.18), 0).draw(
				get_canvas_item(), Rect2(x, dice.position.y, face, face))
	var top := maxf(hit.end.y, dice.end.y)
	draw_string(font, Vector2(hit.position.x - face, top + font.get_ascent(body_size)), "Tap to roll",
			HORIZONTAL_ALIGNMENT_CENTER, hit.size.x + face * 2.0, body_size, _die_tint.lerp(Color.WHITE, 0.3))
	return top + font.get_height(body_size)


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
	# Pack word in sentence case, as trade.gd does: String.capitalize() would title-case it and turn
	# "-" / "_" into spaces.
	var unowned := board.term("unowned")
	var owner := (unowned.left(1).to_upper() + unowned.substr(1) if deed.owner == PropertyDeed.BANK
		else "Owner: %s" % controller.players[deed.owner].display_name)
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


## Build expands; sale contracts. Snapshot pips survive the final sell-to-zero frame.
func building_pop(index: int, selling: bool, hotel: bool, count: int) -> void:
	if not animate:
		return
	_building_fx.append({"index": index, "selling": selling, "hotel": hotel,
		"count": maxi(1, count), "elapsed": 0.0})
	queue_redraw()


func advance_building_fx(delta: float) -> void:
	if _building_fx.is_empty():
		return
	for i in range(_building_fx.size() - 1, -1, -1):
		_building_fx[i]["elapsed"] += delta
		if float(_building_fx[i]["elapsed"]) >= UiStyle.num("building_pop_seconds", 0.32):
			_building_fx.remove_at(i)
	queue_redraw()


func _draw_building_fx(br: Rect2, cell: float) -> void:
	for fx in _building_fx:
		var t := clampf(float(fx["elapsed"]) / UiStyle.num("building_pop_seconds", 0.32), 0, 1)
		var center := br.position + Vector2(cell_of(int(fx["index"]))) * cell + Vector2(cell * 0.5, cell * 0.12)
		var amount := UiStyle.num("building_pop_scale", 1.8)
		var zoom := lerpf(amount, 0.1, t) if fx["selling"] else 1.0 + sin(t * PI) * (amount - 1.0)
		var tint := Color(UiStyle.color("accent") if fx["hotel"] else UiStyle.color("text"), 1.0 - t)
		var count := 1 if fx["hotel"] else mini(4, int(fx["count"]))
		for i in count:
			var width := cell * (0.4 if fx["hotel"] else 0.14) * zoom
			var offset := Vector2((i - (count - 1) * 0.5) * cell * 0.22, 0)
			draw_rect(Rect2(center + offset - Vector2(width, cell * 0.14 * zoom) * 0.5,
				Vector2(width, cell * 0.14 * zoom)), tint)


## Original vector corner symbols; stable space types choose presentation only.
func _draw_corner_icon(rect: Rect2, kind: int, tint: Color) -> void:
	var c := rect.position + rect.size * Vector2(0.5, 0.72)
	var r := rect.size.x * 0.14
	match kind:
		Space.Type.GO:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r), c + Vector2(0, -r), c + Vector2(r, r), c]), tint)
		Space.Type.JAIL_CORNER, Space.Type.GO_TO_JAIL:
			draw_rect(Rect2(c - Vector2(r, r), Vector2.ONE * r * 2), tint, false, 1.5)
			for x in [-0.5, 0.0, 0.5]:
				draw_line(c + Vector2(r * x, -r), c + Vector2(r * x, r), tint, 1.5)
			if kind == Space.Type.GO_TO_JAIL:
				draw_line(c + Vector2(-r * 2, 0), c, tint, 2)
		Space.Type.FREE_PARKING:
			draw_arc(c, r, 0, TAU, 24, tint, 1.5, true)
			draw_line(c + Vector2(-r * 1.5, 0), c + Vector2(r * 1.5, 0), tint, 1.5)
