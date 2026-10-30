extends SceneTree
## Makes the livery art (docs/VEHICLE_PACKAGE.md §12, docs/ART_AUDIO.md §8):
## content/liveries/catalog.json (every shape and font a livery may use) and
## content/liveries/shapes.png, the atlas of drawn shapes: one-channel distance fields in a 16 x 16
## grid of 128 px cells (2048 px square), a shape one to three cells wide. Each shape is drawn as a
## mask at 4x, measured into a signed distance field and stored at 0.5 + distance / RANGE.
## Procedural shapes are drawn by the shader (livery.gdshaderinc) and only listed here. The
## sponsor logos are invented (names checked against real brands on 2026-10-30). Seeded, so the
## same every run:
##   tools/godot.sh --headless -s res://tools/make_livery_art.gd

const OUT_CATALOG := "res://content/liveries/catalog.json"
const OUT_ATLAS := "res://content/liveries/shapes.png"
const CELL := 128
const GRID := 16
const UP := 4 # mask pixels per atlas pixel
const RANGE := 16.0 # atlas pixels across the field (livery_shape_range)
const SEED := 20261030
## A shape keeps to this share of its cells.
const INSET := 0.92

const FONTS := [
	{ "id": "atkinson_bold", "name": "Clear", "file": "res://content/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf" },
	{ "id": "racing_sans_one", "name": "Racing", "file": "res://content/fonts/racing_sans_one/RacingSansOne-Regular.ttf" },
	{ "id": "russo_one", "name": "Blocky", "file": "res://content/fonts/russo_one/RussoOne-Regular.ttf" },
	{ "id": "orbitron", "name": "Tech", "file": "res://content/fonts/orbitron/Orbitron[wght].ttf", "variation": { "wght": 800 } },
	{ "id": "bebas_neue", "name": "Condensed", "file": "res://content/fonts/bebas_neue/BebasNeue-Regular.ttf" },
	{ "id": "saira_stencil_one", "name": "Stencil", "file": "res://content/fonts/saira_stencil_one/SairaStencilOne-Regular.ttf" },
	{ "id": "pacifico", "name": "Script", "file": "res://content/fonts/pacifico/Pacifico-Regular.ttf" },
	{ "id": "monoton", "name": "Retro", "file": "res://content/fonts/monoton/Monoton-Regular.ttf" },
]

## Drawn by the shader: index is its code there.
const PROC := [
	{ "id": "rect", "name": "Rectangle", "category": "basic", "params": [0.0, 0.0], "param_names": ["Corners", "Outline"] },
	{ "id": "ellipse", "name": "Ellipse", "category": "basic", "params": [0.0], "param_names": ["Outline"] },
	{ "id": "ring", "name": "Ring", "category": "basic", "params": [0.3], "param_names": ["Thickness"] },
	{ "id": "triangle", "name": "Triangle", "category": "basic", "params": [0.5, 0.0], "param_names": ["Peak", "Outline"] },
	{ "id": "diamond", "name": "Diamond", "category": "basic", "params": [0.0], "param_names": ["Outline"] },
	{ "id": "star", "name": "Star", "category": "basic", "params": [0.22, 0.45], "param_names": ["Points", "Inner"] },
	{ "id": "arrow", "name": "Arrow", "category": "basic", "params": [0.4, 0.4], "param_names": ["Shaft", "Head"] },
	{ "id": "chevrons", "name": "Chevrons", "category": "racing", "params": [0.3, 0.5], "param_names": ["Count", "Thickness"] },
	{ "id": "stripes", "name": "Stripes", "category": "racing", "params": [0.1, 0.5], "param_names": ["Count", "Width"] },
	{ "id": "pinstripes", "name": "Pinstripes", "category": "racing", "params": [0.1, 0.15], "param_names": ["Count", "Width"] },
	{ "id": "checker", "name": "Checker", "category": "racing", "params": [0.4], "param_names": ["Squares"] },
	{ "id": "gradient", "name": "Fade", "category": "racing", "params": [1.0], "param_names": ["Softness"] },
	{ "id": "radial", "name": "Glow", "category": "racing", "params": [1.0], "param_names": ["Softness"] },
	{ "id": "halftone", "name": "Halftone", "category": "racing", "params": [0.4], "param_names": ["Dots"] },
	{ "id": "speed_lines", "name": "Speed lines", "category": "racing", "params": [0.4, 0.5], "param_names": ["Count", "Taper"] },
	{ "id": "slash", "name": "Slash", "category": "racing", "params": [0.5, 0.0], "param_names": ["Slant", "Outline"] },
]

