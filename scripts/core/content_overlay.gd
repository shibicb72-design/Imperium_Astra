class_name ContentOverlay
extends RefCounted
## Theme pack content overlay (P5-FEEL A5): words only. The caller passes the overlay dictionary in
## (Main and the setup screen read the active pack's content_path); core never reads UiStyle or
## data/ui.json. GameSetup.new_game() applies it once at match start (apply()); seat_names name the
## default seats when they are built (name_seats(): GameSetup.seats_for() for the setup screen and
## new_game()'s local_players fallback). Shape (whitelisted top-level keys only, none of them rules
## keys; see docs/THEME_MAP.md):
##   terms:       {term key: String}                         -> Board.terms
##   space_names: {"<index>": {display_name, short_name?}}   -> Space display_name / short_name
##   group_names: {group id: String}                         -> Board.group_info display_name
##   seat_names:  [String, ...]  (seat order, one per rules.json seat_pool seat)
##                                   -> default seat display_name (name_seats(), not apply())
##   card_text:   {card_id: String}  (optional)              -> Card.text
## Prices, rents, space types, opcodes and group colors stay in the shared classic data; seat
## colors and Human/Bot flags stay in rules.json and the seat choice.

const KEYS: Array[String] = ["_doc", "id", "terms", "space_names", "group_names", "seat_names", "card_text"]
const SPACE_NAME_KEYS: Array[String] = ["display_name", "short_name"]


## Applies `overlay` to the match's board and decks. Unknown keys and malformed entries are skipped
## (problems() reports them); anything the overlay leaves out keeps the shared data's words.
static func apply(overlay: Dictionary, board: Board, decks: Array[CardDeck]) -> void:
	if overlay.is_empty():
		return
	for k: Variant in overlay:
		if not (String(k) in KEYS):
			push_warning("ContentOverlay: ignoring key '%s'" % k)
	var terms: Variant = overlay.get("terms", {})
	if terms is Dictionary:
		for key: Variant in terms:
			if terms[key] is String:
				board.terms[String(key)] = terms[key]
	var space_names: Variant = overlay.get("space_names", {})
	if space_names is Dictionary:
		for key: Variant in space_names:
			var i := _index(key, board.spaces.size())
			var entry: Variant = space_names[key]
			if i < 0 or not entry is Dictionary:
				continue
			var s := board.spaces[i]
			if entry.get("display_name") is String:
				s.display_name = entry["display_name"]
				s.short_name = s.display_name
			if entry.get("short_name") is String:
				s.short_name = entry["short_name"]
	var group_names: Variant = overlay.get("group_names", {})
	if group_names is Dictionary:
		for gid: Variant in group_names:
			var info: Variant = board.group_info.get(StringName(gid))
			if info is Dictionary and group_names[gid] is String:
				info["display_name"] = group_names[gid]
	var card_text: Variant = overlay.get("card_text", {})
	if card_text is Dictionary:
		for deck in decks:
			for c in deck.draw_pile:
				var text: Variant = card_text.get(String(c.card_id))
				if text is String and not String(text).is_empty():
					c.text = text


## Copies of the default seat specs (rules.json seat_pool / local_players, in seat order) with seat
## i named seat_names[i] when that is a non-empty string; other seats and every other field (color,
## is_bot) stay as given. Callers pass default seats only, so a name a caller picked is kept.
static func name_seats(overlay: Dictionary, specs: Array[Dictionary]) -> Array[Dictionary]:
	var names: Variant = overlay.get("seat_names", [])
	var out: Array[Dictionary] = []
	for i in specs.size():
		var spec := specs[i].duplicate()
		if names is Array and i < names.size() and names[i] is String and not String(names[i]).is_empty():
			spec["display_name"] = names[i]
		out.append(spec)
	return out


## Schema problems in `overlay` against the shared data (empty = valid); `seat_count` is the size of
## rules.json seat_pool. With `complete`, the overlay must also name every term, space, group and
## seat so no default-pack word leaks through (every registered pack's overlay is complete;
## card_text stays optional either way).
static func problems(overlay: Dictionary, board: Board, card_ids: Array[String], seat_count: int, complete: bool) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in overlay:
		if not (String(k) in KEYS):
			out.append("unknown key '%s'" % k)
	var terms: Variant = overlay.get("terms", {})
	if not terms is Dictionary:
		out.append("terms is not an object")
		terms = {}
	for key: Variant in terms:
		if not terms[key] is String or String(terms[key]).is_empty():
			out.append("term '%s' is not a non-empty string" % key)
	var space_names: Variant = overlay.get("space_names", {})
	if not space_names is Dictionary:
		out.append("space_names is not an object")
		space_names = {}
	for key: Variant in space_names:
		var entry: Variant = space_names[key]
		if _index(key, board.spaces.size()) < 0:
			out.append("space_names key '%s' is not a space index" % key)
		elif not entry is Dictionary:
			out.append("space_names '%s' is not an object" % key)
		else:
			for f: Variant in entry:
				if not (String(f) in SPACE_NAME_KEYS):
					out.append("space_names '%s' has non-name key '%s'" % [key, f])
				elif not entry[f] is String or String(entry[f]).is_empty():
					out.append("space_names '%s' %s is not a non-empty string" % [key, f])
	var group_names: Variant = overlay.get("group_names", {})
	if not group_names is Dictionary:
		out.append("group_names is not an object")
		group_names = {}
	for gid: Variant in group_names:
		if not board.group_info.has(StringName(gid)):
			out.append("group_names key '%s' is not a group" % gid)
		elif not group_names[gid] is String or String(group_names[gid]).is_empty():
			out.append("group_names '%s' is not a non-empty string" % gid)
	var seat_names: Variant = overlay.get("seat_names", [])
	if not seat_names is Array:
		out.append("seat_names is not a list")
		seat_names = []
	if seat_names.size() > seat_count:
		out.append("seat_names has %d names for %d seats" % [seat_names.size(), seat_count])
	for i in seat_names.size():
		if not seat_names[i] is String or String(seat_names[i]).is_empty():
			out.append("seat_names[%d] is not a non-empty string" % i)
		elif seat_names.find(seat_names[i]) < i:
			out.append("seat_names[%d] repeats '%s'" % [i, seat_names[i]])
	var card_text: Variant = overlay.get("card_text", {})
	if not card_text is Dictionary:
		out.append("card_text is not an object")
		card_text = {}
	for cid: Variant in card_text:
		if not (String(cid) in card_ids):
			out.append("card_text key '%s' is not a card_id" % cid)
		elif not card_text[cid] is String or String(card_text[cid]).is_empty():
			out.append("card_text '%s' is not a non-empty string" % cid)
	if complete:
		for key: String in board.terms:
			if not terms.has(key):
				out.append("missing term '%s'" % key)
		for i in board.spaces.size():
			var entry: Variant = space_names.get(str(i))
			if not entry is Dictionary or not entry.get("display_name") is String:
				out.append("missing space_names '%d' display_name" % i)
		for gid: StringName in board.group_info:
			if not group_names.has(String(gid)):
				out.append("missing group_names '%s'" % gid)
		for i in range(seat_names.size(), seat_count):
			out.append("missing seat_names[%d]" % i)
	return out


## Space index for a space_names key ("0".."39"), or -1.
static func _index(key: Variant, count: int) -> int:
	var s := String(key)
	if not s.is_valid_int():
		return -1
	var i := s.to_int()
	return i if i >= 0 and i < count else -1
