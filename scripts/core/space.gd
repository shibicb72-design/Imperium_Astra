class_name Space
extends RefCounted
## One of the 40 board spaces (layout from data/board.json). Only display_name and short_name
## (compact board label, defaults to display_name) are theme data.

enum Type {
	GO, JAIL_CORNER, FREE_PARKING, GO_TO_JAIL, CHANCE, COMMUNITY_CHEST,
	INCOME_TAX, LUXURY_TAX, STREET, RAILROAD, UTILITY,
}

var index: int = 0
var space_type: Type = Type.GO
var display_name: String = ""
var short_name: String = ""
var color_group_id: StringName = &""
var list_price: int = 0
var tax_amount: int = 0
var deed: PropertyDeed = null


func is_property() -> bool:
	return space_type == Type.STREET or space_type == Type.RAILROAD or space_type == Type.UTILITY


static func type_from_string(s: String) -> Type:
	var t: int = Type.keys().find(s)
	if t < 0:
		push_error("Space: unknown space_type '%s'" % s)
		return Type.GO
	return t as Type