## Drawn here: [id, name, category, span, readable].
const ATLAS := [
	["flames", "Flames", "graphics", 2, false],
	["flame", "Flame", "graphics", 1, false],
	["splatter", "Splatter", "graphics", 1, false],
	["splash", "Splash", "graphics", 1, false],
	["torn", "Torn edge", "graphics", 2, false],
	["lightning", "Lightning", "graphics", 1, false],
	["wing", "Wing", "graphics", 2, false],
	["camo", "Camo", "graphics", 1, false],
	["sunburst", "Sunburst", "graphics", 1, false],
	["plate", "Plate", "plates", 2, false],
	["roundel", "Roundel", "plates", 1, false],
	["shield", "Shield", "plates", 1, false],
	["banner", "Banner", "plates", 2, false],
	["torqwell", "Torqwell", "sponsors", 3, true],
	["pistonfly", "Pistonfly", "sponsors", 2, true],
	["gearhound", "Gearhound", "sponsors", 2, true],
	["sparkmoth", "Sparkmoth", "sponsors", 3, true],
	["quokka_lube", "Quokka Lube", "sponsors", 3, true],
	["brakebird", "Brakebird", "sponsors", 3, true],
	["fizzbolt", "Fizzbolt", "sponsors", 3, true],
	["grip_owl", "Grip Owl", "sponsors", 3, true],
	["kettlecomet", "Kettlecomet", "sponsors", 3, true],
	["apexberry", "Apexberry", "sponsors", 3, true],
]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = SEED
	var t0 := Time.get_ticks_msec()
	var cells := _layout()
	_write_catalog(cells)
	var atlas := Image.create(CELL * GRID, CELL * GRID, false, Image.FORMAT_L8)
	for item: Array in ATLAS:
		var id: String = item[0]
		var span: int = item[3]
		var mask := Image.create(CELL * UP * span, CELL * UP, false, Image.FORMAT_L8)
		call("_draw_" + id, mask, float(mask.get_width()), float(mask.get_height()))
		var field := _field(_inset(mask))
		var cell: int = cells[id]
		atlas.blit_rect(field, Rect2i(Vector2i.ZERO, field.get_size()), Vector2i(cell % GRID, cell / GRID) * CELL)
		print("  %s: cell %d" % [id, cell])
	atlas.save_png(ProjectSettings.globalize_path(OUT_ATLAS))
	print("make_livery_art: %d shapes, %d fonts, %d ms" % [PROC.size() + ATLAS.size(), FONTS.size(), Time.get_ticks_msec() - t0])
	quit()


## Each atlas shape's first cell, rows filled left to right (a wide shape never wraps).
func _layout() -> Dictionary:
	var out := {}
	var at := 0
	for item: Array in ATLAS:
		var span: int = item[3]
		if at % GRID + span > GRID:
			at += GRID - at % GRID
		out[item[0]] = at
		at += span
	return out


func _write_catalog(cells: Dictionary) -> void:
	var shapes := []
	for i in PROC.size():
		var s: Dictionary = PROC[i].duplicate(true)
		s.kind = "proc"
		s.index = i
		shapes.append(s)
	for item: Array in ATLAS:
		var s := { "id": item[0], "name": item[1], "category": item[2], "kind": "atlas", "index": cells[item[0]], "span": item[3],
			"params": [], "param_names": [] }
		if item[4]:
			s.readable = true
		shapes.append(s)
	var data := { "schema": "noss.livery_catalog/1", "shapes": shapes, "fonts": FONTS }
	var f := FileAccess.open(OUT_CATALOG, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", true) + "\n")
	f.close()


# --- distance field ----------------------------------------------------------


## The drawing shrunk to INSET of its cells, centred, so no shape reaches its cells' edges (or
## bleeds into the next shape's).
func _inset(mask: Image) -> Image:
	var w := mask.get_width()
	var h := mask.get_height()
	var small := mask.duplicate() as Image
	small.resize(roundi(w * INSET), roundi(h * INSET), Image.INTERPOLATE_BILINEAR)
	var out := Image.create(w, h, false, Image.FORMAT_L8)
	out.blit_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), (Vector2i(w, h) - small.get_size()) / 2)
	return out


