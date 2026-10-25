class_name Trade
extends RefCounted
## Private trades between players (docs/classic_monopoly_structure.md 3.2, 4.3 item 5). Pure static
## checks and actions; TurnController holds the open offer and logs the outcome.
##
## Flow: propose -> the receiver accepts, rejects or counters (a counter is a new offer the other
## way). Official: cash, unimproved deeds (railroads / utilities too) and pardon cards may change hands at
## any time. Buildings cannot be traded: every building in a deed's color set must be sold first.
## A mortgaged deed stays mortgaged; its new owner pays the Bank the transfer interest (10% of the
## mortgage value) at once. TODO(OPEN_QUESTIONS Q13): the receiver may instead lift it at once.

enum Status { PENDING, ACCEPTED, REJECTED, COUNTERED }


## One offer: `from_id` proposes, `to_id` must accept, reject or counter. "give" = from -> to,
## "get" = to -> from. Deeds are space indices; pardon cards are deck ids.
class Offer:
	var from_id: int
	var to_id: int
	var give_cash: int = 0
	var get_cash: int = 0
	var give_deeds: Array[int] = []
	var get_deeds: Array[int] = []
	var give_cards: Array[StringName] = []
	var get_cards: Array[StringName] = []
	var status: Status = Status.PENDING

	func _init(p_from: int, p_to: int) -> void:
		from_id = p_from
		to_id = p_to

	func is_empty() -> bool:
		return (give_cash == 0 and get_cash == 0 and give_deeds.is_empty() and get_deeds.is_empty()
			and give_cards.is_empty() and get_cards.is_empty())


static func propose(from_id: int, to_id: int) -> Offer:
	return Offer.new(from_id, to_id)


## Empty string when the offer can be accepted as it stands, otherwise the first reason it cannot.
static func validate(board: Board, players: Array[Player], offer: Offer, config: RulesConfig) -> String:
	if offer.from_id == offer.to_id:
		return "A commander cannot trade with themselves."
	if not _valid_id(players, offer.from_id) or not _valid_id(players, offer.to_id):
		return "Unknown commander."
	var a := players[offer.from_id]
	var b := players[offer.to_id]
	if a.is_bankrupt or b.is_bankrupt:
		return "Bankrupt commanders cannot trade."
	if offer.is_empty():
		return "The offer is empty."
	if offer.give_cash < 0 or offer.get_cash < 0:
		return "Cash amounts cannot be negative."
	if offer.give_cash > a.cash or offer.get_cash > b.cash:
		return "Not enough cash."
	var deed_error := _check_deeds(board, offer.give_deeds, a.id)
	if deed_error.is_empty():
		deed_error = _check_deeds(board, offer.get_deeds, b.id)
	if not deed_error.is_empty():
		return deed_error
	if not _holds_cards(a, offer.give_cards) or not _holds_cards(b, offer.get_cards):
		return "Pardon card not held."
	# Each side must be able to pay the transfer interest on mortgaged deeds it receives.
	if a.cash - offer.give_cash + offer.get_cash < interest_due(board, offer.get_deeds, config):
		return "%s cannot pay the mortgage interest." % a.display_name
	if b.cash - offer.get_cash + offer.give_cash < interest_due(board, offer.give_deeds, config):
		return "%s cannot pay the mortgage interest." % b.display_name
	return ""


static func is_valid(board: Board, players: Array[Player], offer: Offer, config: RulesConfig) -> bool:
	return validate(board, players, offer, config).is_empty()


## Transfer interest owed to the Bank by whoever receives these deeds (mortgaged ones only).
static func interest_due(board: Board, space_indices: Array[int], config: RulesConfig) -> int:
	var total := 0
	for i in space_indices:
		var deed := board.deed_at(i)
		if deed != null and deed.is_mortgaged:
			total += Mortgage.transfer_interest(deed, config)
	return total


