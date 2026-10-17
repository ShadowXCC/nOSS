class_name EndlessCode
extends RefCounted
## A road to share (docs/GAMEMODES.md §4, D157): the start biome and the seed, as
## "FOREST-0007K2Q". The seed is 31 bits in Crockford base 32 (no I, L, O or U, so it's hard to
## misread); case, spaces and O-for-0 typos don't matter.

const DIGITS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const LENGTH := 7


static func encode(seed_value: int, biome: int) -> String:
	var v := clampi(seed_value, 0, 0x7FFFFFFF)
	var digits := ""
	for i in LENGTH:
		digits = DIGITS[v % 32] + digits
		v /= 32
	return "%s-%s" % [String(NossRoadGen.biome_ids()[clampi(biome, 0, NossRoadGen.biome_ids().size() - 1)]).to_upper(), digits]


## {seed, biome} from a code, or {} if it isn't one.
static func decode(code: String) -> Dictionary:
	var c := code.strip_edges().to_upper().replace(" ", "")
	var parts := c.split("-")
	if parts.size() != 2:
		return {}
	var biome := Array(NossRoadGen.biome_ids()).find(parts[0].to_lower())
	if biome < 0 or parts[1].is_empty() or parts[1].length() > LENGTH:
		return {}
	var v := 0
	for ch in parts[1].replace("O", "0").replace("I", "1").replace("L", "1"):
		var d := DIGITS.find(ch)
		if d < 0:
			return {}
		v = v * 32 + d
	if v > 0x7FFFFFFF:
		return {}
	return { "seed": v, "biome": biome }


## A new seed for a new road.
static func random_seed() -> int:
	return randi_range(1, 0x7FFFFFFF)
