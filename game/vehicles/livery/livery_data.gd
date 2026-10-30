class_name LiveryData
extends RefCounted
## Livery files (docs/VEHICLE_PACKAGE.md §12, PKG-10, schema data/schemas/livery.schema.json):
## base paint and up to 100 layers (shapes, text, race numbers), each a box projected onto the
## body along its normal. Layers live in the model's own space (under CarVisual.model_root), so
## they stay put through Orient, Scale and a class's fitting; `frame` maps that space to the car
## frame in metres, for moving a livery to another car.
##
## A livery can come from anywhere (a file, another player), so clean() never trusts it: unknown
## keys, shapes and fonts go, numbers are clamped and snapped, axes made square again and each
## group's layers put together. clean() of a cleaned livery changes nothing, so its hash holds.

const SCHEMA := "noss.livery/1"
const CATALOG := "res://content/liveries/catalog.json"
const MAX_LAYERS := 100
const MAX_GROUPS := 32
## Liveries a car keeps, at most.
const MAX_PER_CAR := 32
const MAX_TEXT := 32
const MAX_NAME := 48
## A livery file imported, and one sent online, at most (bytes).
const MAX_IMPORT_BYTES := 262144
const MAX_NET_BYTES := 65536
const KINDS := ["shape", "text", "number"]
const SLOTS := ["primary", "secondary", "tertiary"]
## What a layer lands on: the paint slots and the glass.
const SURFACES := ["primary", "secondary", "tertiary", "glass"]
## Colours a layer can take from the car's paint instead of its own.
const LINKS := ["primary", "secondary", "tertiary", "contrast"]
## Layer finishes; "paint" is the finish of the paint under it.
const FINISHES := ["paint", "gloss", "satin", "matte", "metallic", "chrome", "pearl"]
const SLOT_FINISHES := ["solid", "metallic", "pearl", "matte", "chrome"]
const DEFAULT_FONT := "atkinson_bold"
## Coordinates (model units) stay within this, and are kept to this step.
const LIMIT := 100000.0
const SNAP := 0.0001
const MIN_SIZE := 0.0001

static var _catalog := {}
static var _id_re: RegEx


## The shapes and fonts a livery may use: {shapes: {id: entry}, fonts: {id: entry}, shape_list,
## font_list} (content/liveries/catalog.json).
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		var shapes := {}
		var fonts := {}
		var shape_list := []
		var font_list := []
		if data is Dictionary:
			for s: Dictionary in data.get("shapes", []):
				shapes[s.id] = s
				shape_list.append(s)
			for f: Dictionary in data.get("fonts", []):
				fonts[f.id] = f
				font_list.append(f)
		_catalog = { "shapes": shapes, "fonts": fonts, "shape_list": shape_list, "font_list": font_list }
	return _catalog


static func shape(id: String) -> Dictionary:
	return catalog().shapes.get(id, {})


static func font(id: String) -> Dictionary:
	return catalog().fonts.get(id, {})


## A livery id or car id that is safe as a file name.
static func valid_id(id: Variant) -> bool:
	if _id_re == null:
		_id_re = RegEx.create_from_string("^[A-Za-z0-9-]{1,64}$")
	return id is String and _id_re.search(id) != null


## A new, empty livery for the car `car` ({id, model, name}).
static func new_livery(livery_name: String, car := {}, frame := {}) -> Dictionary:
	var d := { "schema": SCHEMA, "id": PackageWriter.new_uuid(), "name": livery_name, "layers": [], "groups": [] }
	if not car.is_empty():
		d.car = car
	if not frame.is_empty():
		d.frame = frame
	return clean(d)


