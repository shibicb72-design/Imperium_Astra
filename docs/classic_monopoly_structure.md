# Classic US Monopoly — Structure Rundown for Godot 4 Android Scaffolding

**Scope:** Classic US Monopoly (Hasbro / Parker Brothers standard Atlantic City edition). Theme is TBD — this document uses **only classic Monopoly names and structure**. No invented theme content.

**Primary official sources (prefer these):**

| ID | Source | URL | Notes |
|----|--------|-----|-------|
| **H-C1009** | Hasbro Monopoly Classic instructions (C1009, ©2021) PDF | https://assets-us-01.kc-usercontent.com/500e0a65-283d-00ef-33b2-7f1f20488fe2/6755a913-6560-430c-afdc-890014a82ce7/C10090790_INST_MONOPOLY_CLASSIC_F21.pdf | Current-style classic sheet: setup, turn flow, board spaces, jail, buildings, mortgage, bankruptcy |
| **H-G0009** | Hasbro Monopoly Classic Refresh instructions (G0009, ©2025) PDF | https://assets-us-01.kc-usercontent.com/500e0a65-283d-00ef-33b2-7f1f20488fe2/12890f7d-e57c-47f5-9d25-288b2fa5c397/G0009GA01_INST_MONOPOLY_CLASSIC_REFRESH_FAR.pdf | Confirms contents, $1500 start, same core rules |
| **H-WEB** | Hasbro product / instructions page for Monopoly C1009 | https://instructions.hasbro.com/en-us/instruction/monopoly-board-game-for-ages-8-for-2-6-players-includes-8-tokens-tokens-may-vary | Contents: 28 deeds, 16 Chance, 16 Community Chest, 32 houses, 12 hotels, 2–6 players, 8 tokens |
| **H-00009** | Hasbro/Parker Brothers classic rules PDF (Speed Die edition, classic section, ©2004/2007) | https://www.hasbro.com/common/instruct/00009.pdf | Fuller classic wording: mortgages, bankruptcy, GOOJF sale, older Income Tax option |

**Secondary / community (use only where official PDF omits numbers):**

| ID | Source | URL |
|----|--------|-----|
| **WIKI** | Wikipedia — Monopoly (game) | https://en.wikipedia.org/wiki/Monopoly_(game) |
| **DEED-SEC** | Widely republished classic Title Deed rent tables (e.g. falstad.com/monopoly.html; academic mirrors) | https://falstad.com/monopoly.html |
| **CARD-SEC** | Community lists of post-2008 US Chance / Community Chest card texts | e.g. https://www.monopolyland.com/list-monopoly-chance-community-chest-cards/ |

**Claim labels used below:**

- **OFFICIAL** — Stated in Hasbro/Parker Brothers rules or Hasbro product contents.
- **COMMUNITY/SECONDARY** — Consistent across reputable secondary compilations / Wikipedia; not printed in the cited rules PDF text.
- **INFERRED** — Logical consequence of official rules for a digital implementation; not a printed rule.
- **UNKNOWN** — Not verified from sources used; do not invent.

**Edition note (classic names):** This report uses classic US street names including **Oriental Avenue**. Wikipedia reports a 2025 Hasbro refresh renaming Oriental Avenue → Rhode Island Avenue; if targeting the absolute newest physical set, verify that rename. Core geometry and prices otherwise match classic US structure.

---

## 1) Board layout

### 1.1 Forty spaces and corner positions

**OFFICIAL (structure) / COMMUNITY/SECONDARY (exact clockwise index list):** The classic board has **40 spaces** in a clockwise loop. Corners (indices 0, 10, 20, 30 if GO = 0):

| Index | Corner | Role |
|------:|--------|------|
| 0 | **GO** | Collect $200 salary when pass or land (**OFFICIAL** H-C1009, H-00009) |
| 10 | **Jail / Just Visiting** | Same physical corner; “In Jail” vs “Just Visiting” are distinct states (**OFFICIAL** H-C1009, H-00009) |
| 20 | **Free Parking** | Resting place only; no money/reward under official rules (**OFFICIAL** H-C1009; H-00009 “free resting place”) |
| 30 | **Go To Jail** | Immediate move to In Jail; no $200 for passing GO; turn ends (**OFFICIAL** H-C1009, H-00009) |

