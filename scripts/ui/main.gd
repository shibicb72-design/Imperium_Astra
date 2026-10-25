class_name Main
extends Control
## Local hotseat match screen, board-first (P5-FEEL Dig 5). MatchGate decides what shows, from the
## rules state and whether the board is still moving: while a person waits to roll, while the dice
## roll and while a piece moves, the play surface is the full board (it takes the full short side
## of the play area) and the die-ready look in its center is the roll affordance (die_pressed).
## Once the board settles, the floating TurnPanel shows the deciding seat's name and options (Buy /
## Skip / Action / End Turn, or the jail set before the roll); it never resizes the board. Bot turns
## stay chrome-free. One canvas unit is about 1 dp on mobile (DisplayScale). Input comes from
## touch/mouse buttons or InputMap actions only (roll_dice, buy_property, end_turn), all through the
## same gated handlers as the die and the panel.
##
## Dig 5a1 interim: the control column (turn header, cash chips, status line, pinned Auction / Debt
## banners, tabbed Holdings / Trade / Log on an opaque panel) shows only while a person owes a forced
## input (auction bid, debt, trade answer) or opened Action; the board then shares the screen with
## it (beside it in landscape, above it in portrait, data/ui.json board_max_share_*). Dig 5a2 turns
## those into board overlays.
##
## Motion and dialogue (P4-DEMO): TurnController.game_event feeds BoardView's animation queue
## (dice tumble, pawn hops, Brig jump) and the DialogueBanner over the board center (theme
## dialogue.json lines via DialogueLines). Banner lines are queued behind the pawn so they appear
## when it lands. Bots wait for the board and for a short banner backlog, then play on the bot timer.

enum Section { HOLDINGS, TRADE, LOG }

const SECTION_NAMES: Array[String] = ["Holdings", "Trade", "Log"]
const MIN_BOARD_SIDE := 160.0

## Optional injected match (tests); otherwise a new local game from GameState.
var controller: TurnController = null

## DisplayScale factor; 0 when started without a window (tests), which keeps insets at zero.
var _scale := 0.0
var _insets := Vector4.ZERO
var _margin: MarginContainer
var _box: BoxContainer
var _side: VBoxContainer
var _board_view: BoardView
var _turn_label: Label
var _player_labels: Array[Label] = []
var _status_label: Label
## Post-move / jail options floating over the screen (MatchGate panel states and game over).
var _turn_panel: TurnPanel
## Action view (OPEN_QUESTIONS Q24): Holdings / Trade / Log opened from the panel; Done closes it.
var _action_open := false
var _done_button: Button
var _auction_panel: AuctionPanel
var _debt_panel: DebtPanel
var _tab_buttons: Array[Button] = []
var _sections: Array[Control] = []
var _section: Section = Section.HOLDINGS
var _sections_open := true
var _section_holder: PanelContainer
var _holdings_panel: HoldingsPanel
var _trade_panel: TradePanel
var _log_label: Label
## Paces bot seats (TurnController.bot_step) so people can follow; data/ui.json bot_step_seconds.
var _bot_timer: Timer
var _banner: DialogueBanner
var _lines: DialogueLines
var _setup_panel: SetupPanel
var _starfield: StarfieldBackground


func _ready() -> void:
	if controller != null:
		start(get_window())
	else:
		show_setup(get_window())


## Seat setup first (OPEN_QUESTIONS Q19); its Start builds the match and opens the board.
func show_setup(window: Window) -> SetupPanel:
	if window != null:
		_scale = DisplayScale.apply(window)
	theme = UiStyle.make_theme()
	var panel := SetupPanel.new()
	_setup_panel = panel
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.setup(_scale)
	UiFx.fade_in(panel)
	panel.theme_requested.connect(select_theme)
	panel.start_requested.connect(func(seats: Array[Dictionary]) -> void:
		_setup_panel = null
		remove_child(panel)
		panel.queue_free()
		begin_match(seats, window))
	return panel


