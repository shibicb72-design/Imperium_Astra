extends TestCase
## MAIN_MENU_STARK: a cold launch opens the main menu (gel chrome over a moving backdrop) before the
## seat setup; PLAY opens the setup (Q19), whose Start still needs data/ui.json setup_min_humans and
## builds the match; the theme switch stays pre-match only; the right-side promo stack is dropped and
## there are no resource bars; the backdrop pans with parallax and its props move; the chrome fits
## portrait, near-square (Fold) and landscape screens. Presentation only; no rules involved.

## Canvas sizes (dp): phone portrait, Fold inner (near-square), phone landscape, small phone.
const SIZES: Array[Vector2] = [Vector2(412, 915), Vector2(774, 930), Vector2(915, 412), Vector2(360, 640)]
## Third-party promos from the reference menu's dropped right-side stack.
const DROPPED_PROMOS: Array[String] = ["clue", "cluedo", "discord", "fellow fans", "new rules"]
const MENU_FILES: Array[String] = [
	"res://scripts/ui/main_menu.gd", "res://scripts/ui/main_menu_background.gd", "res://data/ui.json",
	"res://data/themes/imperium_astra/theme.json", "res://data/themes/astra_alt/theme.json",
]
## Every data/ui.json main_menu color the chrome paints with.
const CHROME_COLORS: Array[String] = [
	"play", "play_lip", "play_outline", "shop", "shop_lip", "shop_outline", "round", "round_lip",
	"round_outline", "ink", "shadow", "profile", "profile_lip", "profile_text", "level", "level_lip",
	"progress_track", "progress_fill", "promo_top", "promo_bottom", "promo_lip", "promo_rim", "burst",
	"tile_face", "tile_side", "tile_border", "go_red", "token_light", "token_mid", "token_dark",
	"die_body", "die_edge", "die_pip", "hat", "hat_band",
]
const SHIPPED_PACKS: Array[String] = ["imperium_astra", "astra_alt"]


func teardown() -> void:
	UiStyle.reset_theme()


## Main as on a cold launch (no injected controller). Tests run outside the tree, so _ready is
## called by hand.
func _cold_main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main._ready()
	return main


func _child_menu(main: Main) -> MainMenu:
	for c in main.get_children():
		if c is MainMenu:
			return c
	return null


func _child_setup(main: Main) -> SetupPanel:
	for c in main.get_children():
		if c is SetupPanel:
			return c
	return null


func _menu(s: Vector2) -> MainMenu:
	var menu := MainMenu.new()
	menu.setup()
	menu.size = s
	menu.layout()
	return menu


func test_cold_launch_opens_the_main_menu_first() -> void:
	var main := _cold_main()
	var menu := _child_menu(main)
	check(menu != null, "cold launch shows the main menu")
	check(main._main_menu == menu, "Main tracks the menu")
	check(_child_setup(main) == null, "seat setup waits for PLAY")
	check(main.controller == null and main._board_view == null, "no match and no board before PLAY")
	main.free()
	done()


## PLAY reaches the existing seat setup (Q19, not bypassed); Start still needs setup_min_humans
## people, then builds the match and the board as before.
func test_play_opens_seat_setup_then_start_builds_the_match() -> void:
	var main := _cold_main()
	var menu := _child_menu(main)
	menu.play_button.pressed.emit()
	var panel := _child_setup(main)
	check(panel != null, "PLAY opens the seat setup")
	check(menu.get_parent() == null and main._main_menu == null, "menu removed after PLAY")
	menu.play_requested.emit()
	var setups := 0
	for c in main.get_children():
		setups += 1 if c is SetupPanel else 0
	check_eq(setups, 1, "a second PLAY does not open a second setup")
	check(main.controller == null and main._board_view == null, "PLAY alone starts no match")
	if panel != null:
		panel.save_path = ""
		for i in panel.bot_flags.size():
			panel.set_bot(i, true)
		check(int(UiStyle.num("setup_min_humans", 1.0)) >= 1 and not panel.can_start(),
				"all-bot seats cannot start (setup_min_humans)")
		panel.start()
		check(main.controller == null, "Start refused without enough people")
		panel.set_bot(0, false)
		panel.start()
		check(main.controller != null and main._board_view != null, "Start builds the match and the board")
		check(panel.get_parent() == null, "setup removed at match start")
		panel.free()
	menu.free()
	main.free()
	done()


