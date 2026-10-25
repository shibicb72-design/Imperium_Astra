extends TestCase
## Theme pack tests (P3-THEME, P5-FEEL A8): every registered pack (data/themes/index.json) loads,
## carries every key the UI reads, keeps text readable (WCAG-style contrast ratios), stays
## presentation-only in every pack file, ships a complete content overlay, and the UI picks it up
## (themed buttons stay touch-sized; BoardView corners and starfield come from theme data).
## Packs are switched with UiStyle.set_theme; teardown restores the shipped default.

const REQUIRED_COLORS: Array[String] = [
	"background", "background_top", "panel", "panel_border", "accent", "accent_dim", "text",
	"text_muted", "alert", "button", "button_hover", "button_pressed", "button_disabled",
	"button_border", "button_text", "button_text_disabled", "input", "board_cell", "board_border",
	"board_center", "board_frame", "dice_face", "dice_pip", "star",
]
## Keys that would mean rules data leaked into the theme pack.
const RULE_KEYS: Array[String] = ["spaces", "space_type", "price", "rent", "rents", "cards", "opcode", "groups"]
## Rules fields from board.json / cards.json that must not appear as a key anywhere in a pack file.
const RULE_FIELDS: Array[String] = [
	"list_price", "house_cost", "hotel_cost", "mortgage_value", "tax_amount", "property_id",
	"color_group_id", "params",
]
## theme.json keys that point at other files of the pack.
const PATH_KEYS: Array[String] = ["dialogue_path", "content_path"]
const CORNERS: Array[String] = ["GO", "JAIL_CORNER", "FREE_PARKING", "GO_TO_JAIL"]
const FIXTURE_INDEX := "res://tests/fixtures/themes/index.json"


func teardown() -> void:
	Engine.print_error_messages = true
	UiStyle.reset_theme()


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


## Registered (shipped) pack ids, in index order.
func _pack_ids() -> Array[String]:
	var out: Array[String] = []
	for p in UiStyle.theme_packs():
		out.append(String(p["id"]))
	return out


## Every file a pack references: theme.json plus its dialogue / content paths.
static func _pack_files(theme_path: String) -> Array[String]:
	var out: Array[String] = [theme_path]
	var t := JsonData.load_json(theme_path)
	for k in PATH_KEYS:
		if t.get(k) is String:
			out.append(String(t[k]))
	return out


