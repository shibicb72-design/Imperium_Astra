class_name Building
extends RefCounted
## Houses and hotels (docs/classic_monopoly_structure.md 3.2). Pure static checks and actions on
## Board / Bank / Player; TurnController only orchestrates. A hotel counts as level 5 (it replaces
## 4 houses, which go back to the Bank).

const MAX_HOUSES := 4
const HOTEL_LEVEL := 5
## Building lot kinds (ids, also the board.json term keys).
const HOUSE := &"house"
const HOTEL := &"hotel"


static func level(deed: PropertyDeed) -> int:
	return HOTEL_LEVEL if deed.has_hotel else deed.houses


static func group_deeds(board: Board, group_id: StringName) -> Array[PropertyDeed]:
	var out: Array[PropertyDeed] = []
	if board.color_groups.has(group_id):
		for i: int in board.color_groups[group_id]:
			out.append(board.deed_at(i))
	return out


static func group_has_buildings(board: Board, group_id: StringName) -> bool:
	for d in group_deeds(board, group_id):
		if level(d) > 0:
			return true
	return false


## Needs the full color set, no mortgaged street in it, even building (this street may not get
## ahead of the lowest one), Bank stock and cash.
static func can_build(board: Board, bank: Bank, player: Player, deed: PropertyDeed) -> bool:
	if not can_place(board, player, deed):
		return false
	return stock(bank, next_kind(deed)) > 0 and player.cash >= next_cost(deed)


## The next building on this street is legal (full set, none mortgaged, even building), not
## counting Bank stock or cash. A shortage-auction claim must pass this.
static func can_place(board: Board, player: Player, deed: PropertyDeed) -> bool:
	if deed == null or player.is_bankrupt or deed.owner != player.id or not board.color_groups.has(deed.color_group_id):
		return false
	if not board.owns_full_group(player.id, deed.color_group_id):
		return false
	var lowest := HOTEL_LEVEL
	for d in group_deeds(board, deed.color_group_id):
		if d.is_mortgaged:
			return false
		lowest = mini(lowest, level(d))
	var lv := level(deed)
	return lv < HOTEL_LEVEL and lv <= lowest


## Returns the price paid, or -1 if not allowed.
static func build(board: Board, bank: Bank, player: Player, deed: PropertyDeed) -> int:
	if not can_build(board, bank, player, deed):
		return -1
	var kind := next_kind(deed)
	var cost := next_cost(deed)
	take_lot(bank, kind)
	place_lot(board, bank, player, deed, kind)
	bank.collect(player, cost)
	return cost


# --- Building lots (shortage auction, docs/classic_monopoly_structure.md 3.2, Q10) -----------

## Kind of the next building on this street: HOUSE, or HOTEL on a 4-house street.
static func next_kind(deed: PropertyDeed) -> StringName:
	return HOTEL if deed.houses == MAX_HOUSES else HOUSE


## List cost of the next building on this street.
static func next_cost(deed: PropertyDeed) -> int:
	return deed.hotel_cost if next_kind(deed) == HOTEL else deed.house_cost


static func stock(bank: Bank, kind: StringName) -> int:
	return bank.hotels_remaining if kind == HOTEL else bank.houses_remaining


## Official shortage: the Bank has some of this kind left but fewer than the players who want
## one, so it auctions them. With enough stock (or none) building stays first come, first served.
static func is_contested(bank: Bank, kind: StringName, claimants: int) -> bool:
	var left := stock(bank, kind)
	return claimants >= 2 and left > 0 and claimants > left


## Takes one building of `kind` out of Bank stock (for a build or a running lot auction).
## False, and nothing changes, if the Bank has none: stock never goes negative.
static func take_lot(bank: Bank, kind: StringName) -> bool:
	if stock(bank, kind) <= 0:
		return false
	if kind == HOTEL:
		bank.hotels_remaining -= 1
	else:
		bank.houses_remaining -= 1
	return true


## Puts a building taken by take_lot() back into Bank stock (unsold lot).
static func return_lot(bank: Bank, kind: StringName) -> void:
	if kind == HOTEL:
		bank.hotels_remaining += 1
	else:
		bank.houses_remaining += 1


## Places a building already taken out of stock on this street, under the normal placement rules
## (a hotel sends its 4 houses back to the Bank). No payment here. False if not legal now.
static func place_lot(board: Board, bank: Bank, player: Player, deed: PropertyDeed, kind: StringName) -> bool:
	if not can_place(board, player, deed) or next_kind(deed) != kind:
		return false
	if kind == HOTEL:
		bank.houses_remaining += MAX_HOUSES
		deed.houses = 0
		deed.has_hotel = true
	else:
		deed.houses += 1
	return true


static func sell_value(cost: int, config: RulesConfig) -> int:
	return int(cost * config.building_sell_percent / 100.0)


## Sell one level evenly (this street must be among the highest). Selling a hotel trades it
## back for 4 houses, so the Bank must have 4 houses in stock; otherwise use sell_group().
static func can_sell(board: Board, bank: Bank, player: Player, deed: PropertyDeed) -> bool:
	if deed.owner != player.id or level(deed) == 0:
		return false
	for d in group_deeds(board, deed.color_group_id):
		if level(d) > level(deed):
			return false
	if deed.has_hotel:
		return bank.houses_remaining >= MAX_HOUSES
	return true


## Returns the money received, or -1 if not allowed.
static func sell(board: Board, bank: Bank, player: Player, deed: PropertyDeed, config: RulesConfig) -> int:
	if not can_sell(board, bank, player, deed):
		return -1
	var value: int
	if deed.has_hotel:
		value = sell_value(deed.hotel_cost, config)
		bank.hotels_remaining += 1
		bank.houses_remaining -= MAX_HOUSES
		deed.has_hotel = false
		deed.houses = MAX_HOUSES
	else:
		value = sell_value(deed.house_cost, config)
		bank.houses_remaining += 1
		deed.houses -= 1
	bank.pay(player, value)
	return value


## What every building on this deed would fetch if sold back at once.
static func liquidation_value(deed: PropertyDeed, config: RulesConfig) -> int:
	if deed.has_hotel:
		return sell_value(deed.hotel_cost, config) + MAX_HOUSES * sell_value(deed.house_cost, config)
	return deed.houses * sell_value(deed.house_cost, config)


## Sells every building in the group at once (always even, needs no house stock). Returns the
## money received, or -1 if the player has nothing to sell there.
static func sell_group(board: Board, bank: Bank, player: Player, group_id: StringName, config: RulesConfig) -> int:
	var total := 0
	var sold := false
	for d in group_deeds(board, group_id):
		if d.owner != player.id or level(d) == 0:
			continue
		sold = true
		total += liquidation_value(d, config)
		if d.has_hotel:
			bank.hotels_remaining += 1
		else:
			bank.houses_remaining += d.houses
		d.has_hotel = false
		d.houses = 0
	if not sold:
		return -1
	bank.pay(player, total)
	return total
