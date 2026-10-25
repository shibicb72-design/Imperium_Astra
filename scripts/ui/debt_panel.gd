class_name DebtPanel
extends VBoxContainer
## Raise-funds controls (core module: Bankruptcy). Visible only in the RAISING_FUNDS phase; the
## debtor sells buildings / mortgages in the Holdings panel, then pays or declares bankruptcy.

const BUTTON_MIN_HEIGHT := 56.0

var _controller: TurnController
var _info: Label
var _pay_button: Button
var _bankrupt_button: Button


func setup(controller: TurnController) -> void:
	_controller = controller
	add_theme_constant_override("separation", 6)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_pay_button = _make_button("Pay Debt", func() -> void: _controller.pay_debt())
	_bankrupt_button = _make_button("Declare Bankruptcy", func() -> void: _controller.declare_bankruptcy())


func _make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_MIN_HEIGHT)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	add_child(b)
	return b


func refresh() -> void:
	var debt := _controller.current_debt()
	visible = _controller.phase == TurnController.Phase.RAISING_FUNDS and debt != null
	if not visible:
		return
	var tc := _controller
	var debtor := tc.players[debt.debtor]
	var creditor := "the Bank" if debt.creditor == PropertyDeed.BANK else tc.players[debt.creditor].display_name
	_info.text = "%s owes %s $%d (cash $%d, could raise $%d).\nSell buildings or mortgage below, then pay." % [
		debtor.display_name, creditor, debt.amount, debtor.cash,
		Bankruptcy.max_raisable(tc.board, debtor, tc.config)]
	_pay_button.disabled = debtor.cash < debt.amount
	_bankrupt_button.disabled = not tc.can_declare_bankruptcy()
