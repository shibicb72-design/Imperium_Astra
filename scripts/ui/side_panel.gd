class_name SidePanel
extends Control
## Per-seat side panel (P5 SIDE_PANEL_A1, Shibi GO Oct 29 2026): one SeatCard per seat, in seat
## order, in a strip of the screen the panel owns (Main carves it out of the free band, A2; nothing
## else draws there). Layout and state only: no Tween, AnimationPlayer, _process motion or UiFx call
## here; the hooks below are instant setters that SIDE_PANEL_B_ANIM (Codex) animates in place.
##
## A card shows the seat's token (its SpacePiece, else a colour disc with the seat number) over its
## cash and, on a full card, a details column: name (ellipsis), deeds owned, net worth (NetWorth.of)
## and badges (jail / bankrupt / pardon cards / bot, in the chips' and overlay title's words). A
## compact card is the token over the cash. A card is the theme panel colour tinted with the seat
## colour (data/ui.json side_tint_alpha, light so theme "text" stays readable) with a thin
## seat-coloured border; the active seat (current_player() and not bankrupt) also shows glow_frame,
## a thicker seat-coloured border. Display-only: every node ignores the mouse.
##
## Layout (layout_for / rect_for, pure): one row when the strip is wider than tall, else one column;
## each card takes its share of the strip, capped at side_card_max_width x side_card_max_height; full
## where that holds the full content, else compact, else nothing shows (Rect2(): Main hides the
## panel). No card is below side_card_min_size either way; spare room stays empty, cards centred.
## Cards place their own nodes from font string widths (no containers), so the geometry is the same
## outside the tree.
##
## Hook contract (Codex animates inside these in SIDE_PANEL_B_ANIM and changes nothing else):
## - SeatCard.set_cash(value, delta) / set_owned(value, delta): delta = value - the last value the
##   card was given (0 on the first call at build, so a new match shows no popup; 0 when unchanged);
##   every panel refresh (show_values) sends both.
## - SeatCard.set_net_worth(value); SeatCard.set_active(on) (false for a bankrupt seat, sent in the
##   same refresh that first sets its bankrupt badge); SeatCard.set_badges(flags) with exactly the
##   keys {"jail": bool, "bankrupt": bool, "pardon": int (card count), "bot": bool}.
## - SidePanel.set_panel_shown(on): the only way the panel is shown or hidden.
## - Per card, nodes to animate without a layout change: fx_layer (plain Control over the card,
##   clip_contents off, for floating popups) and glow_frame (Panel with its own StyleBoxFlat in the
##   seat colour, carrying the static active border; border widths never change at run time). The
##   badge and number Labels are persistent (one per badge key, toggled by set_badges).
## - SeatCard.money_text(value): the cash and net worth figure ("$1500").
## - Cards are built once in setup() and never freed or rebuilt during the match; their content
##   changes only through the hooks (name and badge words are set once at build).

enum Mode { HIDDEN, COMPACT, FULL }

## set_badges keys, in the order the badges line shows them.
const BADGE_KEYS: Array[String] = ["jail", "bankrupt", "pardon", "bot"]
## The word before the net worth figure. TODO(Q-networth-label): `_placeholder`, the dig's neutral word.
const WORTH_LABEL_PLACEHOLDER := "worth"

## Set by Main like BoardView.animate (A2); A1 never reads it.
var animate := false
## One card per seat, in seat order (index = player id).
var cards: Array[SeatCard] = []
## How the cards are laid out now (the last place_in that could show them).
var mode: Mode = Mode.HIDDEN


## Where the cards go in a strip (layout_for), in the strip's coordinates: the mode, one rect per
## seat and their bounding rect (the panel's rect). HIDDEN: Rect2() and no cards.
class Layout extends RefCounted:
	var mode: SidePanel.Mode = SidePanel.Mode.HIDDEN
	var vertical := false
	var rect := Rect2()
	var cards: Array[Rect2] = []


