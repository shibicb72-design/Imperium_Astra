class_name NetWorth
extends RefCounted
## A seat's net worth, shown per seat by the side panel (P5 SIDE_PANEL_A1). Pure static, no UI; one
## function so the definition can be swapped.
##
## Default (Shibi Oct 29 2026, Q-networth-definition; `_placeholder` until confirmed): what the seat
## could raise now, cash + the sell-back value of its buildings + the mortgage value of each
## unmortgaged deed, the same sum as Bankruptcy.max_raisable (the number the debt overlay calls
## "could raise"). So it drops on every purchase and build (a deed adds only its mortgage value, a
## house only its sell-back value), counts mortgaged deeds and pardon cards as 0, does not subtract a
## pending debt, stays the same on mortgaging and falls by the 10% interest when a mortgage is lifted.
## TODO(Q-networth-definition): the "list-price" alternative is not chosen without Shibi.


static func of(board: Board, player: Player, config: RulesConfig) -> int:
	return Bankruptcy.max_raisable(board, player, config)
