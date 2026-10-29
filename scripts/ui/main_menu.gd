class_name MainMenu
extends Control
## Pre-match main menu (MAIN_MENU_STARK): Monopoly Go-style chrome, i.e. sharp gel / tactile pills
## over the soft moving MainMenuBackground. Top: the profile pill (level badge, name, thin progress)
## and the round Social and Settings buttons. Center: a floating angled GO tile with a metallic
## token and a translucent die over a soft shadow (decorative; not the match die). Bottom: one
## massive red PLAY pill. Left: the promo card and the green SHOP pill. The right edge stays clear
## (the right-side promo stack is dropped) and there are no currency or resource bars.
## PLAY emits play_requested and Main opens the seat setup (OPEN_QUESTIONS Q19). SHOP, Social,
## Settings, the promo card and the profile are stubs that open a placeholder card: no store,
## backend, social or event wiring. Chrome colors and sizes come from data/ui.json main_menu and
## look the same in every theme pack; only the backdrop follows the pack. All chrome is drawn
## (original vectors, no image assets) on plain Buttons, so touch, mouse and ui_accept press it.
## Layout comes from the rect (chrome_rects()): narrow screens stack the left column under the
## centerpiece, wider ones put it beside. One canvas unit is about 1 dp (DisplayScale).
## Presentation only.

signal play_requested

const CONFIG := "main_menu"
## Chrome laid out by chrome_rects(); each node carries the same name.
const CHROME: Array[StringName] = [&"Profile", &"Social", &"Settings", &"Centerpiece", &"Promo", &"Shop", &"Play"]

var background: MainMenuBackground
var centerpiece: Control
var profile_button: Button
var social_button: Button
var settings_button: Button
var promo_button: Button
var shop_button: Button
var play_button: Button
## Placeholder layer the stub buttons open: dims the menu, swallows taps, shows one card.
var stub: Control
var stub_close: Button
var stub_title := ""
## Seconds of menu time (centerpiece float, promo burst); advance() moves it with the backdrop.
var time := 0.0

var _scale := 0.0
var _font: FontVariation
var _nodes: Dictionary = {}


## Builds the menu. `scale` is the DisplayScale factor (0 off-device / tests: no insets).
func setup(scale: float = 0.0) -> void:
	_scale = scale
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = knob("embolden", 0.9)
	background = MainMenuBackground.new()
	background.name = &"Background"
	add_child(background)
	centerpiece = Control.new()
	centerpiece.name = &"Centerpiece"
	centerpiece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centerpiece.draw.connect(_paint_centerpiece)
	add_child(centerpiece)
	profile_button = _button(self, &"Profile", _paint_profile, open_stub.bind("Profile"))
	social_button = _button(self, &"Social", _paint_pill.bind(_spec("", &"friends", "round", 0)),
			open_stub.bind("Friends"))
	settings_button = _button(self, &"Settings", _paint_pill.bind(_spec("", &"gear", "round", 0)),
			open_stub.bind("Settings"))
	promo_button = _button(self, &"Promo", _paint_promo, open_stub.bind("Event"))
	shop_button = _button(self, &"Shop", _paint_pill.bind(_spec("SHOP", &"hat", "shop", int(knob("shop_font", 22.0)))),
			open_stub.bind("Shop"))
	play_button = _button(self, &"Play", _paint_pill.bind(_spec("PLAY", &"dice", "play", int(knob("play_font", 36.0)))),
			play_requested.emit)
	for n: StringName in CHROME:
		_nodes[n] = get_node(NodePath(String(n)))
	stub = Control.new()
	stub.name = &"Stub"
	stub.visible = false
	stub.draw.connect(_paint_stub)
	add_child(stub)
	stub_close = _button(stub, &"StubClose", _paint_pill.bind(_spec("OK", &"", "round", int(knob("shop_font", 22.0)))),
			close_stub)
	resized.connect(layout)
	layout()
	if is_inside_tree():
		play_button.grab_focus.call_deferred()


