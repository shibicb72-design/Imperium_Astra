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
## PieceState.in_jail mirrors the player's jail flag so a piece can paint its jail look.
##
## FX hooks (P5 structure hooks): queue_fx(kind, info, dur) queues a timed presentation item that
## holds the same queue, so is_animating() stays the one busy signal (no second FX flag). fx_pose(kind)
## samples claim, gavel, rest and victory poses; cash_fly_pose samples shared money arcs. Pass-GO
## is sampled inside the move item so its duration cap is preserved. Nothing changes rules state.
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
	## The player is in jail (jail look); from the rules state, never from the queue.
	var in_jail := false

var controller: TurnController = null
var selected_index: int = NO_SELECTION
## Play queued motion over time; off = apply at once. Main turns it on inside the live tree.
var animate := false
## Die-ready look and die presses on (set_die_ready); Main sets it from its gate.
var die_ready := false
var _die_tint := Color.WHITE
var _idle_time := 0.0

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
		if _t / float(_item["dur"]) >= UiStyle.num("dice_bounce_settle_fraction", 0.88):
			return Vector2i(int(_item.d1), int(_item.d2))
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


func queue_dice(d1: int, d2: int, doubles: bool = false) -> void:
	_enqueue({"type": &"dice", "d1": d1, "d2": d2, "doubles": doubles,
		"dur": UiStyle.num("dice_roll_seconds", 0.55)})


## Presentation-only ballistic arcs, sampled by advance() and shared with drawing/tests.
## Release compression -> large hop -> impact -> rebound -> final settle.
func dice_pose(die: int) -> Dictionary:
	var r := dice_rect()
	var cell := _board_rect().size.x / GRID
	var rest := Vector2(r.position.x + r.size.y * 0.5, r.get_center().y)
	if die == 1:
		rest.x = r.end.x - r.size.y * 0.5
	var lift := 0.0
	var stretch := Vector2.ONE
	var offset := Vector2.ZERO
	var angle := 0.0
	var pip_scale := 1.0
	var glint := 0.0
	if _rolling():
		var t := clampf(_t / float(_item["dur"]), 0.0, 1.0)
		var release := UiStyle.num("dice_bounce_release_fraction", 0.08)
		var land := UiStyle.num("dice_bounce_land_fraction", 0.60)
		var rebound := UiStyle.num("dice_bounce_rebound_fraction", 0.68)
		var settle := UiStyle.num("dice_bounce_settle_fraction", 0.88)
		var direction := -1.0 if die == 0 else 1.0
		if t < release:
			var press := sin(PI * t / release)
			stretch = Vector2.ONE * (1.0 - UiStyle.num("dice_press_depth", 0.1) * press)
		elif t < land:
			var u := (t - release) / (land - release)
			var arc := 4.0 * u * (1.0 - u)
			lift = cell * UiStyle.num("dice_bounce_height", 0.85) * arc
			offset.x = direction * cell * UiStyle.num("dice_bounce_spread", 0.65) * sin(PI * u)
			stretch = Vector2(1.0 - 0.12 * arc, 1.0 + 0.12 * arc)
			angle = direction * TAU * u
		elif t < rebound:
			var impact := 1.0 - (t - land) / (rebound - land)
			stretch = Vector2(1.0 + 0.24 * impact, 1.0 - 0.24 * impact)
		elif t < settle:
			var u := (t - rebound) / (settle - rebound)
			var arc := 4.0 * u * (1.0 - u)
			lift = cell * UiStyle.num("dice_bounce_rebound_height", 0.28) * arc
			offset.x = direction * cell * 0.15 * sin(PI * u)
			angle = direction * 0.25 * sin(PI * u)
		else:
			var impact := 1.0 - (t - settle) / (1.0 - settle)
			stretch = Vector2(1.0 + 0.12 * impact, 1.0 - 0.12 * impact)
			pip_scale = 1.0 + UiStyle.num("dice_pip_lock_extra", 0.3) * impact
			if bool(_item.get("doubles", false)):
				glint = sin(PI * (1.0 - impact))
	return {"point": rest + offset + Vector2(0.0, -lift), "lift": lift,
		"scale": stretch, "rotation": angle, "pip_scale": pip_scale, "glint": glint}


