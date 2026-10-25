class_name Rules
extends RefCounted
## Pure rule functions (no state, no UI) so headless tests can assert them directly.
## References are to docs/classic_monopoly_structure.md sections.


## 4.1: deed rent for houses/hotel; unimproved streets in a complete color set pay double
## (still double when another street of the set is mortgaged). Mortgaged -> 0.
static func street_rent(board: Board, deed: PropertyDeed) -> int:
	if deed.is_mortgaged or deed.owner == PropertyDeed.BANK:
		return 0
	if deed.has_hotel:
		return deed.rent_by_houses[5]
	if deed.houses > 0:
		return deed.rent_by_houses[deed.houses]
	var base := deed.rent_by_houses[0]
	if board.owns_full_group(deed.owner, deed.color_group_id):
		return base * 2
	return base


## 4.2: 25 / 50 / 100 / 200 by jump gates (railroads) owned. Mortgaged gates still count toward
## the owner's total (classic deed wording counts railroads owned).
static func railroad_rent(board: Board, deed: PropertyDeed, config: RulesConfig) -> int:
	if deed.is_mortgaged or deed.owner == PropertyDeed.BANK:
		return 0
	var owned := board.count_owned(deed.owner, Space.Type.RAILROAD)
	return config.railroad_rent[clampi(owned, 1, config.railroad_rent.size()) - 1]


## 4.2: 4x dice with one utility, 10x with both.
static func utility_rent(board: Board, deed: PropertyDeed, dice_total: int, config: RulesConfig) -> int:
	if deed.is_mortgaged or deed.owner == PropertyDeed.BANK:
		return 0
	var owned := board.count_owned(deed.owner, Space.Type.UTILITY)
	return dice_total * config.utility_multiplier[clampi(owned, 1, config.utility_multiplier.size()) - 1]


static func rent_for(board: Board, space_index: int, dice_total: int, config: RulesConfig) -> int:
	var s := board.spaces[space_index]
	match s.space_type:
		Space.Type.STREET:
			return street_rent(board, s.deed)
		Space.Type.RAILROAD:
			return railroad_rent(board, s.deed, config)
		Space.Type.UTILITY:
			return utility_rent(board, s.deed, dice_total, config)
	return 0


## 3 / 1.1: moving forward `steps` from `from` passes or lands on GO.
static func passes_go(from: int, steps: int) -> bool:
	return steps > 0 and from + steps >= Board.SPACE_COUNT


## 4.3: unmortgage cost = mortgage value + 10% (percent from data).
static func unmortgage_cost(deed: PropertyDeed, config: RulesConfig) -> int:
	return deed.mortgage_value + int(ceil(deed.mortgage_value * config.unmortgage_interest_percent / 100.0))


## 5.1 repairs cards: cost per house and per hotel the player owns.
static func repairs_cost(board: Board, player_id: int, per_house: int, per_hotel: int) -> int:
	var total := 0
	for deed in board.deeds_owned_by(player_id):
		if deed.has_hotel:
			total += per_hotel
		else:
			total += deed.houses * per_house
	return total
