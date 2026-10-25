class_name GameSetup
extends RefCounted
## Builds a fresh local match from res://data/*.json. Used by GameState (UI) and by tests.

const RULES_PATH := "res://data/rules.json"
const BOARD_PATH := "res://data/board.json"
const CARDS_PATH := "res://data/cards.json"


## rng_seed < 0 picks a random seed. Players come from rules.json local_players (P0 hotseat).
static func new_game(rng_seed: int = -1) -> TurnController:
	var config := RulesConfig.from_dict(JsonData.load_json(RULES_PATH))
	var cards := JsonData.load_json(CARDS_PATH)
	var tc := TurnController.new()
	tc.config = config
	tc.board = Board.from_dict(JsonData.load_json(BOARD_PATH))
	tc.bank = Bank.new(config.houses_in_bank, config.hotels_in_bank)
	if rng_seed < 0:
		tc.dice.rng.randomize()
	else:
		tc.dice.rng.seed = rng_seed
	tc.chance = CardDeck.from_array(&"chance", cards.get("chance", []))
	tc.community_chest = CardDeck.from_array(&"community_chest", cards.get("community_chest", []))
	tc.chance.shuffle(tc.dice.rng)
	tc.community_chest.shuffle(tc.dice.rng)
	for i in config.local_players.size():
		var spec: Dictionary = config.local_players[i]
		var p := Player.new()
		p.id = i
		p.display_name = String(spec["display_name"])
		p.color = Color.html(String(spec["color"]))
		p.cash = config.starting_cash
		tc.players.append(p)
	return tc