## Hop `steps` spaces (negative: backward) from `from`. Long moves speed up to fit
## pawn_move_max_seconds.
func queue_move(player_id: int, from: int, steps: int, show_land_card: bool = false, salary: int = 0) -> void:
	if steps == 0:
		return
	var per := UiStyle.num("pawn_step_seconds", 0.14)
	per = minf(per, UiStyle.num("pawn_move_max_seconds", 1.8) / absi(steps))
	_enqueue({"type": &"move", "player": player_id, "from": from, "steps": steps, "per": per,
			"dur": per * absi(steps), "salary": salary})
	if show_land_card:
		var destination := posmod(from + steps, Board.SPACE_COUNT)
		if controller != null and controller.board.spaces[destination].space_type == Space.Type.FREE_PARKING:
			queue_fx(&"anchor", {"player": player_id, "space": destination}, UiStyle.num("anchor_seconds", 0.6))
		if controller != null and controller.board.spaces[destination].space_type == Space.Type.RAILROAD:
			var owner := controller.board.spaces[destination].deed.owner
			queue_fx(&"gate_arrival", {"player": player_id, "space": destination, "owner": owner}, UiStyle.num("gate_arrival_seconds", 0.25))
		queue_land_card(destination)


## Straight arc from `from` to `to` (sent to the Brig).
func queue_jump(player_id: int, from: int, to: int, show_land_card: bool = false) -> void:
	_enqueue({"type": &"jump", "player": player_id, "from": from, "to": to,
			"dur": UiStyle.num("pawn_jump_seconds", 0.6)})
	if show_land_card:
		queue_land_card(to)


## One card per arrival, including card-driven moves and owned/mortgaged spaces.
## Snapshot words and numbers now; presentation never computes or changes rule results.
func queue_land_card(index: int) -> void:
	if not animate or controller == null:
		return
	var details := space_details(index)
	var lines := PackedStringArray([details[0]])
	for line in details:
		if line.begins_with("Price "):
			lines.append(line.get_slice("  |  ", 0))
		elif line.begins_with("Rent ") or line.begins_with("Pay $") or line == "Mortgaged" or line.begins_with("Owner:") or (line.length() > 0 and line.left(1).is_valid_int()):
			lines.append(line)
	var s := controller.board.spaces[index]
	var chrome := land_card_chrome(s.space_type)
	if s.space_type == Space.Type.STREET:
		chrome.stripe = controller.board.group_info.get(s.color_group_id, {}).get("color", chrome.stripe)
	var owner_color := Color.TRANSPARENT
	if s.deed != null and s.deed.owner >= 0:
		owner_color = controller.players[s.deed.owner].color
		lines.append("Owner: %s" % controller.players[s.deed.owner].display_name)
	_enqueue({"type": &"land_card", "index": index, "text": "\n".join(lines),
		"space_type": s.space_type, "owner_color": owner_color, "chrome": chrome,
		"dur": UiStyle.num("land_card_seconds", 2.6)})


## Stable types select vector chrome; words and prices never select the artwork.
static func land_card_chrome(space_type: int) -> Dictionary:
	var stripe := UiStyle.color("accent")
	var glyph := &"tab"
	var weight := 4.0
	match space_type:
		Space.Type.STREET:
			stripe = UiStyle.color("board_border")
			glyph = &"stripe"
		Space.Type.RAILROAD:
			glyph = &"ring"
		Space.Type.UTILITY:
			glyph = &"bolt"
		Space.Type.INCOME_TAX, Space.Type.LUXURY_TAX:
			stripe = UiStyle.color("alert")
			glyph = &"stamp"
			weight = 7.0 if space_type == Space.Type.INCOME_TAX else 3.0
		Space.Type.COMMUNITY_CHEST:
			stripe = UiStyle.color("accent_dim")
		Space.Type.GO, Space.Type.FREE_PARKING, Space.Type.JAIL_CORNER, Space.Type.GO_TO_JAIL:
			stripe = corner_tint(space_type)
			glyph = &"corner"
	return {"stripe": stripe, "glyph": glyph, "weight": weight}


