class_name LiveryText
extends RefCounted
## Text and race-number layers (docs/VEHICLE_PACKAGE.md §12): each string set in its font as a
## multi-channel distance field (the alpha channel a true one), packed into one atlas per livery.
## Built on the CPU from the TextServer's glyph cache, so it works headless and only the livery's
## JSON travels; glyphs that overlap (scripts, tight kerning) merge by their true distance.

## Glyph size in the atlas (px) and the distance field's range (livery_text_range in the shader).
const SIZE := 48
const RANGE := 8
const ATLAS_W := 2048
const PAD := 6
## What a race number set to auto shows where nobody's racing (the bay, the garage).
const PLACEHOLDER_NUMBER := "00"
## Strings and atlases kept, at most (cleared past these).
const KEEP_STRINGS := 256
const KEEP_ATLASES := 48

static var _fonts := {} # font id -> Font set up for distance fields
static var _strings := {} # "font|text" -> Image
static var _atlases := {} # key -> [ImageTexture, {layer index: Rect2}]


## The catalog's font `id` set up for distance fields (the default font for an unknown id).
static func font(id: String) -> Font:
	if _fonts.has(id):
		return _fonts[id]
	var entry := LiveryData.font(id)
	if entry.is_empty():
		entry = LiveryData.font(LiveryData.DEFAULT_FONT)
	var base: FontFile = load(String(entry.file))
	var f := base.duplicate() as FontFile
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = RANGE
	f.msdf_size = SIZE
	f.allow_system_fallback = false
	var out: Font = f
	if entry.get("variation") is Dictionary:
		var v := FontVariation.new()
		v.base_font = f
		var coords := {}
		for tag: String in entry.variation:
			coords[TextServerManager.get_primary_interface().name_to_tag(tag)] = float(entry.variation[tag])
		v.variation_opentype = coords
		out = v
	_fonts[id] = out
	return out


## What a text or number layer shows; `number` is the racer's (auto numbers).
static func layer_text(layer: Dictionary, number: String) -> String:
	if layer.get("kind") == "text":
		return String(layer.get("text", ""))
	var n := String(layer.get("number", "auto"))
	if n == "auto":
		return number if number else PLACEHOLDER_NUMBER
	return n


## `text` set in font `font_id`: an RGBA8 distance field image hugging the glyphs (plus the
## field's margin); null for nothing to draw.
static func string_image(text: String, font_id: String) -> Image:
	var key := font_id + "|" + text
	if _strings.has(key):
		return _strings[key]
	if _strings.size() >= KEEP_STRINGS:
		_strings.clear()
	var image := _render(text, font(font_id))
	_strings[key] = image
	return image


## Width over height of `text` as it's drawn (1 when there's nothing to draw).
static func aspect(text: String, font_id: String) -> float:
	var image := string_image(text, font_id)
	return float(image.get_width()) / image.get_height() if image else 1.0


## The atlas for a livery's text and number layers: [ImageTexture or null, {layer index: Rect2
## in atlas uv}]. Shared between cars wearing the same livery with the same number.
static func build(livery: Dictionary, number: String) -> Array:
	var items := []
	var key_parts := PackedStringArray()
	var layers: Array = livery.get("layers", [])
	for i in layers.size():
		var l: Dictionary = layers[i]
		if l.kind == "shape" or l.get("hidden", false):
			continue
		var text := layer_text(l, number)
		var image := string_image(text, String(l.get("font", LiveryData.DEFAULT_FONT)))
		if image:
			items.append([i, image])
			key_parts.append("%d:%s|%s" % [i, l.get("font", ""), text])
	if items.is_empty():
		return [null, {}]
	var key := "\n".join(key_parts)
	if _atlases.has(key):
		return _atlases[key]
	if _atlases.size() >= KEEP_ATLASES:
		_atlases.clear()
	var packed := _pack(items)
	_atlases[key] = packed
	return packed


