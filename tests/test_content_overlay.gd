extends TestCase
## Pack content overlay (P5-FEEL A5) and hard-coded flavor strip (A6): GameSetup.new_game() applies
## the overlay passed in (terms, space / group names, card text by card_id) without touching rules
## data; core never reads UiStyle / ui.json; Main passes the active pack's overlay at match start;
## with a non-default overlay no default-pack word reaches the log, board or trade messages.
## Dig 3c: seat names are pack words too (seat_names, via GameSetup.seats_for / the setup screen),
## and card_text is an optional per-card override (cards a pack leaves out keep cards.json text).
## The second pack is the test-only fixture (tests/fixtures/themes/test_alt); teardown restores
## the shipped default pack.

const P := TurnController.Phase
const FIXTURE_INDEX := "res://tests/fixtures/themes/index.json"
const FIXTURE_CONTENT := "res://tests/fixtures/themes/test_alt/content.json"
const DEFAULT_CONTENT := "res://data/themes/imperium_astra/content.json"


func teardown() -> void:
	UiStyle.reset_theme()


static func _base_board() -> Board:
	return Board.from_dict(JsonData.load_json(GameSetup.BOARD_PATH))


static func _card_ids() -> Array[String]:
	var out: Array[String] = []
	var cards := JsonData.load_json(GameSetup.CARDS_PATH)
	for deck in ["chance", "community_chest"]:
		for c: Dictionary in cards.get(deck, []):
			out.append(String(c["card_id"]))
	return out


## card_id -> the shared data/cards.json text.
static func _shared_card_text() -> Dictionary:
	var out := {}
	var cards := JsonData.load_json(GameSetup.CARDS_PATH)
	for deck in ["chance", "community_chest"]:
		for c: Dictionary in cards.get(deck, []):
			out[String(c["card_id"])] = String(c["text"])
	return out


static func _seat_pool() -> Array[Dictionary]:
	return RulesConfig.from_dict(JsonData.load_json(GameSetup.RULES_PATH)).seat_pool


static func _logged(tc: TurnController, text: String) -> bool:
	for line in tc.log_lines:
		if line.contains(text):
			return true
	return false


## Fixture overlay plus card_text for every card, so no default-pack word is left anywhere.
static func _full_fixture() -> Dictionary:
	var o := JsonData.load_json(FIXTURE_CONTENT)
	var text: Dictionary = o["card_text"]
	for cid in _card_ids():
		if not text.has(cid):
			text[cid] = "T card %s." % cid
	return o


## Every word the default pack overlay supplies (terms, space, group and seat names).
static func _default_words() -> Array[String]:
	var words: Array[String] = []
	var d := JsonData.load_json(DEFAULT_CONTENT)
	for k: String in d["terms"]:
		words.append(String(d["terms"][k]))
	for k: String in d["group_names"]:
		words.append(String(d["group_names"][k]))
	for k: String in d["space_names"]:
		for f: String in d["space_names"][k]:
			words.append(String(d["space_names"][k][f]))
	for n: Variant in d.get("seat_names", []):
		words.append(String(n))
	return words


static func _seats() -> Array[Dictionary]:
	return [{"display_name": "Ann", "color": "#ff0000"}, {"display_name": "Bob", "color": "#00ff00"},
			{"display_name": "Cy", "color": "#0000ff"}]


func test_default_overlay_matches_board_json() -> void:
	var base := _base_board()
	var pool := _seat_pool()
	var d := JsonData.load_json(DEFAULT_CONTENT)
	check_eq(ContentOverlay.problems(d, base, _card_ids(), pool.size(), true), [] as Array[String], "default overlay valid")
	check_eq(d["terms"], base.terms, "terms match board.json")
	for i in base.spaces.size():
		var e: Dictionary = d["space_names"][str(i)]
		check_eq(e["display_name"], base.spaces[i].display_name, "space %d name matches" % i)
		check_eq(e.get("short_name", e["display_name"]), base.spaces[i].short_name, "space %d short name matches" % i)
	for gid: StringName in base.group_info:
		check_eq(d["group_names"][String(gid)], base.group_info[gid]["display_name"], "group %s matches" % gid)
	var seat_names: Array = d.get("seat_names", [])
	check_eq(seat_names.size(), pool.size(), "one seat name per rules.json seat_pool seat")
	for i in mini(seat_names.size(), pool.size()):
		check_eq(seat_names[i], pool[i]["display_name"], "seat %d name matches seat_pool" % (i + 1))
	var tc := GameSetup.new_game(1234, [], d)
	var plain := GameSetup.new_game(1234)
	check_eq(tc.board.spaces[0].display_name, base.spaces[0].display_name, "default overlay changes nothing")
	for i in plain.players.size():
		check_eq(tc.players[i].display_name, plain.players[i].display_name, "default overlay keeps seat %d name" % (i + 1))
	done()


