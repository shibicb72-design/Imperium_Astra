# Theme map: classic structure -> Imperium Astra

The theme is a data swap only. `space_type`, prices, rents, tax amounts and card opcodes in
`data/*.json` are the classic US values (see `classic_monopoly_structure.md`) and stay fixed.
Only `display_name`, group `display_name` / `color`, and card `text` are theme data.
Classic names appear here only, for traceability; they are not shipped in game data.

## Special spaces

| Index | Classic | Imperium Astra |
|---:|---|---|
| 0 | GO | Launch Bay |
| 2, 17, 33 | Community Chest | Senate Dispatch |
| 7, 22, 36 | Chance | Mission Brief |
| 4 | Income Tax ($200) | Imperial Levy |
| 38 | Luxury Tax ($100) | Luxuria Tariff |
| 10 | Jail / Just Visiting | The Brig (Just Visiting / In the Brig) |
| 20 | Free Parking | Deep Space Anchorage |
| 30 | Go To Jail | Report to the Brig |

## Railroads -> Jump Gates, Utilities -> Plants

| Index | Classic | Imperium Astra |
|---:|---|---|
| 5 | Reading Railroad | Porta Mercurii Jump Gate |
| 15 | Pennsylvania Railroad | Porta Martis Jump Gate |
| 25 | B&O Railroad | Porta Iovis Jump Gate |
| 35 | Short Line | Porta Saturni Jump Gate |
| 12 | Electric Company | Sol Invictus Solar Array |
| 28 | Water Works | Aquaeductus Water Reclaim |

## Streets (color groups)

| Group id | Classic color | Group name | Streets (index: classic -> themed) |
|---|---|---|---|
| brown | Brown | Belt Outposts | 1 Mediterranean -> Ceres Outpost; 3 Baltic -> Vesta Outpost |
| light_blue | Light blue | Selene Domes | 6 Oriental -> Tranquillitas Dome; 8 Vermont -> Serenitas Dome; 9 Connecticut -> Imbrium Dome |
| pink | Pink | Mars Habitats | 11 St. Charles -> Olympus Habitat; 13 States -> Marineris Habitat; 14 Virginia -> Hellas Habitat |
| orange | Orange | Jovian Moons | 16 St. James -> Io Forge; 18 Tennessee -> Europa Ice Works; 19 New York -> Ganymede Citadel |
| red | Red | Saturnian Moons | 21 Kentucky -> Titan Refinery; 23 Indiana -> Enceladus Geyser Base; 24 Illinois -> Rhea Bastion |
| yellow | Yellow | Ice Giant Ports | 26 Atlantic -> Miranda Spire; 27 Ventnor -> Ariel Port; 29 Marvin Gardens -> Triton Gardens |
| green | Green | Kuiper Frontier | 31 Pacific -> Pluto Praetorium; 32 North Carolina -> Charon Bastion; 34 Pennsylvania Ave -> Eris Forum |
| dark_blue | Dark blue | Centauri Crown | 37 Park Place -> Palatium Proxima; 39 Boardwalk -> Centauri Imperial Court |

Groups move outward from the Sun as prices rise. Group colors keep the classic hues so the
board stays readable.

## Other terms used in card text

| Classic | Imperium Astra |
|---|---|
| House | Outpost module |
| Hotel | Citadel |
| Get Out of Jail Free | Imperial Pardon (Mission Brief) / Senatorial Pardon (Senate Dispatch) |
| Bank | Imperial Treasury |
| Railroad rent | Jump Gate toll |

The house / hotel words used in game log text come from `data/board.json` `terms`
(`house`, `houses`, `hotel`), so a theme pack swaps them as data. The deck names shown on
pardon cards in the Trade panel come from the same `terms` (`chance`, `community_chest`, keyed by
the stable deck id). UI wording also comes from `terms` (P1-UI): `jail` ("the Brig"),
`jail_fine` ("Brig fine"), `buy` ("Claim"), `pardon` ("Pardon card"), `bank` ("the Treasury").

