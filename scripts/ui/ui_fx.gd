class_name UiFx
extends RefCounted
## Small Tween helpers for panel show/hide and attention pulses (presentation only). Timings come
## from data/ui.json (panel_fade_seconds, pulse_seconds). Outside the scene tree (headless tests)
## or with a zero duration every change is instant, so logic never waits on an animation.
## Containers own their children's position and scale, so panels fade (modulate alpha) rather
## than slide.

const TWEEN_META := &"ui_fx_tween"
const HIDING_META := &"ui_fx_hiding"


static func _animated(c: CanvasItem, seconds: float) -> bool:
	return seconds > 0.0 and c.is_inside_tree()


static func _kill(c: CanvasItem) -> void:
	if c.has_meta(TWEEN_META):
		var tw: Tween = c.get_meta(TWEEN_META)
		if tw != null and tw.is_valid():
			tw.kill()
		c.remove_meta(TWEEN_META)
	if c.has_meta(HIDING_META):
		c.remove_meta(HIDING_META)


## Shows or hides `c` with a short fade. `visible` stays true until a fade-out ends.
static func set_shown(c: CanvasItem, shown: bool) -> void:
	var seconds := UiStyle.num("panel_fade_seconds", 0.18)
	var hiding := c.has_meta(HIDING_META)
	if not _animated(c, seconds):
		_kill(c)
		c.visible = shown
		c.modulate.a = 1.0
		return
	if shown:
		if c.visible and not hiding:
			return
		_kill(c)
		if not c.visible:
			c.modulate.a = 0.0
		c.visible = true
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 1.0, seconds)
		c.set_meta(TWEEN_META, tw)
	else:
		if not c.visible or hiding:
			return
		_kill(c)
		c.set_meta(HIDING_META, true)
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 0.0, seconds)
		tw.tween_callback(func() -> void:
			c.visible = false
			c.modulate.a = 1.0
			if c.has_meta(HIDING_META):
				c.remove_meta(HIDING_META)
			c.remove_meta(TWEEN_META))
		c.set_meta(TWEEN_META, tw)


## Fades `c` in from transparent (e.g. a freshly built screen).
static func fade_in(c: CanvasItem, seconds: float = -1.0) -> void:
	if seconds < 0.0:
		seconds = UiStyle.num("screen_fade_seconds", 0.35)
	if not _animated(c, seconds):
		return
	_kill(c)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, seconds)
	c.set_meta(TWEEN_META, tw)


## Brief brighten-and-settle flash to draw the eye (turn change, new banner line).
static func pulse(c: CanvasItem) -> void:
	var seconds := UiStyle.num("pulse_seconds", 0.35)
	if not _animated(c, seconds) or c.has_meta(HIDING_META):
		return
	_kill(c)
	c.modulate = Color(1.6, 1.6, 1.6, 1.0)
	var tw := c.create_tween()
	tw.tween_property(c, "modulate", Color.WHITE, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c.set_meta(TWEEN_META, tw)
