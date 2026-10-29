class_name MainMenuBackground
extends Control
## Main menu backdrop (MAIN_MENU_STARK): a soft dusk skyline of towers, domes, temples and spires in
## three parallax layers (the far one pans slowest) veiled by haze, under a sky with faint stars, a
## pale ringed planet and a warm glow, with drifting clouds, a sky barge crossing and a lantern
## balloon bobbing. Low contrast on purpose, so the sharp menu chrome reads on top.
## Motion is a pure function of `time`: MainMenu.advance() moves it every frame in the tree, and
## headless tests sample it through pan_distance() / prop_position() / layer_offset(). The skyline
## layers are drawn once per size or theme and only slide; clouds and props redraw each frame.
## Colors and motion come from the active pack's "menu_background" section; a pack without one
## falls back to its own colors (FALLBACK_TONES). Presentation only; ignores input.

const SECTION := "menu_background"
## Skyline tile length in screen heights; every layer draws two tiles so the pan wraps seamlessly.
const TILE_HEIGHTS := 2.5
## Upper bound on the pack's cloud_count (each cloud redraws every frame).
const MAX_CLOUDS := 24
## Skyline layers, far to near.
const LAYER_COUNT := 3
## Props with their own motion (0 sky barge, 1 lantern balloon); clouds drift separately.
const PROP_COUNT := 2
const LAYER_TONES: Array[String] = ["far", "mid", "near"]
## Building shape ranges per layer, in screen heights: min width, max width, max height, max gap.
const SHAPES: Array[Vector4] = [Vector4(0.035, 0.07, 0.17, 0.02), Vector4(0.05, 0.1, 0.17, 0.05),
		Vector4(0.08, 0.14, 0.15, 0.12)]
const DEFAULT_PARALLAX: Array[float] = [0.3, 0.6, 1.0]
const DEFAULT_GROUND: Array[float] = [0.64, 0.72, 0.81]
## Pack color used when the pack's menu_background colors lack a key.
const FALLBACK_TONES := {
	"sky_top": "background_top", "sky_bottom": "panel_border", "glow": "accent_dim",
	"planet": "panel_border", "far": "button_border", "mid": "button", "near": "panel",
	"haze": "text_muted", "lights": "accent", "cloud": "text", "prop": "text_muted",
	"prop_light": "accent",
}

## Seconds of menu time; advance() moves it.
var time := 0.0

var _layers: Array[Control] = []
## Per layer: the Array[Vector4] buildings from make_skyline().
var _skylines: Array = []
## Each cloud: x, y (shares of the rect), radius (screen heights), speed factor.
var _clouds: Array[Vector4] = []
var _stars: Array[Vector4] = []
## Clouds and props, redrawn every frame (between the mid and near layers).
var _drift: Control
## Darkens the top and bottom edges over everything, so the chrome rows read.
var _veil: Control


## No anchors: the owner (MainMenu.layout) sets the rect on every resize.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in LAYER_COUNT:
		var layer := _canvas()
		layer.draw.connect(_paint_layer.bind(layer, i))
		_layers.append(layer)
		if i == 1:
			_drift = _canvas()
			_drift.draw.connect(_paint_drift)
	_veil = _canvas()
	_veil.draw.connect(_paint_veil)
	resized.connect(layout)
	_rebuild()


## The active pack's menu_background section ({} when it has none).
static func section() -> Dictionary:
	var v: Variant = UiStyle.theme_data().get(SECTION, {})
	return v if v is Dictionary else {}


static func knob(key: String, fallback: float) -> float:
	return float(section().get(key, fallback))


## Per-layer number `key` (an array far..near in the section), else `fallback`.
static func layer_knob(key: String, layer: int, fallback: Array[float]) -> float:
	var v: Variant = section().get(key)
	if v is Array and layer < (v as Array).size():
		return float(v[layer])
	return fallback[layer]


## Backdrop color `key` from the section's colors, else the pack color named in FALLBACK_TONES.
static func tone(key: String) -> Color:
	var colors: Variant = section().get("colors", {})
	var v: Variant = colors.get(key) if colors is Dictionary else null
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return UiStyle.color(String(FALLBACK_TONES.get(key, "background")))


## How far layer `layer` (0 far .. 2 near) has panned at time `t`, in skyline tiles (unwrapped).
## Nearer layers move faster (parallax).
static func pan_distance(layer: int, t: float) -> float:
	return t * knob("pan_speed", 0.004) * layer_knob("parallax", layer, DEFAULT_PARALLAX)