## Theme switch (P5-FEEL A4): selects registered pack `id` for this session and re-themes the
## setup screen. Supported only before match start; returns false (no change) once the match
## screen is built or for an unknown id.
func select_theme(id: String) -> bool:
	if _board_view != null:
		push_warning("Main.select_theme: theme switch is only supported before match start")
		return false
	if not UiStyle.set_theme(id):
		return false
	apply_theme()
	return true


## Re-applies the active pack to built UI: HUD Theme, dialogue lines, setup screen, starfield and
## board chrome. Panels styled at build time on the match screen are not rebuilt (no mid-match swap).
func apply_theme() -> void:
	theme = UiStyle.make_theme()
	_lines = DialogueLines.load_theme()
	if _setup_panel != null:
		_setup_panel.refresh_theme()
	if _starfield != null:
		_starfield.refresh_theme()
	if _board_view != null:
		_board_view.refresh_theme()


## New local match with the chosen seats (rng_seed < 0: random), then the board screen. The active
## pack's content overlay (terms, space / group names, card text) is applied here, at match start;
## the setup screen already named the seats from the same overlay (SetupPanel.seats()).
func begin_match(seats: Array[Dictionary], window: Window, rng_seed: int = -1) -> void:
	controller = GameSetup.new_game(rng_seed, seats, UiStyle.content_overlay())
	controller.determine_start_player()
	var gs := get_node_or_null("/root/GameState") if is_inside_tree() else null  # tests run outside the tree
	if gs != null:
		gs.controller = controller
	start(window)


## Builds the screen. Called from _ready; tests call it directly (window null: no DPI scaling).
func start(window: Window) -> void:
	if window != null:
		_scale = DisplayScale.apply(window)
	theme = UiStyle.make_theme()
	if controller == null:
		controller = GameState.new_local_game(-1, [], UiStyle.content_overlay())
	_build_ui()
	_bot_timer = Timer.new()
	_bot_timer.one_shot = true
	_bot_timer.wait_time = UiStyle.num("bot_step_seconds", 0.4)
	_bot_timer.timeout.connect(_on_bot_timer)
	add_child(_bot_timer)
	controller.state_changed.connect(_refresh)
	controller.status.connect(_on_status)
	controller.turn_started.connect(_on_turn_started)
	controller.debt_started.connect(_on_debt_started)
	controller.trade_proposed.connect(func(_o: Trade.Offer) -> void: show_section(Section.TRADE))
	controller.game_event.connect(_on_game_event)
	controller.doubles_extra_turn.connect(func(p: Player) -> void:
		_say_later(_lines.line("doubles", {"name": p.display_name}), p.color))
	_board_view.animate = is_inside_tree()
	_board_view.animation_finished.connect(_refresh, CONNECT_DEFERRED)
	_board_view.die_pressed.connect(press_die)
	_board_view.item_rect_changed.connect(_place_turn_panel)
	_turn_panel.slot_pressed.connect(press_slot)
	# Deferred: a line can be pushed mid-rule-step (e.g. inside auction resolution), when the
	# controller is between phases and bot_actor() must not be asked yet. A bound method, not a
	# lambda: queued calls are dropped once this Main is freed (a lambda keeps a raw self, so calls
	# queued before a test freed Main later ran against a dead instance).
	_banner.line_shown.connect(_schedule_bot.unbind(1), CONNECT_DEFERRED)
	_banner.emptied.connect(_schedule_bot, CONNECT_DEFERRED)
	resized.connect(_update_layout)
	_update_layout()
	if not controller.log_lines.is_empty():
		_on_status(controller.log_lines[-1])
	var first := controller.current_player()
	_banner.push(_lines.line("match_start", {"name": first.display_name}), first.color)
	_refresh()
	UiFx.fade_in(_margin)


## The InputMap actions go through the same gated handlers as the die and the turn panel.
func _unhandled_input(event: InputEvent) -> void:
	if controller == null or _board_view == null:
		return
	if event.is_action_pressed("roll_dice"):
		press_die()
	elif event.is_action_pressed("buy_property"):
		press_slot(&"buy")
	elif event.is_action_pressed("end_turn"):
		press_slot(&"end_turn")


