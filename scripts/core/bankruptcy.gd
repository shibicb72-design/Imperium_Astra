class_name Bankruptcy
extends RefCounted
## Debts and bankruptcy settlement (docs/classic_monopoly_structure.md 4.4). Pure static helpers;
## TurnController queues debts and runs any follow-up auctions.


## Money a player owes to another player (creditor = player id) or to the Bank (PropertyDeed.BANK).
class Debt:
	var debtor: int
	var creditor: int
	var amount: int

	func _init(p_debtor: int, p_creditor: int, p_amount: int) -> void:
		debtor = p_debtor
		creditor = p_creditor
		amount = p_amount


## Most cash the player could raise: cash + selling every building + mortgaging every deed.
static func max_raisable(board: Board, player: Player, config: RulesConfig) -> int:
	var total := player.cash
	for deed in board.deeds_owned_by(player.id):
		total += Building.liquidation_value(deed, config)
		if not deed.is_mortgaged:
			total += deed.mortgage_value
	return total


## 4.4: bankruptcy is only for a debt the player cannot cover even after selling and mortgaging.
static func can_declare(board: Board, player: Player, amount: int, config: RulesConfig) -> bool:
	return not player.is_bankrupt and max_raisable(board, player, config) < amount


## Owed a player (H-00009): buildings are sold to the Bank at the sell-back price, then all cash,
## deeds (mortgaged ones stay mortgaged) and pardon cards go to the creditor. Returns the interest
## the creditor owes the Bank to keep the inherited mortgages.
## TODO(OPEN_QUESTIONS Q9): the creditor may instead lift each mortgage at once; placeholder keeps them.
static func settle_to_player(board: Board, bank: Bank, debtor: Player, creditor: Player, config: RulesConfig) -> int:
	_sell_all_buildings(board, bank, debtor, config)
	creditor.add_cash(debtor.cash)
	debtor.add_cash(-debtor.cash)
	var interest := 0
	for deed in board.deeds_owned_by(debtor.id):
		deed.owner = creditor.id
		if deed.is_mortgaged:
			interest += Mortgage.transfer_interest(deed, config)
	creditor.goojf_cards.append_array(debtor.goojf_cards)
	debtor.goojf_cards.clear()
	_mark_bankrupt(debtor)
	return interest


## Owed the Bank: buildings and deeds return to the Bank (mortgages cancelled), cash is gone,
## pardon cards go to the bottom of their decks. Returns the space indices the Bank must auction.
static func settle_to_bank(board: Board, bank: Bank, debtor: Player, decks: Array[CardDeck]) -> Array[int]:
	var to_auction: Array[int] = []
	for deed in board.deeds_owned_by(debtor.id):
		if deed.has_hotel:
			bank.hotels_remaining += 1
		else:
			bank.houses_remaining += deed.houses
		deed.has_hotel = false
		deed.houses = 0
		deed.is_mortgaged = false
		deed.owner = PropertyDeed.BANK
		to_auction.append(deed.space_index)
	for card in debtor.goojf_cards:
		for deck in decks:
			if deck.deck_id == card.deck_id:
				deck.return_to_bottom(card)
	debtor.goojf_cards.clear()
	debtor.add_cash(-debtor.cash)
	_mark_bankrupt(debtor)
	return to_auction


static func _sell_all_buildings(board: Board, bank: Bank, player: Player, config: RulesConfig) -> void:
	for gid: StringName in board.color_groups:
		if Building.group_has_buildings(board, gid):
			Building.sell_group(board, bank, player, gid, config)


static func _mark_bankrupt(p: Player) -> void:
	p.is_bankrupt = true
	p.in_jail = false
	p.jail_turns_tried = 0
	p.bankrupt.emit()
