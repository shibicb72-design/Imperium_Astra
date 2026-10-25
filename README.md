# Imperium Astra

A property-trading board game with the classic Hasbro rules structure (C1009 / G0009, see
`docs/classic_monopoly_structure.md`) and a Roman space-empire theme. Godot 4.7.2, GDScript.
No trademarked names, art or logos are used; the theme is a pure data swap (`docs/THEME_MAP.md`).

## Status (P1)

- Rules core (`scripts/core/`): Board, Space, PropertyDeed, Player, Bank, Dice, CardDeck, Card,
  TurnController, pure `Rules` functions. All numbers live in `data/*.json`.
- P0: roll/move, $200 GO salary (pass or land), buy, rent (streets with color-set double,
  houses/hotel table, jump gates, utilities), taxes, all 32 cards, jail (three doubles, Go To Jail,
  card; leave by fine, pardon card, doubles, or third-turn fine), Free Parking pays nothing.
- P1 rule modules, one file each so they can be tuned or swapped on their own:
  - `auction.gd` - declined deeds are auctioned (bids from $10, $1 steps, any active player).
  - `building.gd` - houses/hotels: full color set, build and sell evenly, 32/12 Bank stock,
    hotel trades in 4 houses, sell back at half.
  - `mortgage.gd` - mortgage value out, value + 10% to lift, no buildings in the set, no rent.
  - `bankruptcy.gd` - unpaid debts are queued; the debtor raises funds or, only if even selling
    and mortgaging everything cannot cover it, goes bankrupt to the player (all assets) or to
    the Bank (deeds auctioned). Last player standing wins.
  - `trade.gd` - private trades: cash, unimproved deeds (mortgaged or not) and pardon cards;
    propose / accept / reject / counter / withdraw, one open offer at a time. No deed whose
    color set has buildings. The receiver of a mortgaged deed pays the Bank 10% of its mortgage
    value at once and keeps the mortgage; a trade whose interest a side cannot pay is refused.
  - `TurnController` only sequences them (debts -> auctions -> buy decision -> end of landing).
- Not yet: building-shortage auctions. See `docs/OPEN_QUESTIONS.md`.
- P2 bots (`bot.gd`, `data/bot.json`): optional AI seats (`Player.is_bot`). `Bot.decide()` only
  reads the match and returns one action; `TurnController.bot_step()` applies it through the same
  public actions people use, so bots follow every rule check. The UI plays bot steps on a timer
  (`data/ui.json` `bot_step_seconds`). Heuristics: buy / bid / build only while $200 stays, bid up
  to list price, even-build the cheapest street, mortgage only to pay debts, refuse all trades but
  clearly +EV cash-for-deed offers. Seats: `GameSetup.seats(humans, bots)` (2-6 total).
- Play mode: **2-player local hotseat** (default: Commander 1 human, Commander 2 bot; one device). The Holdings panel lets
  any commander build / sell / mortgage at any time, and the Trade panel lets any two active
  commanders trade at any time (also off-turn, in the Brig, or while raising funds), as the
  official rules allow.
- Who may act (P1-PHASE, `tests/test_phase.gd`): build / sell / mortgage / unmortgage / trade
  are open to every active commander in every phase but game over, on or off turn and in the
  Brig; jailed commanders also bid in auctions and collect rent. Only the current player rolls,
  pays the jail fine or uses a pardon (before rolling), buys / declines, and ends the turn.

## Run on desktop

1. Open the folder in Godot 4.7.2 and press Play, or run `godot --path .`
2. Controls: buttons on the right (or below in portrait). Keys: Space = roll, B = claim, E = end turn.

## Tests (headless)

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

The runner runs every `test_*` method in `tests/test_*.gd` and exits 1 on any failure.

## Export Android

Requires Godot 4.7.2 export templates, Android SDK (build-tools 36.0.0, platform 36), JDK 17 and a
debug keystore configured in Editor Settings.

```
mkdir -p build
godot --headless --path . --export-debug "Android" build/imperium-astra-debug.apk
```

CI (`.github/workflows/android.yml`) does the same on every push to `main` and uploads the APK.
It creates a throwaway debug keystore per run; no keys are committed.