## The gate state now (MatchGate): rules state plus whether the board is still moving.
func gate() -> MatchGate.State:
	return MatchGate.of(controller, is_busy())


## Die press or roll_dice: rolls only while the gate offers the die to a person (never while the
## board moves, for a bot, in another phase or with the Action view open). True if it rolled.
func press_die() -> bool:
	if _action_open or not MatchGate.die_live(gate()):
		return false
	_board_view.set_die_ready(false)
	controller.roll()
	_refresh()
	return true


## Turn panel option (or buy_property / end_turn): applied only when the gate state lists `slot`
## and it is legal now; the panel hides at once and the table decides what shows next.
func press_slot(slot: StringName) -> bool:
	if _action_open or not slot in MatchGate.panel_slots(gate()):
		return false
	if not _turn_panel.slot_shown(slot) or not _turn_panel.slot_enabled(slot):
		return false
	_turn_panel.visible = false
	match slot:
		&"buy":
			controller.buy()
		&"skip":
			controller.decline()
		&"end_turn":
			controller.end_turn()
		&"fine":
			controller.pay_jail_fine()
		&"pardon":
			controller.use_get_out_of_jail_card()
		&"action":
			open_action()
			return true
	_refresh()  # a refused call emits no state_changed; refresh anyway
	return true


## Action (Q24 placeholder): Holdings / Trade / Log for the deciding seat. Dig 5a1 interim: shown in
## the control column, which Done (close_action) hides again.
func open_action() -> void:
	_action_open = true
	_holdings_panel.set_actor(controller.deciding_player())
	show_section(Section.HOLDINGS)
	_refresh()


func close_action() -> void:
	_action_open = false
	_refresh()


func action_open() -> bool:
	return _action_open


## Board side for the play area in board-first play: the full short side.
static func board_side_for(avail: Vector2) -> float:
	return minf(avail.x, avail.y)


## Dig 5a1 interim, while the control column shows (forced input or Action): up to the full short
## side, but at most the data/ui.json share of the long side, so the column keeps room.
static func column_board_side_for(avail: Vector2) -> float:
	if avail.y > avail.x:
		return minf(avail.x, avail.y * UiStyle.num("board_max_share_portrait", 0.48))
	return minf(avail.y, avail.x * UiStyle.num("board_max_share_landscape", 0.58))


func _build_ui() -> void:
	_starfield = StarfieldBackground.new()
	add_child(_starfield)

	var m := int(UiStyle.num("screen_margin", 8.0))
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_apply_margins()

	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", m)
	_margin.add_child(_box)

	_board_view = BoardView.new()
	_board_view.size_flags_horizontal = Control.SIZE_FILL
	_board_view.size_flags_vertical = Control.SIZE_FILL
	_box.add_child(_board_view)
	_board_view.setup(controller)
	_lines = DialogueLines.load_theme()
	_banner = DialogueBanner.new()
	_board_view.add_child(_banner)  # floats over the board center; never changes the layout
	_board_view.resized.connect(_place_banner)

	var side := VBoxContainer.new()
	_side = side
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	_box.add_child(side)

	_turn_label = UiStyle.label(side, "", "title")
	var chips := HFlowContainer.new()
	side.add_child(chips)
	for p in controller.players:
		var l := UiStyle.label(chips, "", "small")
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_color_override("font_color", p.color)
		_player_labels.append(l)
	_status_label = UiStyle.label(side, "", "small")
	_status_label.max_lines_visible = 2

	_auction_panel = AuctionPanel.new()
	_auction_panel.setup(controller)
	side.add_child(_auction_panel)
	_debt_panel = DebtPanel.new()
	_debt_panel.setup(controller)
	side.add_child(_debt_panel)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	side.add_child(tabs)
	# Done (closes the Action view) leads the row, so a row wider than a narrow column never pushes
	# the only way back off screen.
	_done_button = UiStyle.button(tabs, "Done", close_action)
	_done_button.visible = false
	# No ButtonGroup: tapping the open tab again collapses the sections (toggle_tab).
	for i in SECTION_NAMES.size():
		var b := UiStyle.button(tabs, SECTION_NAMES[i], toggle_tab.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons.append(b)

	# Opaque, clipped backing so nothing behind the sections shows through.
	_section_holder = PanelContainer.new()
	_section_holder.add_theme_stylebox_override("panel", UiStyle.section_style())
	_section_holder.clip_contents = true
	_section_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_section_holder)
	var holder := VBoxContainer.new()
	_section_holder.add_child(holder)
	_holdings_panel = HoldingsPanel.new()
	_holdings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holdings_panel.setup(controller)
	_sections.append(_wrap_scroll(holder, _holdings_panel))
	_trade_panel = TradePanel.new()
	_trade_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_panel.setup(controller)
	holder.add_child(_trade_panel)
	_sections.append(_trade_panel)
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("font_size", UiStyle.font("small"))
	_sections.append(_wrap_scroll(holder, _log_label))
	show_section(Section.HOLDINGS)

	# Last child of Main: floats over the board and the column, outside every container.
	_turn_panel = TurnPanel.new()
	_turn_panel.setup(controller)
	add_child(_turn_panel)


