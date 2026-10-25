class_name BuildingLotAuction
extends Auction
## Non-deed Auction variant: one Bank building (house or hotel) during a building shortage
## (docs/classic_monopoly_structure.md 3.2: several players want more than the Bank has -> auction
## from $10). Same bidding as a deed auction; space_index stays -1. Each bidder has a claim: the
## street they would build it on. The winner pays the bid instead of the list cost and builds on
## that street under the normal placement rules (Building.place_lot).
## How claims get declared (claim window, bot / person interest) is undecided: OPEN_QUESTIONS Q10
## `_placeholder`. Only TurnController.start_building_auction() creates these.

## Building.HOUSE or Building.HOTEL.
var kind: StringName
## Bidder id -> space index of the street they claimed.
var claims: Dictionary[int, int] = {}


func _init(p_kind: StringName, p_claims: Dictionary[int, int], bidder_ids: Array[int], p_min_bid: int, p_increment: int) -> void:
	super(-1, bidder_ids, p_min_bid, p_increment)
	kind = p_kind
	claims = p_claims.duplicate()


func is_building_lot() -> bool:
	return true


func claim_of(player_id: int) -> int:
	return claims.get(player_id, -1)


## List cost of the building on this bidder's claimed street.
func list_price_for(board: Board, player_id: int) -> int:
	var i := claim_of(player_id)
	return 0 if i < 0 else Building.next_cost(board.deed_at(i))
