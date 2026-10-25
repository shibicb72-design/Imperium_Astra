class_name Player
extends RefCounted
## A seat in the match. Deeds are not stored here: Board deeds hold `owner` (single source of truth).

signal cash_changed(new_cash: int)
signal moved(new_position: int)
signal bankrupt

var id: int = 0
var display_name: String = ""
var color: Color = Color.WHITE
var cash: int = 0
var position: int = 0
var in_jail: bool = false
var jail_turns_tried: int = 0
var goojf_cards: Array[Card] = []
var is_bankrupt: bool = false
## Seat played by Bot (TurnController.bot_step) instead of a person.
var is_bot: bool = false


func add_cash(amount: int) -> void:
	cash += amount
	cash_changed.emit(cash)


func set_position(index: int) -> void:
	position = index
	moved.emit(index)
