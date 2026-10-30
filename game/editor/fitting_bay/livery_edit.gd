class_name LiveryEdit
extends RefCounted
## Edits to a Fitting Bay draft's liveries (docs/VEHICLE_PACKAGE.md §12, the Livery step): which
## livery the car wears and which is being edited, its base paint, and its layers: adding,
## placing, sizing, ordering, grouping, and undo and redo. Places and sizes are the car frame in
## metres before a class scales the car, as the bay shows them; the livery keeps them in the
## model's own space. Each change returns what to say ("Chevrons added"), or "".

## Where a layer is put from: its side of the car, the way it projects (car frame), and which
## way is right on it, as someone facing that side sees it.
const SIDES := {
	"left": [Vector3.RIGHT, Vector3.BACK], "right": [Vector3.LEFT, Vector3.FORWARD], "top": [Vector3.UP, Vector3.LEFT],
	"front": [Vector3.BACK, Vector3.RIGHT], "back": [Vector3.FORWARD, Vector3.LEFT],
}
## Vehicle frame: +X left, +Z forward. Vector3.BACK is +Z, FORWARD -Z.
const SIDE_NAMES := [["left", "Left"], ["right", "Right"], ["top", "Top"], ["front", "Front"], ["back", "Back"]]
const FLIPS := [["none", "None"], ["across", "Across"], ["up", "Up and down"], ["both", "Both"]]
## Undo steps kept.
const HISTORY := 200
const DEFAULT_DEPTH := 0.25
## Layer sizes, metres.
const MIN_SIZE := 0.02
const MAX_SIZE := 8.0

var draft: FittingDraft
## The picked layer of the edited livery (-1: none); kept by the draft, as undo puts it back.
var layer: int:
	get:
		return draft.livery_layer
	set(value):
		draft.livery_layer = value
## Placement moves the picked layer's whole group with it.
var whole_group := false
## Where the last layer went: new ones go there too.
var side := "left"

var _ray_meshes: Array = [] # [root <- mesh, TriangleMesh, box in root space]
var _ray_key := ""


func _init(fitting: FittingDraft) -> void:
	draft = fitting
	if draft.livery_history == null:
		draft.livery_history = EditHistory.new(HISTORY)
	_fix_layer()


# --- liveries --------------------------------------------------------------------


## The livery being edited, or {}.
func livery() -> Dictionary:
	for l: Dictionary in draft.liveries:
		if l.id == draft.editing:
			return l
	return {}


func layers() -> Array:
	return livery().get("layers", [])


func current() -> Dictionary:
	var ls := layers()
	return ls[layer] if layer >= 0 and layer < ls.size() else {}


## A new livery with the car's paint as its base, worn and edited from now on.
func new_livery() -> String:
	if draft.liveries.size() >= LiveryData.MAX_PER_CAR:
		return "Too many liveries"
	var l := LiveryData.new_livery(_free_name("Livery"), car_info(), LiveryData.frame_of(draft.fit))
	var base := {}
	for slot: String in draft.paint.get("slots", {}):
		var s: Dictionary = draft.paint.slots[slot]
		base[slot] = { "color": s.color, "finish": s.finish }
	l.base = base
	_act("New livery", func() -> void:
		draft.liveries.append(l)
		draft.editing = l.id
		draft.worn = l.id
		layer = -1)
	return "Livery added"


## A copy of the edited livery (a new id), edited from now on.
func copy_livery() -> String:
	var src := livery()
	if src.is_empty():
		return ""
	if draft.liveries.size() >= LiveryData.MAX_PER_CAR:
		return "Too many liveries"
	var l: Dictionary = src.duplicate(true)
	l.id = PackageWriter.new_uuid()
	l.name = _free_name(String(src.name).left(LiveryData.MAX_NAME - 5) + " copy")
	_act("Copy livery", func() -> void:
		draft.liveries.insert(_index_of(draft.liveries, src) + 1, l)
		draft.editing = l.id)
	return "Copied"


