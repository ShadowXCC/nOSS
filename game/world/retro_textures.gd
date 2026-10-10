class_name RetroTextures
extends RefCounted
## Small procedural world textures in the retro style (docs/ART_AUDIO.md §2-3). All original,
## generated at load time and cached.

static var _cache := {}


static func asphalt() -> Texture2D:
	return _cached("asphalt", func() -> Image:
		var img := _noise_image(256, 256, 0.34, 0.035, 11, 0.05)
		_speckle(img, 0.06, Color(0.40, 0.40, 0.41), 21)
		_speckle(img, 0.06, Color(0.29, 0.29, 0.30), 22)
		# White edge lines, ~25 cm wide, 30 cm in from each edge of a 12 m road.
		for u in [0.026, 0.954]:
			img.fill_rect(Rect2i(int(u * 256), 0, 5, 256), Color(0.86, 0.86, 0.84))
		return img)


static func curb() -> Texture2D:
	return _cached("curb", func() -> Image:
		var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
		img.fill_rect(Rect2i(0, 0, 16, 16), Color(0.78, 0.1, 0.08))
		img.fill_rect(Rect2i(0, 16, 16, 16), Color(0.92, 0.92, 0.9))
		return img)


static func grass() -> Texture2D:
	return _cached("grass", func() -> Image:
		var img := _noise_image(128, 128, 0.0, 0.0, 31, 0.12, Color(0.22, 0.36, 0.14), Color(0.33, 0.48, 0.2))
		_speckle(img, 0.05, Color(0.17, 0.28, 0.1), 32)
		return img)


static func gravel() -> Texture2D:
	return _cached("gravel", func() -> Image:
		var img := _noise_image(64, 64, 0.0, 0.0, 41, 0.3, Color(0.55, 0.5, 0.42), Color(0.72, 0.67, 0.57))
		_speckle(img, 0.08, Color(0.4, 0.37, 0.32), 42)
		return img)


static func concrete() -> Texture2D:
	return _cached("concrete", func() -> Image:
		var img := _noise_image(128, 128, 0.0, 0.0, 51, 0.06, Color(0.56, 0.56, 0.54), Color(0.66, 0.66, 0.63))
		img.fill_rect(Rect2i(0, 0, 128, 1), Color(0.45, 0.45, 0.43)) # slab joints
		img.fill_rect(Rect2i(0, 0, 1, 128), Color(0.45, 0.45, 0.43))
		return img)


static func tyre_wall() -> Texture2D:
	return _cached("tyre_wall", func() -> Image:
		var img := _noise_image(32, 32, 0.0, 0.0, 61, 0.4, Color(0.06, 0.06, 0.065), Color(0.12, 0.12, 0.13))
		for x in range(0, 32, 8):
			img.fill_rect(Rect2i(x, 12, 8, 8), Color(0.88, 0.88, 0.86) if (x / 8) % 2 == 0 else Color(0.75, 0.12, 0.1))
		return img)


static func checker() -> Texture2D:
	return _cached("checker", func() -> Image:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 4:
			for x in 4:
				img.fill_rect(Rect2i(x * 4, y * 4, 4, 4), Color.WHITE if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.08))
		return img)


## Grandstand crowd: coloured dots on dark rows.
static func crowd() -> Texture2D:
	return _cached("crowd", func() -> Image:
		var rng := RandomNumberGenerator.new()
		rng.seed = 71
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.18, 0.18, 0.2))
		for y in range(0, 64, 8):
			img.fill_rect(Rect2i(0, y + 6, 64, 2), Color(0.5, 0.5, 0.52))
			for x in range(0, 64, 3):
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.8), rng.randf_range(0.4, 0.95))
				img.fill_rect(Rect2i(x, y + 1, 2, 4), c)
		return img)


static func building() -> Texture2D:
	return _cached("building", func() -> Image:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.79, 0.75))
		for y in [8, 36]:
			for x in range(4, 64, 12):
				img.fill_rect(Rect2i(x, y, 8, 16), Color(0.16, 0.22, 0.3))
		img.fill_rect(Rect2i(0, 60, 64, 4), Color(0.5, 0.5, 0.5))
		return img)


## Cut-out tree sprite for billboards.
static func tree() -> Texture2D:
	return _cached("tree", func() -> Image:
		var rng := RandomNumberGenerator.new()
		rng.seed = 81
		var w := 64
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		img.fill_rect(Rect2i(w / 2 - 3, h - 30, 6, 30), Color(0.3, 0.2, 0.12))
		for i in 900:
			var y := rng.randf_range(0.0, 0.8)
			var spread := (0.15 + y * 0.5) * w * 0.5
			var x := w / 2.0 + rng.randf_range(-spread, spread)
			var py := int(y * (h - 24))
			var shade := rng.randf_range(0.6, 1.0) * (0.75 + 0.25 * (1.0 - y))
			img.fill_rect(Rect2i(int(x) - 2, py, 4, 4), Color(0.1 * shade, 0.32 * shade, 0.12 * shade))
		return img)


## Seamless noise for the sky's clouds and mountain lines.
static func sky_noise() -> Texture2D:
	return _cached("sky_noise", func() -> Image:
		var noise := FastNoiseLite.new()
		noise.seed = 91
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		return noise.get_seamless_image(256, 256))


## Large-scale colour variation for terrain.
static func variation() -> Texture2D:
	return _cached("variation", func() -> Image:
		var noise := FastNoiseLite.new()
		noise.seed = 101
		noise.frequency = 0.02
		noise.fractal_octaves = 3
		return noise.get_seamless_image(128, 128))


static func _cached(key: String, make: Callable) -> Texture2D:
	if not _cache.has(key):
		var img: Image = make.call()
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Seamless noise between two colours (or a grey level +- spread).
static func _noise_image(w: int, h: int, grey: float, spread: float, seed: int, freq: float, dark := Color.BLACK, light := Color.BLACK) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_octaves = 3
	var n := noise.get_seamless_image(w, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var use_colors := dark != Color.BLACK or light != Color.BLACK
	for y in h:
		for x in w:
			var v := n.get_pixel(x, y).r
			if use_colors:
				img.set_pixel(x, y, dark.lerp(light, v))
			else:
				var g := grey + (v - 0.5) * 2.0 * spread
				img.set_pixel(x, y, Color(g, g, g * 1.02))
	return img


static func _speckle(img: Image, amount: float, color: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in int(img.get_width() * img.get_height() * amount):
		img.set_pixel(rng.randi_range(0, img.get_width() - 1), rng.randi_range(0, img.get_height() - 1), color)
