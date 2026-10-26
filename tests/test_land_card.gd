extends TestCase

func teardown() -> void:
	UiStyle.reset_theme()


func test_main_arrival_queues_land_card() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.controller = GameSetup.new_game(7)
	main.start(null)
	main._board_view.animate = true
	main._on_game_event(&"moved", {"player": 0, "from": 0, "steps": 1})
	check(not main._board_view.land_card_pose().active, "no card before arrival")
	main._board_view.advance(0.15)
	check(main._board_view.land_card_pose().active and main.is_busy(), "Main arrival activates card and gate")
	main._board_view.advance(3.0)
	check(not main.is_busy(), "card exit releases Main gate")
	main.free()
	done()


func test_land_card_pack_queue_and_placement() -> void:
	for pack in ["imperium_astra", "astra_alt"]:
		UiStyle.set_theme(pack)
		var view := BoardView.new()
		view.setup(GameSetup.new_game(7, [], UiStyle.content_overlay()))
		view.animate = true
		for side in [360.0, 411.0, 660.0]:
			view.size = Vector2(side, side)
			var r := view.land_card_rect()
			check(not r.intersects(view.die_hit_rect()), "card rests clear of dice")
			check(not r.intersects(view.banner_rect()), "banner reservation unchanged and clear")
		view.queue_move(0, 0, 1, true)
		view.queue_move(0, 1, 3, true)
		var observed: Array[int] = []
		view.queue_call(func() -> void: observed.append(view.shown_position(0)))
		view.advance(0.14)
		check(view.land_card_pose().text.contains(view.controller.board.spaces[1].display_name), "active pack name")
		view.advance(UiStyle.num("land_card_seconds", 2.6) + 0.43)
		check(view.land_card_pose().text.contains(view.controller.board.spaces[4].display_name), "next card replaces first cleanly")
		check(observed.is_empty(), "callback and turn gate wait for second card")
		view.advance(10.0)
		check_eq(observed, [4], "callback runs after all cards")
		view.sync_to_game()
		check(not view.land_card_pose().active, "reset clears card")
		view.free()
	done()


func test_land_card_motion_and_content() -> void:
	var view := BoardView.new()
	view.setup(GameSetup.new_game(7))
	view.size = Vector2(660, 660)
	view.animate = true
	view.queue_move(0, 0, 1, true)
	view.advance(0.14)
	check(view.has_method("land_card_pose"), "landing exposes an active pixel card")
	if not view.has_method("land_card_pose"):
		view.free()
		done()
		return
	var pose: Dictionary = view.call("land_card_pose")
	check(pose.active, "card begins after pawn arrival")
	check(pose.text.contains(view.controller.board.spaces[1].display_name), "space name")
	check(pose.text.contains("60") and pose.text.contains("Rent"), "deed price and rent ladder")
	var seconds := UiStyle.num("land_card_seconds", 0.0)
	check(seconds >= 2.0 and seconds <= 3.0, "card duration in reading band")
	var peaks := 0.0
	var impacts := false
	var rest := false
	var exit_motion := false
	for i in range(100):
		view.advance(seconds / 100.0)
		pose = view.call("land_card_pose")
		if pose.active:
			peaks = maxf(peaks, pose.lift)
			impacts = impacts or pose.scale.x > 1.1
			rest = rest or (pose.scale == Vector2.ONE and pose.lift == 0.0)
			exit_motion = exit_motion or (i > 85 and absf(pose.rotation) > 0.1)
	check(peaks > 20.0 and impacts and rest and exit_motion, "arc, impact, settle, exit ban cheap-only motion")
	view.advance(0.1)
	check(not view.call("land_card_pose").active and not view.is_animating(), "dismiss releases queue")
	view.queue_move(0, 1, 3, true)
	view.advance(0.43)
	check(view.call("land_card_pose").text.contains("200"), "tax reads board amount")
	view.animate = false
	view.advance(0.01)
	check(not view.call("land_card_pose").active, "animation off dismisses immediately")
	view.queue_move(0, 4, 1, true)
	check(not view.is_animating(), "nonanimated landing skips card")
	view.free()
	done()