func test_overlay_applies_words_only() -> void:
	var base := _base_board()
	var plain := GameSetup.new_game(1234)
	var tc := GameSetup.new_game(1234, [], _full_fixture())
	check_eq(tc.board.spaces[0].display_name, "T Space 0", "space display_name from overlay")
	check_eq(tc.board.spaces[0].short_name, "T0", "short_name from overlay")
	check_eq(tc.board.spaces[1].short_name, "T Space 1", "short_name defaults to the overlay display_name")
	check_eq(tc.board.group_info[&"brown"]["display_name"], "T Group 1", "group name from overlay")
	check_eq(tc.board.group_info[&"brown"]["color"], base.group_info[&"brown"]["color"], "group color unchanged")
	check_eq(tc.board.term("jail"), "t-jail", "terms from overlay")
	check_eq(plain.board.term("jail"), base.term("jail"), "no overlay keeps board.json terms")
	for i in base.spaces.size():
		var s := tc.board.spaces[i]
		var b := base.spaces[i]
		check_eq(s.space_type, b.space_type, "space %d type unchanged" % i)
		check_eq(s.list_price, b.list_price, "space %d price unchanged" % i)
		check_eq(s.tax_amount, b.tax_amount, "space %d tax unchanged" % i)
		if b.deed != null:
			check_eq(s.deed.rent_by_houses, b.deed.rent_by_houses, "space %d rents unchanged" % i)
			check_eq(s.deed.mortgage_value, b.deed.mortgage_value, "space %d mortgage unchanged" % i)
	var plain_ops := {}
	for deck in [plain.chance, plain.community_chest]:
		for c in deck.draw_pile:
			plain_ops[c.card_id] = c.opcode
	for deck in [tc.chance, tc.community_chest]:
		check_eq(deck.draw_pile.size(), 16, "%s deck size unchanged" % deck.deck_id)
		for c in deck.draw_pile:
			check(c.text.begins_with("T card"), "card %s text from overlay" % c.card_id)
			check_eq(c.opcode, plain_ops.get(c.card_id), "card %s opcode unchanged" % c.card_id)
	done()


func test_overlay_never_changes_rules_data() -> void:
	var base := _base_board()
	var bad := {
		"spaces": [{"index": 1, "list_price": 1}],
		"groups": {"brown": {"color": "#000000"}},
		"cards": {"chance": []},
		"space_names": {"1": {"display_name": "X", "list_price": 1}, "40": {"display_name": "Y"}, "abc": {}},
		"group_names": {"no_group": "Z"},
		"seat_names": ["S", "S", 7, "", "a", "b", "c"],
		"card_text": {"no_card": "W", "ch_advance_go": ""},
	}
	var seat_count := _seat_pool().size()
	var tc := GameSetup.new_game(1234, [], bad)
	check_eq(tc.board.spaces[1].display_name, "X", "name applied")
	check_eq(tc.board.spaces[1].list_price, base.spaces[1].list_price, "price key inside space_names ignored")
	check_eq(tc.board.group_info[&"brown"]["color"], base.group_info[&"brown"]["color"], "banned groups key ignored")
	check_eq(tc.chance.draw_pile.size(), 16, "banned cards key ignored")
	for c in tc.chance.draw_pile:
		if c.card_id == &"ch_advance_go":
			check_eq(c.text, _shared_card_text()["ch_advance_go"], "empty card_text skipped, cards.json text kept")
	var problems := ContentOverlay.problems(bad, base, _card_ids(), seat_count, false)
	for needle in ["unknown key 'spaces'", "unknown key 'groups'", "unknown key 'cards'", "non-name key 'list_price'",
			"'40' is not a space index", "'abc' is not a space index", "'no_group' is not a group",
			"'no_card' is not a card_id", "card_text 'ch_advance_go' is not a non-empty string",
			"seat_names has 7 names for %d seats" % seat_count,
			"seat_names[1] repeats 'S'", "seat_names[2] is not a non-empty string",
			"seat_names[3] is not a non-empty string"]:
		var found := false
		for p in problems:
			found = found or p.contains(needle)
		check(found, "problems() reports %s" % needle)
	var not_list := ContentOverlay.problems({"seat_names": {"0": "S"}}, base, _card_ids(), seat_count, false)
	check(not_list.has("seat_names is not a list"), "problems() reports a seat_names object")
	var not_object := ContentOverlay.problems({"card_text": ["W"]}, base, _card_ids(), seat_count, false)
	check(not_object.has("card_text is not an object"), "problems() reports a card_text list")
	var partial := {"terms": {"jail": "j"}, "space_names": {"0": {"display_name": "G"}}, "seat_names": ["S"]}
	check(ContentOverlay.problems(partial, base, _card_ids(), seat_count, false).is_empty(), "partial overlay valid when not complete")
	var missing := ContentOverlay.problems(partial, base, _card_ids(), seat_count, true)
	for needle in ["missing term 'house'", "missing space_names '1' display_name", "missing group_names 'brown'",
			"missing seat_names[1]", "missing seat_names[%d]" % (seat_count - 1)]:
		check(missing.has(needle), "complete overlay flags %s" % needle)
	check(not missing.has("missing term 'jail'") and not missing.has("missing seat_names[0]"), "named entries not reported missing")
	done()


