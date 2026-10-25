# P3-BOTTRADE report: smarter bot trading

## What changed
- `scripts/core/bot_trade.gd` (new, `BotTrade`): pure trade decisions. `answer(tc, offer)` returns
  ACCEPT / COUNTER / REJECT for an offer to a bot; `proposal(tc, player)` returns the best +EV offer
  or null. Helpers `gain`, `margin`, `refuses`, `accepts` are public for tests.
- `scripts/core/bot.gd`: new kinds `PROPOSE_TRADE`, `COUNTER_TRADE`, `Action.offer`; `decide()` uses
  `BotTrade.answer`; `_manage()` proposes (after lifting mortgages, before building) when no offer
  is open and the bot has not tried this turn. Old `wants_trade` removed. `Settings` reads 5 new keys.
- `scripts/core/trade.gd`: `Offer.is_counter`, set by `Trade.counter` (bots never counter a counter).
- `scripts/core/turn_controller.gd`: `bot_proposed_this_turn` (reset in `end_turn`), applies the two
  new kinds, and `bot_actor()` returns -1 while a bot's offer waits on a person (hotseat: the Trade
  tab opens on `trade_proposed`; bots resume on the next state change).
- `data/bot.json`: `trade_swap_min_percent` 110, `complete_set_bonus_percent` 100,
  `monopoly_block_bonus_percent` 50, `trade_counter_max_percent` 50, `trade_max_surplus_deeds` 2
  (all `_placeholder`, Q18). Existing `cash_buffer` 200 and `trade_min_cash_percent` 150 reused.
- No UI code, no theme strings, no rule changes; buildings and mortgaged-deed handling stay in `Trade`.

## Strategy (details in the `bot_trade.gd` class doc and OPEN_QUESTIONS Q18)
- Score: deed list prices (mortgaged: minus lift cost) + 100% of a full set's total list price,
  minus that bonus for any set the other side completes, + 50% of a set's total for buying the
  deed another commander lacks from a person (block).
- Answer: hard reject (pardon card out, deed of own full set, cash below $200, or proposer completes
  a set without the bot completing an equal-or-dearer one); accept if gain >= 50% premium on deeds
  sold for cash / 10% on swaps; else one cash counter if the shortfall <= 50% of deeds given.
- Propose: the bot's own missing deed or a block, priced at the seller's margin; spare deeds (never
  from a full or nearly complete own set, never mortgaged) only when cash would break $200. Against
  a bot seller only mutual set-completing swaps the seller would accept are proposed, so bot-vs-bot
  play never loops (counters end after one round; blocks are bought only from people).

## Tests
- `tests/test_bot_trade.gd` (8 new): cash proposal to complete a set; spare-deed proposal when cash
  is short (and none when nothing is spare); one proposal per turn; block proposal only from a
  person; reject underpay that completes the opponent's set, accept equal-or-better mutual
  completion, reject worse; accept fair cash-for-deed; uneven multi-deed swap counters once
  (asks $54) then rejects the person's re-counter, lopsided swap rejected; never sells from a full set.
- `tests/test_bot.gd`: `test_trades_only_clear_cash_for_deed` became
  `test_trade_answers_cash_for_deed` (lowball now gets a $150 counter; a deed + $500 for a $100
  deed is now accepted instead of rejected as "too complex").
- Result: **105 passed, 0 failed** (was 97). 2-bot soak still 8 of 10 seeded games reach a winner;
  4-bot smoke never stalls.

## Open
- Q18 TODO: bots do not remember rejected offers, so a person may see the same offer each bot turn.
- Bots never offer pardon cards or deed-for-deed counters (cash-only counter).
