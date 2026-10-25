class_name Mortgage
extends RefCounted
## Mortgaging (docs/classic_monopoly_structure.md 4.3). Pure static checks and actions.


## Owner only; every building in the color set must be sold first.
static func can_mortgage(board: Board, player: Player, deed: PropertyDeed) -> bool:
	if player.is_bankrupt or deed.owner != player.id or deed.is_mortgaged:
		return false
	return not Building.group_has_buildings(board, deed.color_group_id)


## Returns the mortgage value received, or -1 if not allowed.
static func mortgage(board: Board, bank: Bank, player: Player, deed: PropertyDeed) -> int:
	if not can_mortgage(board, player, deed):
		return -1
	deed.is_mortgaged = true
	bank.pay(player, deed.mortgage_value)
	return deed.mortgage_value


static func can_unmortgage(player: Player, deed: PropertyDeed, config: RulesConfig) -> bool:
	return (not player.is_bankrupt and deed.owner == player.id and deed.is_mortgaged
		and player.cash >= Rules.unmortgage_cost(deed, config))


## Pays mortgage value + interest. Returns the price paid, or -1 if not allowed.
static func unmortgage(bank: Bank, player: Player, deed: PropertyDeed, config: RulesConfig) -> int:
	if not can_unmortgage(player, deed, config):
		return -1
	var cost := Rules.unmortgage_cost(deed, config)
	deed.is_mortgaged = false
	bank.collect(player, cost)
	return cost


## 4.3 item 5: a new owner of a mortgaged deed pays this at once to keep the mortgage.
static func transfer_interest(deed: PropertyDeed, config: RulesConfig) -> int:
	return int(ceil(deed.mortgage_value * config.mortgage_transfer_interest_percent / 100.0))