## The pack switch works on the menu (its backdrop rebuilds from the new pack) and on the setup
## screen after PLAY, and is still refused once the match has started.
func test_theme_switch_stays_pre_match_only() -> void:
	var main := _cold_main()
	var menu := _child_menu(main)
	var far_before := menu.background.skyline(0).duplicate()
	var sky_before := MainMenuBackground.tone("sky_top")
	check(main.select_theme("astra_alt"), "switch accepted on the main menu")
	check(MainMenuBackground.tone("sky_top") != sky_before, "menu sky color from the new pack")
	check(menu.background.skyline(0) != far_before, "menu skyline rebuilt from the new pack seed")
	check_eq(MainMenu.chrome_color("play"), Color.html("#f03c2e"), "chrome look unchanged across packs")
	menu.play_button.pressed.emit()
	var panel := _child_setup(main)
	check(panel != null and is_instance_valid(panel.theme_picker), "setup keeps its theme picker")
	if panel != null:
		panel.save_path = ""
		check(main.select_theme("imperium_astra"), "switch still accepted on the setup screen")
		panel.set_bot(0, false)
		panel.start()
		check(main._board_view != null, "match started")
		check(not main.select_theme("astra_alt"), "mid-match switch refused")
		check_eq(String(UiStyle.theme_data().get("id", "")), "imperium_astra", "refused switch keeps the pack")
		panel.free()
	menu.free()
	main.free()
	done()


## DROP: below the top bar nothing but the centered PLAY and centerpiece reaches the right half (no
## right-side promo stack); one promo card; the menu holds only the KEEP chrome, the backdrop and
## the stub layer, and no Range (no currency or resource bars).
func test_no_right_promo_stack_and_no_resource_bars() -> void:
	var menu := _menu(SIZES[0])
	for s in SIZES:
		menu.size = s
		menu.layout()
		var rects := menu.chrome_rects()
		check_eq(rects.size(), MainMenu.CHROME.size(), "%s: only the KEEP chrome is laid out" % s)
		var bar: Rect2 = rects[&"Settings"]
		for n: StringName in rects:
			var r: Rect2 = rects[n]
			if r.position.y >= bar.end.y and n != &"Play" and n != &"Centerpiece":
				check(r.end.x <= s.x * 0.5, "%s: %s stays on the left half" % [s, n])
		var center: Rect2 = rects[&"Centerpiece"]
		var play: Rect2 = rects[&"Play"]
		check(absf(center.get_center().x - s.x * 0.5) < 1.0, "%s: centerpiece centered" % s)
		check(absf(play.get_center().x - s.x * 0.5) < 1.0, "%s: PLAY centered" % s)
	var names: Array[String] = []
	for c in menu.get_children():
		names.append(String(c.name))
	names.sort()
	check_eq(names, ["Background", "Centerpiece", "Play", "Profile", "Promo", "Settings", "Shop", "Social",
			"Stub"] as Array[String], "menu children: KEEP chrome, backdrop and stub layer only")
	var pending: Array[Node] = [menu]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		check(not node is Range, "no resource or currency bar (%s)" % node.name)
		pending.append_array(node.get_children())
	menu.free()
	done()


## Motion: the skyline layers slide across frames, nearer layers faster (parallax), the barge and
## the balloon move, the balloon bobs; the skyline is deterministic from the pack seed.
func test_backdrop_pans_with_parallax_and_props_move() -> void:
	var bg := MainMenuBackground.new()
	bg.size = SIZES[0]
	bg.layout()
	var offsets: Array[float] = []
	for i in MainMenuBackground.LAYER_COUNT:
		offsets.append(bg.layer_offset(i))
	var props: Array[Vector2] = []
	for i in MainMenuBackground.PROP_COUNT:
		props.append(MainMenuBackground.prop_position(i, bg.time))
	bg.advance(2.0)
	check_eq(bg.time, 2.0, "advance moves the clock")
	for i in MainMenuBackground.LAYER_COUNT:
		check(bg.layer_offset(i) < offsets[i], "layer %d slides left across frames" % i)
	check(offsets[0] - bg.layer_offset(0) < offsets[2] - bg.layer_offset(2), "near layer moved farther than far")
	var far := MainMenuBackground.pan_distance(0, 10.0)
	var mid := MainMenuBackground.pan_distance(1, 10.0)
	var near := MainMenuBackground.pan_distance(2, 10.0)
	check(0.0 < far and far < mid and mid < near, "parallax: nearer layers pan faster (%s, %s, %s)" % [far, mid, near])
	for i in MainMenuBackground.PROP_COUNT:
		check(MainMenuBackground.prop_position(i, bg.time) != props[i], "prop %d moves" % i)
	var bob_seconds := MainMenuBackground.knob("balloon_bob_seconds", 6.0)
	check(MainMenuBackground.prop_position(1, bob_seconds * 0.25).y > MainMenuBackground.prop_position(1, bob_seconds * 0.75).y,
			"balloon bobs")
	check(bg.cloud_count() >= 2, "drifting clouds")
	check_eq(MainMenuBackground.make_skyline(1, 11), MainMenuBackground.make_skyline(1, 11), "skyline deterministic")
	for i in MainMenuBackground.LAYER_COUNT:
		check(not bg.skyline(i).is_empty(), "layer %d has buildings" % i)
		for b in bg.skyline(i):
			check(b.x >= 0.0 and b.x + b.y / MainMenuBackground.TILE_HEIGHTS <= 1.0 + 1e-6, "layer %d building inside its tile" % i)
	bg.free()
	done()