## Shared draw/test pose: ballistic arrival, squash, rebound, settle, hold, windup and exit.
## Fractions are keyframe boundaries; arcs are sampled analytically, never a fade-only tween.
func land_card_pose() -> Dictionary:
	var active: bool = not _item.is_empty() and _item["type"] == &"land_card" and animate
	var pose := {"active": active, "text": "", "lift": 0.0, "scale": Vector2.ONE,
		"offset": Vector2.ZERO, "rotation": 0.0}
	if not active:
		return pose
	pose.text = _item["text"]
	var t := clampf(_t / float(_item["dur"]), 0.0, 1.0)
	var cell := _board_rect().size.x / GRID
	var arrival := UiStyle.num("land_card_arrive_fraction", 0.16)
	var impact := UiStyle.num("land_card_impact_fraction", 0.20)
	var settle := UiStyle.num("land_card_settle_fraction", 0.29)
	var windup := UiStyle.num("land_card_windup_fraction", 0.86)
	var exit_at := UiStyle.num("land_card_exit_fraction", 0.90)
	if t < arrival:
		var u := t / arrival
		pose.lift = cell * UiStyle.num("land_card_arc_height", 0.8) * 4.0 * u * (1.0 - u)
		var origin := _board_rect().position + (Vector2(cell_of(int(_item["index"]))) + Vector2.ONE * 0.5) * cell
		pose.offset = (origin - land_card_rect().get_center()) * (1.0 - smoothstep(0.0, 1.0, u))
		pose.scale = Vector2.ONE * lerpf(0.35, 1.0, u)
		pose.rotation = -0.18 * sin(PI * u)
	elif t < impact:
		var squash := 1.0 - (t - arrival) / (impact - arrival)
		pose.scale = Vector2(1.0 + 0.16 * squash, 1.0 - 0.18 * squash)
	elif t < settle:
		var u := (t - impact) / (settle - impact)
		pose.lift = cell * 0.18 * 4.0 * u * (1.0 - u)
		pose.rotation = 0.035 * sin(TAU * u)
		pose.scale = Vector2(1.0 - 0.04 * sin(PI * u), 1.0 + 0.04 * sin(PI * u))
	elif t > windup and t < exit_at:
		var u := (t - windup) / (exit_at - windup)
		pose.scale = Vector2(1.0 + 0.08 * u, 1.0 - 0.08 * u)
		pose.offset = Vector2(-cell * 0.12 * u, cell * 0.08 * u)
	elif t >= exit_at:
		var u := (t - exit_at) / (1.0 - exit_at)
		pose.offset = Vector2(cell * 9.0 * u * u, -cell * 1.5 * sin(PI * u))
		pose.rotation = 0.4 * u
		pose.scale = Vector2.ONE * (1.0 - 0.3 * u)
	return pose


## Between dice and the unchanged banner reservation. TODO Q21 device tune; a long toast now stops
## at the reservation (Q22 truncate-to-reserve). No new nodes, timers or input surfaces to clean up.
func land_card_rect() -> Rect2:
	var br := _board_rect()
	var cell := br.size.x / GRID
	var top := die_hit_rect().end.y + cell * 0.2
	var bottom := banner_rect().position.y - cell * 0.15
	return Rect2(br.position.x + cell * 1.6, top, cell * 7.8, maxf(cell, bottom - top))