## Normalized position (shares of the rect) of prop `index` at time `t`: 0 = sky barge crossing
## right to left once every barge_seconds, 1 = lantern balloon swaying and bobbing.
static func prop_position(index: int, t: float) -> Vector2:
	if index == 0:
		var u := fposmod(t / maxf(knob("barge_seconds", 80.0), 1.0), 1.0)
		return Vector2(1.2 - 1.4 * u, 0.2 + 0.012 * sin(t * 0.7))
	var sway := sin(TAU * t / maxf(knob("balloon_drift_seconds", 140.0), 1.0))
	var bob := sin(TAU * t / maxf(knob("balloon_bob_seconds", 6.0), 0.1))
	return Vector2(0.84 - 0.22 * sway, 0.36 + knob("balloon_bob_height", 0.014) * bob)


## Normalized center of cloud `c` (a _clouds entry) at time `t`; clouds drift left and wrap.
static func cloud_position(c: Vector4, t: float) -> Vector2:
	return Vector2(fposmod(c.x - t * knob("cloud_speed", 0.006) * c.w, 1.5) - 0.25, c.y)


## Deterministic buildings for layer `layer` across one tile: x (0..1 of the tile), width and
## height in screen heights, kind (0 tower, 1 dome, 2 temple, 3 spire). None crosses the seam.
static func make_skyline(layer: int, seed_value: int) -> Array[Vector4]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + layer
	var s := SHAPES[layer]
	var out: Array[Vector4] = []
	var x := rng.randf_range(0.0, s.w)
	while true:
		var w := rng.randf_range(s.x, s.y)
		if x + w > TILE_HEIGHTS:
			break
		var kind := rng.randi_range(0, 3)
		var h := rng.randf_range(s.z * 0.4, s.z)
		if kind == 2:
			h *= 0.55
		elif kind == 3:
			h = maxf(h, s.z * 0.75)
		out.append(Vector4(x / TILE_HEIGHTS, w, h, kind))
		x += w + rng.randf_range(s.w * 0.2, s.w)
	return out


func skyline(layer: int) -> Array[Vector4]:
	return _skylines[layer]


func cloud_count() -> int:
	return _clouds.size()


## Skyline tile width in canvas units: TILE_HEIGHTS screen heights, at least the rect width.
func tile_width() -> float:
	return maxf(size.y * TILE_HEIGHTS, size.x)


## Current horizontal offset of layer `layer` in canvas units (0 or less; wraps every tile).
func layer_offset(layer: int) -> float:
	return _layers[layer].position.x


## Sizes the layers to the rect (two tiles wide) and re-applies the pan; on resize, and by tests.
func layout() -> void:
	var tile := tile_width()
	for layer in _layers:
		layer.size = Vector2(tile * 2.0, size.y)
		layer.queue_redraw()
	_drift.size = size
	_veil.size = size
	_veil.queue_redraw()
	_apply_pan()
	queue_redraw()


## Moves the backdrop clock: slides the skyline layers and redraws the clouds and props.
func advance(delta: float) -> void:
	time += delta
	_apply_pan()


## Re-reads the active pack (after UiStyle.set_theme): skyline seed, colors and motion.
func refresh_theme() -> void:
	_rebuild()
	layout()


func _canvas() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _rebuild() -> void:
	var seed_value := int(knob("seed", 11))
	_skylines.clear()
	for i in LAYER_COUNT:
		_skylines.append(make_skyline(i, seed_value))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	_clouds.clear()
	for i in clampi(int(knob("cloud_count", 5)), 0, MAX_CLOUDS):
		_clouds.append(Vector4(rng.randf(), rng.randf_range(0.06, 0.4), rng.randf_range(0.04, 0.08),
				rng.randf_range(0.6, 1.4)))
	_stars = StarfieldBackground.make_stars()


func _apply_pan() -> void:
	var tile := tile_width()
	for i in LAYER_COUNT:
		_layers[i].position = Vector2(-fposmod(pan_distance(i, time), 1.0) * tile, 0.0)
	_drift.queue_redraw()


## Vertical gradient over `r` on `ci` as one quad with vertex colors (no band seams).
static func _gradient(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))


