class_name TrackPreview
extends Node3D
## The track as the editor shows it (EDT-06): ground, road (a node per control segment), start
## gantry and props (a node per item), kept up with the draft in parts. Changes are gathered and
## applied once a frame; while a drag goes on, at most every LIVE_S, and only the segments it
## moves (the ground's bed under them included). A highway's ramps come again one by one, with
## the stretches of road where they leave and join it (EDT-10); kart pieces one by one too
## (EDT-04), and an arena's floor and wall stand in for the road.

const LIVE_S := 1.0 / 30.0

var draft: TrackDraft
var _ground: Node3D
var _road: Node3D
var _start: Node3D
var _props: Node3D
var _stunts: Node3D
var _built: TrackData
var _pending := {}
var _since := 0.0
## Ground the road's bed hasn't been cut into yet (live drags leave it to the release).
var _unconformed := Rect2i()


func setup(d: TrackDraft) -> void:
	draft = d
	draft.changed.connect(_on_changed)
	rebuild_all()


## Everything again, from the draft.
func rebuild_all() -> void:
	var t0 := Time.get_ticks_usec()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_pending.clear()
	var t := draft.track()
	if draft.terrain:
		draft.terrain.conform(t)
	_ground = _part("Ground")
	if draft.scene:
		draft.scene.build(_ground) # a fitted scene is the ground and the road
	else:
		TrackBuilder.add_ground(_ground, t, draft.terrain)
	_road = _part("Road")
	_build_road(t)
	_stunts = _part("Stunts")
	StuntBuilder.build(t, _stunts)
	_start = _part("Start")
	TrackBuilder.add_gantry(_start, t)
	_props = _part("Props")
	PropBuilder.new(t, draft.terrain).build(_props, true)
	_built = t
	if Game.dev.has("perf"):
		print("perf editor rebuild %.1f ms (%.2f km)" % [(Time.get_ticks_usec() - t0) / 1000.0, t.length / 1000.0])


func terrain_view() -> TerrainView:
	return _ground.get_node_or_null("TerrainView") as TerrainView if _ground else null


func terrain_collision() -> TerrainCollision:
	return _ground.get_node_or_null("TerrainCollision") as TerrainCollision if _ground else null


## The node holding prop item `i` (picking), or null.
func item_node(i: int) -> Node3D:
	return _props.get_node_or_null("Item_%d" % i) as Node3D if _props else null


## The road, or an arena's floor and wall.
func _build_road(t: TrackData) -> void:
	if t.arena:
		ArenaBuilder.build(t, _road)
	else:
		RoadBuilder.new(t, draft.terrain).build_all(_road, true)


