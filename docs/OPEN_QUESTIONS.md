# Open questions

Undecided product points. Placeholders are marked `_placeholder` / `TODO` in data.

| # | Question | Current placeholder |
|---|---|---|
| Q1 | Player setup: how many seats, names, colors, AI or human? | `data/rules.json` `local_players`: 2 hotseat "Commander 1/2" (`_placeholder: true`) |
| Q2 | Currency name/symbol for the theme (credits, denarii, ...)? | `$` in UI and card text |
| Q3 | Auction UI flow (official: bids from $10, $1 steps, any player). | Declining leaves the deed with the Bank (stub in `Bank.auction`) |
| Q4 | Building, mortgage, trade and bankruptcy UI (rules exist in the md; P0 has none). | Not implemented; cash may go negative |
| Q5 | Rent "ask" window (owner must ask before next roll). Keep auto-ask for local play? | Auto-ask (rent always collected) |
| Q6 | Card text uses the post-2008 US card set (COMMUNITY/SECONDARY source). Confirm the set. | `data/cards.json` |
| Q7 | Package id `com.shibibabu.imperiumastra` and app icon art. | Placeholder `icon.svg` |
| Q8 | Edition rename Oriental Ave -> Rhode Island Ave (2025 refresh) has no rule impact; themed name used. | n/a |