## Dig 4a (Track B nit 3): apply() skips an empty string the way problems() rejects it (as for
## card_text above), so an overlay "" never blanks a shared word; problems() still reports each one.
func test_empty_overlay_strings_keep_shared_words() -> void:
	var base := _base_board()
	var overlay := {
		"terms": {"jail": ""},
		"space_names": {"1": {"display_name": ""}, "3": {"display_name": "N", "short_name": ""}},
		"group_names": {"brown": ""},
	}
	var tc := GameSetup.new_game(1234, [], overlay)
	check_eq(tc.board.term("jail"), base.term("jail"), "empty term keeps the shared word")
	check_eq(tc.board.spaces[1].display_name, base.spaces[1].display_name, "empty display_name keeps the shared name")
	check_eq(tc.board.spaces[1].short_name, base.spaces[1].short_name, "empty display_name keeps the shared short_name")
	check_eq(tc.board.group_info[&"brown"]["display_name"], base.group_info[&"brown"]["display_name"],
			"empty group name keeps the shared name")
	check_eq(tc.board.spaces[3].display_name, "N", "display_name applied")
	check_eq(tc.board.spaces[3].short_name, "N", "empty short_name skipped: short_name follows the new display_name")
	var problems := ContentOverlay.problems(overlay, base, _card_ids(), _seat_pool().size(), false)
	for needle in ["term 'jail' is not a non-empty string", "space_names '1' display_name is not a non-empty string",
			"space_names '3' short_name is not a non-empty string", "group_names 'brown' is not a non-empty string"]:
		check(problems.has(needle), "problems() reports %s" % needle)
	done()