### 1.2 Space types and counts

**COMMUNITY/SECONDARY (WIKI; consistent with H-WEB contents of 28 Title Deeds):**

| Type | Count | Notes |
|------|------:|-------|
| Color-group streets | 22 | 8 color groups (2 or 3 streets each) |
| Railroads | 4 | Mid-side each edge |
| Utilities | 2 | Electric Company, Water Works |
| Chance | 3 | Draw Chance |
| Community Chest | 3 | Draw Community Chest |
| Income Tax | 1 | Flat tax on modern classic |
| Luxury Tax | 1 | Flat tax on modern classic |
| Corner action / special | 4 | GO, Jail/JV, Free Parking, Go To Jail |
| **Total** | **40** | |

Purchasable properties = 22 + 4 + 2 = **28** → matches **28 Title Deed Cards** (**OFFICIAL** H-WEB, H-C1009 contents).

### 1.3 Classic clockwise board (GO = 0)

**COMMUNITY/SECONDARY** layout and board prices (WIKI US board table; prices also appear on board art / Title Deeds). Prices marked **OFFICIAL** where confirmed in H-C1009 / H-G0009 PDF excerpts.

| # | Space | Type / color | Price |
|--:|-------|--------------|------:|
| 0 | GO | Corner | — |
| 1 | Mediterranean Avenue | Brown | 60 |
| 2 | Community Chest | Draw | — |
| 3 | Baltic Avenue | Brown | 60 |
| 4 | Income Tax | Tax | Pay **200** (modern flat) **OFFICIAL** H-C1009 shows A200 |
| 5 | Reading Railroad | Railroad | **200** **OFFICIAL** H-C1009 |
| 6 | Oriental Avenue | Light blue | 100 (**OFFICIAL** deed rent examples in H-C1009; price COMMUNITY) |
| 7 | Chance | Draw | — |
| 8 | Vermont Avenue | Light blue | 100 |
| 9 | Connecticut Avenue | Light blue | **120** (**OFFICIAL** H-G0009 example A120) |
| 10 | Jail / Just Visiting | Corner | — |
| 11 | St. Charles Place | Pink (magenta) | 140 |
| 12 | Electric Company | Utility | **150** **OFFICIAL** H-C1009 |
| 13 | States Avenue | Pink | 140 |
| 14 | Virginia Avenue | Pink | 160 |
| 15 | Pennsylvania Railroad | Railroad | 200 |
| 16 | St. James Place | Orange | 180 |
| 17 | Community Chest | Draw | — |
| 18 | Tennessee Avenue | Orange | 180 |
| 19 | New York Avenue | Orange | 200 |
| 20 | Free Parking | Corner | — |
| 21 | Kentucky Avenue | Red | 220 (**OFFICIAL** H-G0009 deed snippet Rent A18 / houses A150) |
| 22 | Chance | Draw | — |
| 23 | Indiana Avenue | Red | 220 |
| 24 | Illinois Avenue | Red | **240** **OFFICIAL** H-C1009 |
| 25 | B&O Railroad | Railroad | 200 |
| 26 | Atlantic Avenue | Yellow | 260 |
| 27 | Ventnor Avenue | Yellow | 260 |
| 28 | Water Works | Utility | **150** **OFFICIAL** H-C1009 |
| 29 | Marvin Gardens | Yellow | 280 |
| 30 | Go To Jail | Corner | — |
| 31 | Pacific Avenue | Green | 300 |
| 32 | North Carolina Avenue | Green | 300 |
| 33 | Community Chest | Draw | — |
| 34 | Pennsylvania Avenue | Green | 320 |
| 35 | Short Line | Railroad | 200 |
| 36 | Chance | Draw | — |
| 37 | Park Place | Dark blue | 350 |
| 38 | Luxury Tax | Tax | Pay **100** (modern) **OFFICIAL** H-C1009 shows A100 |
| 39 | Boardwalk | Dark blue | 400 |

### 1.4 Color groups with classic prices / rents

**Rent / house-cost tables:** Partial deeds are printed in official PDFs (examples below). A **complete** 0–4 houses + hotel rent matrix for all 22 streets is **not fully transcribed in the rules PDF text**; the table below marks rows:

- **OFFICIAL*** — Values appear in H-C1009 / H-G0009 Title Deed illustrations.
- **COMMUNITY/SECONDARY** — Standard classic US Title Deed values from secondary deed tables (DEED-SEC); treat as authoritative for scaffolding only after verifying against physical Title Deeds if legal/compliance requires pixel-perfect fidelity.

**Color-set monopoly bonus (unimproved):** Owning all streets in a color set doubles rent on those streets (**OFFICIAL** H-C1009, H-00009). Building requires a complete color set (**OFFICIAL**).

| Color | Streets | Price | House cost | Rent 0 / color-set / 1H / 2H / 3H / 4H / Hotel | Label |
|-------|---------|------:|-----------:|-----------------------------------------------|-------|
| Brown | Mediterranean Ave | 60 | 50 | 2 / 4 / 10 / 30 / 90 / 160 / 250 | OFFICIAL* (H-G0009 Mediterranean deed); COMMUNITY for full row |
| Brown | Baltic Ave | 60 | 50 | 4 / 8 / 20 / 60 / 180 / 320 / 450 | COMMUNITY/SECONDARY |
| Light blue | Oriental Ave | 100 | 50 | 6 / 12 / 30 / 90 / 270 / 400 / 550 | **OFFICIAL** H-C1009 |
| Light blue | Vermont Ave | 100 | 50 | 6 / 12 / 30 / 90 / 270 / 400 / 550 | **OFFICIAL** H-C1009 |
| Light blue | Connecticut Ave | 120 | 50 | 8 / 16 / 40 / 100 / 300 / 450 / 600 | **OFFICIAL** H-C1009 |
| Pink | St. Charles Place | 140 | 100 | 10 / 20 / 50 / 150 / 450 / 625 / 750 | COMMUNITY/SECONDARY |
| Pink | States Avenue | 140 | 100 | 10 / 20 / 50 / 150 / 450 / 625 / 750 | COMMUNITY/SECONDARY |
| Pink | Virginia Avenue | 160 | 100 | 12 / 24 / 60 / 180 / 500 / 700 / 900 | COMMUNITY/SECONDARY |
| Orange | St. James Place | 180 | 100 | 14 / 28 / 70 / 200 / 550 / 750 / 950 | OFFICIAL* partial (H-G0009 St. James); COMMUNITY for full |
| Orange | Tennessee Avenue | 180 | 100 | 14 / 28 / 70 / 200 / 550 / 750 / 950 | COMMUNITY/SECONDARY |
| Orange | New York Avenue | 200 | 100 | 16 / 32 / 80 / 220 / 600 / 800 / 1000 | COMMUNITY/SECONDARY |
| Red | Kentucky Avenue | 220 | 150 | 18 / 36 / 90 / 250 / 700 / 875 / 1050 | OFFICIAL* partial (H-G0009); COMMUNITY for full |
| Red | Indiana Avenue | 220 | 150 | 18 / 36 / 90 / 250 / 700 / 875 / 1050 | COMMUNITY/SECONDARY |
| Red | Illinois Avenue | 240 | 150 | 20 / 40 / 100 / 300 / 750 / 925 / 1100 | COMMUNITY/SECONDARY (price OFFICIAL) |
| Yellow | Atlantic Avenue | 260 | 150 | 22 / 44 / 110 / 330 / 800 / 975 / 1150 | COMMUNITY/SECONDARY |
| Yellow | Ventnor Avenue | 260 | 150 | 22 / 44 / 110 / 330 / 800 / 975 / 1150 | COMMUNITY/SECONDARY |
| Yellow | Marvin Gardens | 280 | 150 | 24 / 48 / 120 / 360 / 850 / 1025 / 1200 | COMMUNITY/SECONDARY |
| Green | Pacific Avenue | 300 | 200 | 26 / 52 / 130 / 390 / 900 / 1100 / 1275 | COMMUNITY/SECONDARY |
| Green | North Carolina Avenue | 300 | 200 | 26 / 52 / 130 / 390 / 900 / 1100 / 1275 | COMMUNITY/SECONDARY |
| Green | Pennsylvania Avenue | 320 | 200 | 28 / 56 / 150 / 450 / 1000 / 1200 / 1400 | COMMUNITY/SECONDARY |
| Dark blue | Park Place | 350 | 200 | 35 / 70 / 175 / 500 / 1100 / 1300 / 1500 | COMMUNITY/SECONDARY |
| Dark blue | Boardwalk | 400 | 200 | 50 / 100 / 200 / 600 / 1400 / 1700 / 2000 | COMMUNITY/SECONDARY |

