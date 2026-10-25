# Open questions

Undecided product points. Placeholders are marked `_placeholder` / `TODO` in data.

| # | Question | Current placeholder |
|---|---|---|
| Q1 | Player setup: how many seats, names, colors, AI or human? | `data/rules.json` `local_players`: 2 hotseat "Commander 1/2" (`_placeholder: true`) |
| Q2 | Currency name/symbol for the theme (credits, denarii, ...)? | `$` in UI and card text |
| Q3 | Auction flow. Official: bids from $10, $1 steps, any player; open outcry isn't specified for digital play. | `Auction`: seat order starting left of the current player; each bidder raises or drops out for good; ends when only the high bidder is left. Quick-bid buttons +1/+10/+50/+100 (`data/ui.json`) |
| Q4 | ~~Trade UI and rules module~~ **Resolved (P1-TRD):** `Trade` module + `TradePanel`; any time, any phase except game over; one open offer at a time. | n/a |
| Q13 | Trading a mortgaged deed: official lets the receiver lift it at once (value + 10%) **or** pay 10% now and keep it. Who chooses, and how is it shown? | Placeholder in `Trade.accept`: always keeps the mortgage and charges 10% (TODO). The receiver can lift it later in Holdings for value + 10%. **EL default (P1-PHASE): keep as is, pending Shibi override.** |
| Q14 | Trades that leave a side unable to pay the 10% transfer interest. | Refused up front by `Trade.validate` (no debt is created) (INFERRED). **EL default (P1-PHASE): refuse, no debt conversion, pending Shibi override.** |
| Q15 | A commander who owes a debt can still build, unmortgage or trade cash away before paying (classic rules do not forbid it), which could shrink what a player creditor inherits on bankruptcy. Restrict while in debt? | No restriction (any-time rules apply to debtors too) (INFERRED) |
| Q9 | Bankruptcy to a player: official lets the creditor lift each inherited mortgage at once (value + 10%) **or** pay 10% now and keep it. Who chooses, and how is it shown? | Placeholder in `Bankruptcy.settle_to_player`: always keeps the mortgage and charges 10% (TODO) |
| Q10 | Building shortage: official auctions the last houses/hotels when several players want them. | Not implemented; first come, first served |
| Q11 | Several debts from one card (e.g. pay each player) and the debtor goes bankrupt partway. | Debts are settled oldest first; bankruptcy goes to the creditor being paid then, later debts of that player are dropped (INFERRED) |
| Q12 | Hotseat "any time" actions: any commander can pick themselves in the Holdings panel at any moment. OK, or limit to own turn + debts? | Any commander, any phase except game over; jail never blocks them. Rules side confirmed and tested in P1-PHASE (`tests/test_phase.gd`); the hotseat UX question stays open |
| Q16 | UI scale off mobile: desktop and web stay at 1.0 (one canvas unit = one pixel). Scale by monitor DPI / browser devicePixelRatio later? | `DisplayScale` scales only Android/iOS (dpi / 160); no-op elsewhere (P1-UI) |
| Q17 | Hotseat privacy: everyone sees every commander's cash and offers on one screen. Hide the receiver's view / add a "pass the device" screen? | Everything visible (P1-UI) |
| Q5 | Rent "ask" window (owner must ask before next roll). Keep auto-ask for local play? | Auto-ask (rent always collected) |
| Q6 | Card text uses the post-2008 US card set (COMMUNITY/SECONDARY source). Confirm the set. | `data/cards.json` |
| Q7 | Package id `com.shibibabu.imperiumastra` and app icon art. | Placeholder `icon.svg` |
| Q8 | Edition rename Oriental Ave -> Rhode Island Ave (2025 refresh) has no rule impact; themed name used. | n/a |
