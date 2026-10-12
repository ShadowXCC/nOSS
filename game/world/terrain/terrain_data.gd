class_name TerrainData
extends RefCounted
## A track's terrain (docs/TRACK_EDITOR.md §2, D90): a 1 m heightmap in 256 m chunks with eight
## paint layers, kept by NossTerrain. The heights the player shapes are saved (16-bit PNG); the
## ground the game drives on is those with the road's bed cut in (conform), made at load.

const CHUNK := 256
const MAX_CHUNKS := 16
## Paint layers, in the order the shader's texture array has them, and what each drives like.
const LAYERS := ["grass", "dirt", "sand", "gravel", "rock", "snow", "concrete", "asphalt"]
const LAYER_SURFACES := [
	VehicleSim.SURFACE_GRASS, VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_SAND, VehicleSim.SURFACE_GRAVEL,
	VehicleSim.SURFACE_CONCRETE, VehicleSim.SURFACE_SNOW, VehicleSim.SURFACE_CONCRETE, VehicleSim.SURFACE_ASPHALT,
]
const HEIGHT_MIN := -100.0
const HEIGHT_STEP := 0.01
## The road's bed: this far below the road, blending back to the shaped ground over FALLOFF_M
## past the run-off.
const BED_DEPTH_M := 0.05
const FALLOFF_M := 12.0

var meta := {}
var field: NossTerrain
var _surface_map: NossSurfaceMap


## Flat ground at `height`, all grass, `chunks` chunks from `origin` (x, z).
static func create(origin: Vector2, chunks: Vector2i, height := 0.0) -> TerrainData:
	var t := TerrainData.new()
	t.meta = {
		"schema": "noss.terrain/1", "origin": [origin.x, origin.y],
		"chunks": [clampi(chunks.x, 1, MAX_CHUNKS), clampi(chunks.y, 1, MAX_CHUNKS)],
		"chunk_m": CHUNK, "cell_m": 1, "height_min": HEIGHT_MIN, "height_step": HEIGHT_STEP,
		"falloff_m": FALLOFF_M, "layers": LAYERS.duplicate(),
	}
	t.field = NossTerrain.new()
	t.field.create(t.chunks().x * CHUNK + 1, t.chunks().y * CHUNK + 1, origin, 1.0, height, 0)
	return t


## Terrain big enough for `bounds` (x, z) plus `margin` metres all round, in whole chunks.
static func around(bounds: Rect2, margin := 300.0, height := 0.0) -> TerrainData:
	var b := bounds.grow(margin)
	var chunks := Vector2i(ceili(b.size.x / CHUNK), ceili(b.size.y / CHUNK))
	var size := Vector2(chunks) * CHUNK
	return create((b.get_center() - size / 2.0).floor(), chunks, height)


