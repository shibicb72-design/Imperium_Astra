class_name PropertyDeed
extends RefCounted
## Title deed for a street, jump gate (railroad) or utility. Prices are fixed data; owner,
## mortgage and buildings are per-match state.

const BANK := -1

var property_id: StringName = &""
var space_index: int = 0
var color_group_id: StringName = &""
var list_price: int = 0
var mortgage_value: int = 0
var house_cost: int = 0
var hotel_cost: int = 0
## [0 houses, 1, 2, 3, 4, hotel]; empty for railroads and utilities.
var rent_by_houses: Array[int] = []

var owner: int = BANK  ## player id, or BANK
var is_mortgaged: bool = false
var houses: int = 0  ## 0-4; ignored when has_hotel
var has_hotel: bool = false
