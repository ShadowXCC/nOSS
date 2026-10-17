class_name EnvDirector
extends Node
## Puts a session's sky on the world (ENV-01…03, D153): the sun by day and the moon by night (one
## light), the sky's colours, clouds, stars and moon, fog, ambient light and exposure, the world
## shaders' weather (env_wetness, env_snow, env_night), headlights and their beams, and each car's
## grip in the wet and snow. A few times a second, from EnvState at the session's clock.
## Every player view keeps its own copy of the environment (brightness, lightning), kept in step.

## How often the sky is worked out again (s), and the cars' lights and grip.
const APPLY_S := 0.25
const CARS_S := 0.5
## The style's palettes by the sun's elevation (degrees): night below, day above.
const KEYS := [[-14.0, "night"], [-3.0, "twilight"], [6.0, "golden"], [22.0, "day"]]
## Headlights on below this sun, in fog or in rain.
const LIGHTS_BELOW_DEG := 4.0
## Cars besides the players' that cast light from their headlights (nearest a camera first).
const BEAMS_NEAREST := 4
const BEAMS_M := 150.0

var state: EnvState
## Seconds since the sky started (online: from the server's clock). Unset: this node's own clock,
## which stops while the game is paused.
var clock := Callable()
## (Vehicle) -> true where the weather doesn't reach (a highway's tunnel).
var sheltered := Callable()
## () -> the players' own cars here (their headlights always light the road at night).
var local_vehicles := Callable()
## The last snapshot (EnvState.at) and what came of it: {night, lights, daylight}.
var snapshot := {}
var lights_on := false
var night := 0.0
## The world shaders' weather as last set: {env_wetness, env_snow, env_night}.
var globals := {}

var _style: StyleProfile
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _palettes := {}
var _base := {}
var _fog_scale := 1.0
var _time := 0.0
var _since := INF
var _cars_since := INF


## `fog_scale`: the track's fog (light 0.5, normal 1, heavy 2).
func setup(style: StyleProfile, env: Environment, sun: DirectionalLight3D, sky_state: EnvState, fog_scale := 1.0) -> void:
	_style = style
	_env = env
	_sun = sun
	state = sky_state
	_fog_scale = fog_scale
	_sky = (env.sky.sky_material as ShaderMaterial) if env.sky else null
	var d := style.data
	_base = {
		"fog_density": float(d.get("fog", {}).get("density", 0.0016)),
		"ambient": float(d.get("ambient", {}).get("energy", 0.9)),
		"sun_energy": float(d.get("sun", {}).get("energy", 1.25)),
		"exposure": float(d.get("exposure", 1.0)),
		"clouds": float(d.get("sky", {}).get("clouds", 0.45)),
	}
	_palettes = _read_palettes(d)


func _ready() -> void:
	name = "EnvDirector"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -58


func _exit_tree() -> void:
	for g: StringName in [&"env_wetness", &"env_snow", &"env_night"]:
		RenderingServer.global_shader_parameter_set(g, 0.0)


func now() -> float:
	return float(clock.call()) if clock.is_valid() else _time


func _physics_process(delta: float) -> void:
	_time += delta


func _process(delta: float) -> void:
	_since += delta
	_cars_since += delta
	if _since >= APPLY_S:
		_since = 0.0
		apply()
	if _cars_since >= CARS_S:
		_cars_since = 0.0
		_update_cars()


## Works the sky out for now and puts it on the world (and every view).
func apply() -> void:
	if state == null or _env == null:
		return
	snapshot = state.at(now())
	var el: float = snapshot.elevation
	var cloud: float = snapshot.cloud
	var precip: float = snapshot.precip
	var storm: float = snapshot.storm
	var fog: float = snapshot.fog
	var p := _palette(el)
	night = 1.0 - smoothstep(-12.0, -2.0, el)
	var lum := lerpf(0.1, 1.0, smoothstep(-8.0, 12.0, el))
	var over: Dictionary = _palettes.overcast
	var over_sky := (over.sky as Color) * lum
	var over_cloud := ((over.cloud_color as Color) * lum).lerp((over.storm_cloud as Color) * lum, storm * 0.7)

	var fog_color := (p.fog as Color).lerp((over.fog as Color) * lum, maxf(cloud * 0.5, fog))
	var fog_density: float = _base.fog_density * _fog_scale * (1.0 + 2.0 * precip + 6.5 * fog) * (1.6 if snapshot.snowing else 1.0)
	var ambient: float = _base.ambient * float(p.ambient) * (1.0 - 0.15 * cloud)
	var exposure: float = _base.exposure * float(p.exposure)
	_write(_env, fog_color, fog_density, ambient, exposure)
	for view in get_tree().get_nodes_in_group(&"player_views"):
		var copy: Environment = view.call(&"environment")
		if copy and copy != _env:
			_write(copy, fog_color, fog_density, ambient, exposure)

	# The light: the sun above the horizon, the moon (opposite) below it.
	var az: float = snapshot.azimuth
	if el > -3.0:
		_sun.light_color = p.sun
		_sun.light_energy = _base.sun_energy * float(p.sun_energy) * smoothstep(-3.0, 6.0, el) * (1.0 - 0.7 * cloud)
		_sun.rotation = Vector3(-deg_to_rad(maxf(el, 3.0)), deg_to_rad(az), 0.0)
	else:
		var night_p: Dictionary = _palettes.night
		_sun.light_color = night_p.moon
		_sun.light_energy = float(night_p.moon_energy) * (1.0 - smoothstep(-12.0, -3.0, el)) * (1.0 - 0.6 * cloud)
		_sun.rotation = Vector3(-deg_to_rad(maxf(-el, 12.0)), deg_to_rad(az + 180.0), 0.0)
	_sun.shadow_opacity = 1.0 - 0.8 * cloud

	if _sky:
		var sun_dir := Basis.from_euler(Vector3(-deg_to_rad(el), deg_to_rad(az), 0.0)).z
		_sky.set_shader_parameter("top_color", (p.top as Color).lerp(over_sky, cloud * 0.7))
		_sky.set_shader_parameter("horizon_color", (p.horizon as Color).lerp(over_sky * 1.05, cloud * 0.6))
		_sky.set_shader_parameter("ground_color", p.ground)
		_sky.set_shader_parameter("cloud_color", (p.cloud_color as Color).lerp(over_cloud, cloud * 0.6))
		_sky.set_shader_parameter("mountain_color", p.mountains)
		_sky.set_shader_parameter("mountain_far_color", (p.mountains_far as Color).lerp(fog_color, fog * 0.6))
		_sky.set_shader_parameter("cloud_cover", lerpf(_base.clouds, 1.0, cloud))
		_sky.set_shader_parameter("sun_dir", sun_dir)
		_sky.set_shader_parameter("moon_dir", -sun_dir)
		_sky.set_shader_parameter("sun_color", p.sun)
		_sky.set_shader_parameter("sun_disc", (1.0 - 0.95 * cloud) * smoothstep(-2.0, 1.0, el))
		_sky.set_shader_parameter("night", night * (1.0 - 0.85 * cloud))

	globals = { &"env_wetness": float(snapshot.wetness), &"env_snow": float(snapshot.snow), &"env_night": night }
	for g: StringName in globals:
		RenderingServer.global_shader_parameter_set(g, globals[g])
	lights_on = el < LIGHTS_BELOW_DEG or fog > 0.5 or precip > 0.3