func _draw_land_card() -> void:
	var pose := land_card_pose()
	if not pose.active:
		return
	var r := land_card_rect()
	var center: Vector2 = r.get_center() + pose.offset - Vector2(0, pose.lift)
	draw_set_transform(center.round(), pose.rotation, pose.scale)
	var box := Rect2(-r.size * 0.5, r.size)
	var accent: Color = _item.chrome.stripe
	var chrome := UiStyle.card_style(accent)
	chrome.set_corner_radius_all(0)
	chrome.draw(get_canvas_item(), box)
	# Square group stripe and stepped pixel corners, using the active pack palette.
	draw_rect(Rect2(box.position + Vector2(6, 5), Vector2(box.size.x - 12, float(_item.chrome.weight))), accent)
	if (_item.owner_color as Color).a > 0.0:
		draw_rect(Rect2(box.position + Vector2(3, 12), Vector2(3, box.size.y - 18)), _item.owner_color)
	var mark := box.position + Vector2(box.size.x - 16, 22)
	match _item.chrome.glyph:
		&"ring":
			draw_arc(mark, 7, 0, TAU, 24, UiStyle.color("accent"), 2)
		&"bolt":
			draw_polyline(PackedVector2Array([mark + Vector2(3, -7), mark + Vector2(-4, 0), mark + Vector2(4, 0), mark + Vector2(-3, 7)]), UiStyle.color("accent"), 2)
		&"stamp":
			draw_rect(Rect2(mark - Vector2.ONE * 6, Vector2.ONE * 12), accent, false, 2)
		&"corner":
			_draw_corner_icon(Rect2(mark - Vector2(16, 23), Vector2.ONE * 32), int(_item.space_type), UiStyle.color("accent"))
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(side * (box.size.x * 0.5 - 9) - 2, box.end.y - 9), Vector2(4, 4)), accent)
	var lines := String(pose.text).split("\n")
	var font := UiStyle.display_font()
	var fs := maxi(6, mini(int(r.size.x / 32.0), int((r.size.y - 20) / (lines.size() * 1.3))))
	var y := box.position.y + 12.0 + font.get_ascent(fs)
	for line in lines:
		draw_string(font, Vector2(box.position.x + 10, y), line, HORIZONTAL_ALIGNMENT_CENTER,
			box.size.x - 20, fs, UiStyle.color("text_muted") if line == "Mortgaged" else UiStyle.color("text"))
		y += font.get_height(fs)
	draw_set_transform(Vector2.ZERO)


## Runs `fn` once everything queued before it has played (at once when idle).
func queue_call(fn: Callable) -> void:
	_enqueue({"type": &"call", "fn": fn, "dur": 0.0})


## Timed presentation fx (`kind` names a pose in fx_pose; `info` carries ids and numbers from the
## game_event) that holds the queue, and so is_animating(), for `dur` seconds. Instant when animate
## is off or dur <= 0. Changes no rules state and no shown positions.
func queue_fx(kind: StringName, info: Dictionary, dur: float) -> void:
	_enqueue({"type": &"fx", "kind": kind, "info": info, "dur": maxf(0.0, dur)})


## Shared analytic FX pose. Only the matching active item contributes; no timers or orphan nodes.
## Unimplemented kinds retain neutral transforms for the later Pass B consumers.
func fx_pose(kind: StringName) -> Dictionary:
	var pose := {"active": false, "kind": kind, "t": 0.0, "info": {}, "lift": 0.0, "scale": Vector2.ONE,
		"offset": Vector2.ZERO, "rotation": 0.0}
	if _item.is_empty() or _item["type"] != &"fx" or _item["kind"] != kind or not animate:
		return pose
	pose.active = true
	pose.t = clampf(_t / maxf(float(_item["dur"]), 0.0001), 0.0, 1.0)
	pose.info = _item["info"]
	var t: float = pose.t
	match kind:
		&"victory":
			var sweep := UiStyle.num("victory_sweep_seconds", 0.6) / float(_item.dur)
			var laurel := UiStyle.num("victory_laurel_seconds", 0.4) / float(_item.dur)
			pose.sweep = clampf(t / sweep, 0, 1)
			pose.laurel = smoothstep(sweep, minf(1.0, sweep + laurel), t)
			var height := UiStyle.num("victory_hop_height", 0.4) if t < 0.5 else UiStyle.num("victory_second_hop_height", 0.3)
			pose.lift = height * sin(PI * fmod(t * 2.0, 1.0))
		&"anchor":
			pose.rotation = TAU * smoothstep(0.0, 1.0, t)
			pose.lift = UiStyle.num("anchor_settle_height", 0.12) * sin(PI * minf(t * 2, 1))
		&"claim_bar":
			pose.lift = UiStyle.num("claim_hop_height", 0.3) * sin(PI * t)
		&"gavel":
			pose.rotation = -0.8 * sin(PI * minf(t * 2.0, 1.0))
			pose.offset = Vector2(0, -sin(PI * t))
	return pose


func anchor_pose() -> Dictionary:
	return fx_pose(&"anchor")


func queue_victory(player_id: int) -> void:
	queue_fx(&"victory", {"player": player_id}, UiStyle.num("victory_seconds", 1.2))


func victory_pose() -> Dictionary:
	return fx_pose(&"victory")


## Shared transient money arc. Numeric payload only; never changes a balance.
func queue_cash_fly(info: Dictionary) -> void:
	var duration := UiStyle.num("cash_fly_light_seconds", 0.45) if bool(info.get("light", false)) else UiStyle.num("cash_fly_seconds", 0.5)
	queue_fx(&"cash_fly", info.duplicate(true), duration)


