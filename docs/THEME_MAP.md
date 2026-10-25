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
