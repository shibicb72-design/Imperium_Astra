class_name DialogueLines
extends RefCounted
## Event-banner copy (presentation only). Loads the active theme's dialogue file (theme.json
## dialogue_path, e.g. data/themes/imperium_astra/dialogue.json) and turns TurnController.game_event
## kinds into one short line. Rules never see this text; a theme swap edits only the JSON strings.
## Keys missing from the theme fall back to the plain English in FALLBACK.

const FALLBACK := {
	"match_start": ["{name} goes first."],
	"roll": ["{name} rolls {total}."],
	"roll_bot": ["{name} rolls {total}."],
	"doubles": ["Doubles! {name} rolls again."],
	"passed_go": ["{name} passes GO: +{amount}."],
	"landed_unowned": ["{space} is for sale: {price}."],
	"bought": ["{name} buys {space}."],
	"auction_won": ["{name} wins {space} for {amount}."],
	"auction_unsold": ["No bids for {space}."],
	"rent_paid": ["{name} pays {owner} {amount}."],
	"rent_owed": ["{name} owes {owner} {amount} and must raise funds."],
	"tax": ["{name} pays {amount} tax."],
	"card_chance": ["{text}"],
	"card_community": ["{text}"],
	"jail_enter": ["{name} goes to jail."],
	"jail_exit_fine": ["{name} pays the fine and leaves jail."],
	"jail_exit_pardon": ["{name} uses a card to leave jail."],
	"jail_exit_doubles": ["{name} rolls doubles and leaves jail."],
	"jail_exit_forced": ["{name} pays the fine and leaves jail."],
	"bankrupt": ["{name} is bankrupt."],
	"trade_proposed": ["{name} offers {other} a trade."],
	"trade_accepted": ["{name} accepts the trade with {other}."],
	"trade_rejected": ["{name} rejects the trade."],
	"trade_countered": ["{name} makes a counter-offer."],
	"trade_withdrawn": ["{name} withdraws the offer."],
	"game_over": ["{name} wins!"],
}

var lines: Dictionary = {}
var rng := RandomNumberGenerator.new()


## Loads `path`, or the active theme's dialogue_path when empty. A missing file keeps FALLBACK only.
static func load_theme(path: String = "") -> DialogueLines:
	var d := DialogueLines.new()
	if path == "":
		path = String(UiStyle.theme_data().get("dialogue_path", ""))
	if path != "" and FileAccess.file_exists(path):
		var v: Variant = JsonData.load_json(path).get("lines", {})
		if v is Dictionary:
			d.lines = v
	return d


func has_key(key: String) -> bool:
	return lines.has(key) or FALLBACK.has(key)


## One variant for `key` with {placeholders} filled from vars; "" for an unknown key.
func line(key: String, vars: Dictionary = {}) -> String:
	var options: Variant = lines.get(key, FALLBACK.get(key, []))
	if not options is Array or (options as Array).is_empty():
		options = FALLBACK.get(key, [])
	if (options as Array).is_empty():
		return ""
	var pick: String = String(options[rng.randi_range(0, options.size() - 1)])
	return pick.format(vars)


## Line key and placeholder values for a TurnController.game_event, or {} when the event has no
## banner (moves are shown by the pawn instead).
static func describe(tc: TurnController, kind: StringName, info: Dictionary) -> Dictionary:
	var vars := {}
	var pid := int(info.get("player", -1))
	if pid >= 0 and pid < tc.players.size():
		vars["name"] = tc.players[pid].display_name
	var other := int(info.get("other", info.get("owner", -1)))
	if other >= 0 and other < tc.players.size():
		vars["other"] = tc.players[other].display_name
		vars["owner"] = vars["other"]
	if info.has("space"):
		vars["space"] = tc.board.spaces[int(info["space"])].display_name
	for k: String in ["amount", "price"]:
		if info.has(k):
			vars[k] = "$%d" % int(info[k])
	var key := ""
	match kind:
		&"rolled":
			vars["d1"] = info["d1"]
			vars["d2"] = info["d2"]
			vars["total"] = int(info["d1"]) + int(info["d2"])
			key = "roll_bot" if pid >= 0 and tc.players[pid].is_bot else "roll"
		&"passed_go", &"landed_unowned", &"bought", &"auction_won", &"auction_unsold", &"tax", &"bankrupt", \
		&"trade_proposed", &"trade_accepted", &"trade_rejected", &"trade_countered", &"trade_withdrawn", &"game_over":
			key = String(kind)
		&"rent":  # paid false: the rent became a debt (rules unchanged; the banner stops saying "pays")
			key = "rent_paid" if bool(info.get("paid", true)) else "rent_owed"
		&"card":
			vars["text"] = String(info.get("text", ""))
			vars["deck"] = tc.board.term(String(info.get("deck", "")))
			key = "card_chance" if StringName(info.get("deck", &"")) == tc.chance.deck_id else "card_community"
		&"jailed":
			key = "jail_enter"
		&"released":
			key = "jail_exit_" + String(info.get("how", "fine"))
		_:
			return {}
	return {"key": key, "vars": vars}


## The banner text for a game_event ("" when it has none).
func event_line(tc: TurnController, kind: StringName, info: Dictionary) -> String:
	var d := describe(tc, kind, info)
	return "" if d.is_empty() else line(String(d["key"]), d["vars"])
