class_name TurnController
extends RefCounted
## Turn state machine (docs/classic_monopoly_structure.md section 3, 6). Pure logic: the UI only
## calls the public actions below and listens to signals.
##
## P0 scope: roll/move, GO salary, buy, rent (auto-asked: the owner always asks in local play),
## taxes, cards, jail (fine / pardon card / doubles / third-turn fine). Not yet: auctions,
## building, mortgaging, trades, bankruptcy settlement (see docs/OPEN_QUESTIONS.md).

signal turn_started(player: Player)
signal turn_ended(player: Player)
signal doubles_extra_turn(player: Player)
signal sent_to_jail(player: Player, reason: String)
signal rent_requested(owner: Player, payer: Player, amount: int)
signal winner_declared(player: Player)
signal status(message: String)
signal state_changed

enum Phase { AWAITING_ROLL, AWAITING_BUY_DECISION, AWAITING_END_TURN, GAME_OVER }

var config: RulesConfig
var board: Board
var bank: Bank
var dice := Dice.new()
var chance: CardDeck
var community_chest: CardDeck
var players: Array[Player] = []
var current_index: int = 0
var doubles_streak: int = 0
var phase: Phase = Phase.AWAITING_ROLL
var pending_buy_index: int = -1
var last_card: Card = null
var log_lines: Array[String] = []

var _extra_turn_pending := false


func current_player() -> Player:
	return players[current_index]


## Official setup: everyone rolls both dice, highest starts (ties re-roll among the tied).
func determine_start_player() -> void:
	var contenders: Array[int] = []
	for p in players:
		contenders.append(p.id)
	while contenders.size() > 1:
		var best := -1
		var leaders: Array[int] = []
		for id in contenders:
			dice.roll()
			if dice.total() > best:
				best = dice.total()
				leaders = [id]
			elif dice.total() == best:
				leaders.append(id)
		contenders = leaders
	current_index = contenders[0]
	_say("%s rolls highest and starts." % current_player().display_name)
	turn_started.emit(current_player())
	state_changed.emit()


func roll() -> void:
	if phase != Phase.AWAITING_ROLL:
		return
	var p := current_player()
	dice.roll()
	_extra_turn_pending = false
	_say("%s rolled %d + %d." % [p.display_name, dice.d1, dice.d2])
	if p.in_jail:
		_roll_in_jail(p)
	elif dice.is_doubles() and doubles_streak + 1 >= config.doubles_to_jail:
		doubles_streak = 0
		_send_to_jail(p, "third doubles in a row")
	else:
		if dice.is_doubles():
			doubles_streak += 1
			_extra_turn_pending = true
		move_by(p, dice.total())
		_resolve_space(p, {"dice_total": dice.total()})
	_after_resolution()


## Section 6.3 option 1: pay the fine at the start of the turn, then roll normally.
func pay_jail_fine() -> bool:
	var p := current_player()
	if phase != Phase.AWAITING_ROLL or not p.in_jail or p.cash < config.jail_fine:
		return false
	bank.collect(p, config.jail_fine)
	_release(p)
	_say("%s pays $%d and leaves the Brig." % [p.display_name, config.jail_fine])
	state_changed.emit()
	return true


## Section 6.3 option 2: use a held pardon card; it returns to the bottom of its deck.
func use_get_out_of_jail_card() -> bool:
	var p := current_player()
	if phase != Phase.AWAITING_ROLL or not p.in_jail or p.goojf_cards.is_empty():
		return false
	var card: Card = p.goojf_cards.pop_front()
	_deck_for(card.deck_id).return_to_bottom(card)
	_release(p)
	_say("%s uses a pardon and leaves the Brig." % p.display_name)
	state_changed.emit()
	return true


func buy() -> bool:
	if phase != Phase.AWAITING_BUY_DECISION:
		return false
	var p := current_player()
	var deed := board.deed_at(pending_buy_index)
	if not bank.sell_property(p, deed):
		return false
	_say("%s claims %s for $%d." % [p.display_name, board.spaces[pending_buy_index].display_name, deed.list_price])
	pending_buy_index = -1
	_post_landing()
	return true