func _part(part_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	add_child(n)
	return n


func _on_changed(what: StringName, info: Dictionary) -> void:
	var p: Dictionary = _pending.get(what, {})
	if what == &"kart":
		# Pieces by id; none named: all of them.
		if info.has("stunts") and not p.has("all"):
			var ids: Array = p.get("stunts", [])
			for id: String in info.stunts:
				if id not in ids:
					ids.append(id)
			p.stunts = ids
		elif not info.has("stunts"):
			p.erase("stunts")
			p.all = true
		p.live = bool(info.get("live", false))
		_pending[what] = p
		if not p.live:
			_flush()
		return
	if what == &"highway":
		# Ramps by id; none named: all of them.
		if info.has("ramps") and not p.has("all"):
			var ids: Array = p.get("ramps", [])
			for id: String in info.ramps:
				if id not in ids:
					ids.append(id)
			p.ramps = ids
		elif not info.has("ramps"):
			p.erase("ramps")
			p.all = true
		p.live = bool(info.get("live", false))
		_pending[what] = p
		if not p.live:
			_flush()
		return
	if info.has("segments") and (p.is_empty() or p.has("segments")):
		var segs: PackedInt32Array = p.get("segments", PackedInt32Array())
		for s in info.segments:
			if s not in segs:
				segs.append(s)
		p.segments = segs
	elif not info.has("segments"):
		p.erase("segments")
		p.all = true
	if info.has("rect"):
		var r: Rect2i = p.get("rect", info.rect)
		p.rect = r.merge(info.rect)
	p.live = bool(info.get("live", false))
	_pending[what] = p
	if not p.live:
		_flush()


func _process(delta: float) -> void:
	_since += delta
	if not _pending.is_empty() and _since >= LIVE_S:
		_flush()


func _flush() -> void:
	var t0 := Time.get_ticks_usec()
	_flush_parts()
	if Game.dev.has("perf"):
		print("perf editor update %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))


func _flush_parts() -> void:
	_since = 0.0
	var pending := _pending
	_pending = {}
	if pending.has(&"all"):
		rebuild_all()
		return
	var t := draft.track()
	if pending.has(&"terrain"):
		var rect: Rect2i = pending.terrain.get("rect", Rect2i())
		# The road follows the ground: it, its bed and anything standing on it come again.
		_rebuild_road(t, PackedInt32Array(), rect)
	elif pending.has(&"road"):
		_rebuild_road(t, pending.road.get("segments", PackedInt32Array()) if not pending.road.has("all") else PackedInt32Array(), Rect2i(),
			bool(pending.road.get("live", false)))
	elif pending.has(&"highway"):
		_rebuild_ramps(t, pending.highway)
	if pending.has(&"road") or pending.has(&"terrain"):
		_clear(_stunts)
		StuntBuilder.build(t, _stunts) # they stand on the road
	elif pending.has(&"kart"):
		_rebuild_stunts(t, pending.kart)
	if pending.has(&"race") or pending.has(&"road") or pending.has(&"terrain"):
		_clear(_start)
		TrackBuilder.add_gantry(_start, t)
	if pending.has(&"scene") and draft.scene:
		_clear(_ground)
		draft.scene.build(_ground)
	if pending.has(&"paint") and terrain_view():
		var rect: Rect2i = pending.paint.get("rect", Rect2i())
		terrain_view().update_paint(rect)
		terrain_collision().update_surfaces()
	var live_road := (pending.has(&"road") and bool(pending.road.get("live", false)) or pending.has(&"highway") and bool(pending.highway.get("live", false))) \
			and pending.size() == 1
	if (pending.has(&"props") or pending.has(&"scatter") or pending.has(&"road") or pending.has(&"terrain") or pending.has(&"highway")) and not live_road:
		_clear(_props)
		PropBuilder.new(t, draft.terrain).build(_props, true)
	_built = t


## The road again: only `segments` if the points are the same ones (a move), else all of it,
## with the ground's bed cut round it and the terrain's drawing and collision after it. `live`
## (dragging): the road alone; the ground catches up when the drag ends.
func _rebuild_road(t: TrackData, segments: PackedInt32Array, ground_rect: Rect2i, live := false) -> void:
	var partial := not segments.is_empty() and _built != null and _built.seg_first.size() == t.seg_first.size()
	var builder := RoadBuilder.new(t, draft.terrain)
	if draft.terrain:
		var rect := ground_rect
		if partial:
			rect = rect.merge(_segments_rect(_built, segments)).merge(_segments_rect(t, segments))
		else:
			rect = Rect2i(Vector2i.ZERO, draft.terrain.field.get_size())
		if live:
			_unconformed = rect if not _unconformed.has_area() else _unconformed.merge(rect)
		else:
			if _unconformed.has_area():
				rect = rect.merge(_unconformed)
				_unconformed = Rect2i()
			var changed := draft.terrain.conform(t, rect)
			terrain_view().update_rect(changed)
			terrain_collision().update_rect(changed)
	if partial and t.arena == null:
		builder.rebuild_segments(_road, segments)
		builder.rebuild_highway(_road) # ramps share the road's samples where they leave and join it
		builder.rebuild_pit(_road) # so does a pit lane
		builder.rebuild_scenery(_road) # and scenery roads are fitted to it
	else:
		_clear(_road)
		_build_road(t)


## Kart pieces again (`p.stunts`: those; else all). A wall-ride opens the barrier beside it: the
## road comes again with it.
func _rebuild_stunts(t: TrackData, p: Dictionary) -> void:
	var ids: Array = p.get("stunts", [])
	var walls := p.has("all")
	for id: String in ids:
		for layout: KartLayout in [_built.kart if _built else null, t.kart]:
			if layout:
				for piece in layout.pieces:
					walls = walls or (piece.id == id and piece.kind == "wall_ride")
	if walls and not bool(p.get("live", false)):
		_clear(_road)
		_build_road(t)
	if p.has("all") or t.kart == null:
		_clear(_stunts)
		StuntBuilder.build(t, _stunts)
		return
	var b := StuntBuilder.new()
	b.track = t
	b.layout = t.kart
	for id: String in ids:
		for n: String in ["Stunt_" + id, "Stunt_" + id + "_pad"]:
			var old := _stunts.get_node_or_null(n)
			if old:
				_stunts.remove_child(old)
				old.queue_free()
		for piece in t.kart.pieces:
			if piece.id == id or piece.id == id + "_pad":
				b.build_piece(piece, _stunts)


## A highway's ramps again (`p.ramps`: those; else all), with the road's segments where they
## leave and join it, before and after (its barriers open there), and the signs and portals.
## While dragging, the ramps alone. On terrain the ground is cut round them again: all of it.
func _rebuild_ramps(t: TrackData, p: Dictionary) -> void:
	var live := bool(p.get("live", false))
	if draft.terrain and not live or _built == null or _built.samples.size() != t.samples.size():
		_rebuild_road(t, PackedInt32Array(), Rect2i())
		return
	var builder := RoadBuilder.new(t, draft.terrain)
	var ids: Array = p.get("ramps", [])
	if p.has("all"):
		ids = []
		for layout: HighwayLayout in [_built.highway, t.highway]:
			for r in layout.ramps if layout else []:
				if r.id not in ids:
					ids.append(r.id)
		for e in t.highway.errors + (_built.highway.errors if _built.highway else PackedStringArray()):
			var id := e.get_slice(":", 0)
			if id not in ids:
				ids.append(id)
	var segments := PackedInt32Array()
	for id: String in ids:
		builder.rebuild_ramp(_road, id)
		for layout: HighwayLayout in [_built.highway, t.highway]:
			var r := layout.ramp(id) if layout else null
			if r == null:
				continue
			for k in r.head_main + r.tail_main:
				var s := t.sample_seg[k]
				if s not in segments:
					segments.append(s)
	if not live:
		builder.rebuild_segments(_road, segments)
		builder.rebuild_extras(_road)


## The terrain samples the road's bed reaches along `segments` of `t`.
func _segments_rect(t: TrackData, segments: PackedInt32Array) -> Rect2i:
	var out := Rect2i()
	var field := draft.terrain.field
	for s in segments:
		if s >= t.seg_first.size():
			continue
		var span := t.segment_samples(s)
		var box := Rect2()
		for k in range(span.x, span.y + 1):
			var p := t.samples[k % t.samples.size()]
			box = Rect2(p.x, p.z, 0, 0) if box.size == Vector2.ZERO and k == span.x else box.expand(Vector2(p.x, p.z))
		var reach := 0.0
		for k in range(span.x, span.y):
			var i := k % t.samples.size()
			reach = maxf(reach, maxf(t.half_l[i] + t.runoff_l_m[i], t.half_r[i] + t.runoff_r_m[i]))
		var r := field.rect_around(box.get_center(), box.size.length() / 2.0 + reach + TrackData.CURB_WIDTH + TerrainData.FALLOFF_M + 2.0)
		out = r if not out.has_area() else out.merge(r)
	return out


static func _clear(n: Node) -> void:
	for child in n.get_children():
		n.remove_child(child)
		child.queue_free()