## Dig 4a (Track B nits 8-9): space_names keys are canonical String indices only ("05" / "+5" / an
## int key would name space 5 in apply() yet not count for completeness); a section or name of the
## wrong type is reported by problems() and skipped by apply(); a short_name-only entry keeps the
## shared display_name.
func test_overlay_keys_and_sections_strict() -> void:
	var base := _base_board()
	var seat_count := _seat_pool().size()
	var odd_keys := {"space_names": {"05": {"display_name": "Q"}, "+5": {"display_name": "R"}, 5: {"display_name": "I"},
			"-0": {"display_name": "Z"}}}
	var tc := GameSetup.new_game(1234, [], odd_keys)
	check_eq(tc.board.spaces[5].display_name, base.spaces[5].display_name, "non-canonical keys not applied to space 5")
	check_eq(tc.board.spaces[0].display_name, base.spaces[0].display_name, "'-0' not applied to space 0")
	var problems := ContentOverlay.problems(odd_keys, base, _card_ids(), seat_count, false)
	for key in ["05", "+5", "-0"]:
		check(problems.has("space_names key '%s' is not a space index" % key), "problems() reports key '%s'" % key)
	check(problems.has("space_names key '5' is not a space index"), "problems() reports the int key 5")
	var entries := {"space_names": {"6": {"short_name": "S"}, "8": {"display_name": 5}}}
	var named := GameSetup.new_game(1234, [], entries)
	check_eq(named.board.spaces[6].display_name, base.spaces[6].display_name, "short_name-only entry keeps the shared display_name")
	check_eq(named.board.spaces[6].short_name, "S", "short_name-only entry applied")
	check_eq(named.board.spaces[8].display_name, base.spaces[8].display_name, "non-string display_name skipped")
	check_eq(named.board.spaces[8].short_name, base.spaces[8].short_name, "non-string display_name leaves short_name")
	check(ContentOverlay.problems(entries, base, _card_ids(), seat_count, false).has(
			"space_names '8' display_name is not a non-empty string"), "problems() reports a non-string display_name")
	var wrong_types := {"terms": ["x"], "space_names": "y", "group_names": 7}
	var plain := GameSetup.new_game(1234, [], wrong_types)
	check_eq(plain.board.term("jail"), base.term("jail"), "terms list skipped")
	check_eq(plain.board.spaces[1].display_name, base.spaces[1].display_name, "space_names string skipped")
	check_eq(plain.board.group_info[&"brown"]["display_name"], base.group_info[&"brown"]["display_name"],
			"group_names number skipped")
	problems = ContentOverlay.problems(wrong_types, base, _card_ids(), seat_count, false)
	for section in ["terms", "space_names", "group_names"]:
		check(problems.has("%s is not an object" % section), "problems() reports %s of the wrong type" % section)
	done()


## Dig 4a (Track B nit 7): the board readout names a Bank-owned deed with the pack's `unowned` term
## in sentence case (first letter only, so "t-unowned" keeps its spelling), never a hard-coded
## "Unowned".
func test_board_view_unowned_uses_pack_term() -> void:
	var cases := {FIXTURE_CONTENT: "T-unowned", DEFAULT_CONTENT: "Unclaimed"}
	for path: String in cases:
		var pack := path.get_base_dir().get_file()
		var tc := GameSetup.new_game(1234, [], JsonData.load_json(path))
		check_eq(tc.board.deed_at(39).owner, PropertyDeed.BANK, "%s: space 39 starts with the Bank" % pack)
		var bv := BoardView.new()
		bv.setup(tc)
		var text := " ".join(bv.space_details(39))
		check(text.contains(cases[path]), "%s: pack word in details: %s" % [pack, text])
		check(not text.contains("Unowned"), "%s: no hard-coded Unowned: %s" % [pack, text])
		bv.free()
	done()


## Dig 4a (Track B nit 6): build / sell lines (house and hotel) put no indefinite article before the
## pack word, so the default pack's vowel-initial "outpost module" never logs as "a outpost module".
func test_build_and_sell_lines_take_no_article() -> void:
	var tc := GameSetup.new_game(1234, [], JsonData.load_json(DEFAULT_CONTENT))
	var house := tc.board.term("house")
	check_eq(house, "outpost module", "default pack house word starts with a vowel")
	tc.board.deed_at(1).owner = 0
	tc.board.deed_at(3).owner = 0
	check(tc.build(0, 1), "build")
	check(tc.sell_building(0, 1), "sell")
	check(_logged(tc, "builds 1 %s on" % house), "build line: 1 %s" % house)
	check(_logged(tc, "sells 1 %s on" % house), "sell line: 1 %s" % house)
	for _i in 4:
		check(tc.build(0, 1) and tc.build(0, 3), "even build to 4 on each street")
	check(tc.build(0, 1) and tc.board.deed_at(1).has_hotel, "fifth build on space 1 is the hotel")
	check(tc.sell_building(0, 1), "sell the hotel")
	var hotel := tc.board.term("hotel")
	check(_logged(tc, "builds 1 %s on" % hotel), "hotel build line: 1 %s" % hotel)
	check(_logged(tc, "sells 1 %s on" % hotel), "hotel sell line: 1 %s" % hotel)
	check(not _logged(tc, "a outpost") and not _logged(tc, " a %s" % house), "no 'a outpost' in the log")
	done()