func delete_livery() -> String:
	var l := livery()
	if l.is_empty():
		return ""
	_act("Delete livery", func() -> void:
		var i := _index_of(draft.liveries, l)
		draft.liveries.remove_at(i)
		if draft.worn == l.id:
			draft.worn = ""
		draft.editing = draft.liveries[mini(i, draft.liveries.size() - 1)].id if not draft.liveries.is_empty() else ""
		layer = -1)
	return "Livery deleted"


func rename(new_name: String) -> void:
	var l := livery()
	var n := LiveryData._text(new_name, LiveryData.MAX_NAME, "")
	if l.is_empty() or n.is_empty() or n == l.name:
		return
	_act("Rename", func() -> void: l.name = n, true)


## Wears livery `id` ("": plain paint).
func wear(id: String) -> void:
	if id == draft.worn:
		return
	_act("Wear", func() -> void: draft.worn = id)


func edit(id: String) -> void:
	if id == draft.editing:
		return
	draft.editing = id
	layer = layers().size() - 1


## The edited livery's base paint for `slot`.
func set_base(slot: String, color: Color, finish: String) -> void:
	var l := livery()
	if l.is_empty():
		return
	_act("Paint", func() -> void:
		var base: Dictionary = l.get("base", {})
		base[slot] = { "color": "#" + color.to_html(false).to_upper(), "finish": finish }
		l.base = base, true)


func car_info() -> Dictionary:
	return { "id": draft.id, "name": draft.car_name }


# --- layers ----------------------------------------------------------------------


## Adds a layer of `kind` ("shape" with `shape_id`, "text", "number") over the others, on the
## side the last one went.
func add(kind: String, shape_id := "rect") -> String:
	var l := livery()
	if l.is_empty():
		new_livery()
		l = livery()
	if layers().size() >= LiveryData.MAX_LAYERS:
		return "Too many layers"
	var height := 0.4 if kind == "number" else 0.22 if kind == "text" else 0.5
	var width := height
	if kind == "shape":
		width = height * int(LiveryData.shape(shape_id).get("span", 1))
	elif kind == "text":
		width = height * LiveryText.aspect("nOSS", LiveryData.DEFAULT_FONT)
	else:
		width = height * 1.15
	var spot := _side_spot(side, Vector2.ZERO)
	var made := LiveryData.new_layer(kind, Vector3.ZERO, Vector3.UP, Vector3.RIGHT, Vector2.ONE, shape_id)
	made.color = "contrast"
	var name := LiveryData.layer_name(made)
	_act(name + " added", func() -> void:
		l.layers.append(made)
		layer = l.layers.size() - 1
		_place_frame(made, spot.at, spot.normal, spot.right)
		_set_size_m(made, Vector2(width, height))
		made.depth = _to_model_len(maxf(DEFAULT_DEPTH, height * 0.5)))
	return name + " added"


func delete_layer() -> String:
	var l := livery()
	var c := current()
	if c.is_empty():
		return ""
	var name := LiveryData.layer_name(c)
	_act("Delete", func() -> void:
		l.layers.remove_at(layer)
		_regroup(l)
		layer = mini(layer, l.layers.size() - 1))
	return name + " deleted"


func duplicate_layer() -> String:
	var l := livery()
	var c := current()
	if c.is_empty():
		return ""
	if layers().size() >= LiveryData.MAX_LAYERS:
		return "Too many layers"
	_act("Duplicate", func() -> void:
		var copy: Dictionary = c.duplicate(true)
		var shift := _to_model_len(0.1)
		var at := _v(copy.at) + _v(copy.right) * shift - _v(copy.normal).cross(_v(copy.right)) * shift
		copy.at = _a(at)
		l.layers.insert(layer + 1, copy)
		layer += 1)
	return "Duplicated"


