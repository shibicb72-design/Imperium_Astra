# Imperium Astra P1-PHASE Report (any-time actions and jail)

**Date:** 2026-10-24
**Tip before:** `0493c80` P1-TRD: classic trade module

## Audit
Checked `TurnController`, `Building`, `Mortgage`, `Trade`, `Auction`, `Bankruptcy` and the UI
panels for "must be current player" or "in jail" gates on any-time actions.

- **No violations found.** `build`, `sell_building`, `sell_group_buildings`, `mortgage`,
  `unmortgage` and every trade action go through `can_manage(player_id)` (any active commander,
  any phase but GAME_OVER). The rule modules check only ownership, sets, stock and cash; none
  read `current_index` or `in_jail`. `HoldingsPanel` / `TradePanel` let any commander act.
- Intentional current-player-only actions (now documented in the `TurnController` header):
  `roll` (incl. the jail doubles try), `pay_jail_fine` and `use_get_out_of_jail_card` (before
  rolling, AWAITING_ROLL, classic 6.3), `buy` / `decline`, `end_turn`. Auction bids follow the
  auction's bidder order; debts are paid by their debtor, on or off turn.
- Jail restricts only movement / leaving: a jailed commander builds, sells, mortgages, trades
  (incl. buying a pardon card and then using it), bids in auctions, collects rent, and raises
  funds for the third-try fine.

No rule code changed; the controller header comment and docs were updated.

## Tests (new `tests/test_phase.gd`, 10 tests)
Off-turn build / sell / mortgage / unmortgage; off-turn actions in every live phase and none
after game over; off-turn trade as proposer and receiver; off-turn mortgage during an auction;
creditor builds while the debtor raises funds; turn-bound actions refused off-turn (fine,
pardon, roll, buy); jailed current player builds / mortgages / buys a pardon by trade and
uses it; off-turn jailed player mortgages and trades a mortgaged deed (Q13 default); jailed
player bids, wins an auction and collects rent; jailed player raises funds for the fine.

## Verification (MEASURED)
```
godot --headless --path . --import                              # ok
godot --headless --path . --script res://tests/run_tests.gd     # 60 passed, 0 failed
godot --headless --path . --export-debug "Android" build/imperium-astra-debug.apk   # signed, verified
```

## Defaults and open points
- Q13 (EL default, pending Shibi): traded mortgaged deed stays mortgaged, receiver pays 10% now.
- Q14 (EL default, pending Shibi): trade refused if a side cannot pay the 10%; no debt created.
- Q15 (new): debtors may still build / unmortgage / trade cash away before paying.
- Q12 hotseat UX (any commander picks themselves in Holdings) stays open.
