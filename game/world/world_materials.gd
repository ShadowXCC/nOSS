class_name WorldMaterials
extends RefCounted
## Materials for world pieces (docs/ARCHITECTURE.md §7): the shared noss_world shader with a
## retro texture, made once per kind and shared by every track.

const WORLD_SHADER := preload("res://game/world/noss_world.gdshader")

## A flickering lamp's chance of a dip each second, and how long one lasts (s).
const FLICKER_CHANCE := 0.4
const FLICKER_DIP_S := Vector2(0.06, 0.14)

static var _cache := {}


static func get_material(key: String, texture: Texture2D, roughness: float, specular: float, world_uv := false, uv_scale := Vector2.ONE, tint := Color.WHITE) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	if texture:
		m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("specular", specular)
	m.set_shader_parameter("world_uv", world_uv)
	m.set_shader_parameter("uv_scale", uv_scale)
	_cache[key] = m
	return m


## Open water (a track's lakes, D224): glossy, and snow never settles on it.
static func water() -> ShaderMaterial:
	if _cache.has("water"):
		return _cache["water"]
	var m := get_material("water", RetroTextures.water(), 0.06, 0.8)
	m.set_shader_parameter("snow_settle", 0.0)
	return m


## A lit-up material (lamp heads, tunnel lights): `color`, glowing at `glow` of it; with
## `night_only`, only after dark (D153); with `flickers`, dipping now and then (flicker(), D221).
## Snow never settles on it.
static func glowing(key: String, color: Color, glow := 1.0, night_only := false, flickers := false) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := get_material(key, null, 0.5, 0.3, false, Vector2.ONE, color)
	m.set_shader_parameter("emission", color * glow)
	m.set_shader_parameter("night_glow", night_only)
	m.set_shader_parameter("flicker", flickers)
	m.set_shader_parameter("snow_settle", 0.0)
	return m


## A flickering lamp's glow at `t` seconds for its `seed` (the world shader's flicker_at, its twin):
## at most one dip a second, FLICKER_DIP_S long, down to between 0.5 and 0.8, never below half
## (ACC-04: well under three flashes a second). Reduce flashing holds it at 1 (env_flicker 0).
static func flicker(t: float, seed: float) -> float:
	var sec := floorf(t)
	if _hash(sec, seed, 0.0) > FLICKER_CHANCE:
		return 1.0
	var length := lerpf(FLICKER_DIP_S.x, FLICKER_DIP_S.y, _hash(sec, seed, 1.0))
	var start := _hash(sec, seed, 2.0) * (1.0 - length)
	var x := t - sec
	if x < start or x > start + length:
		return 1.0
	return lerpf(0.5, 0.8, _hash(sec, seed, 3.0))


static func _hash(a: float, b: float, k: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233 + k * 37.719) * 43758.5453, 1.0)


## A cut-out material (`texture`'s clear pixels are holes): a catch fence's chain link.
static func see_through(key: String, texture: Texture2D, uv_scale: Vector2, tint := Color.WHITE) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := get_material(key, texture, 0.5, 0.5, false, uv_scale, tint)
	m.set_shader_parameter("alpha_scissor", true)
	m.set_shader_parameter("snow_settle", 0.0)
	return m


## Road paint in `color` (lines, painted props): paved, like the road it's on.
static func paint(key: String, color: Color) -> ShaderMaterial:
	return _paved(get_material(key, null, 0.6, 0.2, false, Vector2.ONE, color))


## `m` under cover (highway tunnels): no rain or snow reaches it (D153). Made once per material.
static func sheltered(m: ShaderMaterial) -> ShaderMaterial:
	var key := "sheltered:%d" % m.get_instance_id()
	if not _cache.has(key):
		var dry := m.duplicate() as ShaderMaterial
		dry.set_shader_parameter("weathered", 0.0)
		_cache[key] = dry
	return _cache[key]


## A paved surface: it shines when wet, and snow dusts it rather than lying in a sheet (D153).
static func _paved(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("wet_shine", 1.0)
	m.set_shader_parameter("snow_settle", 0.8) # traffic keeps a road thinner than the verges
	m.set_shader_parameter("snow_dust", 1.0)
	m.set_shader_parameter("snow_noise", RetroTextures.snow_dust())
	return m


## The material for a surface by VehicleSim id (roads, run-offs).
static func surface(id: int) -> ShaderMaterial:
	match id:
		VehicleSim.SURFACE_CONCRETE:
			return _paved(get_material("concrete_world", RetroTextures.concrete(), 0.8, 0.25, true, Vector2.ONE / 6.0))
		VehicleSim.SURFACE_GRASS:
			return get_material("runoff_grass", RetroTextures.grass(), 1.0, 0.1, true, Vector2.ONE / 5.0)
		VehicleSim.SURFACE_GRAVEL:
			return get_material("runoff_gravel", RetroTextures.gravel(), 1.0, 0.1, true, Vector2.ONE / 3.0)
		VehicleSim.SURFACE_DIRT:
			return get_material("runoff_dirt", RetroTextures.dirt(), 1.0, 0.1, true, Vector2.ONE / 4.0)
		VehicleSim.SURFACE_SAND:
			return get_material("runoff_sand", RetroTextures.sand(), 1.0, 0.1, true, Vector2.ONE / 4.0)
		VehicleSim.SURFACE_SNOW, VehicleSim.SURFACE_ICE:
			return get_material("runoff_snow", RetroTextures.snow(), 0.6, 0.3, true, Vector2.ONE / 4.0)
		VehicleSim.SURFACE_CURB:
			return _paved(get_material("curb", RetroTextures.curb(), 0.6, 0.3))
		VehicleSim.SURFACE_PAINT:
			return paint("paint_white", Color(0.9, 0.9, 0.88))
	return _paved(get_material("asphalt_plain", RetroTextures.asphalt_plain(), 0.85, 0.3, true, Vector2.ONE / 6.0))