## The mask (white inside) as a field at atlas size: 0.5 + signed distance / RANGE (inside up).
func _field(mask: Image) -> Image:
	var w := mask.get_width()
	var h := mask.get_height()
	var bytes := mask.get_data()
	var inside := PackedFloat32Array()
	var outside := PackedFloat32Array()
	inside.resize(w * h)
	outside.resize(w * h)
	const BIG := 1e12
	for i in w * h:
		var on := bytes[i] > 127
		inside[i] = 0.0 if on else BIG # distance to the inside, for outside pixels
		outside[i] = BIG if on else 0.0
	_edt(inside, w, h)
	_edt(outside, w, h)
	var ow := w / UP
	var oh := h / UP
	var out := PackedByteArray()
	out.resize(ow * oh)
	for y in oh:
		for x in ow:
			# The middle of the atlas pixel: the nearest mask pixel's distances.
			var i := (y * UP + UP / 2) * w + x * UP + UP / 2
			var d := (sqrt(outside[i]) - sqrt(inside[i])) / UP
			d += -0.5 / UP if bytes[i] > 127 else 0.5 / UP
			out[y * ow + x] = clampi(roundi((0.5 + d / RANGE) * 255.0), 0, 255)
	return Image.create_from_data(ow, oh, false, Image.FORMAT_L8, out)


## Squared Euclidean distance transform in place (Felzenszwalb and Huttenlocher), rows then columns.
func _edt(grid: PackedFloat32Array, w: int, h: int) -> void:
	var n := maxi(w, h)
	var f := PackedFloat32Array()
	var d := PackedFloat32Array()
	var v := PackedInt32Array()
	var z := PackedFloat32Array()
	f.resize(n)
	d.resize(n)
	v.resize(n)
	z.resize(n + 1)
	for x in w:
		for y in h:
			f[y] = grid[y * w + x]
		_edt_1d(f, d, v, z, h)
		for y in h:
			grid[y * w + x] = d[y]
	for y in h:
		for x in w:
			f[x] = grid[y * w + x]
		_edt_1d(f, d, v, z, w)
		for x in w:
			grid[y * w + x] = d[x]


func _edt_1d(f: PackedFloat32Array, d: PackedFloat32Array, v: PackedInt32Array, z: PackedFloat32Array, n: int) -> void:
	var k := 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var s := ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		while s <= z[k]:
			k -= 1
			s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]


# --- drawing (shapes in pixels of the mask, y down) --------------------------


## Fills a polygon (even-odd) with `on` (white) or off (a hole).
func _poly(mask: Image, pts: PackedVector2Array, on := true) -> void:
	var w := mask.get_width()
	var h := mask.get_height()
	var top := h
	var bottom := 0
	for p in pts:
		top = mini(top, floori(p.y))
		bottom = maxi(bottom, ceili(p.y))
	var c := Color.WHITE if on else Color.BLACK
	for y in range(maxi(top, 0), mini(bottom + 1, h)):
		var yc := y + 0.5
		var xs := PackedFloat32Array()
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			var x0 := clampi(roundi(xs[i]), 0, w)
			var x1 := clampi(roundi(xs[i + 1]), 0, w)
			if x1 > x0:
				mask.fill_rect(Rect2i(x0, y, x1 - x0, 1), c)


func _circle(mask: Image, center: Vector2, r: float, on := true) -> void:
	_ellipse(mask, center, Vector2(r, r), on)


func _ellipse(mask: Image, center: Vector2, r: Vector2, on := true) -> void:
	var pts := PackedVector2Array()
	for i in 96:
		var a := TAU * i / 96.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_poly(mask, pts, on)


func _ring(mask: Image, center: Vector2, r: float, t: float) -> void:
	_circle(mask, center, r)
	_circle(mask, center, r - t, false)


## A thick line through `pts`, round at the joints and ends.
func _stroke(mask: Image, pts: PackedVector2Array, width: float, on := true) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).orthogonal().normalized() * width * 0.5
		_poly(mask, PackedVector2Array([a + n, b + n, b - n, a - n]), on)
	for p in pts:
		_circle(mask, p, width * 0.5, on)


