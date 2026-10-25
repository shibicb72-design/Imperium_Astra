class_name AuctionPanel
extends PanelContainer
## Auction banner (core module: Auction). Visible only in the AUCTION phase and pinned above
## the scrolling sections, so the bid and Drop Out buttons are always on screen. Quick-bid raise
## steps come from data/ui.json; the legal minimum always comes from the rules.

var _controller: TurnController
var _info: Label
var _steps: Array[int] = []
var _bid_buttons: Array[Button] = []
var _pass_button: Button


func setup(controller: TurnController) -> void:
	_controller = controller
	_steps = UiStyle.int_list("auction_quick_bid_steps", [1])
	add_theme_stylebox_override("panel", UiStyle.card_style(BoardView.GOLD))
	var v := VBoxContainer.new()
	add_child(v)
	_info = UiStyle.label(v, "", "body")
	var row := HFlowContainer.new()
	v.add_child(row)
	for i in _steps.size():
		var b := UiStyle.button(row, "", _on_bid.bind(i))
		b.custom_minimum_size.x = UiStyle.touch() * 2.0
		_bid_buttons.append(b)
	_pass_button = UiStyle.button(row, "Drop Out", func() -> void: _controller.auction_pass())


## Amount for quick-bid button i: the current high bid plus the step, never below the legal minimum.
func _bid_amount(i: int) -> int:
	var a := _controller.auction
	var base := a.high_bid if a.has_winner() else 0
	return maxi(a.min_next_bid(), base + _steps[i])


func _on_bid(i: int) -> void:
	if _controller.auction != null:
		_controller.auction_bid(_bid_amount(i))


func refresh() -> void:
	var a := _controller.auction
	visible = _controller.phase == TurnController.Phase.AUCTION and a != null
	if not visible:
		return
	var s := _controller.board.spaces[a.space_index]
	var bidder := _controller.players[a.current_bidder()]
	var high := "No bids yet (opening $%d)" % a.min_bid
	if a.has_winner():
		high = "High bid $%d by %s" % [a.high_bid, _controller.players[a.high_bidder].display_name]
	_info.text = "Auction: %s (list $%d)\n%s\n%s to bid (cash $%d)" % [
		s.display_name, s.deed.list_price, high, bidder.display_name, bidder.cash]
	var last := -1
	for i in _bid_buttons.size():
		var amount := _bid_amount(i)
		var b := _bid_buttons[i]
		b.text = "Bid $%d" % amount
		b.visible = amount != last
		b.disabled = amount > bidder.cash or bidder.is_bot
		last = amount
	_pass_button.text = "Drop Out (%s)" % bidder.display_name
	_pass_button.disabled = bidder.is_bot  # bots bid on their own (TurnController.bot_step)
