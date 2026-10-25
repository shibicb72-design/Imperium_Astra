# Imperium Astra P2-SETUP report: seat selection screen

## What was built
- `scripts/ui/setup_panel.gd` (`SetupPanel`): full-screen setup shown before a match. Seat count
  buttons 2 / 3 / 4, one row per seat (name and color from `rules.json` `seat_pool`) with a
  Human/Bot toggle, and Start. All buttons use `UiStyle.button` (>= `touch_target` 48 dp after
  `DisplayScale`); margins follow safe-area insets; seat rows scroll so Start stays on screen in
  landscape. Emits `start_requested(seats)`; holds no rules.
- `GameSetup.seats_for(bot_flags)`: seat list in seat order (any human/bot mix, 2-6 seats).
  `GameSetup.seats(humans, bots)` now builds on it (unchanged behavior).
- `Main`: `_ready` shows the setup first when no match was injected (`show_setup`); Start calls
  `begin_match(seats)`, which builds the match, picks the start player, stores it on the
  `GameState` autoload and opens the board screen. Tests that inject a controller are unchanged.
- `data/ui.json` `setup_*`: offered counts `[2, 3, 4]`, default count 2, per-seat defaults
  (seat 1 Human, others Bot), `setup_min_humans` 1.
- Last choice saved to `user://setup.cfg` (ConfigFile) on Start and restored at launch; bad or
  out-of-range saved values are ignored.

## Product calls (OPEN_QUESTIONS Q19, now resolved; see notes there)
- At least one Human to start (Start disabled with a hint otherwise). All-bot matches stay legal
  in `GameSetup` so headless soak tests keep working. TODO: confirm.
- 5-6 seats (rules allow) are not offered on the screen; add them to `setup_seat_counts`.
- Names and colors are still Q1 placeholders.

## Tests (tests/test_setup.gd, 6 tests)
`seats_for` keeps seat order and min/max limits (all-bot allowed in core); panel defaults (2 seats,
Human + Bot, touch sizes, hidden seats 3-4); count changes and toggles; Start emits seats and is
refused with zero humans; choice persists and bad saved data is ignored; Main setup -> Start
builds a 3-seat human/bot/human match and removes the setup screen.

## Verification (actual output)
- `godot --headless --path . --import`: clean.
- `godot --headless --path . --script res://tests/run_tests.gd`: **89 passed, 0 failed**.
