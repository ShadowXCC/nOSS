extends SceneTree
## Turns screenshots into how they look with colour-blind vision, for review
## (docs/ACCESSIBILITY.md §9). Take shots with a display first (--shot), then:
##   tools/godot.sh --headless -s res://tools/cvd_shots.gd -- <shot.png> [more.png ...]
## Writes <shot>_deuteranopia.png, _protanopia.png and _tritanopia.png next to each.

const KINDS := ["deuteranopia", "protanopia", "tritanopia"]


func _initialize() -> void:
	var files := OS.get_cmdline_user_args()
	if files.is_empty():
		print("Usage: -- <shot.png> [more.png ...]")
		quit(1)
		return
	for path in files:
		var img := Image.load_from_file(path)
		if img == null:
			print("Can't read ", path)
			continue
		img.convert(Image.FORMAT_RGBA8)
		for kind: String in KINDS:
			var out := img.duplicate() as Image
			# Palette.simulate per pixel, through a 32-level lookup per channel triple.
			var cache := {}
			for y in out.get_height():
				for x in out.get_width():
					var c := out.get_pixel(x, y)
					var key := Vector3i(int(c.r * 31.0), int(c.g * 31.0), int(c.b * 31.0))
					if not cache.has(key):
						cache[key] = Palette.simulate(Color(key.x / 31.0, key.y / 31.0, key.z / 31.0), kind)
					var s: Color = cache[key]
					out.set_pixel(x, y, Color(s.r, s.g, s.b, c.a))
			var target := "%s_%s.png" % [path.get_basename(), kind]
			out.save_png(target)
			print("Wrote ", target)
	quit(0)
