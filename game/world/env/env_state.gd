class_name EnvState
extends RefCounted
## A session's sky and weather (ENV-01…03, D153): a pure function of the event's settings and the
## session's clock (the server's, online), so every game shows the same sky and nothing is sent
## but the settings. at(t) gives a snapshot; EnvDirector puts it on the world.

## Start hours of the times of day an event can pick.
const HOURS := { "dawn": 6.5, "morning": 9.0, "noon": 12.5, "afternoon": 15.5, "dusk": 19.0, "night": 23.0 }
## The sun's path: a mid latitude in late spring (noon 55 degrees up; light from about 5:00 to 19:00).
const LATITUDE_DEG := 45.0
const DECLINATION_DEG := 10.0
## Weather that changes: fronts last 4 to 12 minutes and blend over a minute.
const FRONT_MIN_S := 240.0
const FRONT_MAX_S := 720.0
const BLEND_S := 60.0
## What a changing sky's fronts bring, with their odds.
const FRONT_ODDS := { "clear": 30, "cloudy": 25, "rain": 20, "storm": 8, "fog": 10, "snow": 7 }
## Each weather as [cloud cover, precipitation, storm, fog], 0..1. Clear keeps the style's own clouds.
const KINDS := {
	"clear": [0.0, 0.0, 0.0, 0.0],
	"cloudy": [0.6, 0.0, 0.0, 0.1],
	"rain": [0.85, 0.7, 0.0, 0.35],
	"storm": [1.0, 1.0, 1.0, 0.45],
	"fog": [0.8, 0.0, 0.0, 1.0],
	"snow": [0.85, 0.7, 0.0, 0.5],
}
## The road soaks this fast in rain (s) and dries this slowly after; snow settles and melts.
const WET_S := 90.0
const DRY_S := 900.0
const SNOW_S := 150.0
const MELT_S := 1800.0

## The hour the session starts at; -1: a fixed sun (fixed_elevation, fixed_azimuth).
var start_hour := -1.0
var fixed_elevation := 38.0
var fixed_azimuth := 140.0
## Game minutes per real minute (0: the time stands still).
var rate := 0.0
## A kind in KINDS, or "changing".
var weather := "clear"
var seed := 1
var _fronts: Array = [] # [start s, length s, kind]
var _rng := RandomNumberGenerator.new()


## From an event's sky settings, the track's own (its `environment` block) and the style's sun.
static func from_settings(time: String, time_rate: int, weather_pick: String, env_seed: int, track_env: Dictionary, style_sun: Dictionary) -> EnvState:
	var s := EnvState.new()
	s.fixed_elevation = float(track_env.get("sun_elevation_deg", style_sun.get("elevation_deg", 38.0)))
	s.fixed_azimuth = float(track_env.get("sun_azimuth_deg", style_sun.get("azimuth_deg", 140.0)))
	var t := time if time != "track" else String(track_env.get("time", ""))
	s.start_hour = float(HOURS.get(t, -1.0))
	s.rate = float(time_rate) if s.start_hour >= 0.0 else 0.0
	var w := weather_pick if weather_pick != "track" else String(track_env.get("weather", "clear"))
	s.weather = w if KINDS.has(w) or w == "changing" else "clear"
	s.seed = env_seed if env_seed > 0 else 1
	return s


## The sky at t seconds into the session: {hour (-1: fixed), elevation, azimuth (deg, the scene's),
## cloud, precip, storm, fog, snowing (bool), wetness, snow (0..1)}.
func at(t: float) -> Dictionary:
	var out := {}
	if start_hour < 0.0:
		out.hour = -1.0
		out.elevation = fixed_elevation
		out.azimuth = fixed_azimuth
	else:
		var hour := fposmod(start_hour + rate * t / 3600.0, 24.0)
		var sun := sun_position(hour)
		out.hour = hour
		out.elevation = sun.x
		# Noon's sun stands where the track's fixed sun does, so a track keeps its composition.
		out.azimuth = fixed_azimuth + sun.y - 180.0
	var w := _weather_at(t)
	out.cloud = w[0]
	out.precip = w[1]
	out.storm = w[2]
	out.fog = w[3]
	out.snowing = bool(w[4])
	var ground := _ground_at(t)
	out.wetness = ground.x
	out.snow = ground.y
	return out


