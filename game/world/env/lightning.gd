class_name Lightning
extends RefCounted
## Lightning in storms (D153, ACC-04). Each player's view flashes on its own: three quick flickers,
## or with Reduce flashing one soft pulse at most a third as bright (at most one a second, so well
## under three flashes a second). The bolt itself is drawn only for players without Reduce
## flashing (Flash.LAYER_NORMAL). Strikes come from the sky's seed and the clock, so every game
## sees the same ones; thunder follows at the speed of sound.

## [time after the strike (s), brightness] of each flicker, and how fast one fades.
const FLICKERS := [[0.0, 1.0], [0.09, 0.7], [0.2, 0.9]]
const DECAY_S := 0.045
const CALM_PEAK := 0.35
const CALM_RISE_S := 0.15
const CALM_FALL_S := 0.5
## How long a strike lights the sky, and the bolt shows.
const LASTS_S := 1.5
const BOLT_S := 0.28
## A strike's chance each second at full storm; how far away it falls (m).
const CHANCE := 0.12
const NEAREST_M := 700.0
const FARTHEST_M := 6000.0
const SOUND_MPS := 343.0


## The extra brightness of a view `t` seconds after a strike (0 before it).
static func flash(t: float, calm: bool) -> float:
	if t < 0.0 or t > LASTS_S:
		return 0.0
	if calm:
		return CALM_PEAK * (smoothstep(0.0, CALM_RISE_S, t) if t < CALM_RISE_S else exp(-(t - CALM_RISE_S) / CALM_FALL_S))
	var v := 0.0
	for f: Array in FLICKERS:
		var dt := t - float(f[0])
		if dt >= 0.0:
			v += float(f[1]) * exp(-dt / DECAY_S)
	return minf(v, 1.2)


## The strike in second `slot` of the sky with `seed`, at storm strength `storm`: {} or
## {at (s), distance (m), bearing (rad)}. The same everywhere.
static func strike(seed: int, slot: int, storm: float) -> Dictionary:
	if storm <= 0.0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, slot, "lightning"])
	if rng.randf() >= storm * CHANCE:
		return {}
	return { "at": float(slot) + rng.randf(), "distance": rng.randf_range(NEAREST_M, FARTHEST_M), "bearing": rng.randf() * TAU }


## A jagged bolt from the cloud base down to the ground, `height` metres tall, made of two crossed
## strips so it shows from any side; emissive white, unshaded.
static func bolt_mesh(seed: int, height: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := PackedVector3Array([Vector3.ZERO])
	var y := 0.0
	var x := 0.0
	var z := 0.0
	while y > -height:
		y -= rng.randf_range(40.0, 90.0)
		x += rng.randf_range(-35.0, 35.0)
		z += rng.randf_range(-35.0, 35.0)
		points.append(Vector3(x, maxf(y, -height), z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: Vector3 in [Vector3(1.5, 0, 0), Vector3(0, 0, 1.5)]:
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
				st.add_vertex(v)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.92, 0.95, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	mesh.surface_set_material(0, m)
	return mesh