## A copy across the car's middle. Pictures that read (text, numbers, logos) still read there.
func mirror_copy() -> String:
	var l := livery()
	var c := current()
	if c.is_empty():
		return ""
	if layers().size() >= LiveryData.MAX_LAYERS:
		return "Too many layers"
	_act("Mirror copy", func() -> void:
		var copy: Dictionary = c.duplicate(true)
		var base := car_xform()
		var inv := base.affine_inverse()
		var mid := _mid_x()
		var reflect := func(p: Vector3) -> Vector3: return Vector3(2.0 * mid - p.x, p.y, p.z)
		var reflect_dir := func(d: Vector3) -> Vector3: return Vector3(-d.x, d.y, d.z)
		copy.at = _a(inv * reflect.call(base * _v(c.at)))
		copy.normal = _a((inv.basis * reflect_dir.call(base.basis * _v(c.normal))).normalized())
		var right: Vector3 = (inv.basis * reflect_dir.call(base.basis * _v(c.right))).normalized()
		if _readable(c):
			right = -right
		else:
			copy.size = [c.size[0], -float(c.size[1])]
		copy.right = _a(right)
		copy.erase("mirror")
		l.layers.insert(layer + 1, copy)
		layer += 1)
	return "Mirror copy"


## Moves the picked layer (or its group) up, down, to the top or to the bottom.
func reorder(where: String) -> String:
	var l := livery()
	var c := current()
	if c.is_empty():
		return ""
	var ls: Array = l.layers
	var to := { "up": layer + 1, "down": layer - 1, "top": ls.size() - 1, "bottom": 0 }.get(where, layer) as int
	to = clampi(to, 0, ls.size() - 1)
	if to == layer:
		return "Already there"
	_act("Order", func() -> void:
		ls.remove_at(layer)
		ls.insert(to, c)
		# Moving out of its group's run leaves the group.
		var g := int(c.get("group", 0))
		if g and not _in_run(ls, to, g):
			c.erase("group")
		_regroup(l)
		layer = _index_of(l.layers, c))
	return { "up": "Moved up", "down": "Moved down", "top": "On top", "bottom": "At the bottom" }.get(where, "")


## Sets one of the picked layer's own values (colour, opacity, finish, text…). With `merge` a
## run of them (a slider's drag) is one undo step.
func set_value(key: String, value: Variant, merge := false) -> void:
	var c := current()
	if c.is_empty() or c.get(key) == value:
		return
	_act(key.capitalize(), func() -> void:
		if value == null or (value is bool and not value and key in ["cut", "mirror", "hidden"]):
			c.erase(key)
		else:
			c[key] = value
		if key in ["text", "font", "number"]:
			_fit_text(c), merge)


## What the picked layer lands on: `surface` on or off.
func set_on(surface: String, on: bool) -> void:
	var c := current()
	if c.is_empty():
		return
	var list: Array = (c.on as Array).duplicate()
	if on == (surface in list):
		return
	if on:
		list.append(surface)
	else:
		list.erase(surface)
	list.sort_custom(func(a: String, b: String) -> bool: return LiveryData.SURFACES.find(a) < LiveryData.SURFACES.find(b))
	set_value("on", list)


## Puts the picked layer in group `g` (0: none; -1: a new group).
func set_group(g: int) -> String:
	var l := livery()
	var c := current()
	if c.is_empty():
		return ""
	if g < 0:
		var groups: Array = l.get("groups", [])
		if groups.size() >= LiveryData.MAX_GROUPS:
			return "Too many groups"
		g = 1
		while groups.any(func(x: Dictionary) -> bool: return int(x.id) == g):
			g += 1
	_act("Group", func() -> void:
		var groups: Array = l.get("groups", [])
		if g > 0 and not groups.any(func(x: Dictionary) -> bool: return int(x.id) == g):
			groups.append({ "id": g, "name": "Group %d" % g })
		l.groups = groups
		if g > 0:
			c.group = g
		else:
			c.erase("group")
		_regroup(l)
		layer = _index_of(l.layers, c))
	return "Group %d" % g if g > 0 else "Not grouped"


func undo() -> String:
	var said := draft.livery_history.undo_last()
	_fix_layer()
	return "Undone: " + said if said else "Nothing to undo"


func redo() -> String:
	var said := draft.livery_history.redo_next()
	_fix_layer()
	return "Redone: " + said if said else "Nothing to redo"


# --- placement ---------------------------------------------------------------------


## Model space to the car frame in metres.
func car_xform() -> Transform3D:
	return LiveryData.car_xform(draft.fit)


