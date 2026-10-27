extends TestCase
## Pass A presentation contracts; no live tree, timers or physics required.

func teardown() -> void:
	UiStyle.reset_theme()


func test_victory_gates_winner_panel_and_snaps() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = GameSetup.new_game(7)
	main.start(null)
	var view := main._board_view
	view.animate = true
	main.controller.players[1].is_bankrupt = true
	main.controller.phase = TurnController.Phase.GAME_OVER
	main._on_game_event(&"game_over", {"player": 0})
	main._refresh()
	check(main.is_busy() and not main._turn_panel.visible and not view.die_ready, "victory gates the winner panel")
	view.advance(0.3)
	check(view.piece_state(0).lift > 0.3, "first winner hop")
	view.advance(0.6)
	check(view.piece_state(0).lift > 0.2, "second winner hop")
	check(view.victory_pose().laurel > 0.0, "laurel grows after sweep")
	view.advance(10.0)
	main._refresh()
	check(not main.is_busy() and main._turn_panel.visible, "winner panel after victory")
	check(not main._turn_panel._name.text.contains("$"), "winner name without cash totals")
	view.animate = false
	view.queue_victory(0)
	check(not main.is_busy(), "headless victory snaps")
	main.free()
	done()


func test_every_pass_a_fx_in_registered_packs() -> void:
	for pack in UiStyle.theme_packs():
		UiStyle.set_theme(String(pack.id))
		var view := BoardView.new()
		view.setup(GameSetup.new_game(7, [], UiStyle.content_overlay()))
		view.size = Vector2(660, 660)
		view.animate = true
		for kind in [&"claim_bar", &"gavel", &"anchor", &"gate_arrival", &"gate_count", &"victory", &"cash_fly"]:
			view.queue_fx(kind, {"player": 0, "space": 5, "owner": 1, "spaces": [5, 15], "amount": 100, "to": &"bank"}, 1.0)
			view.advance(0.5)
			check(view.fx_pose(kind).active, "pack samples " + String(kind))
			if kind == &"cash_fly":
				check(view.cash_fly_pose().active, "pack samples cash arc")
			view.advance(1.0)
			check(not view.is_animating(), "pack drains " + String(kind))
		view.queue_move(0, 37, 5, true, 200)
		view.advance(10.0)
		check_eq(view.shown_position(0), view.controller.players[0].position, "same final snap state across packs")
		view.free()
	done()


func test_railroad_arrival_claim_and_double_toll() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = GameSetup.new_game(7, GameSetup.seats(2, 0))
	main.start(null)
	var tc := main.controller
	var view := main._board_view
	view.animate = true
	tc.board.deed_at(5).owner = 1
	tc.board.deed_at(15).owner = 1
	view.queue_move(0, 4, 1, true)
	view.advance(UiStyle.num("pawn_step_seconds", 0.14))
	check(view.fx_pose(&"gate_arrival").active, "gate arrival ring before card")
	view.advance(10.0)
	var base := Rules.railroad_rent(tc.board, tc.board.deed_at(5), tc.config)
	main._on_game_event(&"rent", {"player": 0, "owner": 1, "space": 5, "amount": base * 2, "paid": true})
	check(view.cash_fly_pose().info.double, "card double toll gets two rings")
	check(not view.cash_fly_pose().failed, "paid toll flies")
	view.advance(10.0)
	main._on_game_event(&"rent", {"player": 0, "owner": 1, "space": 5, "amount": base, "paid": false})
	check(view.cash_fly_pose().failed, "unpaid toll returns")
	check(not view.cash_fly_pose().info.double, "normal toll has one ring")
	view.advance(10.0)
	main._on_game_event(&"bought", {"player": 1, "space": 15, "price": 200})
	view.advance(UiStyle.num("claim_seconds", 0.35))
	check_eq(view.fx_pose(&"gate_count").info.spaces, [5, 15], "claimed owner's gates blink in board order")
	view.advance(10.0)
	check(not view.is_animating(), "gate FX drain")
	main.free()
	done()


func test_anchor_before_card_without_money() -> void:
	var view := BoardView.new()
	view.setup(GameSetup.new_game(7))
	view.animate = true
	var cash := view.controller.players[0].cash
	view.queue_move(0, 19, 1, true)
	view.advance(UiStyle.num("pawn_step_seconds", 0.14))
	check(view.anchor_pose().active, "arrival starts rest before card")
	check(not view.anchor_pose().info.has("amount"), "rest has no money payload")
	view.advance(UiStyle.num("anchor_seconds", 0.6) * 0.25)
	check(view.piece_state(0).lift > 0, "soft settle is analytic")
	view.advance(UiStyle.num("anchor_seconds", 0.6))
	check(view.land_card_pose().active, "name card after rest")
	check_eq(view.controller.players[0].cash, cash, "rest pays nothing")
	view.advance(10.0)
	check(not view.is_animating(), "rest releases busy")
	view.animate = false
	view.queue_move(0, 19, 1, true)
	check(not view.is_animating(), "headless rest snaps")
	view.free()
	done()


func test_tax_paid_and_debt_routes_are_honest() -> void:
	for amount in [200, 100]:
		for failed in [false, true]:
			var main: Main = load("res://scenes/main.tscn").instantiate()
			main.controller = GameSetup.new_game(7, GameSetup.seats(2, 0))
			main.start(null)
			var tc := main.controller
			var view := main._board_view
			view.animate = true
			var index := 4 if amount == 200 else 38
			tc.players[0].cash = 0 if failed else 500
			tc.players[0].position = index
			view.sync_to_game()
			tc._resolve_space(tc.players[0], {})
			tc._continue()
			view.advance(0.2)
			var cash := view.cash_fly_pose()
			check(cash.active, "tax queues shared cash fly")
			check_eq(cash.failed, failed, "debt sampled after tax charge")
			check_eq(cash.info.amount, amount, "event amount only")
			check_eq(tc.players[0].cash, 0 if failed else 500 - amount, "FX does not alter money")
			view.advance(10.0)
			check(not view.is_animating(), "tax gate drains")
			main._refresh()
			check_eq(main._overlay.visible, failed, "debt overlay only after fly")
			main.free()
	done()