## Shelf-packs the string images (tallest first) into one atlas.
static func _pack(items: Array) -> Array:
	var order := items.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Image).get_height() > (b[1] as Image).get_height())
	var places := {} # image -> where it went (layers showing the same string share it)
	var x := PAD
	var y := PAD
	var shelf := 0
	var width := PAD
	for item: Array in order:
		var image: Image = item[1]
		if places.has(image):
			continue
		if x + image.get_width() + PAD > ATLAS_W:
			x = PAD
			y += shelf + PAD
			shelf = 0
		if y + image.get_height() + PAD > ATLAS_W:
			continue # full: the layer isn't drawn
		places[image] = Vector2i(x, y)
		x += image.get_width() + PAD
		width = maxi(width, x)
		shelf = maxi(shelf, image.get_height())
	var w := _pow2(width)
	var h := _pow2(y + shelf + PAD)
	var atlas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for image: Image in places:
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), places[image])
	var rects := {}
	for item: Array in order:
		var image: Image = item[1]
		if places.has(image):
			rects[item[0]] = Rect2(Vector2(places[image]) / Vector2(w, h), Vector2(image.get_size()) / Vector2(w, h))
	atlas.generate_mipmaps()
	return [ImageTexture.create_from_image(atlas), rects]


static func _render(text: String, f: Font) -> Image:
	var ts := TextServerManager.get_primary_interface()
	var shaped := ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, f.get_rids(), SIZE)
	var glyphs := ts.shaped_text_get_glyphs(shaped)
	var size := Vector2i(SIZE, 0)
	var placed := [] # [rid, texture index, uv rect, at]
	var pen := 0.0
	var bounds := Rect2i()
	for g: Dictionary in glyphs:
		var rid: RID = g.font_rid
		var index := int(g.index)
		var advance := float(g.advance)
		if rid.is_valid() and index > 0:
			ts.font_render_glyph(rid, size, index)
			var uv := Rect2i(ts.font_get_glyph_uv_rect(rid, size, index))
			if uv.size.x > 0 and uv.size.y > 0:
				var off: Vector2 = ts.font_get_glyph_offset(rid, size, index) + (g.offset as Vector2)
				var at := Vector2i(roundi(pen + off.x), roundi(off.y))
				placed.append([rid, ts.font_get_glyph_texture_idx(rid, size, index), uv, at])
				var r := Rect2i(at, uv.size)
				bounds = r if placed.size() == 1 else bounds.merge(r)
		pen += advance * int(g.get("repeat", 1))
	ts.free_rid(shaped)
	if placed.is_empty():
		return null
	var out := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	var data := out.get_data()
	var w := bounds.size.x
	var sources := {}
	for p: Array in placed:
		var source_key := "%s:%d" % [p[0], p[1]]
		if not sources.has(source_key):
			var img := ts.font_get_texture_image(p[0], size, p[1])
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sources[source_key] = [img.get_data(), img.get_width()]
		var src: PackedByteArray = sources[source_key][0]
		var sw: int = sources[source_key][1]
		var uv: Rect2i = p[2]
		var dx: int = p[3].x - bounds.position.x
		var dy: int = p[3].y - bounds.position.y
		# Keep whichever glyph is nearer at each pixel (the larger true distance, in alpha).
		for row in uv.size.y:
			var s := ((uv.position.y + row) * sw + uv.position.x) * 4
			var d := ((dy + row) * w + dx) * 4
			for col in uv.size.x:
				if src[s + 3] > data[d + 3]:
					data[d] = src[s]
					data[d + 1] = src[s + 1]
					data[d + 2] = src[s + 2]
					data[d + 3] = src[s + 3]
				s += 4
				d += 4
	out.set_data(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8, data)
	if out.get_width() + 2 * PAD > ATLAS_W:
		var scale := float(ATLAS_W - 2 * PAD) / out.get_width()
		out.resize(ATLAS_W - 2 * PAD, maxi(roundi(out.get_height() * scale), 1), Image.INTERPOLATE_BILINEAR)
	return out


static func _pow2(n: int) -> int:
	var p := 64
	while p < n:
		p *= 2
	return p