## Only the receiver (`by_id` == offer.to_id) may accept. Swaps cash, deeds and pardon cards, then
## charges each new owner of a mortgaged deed the transfer interest. Returns false and changes
## nothing if the offer is not pending, not theirs to accept, or no longer valid.
static func accept(board: Board, bank: Bank, players: Array[Player], offer: Offer, by_id: int, config: RulesConfig) -> bool:
	if offer.status != Status.PENDING or by_id != offer.to_id:
		return false
	if not is_valid(board, players, offer, config):
		return false
	var a := players[offer.from_id]
	var b := players[offer.to_id]
	var a_interest := interest_due(board, offer.get_deeds, config)
	var b_interest := interest_due(board, offer.give_deeds, config)
	a.add_cash(offer.get_cash - offer.give_cash)
	b.add_cash(offer.give_cash - offer.get_cash)
	for i in offer.give_deeds:
		board.deed_at(i).owner = b.id
	for i in offer.get_deeds:
		board.deed_at(i).owner = a.id
	_move_cards(a, b, offer.give_cards)
	_move_cards(b, a, offer.get_cards)
	if a_interest > 0:
		bank.collect(a, a_interest)
	if b_interest > 0:
		bank.collect(b, b_interest)
	offer.status = Status.ACCEPTED
	return true


## Only the receiver may reject. Nothing but the offer status changes.
static func reject(offer: Offer, by_id: int) -> bool:
	if offer.status != Status.PENDING or by_id != offer.to_id:
		return false
	offer.status = Status.REJECTED
	return true


## The receiver answers with `reply`, a new offer from them back to the proposer. The original is
## closed as COUNTERED; `reply` becomes the open offer. Returns false and changes nothing if the
## receiver may not counter or `reply` is not valid.
static func counter(board: Board, players: Array[Player], offer: Offer, reply: Offer, config: RulesConfig) -> bool:
	if offer.status != Status.PENDING or reply.status != Status.PENDING:
		return false
	if reply.from_id != offer.to_id or reply.to_id != offer.from_id:
		return false
	if not is_valid(board, players, reply, config):
		return false
	offer.status = Status.COUNTERED
	return true


## Same terms seen from the other side (a starting point for a counter-offer).
static func mirror(offer: Offer) -> Offer:
	var c := Offer.new(offer.to_id, offer.from_id)
	c.give_cash = offer.get_cash
	c.get_cash = offer.give_cash
	c.give_deeds = offer.get_deeds.duplicate()
	c.get_deeds = offer.give_deeds.duplicate()
	c.give_cards = offer.get_cards.duplicate()
	c.get_cards = offer.give_cards.duplicate()
	return c


## A deed can be traded by its owner when no street in its color set has buildings.
static func can_trade_deed(board: Board, player_id: int, space_index: int) -> bool:
	if space_index < 0 or space_index >= board.spaces.size():
		return false
	var deed := board.deed_at(space_index)
	if deed == null or deed.owner != player_id:
		return false
	return not Building.group_has_buildings(board, deed.color_group_id)


static func _valid_id(players: Array[Player], id: int) -> bool:
	return id >= 0 and id < players.size()


static func _check_deeds(board: Board, indices: Array[int], owner_id: int) -> String:
	var seen := {}
	for i in indices:
		if seen.has(i):
			return "A deed is listed twice."
		seen[i] = true
		if i < 0 or i >= board.spaces.size() or board.deed_at(i) == null or board.deed_at(i).owner != owner_id:
			return "Cannot trade a deed you do not own."
		if not can_trade_deed(board, owner_id, i):
			return "Sell the buildings in that color set first."
	return ""


static func _holds_cards(p: Player, deck_ids: Array[StringName]) -> bool:
	var held := {}
	for c in p.goojf_cards:
		held[c.deck_id] = int(held.get(c.deck_id, 0)) + 1
	for id in deck_ids:
		var left := int(held.get(id, 0))
		if left <= 0:
			return false
		held[id] = left - 1
	return true


static func _move_cards(src: Player, dst: Player, deck_ids: Array[StringName]) -> void:
	for id in deck_ids:
		for k in src.goojf_cards.size():
			if src.goojf_cards[k].deck_id == id:
				dst.goojf_cards.append(src.goojf_cards[k])
				src.goojf_cards.remove_at(k)
				break
