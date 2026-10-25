class_name CardDeck
extends RefCounted
## Ordered draw pile. Official rule: draw from the top, return to the bottom (no discard pile).

signal card_drawn(card: Card)

var deck_id: StringName = &""
var draw_pile: Array[Card] = []


static func from_array(id: StringName, cards: Array) -> CardDeck:
	var deck := CardDeck.new()
	deck.deck_id = id
	for d in cards:
		deck.draw_pile.append(Card.from_dict(id, d))
	return deck


## Fisher-Yates with the match RNG so a seed reproduces the order.
func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


func draw() -> Card:
	if draw_pile.is_empty():
		return null
	var card: Card = draw_pile.pop_front()
	card_drawn.emit(card)
	return card


func return_to_bottom(card: Card) -> void:
	draw_pile.append(card)


## Test/debug helper: move a card to the top of the pile.
func move_to_top(card_id: StringName) -> bool:
	for i in draw_pile.size():
		if draw_pile[i].card_id == card_id:
			var card := draw_pile[i]
			draw_pile.remove_at(i)
			draw_pile.push_front(card)
			return true
	return false
