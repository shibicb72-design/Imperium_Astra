class_name Auction
extends RefCounted
## One deed auction (docs/classic_monopoly_structure.md 3.1): bids start at min_bid and rise by at
## least `increment`; any active player may bid, including the one who declined; no bid means
## the deed stays with the Bank.
## Digital flow (INFERRED, docs/OPEN_QUESTIONS.md Q3): bidders act in seat order, each either
## raising or dropping out for good, until only the high bidder is left.

const NO_BIDDER := PropertyDeed.BANK

var space_index: int = -1
var min_bid: int = 0
var increment: int = 1
var high_bid: int = 0
var high_bidder: int = NO_BIDDER

var _active: Array[int] = []
var _turn: int = 0


func _init(p_space_index: int, bidder_ids: Array[int], p_min_bid: int, p_increment: int) -> void:
	space_index = p_space_index
	_active = bidder_ids.duplicate()
	min_bid = p_min_bid
	increment = maxi(1, p_increment)


func is_finished() -> bool:
	return _active.is_empty() or (_active.size() == 1 and _active[0] == high_bidder)


func has_winner() -> bool:
	return high_bidder != NO_BIDDER


func current_bidder() -> int:
	return NO_BIDDER if is_finished() else _active[_turn]


func active_bidders() -> Array[int]:
	return _active.duplicate()


func min_next_bid() -> int:
	return min_bid if high_bidder == NO_BIDDER else high_bid + increment


func can_bid(player_id: int, amount: int, cash: int) -> bool:
	return not is_finished() and player_id == current_bidder() and amount >= min_next_bid() and amount <= cash


func bid(player_id: int, amount: int, cash: int) -> bool:
	if not can_bid(player_id, amount, cash):
		return false
	high_bid = amount
	high_bidder = player_id
	_turn = (_turn + 1) % _active.size()
	_skip_high_bidder()
	return true


## The current bidder drops out of this auction.
func pass_turn(player_id: int) -> bool:
	if is_finished() or player_id != current_bidder():
		return false
	_active.remove_at(_turn)
	if _turn >= _active.size():
		_turn = 0
	_skip_high_bidder()
	return true


func _skip_high_bidder() -> void:
	if not is_finished() and _active[_turn] == high_bidder:
		_turn = (_turn + 1) % _active.size()
