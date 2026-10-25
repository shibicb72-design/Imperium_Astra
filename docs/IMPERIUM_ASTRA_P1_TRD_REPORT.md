# Imperium Astra P1-TRD Report (Trade)

**Date:** 2026-10-24
**Tip before:** `9bf711f` P1: auction, building, mortgage, bankruptcy

## Delivered
- `scripts/core/trade.gd` - `Trade` module (pure static) with `Trade.Offer`:
  `propose`, `validate` / `is_valid`, `accept`, `reject`, `counter` (+ `mirror` to prefill),
  `interest_due`, `can_trade_deed`. Cash, deeds (mortgaged or not) and pardon cards on both sides.
  - Classic 3.2: trades at any time; no deed whose color set has buildings.
  - Classic 4.3 item 5: a mortgaged deed stays mortgaged; the receiver pays the Bank
    `Mortgage.transfer_interest` (10% of mortgage value, `data/rules.json`) at once.
  - Refused: self-trade, empty offer, negative / unheld cash, deeds not owned (other player, Bank,
    non-deed space), duplicate deeds, unheld pardon cards, bankrupt party, unaffordable interest.
  - Reject / withdraw change only the offer status.
- `TurnController`: `propose_trade`, `accept_trade`, `reject_trade`, `counter_trade`,
  `cancel_trade`, `trade_problem`; one open `trade_offer`; signals `trade_proposed`,
  `trade_resolved`. Allowed in every phase except GAME_OVER (off-turn, jailed, raising funds,
  auctions). Open offer is dropped when a party goes bankrupt or the game ends.
- `scripts/ui/trade_panel.gd` - hotseat `TradePanel` (from/to pickers, cash spin boxes, deed and
  pardon check boxes, live problem line; Accept / Reject / Counter / Withdraw), wired in `main.gd`.
- Data: deck display names added to `data/board.json` `terms` (theme text only).
- Docs: README status, THEME_MAP terms, OPEN_QUESTIONS Q4 closed, Q13 / Q14 added.

## Verification (MEASURED)
```
godot --headless --path . --import                              # exit 0
godot --headless --path . --script res://tests/run_tests.gd     # 50 passed, 0 failed
godot --headless --path . --quit-after 30                       # main scene boots, no script errors
godot --headless --path . --export-debug "Android" build/imperium-astra-debug.apk   # signed, verified
```
New: `tests/test_trade.gd` (11 tests) - cash + deed swap, pardon transfer, mortgaged deed charges
10% to the Bank, interest affordability, reject no-op, not-owned deeds, buildings in set,
bankrupt players, counter-offer, any-time / one-offer-at-a-time, TradePanel hotseat flow.

## Open
- Q13: receiver's choice to lift a traded mortgage at once (placeholder: always keep + 10%).
- TradePanel layout not yet checked on a device (headless smoke test only).
