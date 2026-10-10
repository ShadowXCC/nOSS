class_name StyleProfile
extends RefCounted
## A swappable world look (docs/ARCHITECTURE.md §7, AV-01): environment, sky, sun and the
## global style_* uniforms of the noss_world shader. Data lives in data/styles/<id>.json.
## Cars are never restyled.

const DIR := "res://data/styles/"
const SKY_SHADER := preload("res://game/world/retro_sky.gdshader")
const DEFAULT := "retro_ps2"

var id := ""
var data := {}


static func load_profile(profile_id: String) -> StyleProfile:
	var p := StyleProfile.new()
	p.id = profile_id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + profile_id + ".json"))
	if parsed is Dictionary:
		p.data = parsed
	else:
		push_error("Style profile missing: " + profile_id)
	return p


## Largest world texture this style allows, in pixels.
func max_texture() -> int:
	return int(data.get("world", {}).get("max_texture", 512))


## Builds the WorldEnvironment and sun for a scene.
func create_environment() -> WorldEnvironment:
	var env := Environment.new()
	var sky_data: Dictionary = data.get("sky", {})
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", _color(sky_data, "top", "#2f63b4"))
	sky_mat.set_shader_parameter("horizon_color", _color(sky_data, "horizon", "#c9d6e2"))
	sky_mat.set_shader_parameter("ground_color", _color(sky_data, "ground", "#5d6b52"))
	sky_mat.set_shader_parameter("cloud_color", _color(sky_data, "cloud_color", "#f4f6f8"))
	sky_mat.set_shader_parameter("mountain_color", _color(sky_data, "mountains", "#7f8fa6"))
	sky_mat.set_shader_parameter("mountain_far_color", _color(sky_data, "mountains_far", "#a5b3c4"))
	sky_mat.set_shader_parameter("cloud_cover", float(sky_data.get("clouds", 0.45)))
	sky_mat.set_shader_parameter("mountain_height", float(sky_data.get("mountain_height", 0.055)))
	sky_mat.set_shader_parameter("noise", RetroTextures.sky_noise())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128 # blurred, low-res reflections
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	var ambient: Dictionary = data.get("ambient", {})
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(ambient.get("energy", 0.9))
	env.ambient_light_sky_contribution = float(ambient.get("sky_contribution", 0.85))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	var fog: Dictionary = data.get("fog", {})
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = _color(fog, "color", "#c3d0dc")
	env.fog_density = float(fog.get("density", 0.0016))
	env.fog_sky_affect = float(fog.get("sky_affect", 0.25))
	env.fog_sun_scatter = float(fog.get("sun_scatter", 0.15))

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if data.get("tonemap", "filmic") == "filmic" else Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = float(data.get("exposure", 1.0))
	var glow := float(data.get("glow", 0.0))
	env.glow_enabled = glow > 0.0
	env.glow_intensity = glow
	env.glow_bloom = 0.05
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false

	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	return world


func create_sun() -> DirectionalLight3D:
	var sun_data: Dictionary = data.get("sun", {})
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = _color(sun_data, "color", "#fff1d6")
	sun.light_energy = float(sun_data.get("energy", 1.25))
	sun.rotation = Vector3(-deg_to_rad(float(sun_data.get("elevation_deg", 38))), deg_to_rad(float(sun_data.get("azimuth_deg", 140))), 0)
	sun.shadow_enabled = bool(sun_data.get("shadows", true))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL # one low-res cascade
	sun.directional_shadow_max_distance = float(sun_data.get("shadow_distance_m", 120))
	sun.shadow_blur = 1.5
	return sun


## Sets the global uniforms every noss_world material reads.
func apply_globals() -> void:
	var world: Dictionary = data.get("world", {})
	RenderingServer.global_shader_parameter_set(&"style_tint", _color(world, "tint", "#ffffff"))
	RenderingServer.global_shader_parameter_set(&"style_mip_bias", float(world.get("mip_bias", 0.0)))
	RenderingServer.global_shader_parameter_set(&"style_saturation", float(world.get("saturation", 1.0)))


static func _color(d: Dictionary, key: String, fallback: String) -> Color:
	return Color.html(String(d.get(key, fallback)))