func cash_fly_pose() -> Dictionary:
	var pose := fx_pose(&"cash_fly")
	pose.point = Vector2.ZERO
	pose.failed = bool(pose.info.get("failed", false))
	pose.receipt = 0.0
	if not pose.active:
		return pose
	var info: Dictionary = pose.info
	var cell := _board_rect().size.x / GRID
	var start := piece_state(int(info.player)).point
	var target := land_card_rect().get_center()
	if info.get("to", &"bank") is int:
		target = piece_state(int(info.to)).point
	var t: float = pose.t
	# tax is emitted before _charge; sample only as the queue plays after the synchronous rules step.
	if bool(info.get("tax", false)):
		for debt in controller.pending_debts:
			if debt.debtor == int(info.player) and debt.creditor == PropertyDeed.BANK and debt.amount == int(info.amount):
				pose.failed = true
	var u := smoothstep(0.0, 1.0, t)
	if pose.failed:
		var stall := UiStyle.num("cash_fly_stall_fraction", 0.45)
		u = minf(t / stall, 1.0) * stall if t < 0.6 else stall * (1.0 - smoothstep(0.6, 1.0, t))
	var height := UiStyle.num("cash_fly_height", 0.8)
	if bool(info.get("light", false)):
		height *= UiStyle.num("cash_fly_light_height_factor", 0.6)
	pose.point = start.lerp(target, u) - Vector2(0, cell * height * 4.0 * u * (1.0 - u))
	if bool(info.get("gate", false)):
		var via := _cell_rect(int(info.space)).get_center()
		var a := start.lerp(via, u)
		var b := via.lerp(target, u)
		pose.point = a.lerp(b, u) - Vector2(0, cell * height * 4 * u * (1 - u))
	if pose.failed and t > 0.6:
		pose.point.x += cell * UiStyle.num("cash_fly_return_shake", 0.06) * sin(TAU * 3 * t) * sin(PI * t)
	pose.scale = Vector2.ONE * lerpf(1.0, 0.3, u)
	if not pose.failed and not (info.get("to", &"bank") is int):
		pose.receipt = sin(PI * clampf((t - 0.7) / 0.3, 0, 1))
	return pose


func _cell_rect(index: int) -> Rect2:
	var br := _board_rect()
	var cell := br.size.x / GRID
	return Rect2(br.position + Vector2(cell_of(index)) * cell, Vector2.ONE * cell)


## Crossing beat belongs to the move item, never a second busy lane. Backward/jail moves cannot pay.
func go_crossing_pose() -> Dictionary:
	var pose := {"active": false, "t": 0.0, "amount": 0, "point": Vector2.ZERO}
	if _item.get("type") != &"move" or int(_item.get("salary", 0)) <= 0 or int(_item.steps) <= 0:
		return pose
	var crossing := Board.SPACE_COUNT - int(_item.from) - 1
	if crossing < 0 or crossing >= int(_item.steps):
		return pose
	var start := crossing * float(_item.per)
	var duration := minf(UiStyle.num("go_flourish_seconds", 0.4), float(_item.dur) - start)
	if _t < start or _t >= start + duration:
		return pose
	pose.active = animate
	pose.t = clampf((_t - start) / duration, 0, 1)
	pose.amount = int(_item.salary)
	var t: float = pose.t
	var cell := _board_rect().size.x / GRID
	pose.point = _cell_rect(0).get_center().lerp(piece_state(int(_item.player)).point, t) - Vector2(0, cell * UiStyle.num("go_tag_height", 0.6) * 4 * t * (1 - t))
	return pose


func _draw_go_crossing() -> void:
	var pose := go_crossing_pose()
	if not pose.active:
		return
	var r := _cell_rect(0)
	var tint := corner_tint(Space.Type.GO).lerp(UiStyle.color("accent"), pose.t)
	draw_arc(r.get_center(), r.size.x * 0.4, -PI * 0.5, -PI * 0.5 + TAU * float(pose.t), 40, tint, 3)
	var font := UiStyle.display_font()
	var label := "+$%d" % int(pose.amount)
	var at: Vector2 = pose.point - Vector2(r.size.x, 0)
	var fs := maxi(10, int(r.size.x * 0.35))
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x * 2, fs, 2, Color.BLACK)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x * 2, fs, UiStyle.color("text"))