## Dig 3c (Shibi): seat names are pack words. seat_names (seat order, one per rules.json seat_pool
## seat) names the default seats: GameSetup.seats_for() / seats() for the setup screen and the
## local_players fallback of new_game(). Colors and Human/Bot flags stay shared; names a caller
## passes in are kept; no overlay (or a seat the list does not name) keeps the seat_pool name.
func test_seat_names_from_overlay() -> void:
	var fixture := JsonData.load_json(FIXTURE_CONTENT)
	var names: Array = fixture["seat_names"]
	var pool := _seat_pool()
	var flags: Array[bool] = [false, true, false, true, false, true]
	var themed := GameSetup.seats_for(flags, fixture)
	var plain := GameSetup.seats_for(flags)
	check_eq(themed.size(), pool.size(), "every seat_pool seat")
	for i in themed.size():
		check_eq(themed[i]["display_name"], names[i], "seat %d named by the pack" % (i + 1))
		check_eq(plain[i]["display_name"], pool[i]["display_name"], "seat %d without overlay keeps seat_pool" % (i + 1))
		check_eq(themed[i]["color"], pool[i]["color"], "seat %d color stays shared" % (i + 1))
		check_eq(themed[i]["is_bot"], flags[i], "seat %d Human/Bot from the choice" % (i + 1))
	ContentOverlay.name_seats(fixture, pool)
	check_eq(pool[0]["display_name"], plain[0]["display_name"], "name_seats() returns copies, input untouched")
	check_eq(GameSetup.seats(1, 1, fixture)[1]["display_name"], names[1], "seats() names from the pack too")
	var fallback := GameSetup.new_game(1234, [], fixture)
	var base := GameSetup.new_game(1234)
	check_eq(fallback.players.size(), base.players.size(), "local_players fallback seat count")
	for i in fallback.players.size():
		check_eq(fallback.players[i].display_name, names[i], "fallback seat %d named by the pack" % (i + 1))
		check_eq(fallback.players[i].is_bot, base.players[i].is_bot, "fallback seat %d Human/Bot unchanged" % (i + 1))
		check_eq(fallback.players[i].color, base.players[i].color, "fallback seat %d color unchanged" % (i + 1))
	var custom := GameSetup.new_game(1234, _seats(), fixture)
	check_eq(custom.players[0].display_name, "Ann", "a name the caller passes in is kept")
	var partial := GameSetup.seats_for([false, false, false] as Array[bool], {"seat_names": ["X", 3, ""]})
	check_eq(partial[0]["display_name"], "X", "seat named by a short list")
	check_eq(partial[1]["display_name"], pool[1]["display_name"], "non-string seat name skipped")
	check_eq(partial[2]["display_name"], pool[2]["display_name"], "empty seat name skipped")
	var not_list := GameSetup.seats_for([false, false] as Array[bool], {"seat_names": "Ann"})
	check_eq(not_list[0]["display_name"], pool[0]["display_name"], "seat_names that is not a list is ignored")
	done()


## Dig 3c (Shibi): card_text is optional per card. A pack's card_text replaces the cards.json text of
## the cards it names, end to end (deck card, log line, card game_event, banner line); cards it
## leaves out, and every card under a pack without card_text, keep the shared cards.json text.
func test_card_text_override_and_defaults() -> void:
	var shared := _shared_card_text()
	var fixture := JsonData.load_json(FIXTURE_CONTENT)
	var own: Dictionary = fixture["card_text"]
	check(own.has("ch_advance_go") and not own.has("ch_dividend"), "fixture overrides some cards, not all")
	var bare := fixture.duplicate(true)
	bare.erase("card_text")
	var tc := GameSetup.new_game(1234, [], fixture)
	var without := GameSetup.new_game(1234, [], bare)
	var seen := 0
	for deck in [tc.chance, tc.community_chest]:
		for c in deck.draw_pile:
			var cid := String(c.card_id)
			check_eq(c.text, String(own.get(cid, shared[cid])), "card %s: pack text where named, else cards.json" % cid)
			seen += 1
	for deck in [without.chance, without.community_chest]:
		for c in deck.draw_pile:
			check_eq(c.text, shared[String(c.card_id)], "card %s: no card_text keeps cards.json" % c.card_id)
			seen += 1
	check_eq(seen, 2 * shared.size(), "every card of both matches checked")
	var lines := DialogueLines.new()  # fallback lines show the card text as is ("{text}")
	var drawn := _draw_chance(tc, &"ch_advance_go")
	check_eq(String(drawn.get("text", "")), own["ch_advance_go"], "card event carries the pack text")
	check_eq(lines.event_line(tc, &"card", drawn), own["ch_advance_go"], "banner line shows the pack text")
	check(_logged(tc, own["ch_advance_go"]), "log shows the pack text")
	var kept := GameSetup.new_game(1234, [], fixture)
	drawn = _draw_chance(kept, &"ch_dividend")
	check_eq(String(drawn.get("text", "")), shared["ch_dividend"], "card the pack leaves out keeps cards.json text")
	check(_logged(kept, shared["ch_dividend"]), "log shows the shared text")
	drawn = _draw_chance(without, &"ch_advance_go")
	check_eq(lines.event_line(without, &"card", drawn), shared["ch_advance_go"], "no card_text: banner shows cards.json text")
	done()


