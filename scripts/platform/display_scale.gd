class_name DisplayScale
extends RefCounted
## Window content scale so one canvas unit is about one density-independent pixel (dp) on
## phones and tablets (Android's 160 dpi baseline), whatever the orientation. Desktop and web
## keep 1.0 (no-op fallback) until they get their own rule. The project uses stretch mode
## "disabled", so this factor is the only UI scaling.

const DP_BASELINE_DPI := 160.0
const MIN_FACTOR := 1.0
const MAX_FACTOR := 4.0
const SCALED_OS: Array[String] = ["Android", "iOS"]


static func factor_for(os_name: String, dpi: int) -> float:
	if os_name in SCALED_OS and dpi > 0:
		return clampf(dpi / DP_BASELINE_DPI, MIN_FACTOR, MAX_FACTOR)
	return 1.0


static func apply(window: Window) -> float:
	var f := factor_for(OS.get_name(), DisplayServer.screen_get_dpi())
	window.content_scale_factor = f
	return f


## Insets (left, top, right, bottom) in canvas units that keep controls out of cutouts and
## system bars. Zero off mobile.
static func safe_insets(factor: float) -> Vector4:
	if not OS.get_name() in SCALED_OS or factor <= 0.0:
		return Vector4.ZERO
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var end := safe.position + safe.size
	return Vector4(maxi(safe.position.x, 0), maxi(safe.position.y, 0),
			maxi(screen.x - end.x, 0), maxi(screen.y - end.y, 0)) / factor