func _draw_event_fx() -> void:
	if _item.get("type") != &"fx":
		return
	var kind: StringName = _item.kind
	var pose := fx_pose(kind)
	var info: Dictionary = pose.info
	var accent := UiStyle.color("accent")
	var cell := _board_rect().size.x / GRID
	match kind:
		&"victory":
			var winner := piece_state(int(info.player))
			var radius := _board_rect().size.length() * float(pose.sweep)
			var tint := Color(accent, 1.0 - float(pose.sweep))
			draw_arc(winner.rest, radius, 0, TAU, 96, tint, 3)
			var grow: float = pose.laurel
			if grow > 0:
				for side in [-1.0, 1.0]:
					var start := PI * 0.5
					var end := start + PI * grow
					draw_set_transform(winner.point, 0, Vector2(side, 1))
					draw_arc(Vector2.ZERO, cell * 0.45, start, end, 32, accent, 2)
					for leaf in range(6):
						if float(leaf + 1) / 6 > grow:
							continue
						var angle := start + PI * float(leaf + 1) / 7
						var point := Vector2.from_angle(angle) * cell * 0.45
						draw_line(point, point + Vector2.from_angle(angle - 0.5) * cell * 0.16, accent, 3)
					draw_set_transform(Vector2.ZERO)
		&"gate_arrival":
			var r := _cell_rect(int(info.space))
			var tint := controller.players[int(info.owner)].color if int(info.owner) >= 0 else accent
			draw_rect(r.grow(-2), Color(tint, sin(PI * float(pose.t))), false, 2)
			draw_arc(r.get_center(), cell * lerpf(0.1, 0.45, pose.t), 0, TAU, 32, Color(accent, 1.0 - float(pose.t)), 2)
		&"gate_count":
			var spaces: Array = info.spaces
			if not spaces.is_empty():
				var which := mini(int(float(pose.t) * spaces.size()), spaces.size() - 1)
				draw_rect(_cell_rect(int(spaces[which])).grow(-2), controller.players[int(info.player)].color, false, 3)
		&"anchor":
			var r := _cell_rect(int(info.space))
			var center := r.get_center()
			var tint := UiStyle.color("accent_dim").lerp(accent, sin(PI * float(pose.t)))
			draw_arc(center, cell * 0.24, pose.rotation, pose.rotation + PI * 1.7, 32, tint, 2)
			var end := center + Vector2.from_angle(pose.rotation) * cell * 0.3
			draw_circle(end, cell * 0.035, accent)
			var point := piece_state(int(info.player)).point
			var retract := 1.0 - smoothstep(0.75, 1.0, pose.t)
			draw_line(point, point.lerp(center, retract), tint, 1)
		&"gavel":
			var r := _cell_rect(int(info.space))
			draw_rect(r.grow(-2), Color(accent, absf(sin(TAU * float(pose.t)))), false, 3)
			var center := r.get_center().lerp(land_card_rect().get_center(), smoothstep(0, 1, pose.t))
			draw_set_transform(center, pose.rotation)
			draw_line(Vector2.ZERO, Vector2(0, cell * 0.3), accent, 3)
			draw_rect(Rect2(-cell * 0.2, -cell * 0.08, cell * 0.4, cell * 0.16), accent)
			draw_set_transform(Vector2.ZERO)
			_draw_label(UiStyle.display_font(), Rect2(center + Vector2(-cell * 2, cell * 0.4), Vector2(cell * 4, cell)), controller.board.spaces[int(info.space)].display_name)
		&"cash_fly":
			var cash := cash_fly_pose()
			draw_set_transform(cash.point, 0, cash.scale)
			var label := "-$%d" % int(info.amount)
			var font := UiStyle.display_font()
			var fs := maxi(10, int(cell * 0.35))
			var at := Vector2(-cell, 0)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, cell * 2, fs, 2, Color.BLACK)
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, cell * 2, fs, UiStyle.color("alert") if cash.failed else UiStyle.color("text"))
			if bool(info.get("gate", false)):
				draw_arc(Vector2(cell * 0.9, -cell * 0.12), cell * 0.12, 0, TAU, 20, accent, 2)
				if bool(info.get("double", false)):
					draw_arc(Vector2(cell * 1.2, -cell * 0.12), cell * 0.12, 0, TAU, 20, accent, 2)
			draw_set_transform(Vector2.ZERO)


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
		&"fx":
			pass  # a pose-only hold; nothing to apply once it ends
	queue_redraw()
	update_pieces()