## Draws Chance card `card_id` for the current player (space 4 + 3 = 7, a Chance space); returns the
## card game_event payload ({} when none was emitted).
func _draw_chance(tc: TurnController, card_id: StringName) -> Dictionary:
	var got := {}
	var grab := func(kind: StringName, info: Dictionary) -> void:
		if kind == &"card":
			got.merge(info)
	tc.game_event.connect(grab)
	check(tc.chance.move_to_top(card_id), "card %s found" % card_id)
	tc.current_player().position = 4
	tc.dice.force(1, 2)
	tc.roll()
	tc.game_event.disconnect(grab)
	return got


## A5: core stays free of UI; the overlay is passed in, never looked up.
func test_core_does_not_read_ui_style() -> void:
	var dir := "res://scripts/core"
	for fname in DirAccess.get_files_at(dir):
		if fname.ends_with(".gd"):
			var src := ""  # code only; doc comments may name UiStyle to say core never uses it
			for line in FileAccess.get_file_as_string(dir.path_join(fname)).split("\n"):
				src += line.get_slice("#", 0) + "\n"
			check(not src.contains("UiStyle"), "%s does not use UiStyle" % fname)
			check(not src.contains("ui.json"), "%s does not read ui.json" % fname)
			check(not src.contains("data/themes"), "%s does not read theme packs" % fname)
			check(not src.contains("scripts/ui"), "%s does not load UI scripts" % fname)
	done()


## A6: a seeded game under a non-default overlay never logs a default-pack word. Seats are named
## the way the setup screen names them (GameSetup.seats_for with the pack overlay, dig 3c), so a
## default seat name ("Commander N") would show up here.
func test_no_default_words_leak() -> void:
	var words := _default_words()
	var overlay := _full_fixture()
	var seat_names: Array = overlay["seat_names"]
	check_eq(ContentOverlay.problems(overlay, _base_board(), _card_ids(), _seat_pool().size(), true), [] as Array[String],
			"fixture overlay complete, so a leak can only come from code")
	for game_seed in [3, 8]:
		var tc := GameSetup.new_game(game_seed, GameSetup.seats_for([false, false, false] as Array[bool], overlay), overlay)
		check_eq(tc.players.size(), 3, "seed %d: three seats from the setup path" % game_seed)
		tc.determine_start_player()
		_exercise_jail_exits(tc)
		_play(tc, 1500)
		var texts: Array[String] = tc.log_lines.duplicate()
		for i in tc.players.size():
			texts.append(tc.players[i].display_name)
			check_eq(tc.players[i].display_name, seat_names[i], "seed %d: seat %d named by the pack" % [game_seed, i + 1])
			check(_logged(tc, seat_names[i]), "seed %d: log names seat %d by its pack name" % [game_seed, i + 1])
		for s in tc.board.spaces:
			texts.append(s.display_name)
			texts.append(s.short_name)
		for gid: StringName in tc.board.group_info:
			texts.append(String(tc.board.group_info[gid]["display_name"]))
		var self_trade := Trade.propose(0, 0)
		self_trade.give_cash = 1
		texts.append(Trade.validate(tc.board, tc.players, self_trade, tc.config))
		var card_trade := Trade.propose(0, 1)
		card_trade.give_cards.append(&"chance")
		texts.append(Trade.validate(tc.board, tc.players, card_trade, tc.config))
		var leaks: Array[String] = []
		for t in texts:
			for w in words:
				if t.contains(w):
					leaks.append("'%s' in \"%s\"" % [w, t])
		check_eq(leaks, [] as Array[String], "seed %d: no default-pack words" % game_seed)
		check(tc.log_lines.size() > 50, "seed %d: game produced a log" % game_seed)
	done()


