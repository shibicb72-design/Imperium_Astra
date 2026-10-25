class_name MatchGate
extends RefCounted
## Match presentation / input gate (P5-FEEL Dig 5, board-first). What the match screen shows and
## which presses it takes is a pure function of the rules phase, the deciding seat
## (TurnController.deciding_player()), the receiver of an open trade offer and whether the board is
## still animating. Main re-evaluates it in _refresh() (on state_changed, and on animation_finished
## once the board queue drains) and every press handler checks it again at press time, so nothing
## waits on a signal alone. These are presentation states only: TurnController.Phase is unchanged.
##
## Settled table (OPEN_QUESTIONS Q23-Q28 placeholders; bots play behind a chrome-free board):
## - BUSY: dice tumbling or a piece moving (rolling / moving): board only, die and panel inert.
## - AWAIT_DIE_TAP: a person's AWAITING_ROLL, not jailed (also between doubles rolls, Q26): die only.
## - JAIL_SET: a jailed person's AWAITING_ROLL: name + Pay fine / Use pardon / Action, and the die
##   rolls for doubles. The only pre-roll panel (Q25).
## - BUY: AWAITING_BUY_DECISION: name + Buy (disabled, price shown, when cash is short) / Skip
##   (decline -> auction) / Action.
## - END_TURN: AWAITING_END_TURN (after a move, a buy, an auction or a failed jail roll): name +
##   Action / End Turn.
## - AUCTION / DEBT: the person bidding / owing, on any seat's turn: their overlay; DEBT also opens
##   Holdings for the debtor.
## - TRADE_ANSWER: an open offer waits on a person: the answer overlay for the receiver (a bot's
##   offer pauses the bots until it is answered).
## - BOT: a bot decides.
## - GAME_OVER: the winner's name; no die, no actions.

enum State { BUSY, AWAIT_DIE_TAP, JAIL_SET, BUY, END_TURN, AUCTION, DEBT, TRADE_ANSWER, BOT, GAME_OVER }

## Q23 slot map: the turn panel's options per state, in order. TurnPanel labels them; one map, so
## a relabel or a reorder is a one-line change. Each shows only when legal (TurnPanel.slot_shown).
const PANEL_SLOTS := {
	State.JAIL_SET: [&"fine", &"pardon", &"action"],
	State.BUY: [&"buy", &"skip", &"action"],
	State.END_TURN: [&"action", &"end_turn"],
}


## The state for one set of facts (pure, so tests can table-drive it). `decider_is_person` and
## `decider_jailed` describe deciding_player(); `offer_to_person`: an open trade offer waits on a
## person (trade_offer.to_id); `busy`: BoardView.is_animating().
static func state_for(phase: int, decider_is_person: bool, decider_jailed: bool, offer_to_person: bool,
		busy: bool) -> State:
	if busy:
		return State.BUSY
	if phase == TurnController.Phase.GAME_OVER:
		return State.GAME_OVER
	if offer_to_person:
		return State.TRADE_ANSWER
	if not decider_is_person:
		return State.BOT
	match phase:
		TurnController.Phase.AUCTION:
			return State.AUCTION
		TurnController.Phase.RAISING_FUNDS:
			return State.DEBT
		TurnController.Phase.AWAITING_BUY_DECISION:
			return State.BUY
		TurnController.Phase.AWAITING_END_TURN:
			return State.END_TURN
	return State.JAIL_SET if decider_jailed else State.AWAIT_DIE_TAP


## The state of a live match. Busy is checked first, so a moving board never asks the rules.
static func of(tc: TurnController, busy: bool) -> State:
	if busy:
		return State.BUSY
	var id := tc.deciding_player()
	var decider: Player = tc.players[id] if id >= 0 else null
	var offer_to_person := tc.trade_offer != null and not tc.players[tc.trade_offer.to_id].is_bot
	return state_for(tc.phase, decider != null and not decider.is_bot, decider != null and decider.in_jail,
			offer_to_person, false)


## The turn panel's options for `state` (empty: no panel).
static func panel_slots(state: State) -> Array:
	return PANEL_SLOTS.get(state, [])


## The die rolls (die-ready look, die press, roll_dice): a person's AWAITING_ROLL, jailed or not.
static func die_live(state: State) -> bool:
	return state == State.AWAIT_DIE_TAP or state == State.JAIL_SET


## Forced inputs a person owes (auction bid, debt, trade answer), on or off turn. Dig 5a1 interim:
## they still use the control column, shown only while needed.
static func is_forced(state: State) -> bool:
	return state == State.AUCTION or state == State.DEBT or state == State.TRADE_ANSWER