## The picked layer's place in metres: {side, along, height, size (larger side), stretch (width
## over height), turn (degrees), flip, depth}.
func placement() -> Dictionary:
	var c := current()
	if c.is_empty():
		return {}
	var base := car_xform()
	var at := base * _v(c.at)
	var n := (base.basis * _v(c.normal)).normalized()
	var r := (base.basis * _v(c.right)).normalized()
	var s := nearest_side(n)
	var axes := _axes(s)
	var default_right: Vector3 = SIDES[s][1]
	default_right = (default_right - n * default_right.dot(n)).normalized()
	var turn := rad_to_deg(default_right.signed_angle_to(r, n))
	var scale := _scale()
	var w := absf(float(c.size[0])) * scale
	var h := absf(float(c.size[1])) * scale
	var flip := "none"
	if float(c.size[0]) < 0.0 and float(c.size[1]) < 0.0:
		flip = "both"
	elif float(c.size[0]) < 0.0:
		flip = "across"
	elif float(c.size[1]) < 0.0:
		flip = "up"
	return { "side": s, "along": at.dot(axes[0]), "height": at.dot(axes[1]), "size": maxf(w, h), "stretch": w / maxf(h, 1e-6),
		"turn": turn, "flip": flip, "depth": float(c.depth) * scale }


## The side whose direction `n` (car frame) is nearest.
static func nearest_side(n: Vector3) -> String:
	var best := "left"
	var dot := -INF
	for s: String in SIDES:
		var d: float = (SIDES[s][0] as Vector3).dot(n)
		if d > dot:
			dot = d
			best = s
	return best


## Puts the picked layer on side `s`, where it is along and up that side.
func place_side(s: String) -> String:
	var c := current()
	side = s
	if c.is_empty():
		return ""
	var p := placement()
	var spot := _side_spot(s, Vector2(p.along, p.height) if p.side == s else Vector2.ZERO, p.side != s)
	_transform_layer("Place", func(l: Dictionary) -> void: _place_frame(l, spot.at, spot.normal, spot.right, p.turn if p.side == s else 0.0))
	return "On the " + s if spot.hit else "Off the car"


## Moves the picked layer along its side (`key` "along" or "height", metres), onto the body.
func slide(key: String, value: float) -> void:
	var c := current()
	if c.is_empty():
		return
	var p := placement()
	var at := Vector2(value if key == "along" else p.along, value if key == "height" else p.height)
	var spot := _side_spot(p.side, at, false, (car_xform().basis * _v(c.normal)).normalized())
	_transform_layer("Move", func(l: Dictionary) -> void: l.at = _a(car_xform().affine_inverse() * spot.at), true)


## Puts the picked layer at a point on the body (model space, from the 3D view), facing out along
## `normal` (model space), keeping its turn.
func place_at(point: Vector3, normal: Vector3, merge := false) -> void:
	var c := current()
	if c.is_empty():
		return
	var base := car_xform()
	var n := (base.basis * normal).normalized()
	var turn: float = placement().turn
	var s := nearest_side(n)
	side = s
	_transform_layer("Move", func(l: Dictionary) -> void: _place_frame(l, base * point, n, SIDES[s][1], turn), merge)


func set_size(metres: float) -> void:
	var p := placement()
	if p.is_empty():
		return
	var k := clampf(metres, MIN_SIZE, MAX_SIZE) / maxf(p.size, 1e-6)
	_transform_layer("Size", func(l: Dictionary) -> void:
		l.size = [float(l.size[0]) * k, float(l.size[1]) * k]
		l.depth = maxf(float(l.depth), absf(float(l.size[1])) * 0.25), true, k)


## Width over height, keeping the larger side.
func set_stretch(ratio: float) -> void:
	var p := placement()
	if p.is_empty():
		return
	ratio = clampf(ratio, 0.05, 20.0)
	var big: float = p.size
	var wh := Vector2(big, big / ratio) if ratio >= 1.0 else Vector2(big * ratio, big)
	_transform_layer("Stretch", func(l: Dictionary) -> void: _set_size_m(l, wh, true), true)