## Sky: gradient, faint stars in the upper half, a warm glow and a pale ringed planet.
func _draw() -> void:
	_gradient(self, Rect2(Vector2.ZERO, size), tone("sky_top"), tone("sky_bottom"))
	var star := UiStyle.color("star")
	for s in _stars:
		if s.y < 0.5:
			draw_circle(Vector2(s.x * size.x, s.y * size.y), s.z * 0.8, Color(star, s.w * (1.0 - s.y * 2.0) * 0.7))
	var m := minf(size.x, size.y)
	var glow := tone("glow")
	for i in 12:
		draw_circle(Vector2(size.x * 0.68, size.y * 0.46), m * 0.6 * (1.0 - i / 12.0), Color(glow, 0.022))
	var planet := tone("planet")
	var pc := Vector2(size.x * 0.22, size.y * 0.16)
	var pr := m * 0.12
	draw_circle(pc, pr, Color(planet, 0.5))
	draw_circle(pc - Vector2(pr, pr) * 0.28, pr * 0.62, Color(1.0, 1.0, 1.0, 0.06))
	draw_set_transform(pc, -0.35, Vector2(1.0, 0.26))
	draw_arc(Vector2.ZERO, pr * 1.65, 0.0, TAU, 64, Color(planet, 0.45), maxf(2.0, pr * 0.1), true)
	draw_set_transform(Vector2.ZERO)


## One skyline layer: haze rising behind it (it veils every farther layer: fog / depth of field),
## the ground below its line, then its buildings in both tiles, each with a faint wider pass for a
## soft edge; mid and near towers get lit windows.
func _paint_layer(layer: Control, i: int) -> void:
	var h := size.y
	if h <= 0.0:
		return
	var tile := tile_width()
	var ground := layer_knob("ground", i, DEFAULT_GROUND) * h
	var far := 1.0 - float(i) / (LAYER_COUNT - 1)
	var haze := tone("haze")
	var body := tone(LAYER_TONES[i]).lerp(haze, far * 0.4)
	var rise := h * 0.22
	_gradient(layer, Rect2(0.0, ground - rise, layer.size.x, rise), Color(haze, 0.0), Color(haze, knob("haze_alpha", 0.35)))
	layer.draw_rect(Rect2(0.0, ground, layer.size.x, h - ground + 1.0), body)
	var soft := h * 0.003 * (1.0 + far * 2.0)
	for copy in 2:
		for bld: Vector4 in _skylines[i]:
			_paint_building(layer, bld, copy * tile, tile, h, ground, soft, Color(body, 0.3))
			_paint_building(layer, bld, copy * tile, tile, h, ground, 0.0, body)
	if i == 0:
		return
	var lit := Color(tone("lights"), 0.45 + 0.2 * (i - 1))
	for copy in 2:
		for bld: Vector4 in _skylines[i]:
			if int(bld.w) != 0:
				continue
			var x := copy * tile + bld.x * tile
			var w := bld.y * h
			var bh := bld.z * h
			var win := maxf(2.0, w * 0.12)
			for row in int(bh / (win * 3.0)) - 1:
				for col in 2:
					if (int(bld.x * 997.0) + row * 3 + col) % 3 != 0:
						layer.draw_rect(Rect2(x + w * (0.24 + 0.4 * col), ground - bh + win * (2.0 + row * 3.0), win, win), lit)


## Building `b` (a make_skyline entry) on `ci` from tile origin `ox`, grown by `grow` (soft pass).
func _paint_building(ci: CanvasItem, b: Vector4, ox: float, tile: float, h: float, ground: float,
		grow: float, col: Color) -> void:
	var x := ox + b.x * tile - grow
	var w := b.y * h + grow * 2.0
	var bh := b.z * h + grow
	match int(b.w):
		0:  # tower with a mast
			ci.draw_rect(Rect2(x, ground - bh, w, bh), col)
			ci.draw_rect(Rect2(x + w * 0.45, ground - bh * 1.2, w * 0.1, bh * 0.2), col)
		1:  # dome on a drum, with a finial
			var drum := bh * 0.55
			ci.draw_rect(Rect2(x, ground - drum, w, drum), col)
			ci.draw_circle(Vector2(x + w * 0.5, ground - drum), w * 0.42, col)
			ci.draw_rect(Rect2(x + w * 0.47, ground - drum - w * 0.42 - bh * 0.16, w * 0.06, bh * 0.16), col)
		2:  # temple: steps, a colonnade, the entablature and a pediment
			ci.draw_rect(Rect2(x, ground - bh * 0.14, w, bh * 0.14), col)
			var cw := w / 9.0
			for c in 5:
				ci.draw_rect(Rect2(x + cw * 2.0 * c, ground - bh * 0.78, cw, bh * 0.66), col)
			ci.draw_rect(Rect2(x - w * 0.03, ground - bh * 0.88, w * 1.06, bh * 0.12), col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.03, ground - bh * 0.88),
					Vector2(x + w * 0.5, ground - bh), Vector2(x + w * 1.03, ground - bh * 0.88)]), col)
		_:  # spire
			ci.draw_rect(Rect2(x + w * 0.2, ground - bh * 0.78, w * 0.6, bh * 0.78), col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x + w * 0.2, ground - bh * 0.78),
					Vector2(x + w * 0.5, ground - bh * 1.1), Vector2(x + w * 0.8, ground - bh * 0.78)]), col)