## Declining sends the deed to auction (official). P0 auction is a stub: the deed stays in the Bank.
func decline() -> void:
	if phase != Phase.AWAITING_BUY_DECISION:
		return
	var deed := board.deed_at(pending_buy_index)
	bank.auction(deed)
	_say("Auction is not in P0 yet; %s stays with the Bank." % board.spaces[pending_buy_index].display_name)
	pending_buy_index = -1
	_post_landing()


func end_turn() -> void:
	if phase != Phase.AWAITING_END_TURN:
		return
	turn_ended.emit(current_player())
	doubles_streak = 0
	for step in range(1, players.size() + 1):
		var next := (current_index + step) % players.size()
		if not players[next].is_bankrupt:
			current_index = next
			break
	phase = Phase.AWAITING_ROLL
	_say("%s's turn." % current_player().display_name)
	turn_started.emit(current_player())
	state_changed.emit()


## Moves forward (or backward when steps < 0). Passing or landing on GO pays salary only forward.
func move_by(p: Player, steps: int) -> void:
	if Rules.passes_go(p.position, steps):
		bank.pay(p, config.go_salary)
		_say("%s passes %s: +$%d." % [p.display_name, board.spaces[0].display_name, config.go_salary])
	p.set_position(posmod(p.position + steps, Board.SPACE_COUNT))


func move_to(p: Player, target: int) -> void:
	move_by(p, posmod(target - p.position, Board.SPACE_COUNT))


func _roll_in_jail(p: Player) -> void:
	if dice.is_doubles():
		# 6.3 option 3: doubles free you; move with that roll; no extra turn.
		_release(p)
		_say("Doubles! %s leaves the Brig." % p.display_name)
	else:
		p.jail_turns_tried += 1
		if p.jail_turns_tried < config.max_jail_turns:
			_say("%s stays in the Brig." % p.display_name)
			return
		# 6.4: third failed try: pay the fine and move with this roll.
		bank.collect(p, config.jail_fine)
		_release(p)
		_say("%s pays $%d after the third try." % [p.display_name, config.jail_fine])
	move_by(p, dice.total())
	_resolve_space(p, {"dice_total": dice.total()})


func _resolve_space(p: Player, ctx: Dictionary) -> void:
	var s := board.spaces[p.position]
	match s.space_type:
		Space.Type.STREET, Space.Type.RAILROAD, Space.Type.UTILITY:
			_resolve_property(p, s, ctx)
		Space.Type.CHANCE:
			_draw_card(p, chance)
		Space.Type.COMMUNITY_CHEST:
			_draw_card(p, community_chest)
		Space.Type.INCOME_TAX, Space.Type.LUXURY_TAX:
			bank.collect(p, s.tax_amount)
			_say("%s pays %s: $%d." % [p.display_name, s.display_name, s.tax_amount])
		Space.Type.GO_TO_JAIL:
			_send_to_jail(p, s.display_name)
		Space.Type.FREE_PARKING:
			# Official rules: nothing happens. The jackpot house rule is not implemented.
			if config.free_parking_jackpot:
				push_warning("free_parking_jackpot is a house rule and is not implemented")
			_say("%s rests at %s." % [p.display_name, s.display_name])
		_:
			pass


func _resolve_property(p: Player, s: Space, ctx: Dictionary) -> void:
	var deed := s.deed
	if deed.owner == PropertyDeed.BANK:
		pending_buy_index = s.index
		phase = Phase.AWAITING_BUY_DECISION
		_say("%s is unclaimed: $%d." % [s.display_name, deed.list_price])
		return
	if deed.owner == p.id or deed.is_mortgaged:
		return
	var amount: int
	if ctx.has("dice_multiplier"):
		dice.roll()  # card says throw the dice for this utility rent
		amount = dice.total() * int(ctx["dice_multiplier"])
	else:
		amount = Rules.rent_for(board, s.index, int(ctx.get("dice_total", 0)), config)
		amount *= int(ctx.get("rent_multiplier", 1))
	var owner := players[deed.owner]
	_transfer(p, owner, amount)
	_say("%s pays %s $%d rent." % [p.display_name, owner.display_name, amount])
	rent_requested.emit(owner, p, amount)