## (elevation, compass azimuth from north) of the sun at an hour, degrees.
static func sun_position(hour: float) -> Vector2:
	var h := deg_to_rad((hour - 12.0) * 15.0)
	var lat := deg_to_rad(LATITUDE_DEG)
	var dec := deg_to_rad(DECLINATION_DEG)
	var el := asin(clampf(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h), -1.0, 1.0))
	var cos_az := (sin(dec) - sin(el) * sin(lat)) / maxf(cos(el) * cos(lat), 1e-6)
	var az := rad_to_deg(acos(clampf(cos_az, -1.0, 1.0)))
	if h > 0.0:
		az = 360.0 - az
	return Vector2(rad_to_deg(el), az)


## [cloud, precip, storm, fog, snowing] at t.
func _weather_at(t: float) -> Array:
	if weather != "changing":
		var k: Array = KINDS[weather]
		return [k[0], k[1], k[2], k[3], weather == "snow"]
	var i := _front_index(t)
	var f: Array = _fronts[i]
	var k: Array = KINDS[f[2]]
	var blend := 1.0 if i == 0 else smoothstep(0.0, BLEND_S, t - float(f[0]))
	if blend >= 1.0:
		return [k[0], k[1], k[2], k[3], f[2] == "snow"]
	var p: Array = KINDS[_fronts[i - 1][2]]
	var out := []
	for j in 4:
		out.append(lerpf(float(p[j]), float(k[j]), blend))
	out.append(f[2] == "snow" if blend >= 0.5 else _fronts[i - 1][2] == "snow")
	return out


## (wetness, snow) on the road at t: steady for set weather (rain starts wet), soaking and drying
## front by front when it changes.
func _ground_at(t: float) -> Vector2:
	if weather != "changing":
		var k: Array = KINDS[weather]
		if float(k[1]) <= 0.0:
			return Vector2.ZERO
		return Vector2(0.0, 1.0) if weather == "snow" else Vector2(1.0, 0.0)
	var last := _front_index(t)
	var first: Array = _fronts[0]
	var water := 1.0 if float(KINDS[first[2]][1]) > 0.0 and first[2] != "snow" else 0.0
	var snow := 1.0 if first[2] == "snow" else 0.0
	for i in last + 1:
		var f: Array = _fronts[i]
		var span := minf(t, float(f[0]) + float(f[1])) - maxf(float(f[0]), 0.0)
		if span <= 0.0:
			continue
		var precip := float(KINDS[f[2]][1])
		var snowing: bool = f[2] == "snow"
		var water_to := 0.0 if snowing else clampf(precip * 1.4, 0.0, 1.0)
		var snow_to := clampf(precip * 1.4, 0.0, 1.0) if snowing else 0.0
		water = water_to + (water - water_to) * exp(-span / (WET_S if water_to > water else DRY_S))
		snow = snow_to + (snow - snow_to) * exp(-span / (SNOW_S if snow_to > snow else MELT_S))
	return Vector2(water, snow)


## The front that covers t (made as far as needed, from the seed).
func _front_index(t: float) -> int:
	if _fronts.is_empty():
		_rng.seed = seed
		_fronts.append([0.0, _rng.randf_range(FRONT_MIN_S, FRONT_MAX_S), _pick(_rng, "")])
	while float(_fronts[-1][0]) + float(_fronts[-1][1]) <= t:
		var last: Array = _fronts[-1]
		_fronts.append([float(last[0]) + float(last[1]), _rng.randf_range(FRONT_MIN_S, FRONT_MAX_S), _pick(_rng, String(last[2]))])
	# Fronts are in order: the last one that has started.
	for i in range(_fronts.size() - 1, -1, -1):
		if float(_fronts[i][0]) <= t:
			return i
	return 0


## A front's weather by FRONT_ODDS, never the same as the one before.
static func _pick(rng: RandomNumberGenerator, not_this: String) -> String:
	var total := 0
	for k: String in FRONT_ODDS:
		if k != not_this:
			total += int(FRONT_ODDS[k])
	var roll := rng.randi_range(0, total - 1)
	for k: String in FRONT_ODDS:
		if k == not_this:
			continue
		roll -= int(FRONT_ODDS[k])
		if roll < 0:
			return k
	return "clear"
