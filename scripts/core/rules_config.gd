class_name RulesConfig
extends RefCounted
## Typed view of data/rules.json. Every rule number comes from data, never from code.

var starting_cash: int
var go_salary: int
var jail_index: int
var jail_fine: int
var max_jail_turns: int
var doubles_to_jail: int
var railroad_rent: Array[int] = []
var utility_multiplier: Array[int] = []
var houses_in_bank: int
var hotels_in_bank: int
var auction_min_bid: int
var auction_increment: int
var unmortgage_interest_percent: int
var free_parking_jackpot: bool
var min_players: int
var max_players: int
var local_players: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> RulesConfig:
	var c := RulesConfig.new()
	c.starting_cash = int(d["starting_cash"])
	c.go_salary = int(d["go_salary"])
	c.jail_index = int(d["jail_index"])
	c.jail_fine = int(d["jail_fine"])
	c.max_jail_turns = int(d["max_jail_turns"])
	c.doubles_to_jail = int(d["doubles_to_jail"])
	for v in d["railroad_rent"]:
		c.railroad_rent.append(int(v))
	for v in d["utility_multiplier"]:
		c.utility_multiplier.append(int(v))
	c.houses_in_bank = int(d["houses_in_bank"])
	c.hotels_in_bank = int(d["hotels_in_bank"])
	c.auction_min_bid = int(d["auction_min_bid"])
	c.auction_increment = int(d["auction_increment"])
	c.unmortgage_interest_percent = int(d["unmortgage_interest_percent"])
	c.free_parking_jackpot = bool(d["free_parking_jackpot"])
	c.min_players = int(d["min_players"])
	c.max_players = int(d["max_players"])
	for p in d["local_players"]:
		c.local_players.append(p)
	return c
