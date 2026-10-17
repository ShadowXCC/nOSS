class_name EndlessGen
extends RefCounted
## The endless road's generator, as scripts use it (docs/GAMEMODES.md §4, D152): NossRoadGen makes
## the road from a seed and a start biome, in integers, the same on every machine.

## Biome ids in NossRoadGen's order (data/endless/biomes/<id>.json describes their look).
static func biome_ids() -> PackedStringArray:
	return NossRoadGen.biome_ids()


static func make(seed: int, biome: int) -> NossRoadGen:
	var gen := NossRoadGen.new()
	gen.setup(seed, clampi(biome, 0, biome_ids().size() - 1))
	return gen


## Dev: --endless-selftest[=<seed>] makes 200 km of road for a few seeds and start biomes, and the
## ground on tiles along it, and prints their checksums, so two builds (Linux and Windows) can be
## compared (M9: "a seed reproduces the same road on two machines").
static func selftest(arg: String) -> String:
	var seeds: Array = [1, 2, 977, 123456789] if arg.is_empty() or arg == "true" else [int(arg)]
	var lines := PackedStringArray()
	var t0 := Time.get_ticks_usec()
	var chunks := ceili(200000.0 / (NossRoadGen.chunk_samples() * 2.0))
	for i in seeds.size():
		var gen := make(int(seeds[i]), i % biome_ids().size())
		var road := gen.checksum(chunks)
		# The ground: a 257 x 257 tile at every 40th chunk's start.
		var ground := HashingContext.new()
		ground.start(HashingContext.HASH_SHA256)
		for k in range(0, chunks, 40):
			var c := gen.chunk(k)
			var at := Vector2(c.x[0], c.z[0]).snapped(Vector2(256, 256))
			ground.update(gen.ground_heights(at.x, at.y, 257, 257, 1.0).to_byte_array())
		lines.append("ENDLESS_SELFTEST seed=%d biome=%s road=%x ground=%s" % [seeds[i], biome_ids()[i % biome_ids().size()], road, ground.finish().hex_encode().left(16)])
	lines.append("ENDLESS_SELFTEST %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	return "\n".join(lines)
