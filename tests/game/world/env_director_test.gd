extends GdUnitTestSuite
## The sky on the world (D153): the default look is the style's own, night is dark with the moon,
## weather thickens the fog, and every player view's environment is kept in step.

class FakeView extends Node:
	var env: Environment
	func environment() -> Environment:
		return env


var _style := StyleProfile.load_profile(StyleProfile.DEFAULT)
var _haunted := EndlessBiomes.find("haunted")


func _director(time: String, weather: String) -> Array:
	var world := _style.create_environment()
	var sun := _style.create_sun()
	var d := EnvDirector.new()
	d.setup(_style, world.environment, sun, EnvState.from_settings(time, 0, weather, 5, {}, _style.data.sun), 1.0)
	add_child(world)
	add_child(sun)
	add_child(d)
	auto_free(world)
	auto_free(sun)
	auto_free(d)
	return [d, world.environment, sun]


func test_the_default_look_is_the_styles() -> void:
	var parts := _director("track", "track")
	(parts[0] as EnvDirector).apply()
	var env: Environment = parts[1]
	var sun: DirectionalLight3D = parts[2]
	var fresh: Environment = (auto_free(_style.create_environment()) as WorldEnvironment).environment
	var fresh_sun: DirectionalLight3D = auto_free(_style.create_sun())
	assert_float(env.fog_density).is_equal_approx(fresh.fog_density, 1e-6)
	assert_float(env.ambient_light_energy).is_equal_approx(fresh.ambient_light_energy, 1e-6)
	assert_float(env.tonemap_exposure).is_equal_approx(fresh.tonemap_exposure, 1e-6)
	assert_bool(env.fog_light_color.is_equal_approx(fresh.fog_light_color)).is_true()
	assert_float(sun.light_energy).is_equal_approx(fresh_sun.light_energy, 1e-6)
	assert_bool(sun.rotation.is_equal_approx(fresh_sun.rotation)).is_true()
	assert_float((parts[0] as EnvDirector).globals[&"env_night"]).is_equal(0.0)
	assert_bool((parts[0] as EnvDirector).lights_on).is_false()


func test_night_is_dark_with_the_moon_up() -> void:
	var parts := _director("night", "clear")
	var d: EnvDirector = parts[0]
	d.apply()
	var sun: DirectionalLight3D = parts[2]
	assert_float(d.night).is_greater(0.9)
	assert_bool(d.lights_on).is_true()
	assert_float(sun.light_energy).is_less(0.2)
	assert_float(sun.rotation.x).is_less(0.0) # the moon shines down
	assert_float((parts[1] as Environment).ambient_light_energy).is_less(0.4)
	assert_float(d.globals[&"env_night"]).is_greater(0.9)


func test_weather_thickens_the_fog_and_wets_the_world() -> void:
	var clear := _director("track", "clear")
	(clear[0] as EnvDirector).apply()
	var rain := _director("track", "rain")
	(rain[0] as EnvDirector).apply()
	assert_float((rain[1] as Environment).fog_density).is_greater((clear[1] as Environment).fog_density * 2.0)
	assert_float((rain[0] as EnvDirector).globals[&"env_wetness"]).is_equal(1.0)
	assert_float((rain[2] as DirectionalLight3D).light_energy).is_less((clear[2] as DirectionalLight3D).light_energy)
	var fog := _director("track", "fog")
	(fog[0] as EnvDirector).apply()
	assert_float((fog[1] as Environment).fog_density).is_greater((clear[1] as Environment).fog_density * 5.0)
	assert_bool((fog[0] as EnvDirector).lights_on).is_true()


func test_views_follow_the_sky_and_keep_their_brightness() -> void:
	var parts := _director("dusk", "rain")
	var view := FakeView.new()
	view.env = (parts[1] as Environment).duplicate()
	view.env.adjustment_enabled = true
	view.env.adjustment_brightness = 0.7
	view.add_to_group(&"player_views")
	add_child(view)
	auto_free(view)
	(parts[0] as EnvDirector).apply()
	assert_float(view.env.fog_density).is_equal((parts[1] as Environment).fog_density)
	assert_float(view.env.ambient_light_energy).is_equal((parts[1] as Environment).ambient_light_energy)
	assert_float(view.env.adjustment_brightness).is_equal_approx(0.7, 1e-6)


func after_test() -> void:
	for g: StringName in [&"env_wetness", &"env_snow", &"env_night", &"env_flicker"]:
		RenderingServer.global_shader_parameter_set(g, 0.0)


## A floodlit track (D205): at night one high, warm light and more ambient light; by day nothing
## changes.
func test_a_floodlit_night_is_brighter() -> void:
	var dark := _director("night", "clear")
	(dark[0] as EnvDirector).apply()
	var lit := _director("night", "clear")
	var d: EnvDirector = lit[0]
	d.floodlit = true
	d.apply()
	var sun: DirectionalLight3D = lit[2]
	assert_float(d.flood).is_greater(0.9)
	assert_float(sun.light_energy).is_greater((dark[2] as DirectionalLight3D).light_energy * 4.0)
	assert_float(rad_to_deg(-sun.rotation.x)).is_greater(55.0) # high overhead
	assert_float(sun.light_color.b).is_less(sun.light_color.r) # warm, not the moon's blue
	assert_float((lit[1] as Environment).ambient_light_energy).is_greater((dark[1] as Environment).ambient_light_energy * 1.5)
	assert_float(d.globals[&"env_night"]).is_greater(0.9) # still night: the lamps glow, the sky is dark
	var day := _director("noon", "clear")
	(day[0] as EnvDirector).floodlit = true
	(day[0] as EnvDirector).apply()
	var plain := _director("noon", "clear")
	(plain[0] as EnvDirector).apply()
	assert_float((day[0] as EnvDirector).flood).is_equal(0.0)
	assert_float((day[2] as DirectionalLight3D).light_energy).is_equal_approx((plain[2] as DirectionalLight3D).light_energy, 1e-6)