## From a package's terrain files ({path: bytes}). {terrain} or {error}.
static func from_files(files: Dictionary) -> Dictionary:
	var meta_v: Variant = JSON.parse_string((files.get("terrain/meta.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not meta_v is Dictionary:
		return { "error": "terrain/meta.json isn't valid JSON" }
	var errors := JsonSchema.validate(meta_v, JsonSchema.load_schema("terrain"))
	if not errors.is_empty():
		return { "error": "terrain/meta.json: " + errors[0] }
	var m: Dictionary = meta_v
	var t := create(Vector2(m.origin[0], m.origin[1]), Vector2i(int(m.chunks[0]), int(m.chunks[1])))
	t.meta = m
	var size := t.field.get_size()
	var png: PackedByteArray = files.get("terrain/height.png", PackedByteArray())
	if NossPackage.image_size(png) != size:
		return { "error": "Heightmap size doesn't match" }
	var err := t.field.set_base_png(png, float(m.height_min), float(m.height_step))
	if err:
		return { "error": err }
	for image in 2:
		var rel := "terrain/splat_%d.png" % image
		var bytes: PackedByteArray = files.get(rel, PackedByteArray())
		if bytes.is_empty():
			continue # all grass
		if NossPackage.image_size(bytes) != size:
			return { "error": rel + ": size doesn't match" }
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			return { "error": rel + " can't be read" }
		img.convert(Image.FORMAT_RGBA8)
		if not t.field.set_splat_rgba(image, img.get_data()):
			return { "error": rel + ": size doesn't match" }
	return { "terrain": t }


## The files a package stores: meta, heights (16-bit PNG) and paint.
func to_files() -> Dictionary:
	var size := field.get_size()
	var out := {
		"terrain/meta.json": PackageWriter.canonical_json(meta).to_utf8_buffer(),
		"terrain/height.png": NossTerrain.png16_encode(field.get_base_u16(float(meta.height_min), float(meta.height_step)), size.x, size.y),
	}
	for image in 2:
		var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, field.get_splat_rgba(image))
		out["terrain/splat_%d.png" % image] = img.save_png_to_buffer()
	return out


func chunks() -> Vector2i:
	return Vector2i(int(meta.chunks[0]), int(meta.chunks[1]))


func origin() -> Vector2:
	return Vector2(meta.origin[0], meta.origin[1])


## The terrain's extent in x, z.
func area() -> Rect2:
	return Rect2(origin(), Vector2(chunks()) * CHUNK)


## The ground the game drives on (with the road's bed).
func height_at(x: float, z: float) -> float:
	return field.height_at(x, z)


## The shaped ground (what roads that follow the ground follow).
func base_at(x: float, z: float) -> float:
	return field.base_at(x, z)


func ground_height() -> Callable:
	return field.base_at


## Cuts the road's bed into the ground under `track` (all of it, or only `rect`, in samples).
## Returns the samples changed.
func conform(track: TrackData, rect := Rect2i()) -> Rect2i:
	var area_rect := rect if rect.has_area() else Rect2i(Vector2i.ZERO, field.get_size())
	return field.conform(area_rect, road_samples(track), FALLOFF_M, BED_DEPTH_M)


## The road for conform: per sample x, y, z, left, how far it levels each side, lifted.
static func road_samples(track: TrackData) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if track == null or track.kind != "road":
		return out
	out.resize(track.samples.size() * 9)
	for i in track.samples.size():
		var p := track.samples[i]
		var l := track.lefts[i]
		var k := i * 9
		out[k] = p.x
		out[k + 1] = p.y
		out[k + 2] = p.z
		out[k + 3] = l.x
		out[k + 4] = l.y
		out[k + 5] = l.z
		out[k + 6] = track.half_l[i] + (TrackData.CURB_WIDTH if track.curb_l[i] else 0.0) + track.runoff_l_m[i]
		out[k + 7] = track.half_r[i] + (TrackData.CURB_WIDTH if track.curb_r[i] else 0.0) + track.runoff_r_m[i]
		out[k + 8] = 1.0 if track.lifted[i] else 0.0
	return out


## Samples of chunk `c` (with the shared edge sample).
func chunk_rect(c: Vector2i) -> Rect2i:
	return Rect2i(c * CHUNK, Vector2i(CHUNK + 1, CHUNK + 1))


## The chunks a rect of samples touches (edges included: neighbours share them).
func chunks_in(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not rect.has_area():
		return out
	var n := chunks()
	var c0 := Vector2i(maxi((rect.position.x - 1) / CHUNK, 0), maxi((rect.position.y - 1) / CHUNK, 0))
	var c1 := Vector2i(mini((rect.end.x) / CHUNK, n.x - 1), mini((rect.end.y) / CHUNK, n.y - 1))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			out.append(Vector2i(cx, cz))
	return out


## What each sample drives like (for VehicleSim); rebuilt after painting.
func surface_map(rebuild := false) -> NossSurfaceMap:
	if _surface_map == null or rebuild:
		_surface_map = field.surface_map(PackedByteArray(LAYER_SURFACES))
	return _surface_map


## A terrain over `bounds` (+ margin) keeping this one's heights and paint where they overlap.
func fit_to(bounds: Rect2, margin := 300.0) -> TerrainData:
	var t := around(bounds, margin, base_at(bounds.get_center().x, bounds.get_center().y))
	var size := t.field.get_size()
	var o := t.origin()
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	var mine := area()
	for z in size.y:
		for x in size.x:
			var w := Vector2(o.x + x, o.y + z)
			heights[z * size.x + x] = base_at(w.x, w.y) if mine.grow(0.5).has_point(w) else base_at(clampf(w.x, mine.position.x, mine.end.x), clampf(w.y, mine.position.y, mine.end.y))
	t.field.set_base(heights)
	# Paint where the two overlap.
	var my_origin := origin()
	var offset := Vector2i((o - my_origin).round())
	var overlap := Rect2i(Vector2i.ZERO, field.get_size()).intersection(Rect2i(offset, size))
	if overlap.has_area():
		var weights := field.splat_region_get(overlap)
		t.field.splat_region_set(Rect2i(overlap.position - offset, overlap.size), weights)
	return t
