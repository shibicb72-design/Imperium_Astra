# P4-HOLDINGS-UI — Fold bugfix report

Base: 94eebf7 (Fold7 cover-screen playtest).

## Root causes (verified in code)
1. **"Board text through the list"**: the theme colors are opaque (`panel` `#10162e`), but the tab
   section area had no background of its own; Holdings/Log scrolls sat straight on the starfield.
   The visible "bleed" in the screenshot was the `Acting:` label in `HoldingsPanel`:
   `UiStyle.label()` turns on `AUTOWRAP_WORD_SMART`, and a wrapping label in an `HBoxContainer`
   has ~0 minimum width, so it got squeezed to one letter per line ("A c t i n g :"). That tall
   label also stretched the actor `OptionButton` into a big box that looked like an open list.
2. **List won't go away**: the three tabs shared a `ButtonGroup`, which always keeps one button
   pressed, and `show_section()` could only switch sections, never close them.

## Fix
- `scripts/ui/holdings_panel.gd`: `Acting:` label has autowrap off and is vertically
  shrink-centered, and so is the picker, so the picker is one touch row tall again. New
  `close_picker()` hides the dropdown popup.
- `scripts/ui/main.gd`: sections now sit inside a `PanelContainer` (`_section_holder`) with an
  opaque `UiStyle.section_style()` backing and `clip_contents`. The `ButtonGroup` is gone. Tabs
  call `toggle_tab()`: tapping the open tab runs `collapse_sections()`, which hides the area,
  deselects every tab, closes the actor dropdown and re-runs layout. Any other tab opens its
  section. `show_section()` always opens, so the debt flow (`_on_debt_started`) and incoming
  trade offers still force their section open.
- `scripts/ui/ui_style.gd`: `section_style()` is built only from theme data (`colors.panel`,
  `colors.panel_border`, `panel.*` sizes), so theme packs stay data-only.

## Tests
- New `tests/test_ui.gd::test_main_sections_opaque_and_collapsible`: checks the backing is
  opaque, the area clips, and `Acting:` doesn't wrap; collapse on re-tap with no tab selected;
  tab switching; trade collapse; debt force-opens Holdings with the debtor as the actor.
- Headless run: 119 passed, 0 failed. At exit, Godot logs `Trying to call a lambda with an
  invalid instance` (deferred `HFlowContainer` lambda). It still appears with the new test
  skipped (118 passed), so the new test doesn't cause it. This repo has no deferred
  HFlowContainer lambda, so it looks like teardown noise from freed nodes. Not compared against
  94eebf7.
- `--export-debug Android` → `build/imperium-astra-debug.apk` (export DONE, exit 0).

## Notes / open
- When sections collapse, the side column gets more room in landscape. In portrait the board's
  size is still capped by `board_max_share_portrait` (data/ui.json), so the board doesn't grow
  past that cap. Raising the cap when collapsed would be a product call and isn't done here.
- Not yet checked on the Fold7 device; the fix is based on the screenshot and code reading.
