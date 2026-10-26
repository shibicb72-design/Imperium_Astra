extends TestCase
## App icon (P5 Q20, Q7 candidate mark): project.godot uses res://icon.svg, and the SVG is a square,
## launcher-size canvas drawn only from local shapes and paths (no text, raster, script, style,
## entity, event handler or external reference). Godot's own SVG rasteriser (the one the importer
## and the Android export use) must draw both mirrored laurel branches.

const ICON_PATH := "res://icon.svg"
## Launcher icons are downscaled from at least this many units per side (432 = xxxhdpi adaptive layer).
const MIN_SIDE := 432
## FileAccess.get_md5 of the 128-unit placeholder replaced in P5 Q20 (guards a silent revert).
const PLACEHOLDER_MD5 := "f0536edee710ebbc2a306d5ff44d27a2"
const BANNED: Array[String] = [
	"<image", "<text", "<script", "<foreignObject", "<!DOCTYPE", "<!ENTITY", "data:", "<style", "@import",
]
## Outer laurel leaf centres at 180 degrees: the drawn branch and its <use> mirror (512-unit canvas).
const LEAF_PROBES: Array[Vector2] = [Vector2(135.5, 241.28), Vector2(376.5, 241.28)]


static func _root_tag(svg: String) -> String:
	var start := svg.find("<svg")
	var stop := svg.find(">", start)
	return svg.substr(start, stop - start + 1) if start >= 0 and stop > start else ""


static func _attr(tag: String, attr: String) -> String:
	var m := RegEx.create_from_string("\\s%s\\s*=\\s*\"([^\"]*)\"" % attr).search(tag)
	return m.get_string(1) if m != null else ""


func test_icon_is_project_icon_and_launcher_sized() -> void:
	check_eq(ProjectSettings.get_setting("application/config/icon"), ICON_PATH, "project icon setting")
	var root := _root_tag(FileAccess.get_file_as_string(ICON_PATH))
	check(root != "", "root <svg> tag found")
	var box := _attr(root, "viewBox").replace(",", " ").split_floats(" ", false)
	check(box.size() == 4 and box[2] > 0.0 and is_equal_approx(box[2], box[3]), "square viewBox")
	var w := _attr(root, "width")
	var h := _attr(root, "height")
	check(w.is_valid_float() and w == h, "width == height (%s, %s)" % [w, h])
	check(w.to_float() >= MIN_SIDE, "side %s >= %d" % [w, MIN_SIDE])
	check(FileAccess.get_md5(ICON_PATH) != PLACEHOLDER_MD5, "placeholder icon replaced")
	done()


func test_icon_svg_is_local_shapes_only() -> void:
	var svg := FileAccess.get_file_as_string(ICON_PATH)
	check(svg.length() > 0, "icon.svg readable")
	for token in BANNED:
		check(not svg.containsn(token), "icon.svg has no %s" % token)
	check(RegEx.create_from_string("href\\s*=\\s*[\"'](?!#)").search(svg) == null, "every href is a local #id")
	check(RegEx.create_from_string("url\\(\\s*(?!#)").search(svg) == null, "every url() is a local #id")
	check(RegEx.create_from_string("(?i)\\son[a-z]+\\s*=").search(svg) == null, "no event handler attributes")
	for m in RegEx.create_from_string("href\\s*=\\s*[\"']#([^\"']+)[\"']").search_all(svg):
		check(svg.contains("id=\"%s\"" % m.get_string(1)), "href target #%s exists" % m.get_string(1))
	done()


func test_icon_rasterises_both_laurel_branches() -> void:
	var img := Image.new()
	var err := img.load_svg_from_string(FileAccess.get_file_as_string(ICON_PATH), 0.5)
	check(err == OK and img.get_width() == 256, "icon rasterises at 256 px")
	if img.get_width() == 256:
		for p in LEAF_PROBES:
			var c := img.get_pixelv(Vector2i(p * 0.5))
			check(c.r > 0.6 and c.b < 0.4, "gold laurel leaf at %s (got #%s)" % [p, c.to_html(false)])
	done()