func test_go_crossing_inside_move_and_snap() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = GameSetup.new_game(7)
	main.start(null)
	var view := main._board_view
	view.animate = true
	main._on_game_event(&"moved", {"player": 0, "from": 37, "steps": 5})
	var duration: float = view._item.dur
	check(not view.go_crossing_pose().active, "no salary before crossing")
	view.advance(UiStyle.num("pawn_step_seconds", 0.14) * 2.5)
	check(view.go_crossing_pose().active, "crossing beat at 39 to 0")
	check_eq(view.go_crossing_pose().amount, main.controller.config.go_salary, "salary read only")
	check_eq(view._item.dur, duration, "crossing does not extend move")
	view.advance(duration)
	check_eq(view.shown_position(0), 2, "final position after crossing")
	check(view.land_card_pose().active, "only final arrival gets card")
	view.advance(10.0)
	view.queue_move(0, 2, -3, false, 200)
	view.advance(0.2)
	check(not view.go_crossing_pose().active, "no salary beat backward")
	view.advance(10.0)
	view.queue_move(0, 39, 1, true, 200)
	view.advance(0.07)
	check(view.go_crossing_pose().active, "exact GO landing pays once")
	view.advance(10.0)
	view.animate = false
	view.queue_move(0, 37, 5, true, 200)
	check_eq(view.shown_position(0), 2, "headless crossing snaps")
	check(not view.is_animating(), "no orphan beat")
	main.free()
	done()


func test_claim_and_auction_main_routes() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = GameSetup.new_game(7, GameSetup.seats(2, 0))
	main.start(null)
	var view := main._board_view
	view.animate = true
	main._on_game_event(&"bought", {"player": 0, "space": 1, "price": 60})
	check(view.fx_pose(&"claim_bar").active and main.is_busy(), "claim gates the panel")
	view.advance(UiStyle.num("claim_seconds", 0.35) * 0.5)
	check(view.piece_state(0).lift > 0.0, "claim hops the Node2D follower")
	view.advance(UiStyle.num("claim_seconds", 0.35) * 0.5)
	check(view.cash_fly_pose().active, "cash follows paint")
	view.advance(10.0)
	main.controller.auction_started.emit(1)
	check(view.fx_pose(&"gavel").active, "signal is connected to gavel")
	main._refresh()
	check(not main._overlay.visible, "overlay waits for gavel")
	view.advance(10.0)
	check(not main.is_busy(), "gavel drains")
	view.animate = false
	main._on_game_event(&"bought", {"player": 0, "space": 1, "price": 60})
	main.controller.auction_started.emit(1)
	check(not main.is_busy(), "headless routes snap")
	main.free()
	done()


func test_land_card_type_chrome_and_snapshot() -> void:
	for pack in UiStyle.theme_packs():
		UiStyle.set_theme(String(pack.id))
		var view := BoardView.new()
		view.setup(GameSetup.new_game(7, [], UiStyle.content_overlay()))
		view.animate = true
		check(view.land_card_chrome(Space.Type.STREET).stripe != view.land_card_chrome(Space.Type.INCOME_TAX).stripe, "street and tax differ")
		check(view.land_card_chrome(Space.Type.CHANCE).stripe != view.land_card_chrome(Space.Type.INCOME_TAX).stripe, "deck and tax differ")
		var deed := view.controller.board.deed_at(1)
		deed.owner = 0
		deed.houses = 2
		view.queue_land_card(1)
		check_eq(view._item.owner_color, view.controller.players[0].color, "seat stripe snapshot")
		check(view.land_card_pose().text.contains(view.controller.board.term("houses")), "building content")
		view.advance(10.0)
		check(not view.is_animating(), "card releases busy")
		view.free()
	done()


func test_dice_feedback_in_both_packs() -> void:
	for pack in UiStyle.theme_packs():
		UiStyle.set_theme(String(pack.id))
		for key in ["accent", "accent_dim", "alert", "panel", "text", "text_muted", "dice_face", "dice_pip"]:
			check(UiStyle.theme_data().colors.has(key), "FX palette key exists: " + key)
		var view := BoardView.new()
		view.setup(GameSetup.new_game(7, [], UiStyle.content_overlay()))
		view.size = Vector2(660, 660)
		view.set_die_ready(true, view.controller.players[0].color)
		view._process(0.4)
		check(not view.is_animating(), "idle breathe never blocks the gate")
		view.animate = true
		view.queue_dice(4, 4, true)
		var duration := UiStyle.num("dice_roll_seconds", 0.55)
		view.advance(duration * 0.04)
		check(view.dice_pose(0).scale.y < 1.0, "press compresses")
		view.advance(duration * 0.90)
		check_eq(view._faces(), Vector2i(4, 4), "final settle locks real faces")
		check(view.dice_pose(0).pip_scale > 1.0, "pips overshoot at settle")
		check(view.dice_pose(0).glint > 0.0, "doubles glint at settle")
		view.advance(duration)
		check_eq(view.shown_dice(), Vector2i(4, 4), "same final faces in every pack")
		check(not view.is_animating(), "dice release the gate")
		view.free()
	done()
