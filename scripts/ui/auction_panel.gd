class_name AuctionPanel
extends VBoxContainer
## Auction controls (core module: Auction). Visible only in the AUCTION phase. Quick-bid raise
## steps come from data/ui.json; the legal minimum always comes from the rules.

const UI_PATH := "res://data/ui.json"
const BUTTON_MIN_HEIGHT := 56.0

var _controller: TurnController
var _info: Label
var _steps: Array[int] = []
var _bid_buttons: Array[Button] = []
var _pass_button: Button


func setup(controller: TurnController) -> void:
	_controller = controller
	for v in JsonData.load_json(UI_PATH).get("auction_quick_bid_steps", [1]):
		_steps.append(int(v))
	add_theme_constant_override("separation", 6)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	var row := HFlowContainer.new()
	add_child(row)
	for i in _steps.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, BUTTON_MIN_HEIGHT)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_bid.bind(i))
		row.add_child(b)
		_bid_buttons.append(b)
	_pass_button = Button.new()
	_pass_button.text = "Drop Out"
	_pass_button.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	_pass_button.add_theme_font_size_override("font_size", 18)
	_pass_button.pressed.connect(func() -> void: _controller.auction_pass())
	add_child(_pass_button)


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
	var high := "no bids yet (opening $%d)" % a.min_bid
	if a.has_winner():
		high = "high bid $%d by %s" % [a.high_bid, _controller.players[a.high_bidder].display_name]
	_info.text = "Auction: %s (list $%d)\n%s\n%s to bid (cash $%d)" % [
		s.display_name, s.deed.list_price, high, bidder.display_name, bidder.cash]
	var last := -1
	for i in _bid_buttons.size():
		var amount := _bid_amount(i)
		var b := _bid_buttons[i]
		b.text = "Bid $%d" % amount
		b.visible = amount != last
		b.disabled = amount > bidder.cash
		last = amount