## The seat's token in a card: its SpacePiece (tint = seat colour, seat dots on the chest), or a
## colour disc with the seat number (id + 1) where the piece cannot render at that size
## (data/ui.json side_token_piece_min_size). The disc's digit is the one card text not in theme
## "text": it sits on the light seat colour, so it takes the dark theme "panel" colour (contrast
## checked in tests/test_side_panel.gd for both packs).
class TokenView extends Control:
	## SpacePiece draws one unit as _cell * 0.22 (space_piece.gd:24; tests/test_side_panel.gd trips
	## if that literal changes) and spans -1.25 (helmet top) .. +1.3 (shadow) units around its origin,
	## about 2.6 units: fit() scales that span to the box and sets the origin 0.025 units above the
	## box centre so the span is centred.
	const PIECE_UNIT_PER_CELL := 0.22
	const PIECE_SPAN_UNITS := 2.6

	var piece: SpacePiece
	var seat_color := Color.WHITE
	var seat := 0

	func setup(color: Color, seat_id: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		seat_color = color
		seat = seat_id
		piece = SpacePiece.new()
		piece.name = "Piece"
		piece.tint = color
		piece.seat = seat_id
		add_child(piece)

	## A `side` x `side` token: the piece where it can render that small, else the disc.
	func fit(side: float) -> void:
		size = Vector2.ONE * side
		piece.visible = side >= UiStyle.num("side_token_piece_min_size", 16.0)
		if piece.visible:
			var unit := side / PIECE_SPAN_UNITS
			var state := BoardView.PieceState.new()
			state.cell = unit / PIECE_UNIT_PER_CELL
			state.visible = true
			piece.position = Vector2(side * 0.5, side * 0.5 - 0.025 * unit)
			piece.apply_piece_state(state)
		queue_redraw()

	func uses_piece() -> bool:
		return piece != null and piece.visible

	func disc_text() -> String:
		return str(seat + 1)

	## The disc's digit: theme panel colour, dark on the light seat colours.
	func disc_color() -> Color:
		return UiStyle.color("panel")

	func _draw() -> void:
		if uses_piece():
			return
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, seat_color)
		var font := get_theme_font("font", "Label")
		var fs := UiStyle.font("small")
		var w := font.get_string_size(disc_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline := (size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
		draw_string(font, Vector2((size.x - w) * 0.5, baseline), disc_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, disc_color())


## One seat's card (hook contract in the header). fit() places its nodes for full or compact content.
class SeatCard extends Control:
	var player_id := -1
	## Seat-tinted background with the thin seat-coloured border.
	var background: Panel
	var token: SidePanel.TokenView
	var cash_label: Label
	## Full-card column (hidden on compact cards): name, owned, net worth, badges.
	var details: Control
	var name_label: Label
	var owned_label: Label
	var worth_caption: Label
	var worth_label: Label
	## One Label per SidePanel.BADGE_KEYS key, under details; set_badges shows or hides each.
	var badges: Dictionary = {}
	## The active border (set_active): its own StyleBoxFlat in the seat colour, no fill.
	var glow_frame: Panel
	## Plain Control over the card for floating popups (B).
	var fx_layer: Control
	## What the hooks were given last (set_cash / set_owned deltas are value - last value).
	var last_cash := 0
	var last_cash_delta := 0
	var last_owned := 0
	var last_owned_delta := 0
	var compact := false

	var _pardon_word := ""
	var _deed_total := 0
	## The labels' font and size (font_small), fixed at build; layout measures with these.
	var _font: Font
	var _font_size := 14
	var _cash_slot := Rect2()
	var _worth_slot := Rect2()

	## The cash and net worth figure: the chips' $ form (main.gd:728) without the leading space.
	static func money_text(value: int) -> String:
		return "$%d" % value

	## Deeds owned, in the chips' words (main.gd:715).
	static func owned_text(count: int) -> String:
		return "%d deed%s" % [count, "" if count == 1 else "s"]

	## Distance from the card's edge to its content: the active border plus padding.
	static func inset() -> float:
		return UiStyle.num("side_active_border_width", 3.0) + UiStyle.num("side_card_padding", 1.0)

	## Builds the nodes once (never rebuilt). `deed_total`: deeds on the board, the most a seat can own.
	func build(p: Player, jail_word: String, pardon_word: String, deed_total: int) -> void:
		player_id = p.id
		name = "Seat%d" % (p.id + 1)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pardon_word = pardon_word
		_deed_total = deed_total
		_font = get_theme_font("font", "Label")
		_font_size = UiStyle.font("small")
		var radius := int(UiStyle.theme_num("panel", "corner_radius", 8))
		var tint := UiStyle.color("panel").lerp(p.color, UiStyle.num("side_tint_alpha", 0.2))
		background = _panel_node("Background", UiStyle.flat_box(tint, p.color,
				int(UiStyle.theme_num("panel", "border_width", 1)), radius, 0))
		token = SidePanel.TokenView.new()
		token.name = "Token"
		add_child(token)
		token.setup(p.color, p.id)
		token.fit(UiStyle.num("side_token_size", 20.0))  # scaled before the first fit(), never at the board's cell
		cash_label = _label(self, "Cash", "")
		cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		details = Control.new()
		details.name = "Details"
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(details)
		name_label = _label(details, "Name", p.display_name)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		owned_label = _label(details, "Owned", "")
		owned_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		worth_caption = _label(details, "WorthCaption", SidePanel.WORTH_LABEL_PLACEHOLDER)
		worth_label = _label(details, "Worth", "")
		var words := {"jail": jail_word, "bankrupt": "bankrupt", "pardon": pardon_word, "bot": "(bot)"}
		for key: String in SidePanel.BADGE_KEYS:
			var b := _label(details, "Badge_" + key, String(words[key]))
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.visible = false
			badges[key] = b
		var glow := UiStyle.flat_box(Color.TRANSPARENT, p.color, int(UiStyle.num("side_active_border_width", 3.0)), radius, 0)
		glow.draw_center = false
		glow_frame = _panel_node("GlowFrame", glow)
		glow_frame.visible = false
		fx_layer = Control.new()
		fx_layer.name = "FxLayer"
		fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.clip_contents = false
		add_child(fx_layer)

	# --- Hooks (instant in A1) ---------------------------------------------------------------

	func set_cash(value: int, delta: int) -> void:
		last_cash = value
		last_cash_delta = delta
		cash_label.text = money_text(value)
		_place_cash()

	func set_owned(value: int, delta: int) -> void:
		last_owned = value
		last_owned_delta = delta
		owned_label.text = owned_text(value)

	func set_net_worth(value: int) -> void:
		worth_label.text = money_text(value)
		_place_worth()

	func set_active(on: bool) -> void:
		glow_frame.visible = on

	func set_badges(flags: Dictionary) -> void:
		var held := int(flags.get("pardon", 0))
		(badges["jail"] as Label).visible = bool(flags.get("jail", false))
		(badges["bankrupt"] as Label).visible = bool(flags.get("bankrupt", false))
		var pardon := badges["pardon"] as Label
		pardon.visible = held > 0
		pardon.text = _pardon_word if held <= 1 else "%s x%d" % [_pardon_word, held]
		(badges["bot"] as Label).visible = bool(flags.get("bot", false))
		_flow_badges()

	# --- Layout ------------------------------------------------------------------------------

	## Smallest card that shows this card's content whole (font string widths plus the data/ui.json
	## side_* sizes, figures measured with side_money_sample), never below side_card_min_size.
	func min_size(compact_mode: bool) -> Vector2:
		var need := _block_size()
		if not compact_mode:
			var d := _details_size()
			need = Vector2(need.x + UiStyle.num("side_column_gap", 6.0) + d.x, maxf(need.y, d.y))
		var lo := UiStyle.num("side_card_min_size", 50.0)
		return (need + Vector2.ONE * 2.0 * inset()).ceil().max(Vector2.ONE * lo)

	## Sizes the card and places its nodes: the token over the cash (centred on a compact card, at
	## the left of a full one), then the details column; layers cover the whole card.
	func fit(card_size: Vector2, compact_mode: bool) -> void:
		compact = compact_mode
		size = card_size
		for layer: Control in [background, glow_frame, fx_layer]:
			layer.position = Vector2.ZERO
			layer.size = card_size
		var pad := inset()
		var content := Rect2(Vector2.ONE * pad, card_size - Vector2.ONE * 2.0 * pad)
		var block := _block_size()
		var t := UiStyle.num("side_token_size", 20.0)
		var gap := UiStyle.num("side_line_gap", 2.0)
		var h := _line_h()
		var x := content.position.x + (floorf((content.size.x - block.x) * 0.5) if compact_mode else 0.0)
		var y := content.position.y + floorf((content.size.y - block.y) * 0.5)
		token.position = Vector2(x + floorf((block.x - t) * 0.5), y)
		token.fit(t)
		_cash_slot = Rect2(x, y + t + gap, block.x, h)
		_place_cash()
		details.visible = not compact_mode
		if compact_mode:
			return
		var d := _details_size()
		var dx := x + block.x + UiStyle.num("side_column_gap", 6.0)
		details.position = Vector2(dx, content.position.y + floorf((content.size.y - d.y) * 0.5))
		details.size = Vector2(content.end.x - dx, d.y)
		var w := details.size.x
		name_label.position = Vector2(0, _line_y(0))
		name_label.size = Vector2(w, h)
		owned_label.position = Vector2(0, _line_y(1))
		owned_label.size = Vector2(w, h)
		var caption_w := _text_w(worth_caption.text)
		worth_caption.position = Vector2(0, _line_y(2))
		worth_caption.size = Vector2(caption_w, h)
		var space := _text_w(" ")
		_worth_slot = Rect2(caption_w + space, _line_y(2), w - caption_w - space, h)
		_place_worth()
		_flow_badges()

	## The figure shows whole: at least its text wide, centred under the token (a figure wider than
	## side_money_sample grows both ways).
	func _place_cash() -> void:
		var w := maxf(_cash_slot.size.x, _text_w(cash_label.text))
		cash_label.position = Vector2(_cash_slot.get_center().x - w * 0.5, _cash_slot.position.y)
		cash_label.size = Vector2(w, _cash_slot.size.y)

	func _place_worth() -> void:
		worth_label.position = _worth_slot.position
		worth_label.size = Vector2(maxf(_worth_slot.size.x, _text_w(worth_label.text)), _worth_slot.size.y)

	## Shown badges left to right on the details' last line, in BADGE_KEYS order: whole where they
	## fit, else the shortest stay whole and the rest share what is left, each ending in an ellipsis,
	## so badges never overlap or leave the card.
	func _flow_badges() -> void:
		var h := _line_h()
		var y := _line_y(3)
		var gap := UiStyle.num("side_column_gap", 6.0)
		var shown: Array[Label] = []
		for key: String in SidePanel.BADGE_KEYS:
			if (badges[key] as Label).visible:
				shown.append(badges[key])
		var left := maxf(details.size.x - gap * maxf(shown.size() - 1, 0.0), 0.0)
		var by_width := shown.duplicate()
		by_width.sort_custom(func(a: Label, b: Label) -> bool: return _text_w(a.text) < _text_w(b.text))
		var widths := {}
		for i in by_width.size():
			# Only the share is floored: a badge that fits keeps its exact text width (no false ellipsis).
			var bw := minf(_text_w(by_width[i].text), floorf(left / (by_width.size() - i)))
			widths[by_width[i]] = bw
			left -= bw
		var x := 0.0
		for key: String in SidePanel.BADGE_KEYS:
			var b := badges[key] as Label
			var bw: float = widths.get(b, 1.0)
			b.position = Vector2(x if b.visible else 0.0, y)
			b.size = Vector2(maxf(bw, 1.0), h)
			if b.visible:
				x += bw + gap

	## Token over cash, measured with data/ui.json side_money_sample.
	func _block_size() -> Vector2:
		var t := UiStyle.num("side_token_size", 20.0)
		var sample := money_text(int(UiStyle.num("side_money_sample", 9999.0)))
		return Vector2(maxf(t, _text_w(sample)), t + UiStyle.num("side_line_gap", 2.0) + _line_h())

	## Name, owned, net worth and badge lines: as wide as the name, the most deeds a seat can own and
	## the captioned sample figure.
	func _details_size() -> Vector2:
		var sample := money_text(int(UiStyle.num("side_money_sample", 9999.0)))
		var w := maxf(_text_w(name_label.text), maxf(_text_w(owned_text(_deed_total)),
				_text_w(worth_caption.text) + _text_w(" ") + _text_w(sample)))
		return Vector2(w, _line_y(3) + _line_h())

	## Top of details line `i` (0 name, 1 owned, 2 net worth, 3 badges).
	func _line_y(i: int) -> float:
		return i * (_line_h() + UiStyle.num("side_line_gap", 2.0))

	func _text_w(text: String) -> float:
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x

	func _line_h() -> float:
		return _font.get_height(_font_size)

	## One-line label in theme "text" at font_small. LabelSettings rather than theme overrides: a
	## Label's theme cache takes overrides only once it enters the tree, while its settings hold
	## everywhere, so the label measures and draws as _text_w / _line_h say in and out of the tree.
	func _label(parent: Control, node_name: String, text: String) -> Label:
		var l := Label.new()
		l.name = node_name
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ls := LabelSettings.new()
		ls.font = _font
		ls.font_size = _font_size
		ls.font_color = UiStyle.color("text")
		ls.line_spacing = 0.0
		l.label_settings = ls
		parent.add_child(l)
		return l

	func _panel_node(node_name: String, style: StyleBoxFlat) -> Panel:
		var panel := Panel.new()
		panel.name = node_name
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		return panel


## One seat's values for its card (pure view-model, headless-testable): id, name, token colour,
## cash, deeds owned (mortgaged ones included, as the chips count them), net worth (NetWorth.of),
## active (current_player() and not bankrupt, the chips' guard main.gd:751) and the badge flags.
static func seat_view(tc: TurnController, player: Player) -> Dictionary:
	return {
		"id": player.id,
		"name": player.display_name,
		"color": player.color,
		"cash": player.cash,
		"owned": tc.board.deeds_owned_by(player.id).size(),
		"net_worth": NetWorth.of(tc.board, player, tc.config),
		"active": player == tc.current_player() and not player.is_bankrupt,
		"badges": {
			"jail": player.in_jail,
			"bankrupt": player.is_bankrupt,
			"pardon": player.goojf_cards.size(),
			"bot": player.is_bot,
		},
	}


## Cards for `seats` seats in `strip` (any coordinates; the result uses the same): one row when the
## strip is wider than tall, else one column. Each card gets its share of the strip's length (less
## side_card_gap between cards) and the strip's depth, capped at side_card_max_width x
## side_card_max_height and floored to whole units: FULL where that is at least `full_min` both
## ways, else COMPACT where at least `compact_min`, else HIDDEN; neither minimum is taken below
## side_card_min_size, so no shown card is smaller. The cards are centred both ways.
static func layout_for(strip: Rect2, seats: int, full_min: Vector2, compact_min: Vector2) -> Layout:
	var out := Layout.new()
	if seats <= 0 or strip.size.x <= 0.0 or strip.size.y <= 0.0:
		return out
	var lo := Vector2.ONE * UiStyle.num("side_card_min_size", 50.0)
	full_min = full_min.max(lo)
	compact_min = compact_min.max(lo)
	var vertical := strip.size.x <= strip.size.y
	var gap := UiStyle.num("side_card_gap", 4.0)
	var cap := Vector2(UiStyle.num("side_card_max_width", 200.0), UiStyle.num("side_card_max_height", 120.0))
	var along := strip.size.y if vertical else strip.size.x
	var across := strip.size.x if vertical else strip.size.y
	var length := floorf(minf((along - gap * (seats - 1)) / seats, cap.y if vertical else cap.x))
	var depth := floorf(minf(across, cap.x if vertical else cap.y))
	var card := Vector2(depth, length) if vertical else Vector2(length, depth)
	if card.x >= full_min.x and card.y >= full_min.y:
		out.mode = Mode.FULL
	elif card.x >= compact_min.x and card.y >= compact_min.y:
		out.mode = Mode.COMPACT
	else:
		return out
	out.vertical = vertical
	var lead := floorf((along - (length * seats + gap * (seats - 1))) * 0.5)
	var side := floorf((across - depth) * 0.5)
	for i in seats:
		var t := lead + i * (length + gap)
		out.cards.append(Rect2(strip.position + (Vector2(side, t) if vertical else Vector2(t, side)), card))
	out.rect = Rect2(out.cards[0].position, out.cards[-1].end - out.cards[0].position)
	return out


## The panel's rect for `seats` cards in `strip` (layout_for), or Rect2() when they cannot show.
static func rect_for(strip: Rect2, seats: int, full_min: Vector2, compact_min: Vector2) -> Rect2:
	return layout_for(strip, seats, full_min, compact_min).rect


## Builds one card per seat of `tc` in seat order and shows their values (deltas 0). Once per match:
## a second call is refused (cards are never rebuilt; a new match builds a new panel). The cards
## take the label font they resolve here, so set the panel up inside Main to follow a HUD font.
func setup(tc: TurnController) -> void:
	if not cards.is_empty():
		push_error("SidePanel.setup: already set up; a new match needs a new panel")
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var deeds := 0
	for s in tc.board.spaces:
		if s.deed != null:
			deeds += 1
	for p in tc.players:
		var card := SeatCard.new()
		add_child(card)
		card.build(p, "in %s" % tc.board.term("jail"), tc.board.term("pardon"), deeds)
		cards.append(card)
	_push(tc, true)


## Panel refresh: every card's hooks from seat_view (Main queues it behind the board, A2).
func show_values(tc: TurnController) -> void:
	_push(tc, false)


## The only way the panel shows or hides (instant in A1).
func set_panel_shown(on: bool) -> void:
	visible = on


## Lays the cards out in `strip` (the parent's coordinates) and takes their bounding rect, which it
## returns; Rect2() when the strip cannot hold them (the cards keep their last placement and the
## caller hides the panel). Never shows or hides the panel itself.
func place_in(strip: Rect2) -> Rect2:
	var lay := layout_for(strip, cards.size(), full_min_size(), compact_min_size())
	if lay.mode == Mode.HIDDEN:
		return Rect2()
	mode = lay.mode
	position = lay.rect.position
	size = lay.rect.size
	for i in cards.size():
		cards[i].position = lay.cards[i].position - lay.rect.position
		cards[i].fit(lay.cards[i].size, mode == Mode.COMPACT)
	return lay.rect


## Smallest card that shows every seat's full content (the longest seat name whole).
func full_min_size() -> Vector2:
	var out := Vector2.ZERO
	for c in cards:
		out = out.max(c.min_size(false))
	return out


## Smallest compact card (token over the cash) for every seat.
func compact_min_size() -> Vector2:
	var out := Vector2.ZERO
	for c in cards:
		out = out.max(c.min_size(true))
	return out


func _push(tc: TurnController, first: bool) -> void:
	for card in cards:
		var v := seat_view(tc, tc.players[card.player_id])
		var cash: int = v["cash"]
		var owned: int = v["owned"]
		card.set_cash(cash, 0 if first else cash - card.last_cash)
		card.set_owned(owned, 0 if first else owned - card.last_owned)
		card.set_net_worth(v["net_worth"])
		card.set_badges(v["badges"])
		card.set_active(v["active"])