## data/ui.json main_menu ({} when absent).
static func config() -> Dictionary:
	var v: Variant = UiStyle.data().get(CONFIG, {})
	return v if v is Dictionary else {}


static func knob(key: String, fallback: float) -> float:
	return float(config().get(key, fallback))


## Chrome color `key` from data/ui.json main_menu colors (the same in every pack); a missing key
## shows magenta (UiStyle.MISSING_COLOR) so gaps are obvious.
static func chrome_color(key: String, fallback: Color = Color.MAGENTA) -> Color:
	var colors: Variant = config().get("colors", {})
	var v: Variant = colors.get(key) if colors is Dictionary else null
	return Color.html(v) if v is String and Color.html_is_valid(v) else fallback


## Placeholder text `key` (profile name, promo copy, stub line) until real sources exist.
static func placeholder(key: String, fallback: String) -> String:
	return String(config().get(key, fallback))


## Centerpiece rise at time `t` in canvas units: 0 (resting) .. main_menu float_height.
static func float_offset(t: float) -> float:
	var period := maxf(knob("float_seconds", 3.2), 0.1)
	return knob("float_height", 10.0) * (0.5 - 0.5 * cos(TAU * t / period))


## Menu-local rect of every CHROME element, from the size, screen margin and safe-area insets.
## Narrow screens stack the left column (promo card, SHOP) above PLAY under the centerpiece; wider
## ones put it beside the centerpiece, which stays centered. Below the top bar nothing sits on the
## right edge (the dropped promo stack).
func chrome_rects() -> Dictionary:
	var insets := DisplayScale.safe_insets(_scale) if _scale > 0.0 else Vector4.ZERO
	var m := UiStyle.num("screen_margin", 8.0)
	var area := Rect2(insets.x + m, insets.y + m, maxf(size.x - insets.x - insets.z - m * 2.0, 0.0),
			maxf(size.y - insets.y - insets.w - m * 2.0, 0.0))
	var gap := knob("gap", 10.0)
	var bar := maxf(knob("top_bar_height", 54.0), UiStyle.touch())
	var out := {}
	out[&"Settings"] = Rect2(area.end.x - bar, area.position.y, bar, bar)
	out[&"Social"] = Rect2(area.end.x - bar * 2.0 - gap, area.position.y, bar, bar)
	var profile_w := clampf(area.size.x - bar * 2.0 - gap * 3.0, 0.0, knob("profile_max_width", 240.0))
	out[&"Profile"] = Rect2(area.position, Vector2(profile_w, bar))
	var play_h := maxf(knob("play_height", 84.0), UiStyle.touch())
	var play_w := minf(clampf(area.size.x * knob("play_width_share", 0.72), knob("play_min_width", 220.0),
			knob("play_max_width", 520.0)), area.size.x)
	out[&"Play"] = Rect2(area.position.x + (area.size.x - play_w) * 0.5, area.end.y - play_h, play_w, play_h)
	var band := Rect2(area.position.x, area.position.y + bar + gap, area.size.x,
			maxf(area.size.y - bar - play_h - gap * 2.0, 0.0))
	var col_w := clampf(area.size.x * knob("promo_width_share", 0.28), knob("promo_min_width", 112.0),
			knob("promo_max_width", 168.0))
	var shop_h := maxf(knob("shop_height", 54.0), UiStyle.touch())
	var promo_h := clampf(col_w * knob("promo_aspect", 1.12), 0.0, maxf(band.size.y - shop_h - gap, 0.0))
	var col_h := promo_h + gap + shop_h
	var col_y: float
	if area.size.x - (col_w + gap) * 2.0 >= knob("center_min_width", 240.0):
		col_y = band.position.y + (band.size.y - col_h) * 0.5
		var side := col_w + gap
		out[&"Centerpiece"] = Rect2(band.position.x + side, band.position.y, band.size.x - side * 2.0, band.size.y)
	else:
		col_y = band.end.y - col_h
		out[&"Centerpiece"] = Rect2(band.position, Vector2(band.size.x, maxf(col_y - gap - band.position.y, 0.0)))
	out[&"Promo"] = Rect2(area.position.x, col_y, col_w, promo_h)
	out[&"Shop"] = Rect2(area.position.x, col_y + promo_h + gap, col_w, shop_h)
	return out