## Plays the queue forward by `delta` seconds; called from _process, or by tests.
func advance(delta: float) -> void:
	if not animate and is_animating():
		sync_to_game()
		animation_finished.emit()
		return
	while not _item.is_empty() and delta > 0.0:
		var left := float(_item["dur"]) - _t
		if delta < left:
			_t += delta
			if _item["type"] == &"dice":
				_tumble_left -= delta
				if _tumble_left <= 0.0:
					_tumble = Vector2i(_rng.randi_range(1, 6), _rng.randi_range(1, 6))
					# Fast face changes at release, slower as the dice settle. Visual RNG only.
					_tumble_left = lerpf(UiStyle.num("dice_tumble_fast_seconds", 0.035),
						UiStyle.num("dice_tumble_slow_seconds", 0.11), _t / float(_item["dur"]))
			queue_redraw()
			update_pieces()
			return
		delta -= left
		var done := _item
		_item = {}
		_finish_item(done)
		_start_next()


func _process(delta: float) -> void:
	if die_ready:
		_idle_time += delta
		queue_redraw()
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
	s.in_jail = controller.players[player_id].in_jail
	var claim := fx_pose(&"claim_bar")
	if claim.active and int(claim.info.player) == player_id:
		s.lift = claim.lift
		s.point.y -= cell * s.lift
		s.moving = true
	var anchor := anchor_pose()
	if anchor.active and int(anchor.info.player) == player_id:
		s.lift = anchor.lift
		s.point.y -= cell * s.lift
		s.moving = true
	var victory := victory_pose()
	if victory.active and int(victory.info.player) == player_id:
		s.lift = victory.lift
		s.point.y -= cell * s.lift
		s.moving = true
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
	return banner_rect_in(_board_rect())


## banner_rect() for the board square `br`, in br's coordinates (Main keeps the turn panel and the
## overlay clear of it, but for a bottom-docked overlay with its sections open, Q22 1B).
static func banner_rect_in(br: Rect2) -> Rect2:
	var cell := br.size.x / GRID
	var inner := Rect2(br.position + Vector2(cell, cell) * 1.3, Vector2(cell, cell) * 8.4)
	return Rect2(inner.position + Vector2(0, inner.size.y * 0.42), Vector2(inner.size.x, inner.size.y * 0.36))