**Hotel cost on deed:** Shown as same amount as house cost “each (plus 4 houses)” on light-blue deeds (**OFFICIAL** H-C1009) — i.e. pay hotel price and return 4 houses.

**Mortgage value:** Printed on Title Deed back; commonly half the purchase price (**COMMUNITY/SECONDARY** for numeric table; **OFFICIAL** that mortgage value is on the deed and you collect that amount — H-C1009, H-00009).

### 1.5 Railroads

**OFFICIAL** (H-C1009, H-G0009):

- Names (classic US): **Reading Railroad**, **Pennsylvania Railroad**, **B&O Railroad**, **Short Line** (**COMMUNITY/SECONDARY** for full four names on board; Reading confirmed **OFFICIAL** in H-C1009).
- Price: **$200** each (**OFFICIAL** H-C1009 for Reading).
- Rent by count owned: **$25 / $50 / $100 / $200** (**OFFICIAL** H-C1009, H-G0009).

### 1.6 Utilities

**OFFICIAL** (H-C1009):

- **Electric Company**, **Water Works** — price **$150** each.
- Rent: roll dice; **4×** dice if owner has 1 utility; **10×** if owner has both.
- Note: When landing by normal move, use the dice just rolled; when sent by a card that says to throw dice for utility rent, roll again (**COMMUNITY/SECONDARY** card text; H-00009 implies rent from dice for utilities).

### 1.7 Chance / Community Chest / taxes / Free Parking

| Space | Rule | Label |
|-------|------|-------|
| Chance (×3) | Take top Chance card; resolve immediately; return to **bottom** of deck (except GOOJF held) | **OFFICIAL** H-C1009, H-00009 |
| Community Chest (×3) | Same with Community Chest deck | **OFFICIAL** |
| Income Tax | Modern classic: pay amount on space = **$200** | **OFFICIAL** H-C1009 |
| Luxury Tax | Modern classic: pay **$100** | **OFFICIAL** H-C1009 |
| Free Parking | Nothing happens; **do not** put fines in the middle (house rule explicitly discouraged) | **OFFICIAL** H-C1009 tip |

**Older Income Tax (do not use for modern classic scaffolding unless targeting pre-2008):** Pay $200 **or** 10% of total worth, chosen before calculating (**OFFICIAL** H-00009 only). Wikipedia attributes flat $200 + Luxury Tax $100 to the **2008** US redesign (**COMMUNITY/SECONDARY** WIKI).

---

## 2) Setup

| Item | Value | Label |
|------|-------|-------|
| Starting cash | **$1,500** per player | **OFFICIAL** H-C1009 “(Total = a1500)”; H-G0009 “Total: A1500”; H-00009 |
| Bill breakdown (modern US classic, post-2008 style) | Commonly **2×$500, 4×$100, 1×$50, 1×$20, 2×$10, 1×$5, 5×$1** | **COMMUNITY/SECONDARY** (WIKI); H-G0009 shows denomination icons totaling 1500 — OCR of exact counts is messy in extracted text |
| Older Parker breakdown (H-00009) | 2 each of $500, $100, $50; 6×$20; 5 each of $10, $5, $1 | **OFFICIAL** H-00009 (OCR garbled; intent is classic $1500 pack) |
| Player count | **2–6** (current classic box) | **OFFICIAL** H-WEB, H-C1009, H-G0009 |
| Older “2 to 8” | Appears on H-00009 Speed Die set | **OFFICIAL** that edition; prefer **2–6** for current classic |
| Tokens | **8** tokens included (names vary by year: e.g. Top Hat, Rubber Ducky, Scotty, Hazel, Race Car, Penguin, Battleship, Thimble/T-Rex per H-WEB) | **OFFICIAL** H-WEB contents; exact set is edition-dependent |
| Title Deed cards | **28** | **OFFICIAL** H-WEB, H-C1009 |
| Houses in bank | **32** | **OFFICIAL** H-WEB, H-C1009, H-00009 |
| Hotels in bank | **12** | **OFFICIAL** H-WEB, H-C1009, H-00009 |
| Dice | **2** six-sided (classic play; ignore optional Speed Die unless implementing that variant) | **OFFICIAL** H-WEB / H-C1009 |
| Chance / Community Chest | **16** each | **OFFICIAL** H-WEB, H-C1009, H-G0009 |
| Banker | Choose someone to be Banker; manages Bank money, houses, hotels, Title Deeds, auctions; may play but must keep personal funds separate | **OFFICIAL** H-C1009, H-00009 |
| Who starts | Each player rolls both dice; highest starts; play to the left | **OFFICIAL** H-C1009 |
| Tokens start | On **GO** | **OFFICIAL** H-C1009 |
| Decks | Shuffle Chance and Community Chest; place facedown on board | **OFFICIAL** H-C1009 |

