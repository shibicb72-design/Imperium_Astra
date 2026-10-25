class_name Bank
extends RefCounted
## The Bank never goes broke (official), so its cash is not tracked. Owns building stock and
## unowned deeds (deeds whose owner is PropertyDeed.BANK).

signal auction_required(deed: PropertyDeed)

var houses_remaining: int = 0
var hotels_remaining: int = 0


func _init(houses: int = 0, hotels: int = 0) -> void:
	houses_remaining = houses
	hotels_remaining = hotels


func pay(player: Player, amount: int) -> void:
	player.add_cash(amount)


func collect(player: Player, amount: int) -> void:
	player.add_cash(-amount)


func sell_property(player: Player, deed: PropertyDeed) -> bool:
	if deed.owner != PropertyDeed.BANK or player.cash < deed.list_price:
		return false
	collect(player, deed.list_price)
	deed.owner = player.id
	return true


## The Banker announces an auction; the bidding itself is the Auction module, run by TurnController.
func auction(deed: PropertyDeed) -> void:
	auction_required.emit(deed)