Each space may also carry a `short_name` (compact board label, e.g. "Mercurii Gate"); it falls
back to `display_name` and is display data only, like `display_name`.

Currency is shown as `$` for now (see OPEN_QUESTIONS.md Q2).

## Visual theme pack (P3-THEME)

Names live in `data/board.json`; the look lives in `data/themes/<id>/theme.json`, picked by
`data/ui.json` `theme_path` (default `imperium_astra`). The pack holds colors (navy panels, gold
accent, ivory button text), button / panel StyleBox sizes, board chrome (group bar height, gold
frame, corner tints and marks keyed by the stable `space_type` name: Launch Bay green-gold,
Brig and Report to the Brig deep red) and the procedural starfield settings. It never holds
`space_type` values, prices, rents or card opcodes (`tests/test_theme.gd` checks this). A new
theme copies the folder, edits the colors, and points `theme_path` at it; the colour-group colors
themselves stay in `board.json` `groups`. Open style points: OPEN_QUESTIONS.md Q20.

### Switching packs (P5-FEEL A4)

Packs are registered in `data/themes/index.json` (explicit `id` + `theme_path` list; no directory
scan). `data/ui.json` `theme_path` stays the shipped default. `UiStyle.set_theme(id)` selects a
registered pack for the current app session only (nothing is written to `res://` or `user://`)
and drops the cached pack; `Main.select_theme(id)` then re-applies it (HUD Theme, dialogue via the
pack's `dialogue_path`, setup screen, starfield, board chrome). Supported contract: switch on the
setup screen before match start; `Main.select_theme` refuses once the match screen is built.
`UiStyle.reset_theme()` restores the default (tests call it in teardown). A new pack adds its
folder and one index entry. Covered by `tests/test_theme_switch.gd`.

### Pack content overlay (P5-FEEL A5 / A6)

Each pack's `theme.json` names a `content_path` (e.g. `data/themes/imperium_astra/content.json`)
holding the pack's words. `Main.begin_match` reads it via `UiStyle.content_overlay()` and passes it
to `GameSetup.new_game(seed, seats, content)`, which applies it once at match start
(`scripts/core/content_overlay.gd`); core never reads `UiStyle` or `data/ui.json`. The setup
screen names the seats from the same overlay (`GameSetup.seats_for(flags, content)`). A pack with
no `content_path` or a missing / unreadable content file fails loudly (`push_error`,
`UiStyle.content_problem`) and the match falls back to the shared words. Whitelisted
top-level keys only (none collide with the rules keys `spaces` / `groups` / `cards` / ...):

| Key | Shape | Replaces |
|---|---|---|
| `terms` | `{term key: text}` | `board.json` `terms` |
| `space_names` | `{"<space index>": {display_name, short_name?}}` | space names (`short_name` defaults to the new `display_name`) |
| `group_names` | `{group id: text}` | group `display_name` (group colors stay in `board.json`) |
| `seat_names` | `[text, ...]`, one per `rules.json` `seat_pool` seat, in seat order | default seat names (`seat_pool` / `local_players` `display_name`; seat colors and Human/Bot stay out of packs; names a caller passes in are kept) |
| `card_text` | `{card_id: text}` (optional) | card text from `cards.json` |

Prices, rents, space types, opcodes and group colors never appear in a pack (one shared classic
`rules.json` / `board.json` / `cards.json`). Every registered pack's overlay must name every term,
space, group and seat so no default-pack word leaks through them (`tests/test_theme.gd`);
`card_text` is optional per card, and a card a pack leaves out keeps the shared `cards.json` text,
which uses the default pack's words. The default pack's overlay matches `board.json` and the
`rules.json` `seat_pool` names word for word. Log and trade-message flavor in
core goes through `board.term(...)`: `jail`, `bank`, `pardon`, `buys` ("claims"), `unowned`
("unclaimed"), `player` / `players` ("commander(s)"); `tests/test_content_overlay.gd` plays a
seeded game under the test fixture pack and checks that no default-pack word appears.
