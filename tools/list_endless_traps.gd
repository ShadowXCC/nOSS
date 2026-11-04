extends Node
## Where the speed traps are on a road seed. Runs as a scene so the autoloads are there:
##   tools/godot.sh --headless res://tools/list_endless_traps.tscn -- <seed> <biome>
##   tools/godot.sh --headless res://tools/list_endless_traps.tscn -- scan <biome> <seeds>


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var biome := int(args[1]) if args.size() > 1 else 1
	if args.size() > 0 and args[0] == "scan":
		_scan(biome, int(args[2]) if args.size() > 2 else 40)
	else:
		_one(int(args[0]) if args.size() > 0 else 7, biome)
	get_tree().quit()


func _traps(road_seed: int, biome: int, chunks: int) -> Array:
	var gen := EndlessGen.make(road_seed, biome)
	var lanes := EndlessLanes.make(0, "right")
	var out := []
	for k in chunks:
		var trap := EndlessTraps.plan(gen.get_seed(), k, gen.chunk(k), lanes)
		if not trap.is_empty():
			out.append(trap)
	return out


## Every seed's first trap past the players' start (1500 m), and how far into the drive it is.
func _scan(biome: int, seeds: int) -> void:
	print("seed  first trap past 1500 m")
	for s in range(1, seeds + 1):
		var found := {}
		for trap: Dictionary in _traps(s, biome, 30):
			if float(trap.at_m) > 1700.0:
				found = trap
				break
		if found.is_empty():
			print("%4d  none in the first 7.2 km" % s)
		else:
			print("%4d  %s at %.0f m (%.0f m into the drive)" % [s, found.kind, found.at_m, float(found.at_m) - 1500.0])


func _one(road_seed: int, biome: int) -> void:
	var gen := EndlessGen.make(road_seed, biome)
	var lanes := EndlessLanes.make(0, "right")
	var chunk_m := TrackData.SAMPLE_M * NossRoadGen.chunk_samples()
	print("seed %d biome %d, chunk %.0f m" % [road_seed, biome, chunk_m])
	for k in 40:
		var data := gen.chunk(k)
		var tier := EndlessLimits.tier_of(data)
		var trap := EndlessTraps.plan(gen.get_seed(), k, data, lanes)
		var line := "chunk %2d  %6.0f-%6.0f m  limit %3d km/h" % [k, k * chunk_m, (k + 1) * chunk_m, EndlessLimits.TIERS[tier][0]]
		if not trap.is_empty():
			line += "   TRAP %s at %.0f m" % [trap.kind, trap.at_m]
		print(line)