## Turns the picked layer to `degrees` from its side's upright.
func set_turn(degrees: float) -> void:
	var c := current()
	if c.is_empty():
		return
	var base := car_xform()
	var n := (base.basis * _v(c.normal)).normalized()
	var r: Vector3 = (SIDES[nearest_side(n)][1] as Vector3)
	r = (r - n * r.dot(n)).normalized().rotated(n, deg_to_rad(degrees))
	_transform_layer("Turn", func(l: Dictionary) -> void: l.right = _a((base.basis.inverse() * r).normalized()), true)


## Turns by `degrees` more.
func turn_by(degrees: float) -> void:
	var p := placement()
	if not p.is_empty():
		set_turn(fposmod(float(p.turn) + degrees + 180.0, 360.0) - 180.0)


func set_flip(mode: String) -> void:
	var c := current()
	if c.is_empty():
		return
	_act("Flip", func() -> void:
		var w := absf(float(c.size[0]))
		var h := absf(float(c.size[1]))
		c.size = [-w if mode in ["across", "both"] else w, -h if mode in ["up", "both"] else h])


func set_depth(metres: float) -> void:
	var c := current()
	if c.is_empty():
		return
	_act("Depth", func() -> void: c.depth = _to_model_len(clampf(metres, 0.01, 4.0)), true)


# --- naming ------------------------------------------------------------------------


## The picked layer as a list shows it: "Layer 3 of 7: Chevrons".
func layer_label(i := -1) -> String:
	i = layer if i < 0 else i
	var ls := layers()
	if i < 0 or i >= ls.size():
		return "No layers"
	var l: Dictionary = ls[i]
	var said := "Layer %d of %d: %s" % [i + 1, ls.size(), LiveryData.layer_name(l)]
	if l.get("hidden", false):
		said += ", hidden"
	if l.get("cut", false):
		said += ", cut-out"
	if l.get("group"):
		said += ", group %d" % int(l.group)
	return said


# --- inside ------------------------------------------------------------------------


## Records `change` (done now) as one undo step named `name`: the liveries before and after.
func _act(name: String, change: Callable, merge := false) -> void:
	var before := _state()
	change.call()
	var after := _state()
	if before == after:
		return
	# The history is the draft's (it lasts through test drives, when the bay and this go): its
	# steps hold the draft weakly, or neither would ever be freed.
	var held: WeakRef = weakref(draft)
	draft.livery_history.act(name, LiveryEdit._restore.bind(held, after), LiveryEdit._restore.bind(held, before), false, merge)


func _state() -> PackedByteArray:
	return var_to_bytes({ "liveries": draft.liveries, "worn": draft.worn, "editing": draft.editing, "layer": layer })


static func _restore(held: WeakRef, state: PackedByteArray) -> void:
	var d := held.get_ref() as FittingDraft
	if d == null:
		return
	var s: Dictionary = bytes_to_var(state)
	d.liveries = (s.liveries as Array).duplicate(true)
	d.worn = s.worn
	d.editing = s.editing
	d.livery_layer = s.layer


func _fix_layer() -> void:
	if livery().is_empty() and not draft.liveries.is_empty():
		draft.editing = draft.liveries[0].id
	layer = clampi(layer, -1, layers().size() - 1)
	if layer < 0 and not layers().is_empty():
		layer = layers().size() - 1


## Applies `fn` to the picked layer, or to its whole group (each moved by how the picked one moved).
func _transform_layer(name: String, fn: Callable, merge := false, size_k := 1.0) -> void:
	var c := current()
	var g := int(c.get("group", 0))
	_act(name, func() -> void:
		var before := _frame_of(c)
		fn.call(c)
		if not whole_group or g == 0:
			return
		var delta := _frame_of(c) * before.affine_inverse()
		for o: Dictionary in layers():
			if is_same(o, c) or int(o.get("group", 0)) != g:
				continue
			if size_k != 1.0:
				o.at = _a(_v(c.at) + (_v(o.at) - _v(c.at)) * size_k)
			o.at = _a(delta * _v(o.at))
			o.normal = _a((delta.basis * _v(o.normal)).normalized())
			o.right = _a((delta.basis * _v(o.right)).normalized())
			if size_k != 1.0:
				o.size = [float(o.size[0]) * size_k, float(o.size[1]) * size_k], merge)