**Bank never goes broke:** Banker may issue more money on paper if needed (**OFFICIAL** H-00009). Digital **INFERENCE:** use unbounded integer cash for the Bank.

---

## 3) Turn flow

**OFFICIAL** sequence (H-C1009):

1. **Roll** both dice.
2. **Move** token **clockwise** that many spaces.
3. **Resolve** the space landed on (see below).
4. If **doubles**: roll again and take another turn — **except** if this is the **third doubles in a row** → go to Jail immediately; **do not complete** the third turn (**OFFICIAL** H-C1009, H-00009).
5. **End turn**; pass dice left.

### 3.1 Landing resolution

| Landing | Action | Label |
|---------|--------|-------|
| Unowned street / RR / utility | **Must buy or auction** (modern classic wording) | **OFFICIAL** H-C1009 (“must buy it or auction it”) |
| Buy | Pay board price; take Title Deed from Bank | **OFFICIAL** |
| Decline / auction | Banker auctions; modern: bids start at **$10**, increments as little as **$1**; any player may bid; if no bid, deed stays in Bank | **OFFICIAL** H-C1009. Older H-00009: bidding may start at any price |
| Owned by other (unmortgaged) | Owner must **ask** for rent; if asked, pay deed rent. If owner doesn’t ask before **next player rolls**, no rent due | **OFFICIAL** H-C1009. Older H-00009: before the **second** player following throws |
| Mortgaged property | No rent | **OFFICIAL** |
| Chance / Community Chest | Draw and resolve | **OFFICIAL** |
| Income Tax / Luxury Tax | Pay Bank amount on space | **OFFICIAL** (modern) |
| GO | Collect $200 (also when **passing**) | **OFFICIAL** |
| Just Visiting | No penalty | **OFFICIAL** |
| Free Parking | Nothing | **OFFICIAL** |
| Go To Jail | Move to In Jail; no $200; turn over | **OFFICIAL** |

### 3.2 Optional build / trade / mortgage timing

**OFFICIAL** (H-C1009, H-00009):

- Buy houses/hotels **as soon as you have a color set** — **you don’t have to wait for your turn**.
- Buy/sell/trade property and GOOJF cards with other players **at any time**.
- Mortgage **at any time** (after selling buildings on the color set).
- While In Jail you may still collect rent, bid, buy houses/hotels, mortgage, and trade (**OFFICIAL** H-C1009).

**Building rules (OFFICIAL):**

- Build **evenly** across the color set; max **4 houses** per street; then upgrade to **1 hotel** (return 4 houses + pay hotel cost).
- Cannot build if any street in the set is mortgaged.
- Houses/hotels sold back to Bank for **half** cost; sell evenly; hotels exchange to 4 houses when sold (**OFFICIAL** H-C1009).
- Building shortage: cannot buy if Bank has none; if multiple players want last building, auction from $10 (**OFFICIAL** H-C1009).

---

## 4) Money & ownership

### 4.1 Street rent

- Use Title Deed rent for 0–4 houses or hotel (**OFFICIAL**).
- **Color-group monopoly:** double rent on **unimproved** streets in a complete set (**OFFICIAL**). Applies to unmortgaged streets even if another street in the set is mortgaged (**OFFICIAL** H-00009; H-C1009 notes increased rent still collectible on unmortgaged streets in a set).

### 4.2 Railroads & utilities

