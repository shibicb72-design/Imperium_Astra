# Imperium Astra

A property-trading board game with the classic Hasbro rules structure (C1009 / G0009, see
`docs/classic_monopoly_structure.md`) and a Roman space-empire theme. Godot 4.7.2, GDScript.
No trademarked names, art or logos are used; the theme is a pure data swap (`docs/THEME_MAP.md`).

## Status (P1 to P5-FEEL)

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
- Building-shortage auction (P5-FEEL dig 1): `building_lot_auction.gd` is the non-deed `Auction`
  variant for one Bank house/hotel; `TurnController.start_building_auction(claims)` runs it when
  legal claimants outnumber Bank stock (winner pays the bid, builds on their claimed street).
  Not wired into play yet: how players claim a building is OPEN_QUESTIONS Q10 `_placeholder`, so
  building stays first come, first served.
- P2 bots (`bot.gd`, `data/bot.json`): optional AI seats (`Player.is_bot`). `Bot.decide()` only
  reads the match and returns one action; `TurnController.bot_step()` applies it through the same
  public actions people use, so bots follow every rule check. The UI plays bot steps on a timer
  (`data/ui.json` `bot_step_seconds`). Heuristics: buy / bid / build only while $200 stays, bid up
  to list price, even-build the cheapest street, mortgage only to pay debts. Trades (`bot_trade.gd`,
  P3): score deeds, cash and color sets; accept fair deals, counter once with a cash fix, refuse to
  hand over a monopoly; propose at most one set-completing or monopoly-blocking deal per turn. Seats: `GameSetup.seats(humans, bots)` or
  `GameSetup.seats_for(bot_flags)` in seat order (2-6 total).
- P2 setup (`scripts/ui/setup_panel.gd`): before each match a setup screen picks 2, 3 or 4 seats
  and Human/Bot per seat (default seat 1 Human, seat 2 Bot), then Start opens the board. Start
  needs at least one Human (`data/ui.json` `setup_*`); the last choice is kept in
  `user://setup.cfg`.
- P4 demo motion and dialogue (`docs/IMPERIUM_ASTRA_P4_DEMO_REPORT.md`): dice tumble, pawns hop
  space by space (arc to the Brig), panels fade, and an event banner over the board center reads
  out rolls, landings, rent, tax, cards, jail, trades and bankruptcy. Lines are theme data
  (`data/themes/<id>/dialogue.json`); the rules only emit `TurnController.game_event` (ids and
  numbers, no text). Timings in `data/ui.json`.
- P5-FEEL feel and theme switching (`docs/IMPERIUM_ASTRA_P5_FEEL_REPORT.md`). Build / sell
  `game_event` hooks plus a Node2D piece contract (dig 2), with original explorer pieces that hop,
  pop on builds and fade on bankruptcy (Track B). Theme packs are registered in
  `data/themes/index.json` (`imperium_astra`, `astra_alt`) and picked on the setup screen for the
  current session only (dig 3a, Track B). Each pack's mandatory `content.json` overlay supplies
  terms and space, group and seat names at match start; card text is optional (digs 3b-3c). Titles
  use the Orbitron OFL display font (`docs/ATTRIBUTION.md`). Dig 4 fixed overlay edge cases and the
  test teardown ERROR noise, and wrote the phase docs. Still to do: the Fold prove and the B6
  device timing pass.
- Play mode: **local hotseat, 2-4 seats** (one device). The Holdings panel lets
  any commander build / sell / mortgage at any time, and the Trade panel lets any two active
  commanders trade at any time (also off-turn, in the Brig, or while raising funds), as the
  official rules allow.
- Who may act (P1-PHASE, `tests/test_phase.gd`): build / sell / mortgage / unmortgage / trade
  are open to every active commander in every phase but game over, on or off turn and in the
  Brig; jailed commanders also bid in auctions and collect rent. Only the current player rolls,
  pays the jail fine or uses a pardon (before rolling), buys / declines, and ends the turn.

## Run on desktop

1. Open the folder in Godot 4.7.2 and press Play, or run `godot --path .`
2. Controls (board-first, P5-FEEL Dig 5): tap the dice in the board center to roll; once your piece
   lands, a floating panel offers Claim / Skip / Action / End Turn (in the Brig: Pay fine / Use
   pardon / Action before the roll). Action opens Holdings / Trade / Log (Dig 5a1: in a side column,
   with Done to close; auctions, debts and trade answers use it too). Keys: Space = roll, B = claim,
   E = end turn, each only when the matching control is on screen.

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
It signs with the shared debug keystore `android/debug.keystore` (the same one used for local
debug exports; standard `androiddebugkey` / `android` debug credentials). No release keys are
committed or created.