## Haunted (D221): night with a mist at noon in clear weather, the lamps lit, the mist not black.
func test_a_haunted_noon_is_a_misty_night() -> void:
	assert_dict(_haunted).is_not_empty()
	var parts := _director("noon", "clear")
	var d: EnvDirector = parts[0]
	d.set_biome(_haunted)
	d.apply()
	assert_float(d.night).is_greater(0.8)
	assert_bool(d.lights_on).is_true()
	assert_float(d.globals[&"env_night"]).is_greater(0.8)
	assert_float(d.snapshot.fog).is_greater_equal(0.45)
	assert_float((parts[1] as Environment).fog_light_color.get_luminance()).is_greater(0.15)
	d.set_biome({})
	d.apply()
	assert_float(d.night).is_equal(0.0)


## Into Haunted across a blend: the night and the mist only grow with its weight, and at weight 0
## it's as if there were none.
func test_it_fades_in_across_a_blend() -> void:
	var plain := _director("noon", "clear")
	(plain[0] as EnvDirector).apply()
	var parts := _director("noon", "clear")
	var d: EnvDirector = parts[0]
	var last := [-INF, -INF, INF]
	for i in 21:
		d.biomes = [{}, _haunted, i / 20.0]
		d.apply()
		var env: Environment = parts[1]
		if i == 0:
			assert_dict(d.snapshot).is_equal((plain[0] as EnvDirector).snapshot)
			assert_float(env.fog_density).is_equal((plain[1] as Environment).fog_density)
			assert_bool(env.fog_light_color.is_equal_approx((plain[1] as Environment).fog_light_color)).is_true()
			assert_float((parts[2] as DirectionalLight3D).light_energy).is_equal((plain[2] as DirectionalLight3D).light_energy)
		assert_float(d.night).is_greater_equal(last[0])
		assert_float(float(d.snapshot.fog)).is_greater_equal(last[1])
		assert_float(float(d.snapshot.elevation)).is_less_equal(last[2])
		last = [d.night, float(d.snapshot.fog), float(d.snapshot.elevation)]
	assert_float(d.night).is_greater(0.8)


## Its own fronts (storm, fog or rain: always overcast) only when the weather changes; set weather
## stays as set but for the mist.
func test_its_own_fronts_only_when_the_weather_changes() -> void:
	var at := [0.0]
	var changing := _director("noon", "changing")
	var d: EnvDirector = changing[0]
	d.set_biome(_haunted)
	d.clock = func() -> float: return at[0]
	var sky := _director("noon", "changing")
	var plain: EnvDirector = sky[0]
	plain.clock = d.clock
	var clear_seen := false
	for i in 60:
		at[0] = i * 120.0
		d.apply()
		plain.apply()
		assert_float(float(d.snapshot.cloud)).is_greater_equal(0.8)
		clear_seen = clear_seen or float(plain.snapshot.cloud) < 0.5
	assert_bool(clear_seen).is_true() # the sky's own fronts do clear
	var still := _director("noon", "clear")
	var s: EnvDirector = still[0]
	s.set_biome(_haunted)
	s.apply()
	assert_float(float(s.snapshot.cloud)).is_equal(0.0)
	assert_float(float(s.snapshot.precip)).is_equal(0.0)
	assert_float(float(s.snapshot.fog)).is_equal_approx(0.45, 1e-6)


## Its sounds: wind at least its own (a storm's louder wind kept), crickets by its night, no birds.
func test_its_wind_crickets_and_no_birds() -> void:
	var parts := _director("noon", "clear")
	var d: EnvDirector = parts[0]
	d.set_biome(_haunted)
	d.apply()
	assert_float(float(d.ambience_levels.get("wind", 0.0))).is_greater_equal(0.5)
	assert_float(float(d.ambience_levels.get("crickets", 0.0))).is_greater(0.5)
	assert_float(float(d.ambience_levels.get("birds", 0.0))).is_equal(0.0)
	var storm := _director("noon", "storm")
	(storm[0] as EnvDirector).apply()
	var stormy := _director("noon", "storm")
	(stormy[0] as EnvDirector).set_biome(_haunted)
	(stormy[0] as EnvDirector).apply()
	assert_float(float((stormy[0] as EnvDirector).ambience_levels.wind)).is_equal(float((storm[0] as EnvDirector).ambience_levels.wind))
	# A plain track has none of a biome's sounds.
	assert_bool((storm[0] as EnvDirector).ambience_levels.has("crickets")).is_false()


## Reduce flashing: lamps burn steady (env_flicker 0).
func test_reduce_flashing_steadies_the_lamps() -> void:
	var parts := _director("night", "clear")
	var d: EnvDirector = parts[0]
	d.apply()
	assert_float(d.globals[&"env_flicker"]).is_equal(1.0)
	d.calm = func() -> bool: return true
	d.apply()
	assert_float(d.globals[&"env_flicker"]).is_equal(0.0)
