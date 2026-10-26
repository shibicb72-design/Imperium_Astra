# P5-FEEL report: feel hooks, explorer pieces and theme switching

Phase status at the Dig 4b tip. Rules stay classic (`docs/classic_monopoly_structure.md`). The Free
Parking jackpot stays off, and no price, rent, space type or card opcode changed in P5-FEEL.

**Not done yet:** the Fold prove (draft SC9, plus the live-device half of SC3 and SC4) and the B6
feel pass. This report claims no device or visual acceptance.

## What landed

| Step | Commit | What |
|---|---|---|
| Dig 1 (A1) | `9e87710` | Building-shortage auction rules. `BuildingLotAuction` is a non-deed `Auction` variant for one Bank house or hotel. `TurnController.start_building_auction(claims)` opens it when legal claimants outnumber Bank stock. Nothing calls it in play (Q10 below). |
| Dig 2 (A2, A3) | `d6a2f31` | `game_event` hooks `built_house`, `built_hotel`, `sold_house` and `sold_hotel` (one per street for a group sell), with ids and numbers only. BoardView Node2D piece contract: `PieceState` (position, lift, alpha) from the existing board math, plus `attach_piece` and `fade_out_piece`. |
| Dig 3a (A4) | `4a2b964` | Explicit pack registry `data/themes/index.json`. `UiStyle.set_theme(id)` / `reset_theme()` select a pack for the session only. `Main.select_theme(id)` re-themes the setup screen before match start. |
| Dig 3b (A5, A6, A8) | `002ea06` | Mandatory pack content overlay (`ContentOverlay`), applied once at match start by `GameSetup.new_game(seed, seats, content)`. Core never reads `UiStyle`. Hard-coded flavor in core logs goes through `board.term()`. Tests walk every registered pack and every pack file. |
| Dig 3c | `ec5544c` | `seat_names` overlay key, an optional `card_text` override, and a loud failure (`push_error`) for a pack with missing content. |
| Track B (B1-B5, Codex) | `70d64b0` | Original procedural explorer pieces (`SpacePiece`, Node2D), build / sell pips, the bankrupt fade, the Orbitron OFL display font, original vector corner icons, the setup theme picker and the minimal `astra_alt` pack. |
| Dig 4a | `d9af15c` | `ContentOverlay.apply()` skips empty strings and accepts canonical space keys only. Bank-owned deeds show the pack's `unowned` term. Build / sell lines say "builds 1 <term>". The deferred `line_shown` handler is a bound method, not a lambda, which removed the teardown ERROR noise. |
| Dig 4b | this commit | This report, the README status, THEME_MAP accuracy and the article convention, the Q21 timing note, a regression run and the debug APK export. Docs only: no code or data changed. |

## Product locks

- **Q10 stays `_placeholder`.** It is not decided what counts as "wanting" a building in any-time
  play (a claim window, who may claim, how bots declare interest). The rules side exists and is
  tested. Play stays first come, first served (`docs/OPEN_QUESTIONS.md` Q10).
- **Theme choice is session-only.** Picking a pack writes nothing to `res://` or `user://`, and
  `data/ui.json` `theme_path` stays the shipped default `imperium_astra` (`tests/test_theme_switch.gd`
  `test_selection_is_session_only`). The switch happens on the setup screen; `Main.select_theme`
  refuses once the match screen is built.
- **`astra_alt`** names its six seats "Pilot 1" to "Pilot 6" in `seat_pool` order. It has its own
  terms, space names, group names and dialogue. It omits the optional `card_text`, so its cards
  show the shared `cards.json` text with default-pack words (for example Launch Bay). This leak is
  accepted.
- **Pieces are Node2D** (`scripts/ui/space_piece.gd`) and follow BoardView's board math. No
  CharacterBody2D, AnimatableBody2D or physics is used.
- **Overlay strictness held.** `ContentOverlay.problems()`, `RULE_KEYS` / `RULE_FIELDS`, the
  stray-file check and the leak tests were not loosened; Dig 4a only tightened the key checks.
  Every registered pack passes `problems(..., complete=true)` (`tests/test_theme.gd`).

## What a pack is (and is not)