- RR: **25 / 50 / 100 / 200** by count (**OFFICIAL**).
- Utilities: **4×** or **10×** dice (**OFFICIAL**).

### 4.3 Mortgage

**OFFICIAL** (H-C1009, H-00009):

1. Sell all buildings in the color set to Bank at half cost first.
2. Turn Title Deed face down; collect **mortgage value** from Bank (printed on deed; typically half price — **COMMUNITY** for “half price” as a universal formula).
3. To unmortgage: pay Bank **mortgage value + 10%** (H-C1009 explicitly: “mortgage value +10%”; modern deeds may print “unmortgage cost”).
4. No rent on mortgaged properties.
5. Trading mortgaged property allowed; new owner must immediately repay unmortgage **or** pay **10%** to keep mortgage (**OFFICIAL** H-C1009 / H-00009; H-00009 details an extra 10% if lifting later after keeping).

### 4.4 Bankruptcy & leaving the game

**OFFICIAL** (H-C1009, expanded in H-00009):

1. Try to raise money: sell buildings half price; mortgage.
2. If still unable to pay:
   - **Owe a player:** Give them all your **mortgaged** properties and any GOOJF cards (H-C1009 simplified). H-00009 also: turn over all value; buildings sold to Bank half price with cash to creditor; creditor handles mortgages with 10% interest rules.
   - **Owe the Bank:** Return all properties to Bank; mortgages canceled; properties auctioned; return GOOJF to bottom of deck.
3. Player is out. Remaining players continue until **one** remains → that player wins (**OFFICIAL**).

**No player-to-player loans** of money (**OFFICIAL** H-00009; H-C1009 tip against loans / rent immunity deals).

---

## 5) Chance / Community Chest

| Topic | Fact | Label |
|-------|------|-------|
| Deck size | **16 Chance**, **16 Community Chest** | **OFFICIAL** H-WEB, H-C1009, H-G0009 |
| Draw | Top card; do what it says immediately | **OFFICIAL** |
| After use | Return to **bottom** of the same deck | **OFFICIAL** H-C1009, H-00009 |
| Separate discard + reshuffle when empty? | **Not** how official rules describe it — cards go to the bottom, so the deck does not “empty” in normal play | **OFFICIAL** procedure; **INFERRED** no reshuffle-from-discard needed |
| Get Out of Jail Free | **Keep** until used or sold; then return to bottom of appropriate deck; may sell to another player at agreed price | **OFFICIAL** H-00009, H-C1009 |

### 5.1 Key card categories (for data model)

Exact modern card wording is **not** printed in the rules PDFs cited. Category taxonomy for scaffolding:

| Category | Examples (classic US themes) | Label |
|----------|------------------------------|-------|
| Move to named space | Advance to GO, Boardwalk, Illinois Ave, St. Charles Place, Reading Railroad | **COMMUNITY/SECONDARY** card lists |
| Move relative / nearest | Go back 3; nearest Railroad (×2); nearest Utility | **COMMUNITY/SECONDARY** |
| Pay / collect Bank | Speeding fine; bank dividend; building loan; various Community Chest collect/pay | **COMMUNITY/SECONDARY** |
| Pay / collect players | Chairman pay each $50; birthday collect from each | **COMMUNITY/SECONDARY** |
| Jail | Go to Jail; Get Out of Jail Free (one per deck typically) | **OFFICIAL** that these card types exist (H-00009); counts **COMMUNITY** |
| Repairs | Chance: $25/house, $100/hotel; Community Chest street repairs $40/house, $115/hotel (post-2008 lists) | **COMMUNITY/SECONDARY** |

**Implementation tip:** Store cards as data-driven `CardEffect` resources (theme-agnostic opcodes: `ADVANCE_TO`, `PAY_BANK`, `COLLECT_BANK`, `PAY_EACH_PLAYER`, `COLLECT_FROM_EACH`, `REPAIRS`, `GO_TO_JAIL`, `GOOJF`, `MOVE_NEAREST_RR`, etc.) so art/theme can swap later without rule changes.

---

## 6) Jail

### 6.1 How you get In Jail

**OFFICIAL** (H-00009, H-C1009):

1. Land on **Go To Jail**.
2. Draw a **Go to Jail** card.
3. Roll **doubles three times in a row** on a turn.

