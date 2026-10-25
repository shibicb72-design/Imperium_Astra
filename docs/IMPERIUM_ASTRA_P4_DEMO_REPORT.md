# P4-DEMO report: motion, dialogue and demo polish

Presentation only. No board rule changed; the rules core gained one additive presentation hook.

## Architecture

- `TurnController.game_event(kind, info)` (core): emitted next to the existing log line for each
  key event. `info` holds ids and numbers only (player, space, amount, dice, deck id, card text
  from `data/cards.json`), never theme strings. It changes no state. Kinds: `rolled`, `moved`,
  `passed_go`, `landed_unowned`, `bought`, `rent`, `tax`, `card`, `jailed`, `released`,
  `auction_won`, `auction_unsold`, `bankrupt`, `trade_proposed` / `_accepted` / `_rejected` /
  `_countered` / `_withdrawn`, `game_over`.
- `scripts/ui/board_view.gd`: its own animation queue, played in order: `queue_dice`,
  `queue_move`, `queue_jump`, `queue_call`. Tokens are drawn at their shown positions, which catch
  up with the game; when the queue drains they snap to the game state. `animate` is off outside
  the scene tree, so headless tests apply everything at once.
- `scripts/ui/dialogue_lines.gd` (`DialogueLines`): loads the theme's `dialogue_path` and maps a
  `game_event` to a line key plus placeholders (`describe`), then fills a random variant
  (`event_line`). Keys missing from the theme fall back to plain English (`FALLBACK`).
- `scripts/ui/dialogue_banner.gd` (`DialogueBanner`): the banner over the lower board center.
  `push`, `queue_size`, `current_text`, `is_showing`, `time_left`, `dismiss` (also a tap), `clear`,
  `advance(delta)`. Lines auto-dismiss; the queue is capped (oldest waiting line dropped).
- `scripts/ui/ui_fx.gd` (`UiFx`): `set_shown` (fade in/out), `fade_in`, `pulse`. They are
  instant outside the tree.
- `scripts/ui/main.gd`: routes `game_event` into the board queue and puts each banner line
  *behind* the motion (`queue_call`), so "X pays tribute" appears when the pawn lands.

## What animates

| Thing | Motion | Tunable (`data/ui.json`) |
|---|---|---|
| Dice | faces flicker and rattle, then settle on the real roll | `dice_roll_seconds` 0.55 |
| Pawn move | hops space by space along the track (lift, shadow, slight grow); backward card moves hop backward; long card advances speed up | `pawn_step_seconds` 0.14, `pawn_move_max_seconds` 1.8, `pawn_hop_height` 0.3 |
| Sent to the Brig | one high arc straight to the Brig | `pawn_jump_seconds` 0.6 |
| Current-space highlight | follows the shown pawn, not the teleported game state | n/a |
| Auction / debt banners | fade in / out | `panel_fade_seconds` 0.18 |
| Trade | the section fades in when switched to; the offer body fades when an offer opens or closes | `panel_fade_seconds` |
| Setup screen, match screen | fade in | `screen_fade_seconds` 0.35 |
| Turn label, new banner line | brief brighten-and-settle pulse | `pulse_seconds` 0.35 |
| Event banner | fades in, auto-dismisses, tap to skip | `banner_seconds` 2.2, `banner_backlog_seconds` 1.2, `banner_max_queue` 4 |

Turn buttons hide while dice and pawns are moving, then come back (Space/B/E keys are ignored
meanwhile). All buttons stay at least `touch_target` 48 (dp). Not done (optional): house/hotel
pop and bankrupt fade.

## Dialogue keys

`data/themes/imperium_astra/dialogue.json`, linked from `theme.json` `dialogue_path`. Each key is
a list of variants with `{name} {other} {owner} {space} {amount} {price} {text} {deck} {d1} {d2}
{total}` placeholders:

`match_start`, `roll`, `roll_bot` (the bot announcing its move: "Commander 2's legion advances:
7!"), `doubles`, `passed_go`, `landed_unowned`, `bought`, `auction_won`, `auction_unsold`,
`rent_paid`, `tax`, `card_chance`, `card_community` (both show the card's own text), `jail_enter`,
`jail_exit_fine`, `jail_exit_pardon`, `jail_exit_doubles`, `jail_exit_forced`, `bankrupt`,
`trade_proposed`, `trade_accepted`, `trade_rejected`, `trade_countered`, `trade_withdrawn`,
`game_over`.

A new theme copies the file and rewrites only the strings.

## Demo polish

- Turn indicator: `> Commander 2's turn  [Bot]` in the player's color, pulsing on each new turn
  (`[Human]` for people; Brig shown).
- Player chips always on screen: cash plus holdings (`$1340 | 3 deeds, 2 bld, Pardon card`).
- Bots auto-play: each bot step waits for the board to finish moving and for the banner backlog to
  drop to `bot_wait_banner_queue` (1), then `bot_step_seconds` (now 0.7; was 0.4). Auction bids
  use `bot_auction_step_seconds` 0.1, because bots raise in $1 steps. Rules never wait on the
  banner: it always drains on its own timer.
- Start goes straight into the match: the screen fades in and an opening banner names who moves
  first.

## How to demo on the Fold (1 human + 1-2 bots)

1. Install `build/imperium-astra-debug.apk` (or the CI artifact) and open it. Either fold state
   works: folded uses portrait (board on top), unfolded landscape puts the board beside the
   controls.
2. On setup pick 3 seats: seat 1 Human, seats 2-3 Bot (or 2 seats: Human + Bot). Tap Start.
3. The opening banner names who goes first. On your turn tap Roll Dice. The dice tumble, your
   pawn hops to its space and the banner reads out the landing. Then Claim, Pass (to auction) or
   End Turn.
4. Bot turns play themselves: "legion advances" banner, dice, pawn hops, buy/rent lines. Tap
   the banner to skip a line. Use the Trade tab to offer a bot a deal; its answer appears as a
   banner.

## Tests

`tests/test_demo.gd` (13 tests): dialogue file has every key and the fallback does too, all
placeholders fill, missing file and unknown keys, `game_event` order and info for roll / move /
landing / buy / tax / jail / card / rent / release / trade, bot roll uses `roll_bot`, the
banner queue API (auto and tap dismiss, backlog time, cap, emptied signal), the BoardView
animation queue driven by `advance()` (dice settle, hop, jump, backward, long-move cap, callbacks
in order, drain snap), instant mode, `UiFx` outside the tree, and Main wiring (opening banner,
chips, turn label). A throwaway in-tree all-bot smoke run (`build/demo_smoke.gd`, not committed)
played a live match with real tweens and timers: banners flowed, pawns animated and bots kept
playing with no script errors.

Open tuning points: `docs/OPEN_QUESTIONS.md` Q21 (timings) and Q22 (dialogue copy).
