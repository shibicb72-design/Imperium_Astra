# CLAUDE.md
Read README.md, docs/classic_monopoly_structure.md (rules source) and docs/THEME_MAP.md first.

Token limits are mandatory:
- Steps of at most ~30-60 turns, each in a fresh `claude -p` session; Sonnet runs with `--max-budget-usd 2.50`.
- No Sonnet helper subagents; subagents are Haiku only (log reading, bulk renames, Explore).
- Read files by line range (Grep, then Read with offset/limit); never read a file over 200 lines whole.
- Pin every model explicitly (`--model opus|sonnet|haiku`).
- Never push, merge, create release keys, or touch files outside this repo. Never commit keystores or APKs.

RULES FIDELITY:
- Classic rules only, per docs/classic_monopoly_structure.md. Free Parking jackpot stays OFF.
- Rules live in scripts/core/ (pure RefCounted types + static `Rules`), never in UI code.
- All tunable numbers in res://data/*.json. A theme swap edits only display_name, group colors and card text;
  never space_type, prices, rents or card opcodes.
- Undecided product points go to docs/OPEN_QUESTIONS.md; placeholders are marked `_placeholder` / `TODO`.
- Every rule change gets a headless test in tests/ (`godot --headless --path . --script res://tests/run_tests.gd`).

CROSS-PLATFORM READINESS (Android ships first; desktop, iOS and web later):
- Input: UI buttons (touch/mouse) and InputMap actions only (roll_dice, buy_property, end_turn). Never read raw touch events.
- UI uses anchors/containers and scales for any aspect ratio and DPI (landscape side-by-side, portrait stacked).
- Platform-specific code goes behind scripts/platform/ with OS.get_name() checks and no-op fallbacks; saves use user://.
- Renderer: Mobile. Keep export_presets.cfg Android-only for now; nothing in code may assume Android.


MODULAR BACKBONE (Shibi Oct 24 2026): rules engine others theme off of; Auction/Build/Mortgage/Bankruptcy/Trade as separate modules; theme packs = data only.
When EL dig says push: commit on main and git push origin main (non-force). Never force-push.

