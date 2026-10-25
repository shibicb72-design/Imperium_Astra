# P3-THEME report: Imperium Astra visual theme pack

Data and presentation only. No rule code, `space_type`, prices, rents or card opcodes changed.

## What changed

- **Theme pack** `data/themes/imperium_astra/theme.json`, selected by `data/ui.json` `theme_path`:
  colors (navy panels, gold accent, ivory button text, alert red), button / panel StyleBox sizes,
  board chrome (group bar share, gold frame, corner tints and ASCII marks keyed by `space_type`
  name) and starfield settings. Font and touch sizes stay in `data/ui.json`.
- **`UiStyle`** loads the pack (`theme_data`, `color`, `theme_num`, `flat_box`). `make_theme()` now
  styles Button / OptionButton (normal, hover, pressed / toggled in gold, disabled, focus ring),
  PanelContainer, PopupMenu, LineEdit and Label colors, so the setup screen, HUD, holdings, trade,
  auction and debt panels all pick it up from the root theme. Title labels are gold, small labels
  muted. `card_style` uses theme panel colors. Every hard-coded color constant in `scripts/ui/` is
  gone (BoardView, Main, SetupPanel, Holdings, Trade, Auction, Debt).
- **`StarfieldBackground`** (new): vertical navy gradient plus a deterministic, resolution-independent
  starfield (no textures). Used behind the match screen and the setup screen.
- **`BoardView`**: taller group bars (24% of the cell, with a divider), labels drawn with a dark
  outline, Launch Bay / Brig / Anchorage / Report-to-Brig corners tinted and marked from theme data,
  gold board frame and inner rule, outlined house / Citadel pips, and the dice readout drawn as two
  ivory pip faces instead of "3 + 4" text.
- **README**: CI note now says it signs with the shared `android/debug.keystore`.
- **Docs**: THEME_MAP "Visual theme pack" section, OPEN_QUESTIONS Q20 (palette, font, corner icons,
  theme picker), `docs/ATTRIBUTION.md` (no third-party assets used).

## Touch targets

Button sizes still come from `UiStyle.button` / `picker` (`touch_target` 48). StyleBox content
margins don't shrink them; `test_ui` touch checks and the new `test_theme_applies_to_ui` pass.

## Tests

`tests/test_theme.gd` (8 tests): the theme path resolves; all 24 required colors are present and
valid; style sections exist; WCAG-style contrast ratios (body text >= 7:1 on background, panels
and cells; button, gold-title, alert and corner-label text >= 4.5:1; dice pips >= 7:1); no rules keys
in the pack; `make_theme` / `card_style` use theme colors and buttons stay >= 48; corners are
distinct and marked; the starfield is deterministic and ignores input.

Suite: **97 passed, 0 failed** (`godot --headless --path . --script res://tests/run_tests.gd`).
A throwaway headless draw smoke (live match, dice rolled, owned deeds, houses, a Citadel, a
selected space) drew the board with no script errors. The look itself hasn't been checked on a
device or in screenshots.

## Not done / open

- No custom display font: the Godot fallback font is used (Q20).
- The corner marks are ASCII placeholders (TODO: icons, CC0 only).
- Only one theme; there is no in-game theme picker (Q20).
