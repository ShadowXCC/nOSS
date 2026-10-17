extends GdUnitTestSuite
## The sky on the world (D153): the default look is the style's own, night is dark with the moon,
## weather thickens the fog, and every player view's environment is kept in step.

class FakeView extends Node:
	var env: Environment
	func environment() -> Environment:
		return env


var _style := StyleProfile.load_profile(StyleProfile.DEFAULT)


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
	for g: StringName in [&"env_wetness", &"env_snow", &"env_night"]:
		RenderingServer.global_shader_parameter_set(g, 0.0)
