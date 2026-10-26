extends TestCase
## Theme switching (P5-FEEL A4): explicit pack index (data/themes/index.json), session-only
## selection via UiStyle.set_theme / reset_theme, reload of HUD Theme, dialogue, starfield and
## board chrome, and the supported contract: switch on the setup screen before match start.
## Switches use the test-only fixture index (tests/fixtures/themes/); teardown restores the
## shipped default so static UiStyle state never leaks into other tests.

const FIXTURE_INDEX := "res://tests/fixtures/themes/index.json"
const ALT_BUTTON := Color("#c0d0e0")


func teardown() -> void:
	UiStyle.reset_theme()


func _use_fixture_index() -> void:
	UiStyle.theme_index_path = FIXTURE_INDEX


## seat_names of registered pack `id` (from its theme.json content_path).
static func _pack_seat_names(id: String) -> Array:
	var t := JsonData.load_json(UiStyle.theme_path_for(id))
	return JsonData.load_json(String(t.get("content_path", ""))).get("seat_names", [])


## Setup seat label texts must be `names` in seat order.
func _check_seat_labels(panel: SetupPanel, names: Array, what: String) -> void:
	check_eq(panel._seat_labels.size(), panel.bot_flags.size(), "%s: one label per offered seat" % what)
	check(names.size() >= panel._seat_labels.size(), "%s: the pack names every offered seat" % what)
	for i in mini(panel._seat_labels.size(), names.size()):
		check_eq(panel._seat_labels[i].text, names[i], "%s: seat %d label" % [what, i + 1])


func test_shipped_index_lists_default_pack() -> void:
	var packs := UiStyle.theme_packs()
	check(not packs.is_empty(), "index lists at least one pack")
	var ids: Array[String] = []
	for p in packs:
		ids.append(String(p["id"]))
		var path := String(p["theme_path"])
		check(path.begins_with("res://data/themes/"), "%s lives under data/themes/" % p["id"])
		check(FileAccess.file_exists(path), "%s theme file exists" % p["id"])
		check_eq(String(JsonData.load_json(path).get("id", "")), p["id"], "theme.json id matches index id")
	check("imperium_astra" in ids, "default pack registered")
	check_eq(UiStyle.theme_path_for("imperium_astra"), UiStyle.default_theme_path(),
			"ui.json theme_path is the registered default")
	check_eq(UiStyle.active_theme_path(), UiStyle.default_theme_path(), "default active at start")
	done()


func test_set_theme_reloads_pack_data() -> void:
	_use_fixture_index()
	check(UiStyle.set_theme("test_alt"), "set_theme accepts a registered pack")
	check_eq(String(UiStyle.theme_data().get("id", "")), "test_alt", "cached theme replaced")
	check_eq(UiStyle.active_theme_path(), UiStyle.theme_path_for("test_alt"), "active path")
	check_eq(UiStyle.color("button"), ALT_BUTTON, "colors from the new pack")
	var sb := UiStyle.make_theme().get_stylebox("normal", "Button") as StyleBoxFlat
	check(sb != null and sb.bg_color == ALT_BUTTON, "remade HUD Theme uses the new pack")
	check_eq(DialogueLines.load_theme().line("match_start", {"name": "Ann"}), "TEST_ALT Ann starts.",
			"dialogue reloads from the pack's dialogue_path")
	check_eq(BoardView.corner_mark(Space.Type.GO), "test-go", "board chrome from the new pack")
	check_eq(StarfieldBackground.make_stars().size(), 5, "starfield from the new pack")
	check(UiStyle.set_theme("imperium_astra"), "switch back to the default")
	check_eq(String(UiStyle.theme_data().get("id", "")), "imperium_astra", "default reloaded")
	check(UiStyle.color("button") != ALT_BUTTON, "default colors back")
	done()


func test_set_theme_rejects_unknown_pack() -> void:
	_use_fixture_index()
	check_eq(UiStyle.theme_packs().size(), 3, "index entry without an id is skipped")
	check(not UiStyle.set_theme("no_such_pack"), "unregistered id rejected")
	check(not UiStyle.set_theme("test_missing"), "registered id with a missing file rejected")
	check_eq(String(UiStyle.theme_data().get("id", "")), "imperium_astra", "rejected switch keeps the pack")
	done()