A pack holds words, colors, dialogue and fonts only:

- `theme.json`: colors, StyleBoxes, board chrome and the display font;
- `dialogue.json`;
- the `content.json` overlay: terms, space / group / seat names, and optional card text.

Every pack plays the same classic rules from one shared `data/rules.json`, with the shared
`board.json` and `cards.json`. Group colors are shared `board.json` data, not pack data.

Theme-specific rule variants and alternate event decks are a future extension, not the current
pack contract (draft SC10; listed as out of scope in the P5 draft). Today no pack can change a
price, rent, space type or card opcode. The rules load only from the shared files, and
`ContentOverlay.apply()` reads only its whitelisted keys and writes only text fields. The pack
tests also reject rules key names in pack files, and overlay keys that collide with them
(`tests/test_theme.gd`). They check key names, not values (see the leftovers below).

## Success criteria (P5 draft SC1-SC10)

| SC | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Headless 0 failed; shortage auction keeps stock >= 0, uncontested build stays first come, contested path per the Q10 placeholder; building-lot variant | Done (headless) | `tests/test_building_auction.gd` (10 tests) |
| 2 | `built_*` / `sold_*` / `bankrupt` events carry ids and numbers only | Done (headless) | `tests/test_feel_hooks.gd` |
| 3 | Piece art, not flat circles; space-by-space hops; Brig arc; headless snaps with no script errors | Headless half done; live half pending Fold | `test_feel_hooks.gd` `test_attached_piece_follows_and_snaps_headless`, `test_track_b.gd` `test_piece_motion_build_and_bankrupt_feedback` |
| 4 | Visible build pop; bankrupt fade within `bankrupt_fade_seconds` | Headless half done; live half and tuning pending Fold / B6 | The same Track B test. `bankrupt_fade_seconds` is 0.8, above the draft's suggested 0.45-0.6 s; left for B6 (Q21) |
| 5 | OFL / CC0 display font; non-ASCII corner marks; contrast for every pack | Done (headless) | Orbitron OFL and original vectors in `docs/ATTRIBUTION.md`; `test_theme.gd` `test_text_contrast` for each registered pack |
| 6 | At least two packs, setup picker, real overlay switch, one shared `rules.json` | Done (headless) | `test_theme_switch.gd`; `test_track_b.gd` `test_product_picker_switch_and_match`; `test_theme.gd` every-pack overlay and rules-key checks |
| 7 | No hard-coded space flavor in core logs | Done (headless) | `test_content_overlay.gd` `test_no_default_words_leak` (fixture pack with full card text); the `astra_alt` card-text leak is accepted |
| 8 | Holdings opaque and collapsible | Done (headless) | `test_ui.gd` `test_main_sections_opaque_and_collapsible` |
| 9 | Fold prove: screencaps of a piece hop, a build pop, Holdings, and the theme select with a name / term difference | **Pending (dig-order 10)** | Not run |
| 10 | Docs | Done | This report; OPEN_QUESTIONS Q10 / Q20 / Q21; README; THEME_MAP; ATTRIBUTION; superseded banner on `THEME_PICKER_DEFER_CHECK.md` (outside this repo, in `cc_gladius/promptsImperiumAstra/`) |

## Tests

- Track B tip `70d64b0`: 158 passed, 0 failed (Codex report), with teardown ERROR noise after the
  totals.
- Dig 4a tip `d9af15c`: 163 passed, 0 failed in two consecutive runs. Zero `ERROR:` lines, and
  only the 4 expected WARNINGs. Dig 4a added 5 tests: 4 in `test_content_overlay.gd`, 1 in
  `test_ui.gd`.
- Dig 4b tip: 163 passed, 0 failed in one full run. Zero `ERROR:` lines, and only the 4 expected
  WARNINGs: 3x "ContentOverlay: ignoring key" (`test_overlay_never_changes_rules_data`) and 1x
  `Main.select_theme` (`test_main_switch_before_match_start`). Dig 4b adds no tests, so the final
  Dig 4 count is 163.

## Teardown ERROR noise (Dig 4a §5)

