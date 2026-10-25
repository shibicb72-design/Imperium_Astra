# Imperium Astra P2-BOT report: simple hotseat bots

## What was built
- `scripts/core/bot.gd` (`Bot`): pure decisions. `Bot.decide(tc, player_id)` reads the match and
  returns one `Bot.Action`; it never changes state. `Bot.Settings` is the typed view of
  `data/bot.json` (all heuristic numbers; `_placeholder`, OPEN_QUESTIONS Q18).
- `TurnController`: `deciding_player()`, `bot_actor()` (a trade offer to a bot is answered first,
  then the debtor / auction bidder / current player if that seat is a bot), `bot_step()` (one
  decision applied through the existing public actions) and `run_bots(max_steps)` for headless play.
  No rule logic moved; bots go through the same checks as people.
- Seats: `Player.is_bot`; `GameSetup.new_game(seed, seats)` and `GameSetup.seats(humans, bots)`
  (2-6 seats, names/colors from `rules.json` `seat_pool`, placeholders). Default match in
  `rules.json` `local_players`: Commander 1 human + Commander 2 bot. `GameState.new_local_game`
  takes the same seats list. No setup screen yet (OPEN_QUESTIONS Q19).
- UI (`main.gd`): a one-shot Timer plays one bot step every `bot_step_seconds` (data/ui.json, 0.4 s)
  while a bot is up; turn buttons and InputMap shortcuts are hidden on a bot's turn; player chips
  show "(bot)". Auction and debt banners disable their buttons when the bidder / debtor is a bot.

## Heuristics (data/bot.json)
| Situation | Bot does |
|---|---|
| Unowned land | Buy if `cash - price >= cash_buffer` (200); else decline -> auction |
| Auction | Bid `min_next_bid` (rules: $10 open, $1 steps) while it is <= min(cash - 200, list price x 100%); else drop out |
| Own turn (before roll and before end) | Lift the cheapest mortgage if $500 stays; else build the lowest-level, cheapest legal street if $200 stays (Building enforces full set, no mortgages, even build, hotels when all at 4) |
| Jail | Pardon card; else pay fine if $200 stays; else roll; on the last try pay first if it can |
| Debt | Pay if cash covers it; declare bankruptcy if even full liquidation cannot; else sell buildings (highest level first, whole group if a hotel cannot be broken), then mortgage (outside full sets first, cheapest first) |
| Trade offer to the bot | Accept only cash-in / deeds-out offers paying >= 150% of list price that do not complete the proposer's color set and do not break one of the bot's sets; reject everything else. Bots never propose |
| Bankrupt on its own turn | Ends the turn so play moves on |

## Tests (tests/test_bot.gd, 13 tests)
Default seats and `seats()` limits; `bot_actor` idle on human turns; buy vs decline at the buffer;
auction bid cap by buffer and by list price; jail (pardon, pay, roll, last-try pay); even build
within buffer through to hotels, no build on a mortgaged set, mortgage lift when comfortable; debt
order sell -> sell -> mortgage railroad -> pay; bankruptcy when nothing covers the debt; bankrupt
bot hands its turn on; trade accept/reject cases; Main hides turn buttons on a bot turn; soak:
10 seeded 2-bot games (60k step cap, invariants checked) plus three 4-bot games that must not stall.

## Verification (actual output)
- `godot --headless --path . --import`: clean.
- `godot --headless --path . --script res://tests/run_tests.gd`: **83 passed, 0 failed**.
- Bot soak: **8 of 10** seeded 2-bot games reached a winner (test requires at least half). The
  other two were still running at the step cap: with no trading, games where neither bot gets a
  color set can go on for a long time.
- The 4-bot soak caught one real bug during development (a bot that went bankrupt on its own turn
  returned no action, stalling the turn); fixed and covered by `test_bankrupt_bot_hands_turn_on`.

## Open / trade-offs
- Q18: heuristic numbers are guesses; "buy if affordable" vs the $200 buffer is a tunable choice.
- Q19: no seat setup screen; the default 1 human + 1 bot is for smoke testing.
- Bots answer a person's trade offer at once; they never make offers (P2 keeps trading simple).
- Off-turn management by bots (building while another player's turn runs) is not done; bots
  manage on their own turn only.
