extends TestCase
## Theme pack tests (P3-THEME): the active theme loads, carries every key the UI reads, keeps
## text readable (WCAG-style contrast ratios), stays presentation-only, and the UI picks it up
## (themed buttons stay touch-sized; BoardView corners and starfield come from theme data).

const REQUIRED_COLORS: Array[String] = [
	"background", "background_top", "panel", "panel_border", "accent", "accent_dim", "text",
	"text_muted", "alert", "button", "button_hover", "button_pressed", "button_disabled",
	"button_border", "button_text", "button_text_disabled", "input", "board_cell", "board_border",
	"board_center", "board_frame", "dice_face", "dice_pip", "star",
]
## Keys that would mean rules data leaked into the theme pack.
const RULE_KEYS: Array[String] = ["spaces", "space_type", "price", "rent", "rents", "cards", "opcode", "groups"]
const CORNERS: Array[String] = ["GO", "JAIL_CORNER", "FREE_PARKING", "GO_TO_JAIL"]


static func _luminance(c: Color) -> float:
	var ch := func(v: float) -> float:
		return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _theme() -> Dictionary:
	return UiStyle.theme_data()


func test_theme_loads_from_ui_json_path() -> void:
	var path := String(UiStyle.data().get("theme_path", ""))
	check(path.begins_with("res://data/themes/"), "ui.json theme_path points into data/themes/")
	check(FileAccess.file_exists(path), "theme file exists")
	check_eq(String(_theme().get("id", "")), "imperium_astra", "theme id")
	done()


func test_required_colors_present_and_valid() -> void:
	var colors: Dictionary = _theme().get("colors", {})
	for k in REQUIRED_COLORS:
		check(colors.has(k), "color '%s' present" % k)
		check(Color.html_is_valid(String(colors.get(k, ""))), "color '%s' is valid hex" % k)
		check(UiStyle.color(k) != UiStyle.MISSING_COLOR, "UiStyle.color('%s') resolves" % k)
	check_eq(UiStyle.color("no_such_key"), UiStyle.MISSING_COLOR, "missing key is loud magenta")
	done()


func test_style_sections_present() -> void:
	for section in ["button", "panel", "board", "starfield"]:
		check(_theme().get(section) is Dictionary, "section '%s' present" % section)
	check(UiStyle.theme_num("button", "corner_radius", -1) >= 0, "button corner_radius")
	check(UiStyle.theme_num("panel", "accent_width", -1) > 0, "panel accent_width")
	var share := UiStyle.theme_num("board", "group_bar_share", -1)
	check(share > 0.1 and share < 0.4, "group bar share leaves room for the label")
	var corners: Dictionary = _theme()["board"].get("corner_colors", {})
	for c in CORNERS:
		check(Color.html_is_valid(String(corners.get(c, ""))), "corner color for %s" % c)
	done()


func test_text_contrast() -> void:
	var text := UiStyle.color("text")
	check(contrast(text, UiStyle.color("background")) >= 7.0, "body text on background (AAA)")
	check(contrast(text, UiStyle.color("panel")) >= 7.0, "body text on panels (AAA)")
	check(contrast(text, UiStyle.color("board_cell")) >= 7.0, "board labels on cells (AAA)")
	check(contrast(UiStyle.color("text_muted"), UiStyle.color("panel")) >= 4.5, "muted text on panels (AA)")
	var bt := UiStyle.color("button_text")
	for bg in ["button", "button_hover"]:
		check(contrast(bt, UiStyle.color(bg)) >= 4.5, "button text on %s (AA)" % bg)
	check(contrast(UiStyle.color("accent"), UiStyle.color("button_pressed")) >= 4.5, "pressed text (AA)")
	check(contrast(UiStyle.color("accent"), UiStyle.color("background")) >= 4.5, "gold titles on background (AA)")
	check(contrast(UiStyle.color("alert"), UiStyle.color("panel")) >= 4.5, "alert text on panels (AA)")
	check(contrast(UiStyle.color("dice_pip"), UiStyle.color("dice_face")) >= 7.0, "dice pips")
	check(contrast(UiStyle.color("button_text_disabled"), UiStyle.color("button_disabled")) >= 2.5,
			"disabled text still visible")
	for c in CORNERS:
		check(contrast(text, BoardView.corner_tint(Space.Type[c])) >= 4.5, "corner %s label contrast" % c)
	done()


func test_theme_is_presentation_only() -> void:
	var t := _theme()
	for k in RULE_KEYS:
		check(not t.has(k), "theme has no rules key '%s'" % k)
	var text := JSON.stringify(t)
	for k in ["\"price\"", "\"rent", "\"opcode\"", "\"space_type\""]:
		check(not text.contains(k), "theme JSON has no %s" % k)
	done()


func test_theme_applies_to_ui() -> void:
	var th := UiStyle.make_theme()
	var sb := th.get_stylebox("normal", "Button") as StyleBoxFlat
	check(sb != null, "Button normal stylebox is flat")
	if sb != null:
		check_eq(sb.bg_color, UiStyle.color("button"), "button color from theme")
	check_eq(th.get_color("font_color", "Button"), UiStyle.color("button_text"), "button text color")
	check(th.get_stylebox("panel", "PanelContainer") is StyleBoxFlat, "panel stylebox")
	var card := UiStyle.card_style()
	check_eq(card.bg_color, UiStyle.color("panel"), "card uses panel color")
	check_eq(card.border_color, UiStyle.color("panel_border"), "card default accent")
	var holder := Control.new()
	var b := UiStyle.button(holder, "x", Callable())
	check(b.custom_minimum_size.y >= 48.0 and b.custom_minimum_size.x >= 48.0, "themed button >= 48dp")
	holder.free()
	done()


func test_board_corners_distinct() -> void:
	var cell := UiStyle.color("board_cell")
	var go := BoardView.corner_tint(Space.Type.GO)
	var brig := BoardView.corner_tint(Space.Type.JAIL_CORNER)
	check(go != cell and brig != cell, "Launch Bay and Brig corners are tinted")
	check(go != brig, "Launch Bay and Brig tints differ")
	check(BoardView.corner_mark(Space.Type.GO) != "", "Launch Bay mark")
	check(BoardView.corner_mark(Space.Type.JAIL_CORNER) != "", "Brig mark")
	check_eq(BoardView.corner_tint(Space.Type.STREET), cell, "non-corner falls back to cell color")
	done()


func test_starfield_deterministic() -> void:
	var a := StarfieldBackground.make_stars()
	var b := StarfieldBackground.make_stars()
	check_eq(a.size(), int(UiStyle.theme_num("starfield", "count", 0)), "star count from theme")
	check_eq(a, b, "same seed, same stars")
	for s in a:
		check(s.x >= 0.0 and s.x <= 1.0 and s.y >= 0.0 and s.y <= 1.0, "star inside rect")
	var bg := StarfieldBackground.new()
	check_eq(bg.mouse_filter, Control.MOUSE_FILTER_IGNORE, "backdrop ignores input")
	bg.free()
	done()