Outcome: **clean**. At `70d64b0` the suite printed four ERROR pairs after the totals:
"Trying to call a lambda with an invalid instance." followed by "Error calling deferred method:
'<Class>::<anonymous lambda>': Instance is null." The cause: `Main` connected the banner's
`line_shown` signal to a lambda with `CONNECT_DEFERRED`. Calls queued before a test freed `Main`
later ran on a dead or reused instance, which is why the class names varied between runs. Dig 4a connects `_schedule_bot.unbind(1)` instead and adds `test_ui.gd`
`test_no_deferred_lambda_connections_in_ui`. Dig 4a did not touch `tests/run_tests.gd` or add any
error suppression. Its diff covers only `content_overlay.gd`, `turn_controller.gd`,
`board_view.gd`, `main.gd` and two test files.

## Review items: closed and left

Track B review (`002ea06`) nits 3-10, rechecked at the Dig 4a tip:

| Nit | Status |
|---|---|
| 3 Overlay fails open | Closed. Missing content fails loudly (`push_error`, dig 3c), and `apply()` skips empty strings (Dig 4a) |
| 4 THEME_MAP drift | Closed (Dig 4b) |
| 5 Teardown ERROR noise | Closed (Dig 4a) |
| 6 Article convention | Closed. Templates fixed in Dig 4a; convention documented in THEME_MAP in Dig 4b |
| 7 Generic UI words | Closed. The Bank-owned readout uses `unowned` (Dig 4a); the setup heading uses the pack's `players` term (`setup_panel.gd:146`) |
| 8 Overlay-code accuracy | Closed. Canonical space keys and the `short_name` header comment (Dig 4a) |
| 9 Test-coverage gaps | Partly closed. Dig 4a added strict key / section-type tests and bans `scripts/ui` in the core UI-free guard; dig 3c tests a pack with missing content. **Left:** see below |
| 10 Pack paths trusted verbatim | **Left** (informational) |

Deliberate leftovers:

- **Nit 9 remainder.**
  - Pardon-trade reachability: the pardon-card trade check in `test_no_default_words_leak` depends
    on the game state after 1500 steps. `Trade.validate` checks bankruptcy before held cards
    (`trade.gd:52` vs `:64-66`), so the routed "... not held." line is not guaranteed to run.
  - Presentation-only scan holes: `test_every_pack_file_presentation_only` lists the pack folder
    flat and checks `.json` files only. A malformed pack JSON loads as `{}`. The ban lists omit
    some `rules.json` keys (`starting_cash`, `go_salary`, `jail_index`).
  - Overlay-then-plain match: no test plays an overlay match followed by a plain match. No cache
    exists, so this would only be a regression guard.
  - The leak run asserts that the pack's seat names appear in the log. Other fixture terms are
    checked only through `board.term()`.
- **Nit 10.** `theme_path`, `dialogue_path` and `content_path` are used without a pack-folder
  prefix check. That is safe while packs are shipped `res://` data, chosen by id from the explicit
  index. Revisit it if packs ever become user-downloadable.
- Track B review nit 11 (process) and Dig 4 prompt-review nit 15 (B6 has no slot in the dig
  order) are for the EL.

## Not done / next

- **Fold prove (dig-order 10).** Install the P5 APK on the Fold. Take screencaps of a piece hop, a
  build pop, Holdings opaque / collapsible, and the setup theme picker showing both packs with a
  visible name / term difference. Q20 polish adds: the home-screen launcher icon (adaptive mask),
  both packs' palettes on the setup screen and the board, and a check that the `astra_alt` accent
  `#5fe0bd` and seat 1 `#4fc3f7` read as different colours.
- **B6 feel pass on the Fold (Codex).** Tune `pawn_*`, `dice_*`, `building_pop_*` and
  `bankrupt_fade_seconds` (Q21). Not done; the values are unchanged.
- **Still-open product points:** Q10 claim trigger, Q1 default seat names, Q20 device art review
  (the palette pass landed in the Q20 polish dig), Q7 icon sign-off, Q2 currency.

## Export

Dig 4b exported a debug APK in its own session to `build/imperium-astra-debug.apk`, signed and
verified with the shared debug keystore. The file is local only and not committed. It was not
installed on any device.