func _rounded_rect(mask: Image, r: Rect2, radius: float, on := true) -> void:
	var pts := PackedVector2Array()
	var corners := [r.position + Vector2(r.size.x - radius, radius), r.position + Vector2(r.size.x - radius, r.size.y - radius),
		r.position + Vector2(radius, r.size.y - radius), r.position + Vector2(radius, radius)]
	for k in 4:
		for i in 13:
			var a := -PI / 2.0 + PI / 2.0 * k + PI / 2.0 * i / 12.0
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * radius)
	_poly(mask, pts, on)


## `text` in font `font_id`, as big as fits `box` (kept in shape, centred).
func _text(mask: Image, text: String, font_id: String, box: Rect2, on := true, slant := 0.0) -> void:
	var src := LiveryText.string_image(text, font_id)
	var scale := minf(box.size.x / src.get_width(), box.size.y / src.get_height())
	var size := Vector2(src.get_size()) * scale
	var at := box.position + (box.size - size) * 0.5
	var data := src.get_data()
	var sw := src.get_width()
	var sh := src.get_height()
	var mw := mask.get_width()
	var bytes := mask.get_data()
	var v := 255 if on else 0
	for y in range(maxi(floori(at.y), 0), mini(ceili(at.y + size.y), mask.get_height())):
		for x in range(maxi(floori(at.x - absf(slant) * size.y), 0), mini(ceili(at.x + size.x + absf(slant) * size.y), mw)):
			var sx := (x + 0.5 - at.x + slant * (y + 0.5 - at.y - size.y)) / scale - 0.5
			var sy := (y + 0.5 - at.y) / scale - 0.5
			if sx < 0.0 or sy < 0.0 or sx > sw - 1 or sy > sh - 1:
				continue
			var x0 := floori(sx)
			var y0 := floori(sy)
			var x1 := mini(x0 + 1, sw - 1)
			var y1 := mini(y0 + 1, sh - 1)
			var fx := sx - x0
			var fy := sy - y0
			var a := lerpf(lerpf(data[(y0 * sw + x0) * 4 + 3], data[(y0 * sw + x1) * 4 + 3], fx),
				lerpf(data[(y1 * sw + x0) * 4 + 3], data[(y1 * sw + x1) * 4 + 3], fx), fy)
			if a >= 127.5:
				bytes[y * mw + x] = v
	mask.set_data(mw, mask.get_height(), false, Image.FORMAT_L8, bytes)


func _lightning_pts(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Vector2 in [Vector2(0.12, -0.5), Vector2(-0.2, 0.06), Vector2(0.0, 0.06), Vector2(-0.12, 0.5), Vector2(0.24, -0.14),
			Vector2(0.03, -0.14), Vector2(0.22, -0.5)]:
		pts.append(c + p * s)
	return pts


# --- graphics ----------------------------------------------------------------


func _draw_flames(mask: Image, w: float, h: float) -> void:
	# Hot-rod flames: licks streaming back from a solid front.
	_ellipse(mask, Vector2(w * 0.06, h * 0.5), Vector2(w * 0.08, h * 0.42))
	var tongues := [[0.18, 0.95, 0.16], [0.34, 0.72, 0.14], [0.5, 0.98, 0.17], [0.66, 0.66, 0.13], [0.82, 0.88, 0.15]]
	for t: Array in tongues:
		var y0: float = t[0] * h
		var length: float = t[1] * w
		var half: float = t[2] * h
		var drift := rng.randf_range(-0.12, 0.12) * h
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		for i in 25:
			var u := i / 24.0
			var center := Vector2(w * 0.04 + u * length, y0 + drift * u * u + sin(u * PI * 2.2) * h * 0.035 * u)
			var hw := half * pow(1.0 - u, 0.85) * (1.0 + 0.25 * sin(u * PI * 3.0))
			top.append(center + Vector2(0, -hw))
			bottom.append(center + Vector2(0, hw))
		bottom.reverse()
		_poly(mask, top + bottom)


func _draw_flame(mask: Image, w: float, h: float) -> void:
	var pts := PackedVector2Array()
	for i in 120:
		var a := TAU * i / 120.0
		var up := (1.0 - cos(a)) * 0.5 # 0 at the bottom, 1 at the top
		var r := 0.28 * (1.0 - up * 0.65) + 0.04 * sin(a * 5.0) * up
		var p := Vector2(sin(a) * r, cos(a) * 0.3 - up * up * 0.32)
		p.x += sin(up * PI * 1.5) * 0.06 * up
		pts.append(Vector2(w * (0.5 + p.x), h * (0.62 + p.y)))
	_poly(mask, pts)
	_poly(mask, _flick(w * 0.3, h * 0.52, 0.16 * h, -0.5))
	_poly(mask, _flick(w * 0.72, h * 0.48, 0.18 * h, 0.4))


## A small flame lick at (x, y) leaning `lean`.
func _flick(x: float, y: float, size: float, lean: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var up := (1.0 - cos(a)) * 0.5
		pts.append(Vector2(x + sin(a) * size * 0.35 * (1.0 - up * 0.8) + lean * up * up * size, y + cos(a) * size * 0.4 - up * up * size * 0.7))
	return pts


func _draw_splatter(mask: Image, w: float, h: float) -> void:
	_blob(mask, Vector2(w, h) * 0.5, minf(w, h) * 0.24, 14, 0.35)
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, 0.46) * minf(w, h)
		_circle(mask, Vector2(w, h) * 0.5 + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.01, 0.035) * minf(w, h))


