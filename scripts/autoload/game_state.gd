extends Node
## Autoload "GameState": holds the current local match for UI scenes.
## All rules live in scripts/core/ (pure RefCounted types, headless-testable).

var controller: TurnController = null


func new_local_game(rng_seed: int = -1) -> TurnController:
	controller = GameSetup.new_game(rng_seed)
	controller.determine_start_player()
	return controller
