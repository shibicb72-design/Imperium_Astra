class_name SetupPanel
extends PanelContainer
## Seat setup shown before a match (OPEN_QUESTIONS Q19): seat count (data/ui.json
## setup_seat_counts, 2-4), Human/Bot per seat, Start. Seat names come from the active pack's
## content overlay (seat_names) and colors from rules.json seat_pool, through GameSetup.seats_for;
## refresh_theme() relabels the seats after a pack switch. Start needs data/ui.json
## setup_min_humans people.
## The last choice is kept in user:// (save_path) so the next launch opens with it.
## Presentation only: emits start_requested(seats) and the owner builds the match.

signal start_requested(seats: Array[Dictionary])

const SECTION := "setup"

## ConfigFile path for the last choice; empty disables load/save (tests).
var save_path := "user://setup.cfg"

var count := 2
## One flag per offered seat (longest count); only the first `count` are used.
var bot_flags: Array[bool] = []

var _counts: Array[int] = []
var _scale := 0.0
var _margin: MarginContainer
var _count_buttons: Array[Button] = []
var _seat_rows: Array[Control] = []
var _seat_labels: Array[Label] = []
var _seat_toggles: Array[Button] = []
var _hint_label: Label
var _start_button: Button


## Builds the screen. `scale` is the DisplayScale factor (0 off-device / tests: no insets).
func setup(scale: float = 0.0) -> void:
	_scale = scale
	_counts = UiStyle.int_list("setup_seat_counts", [2, 3, 4])
	var max_count := 0
	for c in _counts:
		max_count = maxi(max_count, c)
	var defaults: Array = UiStyle.data().get("setup_default_bots", [])
	bot_flags.clear()
	for i in max_count:
		bot_flags.append(bool(defaults[i]) if i < defaults.size() else i > 0)
	count = int(UiStyle.num("setup_default_count", 2.0))
	if not count in _counts:
		count = _counts[0]
	_load()
	_build_ui()
	resized.connect(_apply_margins)
	_refresh()


func set_count(n: int) -> void:
	if not n in _counts:
		return
	count = n
	_refresh()


func set_bot(seat: int, is_bot: bool) -> void:
	if seat < 0 or seat >= bot_flags.size():
		return
	bot_flags[seat] = is_bot
	_refresh()


func human_count() -> int:
	var n := 0
	for i in count:
		if not bot_flags[i]:
			n += 1
	return n


## Enough people and a seat count GameSetup accepts. Names do not matter here, so the pack overlay
## is not read on every refresh.
func can_start() -> bool:
	var count_ok := not GameSetup.seats_for(bot_flags.slice(0, count)).is_empty()
	return count_ok and human_count() >= int(UiStyle.num("setup_min_humans", 1.0))


## Seat specs for GameSetup.new_game / GameState.new_local_game, in seat order, named by the
## active pack.
func seats() -> Array[Dictionary]:
	return GameSetup.seats_for(bot_flags.slice(0, count), UiStyle.content_overlay())


## Saves the choice and emits start_requested. Does nothing when the choice cannot start.
func start() -> void:
	if not can_start():
		return
	_save()
	start_requested.emit(seats())


## Rebuilds the screen from the active theme pack (after UiStyle.set_theme), keeping the seat choice.
func refresh_theme() -> void:
	for c in get_children():
		remove_child(c)
		if is_inside_tree():
			c.queue_free()  # a picker button inside may be mid-signal
		else:
			c.free()
	_count_buttons.clear()
	_seat_rows.clear()
	_seat_labels.clear()
	_seat_toggles.clear()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(StarfieldBackground.new())

	_margin = MarginContainer.new()
	add_child(_margin)
	_apply_margins()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_margin.add_child(box)

	UiStyle.label(box, "New match", "title")
	UiStyle.label(box, "Players", "small")
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 6)
	box.add_child(counts)
	var group := ButtonGroup.new()
	for c in _counts:
		var b := UiStyle.button(counts, str(c), set_count.bind(c))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_count_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var all_flags: Array[bool] = []
	all_flags.resize(bot_flags.size())
	all_flags.fill(false)
	var specs := GameSetup.seats_for(all_flags, UiStyle.content_overlay())
	for i in bot_flags.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var seat_label := UiStyle.label(row, "Seat %d" % (i + 1))
		seat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i < specs.size():
			seat_label.text = String(specs[i]["display_name"])
			seat_label.add_theme_color_override("font_color", Color.html(String(specs[i]["color"])))
		var toggle := UiStyle.button(row, "", Callable())
		toggle.custom_minimum_size.x = UiStyle.touch() * 3.0
		toggle.pressed.connect(func() -> void: set_bot(i, not bot_flags[i]))
		_seat_rows.append(row)
		_seat_labels.append(seat_label)
		_seat_toggles.append(toggle)

	_hint_label = UiStyle.label(box, "", "small")
	_start_button = UiStyle.button(box, "Start", start)


func _apply_margins() -> void:
	if _margin == null:
		return
	var insets := DisplayScale.safe_insets(_scale) if _scale > 0.0 else Vector4.ZERO
	var m := int(UiStyle.num("screen_margin", 8.0))
	_margin.add_theme_constant_override("margin_left", m + int(insets.x))
	_margin.add_theme_constant_override("margin_top", m + int(insets.y))
	_margin.add_theme_constant_override("margin_right", m + int(insets.z))
	_margin.add_theme_constant_override("margin_bottom", m + int(insets.w))


func _refresh() -> void:
	if _start_button == null:
		return
	for i in _counts.size():
		_count_buttons[i].set_pressed_no_signal(_counts[i] == count)
	for i in _seat_rows.size():
		_seat_rows[i].visible = i < count
		_seat_toggles[i].text = "Bot" if bot_flags[i] else "Human"
	var ok := can_start()
	_start_button.disabled = not ok
	var need := int(UiStyle.num("setup_min_humans", 1.0))
	_hint_label.text = "" if ok else "Make at least %d seat%s Human." % [need, "" if need == 1 else "s"]
	_hint_label.visible = not ok


func _load() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	var saved_count := int(cfg.get_value(SECTION, "count", count))
	if saved_count in _counts:
		count = saved_count
	var saved: Variant = cfg.get_value(SECTION, "bots", [])
	if saved is Array:
		for i in mini((saved as Array).size(), bot_flags.size()):
			if saved[i] is bool:
				bot_flags[i] = saved[i]


func _save() -> void:
	if save_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "count", count)
	cfg.set_value(SECTION, "bots", bot_flags.duplicate())
	cfg.save(save_path)