func test_reset_theme_restores_default() -> void:
	_use_fixture_index()
	UiStyle.set_theme("test_alt")
	UiStyle.reset_theme()
	check_eq(UiStyle.theme_index_path, UiStyle.THEME_INDEX_PATH, "shipped index restored")
	check_eq(UiStyle.active_theme_path(), UiStyle.default_theme_path(), "default path active")
	check_eq(String(UiStyle.theme_data().get("id", "")), "imperium_astra", "default pack loaded")
	done()


func test_selection_is_session_only() -> void:
	var before := FileAccess.get_file_as_string(UiStyle.UI_PATH)
	_use_fixture_index()
	UiStyle.set_theme("test_alt")
	check_eq(FileAccess.get_file_as_string(UiStyle.UI_PATH), before, "ui.json untouched on disk")
	check_eq(UiStyle.default_theme_path(), String(JsonData.load_json(UiStyle.UI_PATH)["theme_path"]),
			"ui.json theme_path still the shipped default")
	check(UiStyle.active_theme_path() != UiStyle.default_theme_path(), "choice held in memory only")
	done()


## Supported contract: pick a pack on the setup screen, then Start; no app restart.
func test_main_switch_before_match_start() -> void:
	_use_fixture_index()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var panel := main.show_setup(null)
	panel.save_path = ""
	panel.set_count(3)
	check(main.select_theme("test_alt"), "switch accepted on setup")
	var sb := main.theme.get_stylebox("normal", "Button") as StyleBoxFlat
	check(sb != null and sb.bg_color == ALT_BUTTON, "Main HUD Theme remade")
	check_eq(panel.count, 3, "seat choice kept across the re-theme")
	check_eq(panel._seat_toggles.size(), panel.bot_flags.size(), "seat rows rebuilt once")
	var stars: StarfieldBackground = null
	for c in panel.get_children():
		if c is StarfieldBackground:
			stars = c
	check(stars != null and stars.stars.size() == 5, "setup starfield rebuilt from the new pack")
	check(not main.select_theme("no_such_pack"), "unknown pack rejected")
	panel.start()
	check(main.controller != null and main._board_view != null, "match starts after the switch")
	if main._board_view != null:
		check(main._lines.line("match_start", {"name": "Ann"}).begins_with("TEST_ALT"), "match dialogue from the pack")
		check_eq(main._starfield.stars.size(), 5, "match starfield from the pack")
		check(not main.select_theme("imperium_astra"), "mid-match switch refused")
		check_eq(String(UiStyle.theme_data().get("id", "")), "test_alt", "refused switch keeps the pack")
	main.free()
	panel.free()
	done()


## Dig 3c: seat names are pack words, so a switch on the setup screen relabels the seats, switching
## back restores the default names, and the match starts with the active pack's names.
func test_seat_labels_follow_pack_switch() -> void:
	_use_fixture_index()
	var default_names := _pack_seat_names("imperium_astra")
	var alt_names := _pack_seat_names("test_alt")
	check(not default_names.is_empty() and default_names != alt_names, "packs name seats differently")
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var panel := main.show_setup(null)
	panel.save_path = ""
	_check_seat_labels(panel, default_names, "default pack")
	check(main.select_theme("test_alt"), "switch on setup")
	_check_seat_labels(panel, alt_names, "after switch")
	check_eq(panel.theme_picker.get_theme_font("font"), UiStyle.display_font(), "picker font follows the fixture pack")
	check(main.select_theme("imperium_astra"), "switch back")
	_check_seat_labels(panel, default_names, "after switch back")
	check_eq(panel.theme_picker.get_theme_font("font"), UiStyle.display_font(), "picker font follows the default pack")
	check(main.select_theme("test_alt"), "switch again")
	panel.set_count(3)
	panel.set_bot(0, false)
	panel.start()
	check(main.controller != null, "match started")
	if main.controller != null:
		check_eq(main.controller.players.size(), 3, "three seats chosen")
		for i in main.controller.players.size():
			check_eq(main.controller.players[i].display_name, alt_names[i], "match seat %d named by the pack" % (i + 1))
	main.free()
	panel.free()
	done()