## Clouds (flattened puffs in faint shells, so the edges fall off softly), the sky barge and the
## lantern balloon at the current time.
func _paint_drift() -> void:
	var h := size.y
	if h <= 0.0:
		return
	var tint := Color(tone("cloud"), 0.045)
	for c in _clouds:
		var r := c.z * h
		_drift.draw_set_transform(cloud_position(c, time) * size, 0.0, Vector2(1.0, 0.62))
		for k in 3:
			var shell := 1.0 + (2 - k) * 0.22
			_drift.draw_circle(Vector2(-r * 0.95, r * 0.12), r * 0.62 * shell, tint)
			_drift.draw_circle(Vector2(0.0, -r * 0.12), r * 0.9 * shell, tint)
			_drift.draw_circle(Vector2(r * 0.9, r * 0.15), r * 0.58 * shell, tint)
			_drift.draw_circle(Vector2(r * 0.25, r * 0.28), r * 0.7 * shell, tint)
	_drift.draw_set_transform(Vector2.ZERO)
	_paint_barge(prop_position(0, time) * size, h)
	_paint_balloon(prop_position(1, time) * size, h)


## Sky barge (an airship heading left): envelope, tail fins, gondola and a blinking light.
func _paint_barge(p: Vector2, h: float) -> void:
	var l := h * 0.085
	var hull := Color(tone("prop"), 0.85)
	var shade := hull.darkened(0.25)
	_drift.draw_set_transform(p, 0.0, Vector2(1.0, 0.34))
	_drift.draw_circle(Vector2.ZERO, l * 0.5, hull)
	_drift.draw_circle(Vector2(-l * 0.08, -l * 0.18), l * 0.3, Color(1.0, 1.0, 1.0, 0.12))
	_drift.draw_set_transform(Vector2.ZERO)
	for side: float in [-1.0, 1.0]:
		_drift.draw_colored_polygon(PackedVector2Array([p + Vector2(l * 0.38, l * 0.04 * side),
				p + Vector2(l * 0.62, l * 0.2 * side), p + Vector2(l * 0.56, 0.0)]), shade)
	_drift.draw_rect(Rect2(p + Vector2(-l * 0.12, l * 0.15), Vector2(l * 0.24, l * 0.07)), shade)
	_drift.draw_circle(p + Vector2(-l * 0.1, l * 0.24), maxf(1.5, l * 0.025),
			Color(tone("prop_light"), 0.5 + 0.5 * sin(time * 3.0)))


## Lantern balloon: envelope with a lit center stripe, cords, basket and a warm glow below.
func _paint_balloon(p: Vector2, h: float) -> void:
	var r := h * 0.028
	var skin := Color(tone("prop"), 0.9)
	var light := tone("prop_light")
	_drift.draw_circle(p + Vector2(0.0, r * 1.3), r * 0.9, Color(light, 0.12))
	_drift.draw_set_transform(p, 0.0, Vector2(0.88, 1.05))
	_drift.draw_circle(Vector2.ZERO, r, skin)
	_drift.draw_set_transform(p, 0.0, Vector2(0.36, 1.05))
	_drift.draw_circle(Vector2.ZERO, r, Color(light, 0.35))
	_drift.draw_set_transform(Vector2.ZERO)
	var cord := skin.darkened(0.3)
	_drift.draw_line(p + Vector2(-r * 0.55, r * 0.8), p + Vector2(-r * 0.22, r * 1.45), cord, 1.0)
	_drift.draw_line(p + Vector2(r * 0.55, r * 0.8), p + Vector2(r * 0.22, r * 1.45), cord, 1.0)
	_drift.draw_rect(Rect2(p + Vector2(-r * 0.25, r * 1.45), Vector2(r * 0.5, r * 0.32)), skin.darkened(0.35))


func _paint_veil() -> void:
	var h := size.y
	var dark := tone("sky_top").darkened(0.6)
	_gradient(_veil, Rect2(0.0, h * 0.7, size.x, h * 0.3), Color(dark, 0.0), Color(dark, 0.5))
	_gradient(_veil, Rect2(0.0, 0.0, size.x, h * 0.12), Color(dark, 0.3), Color(dark, 0.0))