func _draw_splash(mask: Image, w: float, h: float) -> void:
	_blob(mask, Vector2(w * 0.5, h * 0.42), minf(w, h) * 0.26, 9, 0.25)
	for i in 5:
		var x := w * rng.randf_range(0.3, 0.7)
		var length := h * rng.randf_range(0.2, 0.42)
		var r := w * rng.randf_range(0.018, 0.03)
		_stroke(mask, PackedVector2Array([Vector2(x, h * 0.45), Vector2(x, h * 0.45 + length)]), r * 2.0)
		_circle(mask, Vector2(x, h * 0.45 + length), r * 1.5)


## A splat: a circle with `spikes` spikes reaching out by `spiky` of its radius.
func _blob(mask: Image, c: Vector2, r: float, spikes: int, spiky: float) -> void:
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	var lengths := []
	for i in spikes:
		lengths.append(rng.randf_range(0.3, 1.0))
	for i in 180:
		var a := TAU * i / 180.0
		var k := a / TAU * spikes
		var j := int(k) % spikes
		var bump: float = pow(maxf(sin(fposmod(k, 1.0) * PI), 0.0), 6.0) * float(lengths[j])
		pts.append(c + Vector2(cos(a + phase), sin(a + phase)) * r * (1.0 + spiky * bump + 0.05 * sin(a * 7.0)))
	_poly(mask, pts)


func _draw_torn(mask: Image, w: float, h: float) -> void:
	var pts := PackedVector2Array([Vector2(w, h), Vector2(0, h)])
	var y := h * 0.35
	var x := 0.0
	while x < w:
		pts.append(Vector2(x, y))
		x += rng.randf_range(0.01, 0.035) * w
		y = clampf(y + rng.randf_range(-0.07, 0.07) * h, h * 0.2, h * 0.5)
	pts.append(Vector2(w, y))
	_poly(mask, pts)


func _draw_lightning(mask: Image, w: float, h: float) -> void:
	_poly(mask, _lightning_pts(Vector2(w, h) * 0.5, h * 0.92))


func _draw_wing(mask: Image, w: float, h: float) -> void:
	# A wing sweeping back from its root on the left: the leading edge, then feathers.
	var lead := PackedVector2Array()
	for i in 30:
		var u := i / 29.0
		lead.append(Vector2(w * (0.06 + 0.9 * u), h * (0.42 - 0.3 * sin(u * PI * 0.5) + 0.12 * u * u)))
	var under := PackedVector2Array([Vector2(w * 0.96, h * 0.27), Vector2(w * 0.5, h * 0.45), Vector2(w * 0.06, h * 0.55)])
	_poly(mask, lead + under)
	for i in 6:
		var root := Vector2(w * (0.12 + 0.13 * i), h * (0.4 - 0.02 * i))
		var tip := root + Vector2(w * (0.18 + 0.03 * i), h * (0.42 - 0.04 * i))
		var n := (tip - root).orthogonal().normalized() * h * 0.06
		var pts := PackedVector2Array()
		for j in 20:
			var u := j / 19.0
			pts.append(root.lerp(tip, u) + n * sin(u * PI) * (1.0 - 0.3 * u))
		for j in 20:
			var u := 1.0 - j / 19.0
			pts.append(root.lerp(tip, u) - n * sin(u * PI) * 0.5)
		_poly(mask, pts)