func test_centerpiece_floats_on_the_menu_clock() -> void:
	var rest := MainMenu.float_offset(0.0)
	var top := MainMenu.float_offset(MainMenu.knob("float_seconds", 3.2) * 0.5)
	check(is_zero_approx(rest), "centerpiece starts at rest")
	check(top > rest and top <= MainMenu.knob("float_height", 10.0) + 0.001, "rises up to float_height")
	var menu := _menu(SIZES[0])
	menu.advance(0.5)
	check_eq(menu.time, 0.5, "menu clock advanced")
	check_eq(menu.background.time, 0.5, "one clock drives the backdrop")
	menu.free()
	done()


func test_no_third_party_promo_strings() -> void:
	for path in MENU_FILES:
		var text := FileAccess.get_file_as_string(path).to_lower()
		check(text != "", "%s readable" % path)
		for w in DROPPED_PROMOS:
			check(not text.contains(w), "%s has no '%s' promo" % [path, w])
	done()


## Chrome on screen and clear of each other at every size, touch-sized, PLAY the biggest pill; the
## nodes sit at their rects.
func test_chrome_fits_portrait_fold_and_landscape() -> void:
	var menu := _menu(SIZES[0])
	for s in SIZES:
		menu.size = s
		menu.layout()
		var rects := menu.chrome_rects()
		var screen := Rect2(Vector2.ZERO, s)
		var names: Array = rects.keys()
		for i in names.size():
			var a: Rect2 = rects[names[i]]
			check(a.size.x > 0.0 and a.size.y > 0.0, "%s: %s has room" % [s, names[i]])
			check(screen.encloses(a), "%s: %s on screen" % [s, names[i]])
			for j in range(i + 1, names.size()):
				check(not a.intersects(rects[names[j]]), "%s: %s clear of %s" % [s, names[i], names[j]])
		var play: Rect2 = rects[&"Play"]
		for n: StringName in [&"Profile", &"Social", &"Settings", &"Shop", &"Play"]:
			var r: Rect2 = rects[n]
			check(r.size.x >= UiStyle.touch() and r.size.y >= UiStyle.touch(), "%s: %s touch-sized" % [s, n])
			if n != &"Play":
				check(play.get_area() > r.get_area() * 1.5, "%s: PLAY bigger than %s" % [s, n])
		check(play.size.x >= minf(s.x * 0.5, MainMenu.knob("play_max_width", 520.0)), "%s: PLAY is the massive CTA" % s)
		var promo: Rect2 = rects[&"Promo"]
		check_eq(menu.play_button.position, play.position, "%s: PLAY node at its rect" % s)
		check_eq(menu.promo_button.size, promo.size, "%s: promo node sized" % s)
		check_eq(menu.background.size, s, "%s: backdrop fills the menu" % s)
	menu.free()
	done()


## SHOP, Social, Settings, the promo card and the profile open the placeholder card (no store,
## social or backend) and close it; none starts play.
func test_stub_buttons_open_a_placeholder_card() -> void:
	var menu := _menu(SIZES[0])
	var plays: Array[int] = [0]
	menu.play_requested.connect(func() -> void: plays[0] += 1)
	for b: Button in [menu.shop_button, menu.social_button, menu.settings_button, menu.promo_button, menu.profile_button]:
		b.pressed.emit()
		check(menu.stub_open() and menu.stub_title != "", "%s opens its placeholder card" % b.name)
		menu.stub_close.pressed.emit()
		check(not menu.stub_open(), "%s placeholder closes" % b.name)
	check_eq(plays[0], 0, "stubs never start play")
	check(Rect2(Vector2.ZERO, SIZES[0]).encloses(menu.stub_card_rect()), "placeholder card on screen")
	menu.play_button.pressed.emit()
	check_eq(plays[0], 1, "PLAY emits play_requested")
	menu.free()
	done()


## Every chrome color is in data/ui.json (no magenta gaps) and every shipped pack colors the whole
## backdrop itself (no fallback tones).
func test_menu_colors_are_data() -> void:
	for k in CHROME_COLORS:
		check(MainMenu.chrome_color(k) != Color.MAGENTA, "main_menu color %s in data/ui.json" % k)
	for id in SHIPPED_PACKS:
		check(UiStyle.set_theme(id), "%s: set_theme" % id)
		var colors: Dictionary = MainMenuBackground.section().get("colors", {})
		for k: String in MainMenuBackground.FALLBACK_TONES:
			check(colors.has(k) and Color.html_is_valid(String(colors[k])), "%s: menu_background color %s" % [id, k])
		check(MainMenuBackground.section().get("parallax", []).size() == MainMenuBackground.LAYER_COUNT,
				"%s: parallax per layer" % id)
	done()


func test_menu_round_trip_leaves_no_orphans() -> void:
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var main := _cold_main()
	var menu := _child_menu(main)
	menu.advance(0.25)
	menu.play_button.pressed.emit()
	menu.free()
	main.free()
	check_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), before, "no orphan nodes")
	done()
