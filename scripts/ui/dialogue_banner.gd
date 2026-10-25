class_name DialogueBanner
extends PanelContainer
## Event banner: shows one short line at a time over the board center, then the next queued one.
## Each line auto-dismisses after data/ui.json banner_seconds (banner_backlog_seconds while more
## are waiting); a tap dismisses it at once. At most banner_max_queue lines wait; the oldest
## waiting line is dropped beyond that, so the banner never falls far behind the game. Purely
## visual: rules never wait on it (Main only lets bots pause while the backlog is long, and the
## timer always drains it). The queue logic runs through advance(), so tests drive it headless.

signal line_shown(text: String)
signal emptied

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _left := 0.0
var _label: Label


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", UiStyle.font("body"))
	_label.add_theme_color_override("font_color", UiStyle.color("text"))
	add_child(_label)
	add_theme_stylebox_override("panel", UiStyle.card_style(UiStyle.color("accent")))


## Queues a line; `accent` tints the banner edge (e.g. the acting commander's color).
func push(text: String, accent: Color = Color.TRANSPARENT) -> void:
	if text == "":
		return
	_queue.append({"text": text, "accent": accent})
	var cap := maxi(1, int(UiStyle.num("banner_max_queue", 4)))
	while _queue.size() > cap:
		_queue.pop_front()
	if _current.is_empty():
		_next()
	else:  # something is waiting now: the line on screen gets the shorter backlog time
		_left = minf(_left, UiStyle.num("banner_backlog_seconds", 1.2))


## Lines waiting behind the one on screen.
func queue_size() -> int:
	return _queue.size()


func is_showing() -> bool:
	return not _current.is_empty()


func current_text() -> String:
	return String(_current.get("text", ""))


## Seconds left for the line on screen.
func time_left() -> float:
	return _left


## Tap or code: drop the current line and show the next.
func dismiss() -> void:
	if not _current.is_empty():
		_next()


func clear() -> void:
	_queue.clear()
	_current = {}
	_left = 0.0
	visible = false


## Counts down the line on screen; called from _process, or directly by tests.
func advance(delta: float) -> void:
	if _current.is_empty():
		return
	_left -= delta
	if _left <= 0.0:
		_next()


func _process(delta: float) -> void:
	advance(delta)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()


func _next() -> void:
	if _queue.is_empty():
		_current = {}
		_left = 0.0
		UiFx.set_shown(self, false)
		emptied.emit()
		return
	_current = _queue.pop_front()
	_left = UiStyle.num("banner_backlog_seconds" if not _queue.is_empty() else "banner_seconds",
			1.2 if not _queue.is_empty() else 2.2)
	_label.text = current_text()
	var accent: Color = _current["accent"]
	add_theme_stylebox_override("panel", UiStyle.card_style(accent if accent != Color.TRANSPARENT else UiStyle.color("accent")))
	if visible:
		UiFx.pulse(self)
	UiFx.set_shown(self, true)
	line_shown.emit(current_text())