Effects: move **directly** to In Jail; **do not** collect $200 for passing GO; **turn ends**.

### 6.2 Just Visiting vs In Jail

- Land on Jail corner by ordinary movement → **Just Visiting**, no penalty (**OFFICIAL**).
- Sent to Jail → occupy **In Jail** section (**OFFICIAL**).

### 6.3 Getting out (modern classic — 3 options)

**OFFICIAL** H-C1009 / H-G0009:

1. Pay **$50** at the start of your next turn, then roll and move as normal.
2. Use a **Get Out of Jail Free** card (or buy one), return it to bottom of deck, then roll and move.
3. **Roll doubles** on your next turn → free; use that roll to move; **that ends your turn** (no extra doubles turn from this).

You may try for doubles for up to **3 turns** in Jail.

### 6.4 Turn-3 failure

**OFFICIAL** H-C1009: If you don’t roll doubles by your **third** turn in Jail, **pay $50** and **use your last roll to move**.

**Older H-00009 nuance:** Paying $50 allowed before rolling on either of next two turns; on third turn must pay if no doubles — still move with the roll. Prefer **H-C1009** wording for current classic.

While in Jail you may still collect rent, trade, build, mortgage, bid (**OFFICIAL** H-C1009).

---

## 7) Win condition

**OFFICIAL** (H-C1009, H-G0009, H-00009):

> Last player remaining with money when all others have gone **bankrupt** wins.

No official scoring/end-time required for classic play (short-game / timed variants exist in older booklets — out of scope unless requested).

---

## 8) Suggested Godot 4 data model / scene graph (no art)

Theme-agnostic: names and colors are **data**, not hard-coded UI theme. Structure for rules fidelity.

### 8.1 Scene graph (sketch)

```
Main (Node)
└── GameRoot (Node)                          # owns match lifecycle
    ├── BoardView (Node2D / Control)          # visual only; reads Board
    │   └── SpaceMarkers[40]
    ├── UILayer (CanvasLayer)
    │   ├── HUD
    │   ├── DeedPanel
    │   ├── TradePanel
    │   ├── AuctionPanel
    │   └── JailPanel
    └── Controllers (Node)
        ├── TurnController
        ├── Bank
        ├── Dice
        ├── ChanceDeck (CardDeck)
        └── CommunityChestDeck (CardDeck)
```

Players as child nodes or resources referenced by `TurnController`.

### 8.2 Core types (fields)

#### `Board` (Resource or Node)

- `spaces: Array[Space]` — length 40, index 0 = GO
- `color_groups: Dictionary` — `ColorGroupId → Array[space_index]`
- Signals: none required; queried by controllers

#### `Space` (Resource)

- `index: int`
- `space_type: enum` — `GO, JAIL_CORNER, FREE_PARKING, GO_TO_JAIL, CHANCE, COMMUNITY_CHEST, INCOME_TAX, LUXURY_TAX, STREET, RAILROAD, UTILITY`
- `display_name: String` — classic name string
- `color_group_id: StringName` — empty if N/A
- `list_price: int` — 0 if non-property
- `tax_amount: int` — for tax spaces
- `deed: PropertyDeed` — null if non-property

#### `PropertyDeed` (Resource)

- `property_id: StringName`
- `list_price: int`
- `mortgage_value: int`
- `house_cost: int`
- `hotel_cost: int`
- `rent_by_houses: Array[int]` — size 6: [0H, 1H, 2H, 3H, 4H, HOTEL] (color-set double applied in rules, not stored twice)
- `owner: Player` — null = bank
- `is_mortgaged: bool`
- `houses: int` — 0–4; if hotel, use `has_hotel`
- `has_hotel: bool`
- Methods (or pure functions in Rules): `current_rent(game_state) -> int`

#### `Player` (Node or Resource)

- `id`, `display_name`
- `token_id: StringName`
- `cash: int`
- `position: int` — 0–39
- `in_jail: bool`
- `jail_turns_tried: int` — 0–3
- `get_out_of_jail_cards: int` — or references to Card instances
- `deeds: Array[PropertyDeed]`
- Signals: `cash_changed`, `bankrupt`, `moved`

#### `Bank` (Node)