func _write(env: Environment, fog_color: Color, fog_density: float, ambient: float, exposure: float) -> void:
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.ambient_light_energy = ambient
	env.tonemap_exposure = exposure


## Headlights (and the nearest cars' beams) and grip, for every car.
func _update_cars() -> void:
	if snapshot.is_empty():
		return
	var wet: float = snapshot.wetness
	var snow: float = snapshot.snow
	var cams := PackedVector3Array()
	for rig in CameraRig.rigs:
		if is_instance_valid(rig) and rig.camera.is_inside_tree():
			cams.append(rig.camera.global_position)
	var own: Array = local_vehicles.call() if local_vehicles.is_valid() else []
	var near: Array = []
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var v := node as Vehicle
		if v == null or not v.is_inside_tree():
			continue
		v.head_lights = 1 if lights_on else 0
		var dry := sheltered.is_valid() and bool(sheltered.call(v))
		v.set_road(0.0 if dry else wet, 0.0 if dry else snow)
		var d := INF
		for c in cams:
			d = minf(d, c.distance_to(v.global_position))
		near.append([d, v])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var others := 0
	for pair: Array in near:
		var v: Vehicle = pair[1]
		var mine := v in own
		var beam := lights_on and (mine or (others < BEAMS_NEAREST and float(pair[0]) < BEAMS_M))
		if beam and not mine:
			others += 1
		v.set_beams(beam)


## The style's palettes blended for a sun elevation.
func _palette(el: float) -> Dictionary:
	if el >= KEYS[-1][0]:
		return _palettes.day
	if el <= KEYS[0][0]:
		return _palettes.night
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if el <= b[0]:
			return _mix(_palettes[a[1]], _palettes[b[1]], smoothstep(a[0], b[0], el))
	return _palettes.day


static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k: String in b:
		if not a.has(k):
			out[k] = b[k]
		elif b[k] is Color:
			out[k] = (a[k] as Color).lerp(b[k], t)
		else:
			out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out


## Day is the style's own look; the others come from its "times" block, the overcast sky from
## "overcast".
static func _read_palettes(d: Dictionary) -> Dictionary:
	var sky: Dictionary = d.get("sky", {})
	var c := func(dict: Dictionary, key: String, fallback: String) -> Color: return Color.html(String(dict.get(key, fallback)))
	var day := {
		"top": c.call(sky, "top", "#2f63b4"), "horizon": c.call(sky, "horizon", "#c9d6e2"), "ground": c.call(sky, "ground", "#5d6b52"),
		"cloud_color": c.call(sky, "cloud_color", "#f4f6f8"), "mountains": c.call(sky, "mountains", "#7f8fa6"),
		"mountains_far": c.call(sky, "mountains_far", "#a5b3c4"), "fog": c.call(d.get("fog", {}), "color", "#c3d0dc"),
		"sun": c.call(d.get("sun", {}), "color", "#fff1d6"), "sun_energy": 1.0, "ambient": 1.0, "exposure": 1.0,
	}
	var out := { "day": day }
	var times: Dictionary = d.get("times", {})
	for key: String in ["golden", "twilight", "night"]:
		var t: Dictionary = times.get(key, {})
		var pal := {}
		for k: String in day:
			if day[k] is Color:
				pal[k] = c.call(t, k, (day[k] as Color).to_html(false))
			else:
				pal[k] = float(t.get(k, day[k]))
		out[key] = pal
	var night: Dictionary = out.night
	night.moon = c.call(times.get("night", {}), "moon", "#a8bce0")
	night.moon_energy = float(times.get("night", {}).get("moon_energy", 0.16))
	var o: Dictionary = d.get("overcast", {})
	out.overcast = {
		"sky": c.call(o, "sky", "#8a9099"), "fog": c.call(o, "fog", "#9aa1aa"),
		"cloud_color": c.call(o, "cloud_color", "#b4b9c0"), "storm_cloud": c.call(o, "storm_cloud", "#4a4f58"),
	}
	return out
