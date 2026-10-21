class_name EndlessLimits
extends RefCounted
## Speed limits on the endless road (docs/GAMEMODES.md §4, D193): one per chunk, a tier from the
## biome most of the chunk is in (its limit_kmh), two tiers lower where the chunk's traffic has to
## go under BEND_SHARE of it (a tight bend). Worked out from the generator's chunk alone, so every
## game has the same limits. Each tier is a km/h and an mph limit, round numbers in each.

const TIERS := [[30, 20], [40, 25], [50, 30], [60, 40], [70, 45], [80, 50], [90, 55], [100, 60], [110, 70], [120, 75]]
const DEFAULT_KMH := 80
const BEND_SHARE := 0.7
const BEND_DROP := 2


## A chunk's tier (NossRoadGen.chunk()'s dictionary).
static func tier_of(chunk: Dictionary) -> int:
	var biome: PackedByteArray = chunk.biome
	var biome2: PackedByteArray = chunk.biome2
	var blend: PackedFloat32Array = chunk.blend
	var counts := {}
	for i in biome.size():
		var b := int(biome2[i]) if blend[i] >= 0.5 else int(biome[i])
		counts[b] = int(counts.get(b, 0)) + 1
	var most := -1
	for b: int in counts:
		if most < 0 or int(counts[b]) > int(counts[most]) or (int(counts[b]) == int(counts[most]) and b < most):
			most = b
	var tier := tier_for_kmh(int(EndlessBiomes.of(most).get("limit_kmh", DEFAULT_KMH)))
	var slowest := INF
	for v in chunk.speed_up as PackedFloat32Array:
		slowest = minf(slowest, v)
	for v in chunk.speed_down as PackedFloat32Array:
		slowest = minf(slowest, v)
	if slowest < BEND_SHARE * mps(tier):
		tier = maxi(tier - BEND_DROP, 0)
	return tier


## The tier of a km/h limit (the highest at or under it).
static func tier_for_kmh(kmh: int) -> int:
	var out := 0
	for i in TIERS.size():
		if int(TIERS[i][0]) <= kmh:
			out = i
	return out


static func kmh(tier: int) -> int:
	return int(TIERS[clampi(tier, 0, TIERS.size() - 1)][0])


static func mph(tier: int) -> int:
	return int(TIERS[clampi(tier, 0, TIERS.size() - 1)][1])


## The limit, m/s (the km/h one: the mph one is within a few per cent).
static func mps(tier: int) -> float:
	return kmh(tier) / 3.6


## The number a sign shows, in the player's units.
static func text(tier: int) -> String:
	return str(mph(tier) if Settings.units == "imperial" else kmh(tier))