## A layer's frame (model space): right, up, normal at its centre.
func _frame_of(l: Dictionary) -> Transform3D:
	var n := _v(l.normal)
	var r := _v(l.right)
	return Transform3D(Basis(r, n.cross(r), n), _v(l.at))


## Sets a layer's centre, normal and right from car-frame values (right turned `turn` degrees
## about the normal, square to it).
func _place_frame(l: Dictionary, at_car: Vector3, n_car: Vector3, right_car: Vector3, turn := 0.0) -> void:
	var inv := car_xform().affine_inverse()
	var n := n_car.normalized()
	var r := (right_car - n * right_car.dot(n))
	if r.length() < 0.01:
		r = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD)
	r = r.normalized().rotated(n, deg_to_rad(turn))
	l.at = _a(inv * at_car)
	l.normal = _a((inv.basis * n).normalized())
	l.right = _a((inv.basis * r).normalized())


## Sets a layer's width and height in metres, keeping its flips.
func _set_size_m(l: Dictionary, wh: Vector2, keep_sign := false) -> void:
	var sx := signf(float(l.size[0])) if keep_sign and float(l.size[0]) != 0.0 else 1.0
	var sy := signf(float(l.size[1])) if keep_sign and float(l.size[1]) != 0.0 else 1.0
	l.size = [sx * _to_model_len(clampf(wh.x, MIN_SIZE, MAX_SIZE)), sy * _to_model_len(clampf(wh.y, MIN_SIZE, MAX_SIZE))]


## A text or number layer keeps its height and takes its new text's width.
func _fit_text(l: Dictionary) -> void:
	if l.kind == "shape":
		return
	var text := LiveryText.layer_text(l, LiveryText.PLACEHOLDER_NUMBER)
	var a := LiveryText.aspect(text, String(l.get("font", LiveryData.DEFAULT_FONT)))
	var h := absf(float(l.size[1]))
	if l.kind == "number" and l.get("number") == "auto":
		a = maxf(a, 1.15)
	l.size = [signf(float(l.size[0])) * h * a, l.size[1]]


## Where a ray onto side `s` meets the body: {at (car frame), normal, right, hit}. `spot` is
## (along, height) on that side; ZERO with `fresh` puts it in the side's middle. `dir` (car frame)
## is the way it faces, if not the side's own.
func _side_spot(s: String, spot: Vector2, fresh := true, facing := Vector3.ZERO) -> Dictionary:
	var box := _bounds()
	var axes := _axes(s)
	var n: Vector3 = SIDES[s][0]
	var facing_n := n if facing == Vector3.ZERO else facing
	if fresh and spot == Vector2.ZERO:
		var c := box.get_center()
		spot = Vector2(c.dot(axes[0]), c.dot(axes[1]))
		if s in ["left", "right", "front", "back"]:
			spot.y = box.position.y + box.size.y * 0.4
	var reach := box.size.length() + 1.0
	# A point on the side's plane at (along, height), then out along the facing to cast back in.
	var plane_at: Vector3 = axes[0] * spot.x + axes[1] * spot.y + n * (box.get_center().dot(n) + box.size.dot(n.abs()) * 0.5)
	var from := plane_at + facing_n * reach
	var hit := raycast(from, -facing_n)
	var at: Vector3 = hit.position if not hit.is_empty() else plane_at
	return { "at": at, "normal": facing_n, "right": SIDES[s][1], "hit": not hit.is_empty() }


## The side's two in-plane axes (car frame): along, then height.
static func _axes(s: String) -> Array:
	match s:
		"top":
			return [Vector3.BACK, Vector3.RIGHT]
		"front", "back":
			return [Vector3.RIGHT, Vector3.UP]
	return [Vector3.BACK, Vector3.UP]


