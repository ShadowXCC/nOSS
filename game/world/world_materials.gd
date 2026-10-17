class_name WorldMaterials
extends RefCounted
## Materials for world pieces (docs/ARCHITECTURE.md §7): the shared noss_world shader with a
## retro texture, made once per kind and shared by every track.

const WORLD_SHADER := preload("res://game/world/noss_world.gdshader")

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


## A lit-up material (lamp heads, tunnel lights): `color`, glowing at `glow` of it; with
## `night_only`, only after dark (D153). Snow never settles on it.
static func glowing(key: String, color: Color, glow := 1.0, night_only := false) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := get_material(key, null, 0.5, 0.3, false, Vector2.ONE, color)
	m.set_shader_parameter("emission", color * glow)
	m.set_shader_parameter("night_glow", night_only)
	m.set_shader_parameter("snow_settle", 0.0)
	return m


## A paved surface: it shines when wet (D153).
static func _paved(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("wet_shine", 1.0)
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
			return _paved(get_material("paint_white", null, 0.6, 0.2, false, Vector2.ONE, Color(0.9, 0.9, 0.88)))
	return _paved(get_material("asphalt_plain", RetroTextures.asphalt_plain(), 0.85, 0.3, true, Vector2.ONE / 6.0))
