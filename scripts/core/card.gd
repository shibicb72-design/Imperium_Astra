class_name Card
extends RefCounted
## A Mission Brief (Chance) or Senate Dispatch (Community Chest) card: theme text + stable opcode.

var card_id: StringName = &""
var deck_id: StringName = &""
var text: String = ""
var opcode: StringName = &""
var params: Dictionary = {}


static func from_dict(deck: StringName, d: Dictionary) -> Card:
	var c := Card.new()
	c.card_id = StringName(d["card_id"])
	c.deck_id = deck
	c.text = String(d["text"])
	c.opcode = StringName(d["opcode"])
	c.params = d.get("params", {})
	return c


func is_goojf() -> bool:
	return opcode == &"GOOJF"
