extends TestCase
## Pack content overlay (P5-FEEL A5) and hard-coded flavor strip (A6): GameSetup.new_game() applies
## the overlay passed in (terms, space / group names, card text by card_id) without touching rules
## data; core never reads UiStyle / ui.json; Main passes the active pack's overlay at match start;
## with a non-default overlay no default-pack word reaches the log, board or trade messages.
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


## Fixture overlay plus card_text for every card, so no default-pack word is left anywhere.
static func _full_fixture() -> Dictionary:
	var o := JsonData.load_json(FIXTURE_CONTENT)
	var text: Dictionary = o["card_text"]
	for cid in _card_ids():
		if not text.has(cid):
			text[cid] = "T card %s." % cid
	return o


## Every word the default pack overlay supplies (terms, space and group names).
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
	return words


static func _seats() -> Array[Dictionary]:
	return [{"display_name": "Ann", "color": "#ff0000"}, {"display_name": "Bob", "color": "#00ff00"},
			{"display_name": "Cy", "color": "#0000ff"}]


func test_default_overlay_matches_board_json() -> void:
	var base := _base_board()
	var d := JsonData.load_json(DEFAULT_CONTENT)
	check_eq(ContentOverlay.problems(d, base, _card_ids(), true), [] as Array[String], "default overlay valid")
	check_eq(d["terms"], base.terms, "terms match board.json")
	for i in base.spaces.size():
		var e: Dictionary = d["space_names"][str(i)]
		check_eq(e["display_name"], base.spaces[i].display_name, "space %d name matches" % i)
		check_eq(e.get("short_name", e["display_name"]), base.spaces[i].short_name, "space %d short name matches" % i)
	for gid: StringName in base.group_info:
		check_eq(d["group_names"][String(gid)], base.group_info[gid]["display_name"], "group %s matches" % gid)
	var tc := GameSetup.new_game(1234, [], d)
	check_eq(tc.board.spaces[0].display_name, base.spaces[0].display_name, "default overlay changes nothing")
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
		"card_text": {"no_card": "W"},
	}
	var tc := GameSetup.new_game(1234, [], bad)
	check_eq(tc.board.spaces[1].display_name, "X", "name applied")
	check_eq(tc.board.spaces[1].list_price, base.spaces[1].list_price, "price key inside space_names ignored")
	check_eq(tc.board.group_info[&"brown"]["color"], base.group_info[&"brown"]["color"], "banned groups key ignored")
	check_eq(tc.chance.draw_pile.size(), 16, "banned cards key ignored")
	var problems := ContentOverlay.problems(bad, base, _card_ids(), false)
	for needle in ["unknown key 'spaces'", "unknown key 'groups'", "unknown key 'cards'", "non-name key 'list_price'",
			"'40' is not a space index", "'abc' is not a space index", "'no_group' is not a group",
			"'no_card' is not a card_id"]:
		var found := false
		for p in problems:
			found = found or p.contains(needle)
		check(found, "problems() reports %s" % needle)
	var partial := {"terms": {"jail": "j"}, "space_names": {"0": {"display_name": "G"}}}
	check(ContentOverlay.problems(partial, base, _card_ids(), false).is_empty(), "partial overlay valid when not complete")
	check(not ContentOverlay.problems(partial, base, _card_ids(), true).is_empty(), "partial overlay flagged when complete")
	done()


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
	done()


## A6: a seeded game under a non-default overlay never logs a default-pack word.
func test_no_default_words_leak() -> void:
	var words := _default_words()
	for game_seed in [3, 8]:
		var tc := GameSetup.new_game(game_seed, _seats(), _full_fixture())
		tc.determine_start_player()
		_exercise_jail_exits(tc)
		_play(tc, 1500)
		var texts: Array[String] = tc.log_lines.duplicate()
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
	panel.start()
	check_eq(main.controller.board.spaces[0].display_name, "Launch Bay", "default pack names")
	main.free()
	panel.free()
	UiStyle.theme_index_path = FIXTURE_INDEX
	main = load("res://scenes/main.tscn").instantiate()
	panel = main.show_setup(null)
	panel.save_path = ""
	check(main.select_theme("test_alt"), "switch to the fixture pack on setup")
	panel.start()
	var board := main.controller.board
	check_eq(board.spaces[0].display_name, "T Space 0", "pack space names at match start")
	check_eq(board.group_info[&"brown"]["display_name"], "T Group 1", "pack group names at match start")
	check_eq(board.term("buy"), "T-buy", "pack terms at match start")
	check(main._buy_button.text.begins_with("T-buy"), "buy button uses the pack term")
	main.free()
	panel.free()
	done()
