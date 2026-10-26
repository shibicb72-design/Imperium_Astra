extends TestCase

func test_dice_multi_hop_and_snap() -> void:
	var view := BoardView.new()
	view.setup(GameSetup.new_game(7))
	view.size = Vector2(660, 660)
	view.animate = true
	view.queue_dice(2, 5)
	var duration := UiStyle.num("dice_roll_seconds", 0.55)
	check(view.has_method("dice_pose"), "dice expose the same hop pose used by drawing")
	var peaks := [0.0, 0.0]
	var contacts := [0, 0]
	var was_airborne := [false, false]
	var impact := false
	for sample in range(101):
		if sample > 0:
			view.advance(duration / 100.0)
		for die in range(2):
			var pose: Dictionary = view.call("dice_pose", die) if view.has_method("dice_pose") else {"lift": 0.0, "scale": Vector2.ONE}
			var lift: float = pose.lift
			if sample == 0:
				check_eq(lift, 0.0, "roll starts on the ground")
			if view.has_method("dice_pose"):
				var r := view.dice_rect()
				check(absf(pose.point.y - (r.get_center().y - lift)) < 0.001,
					"drawn center follows hop height")
			peaks[die] = maxf(peaks[die], lift)
			if was_airborne[die] and lift <= 0.001:
				contacts[die] += 1
			was_airborne[die] = lift > 0.001
			impact = impact or (lift == 0.0 and pose.scale.x > 1.05)
	for die in range(2):
		check(peaks[die] >= 0.25 * 60.0, "each die has a readable apex")
		check(contacts[die] >= 2, "multiple arcs and landings ban a single slide tween")
	check(impact, "landing includes squash impact")
	view.advance(duration)
	check_eq(view.shown_dice(), Vector2i(2, 5), "forced faces settle")
	if view.has_method("dice_pose"):
		check_eq(view.call("dice_pose", 0).lift, 0.0, "end returns to rest")
	view.animate = false
	view.queue_dice(6, 1)
	check(not view.is_animating(), "nonanimated roll snaps")
	check_eq(view.shown_dice(), Vector2i(6, 1), "snap retains forced faces")
	view.free()
	done()