## The placeholder card's rect, centered on the menu.
func stub_card_rect() -> Rect2:
	var w := maxf(minf(size.x - 32.0, knob("stub_width", 320.0)), 0.0)
	var h := maxf(minf(size.y - 32.0, knob("stub_height", 220.0)), 0.0)
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


## Places every chrome node at its chrome_rects() rect; on resize (tests call it after sizing).
func layout() -> void:
	var rects := chrome_rects()
	for n: StringName in rects:
		var c: Control = _nodes[n]
		var r: Rect2 = rects[n]
		c.position = r.position
		c.size = r.size
		c.queue_redraw()
	background.position = Vector2.ZERO
	background.size = size
	background.layout()
	stub.position = Vector2.ZERO
	stub.size = size
	var card := stub_card_rect()
	var close := Vector2(minf(card.size.x - 32.0, 180.0), maxf(UiStyle.touch(), 54.0))
	stub_close.position = Vector2(card.get_center().x - close.x * 0.5, card.end.y - close.y - 22.0)
	stub_close.size = close


## Moves the menu clock: backdrop pan and props, centerpiece float, promo burst. _process calls it
## in the tree; tests call it by hand.
func advance(delta: float) -> void:
	if background == null:
		return  # not set up yet
	time += delta
	background.advance(delta)
	centerpiece.queue_redraw()
	promo_button.queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Re-applies the active pack (after UiStyle.set_theme): only the backdrop follows the pack.
func refresh_theme() -> void:
	background.refresh_theme()


## Opens the placeholder card titled `title` (stub for a feature that is not built yet).
func open_stub(title: String) -> void:
	stub_title = title
	stub.visible = true
	stub.queue_redraw()
	if stub_close.is_inside_tree():
		stub_close.grab_focus()


func close_stub() -> void:
	stub.visible = false


func stub_open() -> bool:
	return stub.visible