func _draw_camo(mask: Image, w: float, h: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 3.2 / w
	noise.fractal_octaves = 2
	var bytes := mask.get_data()
	var iw := int(w)
	for y in int(h):
		for x in iw:
			var edge := minf(minf(x, w - x), minf(y, h - y)) / (w * 0.08)
			if noise.get_noise_2d(x, y) - (1.0 - clampf(edge, 0.0, 1.0)) * 0.6 > 0.08:
				bytes[y * iw + x] = 255
	mask.set_data(iw, int(h), false, Image.FORMAT_L8, bytes)


func _draw_sunburst(mask: Image, w: float, h: float) -> void:
	var c := Vector2(w, h) * 0.5
	for i in 16:
		var a := TAU * i / 16.0
		_poly(mask, PackedVector2Array([c, c + Vector2(cos(a - 0.11), sin(a - 0.11)) * w * 0.5, c + Vector2(cos(a + 0.11), sin(a + 0.11)) * w * 0.5]))
	_circle(mask, c, w * 0.12)


# --- plates --------------------------------------------------------------------


func _draw_plate(mask: Image, w: float, h: float) -> void:
	_rounded_rect(mask, Rect2(w * 0.03, h * 0.08, w * 0.94, h * 0.84), h * 0.14)
	_rounded_rect(mask, Rect2(w * 0.07, h * 0.18, w * 0.86, h * 0.64), h * 0.08, false)
	for x in [0.15, 0.85]:
		_circle(mask, Vector2(w * x, h * 0.13), h * 0.022, false)


func _draw_roundel(mask: Image, w: float, h: float) -> void:
	_ring(mask, Vector2(w, h) * 0.5, h * 0.47, h * 0.07)
	_ring(mask, Vector2(w, h) * 0.5, h * 0.36, h * 0.025)


func _draw_shield(mask: Image, w: float, h: float) -> void:
	var pts := PackedVector2Array([Vector2(w * 0.12, h * 0.06), Vector2(w * 0.5, h * 0.12), Vector2(w * 0.88, h * 0.06)])
	for i in 21:
		var u := i / 20.0
		pts.append(Vector2(w * (0.88 - 0.38 * u * u), h * (0.06 + 0.88 * sin(u * PI * 0.5))))
	for i in range(19, -1, -1):
		var u := i / 20.0
		pts.append(Vector2(w * (0.12 + 0.38 * u * u), h * (0.06 + 0.88 * sin(u * PI * 0.5))))
	_poly(mask, pts)


func _draw_banner(mask: Image, w: float, h: float) -> void:
	_poly(mask, PackedVector2Array([Vector2(w * 0.16, h * 0.22), Vector2(w * 0.84, h * 0.22), Vector2(w * 0.84, h * 0.7), Vector2(w * 0.16, h * 0.7)]))
	for side: float in [-1.0, 1.0]:
		var x0 := w * 0.5 + side * w * 0.3
		var x1 := w * 0.5 + side * w * 0.48
		_poly(mask, PackedVector2Array([Vector2(x0, h * 0.36), Vector2(x1, h * 0.36), Vector2(x1 - side * w * 0.05, h * 0.6),
			Vector2(x1, h * 0.84), Vector2(x0, h * 0.84)]))


# --- sponsors (invented) ---------------------------------------------------------


func _draw_torqwell(mask: Image, w: float, h: float) -> void:
	_gear(mask, Vector2(h * 0.5, h * 0.5), h * 0.36)
	_text(mask, "TORQWELL", "russo_one", Rect2(h * 0.95, h * 0.2, w - h * 1.0, h * 0.6))


func _draw_pistonfly(mask: Image, w: float, h: float) -> void:
	_text(mask, "Pistonfly", "racing_sans_one", Rect2(w * 0.04, h * 0.12, w * 0.92, h * 0.6))
	_stroke(mask, PackedVector2Array([Vector2(w * 0.08, h * 0.82), Vector2(w * 0.92, h * 0.76)]), h * 0.06)


func _draw_gearhound(mask: Image, w: float, h: float) -> void:
	_rounded_rect(mask, Rect2(w * 0.02, h * 0.1, w * 0.96, h * 0.8), h * 0.12)
	_text(mask, "GEARHOUND", "bebas_neue", Rect2(w * 0.06, h * 0.16, w * 0.88, h * 0.68), false)


func _draw_sparkmoth(mask: Image, w: float, h: float) -> void:
	_poly(mask, _lightning_pts(Vector2(h * 0.45, h * 0.5), h * 0.8))
	_text(mask, "SPARKMOTH", "orbitron", Rect2(h * 0.85, h * 0.25, w - h * 0.9, h * 0.5))


func _draw_quokka_lube(mask: Image, w: float, h: float) -> void:
	var drop := PackedVector2Array()
	for i in 60:
		var a := TAU * i / 60.0
		var r := h * 0.26
		var p := Vector2(sin(a) * r * (1.0 - 0.55 * pow(maxf(cos(a), 0.0), 2.0)), -cos(a) * r * 1.3)
		drop.append(Vector2(h * 0.42, h * 0.56) + p)
	_poly(mask, drop)
	_text(mask, "Quokka Lube", "pacifico", Rect2(h * 0.78, h * 0.1, w - h * 0.84, h * 0.8))


func _draw_brakebird(mask: Image, w: float, h: float) -> void:
	_text(mask, "BRAKEBIRD", "saira_stencil_one", Rect2(w * 0.04, h * 0.08, w * 0.72, h * 0.84))
	for i in 3:
		var x := w * (0.8 + 0.06 * i)
		_poly(mask, PackedVector2Array([Vector2(x, h * 0.2), Vector2(x + w * 0.05, h * 0.5), Vector2(x, h * 0.8),
			Vector2(x - w * 0.025, h * 0.8), Vector2(x + w * 0.025, h * 0.5), Vector2(x - w * 0.025, h * 0.2)]))


func _draw_fizzbolt(mask: Image, w: float, h: float) -> void:
	_rounded_rect(mask, Rect2(w * 0.02, h * 0.12, w * 0.96, h * 0.76), h * 0.38)
	_rounded_rect(mask, Rect2(w * 0.045, h * 0.17, w * 0.91, h * 0.66), h * 0.33, false)
	_text(mask, "FIZZBOLT", "monoton", Rect2(w * 0.1, h * 0.24, w * 0.8, h * 0.52))


func _draw_grip_owl(mask: Image, w: float, h: float) -> void:
	_rounded_rect(mask, Rect2(w * 0.02, h * 0.14, w * 0.96, h * 0.72), h * 0.1)
	for x in [0.13, 0.27]:
		_circle(mask, Vector2(w * x, h * 0.5), h * 0.17, false)
		_circle(mask, Vector2(w * x, h * 0.5), h * 0.07)
	_text(mask, "GRIP OWL", "atkinson_bold", Rect2(w * 0.38, h * 0.2, w * 0.57, h * 0.6), false)


func _draw_kettlecomet(mask: Image, w: float, h: float) -> void:
	_circle(mask, Vector2(h * 0.62, h * 0.32), h * 0.16)
	for i in 3:
		_stroke(mask, PackedVector2Array([Vector2(h * 0.5 - h * 0.12 * i, h * (0.42 + 0.08 * i)), Vector2(h * 0.08, h * (0.6 + 0.08 * i))]), h * 0.05)
	_text(mask, "Kettlecomet", "pacifico", Rect2(h * 0.92, h * 0.12, w - h * 0.98, h * 0.76))


func _draw_apexberry(mask: Image, w: float, h: float) -> void:
	for p: Vector2 in [Vector2(0.3, 0.6), Vector2(0.52, 0.62), Vector2(0.41, 0.42)]:
		_circle(mask, p * h, h * 0.15)
	_poly(mask, PackedVector2Array([Vector2(h * 0.4, h * 0.3), Vector2(h * 0.5, h * 0.08), Vector2(h * 0.58, h * 0.12), Vector2(h * 0.46, h * 0.32)]))
	_text(mask, "APEXBERRY", "racing_sans_one", Rect2(h * 0.8, h * 0.2, w - h * 0.86, h * 0.6))


## A gear: teeth round a ring.
func _gear(mask: Image, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 160:
		var a := TAU * i / 160.0
		var tooth := 1.0 if fposmod(a / TAU * 10.0, 1.0) < 0.5 else 0.0
		pts.append(c + Vector2(cos(a), sin(a)) * r * (0.82 + 0.18 * tooth))
	_poly(mask, pts)
	_circle(mask, c, r * 0.4, false)
