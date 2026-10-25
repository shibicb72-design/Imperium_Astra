# Imperium Astra P1-UI Report (hotseat phone UI pass)

**Date:** 2026-10-24
**Tip before:** `aaa88f3` P1-PHASE: any-time actions and jail

Layout and UX only, aimed at a ~1080x2400 phone (folded Fold). No theme art, no bots, and no rule
changes: every button calls the existing `TurnController` / module methods.

## Scaling (the main phone problem)
The old setup (stretch `canvas_items`, base 1280x720) shrank everything in portrait: a 64 px
button was about 20 dp on a 420 dpi phone. Now:
- `project.godot`: stretch mode back to the default `disabled`.
- `scripts/platform/display_scale.gd` (`DisplayScale`): on Android/iOS sets
  `content_scale_factor = dpi / 160` (clamped 1..4), so one canvas unit is about 1 dp in either
  orientation. Desktop and web are a no-op (1.0), see Q16. It also returns safe-area insets
  (cutouts / system bars), which the main screen adds to its margins.
- `data/ui.json` holds the presentation sizes: `touch_target` 48, font roles, margins, board
  share, trade cash steps, log length. `scripts/ui/ui_style.gd` (`UiStyle`) builds touch-sized
  buttons, labels, pickers and card styles from it, plus a root theme with bigger popup rows.

## Main screen (`scripts/ui/main.gd`)
- Portrait: board on top, controls below. Landscape: side by side. The board takes the full
  short side, capped at `board_max_share_*` of the long side (48% portrait, 58% landscape) so
  the controls keep room; an unfolded Fold gets a ~530 dp board plus a ~380 dp column.
- Header: turn line (with jail state), one colored chip per commander (`> ` marks the current
  one, cash), a status line (2 lines).
- Turn actions in a 2-column grid showing only what applies: Roll (or "Roll for doubles"),
  Claim <short name> $price / Pass, Pay fine / Use pardon card (jailed, before rolling),
  End Turn. Disabled only when it applies but can't be afforded.
- Auction and Debt banners pinned under the actions (not in a scroll), so bids, Drop Out, Pay
  and Declare Bankruptcy are always on screen.
- Sections behind three 48 dp tabs: **Holdings** (scroll list), **Trade**, **Log** (newest
  first). A new trade offer switches to Trade and the tab reads "Trade (offer)". A new debt
  switches to Holdings with the debtor as actor.

## Panels
- **HoldingsPanel**: "Acting:" picker, cash and holdings count, one card per deed with the group
  color on the left edge; Build / Sell / Mortgage / Unmortgage buttons (enable state from the
  modules, as before), plus "Sell all buildings" per group.
- **TradePanel**: pickers, a scrolling body (cash field with -100/-10/+10/+100 buttons, deed and
  pardon check boxes, all 48 dp), then the problem line and the action row **pinned below the
  scroll**: Propose / Clear, Send counter / Back, or Accept / Reject / Counter / Withdraw.
- **AuctionPanel / DebtPanel**: compact banners (PanelContainer) with all buttons in one wrapping
  row; Drop Out and Pay show whose action it is.
- Buttons in scroll lists use `MOUSE_FILTER_PASS`, so a drag that starts on a button still
  scrolls the list.

## BoardView
- Cells show the new `short_name` (theme data in `data/board.json`, falls back to
  `display_name`; see THEME_MAP). The font is fitted so every word fits the cell (up to 3 lines).
- Tap a space to select it (gold outline): the empty board center shows the full name, group,
  price, owner, buildings, mortgage state, rent table and build / mortgage values. Tap again
  to clear. Input is `InputEventMouseButton` (Godot emulates it from touch); no raw touch.
- The current commander's space has an outline in their color. The center title comes from
  `application/config/name` instead of a hard-coded string.
- UI wording that was hard-coded ("Brig", "Claim", "Pardon", "the Bank") now comes from
  `board.json` `terms`.

## Core touch (data only)
`Space.short_name` plus one line in `Board._space_from_dict`. No rule logic changed.

## Review fixes (Haiku code review)
- Portrait: the board also shrinks by the control column's minimum height (floor 160 dp), and
  layout re-runs on every refresh and tab switch, so the pinned trade row and banners stay on
  screen on short phones.
- Safe-area insets are re-read on every layout (rotation moves the cutout).
- Trade draft cash is clamped to the commander's current cash when the field is rebuilt.
- No Build button on a deed that already has a hotel; a dead theme constant was removed.
- Not fixed (pre-existing, core): `TurnController` log text still hard-codes "the Brig" /
  "the Bank"; next core pass should use `board.term("jail" / "bank")`.

## Tests
New `tests/test_ui.gd` (10 tests, including a fit check: with a trade offer open on 411x731,
360x640 and 411x880 portrait, board plus control column fit, and the trade answers, banners and
turn actions are not inside any scroll container): DisplayScale factors; board grid round trip; tap hit-testing
and details; board sizing in portrait / landscape / unfolded; auction, debt, holdings and trade
panels instantiate, show the right buttons, call the modules, and keep every button at least
`touch_target`; trade answers pinned outside the scroll; main scene smoke test (portrait to
claim to auction banner to landscape to log). `test_trade.gd::test_trade_panel_hotseat_flow`
now finds Accept in the pinned action row.

## Verification (MEASURED)
```
godot --headless --path . --import                              # ok
godot --headless --path . --script res://tests/run_tests.gd     # 70 passed, 0 failed
godot --headless --path . --quit-after 120                      # main scene runs, no errors
godot --headless --path . --export-debug "Android" build/imperium-astra-debug.apk   # signed, verified
```
Not verified on a device: real dp sizes depend on Android's reported dpi; check on the Fold
(cover and inner screen, both orientations) before the next pass.

## Open points
- Q16 (new): UI scale on desktop / web.
- Q17 (new): hotseat privacy (every commander sees everything).
- Q12 hotseat "any time" UX stays open.
