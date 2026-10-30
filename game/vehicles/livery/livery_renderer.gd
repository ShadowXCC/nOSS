class_name LiveryRenderer
extends RefCounted
## Packs a livery for the paint and glass shaders (livery.gdshaderinc): per surface (a paint slot
## or the glass), the shown layers that land on it, 6 vec4 each. Linked colours stay links, so
## AI and team paint (CarVisual.set_paint) recolour them without packing again.

const STRIDE := 6
const MAX_VEC4 := LiveryData.MAX_LAYERS * STRIDE
const FINISH_CODES := { "paint": 0, "gloss": 1, "satin": 2, "matte": 3, "metallic": 4, "chrome": 5, "pearl": 6 }
const SOURCE_CODES := { "primary": 1, "secondary": 2, "tertiary": 3, "contrast": 4 }
const FLAG_FLIP := 1
const FLAG_CUT := 2
const FLAG_MIRROR := 4
const FLAG_READABLE := 8
const FLAG_TEXT := 16
## The picture keeps its shape inside the box (a race number set to auto: its width varies).
const FLAG_FIT := 32
## Atlas shapes are coded from here: 100 + their cell, plus 256 for each further cell they span.
const ATLAS_CODE := 100
const SHAPES_ATLAS := "res://content/liveries/shapes.png"

static var _shapes: Texture2D


## The layers on `surface` ("primary", "secondary", "tertiary" or "glass"), bottom first:
## [PackedVector4Array of MAX_VEC4, count]. `text_rects`: each text or number layer's rect in
## the text atlas (LiveryText), by its index in the livery; those without one are left out.
static func pack(livery: Dictionary, surface: String, text_rects := {}) -> Array:
	var data := PackedVector4Array()
	data.resize(MAX_VEC4)
	var shown := []
	var layers: Array = livery.get("layers", [])
	for i in layers.size():
		var l: Dictionary = layers[i]
		if l.get("hidden", false) or surface not in l.get("on", []):
			continue
		if l.kind != "shape" and not text_rects.has(i):
			continue
		shown.append([l, i])
	# Where each group starts in this list: a group's cut-outs reach down to there.
	var group_lo := {}
	for k in shown.size():
		var g := int(shown[k][0].get("group", 0))
		if g and not group_lo.has(g):
			group_lo[g] = k
	for k in shown.size():
		var l: Dictionary = shown[k][0]
		var at := _vec(l.at)
		var normal := _vec(l.normal)
		var right := _vec(l.right)
		var up := normal.cross(right)
		var w := float(l.size[0])
		var h := float(l.size[1])
		var flags := 0
		if (w < 0.0) != (h < 0.0):
			flags |= FLAG_FLIP
		if l.get("cut", false):
			flags |= FLAG_CUT
		if l.get("mirror", false):
			flags |= FLAG_MIRROR
		var code := 0
		var params := Vector4.ZERO
		if l.kind == "shape":
			var s := LiveryData.shape(String(l.shape))
			if s.get("readable", false):
				flags |= FLAG_READABLE
			code = int(s.get("index", 0))
			if s.get("kind") == "atlas":
				code += ATLAS_CODE + 256 * (int(s.get("span", 1)) - 1)
			var p: Array = l.get("params", [])
			for j in mini(p.size(), 4):
				params[j] = float(p[j])
		else:
			flags |= FLAG_TEXT | FLAG_READABLE
			if l.kind == "number" and l.get("number") == "auto":
				flags |= FLAG_FIT
			var r: Rect2 = text_rects[shown[k][1]]
			params = Vector4(r.position.x, r.position.y, r.size.x, r.size.y)
		var color := String(l.get("color", "#FFFFFF"))
		var source := int(SOURCE_CODES.get(color, 0))
		var linear := Color.html(color).srgb_to_linear() if source == 0 else Color.WHITE
		var base := k * STRIDE
		data[base] = Vector4(at.x, at.y, at.z, float(l.get("depth", maxf(absf(w), absf(h)) * 0.5)))
		data[base + 1] = _v4(right / w, code)
		data[base + 2] = _v4(up / h, flags)
		data[base + 3] = params
		data[base + 4] = Vector4(linear.r, linear.g, linear.b, float(l.get("opacity", 1.0)))
		data[base + 5] = Vector4(source, FINISH_CODES.get(l.get("finish", "paint"), 0),
			group_lo.get(int(l.get("group", 0)), 0), absf(w) / maxf(absf(h), 1e-6))
	return [data, shown.size()]


## The colours linked layers take, linear: primary, secondary, tertiary, contrast. A slot the car
## lacks takes the one before it.
static func slot_colors(colors: Dictionary) -> PackedVector4Array:
	var primary: Color = colors.get("primary", Color(0.8, 0.8, 0.8))
	var secondary: Color = colors.get("secondary", primary)
	var tertiary: Color = colors.get("tertiary", secondary)
	var out := PackedVector4Array()
	for c: Color in [primary, secondary, tertiary, contrast(primary)]:
		var l := c.srgb_to_linear()
		out.append(Vector4(l.r, l.g, l.b, 1.0))
	return out


## Near white on dark paint, near black on light.
static func contrast(c: Color) -> Color:
	return Color(0.08, 0.08, 0.09) if c.get_luminance() > 0.5 else Color(0.95, 0.95, 0.95)


## The car's middle (the vehicle frame's x across its bounds) as a plane in model space:
## (normal, offset), for mirrored layers.
static func mirror_plane(model_xform: Transform3D, bounds: AABB) -> Vector4:
	var inverse := model_xform.affine_inverse()
	var n := (model_xform.basis.transposed() * Vector3.RIGHT).normalized()
	var p := inverse * bounds.get_center()
	return Vector4(n.x, n.y, n.z, n.dot(p))


## The shared shape atlas (content/liveries/shapes.png), or null before it's made.
static func shapes_atlas() -> Texture2D:
	if _shapes == null and ResourceLoader.exists(SHAPES_ATLAS):
		_shapes = load(SHAPES_ATLAS)
	return _shapes


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _v4(v: Vector3, w: float) -> Vector4:
	return Vector4(v.x, v.y, v.z, w)
