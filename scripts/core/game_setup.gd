class_name GameSetup
extends RefCounted
## Builds a fresh local match from res://data/*.json. Used by GameState (UI) and by tests.

const RULES_PATH := "res://data/rules.json"
const BOARD_PATH := "res://data/board.json"
const CARDS_PATH := "res://data/cards.json"
const BOT_PATH := "res://data/bot.json"


## rng_seed < 0 picks a random seed. Players come from `seats` (see seats()) or, when empty, from
## rules.json local_players (P0 hotseat). A seat is {display_name, color, is_bot}.
## `content` is the active theme pack's content overlay (ContentOverlay: terms, space / group
## names, optional card text), passed in by the caller; {} keeps board.json / cards.json words.
static func new_game(rng_seed: int = -1, seat_specs: Array[Dictionary] = [], content: Dictionary = {}) -> TurnController:
	var config := RulesConfig.from_dict(JsonData.load_json(RULES_PATH))
	var cards := JsonData.load_json(CARDS_PATH)
	var tc := TurnController.new()
	tc.config = config
	tc.board = Board.from_dict(JsonData.load_json(BOARD_PATH))
	tc.bank = Bank.new(config.houses_in_bank, config.hotels_in_bank)
	tc.bot_settings = Bot.Settings.from_dict(JsonData.load_json(BOT_PATH))
	if rng_seed < 0:
		tc.dice.rng.randomize()
	else:
		tc.dice.rng.seed = rng_seed
	tc.chance = CardDeck.from_array(&"chance", cards.get("chance", []))
	tc.community_chest = CardDeck.from_array(&"community_chest", cards.get("community_chest", []))
	ContentOverlay.apply(content, tc.board, [tc.chance, tc.community_chest])
	tc.chance.shuffle(tc.dice.rng)
	tc.community_chest.shuffle(tc.dice.rng)
	var specs := seat_specs if not seat_specs.is_empty() else config.local_players
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var p := Player.new()
		p.id = i
		p.display_name = String(spec["display_name"])
		p.color = Color.html(String(spec["color"]))
		p.is_bot = bool(spec.get("is_bot", false))
		p.cash = config.starting_cash
		tc.players.append(p)
	return tc


## Seat list for new_game(): `humans` people first, then `bots`, named from rules.json seat_pool.
## Empty if the total is outside min_players..max_players or the pool is too short.
static func seats(humans: int, bots: int) -> Array[Dictionary]:
	if humans < 0 or bots < 0:
		return []
	var flags: Array[bool] = []
	for i in humans + bots:
		flags.append(i >= humans)
	return seats_for(flags)


## Seat list in seat order: seat i is a bot when bot_flags[i] is true (setup screen). Names and
## colors from rules.json seat_pool. Empty if the count is outside min_players..max_players or the
## pool is too short. Any human/bot mix is legal here (all-bot soak games included); the setup
## screen applies its own minimum of people (data/ui.json setup_min_humans).
static func seats_for(bot_flags: Array[bool]) -> Array[Dictionary]:
	var config := RulesConfig.from_dict(JsonData.load_json(RULES_PATH))
	var out: Array[Dictionary] = []
	var total := bot_flags.size()
	if total < config.min_players or total > config.max_players or total > config.seat_pool.size():
		return out
	for i in total:
		var spec: Dictionary = config.seat_pool[i].duplicate()
		spec["is_bot"] = bot_flags[i]
		out.append(spec)
	return out