## Fine and pardon exits (seeded play rarely reaches the pardon path).
func _exercise_jail_exits(tc: TurnController) -> void:
	var p := tc.current_player()
	p.in_jail = true
	p.position = tc.config.jail_index
	check(tc.pay_jail_fine(), "fine exit")
	var card: Card = null
	for c in tc.chance.draw_pile:
		if c.is_goojf():
			card = c
	tc.chance.draw_pile.erase(card)
	p.goojf_cards.append(card)
	p.in_jail = true
	check(tc.use_get_out_of_jail_card(), "pardon exit")


func _play(tc: TurnController, steps: int) -> void:
	for step in steps:
		var p := tc.current_player()
		match tc.phase:
			P.AWAITING_ROLL:
				if step % 4 == 0:
					for deed in tc.board.deeds_owned_by(p.id):
						if p.cash > 400:
							tc.build(p.id, deed.space_index)
				tc.roll()
			P.AWAITING_BUY_DECISION:
				if step % 5 == 0 or not tc.buy():
					tc.decline()
			P.AUCTION:
				var bidder := tc.players[tc.auction.current_bidder()]
				if step % 2 == 0 and bidder.cash >= tc.auction.min_next_bid() * 3:
					tc.auction_bid(tc.auction.min_next_bid())
				else:
					tc.auction_pass()
			P.RAISING_FUNDS:
				if not tc.pay_debt():
					tc.declare_bankruptcy()
			P.AWAITING_END_TURN:
				tc.end_turn()
			P.GAME_OVER:
				return


## A5 wiring: Main.begin_match passes the active pack's overlay to GameSetup.new_game().
func test_main_applies_pack_overlay_at_match_start() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var panel := main.show_setup(null)
	panel.save_path = ""
	var default_seats: Array = JsonData.load_json(DEFAULT_CONTENT)["seat_names"]
	check_eq(panel._seat_labels[0].text, default_seats[0], "default pack seat labels")
	panel.start()
	check_eq(main.controller.board.spaces[0].display_name, "Launch Bay", "default pack names")
	check_eq(main.controller.players[0].display_name, default_seats[0], "default pack seat names")
	main.free()
	panel.free()
	UiStyle.theme_index_path = FIXTURE_INDEX
	main = load("res://scenes/main.tscn").instantiate()
	panel = main.show_setup(null)
	panel.save_path = ""
	check(main.select_theme("test_alt"), "switch to the fixture pack on setup")
	var fixture := JsonData.load_json(FIXTURE_CONTENT)
	var seat_names: Array = fixture["seat_names"]
	for i in panel._seat_labels.size():
		check_eq(panel._seat_labels[i].text, seat_names[i], "setup seat %d label from the pack" % (i + 1))
	panel.start()
	var board := main.controller.board
	check_eq(board.spaces[0].display_name, "T Space 0", "pack space names at match start")
	check_eq(board.group_info[&"brown"]["display_name"], "T Group 1", "pack group names at match start")
	check_eq(board.term("buy"), "T-buy", "pack terms at match start")
	check(main._turn_panel.slot_text(&"buy").begins_with("T-buy"), "panel Buy uses the pack term")
	check_eq(main.controller.players.size(), panel.count, "one player per chosen seat")
	for i in main.controller.players.size():
		check_eq(main.controller.players[i].display_name, seat_names[i], "match seat %d named by the pack" % (i + 1))
	main.controller.current_index = 0  # setup seat 1 is a person by default
	main.controller.dice.force(1, 2)  # 0 -> 3: no card drawn
	check(main.press_die() and main.press_slot(&"action"), "Action after the person's move")
	check(main._overlay.visible and main._overlay_title.text.contains(seat_names[0]), "overlay title shows the pack name")
	var advance_go: Card = null
	for c in main.controller.chance.draw_pile:
		if c.card_id == &"ch_advance_go":
			advance_go = c
	check(advance_go != null and advance_go.text == fixture["card_text"]["ch_advance_go"], "pack card text at match start")
	main.free()
	panel.free()
	done()
