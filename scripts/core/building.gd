class_name Building
extends RefCounted
## Houses and hotels (docs/classic_monopoly_structure.md 3.2). Pure static checks and actions on
## Board / Bank / Player; TurnController only orchestrates. A hotel counts as level 5 (it replaces
## 4 houses, which go back to the Bank).

const MAX_HOUSES := 4
const HOTEL_LEVEL := 5


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
	if player.is_bankrupt or deed.owner != player.id or not board.color_groups.has(deed.color_group_id):
		return false
	if not board.owns_full_group(player.id, deed.color_group_id):
		return false
	var lowest := HOTEL_LEVEL
	for d in group_deeds(board, deed.color_group_id):
		if d.is_mortgaged:
			return false
		lowest = mini(lowest, level(d))
	var lv := level(deed)
	if lv >= HOTEL_LEVEL or lv > lowest:
		return false
	if lv == MAX_HOUSES:
		return bank.hotels_remaining > 0 and player.cash >= deed.hotel_cost
	return bank.houses_remaining > 0 and player.cash >= deed.house_cost


## Returns the price paid, or -1 if not allowed.
static func build(board: Board, bank: Bank, player: Player, deed: PropertyDeed) -> int:
	if not can_build(board, bank, player, deed):
		return -1
	var cost: int
	if deed.houses == MAX_HOUSES:
		cost = deed.hotel_cost
		bank.hotels_remaining -= 1
		bank.houses_remaining += MAX_HOUSES
		deed.houses = 0
		deed.has_hotel = true
	else:
		cost = deed.house_cost
		bank.houses_remaining -= 1
		deed.houses += 1
	bank.collect(player, cost)
	return cost


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
