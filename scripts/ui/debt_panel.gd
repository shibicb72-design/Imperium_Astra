class_name DebtPanel
extends PanelContainer
## Raise-funds banner (core module: Bankruptcy). Visible only in the RAISING_FUNDS phase and
## pinned above the scrolling sections, so Pay and Declare Bankruptcy are always on screen; the
## debtor sells buildings / mortgages in the Holdings section, then pays or declares bankruptcy.

const ALERT_COLOR := Color("#ff9a8a")

var _controller: TurnController
var _info: Label
var _pay_button: Button
var _bankrupt_button: Button


func setup(controller: TurnController) -> void:
	_controller = controller
	add_theme_stylebox_override("panel", UiStyle.card_style(ALERT_COLOR))
	var v := VBoxContainer.new()
	add_child(v)
	_info = UiStyle.label(v, "", "body")
	var row := HFlowContainer.new()
	v.add_child(row)
	_pay_button = UiStyle.button(row, "Pay Debt", func() -> void: _controller.pay_debt())
	_bankrupt_button = UiStyle.button(row, "Declare Bankruptcy", func() -> void: _controller.declare_bankruptcy())


func refresh() -> void:
	var debt := _controller.current_debt()
	visible = _controller.phase == TurnController.Phase.RAISING_FUNDS and debt != null
	if not visible:
		return
	var tc := _controller
	var debtor := tc.players[debt.debtor]
	var creditor := tc.board.term("bank") if debt.creditor == PropertyDeed.BANK else tc.players[debt.creditor].display_name
	_info.text = "%s owes %s $%d (cash $%d, could raise $%d).\nSell or mortgage in Holdings, then pay." % [
		debtor.display_name, creditor, debt.amount, debtor.cash,
		Bankruptcy.max_raisable(tc.board, debtor, tc.config)]
	_pay_button.text = "Pay $%d (%s)" % [debt.amount, debtor.display_name]
	_pay_button.disabled = debtor.cash < debt.amount
	_bankrupt_button.disabled = not tc.can_declare_bankruptcy()
