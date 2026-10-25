class_name UiStyle
extends RefCounted
## Shared presentation sizes from data/ui.json and small builders, so every panel gets
## touch-sized controls (min data/ui.json touch_target, about 48 dp on phones once
## DisplayScale has set the window scale). Presentation only; no rule numbers here.

const UI_PATH := "res://data/ui.json"
const DEFAULT_THEME_PATH := "res://data/themes/imperium_astra/theme.json"
## Shown for a color key the theme pack lacks, so gaps are obvious on screen.
const MISSING_COLOR := Color.MAGENTA

static var _data: Dictionary = {}
static var _theme: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JsonData.load_json(UI_PATH)
	return _data


## Active visual theme pack (data/ui.json theme_path): colors, StyleBox sizes, board chrome.
static func theme_data() -> Dictionary:
	if _theme.is_empty():
		_theme = JsonData.load_json(String(data().get("theme_path", DEFAULT_THEME_PATH)))
	return _theme


static func color(key: String) -> Color:
	var v: Variant = theme_data().get("colors", {}).get(key)
	return Color.html(String(v)) if v is String and Color.html_is_valid(v) else MISSING_COLOR


## Number from a theme section ("button", "panel", "board", "starfield").
static func theme_num(section: String, key: String, fallback: float) -> float:
	return float(theme_data().get(section, {}).get(key, fallback))


static func flat_box(bg: Color, border: Color, border_width: int, radius: int, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func num(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func touch() -> float:
	return num("touch_target", 48.0)


## Font size by role: "small", "body", "button" or "title".
static func font(role: String) -> int:
	return int(num("font_" + role, 16.0))


static func int_list(key: String, fallback: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for v in data().get(key, fallback):
		out.append(int(v))
	return out


## Root theme: body font size everywhere, roomier popup rows (OptionButton lists) for touch,
## and the theme pack's colors / StyleBoxes on buttons, panels, inputs and popups.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = font("body")
	t.set_font_size("font_size", "PopupMenu", font("button"))
	t.set_constant("v_separation", "PopupMenu", int(touch() * 0.4))
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_color("font_color", "Label", color("text"))

	var bw := int(theme_num("button", "border_width", 2))
	var br := int(theme_num("button", "corner_radius", 6))
	var bm := theme_num("button", "content_margin", 10)
	var normal := flat_box(color("button"), color("button_border"), bw, br, bm)
	var hover := flat_box(color("button_hover"), color("accent_dim"), bw, br, bm)
	var pressed := flat_box(color("button_pressed"), color("accent"), bw, br, bm)
	var disabled := flat_box(color("button_disabled"), color("button_disabled"), bw, br, bm)
	var focus := flat_box(Color.TRANSPARENT, color("accent"), bw, br, bm)
	focus.draw_center = false
	for kind: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", kind, normal)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("hover_pressed", kind, pressed)
		t.set_stylebox("disabled", kind, disabled)
		t.set_stylebox("focus", kind, focus)
		for c: String in ["font_color", "font_hover_color", "font_focus_color"]:
			t.set_color(c, kind, color("button_text"))
		t.set_color("font_pressed_color", kind, color("accent"))
		t.set_color("font_hover_pressed_color", kind, color("accent"))
		t.set_color("font_disabled_color", kind, color("button_text_disabled"))

	t.set_stylebox("panel", "PanelContainer", card_style(color("panel_border")))
	var pr := int(theme_num("panel", "corner_radius", 8))
	t.set_stylebox("panel", "PopupMenu", flat_box(color("panel"), color("accent_dim"), 1, pr, 6))
	t.set_color("font_color", "PopupMenu", color("text"))
	t.set_color("font_hover_color", "PopupMenu", color("accent"))
	t.set_stylebox("hover", "PopupMenu", flat_box(color("button_hover"), color("button_hover"), 0, br, 4))
	var field := flat_box(color("input"), color("button_border"), 1, br, 6)
	var field_focus := flat_box(color("input"), color("accent"), 2, br, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", color("text"))
	t.set_color("caret_color", "LineEdit", color("accent"))
	return t


## Touch-sized button. MOUSE_FILTER_PASS lets a drag that starts on it scroll the parent list.
static func button(parent: Control, text: String, action: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(touch(), touch())
	b.add_theme_font_size_override("font_size", font("button"))
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if action.is_valid():
		b.pressed.connect(action)
	parent.add_child(b)
	return b


static func label(parent: Control, text: String, role: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font(role))
	if role == "title":
		l.add_theme_color_override("font_color", color("accent"))
	elif role == "small":
		l.add_theme_color_override("font_color", color("text_muted"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func picker(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(touch() * 3.0, touch())
	o.add_theme_font_size_override("font_size", font("button"))
	parent.add_child(o)
	return o


## Opaque backing for the tabbed section area (Holdings / Trade / Log): theme panel color.
static func section_style() -> StyleBoxFlat:
	return flat_box(color("panel"), color("panel_border"), int(theme_num("panel", "border_width", 1)),
			int(theme_num("panel", "corner_radius", 8)), theme_num("panel", "content_margin", 8))


## Panel background used for banners and deed cards: theme panel color, thin border, thick
## accent bar on the left. No accent: the theme's panel_border.
static func card_style(accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	if accent == Color.TRANSPARENT:
		accent = color("panel_border")
	var margin := theme_num("panel", "content_margin", 8)
	var sb := flat_box(color("panel"), accent, int(theme_num("panel", "border_width", 1)),
			int(theme_num("panel", "corner_radius", 8)), margin)
	sb.border_width_left = int(theme_num("panel", "accent_width", 6))
	sb.content_margin_left = margin + 4
	return sb
