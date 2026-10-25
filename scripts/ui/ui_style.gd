class_name UiStyle
extends RefCounted
## Shared presentation sizes from data/ui.json and small builders, so every panel gets
## touch-sized controls (min data/ui.json touch_target, about 48 dp on phones once
## DisplayScale has set the window scale). Presentation only; no rule numbers here.

const UI_PATH := "res://data/ui.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JsonData.load_json(UI_PATH)
	return _data


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


## Root theme: body font size everywhere, roomier popup rows (OptionButton lists) for touch.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = font("body")
	t.set_font_size("font_size", "PopupMenu", font("button"))
	t.set_constant("v_separation", "PopupMenu", int(touch() * 0.4))
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "HFlowContainer", 6)
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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func picker(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(touch() * 3.0, touch())
	o.add_theme_font_size_override("font_size", font("button"))
	parent.add_child(o)
	return o


## Panel background used for banners and deed cards.
static func card_style(accent: Color = Color("#5b6aa8")) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#10162e")
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.border_width_left = 6
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 12
	return sb
