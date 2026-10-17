class_name EndlessGround
extends TerrainData
## The endless world's natural ground for the road builder (pillars down to it, rails along it),
## from the generator, in the scene of an origin at world (ox, oz). Safe on a worker.

var gen: NossRoadGen
var ox := 0.0
var oz := 0.0


static func of(generator: NossRoadGen, origin_x: float, origin_z: float) -> EndlessGround:
	var g := EndlessGround.new()
	g.gen = generator
	g.ox = origin_x
	g.oz = origin_z
	return g


func height_at(x: float, z: float) -> float:
	return gen.ground_at(x + ox, z + oz)


func base_at(x: float, z: float) -> float:
	return height_at(x, z)
