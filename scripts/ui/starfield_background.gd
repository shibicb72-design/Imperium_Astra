class_name StarfieldBackground
extends Control
## Full-screen backdrop: vertical gradient (theme background_top -> background) and a
## procedural starfield. Stars sit at fractions of the rect, generated once from the theme
## seed, so they rescale with any aspect ratio and look the same every launch. Presentation only;
## ignores input. Starfield settings come from the theme pack's "starfield" section.

const GRADIENT_BANDS := 24

## Each star: x, y in 0..1 of the rect, z = radius in canvas units, w = alpha.
var stars: Array[Vector4] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	stars = make_stars()


## Deterministic star list from the theme (empty when the starfield is disabled).
static func make_stars() -> Array[Vector4]:
	var out: Array[Vector4] = []
	if not bool(UiStyle.theme_data().get("starfield", {}).get("enabled", false)):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(UiStyle.theme_num("starfield", "seed", 7))
	var max_r := UiStyle.theme_num("starfield", "max_radius", 1.6)
	var min_a := UiStyle.theme_num("starfield", "min_alpha", 0.25)
	for i in int(UiStyle.theme_num("starfield", "count", 0)):
		out.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(0.4, max_r), rng.randf_range(min_a, 1.0)))
	return out


func _draw() -> void:
	var top := UiStyle.color("background_top")
	var bottom := UiStyle.color("background")
	var band := size.y / GRADIENT_BANDS
	for i in GRADIENT_BANDS:
		draw_rect(Rect2(0, band * i, size.x, band + 1.0), top.lerp(bottom, float(i) / (GRADIENT_BANDS - 1)))
	var star := UiStyle.color("star")
	for s in stars:
		draw_circle(Vector2(s.x * size.x, s.y * size.y), s.z, Color(star, s.w))