## Keys (at any depth) of `v` that are rules keys / fields.
static func _rule_keys_in(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Dictionary:
		for k: Variant in v:
			if String(k) in RULE_KEYS or String(k) in RULE_FIELDS:
				out.append(String(k))
			out.append_array(_rule_keys_in(v[k]))
	elif v is Array:
		for e: Variant in v:
			out.append_array(_rule_keys_in(e))
	return out


static func _card_ids() -> Array[String]:
	var out: Array[String] = []
	var cards := JsonData.load_json(GameSetup.CARDS_PATH)
	for deck in ["chance", "community_chest"]:
		for c: Dictionary in cards.get(deck, []):
			out.append(String(c["card_id"]))
	return out


## Seats a pack's seat_names must name: data/rules.json seat_pool.
static func _seat_count() -> int:
	return RulesConfig.from_dict(JsonData.load_json(GameSetup.RULES_PATH)).seat_pool.size()


func test_theme_loads_from_ui_json_path() -> void:
	var path := String(UiStyle.data().get("theme_path", ""))
	check(path.begins_with("res://data/themes/"), "ui.json theme_path points into data/themes/")
	check(FileAccess.file_exists(path), "theme file exists")
	check_eq(String(_theme().get("id", "")), "imperium_astra", "theme id")
	check(not _pack_ids().is_empty(), "at least one registered pack")
	done()


func test_required_colors_present_and_valid() -> void:
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var colors: Dictionary = _theme().get("colors", {})
		for k in REQUIRED_COLORS:
			check(colors.has(k), "%s: color '%s' present" % [id, k])
			check(Color.html_is_valid(String(colors.get(k, ""))), "%s: color '%s' is valid hex" % [id, k])
			check(UiStyle.color(k) != UiStyle.MISSING_COLOR, "%s: UiStyle.color('%s') resolves" % [id, k])
	check_eq(UiStyle.color("no_such_key"), UiStyle.MISSING_COLOR, "missing key is loud magenta")
	done()


func test_style_sections_present() -> void:
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		for section in ["button", "panel", "board", "starfield"]:
			check(_theme().get(section) is Dictionary, "%s: section '%s' present" % [id, section])
		check(UiStyle.theme_num("button", "corner_radius", -1) >= 0, "%s: button corner_radius" % id)
		check(UiStyle.theme_num("panel", "accent_width", -1) > 0, "%s: panel accent_width" % id)
		var share := UiStyle.theme_num("board", "group_bar_share", -1)
		check(share > 0.1 and share < 0.4, "%s: group bar share leaves room for the label" % id)
		var corners: Dictionary = _theme().get("board", {}).get("corner_colors", {})
		for c in CORNERS:
			check(Color.html_is_valid(String(corners.get(c, ""))), "%s: corner color for %s" % [id, c])
	done()


func test_text_contrast() -> void:
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var text := UiStyle.color("text")
		check(contrast(text, UiStyle.color("background")) >= 7.0, "%s: body text on background (AAA)" % id)
		check(contrast(text, UiStyle.color("panel")) >= 7.0, "%s: body text on panels (AAA)" % id)
		check(contrast(text, UiStyle.color("board_cell")) >= 7.0, "%s: board labels on cells (AAA)" % id)
		check(contrast(UiStyle.color("text_muted"), UiStyle.color("panel")) >= 4.5, "%s: muted text on panels (AA)" % id)
		var bt := UiStyle.color("button_text")
		for bg in ["button", "button_hover"]:
			check(contrast(bt, UiStyle.color(bg)) >= 4.5, "%s: button text on %s (AA)" % [id, bg])
		check(contrast(UiStyle.color("accent"), UiStyle.color("button_pressed")) >= 4.5, "%s: pressed text (AA)" % id)
		check(contrast(UiStyle.color("accent"), UiStyle.color("background")) >= 4.5, "%s: titles on background (AA)" % id)
		check(contrast(UiStyle.color("alert"), UiStyle.color("panel")) >= 4.5, "%s: alert text on panels (AA)" % id)
		check(contrast(UiStyle.color("dice_pip"), UiStyle.color("dice_face")) >= 7.0, "%s: dice pips" % id)
		check(contrast(UiStyle.color("button_text_disabled"), UiStyle.color("button_disabled")) >= 2.5,
				"%s: disabled text still visible" % id)
		for c in CORNERS:
			check(contrast(text, BoardView.corner_tint(Space.Type[c])) >= 4.5, "%s: corner %s label contrast" % [id, c])
	done()


func test_theme_is_presentation_only() -> void:
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var t := _theme()
		for k in RULE_KEYS:
			check(not t.has(k), "%s: theme has no rules key '%s'" % [id, k])
		var text := JSON.stringify(t)
		for k in ["\"price\"", "\"rent", "\"opcode\"", "\"space_type\""]:
			check(not text.contains(k), "%s: theme JSON has no %s" % [id, k])
	done()


## Every file of every pack (shipped index and the test fixture index): referenced from its
## theme.json, present on disk, and free of rules keys at any depth. Pack folders hold no stray
## files (a file nobody references could smuggle rules data past the loaders).
func test_every_pack_file_presentation_only() -> void:
	var entries := UiStyle.theme_packs()
	UiStyle.theme_index_path = FIXTURE_INDEX
	for p in UiStyle.theme_packs():
		if FileAccess.file_exists(String(p["theme_path"])) and not (p in entries):
			entries.append(p)
	UiStyle.theme_index_path = UiStyle.THEME_INDEX_PATH
	check(entries.size() >= 2, "shipped and fixture packs scanned")
	for p in entries:
		var theme_path := String(p["theme_path"])
		var files := _pack_files(theme_path)
		check_eq(files.size(), PATH_KEYS.size() + 1, "%s: theme.json names dialogue_path and content_path" % p["id"])
		for f in files:
			check(FileAccess.file_exists(f), "%s: %s exists" % [p["id"], f])
			check_eq(_rule_keys_in(JsonData.load_json(f)), [] as Array[String], "%s: %s has no rules keys" % [p["id"], f])
		var dir := theme_path.get_base_dir()
		for fname in DirAccess.get_files_at(dir):
			if fname.ends_with(".json"):
				check(dir.path_join(fname) in files, "%s: %s is referenced by theme.json" % [p["id"], fname])
	done()


## A5: every registered pack's content overlay names every term, space, group and seat (dig 3c:
## one seat_names entry per rules.json seat_pool seat), so no default-pack word can leak through;
## it uses only whitelisted keys and matches its pack id; card_text stays optional.
func test_every_pack_has_complete_content_overlay() -> void:
	var board := Board.from_dict(JsonData.load_json(GameSetup.BOARD_PATH))
	var card_ids := _card_ids()
	var seat_count := _seat_count()
	check(not _pack_ids().is_empty(), "registered packs to check")
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var path := String(_theme().get("content_path", ""))
		check(path != "" and FileAccess.file_exists(path), "%s: content_path set and present" % id)
		check_eq(UiStyle.content_problem(_theme()), "", "%s: content overlay readable" % id)
		var overlay := UiStyle.content_overlay()
		check_eq(String(overlay.get("id", "")), id, "%s: content id matches pack id" % id)
		check_eq(ContentOverlay.problems(overlay, board, card_ids, seat_count, true), [] as Array[String],
				"%s: content overlay complete and valid" % id)
	done()


## Dig 3c (Track B nit 3): a pack that cannot supply its content overlay is a loud problem, not a
## quiet {}: UiStyle.content_overlay() push_errors content_problem() (JsonData push_errors a file
## that is not a JSON object) and the match falls back to the shared words. Every registered pack
## passes (test above), so a registered pack never takes that path.
func test_missing_content_is_a_loud_problem() -> void:
	check(UiStyle.content_problem({}).contains("no content_path"), "pack without content_path flagged")
	check(UiStyle.content_problem({"content_path": ""}).contains("no content_path"), "empty content_path flagged")
	check(UiStyle.content_problem({"content_path": 7}).contains("no content_path"), "non-string content_path flagged")
	var missing := "res://tests/fixtures/themes/no_such_pack/content.json"
	check(UiStyle.content_problem({"content_path": missing}).contains("does not exist"), "missing content file flagged")
	var fixture := "res://tests/fixtures/themes/test_alt/content.json"
	check_eq(UiStyle.content_problem({"content_path": fixture}), "", "present content file passes")
	check(not UiStyle.content_overlay().is_empty(), "default pack overlay loads")
	# Active pack without readable content (cached pack swapped in; teardown reloads the default).
	# Its push_error is expected, so error printing is off around the two calls only.
	Engine.print_error_messages = false
	UiStyle._theme = {"id": "test_broken"}
	var no_path := UiStyle.content_overlay()
	UiStyle._theme = {"id": "test_broken", "content_path": missing}
	var no_file := UiStyle.content_overlay()
	Engine.print_error_messages = true
	check(no_path.is_empty(), "pack without content_path gets {} (shared words), after a push_error")
	check(no_file.is_empty(), "pack with a missing content file gets {} (shared words), after a push_error")
	done()


func test_overlay_keys_never_rules_keys() -> void:
	for k in ContentOverlay.KEYS:
		check(not (k in RULE_KEYS) and not (k in RULE_FIELDS), "overlay key '%s' is not a rules key" % k)
	for k in ContentOverlay.SPACE_NAME_KEYS:
		check(not (k in RULE_KEYS) and not (k in RULE_FIELDS), "space_names field '%s' is not a rules key" % k)
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
	for id in _pack_ids():
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var cell := UiStyle.color("board_cell")
		var go := BoardView.corner_tint(Space.Type.GO)
		var jail := BoardView.corner_tint(Space.Type.JAIL_CORNER)
		check(go != cell and jail != cell, "%s: GO and jail corners are tinted" % id)
		check(go != jail, "%s: GO and jail tints differ" % id)
		check(BoardView.corner_mark(Space.Type.GO) != "", "%s: GO mark" % id)
		check(BoardView.corner_mark(Space.Type.JAIL_CORNER) != "", "%s: jail mark" % id)
		check_eq(BoardView.corner_tint(Space.Type.STREET), cell, "%s: non-corner falls back to cell color" % id)
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
