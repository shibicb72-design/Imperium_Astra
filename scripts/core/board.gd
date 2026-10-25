class_name Board
extends RefCounted
## The 40-space loop, its color groups and the deeds on it (one Board per match).

const SPACE_COUNT := 40

var spaces: Array[Space] = []
## StringName group id -> Array[int] of street indices
var color_groups: Dictionary = {}
## StringName group id -> {"display_name": String, "color": Color}
var group_info: Dictionary = {}
## Theme words for buildings ("house", "houses", "hotel") used in log text; display data only.
var terms: Dictionary = {}


static func from_dict(d: Dictionary) -> Board:
	var b := Board.new()
	b.terms = d.get("terms", {})
	var groups: Dictionary = d.get("groups", {})
	for gid in groups:
		var g: Dictionary = groups[gid]
		b.group_info[StringName(gid)] = {
			"display_name": String(g.get("display_name", gid)),
			"color": Color.html(String(g.get("color", "#888888"))),
		}
	for sd in d.get("spaces", []):
		b.spaces.append(_space_from_dict(sd))
	for i in b.spaces.size():
		if b.spaces[i].index != i:
			push_error("Board: space %d has index %d" % [i, b.spaces[i].index])
		var s := b.spaces[i]
		if s.space_type == Space.Type.STREET:
			if not b.color_groups.has(s.color_group_id):
				var members: Array[int] = []
				b.color_groups[s.color_group_id] = members
			b.color_groups[s.color_group_id].append(i)
	if b.spaces.size() != SPACE_COUNT:
		push_error("Board: expected %d spaces, got %d" % [SPACE_COUNT, b.spaces.size()])
	return b


static func _space_from_dict(sd: Dictionary) -> Space:
	var s := Space.new()
	s.index = int(sd["index"])
	s.space_type = Space.type_from_string(String(sd["space_type"]))
	s.display_name = String(sd["display_name"])
	s.color_group_id = StringName(sd.get("color_group_id", ""))
	s.list_price = int(sd.get("list_price", 0))
	s.tax_amount = int(sd.get("tax_amount", 0))
	if s.is_property():
		var deed := PropertyDeed.new()
		deed.property_id = StringName(sd["property_id"])
		deed.space_index = s.index
		deed.color_group_id = s.color_group_id
		deed.list_price = s.list_price
		deed.mortgage_value = int(sd["mortgage_value"])
		deed.house_cost = int(sd.get("house_cost", 0))
		deed.hotel_cost = deed.house_cost
		for r in sd.get("rent", []):
			deed.rent_by_houses.append(int(r))
		s.deed = deed
	return s


func term(key: String) -> String:
	return String(terms.get(key, key))


func deed_at(index: int) -> PropertyDeed:
	return spaces[index].deed


func deeds_owned_by(player_id: int) -> Array[PropertyDeed]:
	var out: Array[PropertyDeed] = []
	for s in spaces:
		if s.deed != null and s.deed.owner == player_id:
			out.append(s.deed)
	return out


func count_owned(player_id: int, space_type: Space.Type) -> int:
	var n := 0
	for s in spaces:
		if s.space_type == space_type and s.deed.owner == player_id:
			n += 1
	return n


func owns_full_group(player_id: int, group_id: StringName) -> bool:
	if not color_groups.has(group_id):
		return false
	for i: int in color_groups[group_id]:
		if spaces[i].deed.owner != player_id:
			return false
	return true


## Next space of the given type strictly ahead of `from`, moving clockwise.
func next_index_of_type(from: int, space_type: Space.Type) -> int:
	for step in range(1, SPACE_COUNT + 1):
		var i := (from + step) % SPACE_COUNT
		if spaces[i].space_type == space_type:
			return i
	return from