## A layer of `kind` ("shape" with `shape_id`, "text", "number") centred at `at` facing `normal`.
static func new_layer(kind: String, at: Vector3, normal: Vector3, right: Vector3, size: Vector2, shape_id := "rect") -> Dictionary:
	var l := { "kind": kind, "at": _arr(at), "normal": _arr(normal), "right": _arr(right), "size": [size.x, size.y],
		"depth": maxf(absf(size.x), absf(size.y)) * 0.5, "color": "#FFFFFF", "opacity": 1.0, "finish": "paint",
		"on": SLOTS.duplicate() }
	match kind:
		"shape":
			l.shape = shape_id
			l.params = shape(shape_id).get("params", []).duplicate()
		"text":
			l.text = "nOSS"
			l.font = DEFAULT_FONT
		"number":
			l.number = "auto"
			l.font = DEFAULT_FONT
	return clean_layer(l, {})


## The car frame of a package's fit.json: model space to the vehicle frame in metres, before a
## class scales the car (as the Fitting Bay shows it), and the model's bounds there.
static func frame_of(fit: Dictionary) -> Dictionary:
	var xf := car_xform(fit)
	var env: Dictionary = fit.get("envelope", {})
	var box := AABB()
	if env.get("min") is Array and env.get("max") is Array:
		var lo := _vec(env.min, Vector3.ZERO)
		box = xf * AABB(lo, _vec(env.max, Vector3.ZERO) - lo)
	var b := xf.basis
	return { "to_car": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, xf.origin.x, xf.origin.y, xf.origin.z],
		"bounds": { "min": _arr(box.position), "max": _arr(box.end) } }


## Model space to the vehicle frame in metres (fit.json model_transform).
static func car_xform(fit: Dictionary) -> Transform3D:
	var mt: Dictionary = fit.get("model_transform", {})
	var r: Array = mt.get("rotation_deg", [0, 0, 0])
	var basis := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	return Transform3D(basis.scaled(Vector3.ONE * float(mt.get("scale", 1.0))), _vec(mt.get("offset_m", [0, 0, 0]), Vector3.ZERO))


## A livery's frame as a transform and box: [to_car, bounds]; identity and an empty box without one.
static func frame(livery: Dictionary) -> Array:
	var f: Dictionary = livery.get("frame", {})
	var t: Array = f.get("to_car", [])
	if t.size() != 12:
		return [Transform3D.IDENTITY, AABB()]
	var xf := Transform3D(Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8])), Vector3(t[9], t[10], t[11]))
	var lo := _vec(f.bounds.min, Vector3.ZERO)
	return [xf, AABB(lo, _vec(f.bounds.max, Vector3.ZERO) - lo)]


## Canonical bytes: sorted keys, no spaces (hashed and sent online as they are).
static func to_bytes(livery: Dictionary) -> PackedByteArray:
	return JSON.stringify(livery, "", true).to_utf8_buffer()