- `cash: int` — unbounded / large
- `houses_remaining: int` — start 32
- `hotels_remaining: int` — start 12
- `unowned_deeds: Array[PropertyDeed]`
- Methods: `sell_property`, `auction`, `buy_house`, `buy_hotel`, `mortgage`, `unmortgage`, `pay_salary_go`
- Signals: `building_shortage`, `auction_required`

#### `Dice` (Node)

- `d1: int`, `d2: int`
- `is_doubles() -> bool`
- `total() -> int`
- Signals: `rolled(d1, d2)`

#### `CardDeck` (Node)

- `deck_id: enum CHANCE | COMMUNITY_CHEST`
- `draw_pile: Array[Card]` — ordered; draw from front, return to back
- Methods: `shuffle()`, `draw() -> Card`, `return_to_bottom(card)`, `hold_goojf(player, card)`
- Signals: `card_drawn(card)`

#### `Card` (Resource)

- `card_id: StringName`
- `text_classic: String` — classic wording (theme swap later)
- `effect: CardEffect` — data-driven opcode + params
- `is_goojf: bool`

#### `TurnController` (Node) — state machine

Suggested states:

```
IDLE_BETWEEN_TURNS
→ ROLL_AND_MOVE
→ RESOLVE_SPACE          # buy/auction/rent/card/tax/jail/go
→ POST_LANDING           # doubles check → extra turn or end
→ AWAITING_PLAYER_ACTION # optional: build/trade/mortgage anytime overlays
→ IN_JAIL_DECISION       # pay / GOOJF / try doubles
→ AUCTION
→ TRADE
→ BANKRUPTCY_SETTLEMENT
→ GAME_OVER
```

Fields:

- `players: Array[Player]`
- `current_index: int`
- `doubles_streak: int`
- `phase: enum`

Signals:

- `turn_started(player)`
- `turn_ended(player)`
- `doubles_extra_turn(player)`
- `sent_to_jail(player, reason)`
- `rent_requested(owner, payer, amount)`
- `winner_declared(player)`

### 8.3 Ownership / authority

| Authority | Owns |
|-----------|------|
| `Bank` | Unowned deeds, building stock, infinite cash issuance |
| `Player` | Cash, deeds, GOOJF, token position, jail state |
| `Board` | Immutable layout + deed templates |
| `TurnController` | Whose turn, doubles streak, phase |
| `CardDeck` | Ordering of Chance / CC |

### 8.4 Rules fidelity notes for Android / Godot 4

- Keep **rules in pure functions / a `Rules` autoload** separate from UI so headless tests can assert rent, mortgage+10%, three-doubles jail, etc.
- **Anytime actions** (build/trade/mortgage): allow from most phases except mid-forced resolution; queue UI modals without advancing `current_index`.
- Rent prompt: implement owner “ask” window until next roll (**OFFICIAL** modern) — for solo/AI, auto-ask.
- Do **not** implement Free Parking jackpot unless as an explicit optional house-rule flag (default **off** per H-C1009).
- Theme TBD: only swap `display_name`, colors, and card `text` / art; keep `space_type`, prices, and opcodes stable.

---

## Source checklist (quick)

1. **H-C1009** — https://assets-us-01.kc-usercontent.com/500e0a65-283d-00ef-33b2-7f1f20488fe2/6755a913-6560-430c-afdc-890014a82ce7/C10090790_INST_MONOPOLY_CLASSIC_F21.pdf  
2. **H-G0009** — https://assets-us-01.kc-usercontent.com/500e0a65-283d-00ef-33b2-7f1f20488fe2/12890f7d-e57c-47f5-9d25-288b2fa5c397/G0009GA01_INST_MONOPOLY_CLASSIC_REFRESH_FAR.pdf  
3. **H-WEB** — https://instructions.hasbro.com/en-us/instruction/monopoly-board-game-for-ages-8-for-2-6-players-includes-8-tokens-tokens-may-vary  
4. **H-00009** — https://www.hasbro.com/common/instruct/00009.pdf  
5. **WIKI** — https://en.wikipedia.org/wiki/Monopoly_(game)  
6. **DEED-SEC** — https://falstad.com/monopoly.html  

Local copies of PDFs/text extracts used for this report: `/workspace/monopoly_research/`.

---

*End of report. No theme invented. Unknown numeric claims left unlabeled as OFFICIAL.*
