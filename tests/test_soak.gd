extends TestCase
## Plays many seeded random turns (buy when affordable, otherwise pass) to exercise every
## space and card path; the runner's done() check catches runtime script errors.

const P := TurnController.Phase


func test_random_play_keeps_invariants() -> void:
	for game_seed in [1, 2, 3, 4, 5]:
		var tc := GameSetup.new_game(game_seed)
		tc.determine_start_player()
		for step in 600:
			var p := tc.current_player()
			match tc.phase:
				P.AWAITING_ROLL:
					if p.in_jail and p.cash >= 500 and step % 2 == 0:
						tc.pay_jail_fine()
					tc.roll()
				P.AWAITING_BUY_DECISION:
					if not tc.buy():
						tc.decline()
				P.AWAITING_END_TURN:
					tc.end_turn()
				P.GAME_OVER:
					break
			check(p.position >= 0 and p.position < 40, "position in range")
			check(tc.chance.draw_pile.size() + _held(tc, &"chance") == 16, "chance cards conserved")
			check(tc.community_chest.draw_pile.size() + _held(tc, &"community_chest") == 16, "dispatch cards conserved")
		var owned := 0
		for pl in tc.players:
			owned += tc.board.deeds_owned_by(pl.id).size()
		check(owned > 0, "some deeds bought (seed %d)" % game_seed)
	done()


func _held(tc: TurnController, deck: StringName) -> int:
	var n := 0
	for pl in tc.players:
		for c in pl.goojf_cards:
			if c.deck_id == deck:
				n += 1
	return n