## The dialogue toast for `text` inside the banner reservation `reserve` (banner_rect_in, which stays
## what overlays and the turn panel keep clear of): the text wrapped at the reservation's text width
## (`font`, `font_size`, `line_spacing` between lines, as the banner Label draws it) plus `style`'s
## content margins, centered in the reservation (Q21: no near-empty card over the board). Taller
## content takes the whole reservation and no more (Q22 truncate-to-reserve: the banner's last line
## that fits ends in an ellipsis; the full line stays in the Log). Font metrics only, so it holds
## outside the tree too.
static func toast_rect_in(reserve: Rect2, text: String, font: Font, font_size: int, line_spacing: float,
		style: StyleBox) -> Rect2:
	var margins := style.get_minimum_size()
	if reserve.size.x <= margins.x:
		return reserve  # not laid out yet
	var para := TextParagraph.new()
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.width = reserve.size.x - margins.x
	para.add_string(text, font, font_size)
	var text_h := para.get_size().y + line_spacing * maxi(0, para.get_line_count() - 1)
	# 1 px past the widest line: the Label re-wraps at the toast's width and must keep the same breaks.
	var box := Vector2(minf(reserve.size.x, ceilf(para.get_size().x) + 1.0 + margins.x), ceilf(text_h) + margins.y)
	if box.y > reserve.size.y:
		return reserve
	return Rect2(reserve.get_center() - box * 0.5, box)


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
			var victory := victory_pose()
			if victory.active and s.deed.owner == int(victory.info.player):
				var source := piece_state(s.deed.owner).rest
				var radius := br.size.length() * float(victory.sweep)
				var flash := 1.0 - clampf(absf(source.distance_to(r.get_center()) - radius) / cell, 0, 1)
				owner_color = owner_color.lerp(gold, flash)
			var paint := fx_pose(&"claim_bar")
			var share := float(paint.t) if paint.active and int(paint.info.space) == s.index else 1.0
			draw_rect(Rect2(r.position + Vector2(cell * 0.06, cell * 0.8), Vector2(cell * 0.88 * share, cell * 0.12)), owner_color)
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
	_draw_event_fx()
	_draw_go_crossing()
	_draw_land_card()


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
		return [a.lerp(b, smoothstep(0.0, 1.0, u)) - Vector2(0, hop * 3.0 * lift), lift]
	var per := float(_item["per"])
	var dir := signi(int(_item["steps"]))
	var k := mini(int(_t / per), absi(int(_item["steps"])) - 1)
	var u2 := clampf((_t - k * per) / per, 0.0, 1.0)
	var i0 := int(_item["from"]) + dir * k
	var p0 := token_point(br, cell, pid, i0)
	var p1 := token_point(br, cell, pid, i0 + dir)
	var lift2 := sin(PI * u2)
	if posmod(i0, Board.SPACE_COUNT) == Board.SPACE_COUNT - 1 and dir > 0 and int(_item.get("salary", 0)) > 0:
		lift2 *= UiStyle.num("go_hop_boost", 1.2)
	return [p0.lerp(p1, smoothstep(0.0, 1.0, u2)) - Vector2(0, hop * lift2), lift2]


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
	var receipt := cash_fly_pose()
	var underline := UiStyle.color("accent_dim")
	if receipt.active:
		underline = underline.lerp(UiStyle.color("accent"), receipt.receipt)
	draw_line(Vector2(inner.get_center().x - cell * 1.5, y), Vector2(inner.get_center().x + cell * 1.5, y),
			underline, 1.0)
	var look := dice_look()
	var dice := dice_rect()
	var face := dice.size.y
	if look == &"ready":
		y = _draw_die_ready(dice, face, font, body_size)
	elif look != &"none":
		var faces := _faces()
		for die in range(2):
			var pose := dice_pose(die)
			draw_set_transform(pose.point, pose.rotation, pose.scale)
			_draw_die(Rect2(-Vector2.ONE * face * 0.5, Vector2.ONE * face), faces.x if die == 0 else faces.y, pose.pip_scale)
			if float(pose.glint) > 0.0:
				draw_arc(Vector2.ZERO, face * 0.62, 0, TAU, 32, Color(_die_tint, pose.glint), 2.0)
			draw_set_transform(Vector2.ZERO)
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
	var breathe := 0.65 + 0.15 * sin(TAU * _idle_time / UiStyle.num("dice_ready_period_seconds", 1.6))
	UiStyle.flat_box(Color(_die_tint, 0.14), Color(_die_tint, breathe), 1, int(minf(hit.size.y, hit.size.x) * 0.25), 0).draw(get_canvas_item(), hit)
	for x: float in [dice.position.x, dice.end.x - face]:
		UiStyle.flat_box(UiStyle.color("dice_face"), _die_tint, maxi(2, int(face * 0.1)), int(face * 0.18), 0).draw(
				get_canvas_item(), Rect2(x, dice.position.y, face, face))
	var top := maxf(hit.end.y, dice.end.y)
	draw_string(font, Vector2(hit.position.x - face, top + font.get_ascent(body_size)), "Tap to roll",
			HORIZONTAL_ALIGNMENT_CENTER, hit.size.x + face * 2.0, body_size, _die_tint.lerp(Color.WHITE, 0.3))
	return top + font.get_height(body_size)


## One die face: rounded ivory square with dark pips (theme dice_face / dice_pip).
func _draw_die(r: Rect2, value: int, pip_scale: float = 1.0) -> void:
	var face := UiStyle.flat_box(UiStyle.color("dice_face"), UiStyle.color("accent"), 2, int(r.size.x * 0.18), 0)
	face.draw(get_canvas_item(), r)
	var step := r.size.x / 4.0
	for p: Vector2i in PIPS.get(value, []):
		draw_circle(r.position + Vector2(step * (p.x + 1), step * (p.y + 1)), r.size.x * 0.09 * pip_scale, UiStyle.color("dice_pip"))


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