func _draw_card(p: Player, deck: CardDeck) -> void:
	var card := deck.draw()
	if card == null:
		return
	last_card = card
	_say("%s: %s" % [board.spaces[p.position].display_name, card.text])
	if card.is_goojf():
		p.goojf_cards.append(card)
	else:
		deck.return_to_bottom(card)
		_apply_card(p, card)


func _apply_card(p: Player, card: Card) -> void:
	var prm := card.params
	match card.opcode:
		&"ADVANCE_TO":
			move_to(p, int(prm["target"]))
			_resolve_space(p, {"dice_total": dice.total()})
		&"MOVE_RELATIVE":
			move_by(p, int(prm["steps"]))
			_resolve_space(p, {"dice_total": dice.total()})
		&"MOVE_NEAREST":
			move_to(p, board.next_index_of_type(p.position, Space.type_from_string(String(prm["space_type"]))))
			var ctx := {"dice_total": dice.total()}
			if prm.has("rent_multiplier"):
				ctx["rent_multiplier"] = int(prm["rent_multiplier"])
			if prm.has("dice_multiplier"):
				ctx["dice_multiplier"] = int(prm["dice_multiplier"])
			_resolve_space(p, ctx)
		&"COLLECT_BANK":
			bank.pay(p, int(prm["amount"]))
		&"PAY_BANK":
			bank.collect(p, int(prm["amount"]))
		&"PAY_EACH_PLAYER":
			for other in _other_active_players(p):
				_transfer(p, other, int(prm["amount"]))
		&"COLLECT_FROM_EACH":
			for other in _other_active_players(p):
				_transfer(other, p, int(prm["amount"]))
		&"REPAIRS":
			bank.collect(p, Rules.repairs_cost(board, p.id, int(prm["per_house"]), int(prm["per_hotel"])))
		&"GO_TO_JAIL":
			_send_to_jail(p, "card")
		_:
			push_error("TurnController: unknown card opcode %s" % card.opcode)


func _send_to_jail(p: Player, reason: String) -> void:
	p.set_position(config.jail_index)
	p.in_jail = true
	p.jail_turns_tried = 0
	doubles_streak = 0
	_extra_turn_pending = false
	_say("%s is sent to %s (%s)." % [p.display_name, board.spaces[config.jail_index].display_name, reason])
	sent_to_jail.emit(p, reason)


func _release(p: Player) -> void:
	p.in_jail = false
	p.jail_turns_tried = 0


func _after_resolution() -> void:
	if phase == Phase.AWAITING_BUY_DECISION or phase == Phase.GAME_OVER:
		state_changed.emit()
		return
	_post_landing()


func _post_landing() -> void:
	var p := current_player()
	if _extra_turn_pending and not p.in_jail and not p.is_bankrupt:
		phase = Phase.AWAITING_ROLL
		_say("Doubles: %s rolls again." % p.display_name)
		doubles_extra_turn.emit(p)
	else:
		phase = Phase.AWAITING_END_TURN
	_extra_turn_pending = false
	_check_winner()
	state_changed.emit()


func _transfer(from: Player, to: Player, amount: int) -> void:
	from.add_cash(-amount)
	to.add_cash(amount)
	# TODO(P1): raise funds / bankruptcy settlement (section 4.4) when cash goes negative.


func _other_active_players(p: Player) -> Array[Player]:
	var out: Array[Player] = []
	for other in players:
		if other != p and not other.is_bankrupt:
			out.append(other)
	return out


func _check_winner() -> void:
	var alive: Array[Player] = []
	for p in players:
		if not p.is_bankrupt:
			alive.append(p)
	if alive.size() == 1:
		phase = Phase.GAME_OVER
		_say("%s wins!" % alive[0].display_name)
		winner_declared.emit(alive[0])


func _deck_for(deck_id: StringName) -> CardDeck:
	return chance if deck_id == chance.deck_id else community_chest


func _say(message: String) -> void:
	log_lines.append(message)
	status.emit(message)