## The nearest point on the body along a ray (car frame): {position, normal} in the car frame, or {}.
## Hidden parts and the wheels are left out.
func raycast(from: Vector3, dir: Vector3) -> Dictionary:
	var base := car_xform()
	var inv := base.affine_inverse()
	var hit := raycast_model(inv * from, (inv.basis * dir).normalized())
	if hit.is_empty():
		return hit
	return { "position": base * (hit.position as Vector3), "normal": (base.basis * (hit.normal as Vector3)).normalized() }


## The same in model space.
func raycast_model(from: Vector3, dir: Vector3) -> Dictionary:
	_build_rays()
	var best := {}
	var nearest := INF
	for item: Array in _ray_meshes:
		var xf: Transform3D = item[0]
		var box: AABB = item[2]
		if box.grow(box.size.length() * 0.01 + 1e-5).intersects_ray(from, dir) == null:
			continue
		var inv := xf.affine_inverse()
		var r: Dictionary = (item[1] as TriangleMesh).intersect_ray(inv * from, (inv.basis * dir).normalized())
		if r.is_empty():
			continue
		var p := xf * (r.position as Vector3)
		var d := from.distance_to(p)
		if d < nearest:
			nearest = d
			var n := (xf.basis.inverse().transposed() * (r.normal as Vector3)).normalized()
			best = { "position": p, "normal": n if n.dot(dir) < 0.0 else -n }
	return best


func _build_rays() -> void:
	var key := "%d" % (draft.scene.get_instance_id() if draft.scene else 0)
	if key == _ray_key:
		return
	_ray_key = key
	_ray_meshes.clear()
	if draft.scene == null:
		return
	var skip := {}
	for pattern: String in draft.fit.get("hide_nodes", []):
		for node in draft.scene.find_children(pattern, "Node3D", true, false):
			skip[node] = true
	for w: Dictionary in draft.fit.get("wheels", []):
		for n: String in [w.get("node", ""), w.get("spin_node", "")] + w.get("spin_nodes", []) + w.get("fixed_nodes", []):
			var node := draft.scene.find_child(n, true, false) if n else null
			if node:
				skip[node] = true
	for mi: MeshInstance3D in draft.scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or _skipped(mi, skip):
			continue
		var tm := mi.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var xf := CarVisual._xform_to_node(mi, draft.scene)
		_ray_meshes.append([xf, tm, xf * mi.mesh.get_aabb()])


static func _skipped(node: Node, skip: Dictionary) -> bool:
	while node:
		if skip.has(node):
			return true
		node = node.get_parent()
	return false


## The model's bounds in the car frame (metres).
func _bounds() -> AABB:
	var env: Dictionary = draft.fit.envelope
	var lo := _v(env.min)
	return car_xform() * AABB(lo, _v(env.max) - lo)


func _mid_x() -> float:
	return _bounds().get_center().x


## Metres per model unit.
func _scale() -> float:
	return float(draft.fit.model_transform.get("scale", 1.0))


func _to_model_len(metres: float) -> float:
	return metres / maxf(_scale(), 1e-9)


static func _readable(l: Dictionary) -> bool:
	return l.kind != "shape" or LiveryData.shape(String(l.shape)).get("readable", false)


static func _in_run(ls: Array, i: int, g: int) -> bool:
	return (i > 0 and int(ls[i - 1].get("group", 0)) == g) or (i + 1 < ls.size() and int(ls[i + 1].get("group", 0)) == g)


## Each group's layers together again (the same layer objects), and empty groups gone.
static func _regroup(l: Dictionary) -> void:
	l.layers = LiveryData._group_runs(l.layers)
	var used := {}
	for x: Dictionary in l.layers:
		used[int(x.get("group", 0))] = true
	l.groups = (l.get("groups", []) as Array).filter(func(g: Dictionary) -> bool: return used.has(int(g.id)))


## Where `item` itself (not an equal copy) is in `list`, or -1.
static func _index_of(list: Array, item: Variant) -> int:
	for i in list.size():
		if is_same(list[i], item):
			return i
	return -1


func _free_name(want: String) -> String:
	var names := draft.liveries.map(func(x: Dictionary) -> String: return String(x.name))
	if want not in names:
		return want
	var n := 2
	while "%s %d" % [want, n] in names:
		n += 1
	return "%s %d" % [want, n]


static func _v(a: Variant) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
