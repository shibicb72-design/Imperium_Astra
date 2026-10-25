extends Node
## Autoload "GameState": holds the current local match for UI scenes.
## All rules live in scripts/core/ (pure RefCounted types, headless-testable).

var controller: TurnController = null


## `seats` from GameSetup.seats(humans, bots); empty uses rules.json local_players.
## `content`: the active pack's content overlay (UiStyle.content_overlay()).
func new_local_game(rng_seed: int = -1, seats: Array[Dictionary] = [], content: Dictionary = {}) -> TurnController:
	controller = GameSetup.new_game(rng_seed, seats, content)
	controller.determine_start_player()
	return controller