## A drawn chrome button under `parent`: Button press handling (touch, mouse, ui_accept) with every
## stylebox empty, painted by `paint` (called with the button).
func _button(parent: Control, node_name: StringName, paint: Callable, action: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		b.add_theme_stylebox_override(s, empty)
	b.draw.connect(paint.bind(b))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Paint spec for a gel pill: label, icon, palette (main_menu colors prefix) and font size.
func _spec(label: String, icon: StringName, palette: String, font_size: int) -> Dictionary:
	return {"label": label, "icon": icon, "font_size": font_size, "body": chrome_color(palette),
			"lip": chrome_color(palette + "_lip"), "outline": chrome_color(palette + "_outline")}


## Gel body for button `b` over `r`: soft drop shadow and a darker lip under a glossy body; a press
## sinks the body onto the lip. Returns the body rect for the content.
func _gel(b: Button, r: Rect2, body: Color, lip: Color, radius: float) -> Rect2:
	var mode := b.get_draw_mode()
	var down := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
	var lip_h := minf(knob("lip", 6.0), r.size.y * 0.14)
	var sink := lip_h * 0.7 if down else 0.0
	if mode == BaseButton.DRAW_HOVER:
		body = body.lightened(0.08)
	elif mode == BaseButton.DRAW_DISABLED:
		body = body.lerp(Color(0.55, 0.55, 0.6), 0.6)
	var edge := lip.darkened(0.45)
	var base := UiStyle.flat_box(lip, edge, 2, int(radius), 0)
	base.shadow_color = chrome_color("shadow", Color(0.0, 0.0, 0.0, 0.4))
	base.shadow_size = int(lip_h * 1.5)
	base.shadow_offset = Vector2(0.0, lip_h * 0.6)
	b.draw_style_box(base, Rect2(r.position.x, r.position.y + sink, r.size.x, r.size.y - sink))
	var face := Rect2(r.position.x, r.position.y + sink, r.size.x, r.size.y - lip_h)
	b.draw_style_box(UiStyle.flat_box(body, edge, 2, int(radius), 0), face)
	var inset := maxf(3.0, face.size.y * 0.1)
	var gloss := Rect2(face.position.x + inset * 1.5, face.position.y + inset * 0.6, face.size.x - inset * 3.0,
			face.size.y * 0.4)
	if gloss.size.x > 0.0 and gloss.size.y > 0.0:
		b.draw_style_box(UiStyle.flat_box(Color(1.0, 1.0, 1.0, 0.3), Color.TRANSPARENT, 0,
				int(minf(radius, gloss.size.y * 0.5)), 0), gloss)
	# Keyboard / gamepad focus ring; touch screens skip it (a tap would leave it showing).
	if b.has_focus() and not DisplayServer.is_touchscreen_available():
		var ring := UiStyle.flat_box(Color.TRANSPARENT, Color(1.0, 1.0, 1.0, 0.85), 3, int(radius) + 4, 0)
		ring.draw_center = false
		b.draw_style_box(ring, r.grow(4.0))
	return face


## Gel pill or round button (square rect): outlined white label and / or a vector icon.
func _paint_pill(b: Button, spec: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	var face := _gel(b, r, spec["body"], spec["lip"], r.size.y * 0.5)
	var ink := chrome_color("ink", Color.WHITE)
	var text := String(spec["label"])
	var icon: StringName = spec["icon"]
	if text == "":
		var only := face.size.y * 0.64
		_icon(b, icon, Rect2(face.get_center() - Vector2(only, only) * 0.5, Vector2(only, only)), ink)
		return
	var s := face.size.y * 0.58 if icon != &"" else 0.0
	var gap := s * 0.18
	var fs := _fit(text, int(spec["font_size"]), face.size.x - face.size.y * 0.7 - s - gap)
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := face.position.x + (face.size.x - tw - s - gap) * 0.5
	if s > 0.0:
		_icon(b, icon, Rect2(x, face.get_center().y - s * 0.5, s, s), ink)
		x += s + gap
	_text(b, text, Rect2(x, face.position.y, tw + 1.0, face.size.y), fs, ink, spec["outline"], 0.2,
			HORIZONTAL_ALIGNMENT_LEFT)


## Profile pill: white gel with a gold level badge, the name and a thin progress bar (placeholders:
## there is no profile backend yet).
func _paint_profile(b: Button) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	if r.size.x < 48.0 or r.size.y < 16.0:
		return
	var face := _gel(b, r, chrome_color("profile"), chrome_color("profile_lip"), r.size.y * 0.5)
	var d := face.size.y - 8.0
	var badge := Rect2(face.position + Vector2(4.0, 4.0), Vector2(d, d))
	b.draw_style_box(UiStyle.flat_box(chrome_color("level"), chrome_color("level_lip"), 3, int(d * 0.5), 0), badge)
	_text(b, str(int(knob("profile_level_placeholder", 1.0))), badge, int(d * 0.55), Color.WHITE,
			chrome_color("level_lip"))
	var x0 := badge.end.x + 8.0
	var right := face.end.x - face.size.y * 0.4
	if right - x0 < 16.0:
		return
	var ink := chrome_color("profile_text")
	_text(b, placeholder("profile_name_placeholder", "Player"), Rect2(x0, face.position.y + 3.0, right - x0,
			face.size.y * 0.55), int(knob("profile_font", 18.0)), ink, Color.TRANSPARENT, 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	var track := Rect2(x0, face.position.y + face.size.y * 0.66, right - x0, maxf(4.0, face.size.y * 0.13))
	var round_px := int(track.size.y * 0.5)
	b.draw_style_box(UiStyle.flat_box(chrome_color("progress_track"), Color.TRANSPARENT, 0, round_px, 0), track)
	var p := clampf(knob("profile_progress_placeholder", 0.35), 0.0, 1.0)
	if p > 0.0:
		b.draw_style_box(UiStyle.flat_box(chrome_color("progress_fill"), Color.TRANSPARENT, 0, round_px, 0),
				Rect2(track.position, Vector2(maxf(track.size.x * p, track.size.y), track.size.y)))


## Left promo card (event slot): two-tone gel card with a white rim, a turning burst behind two dice
## and placeholder copy (no event wiring yet).
func _paint_promo(b: Button) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	if r.size.x < 32.0 or r.size.y < 32.0:
		return
	var radius := minf(r.size.x, r.size.y) * 0.16
	var face := _gel(b, r, chrome_color("promo_bottom"), chrome_color("promo_lip"), radius)
	b.draw_style_box(UiStyle.flat_box(chrome_color("promo_top"), Color.TRANSPARENT, 0, int(radius), 0),
			Rect2(face.position, Vector2(face.size.x, face.size.y * 0.58)).grow(-3.0))
	var rim := UiStyle.flat_box(Color.TRANSPARENT, chrome_color("promo_rim"), 3, int(radius), 0)
	rim.draw_center = false
	b.draw_style_box(rim, face.grow(-2.0))
	var lip := chrome_color("promo_lip")
	var title_h := face.size.y * 0.2
	_text(b, placeholder("promo_title_placeholder", "EVENT"), Rect2(face.position.x + 8.0, face.position.y + 6.0,
			face.size.x - 16.0, title_h), int(title_h * 0.72), Color.WHITE, lip)
	var ec := Vector2(face.get_center().x, face.position.y + face.size.y * 0.53)
	var er := minf(face.size.x, face.size.y) * 0.3
	var burst := PackedVector2Array()
	for i in 16:
		burst.append(ec + Vector2.from_angle(TAU * i / 16.0 + time * 0.2) * (er if i % 2 == 0 else er * 0.62))
	b.draw_colored_polygon(burst, Color(chrome_color("burst"), 0.85))
	_icon(b, &"dice", Rect2(ec - Vector2(er, er) * 0.8, Vector2(er, er) * 1.6), Color.WHITE)
	var body_h := face.size.y * 0.18
	_text(b, placeholder("promo_body_placeholder", "Coming soon"), Rect2(face.position.x + 8.0,
			face.end.y - body_h - 8.0, face.size.x - 16.0, body_h), int(body_h * 0.62), Color.WHITE, lip)


## Floating centerpiece (decorative): an angled GO tile with depth, a metallic token on it and a
## translucent die above, bobbing over a soft shadow that shrinks and fades as they rise.
func _paint_centerpiece() -> void:
	var c := centerpiece
	var r := Rect2(Vector2.ZERO, c.size)
	var tile := minf(minf(r.size.x * knob("center_tile_share", 0.62), r.size.y * 0.66), knob("center_tile_max", 340.0))
	if tile < 24.0:
		return
	var rise := float_offset(time)
	var lift := rise / maxf(knob("float_height", 10.0), 0.001)
	var sway := sin(TAU * time / maxf(knob("float_seconds", 3.2) * 1.7, 0.1)) * knob("sway_radians", 0.04)
	var center := r.get_center() + Vector2(0.0, tile * 0.12)
	var shadow := chrome_color("shadow", Color(0.0, 0.0, 0.0, 0.4))
	for i in 4:
		c.draw_set_transform(center + Vector2(0.0, tile * 0.5), 0.0, Vector2(1.0, 0.22) * (1.0 - lift * 0.12))
		c.draw_circle(Vector2.ZERO, tile * 0.6 * (1.0 - i * 0.16), Color(shadow, shadow.a * 0.3 * (1.0 - lift * 0.4)))
	# The tile lies back in 3D: rotated and squashed, its side stacked under the face.
	var pos := center - Vector2(0.0, rise)
	var angle := -0.2 + sway
	var squash := Vector2(1.0, 0.56)
	var half := tile * 0.5
	var radius := int(tile * 0.08)
	var side := chrome_color("tile_side")
	var depth := tile * 0.08
	for i in range(8, 0, -1):
		c.draw_set_transform_matrix(Transform2D(angle, squash, 0.0, pos + Vector2(0.0, depth * i / 8.0)))
		c.draw_style_box(UiStyle.flat_box(side.darkened(0.15 * i / 8.0), side, 0, radius, 0),
				Rect2(-half, -half, tile, tile))
	c.draw_set_transform_matrix(Transform2D(angle, squash, 0.0, pos))
	var red := chrome_color("go_red")
	c.draw_style_box(UiStyle.flat_box(chrome_color("tile_face"), chrome_color("tile_border"),
			maxi(2, int(tile * 0.02)), radius, 0), Rect2(-half, -half, tile, tile))
	_text(c, "GO", Rect2(-half, -half + tile * 0.06, tile, tile * 0.5), int(tile * 0.42), red, red.darkened(0.5), 0.06)
	var ay := tile * 0.24
	var t2 := tile * 0.06
	var arrow := PackedVector2Array([Vector2(tile * 0.34, ay - t2), Vector2(-tile * 0.12, ay - t2),
			Vector2(-tile * 0.12, ay - t2 * 2.2), Vector2(-tile * 0.38, ay), Vector2(-tile * 0.12, ay + t2 * 2.2),
			Vector2(-tile * 0.12, ay + t2), Vector2(tile * 0.34, ay + t2)])
	c.draw_colored_polygon(arrow, red)
	arrow.append(arrow[0])
	c.draw_polyline(arrow, red.darkened(0.5), maxf(1.5, tile * 0.012), true)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	_paint_token(c, pos + Vector2(tile * 0.24, tile * 0.02), tile)
	var spin := 0.35 + 0.5 * sin(TAU * time / maxf(knob("die_spin_seconds", 14.0), 0.1))
	_paint_glass_die(c, pos + Vector2(-tile * 0.34, -tile * 0.42 - rise * 0.6), tile * 0.28, spin)


## Polished metal pawn (original vector): base disc, flared skirt with a bright streak and a dark
## rim, collar and a ball head with a specular highlight. `tile` sets the scale.
func _paint_token(c: Control, base: Vector2, tile: float) -> void:
	var light := chrome_color("token_light")
	var mid := chrome_color("token_mid")
	var dark := chrome_color("token_dark")
	var u := tile * 0.01
	c.draw_set_transform(base, 0.0, Vector2(1.0, 0.32))
	c.draw_circle(Vector2.ZERO, 14.0 * u, Color(0.0, 0.0, 0.0, 0.3))
	c.draw_set_transform(base + Vector2(0.0, -2.0 * u), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, 12.0 * u, dark)
	c.draw_set_transform(Vector2.ZERO)
	c.draw_rect(Rect2(base.x - 12.0 * u, base.y - 6.5 * u, 24.0 * u, 4.5 * u), mid)
	c.draw_set_transform(base + Vector2(0.0, -6.5 * u), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, 12.0 * u, light)
	c.draw_set_transform(Vector2.ZERO)
	c.draw_colored_polygon(_skirt(base, u, 1.0, 0.0), mid)
	c.draw_colored_polygon(_skirt(base, u, 0.22, -0.38), Color(light, 0.9))
	c.draw_colored_polygon(_skirt(base, u, 0.18, 0.78), Color(dark, 0.6))
	var neck := Vector2(base.x, base.y - 32.5 * u)
	c.draw_set_transform(neck, 0.0, Vector2(1.0, 0.35))
	c.draw_circle(Vector2.ZERO, 6.5 * u, dark)
	c.draw_set_transform(neck - Vector2(0.0, u), 0.0, Vector2(1.0, 0.35))
	c.draw_circle(Vector2.ZERO, 6.0 * u, light)
	c.draw_set_transform(Vector2.ZERO)
	var head := neck - Vector2(0.0, 8.5 * u)
	c.draw_circle(head, 8.0 * u, dark)
	c.draw_circle(head - Vector2(1.0, 1.0) * u, 7.0 * u, mid)
	c.draw_circle(head - Vector2(3.0, 3.0) * u, 2.8 * u, light)
	c.draw_circle(head - Vector2(3.6, 3.6) * u, 1.1 * u, Color.WHITE)


## Pawn skirt outline from the base to the neck: `width` of the full half-width at each height,
## shifted by `shift` (both shares of that half-width).
func _skirt(base: Vector2, u: float, width: float, shift: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in 11:
		var f := i / 10.0
		var y := base.y - (6.5 + f * 26.0) * u
		var hw := lerpf(9.0, 3.2, pow(f, 0.6)) * u
		left.append(Vector2(base.x + hw * (shift - width), y))
		right.insert(0, Vector2(base.x + hw * (shift + width), y))
	left.append_array(right)
	return left


## Translucent die: glass face with a lighter rim over a faint offset side for depth, a gloss streak
## and solid pips.
func _paint_glass_die(c: Control, p: Vector2, side: float, angle: float) -> void:
	var edge := chrome_color("die_edge", Color(1.0, 1.0, 1.0, 0.85))
	_die(c, p + Vector2(side * 0.09, side * 0.11), side, angle, Color(edge, edge.a * 0.35), Color.TRANSPARENT, 0)
	_die(c, p, side, angle, chrome_color("die_body", Color(1.0, 1.0, 1.0, 0.55)), chrome_color("die_pip"), 5, edge)
	c.draw_set_transform(p, angle, Vector2.ONE)
	c.draw_style_box(UiStyle.flat_box(Color(1.0, 1.0, 1.0, 0.45), Color.TRANSPARENT, 0, int(side * 0.06), 0),
			Rect2(-side * 0.36, -side * 0.42, side * 0.5, side * 0.12))
	c.draw_set_transform(Vector2.ZERO)


## Rounded die of side `side` at `p`, turned by `angle`, showing `pips` (0 = blank).
func _die(ci: CanvasItem, p: Vector2, side: float, angle: float, body: Color, pip: Color, pips: int,
		edge: Color = Color.TRANSPARENT) -> void:
	ci.draw_set_transform(p, angle, Vector2.ONE)
	var half := side * 0.5
	ci.draw_style_box(UiStyle.flat_box(body, edge if edge.a > 0.0 else body.darkened(0.25), maxi(1, int(side * 0.05)),
			int(side * 0.2), 0), Rect2(-half, -half, side, side))
	var q := side * 0.26
	var spots: Array[Vector2] = []
	match pips:
		0:
			spots = []
		1:
			spots = [Vector2.ZERO]
		2:
			spots = [Vector2(-q, -q), Vector2(q, q)]
		3:
			spots = [Vector2(-q, -q), Vector2.ZERO, Vector2(q, q)]
		4:
			spots = [Vector2(-q, -q), Vector2(q, -q), Vector2(-q, q), Vector2(q, q)]
		5:
			spots = [Vector2(-q, -q), Vector2(q, -q), Vector2.ZERO, Vector2(-q, q), Vector2(q, q)]
		_:
			spots = [Vector2(-q, -q), Vector2(q, -q), Vector2(-q, 0.0), Vector2(q, 0.0), Vector2(-q, q), Vector2(q, q)]
	for s in spots:
		ci.draw_circle(s, side * 0.085, pip)
	ci.draw_set_transform(Vector2.ZERO)


## Vector icon `kind` (dice, hat, friends, gear) inside square `r`.
func _icon(ci: CanvasItem, kind: StringName, r: Rect2, ink: Color) -> void:
	var c := r.get_center()
	var s := r.size.x
	match kind:
		&"dice":
			var pip := chrome_color("die_pip")
			_die(ci, c + Vector2(s * 0.14, s * 0.08), s * 0.58, 0.35, ink, pip, 5)
			_die(ci, c - Vector2(s * 0.16, s * 0.12), s * 0.58, -0.22, ink, pip, 3)
		&"hat":
			var hat := chrome_color("hat")
			ci.draw_rect(Rect2(c.x - s * 0.24, c.y - s * 0.38, s * 0.48, s * 0.6), hat)
			ci.draw_rect(Rect2(c.x - s * 0.24, c.y + s * 0.06, s * 0.48, s * 0.1), chrome_color("hat_band"))
			ci.draw_style_box(UiStyle.flat_box(hat, hat, 0, int(s * 0.07), 0),
					Rect2(c.x - s * 0.44, c.y + s * 0.2, s * 0.88, s * 0.14))
			ci.draw_rect(Rect2(c.x - s * 0.17, c.y - s * 0.34, s * 0.06, s * 0.36), Color(1.0, 1.0, 1.0, 0.25))
		&"friends":
			var back := Color(ink, 0.7)
			ci.draw_circle(c + Vector2(s * 0.16, -s * 0.16), s * 0.15, back)
			ci.draw_style_box(UiStyle.flat_box(back, back, 0, int(s * 0.16), 0),
					Rect2(c.x - s * 0.02, c.y + s * 0.02, s * 0.38, s * 0.3))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.1), s * 0.17, ink)
			ci.draw_style_box(UiStyle.flat_box(ink, ink, 0, int(s * 0.18), 0),
					Rect2(c.x - s * 0.34, c.y + s * 0.1, s * 0.48, s * 0.32))
		&"gear":
			for i in 8:
				ci.draw_set_transform(c, TAU * i / 8.0, Vector2.ONE)
				ci.draw_rect(Rect2(-s * 0.07, -s * 0.42, s * 0.14, s * 0.2), ink)
			ci.draw_set_transform(Vector2.ZERO)
			ci.draw_circle(c, s * 0.3, ink)
			ci.draw_circle(c, s * 0.12, chrome_color("round"))


## Largest font size up to `font_size` (down to 10) at which `text` fits `width` in the chrome font.
func _fit(text: String, font_size: int, width: float) -> int:
	var fs := font_size
	while fs > 10 and _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	return fs


## `text` in the chrome font inside `r` on `ci`, centered or left-aligned and shrunk to fit; a
## visible `outline` adds the gel labels' dark stroke, `stroke` (share of the size) thick.
func _text(ci: CanvasItem, text: String, r: Rect2, font_size: int, ink: Color,
		outline: Color = Color.TRANSPARENT, stroke: float = 0.2,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var fs := _fit(text, font_size, r.size.x)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := r.position.x + ((r.size.x - w) * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0)
	var y := r.position.y + (r.size.y + _font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	if outline.a > 0.0 and stroke > 0.0:
		ci.draw_string_outline(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
				maxi(2, int(fs * stroke)), outline)
	ci.draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, ink)


## Dimmed backdrop and the placeholder card: white gel card, title and the placeholder line.
func _paint_stub() -> void:
	stub.draw_rect(Rect2(Vector2.ZERO, stub.size), Color(0.0, 0.0, 0.0, 0.5))
	var card := stub_card_rect()
	if card.size.x < 64.0 or card.size.y < 64.0:
		return
	var lip := chrome_color("profile_lip")
	var edge := lip.darkened(0.45)
	var base := UiStyle.flat_box(lip, edge, 2, 22, 0)
	base.shadow_color = chrome_color("shadow", Color(0.0, 0.0, 0.0, 0.4))
	base.shadow_size = 14
	base.shadow_offset = Vector2(0.0, 6.0)
	stub.draw_style_box(base, card)
	stub.draw_style_box(UiStyle.flat_box(chrome_color("profile"), edge, 2, 22, 0),
			Rect2(card.position, card.size - Vector2(0.0, knob("lip", 6.0))))
	var ink := chrome_color("profile_text")
	_text(stub, stub_title, Rect2(card.position.x + 16.0, card.position.y + 18.0, card.size.x - 32.0, 44.0), 30, ink)
	_text(stub, placeholder("stub_text_placeholder", "Coming soon"), Rect2(card.position.x + 16.0,
			card.position.y + 70.0, card.size.x - 32.0, 32.0), 20, Color(ink, 0.75))