func _wrap_scroll(parent: Control, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	parent.add_child(scroll)
	return scroll


## Opens a section (always; debt and trade offers force their section open).
func show_section(section: int) -> void:
	if section != _section or not _sections_open:
		UiFx.fade_in(_section_holder if not _sections_open else _sections[section],
			UiStyle.num("panel_fade_seconds", 0.18))
	_section = section as Section
	_sections_open = true
	_section_holder.visible = true
	for i in _sections.size():
		_sections[i].visible = i == section
		_tab_buttons[i].set_pressed_no_signal(i == section)
	if _section == Section.TRADE:
		_trade_panel.refresh()
	_update_layout()


## Tab tap: the open tab collapses the sections; any other tab opens its section.
func toggle_tab(section: int) -> void:
	if _sections_open and section == _section:
		collapse_sections()
	else:
		show_section(section)


## Hides the section area so the board gets the room back; no tab stays selected.
func collapse_sections() -> void:
	_sections_open = false
	_holdings_panel.close_picker()
	_section_holder.visible = false
	for b in _tab_buttons:
		b.set_pressed_no_signal(false)
	_update_layout()


func sections_open() -> bool:
	return _sections_open


## Margins = screen margin + safe-area insets, re-read on every layout so rotation moves them.
func _apply_margins() -> void:
	_insets = DisplayScale.safe_insets(_scale) if _scale > 0.0 else Vector4.ZERO
	var m := int(UiStyle.num("screen_margin", 8.0))
	_margin.add_theme_constant_override("margin_left", m + int(_insets.x))
	_margin.add_theme_constant_override("margin_top", m + int(_insets.y))
	_margin.add_theme_constant_override("margin_right", m + int(_insets.z))
	_margin.add_theme_constant_override("margin_bottom", m + int(_insets.w))


## The play area inside the screen margin and safe-area insets (Main-local).
func _play_rect() -> Rect2:
	var m := UiStyle.num("screen_margin", 8.0)
	var origin := Vector2(_insets.x + m, _insets.y + m)
	return Rect2(origin, size - origin - Vector2(_insets.z + m, _insets.w + m))


## Board-first: the board takes the full short side (top in portrait, left in landscape) and the
## turn panel floats in the free band or over it. Dig 5a1 interim, while the column shows: the board
## gives way to it (share of the long side; in portrait also the column's minimum height, so
## pinned buttons never fall off the bottom).
func _update_layout() -> void:
	if _box == null:
		return
	_apply_margins()
	var m := UiStyle.num("screen_margin", 8.0)
	var avail := _play_rect().size
	var portrait := avail.y > avail.x
	_box.vertical = portrait
	var board_side := board_side_for(avail)
	if _side.visible:
		board_side = column_board_side_for(avail)
		if portrait:
			var room := avail.y - _side.get_combined_minimum_size().y - m
			board_side = maxf(MIN_BOARD_SIDE, minf(board_side, room))
	_board_view.custom_minimum_size = Vector2(0, board_side) if portrait else Vector2(board_side, 0)
	_place_turn_panel()


## Floats the turn panel without moving the board (TurnPanel.rect_for: free band after the board,
## else the board center clear of the dialogue banner).
func _place_turn_panel() -> void:
	if _turn_panel == null or not _turn_panel.visible:
		return
	var offset := _margin.position + _box.position + _board_view.position
	var board := _board_view.board_rect()
	var banner := _board_view.banner_rect()
	var die := Rect2(offset + _board_view.die_hit_rect().position, _board_view.die_hit_rect().size) \
			if _board_view.die_ready else Rect2()
	var r := TurnPanel.rect_for(_play_rect(), Rect2(offset + board.position, board.size),
			Rect2(offset + banner.position, banner.size), _turn_panel.height_for(1), _turn_panel.height_for(2), die)
	_turn_panel.set_columns(2 if r.size.x >= TurnPanel.two_column_width() else 1)
	_turn_panel.position = r.position
	_turn_panel.size = r.size


## True when board + control column minimum heights fit the screen in portrait (tests: pinned
## rows stay on screen). Nothing to fit while the column is hidden.
func side_fits() -> bool:
	if not _box.vertical or not _side.visible:
		return true
	var m := UiStyle.num("screen_margin", 8.0)
	var avail_y := size.y - _insets.y - _insets.w - 2.0 * m
	return _board_view.custom_minimum_size.y + m + _side.get_combined_minimum_size().y <= avail_y + 0.5


## The debtor (maybe not the current player) becomes the Holdings actor so they can raise funds.
func _on_debt_started(debtor: Player, _creditor_id: int, _amount: int) -> void:
	_holdings_panel.set_actor(debtor.id)
	show_section(Section.HOLDINGS)


func _on_turn_started(p: Player) -> void:
	_holdings_panel.set_actor(p.id)
	UiFx.pulse(_turn_label)


## Presentation for one game event: dice and pawn motion go to the board queue; the matching
## banner line is queued behind them so it shows when the pawn lands.
func _on_game_event(kind: StringName, info: Dictionary) -> void:
	var pid := int(info.get("player", -1))
	match kind:
		&"built_house", &"built_hotel", &"sold_house", &"sold_hotel":
			_board_view.building_pop(int(info["space"]), kind in [&"sold_house", &"sold_hotel"],
				kind in [&"built_hotel", &"sold_hotel"], int(info.get("count", info.get("houses", 1))))
		&"bankrupt":
			_board_view.fade_out_piece(pid, UiStyle.num("bankrupt_fade_seconds", 0.8))
		&"rolled":
			_board_view.queue_dice(int(info["d1"]), int(info["d2"]))
		&"moved":
			_board_view.queue_move(pid, int(info["from"]), int(info["steps"]))
			return
		&"jailed":
			_board_view.queue_jump(pid, int(info["from"]), int(info["to"]))
	var color := controller.players[pid].color if pid >= 0 and pid < controller.players.size() else Color.TRANSPARENT
	_say_later(_lines.event_line(controller, kind, info), color)


## Banner line after everything the board has queued so far.
func _say_later(text: String, color: Color = Color.TRANSPARENT) -> void:
	if text == "":
		return
	_board_view.queue_call(func() -> void: _banner.push(text, color))


## The banner sits over the lower middle of the board center (BoardView.banner_rect).
func _place_banner() -> void:
	var r := _board_view.banner_rect()
	_banner.position = r.position
	_banner.size = r.size


## Dice or pieces still moving (MatchGate BUSY: the die and the turn panel wait).
func is_busy() -> bool:
	return _board_view.is_animating()


## Starts the bot timer when a bot must act (only in the live tree; tests drive bots directly).
## Bots also wait for the board to finish moving and for the banner backlog to shrink to
## data/ui.json bot_wait_banner_queue, so a spectator can follow; both always drain on their own.
func _schedule_bot() -> void:
	if not is_inside_tree() or not _bot_timer.is_stopped() or controller.bot_actor() < 0:
		return
	if is_busy() or _banner.queue_size() > int(UiStyle.num("bot_wait_banner_queue", 1)):
		return
	# Bot auction bids rise in small steps; a quicker pace keeps a bot-vs-bot auction short.
	var auction := controller.phase == TurnController.Phase.AUCTION
	_bot_timer.start(UiStyle.num("bot_auction_step_seconds" if auction else "bot_step_seconds", 0.1 if auction else 0.7))


func _on_bot_timer() -> void:
	if is_busy():  # something started moving since the timer was set; finishing it reschedules
		return
	if controller.bot_step():  # a failed step waits for the next state change instead of spinning
		_schedule_bot()


## Chip suffix: deeds held, buildings on them and pardon cards (" | 3 deeds, 2 bld"), "" when none.
func _holdings_summary(pl: Player) -> String:
	var deeds := 0
	var buildings := 0
	for s in controller.board.spaces:
		if s.deed != null and s.deed.owner == pl.id:
			deeds += 1
			buildings += 1 if s.deed.has_hotel else s.deed.houses
	var parts := PackedStringArray()
	if deeds > 0:
		parts.append("%d deed%s" % [deeds, "" if deeds == 1 else "s"])
	if buildings > 0:
		parts.append("%d bld" % buildings)
	if not pl.goojf_cards.is_empty():
		parts.append(controller.board.term("pardon"))
	return "" if parts.is_empty() else " | " + ", ".join(parts)


func _on_status(message: String) -> void:
	_status_label.text = message


func _refresh() -> void:
	var tc := controller
	var p := tc.current_player()
	var phase := tc.phase
	_turn_label.text = "> %s's turn  [%s]%s" % [p.display_name, "Bot" if p.is_bot else "Human",
		"  (in %s)" % tc.board.term("jail") if p.in_jail else ""]
	_turn_label.add_theme_color_override("font_color", p.color.lerp(Color.WHITE, 0.25))
	if phase == TurnController.Phase.GAME_OVER:
		_turn_label.text = "Game over"
		_turn_label.add_theme_color_override("font_color", UiStyle.color("accent"))
	for i in tc.players.size():
		var pl := tc.players[i]
		var mark := "> " if pl == p else ""
		var bot := " (bot)" if pl.is_bot else ""
		if pl.is_bankrupt:
			_player_labels[i].text = "%s%s: bankrupt" % [pl.display_name, bot]
		else:
			_player_labels[i].text = "%s%s%s $%d%s" % [mark, pl.display_name, bot, pl.cash, _holdings_summary(pl)]
	# Level-triggered gate (MatchGate): re-read here on every state change and once the board settles.
	var state := gate()
	if MatchGate.panel_slots(state).is_empty():
		_action_open = false  # Action lives in the panel states only (Q24)
	_side.visible = _action_open or MatchGate.is_forced(state)
	_done_button.visible = _action_open
	_board_view.set_die_ready(MatchGate.die_live(state) and not _action_open, p.color)
	_turn_panel.refresh(state, _action_open)
	_auction_panel.refresh()
	_debt_panel.refresh()
	_holdings_panel.refresh()
	_trade_panel.refresh()
	_tab_buttons[Section.TRADE].text = "Trade (offer)" if _trade_panel.has_open_offer() else "Trade"
	var lines := tc.log_lines.slice(-int(UiStyle.num("log_lines_shown", 60.0)))
	lines.reverse()
	_log_label.text = "\n".join(PackedStringArray(lines))
	_board_view.queue_redraw()
	_update_layout()
	_schedule_bot()