static func hash_of(livery: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(to_bytes(livery))
	return "sha256:" + ctx.finish().hex_encode()


## A livery from file or network bytes, cleaned; {} if it isn't one or is over `cap` bytes.
static func parse(bytes: PackedByteArray, cap := MAX_IMPORT_BYTES) -> Dictionary:
	if bytes.is_empty() or bytes.size() > cap:
		return {}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	return clean(json.data)


## True if any shown layer lands on the glass.
static func uses_glass(livery: Dictionary) -> bool:
	for l: Dictionary in livery.get("layers", []):
		if not l.get("hidden", false) and "glass" in l.get("on", []):
			return true
	return false


## A layer's name for lists and screen readers: "Chevrons", "Text NOSS", "Number 42".
static func layer_name(layer: Dictionary) -> String:
	match String(layer.get("kind", "")):
		"text":
			return "Text " + String(layer.get("text", ""))
		"number":
			var n := String(layer.get("number", "auto"))
			return "Race number" if n == "auto" else "Number " + n
	return String(shape(String(layer.get("shape", ""))).get("name", "Shape"))


# --- cleaning --------------------------------------------------------------------


## The livery `d` made safe, or {} if it isn't a livery at all.
static func clean(d: Variant) -> Dictionary:
	if not d is Dictionary or not d.get("layers") is Array:
		return {}
	var schema: Variant = d.get("schema", SCHEMA)
	if not schema is String or schema != SCHEMA:
		return {}
	var out := { "schema": SCHEMA }
	out.id = d.id if valid_id(d.get("id")) else PackageWriter.new_uuid()
	out.name = _text(d.get("name"), MAX_NAME, "Livery")
	var car: Variant = d.get("car")
	if car is Dictionary:
		var c := {}
		for key: String in ["id", "model", "name"]:
			var limit: int = { "id": 64, "model": 80, "name": 96 }[key]
			if car.get(key) is String and not String(car[key]).is_empty():
				c[key] = _text(car[key], limit, "")
		out.car = c
	var f: Variant = d.get("frame")
	if f is Dictionary and f.get("to_car") is Array and (f.to_car as Array).size() == 12 and f.get("bounds") is Dictionary:
		var t := []
		for v: Variant in f.to_car:
			t.append(snappedf(_num(v, -LIMIT, LIMIT, 0.0), 0.000001))
		var lo := _vec(f.bounds.get("min"), Vector3.ZERO)
		var hi := _vec(f.bounds.get("max"), Vector3.ZERO)
		out.frame = { "to_car": t, "bounds": { "min": _arr(lo.min(hi)), "max": _arr(lo.max(hi)) } }
	var base: Variant = d.get("base")
	if base is Dictionary:
		var b := {}
		for slot: String in SLOTS:
			var s: Variant = base.get(slot)
			if s is Dictionary and _color(s.get("color")) and s.get("finish") in SLOT_FINISHES:
				b[slot] = { "color": String(s.color).to_upper(), "finish": s.finish }
		out.base = b
	var groups := []
	var group_ids := {}
	for g: Variant in d.get("groups", []) if d.get("groups") is Array else []:
		if g is Dictionary and groups.size() < MAX_GROUPS:
			var gid := int(_num(g.get("id"), 0, 999, 0))
			if gid >= 1 and not group_ids.has(gid):
				group_ids[gid] = true
				groups.append({ "id": gid, "name": _text(g.get("name"), MAX_NAME, "Group %d" % gid) })
	var layers := []
	for l: Variant in (d.layers as Array).slice(0, MAX_LAYERS):
		var c := clean_layer(l, group_ids)
		if not c.is_empty():
			layers.append(c)
	layers = _group_runs(layers)
	var used := {}
	for l: Dictionary in layers:
		used[int(l.get("group", 0))] = true
	out.groups = groups.filter(func(g: Dictionary) -> bool: return used.has(int(g.id)))
	out.layers = layers
	return out


## One layer made safe, or {} to drop it. `group_ids`: the livery's groups (id -> true).
static func clean_layer(l: Variant, group_ids: Dictionary) -> Dictionary:
	if not l is Dictionary or not l.get("kind") in KINDS:
		return {}
	var out := { "kind": l.kind }
	match String(l.kind):
		"shape":
			var s := shape(String(l.get("shape", "")) if l.get("shape") is String else "")
			if s.is_empty():
				return {}
			out.shape = s.id
			var defaults: Array = s.get("params", [])
			var given: Array = l.get("params", []) if l.get("params") is Array else []
			var params := []
			for i in defaults.size():
				params.append(snappedf(_num(given[i] if i < given.size() else defaults[i], 0.0, 1.0, float(defaults[i])), SNAP))
			out.params = params
		"text":
			var t := _text(l.get("text"), MAX_TEXT, "")
			if t.is_empty():
				return {}
			out.text = t
			out.font = _font(l.get("font"))
		"number":
			var n: Variant = l.get("number", "auto")
			out.number = n if n is String and (n == "auto" or (String(n).length() <= 3 and String(n).is_valid_int() and not String(n).begins_with("-") and not String(n).begins_with("+"))) else "auto"
			out.font = _font(l.get("font"))
	out.at = _arr(_vec(l.get("at"), Vector3.ZERO))
	var normal := _vec(l.get("normal"), Vector3.UP)
	if normal.is_zero_approx():
		normal = Vector3.UP
	if absf(normal.length() - 1.0) > 0.001:
		normal = normal.normalized()
	var right := _vec(l.get("right"), Vector3.RIGHT)
	if absf(right.dot(normal)) > 0.001 or absf(right.length() - 1.0) > 0.001:
		right = (right - normal * right.dot(normal))
		if right.length() < 0.01:
			right = normal.cross(Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
		right = right.normalized()
	out.normal = _arr(normal)
	out.right = _arr(right)
	var size: Array = l.get("size", []) if l.get("size") is Array else []
	var w := _size(size[0] if size.size() > 0 else 1.0)
	var h := _size(size[1] if size.size() > 1 else 1.0)
	out.size = [w, h]
	out.depth = snappedf(_num(l.get("depth"), MIN_SIZE, LIMIT, maxf(absf(w), absf(h)) * 0.5), SNAP)
	if out.depth < MIN_SIZE:
		out.depth = MIN_SIZE
	var color: Variant = l.get("color", "#FFFFFF")
	out.color = color if color is String and color in LINKS else String(color).to_upper() if _color(color) else "#FFFFFF"
	out.opacity = snappedf(_num(l.get("opacity"), 0.0, 1.0, 1.0), SNAP)
	out.finish = l.finish if l.get("finish") in FINISHES else "paint"
	var on := []
	for s: Variant in l.get("on", SLOTS) if l.get("on") is Array else SLOTS:
		if s in SURFACES and s not in on:
			on.append(s)
	on.sort_custom(func(a: String, b: String) -> bool: return SURFACES.find(a) < SURFACES.find(b))
	out.on = on
	for key: String in ["cut", "mirror", "hidden"]:
		if l.get(key) is bool and l[key]:
			out[key] = true
	var g := int(_num(l.get("group"), 0, 999, 0))
	if g > 0 and group_ids.has(g):
		out.group = g
	return out


## Each group's layers together, where its lowest layer is.
static func _group_runs(layers: Array) -> Array:
	var out := []
	var placed := {}
	for l: Dictionary in layers:
		var g := int(l.get("group", 0))
		if g == 0:
			out.append(l)
		elif not placed.has(g):
			placed[g] = true
			for m: Dictionary in layers:
				if int(m.get("group", 0)) == g:
					out.append(m)
	return out


static func _font(v: Variant) -> String:
	return v if v is String and catalog().fonts.has(v) else DEFAULT_FONT


static func _size(v: Variant) -> float:
	var x := _num(v, -LIMIT, LIMIT, 1.0)
	var s := snappedf(maxf(absf(x), MIN_SIZE), SNAP)
	if s < MIN_SIZE:
		s = MIN_SIZE
	return -s if x < 0.0 else s


## Printable text: control characters out, trimmed, at most `limit` characters.
static func _text(v: Variant, limit: int, fallback: String) -> String:
	if not v is String:
		return fallback
	var out := ""
	for i in String(v).length():
		var c := String(v).unicode_at(i)
		if c >= 32 and c != 127 and not (c >= 0x80 and c < 0xA0):
			out += String.chr(c)
	out = out.strip_edges().left(limit).strip_edges()
	return out if out else fallback


static func _color(v: Variant) -> bool:
	if not v is String or String(v).length() != 7 or not String(v).begins_with("#"):
		return false
	for i in range(1, 7):
		if "0123456789abcdefABCDEF".find(String(v)[i]) < 0:
			return false
	return true


static func _num(v: Variant, lo: float, hi: float, fallback: float) -> float:
	if not (v is float or v is int):
		return fallback
	var x := float(v)
	if is_nan(x) or is_inf(x):
		return fallback
	return clampf(x, lo, hi)


static func _vec(v: Variant, fallback: Vector3) -> Vector3:
	if not v is Array or (v as Array).size() != 3:
		return fallback
	return Vector3(_num(v[0], -LIMIT, LIMIT, 0.0), _num(v[1], -LIMIT, LIMIT, 0.0), _num(v[2], -LIMIT, LIMIT, 0.0))


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, SNAP), snappedf(v.y, SNAP), snappedf(v.z, SNAP)]
