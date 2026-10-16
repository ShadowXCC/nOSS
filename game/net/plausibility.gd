class_name Plausibility
extends RefCounted
## The server's checks on a remote car's states (docs/NETWORKING.md §8, D87). nOSS is open source,
## so a determined cheater can change their game; these make cheating hard and visible:
## - speed above the platform's top speed (power against drag) plus a margin
## - acceleration no car could do, away from contacts, knocks and resets (along the ground: landing
##   off a crest or a kerb's knock is up and down, a speed cheat isn't; a car its game says was
##   knocked may lose speed suddenly, not gain it)
## - moving further between two states than its speed allows (a teleport not marked as a reset)
## - a reset that jumps ahead along the track
## - states stamped far from the server's clock
## - a lap faster than the racing line's ideal for the platform (not karts: their boosts beat it)
## Karts (D142): their top speed is the class's geared top boosted; a kart under the tow drone
## isn't driving; jumps, landings and loops jolt them; their bumps bounce.
## A car gets strikes; STRIKES within WINDOW_S trigger the server's response (warn, flag, kick).

const STRIKES := 3
const WINDOW_S := 10.0
const SPEED_MARGIN := 1.15
const SPEED_EXTRA := 8.0 # m/s: slipstream, downhill
const MAX_ACCEL := 45.0 # m/s²: well beyond any grip, short of a crash's spike
const ACCEL_GRACE_S := 0.5 # after a contact or reset
const KNOCK_GAIN := 2.0 # m/s: what a knocked car may gain and still count as knocked
const JUMP_SLACK_M := 6.0
const RESET_AHEAD_M := 40.0
const CLOCK_AHEAD_S := 0.5
const CLOCK_BEHIND_S := 5.0
const LAP_FLOOR := 0.97
const AIR_DENSITY := 1.225

## The fastest the platform's car can go on the flat, m/s.
var top_speed := 100.0
## The racing line's ideal lap for the platform here, s (0: unknown).
var ideal_lap := 0.0
## How much a knock may speed a car up (m/s): karts bounce off each other (D132).
var knock_gain := KNOCK_GAIN
const KART_KNOCK_GAIN := 6.0
var _last: CarState
var _strikes: Array[Dictionary] = [] # {time, reason}
var _grace_until := 0.0


static func for_platform(platform: Dictionary, track: TrackData, arcade := {}) -> Plausibility:
	var p := Plausibility.new()
	var power := GameModes.peak_power_kw(platform) * 1000.0
	var cd_a := maxf(float(platform.get("aero", {}).get("cd_a", 0.8)), 0.05)
	p.top_speed = pow(2.0 * power / (AIR_DENSITY * cd_a), 1.0 / 3.0)
	if not arcade.is_empty():
		p.top_speed = maxf(p.top_speed, geared_top(platform) * float(arcade.boost.cap))
		p.knock_gain = KART_KNOCK_GAIN
		return p # no lap check: boosts beat the line
	if track and track.arena == null: # an arena has no laps
		var line := RacingLine.for_track(track)
		p.ideal_lap = line.lap_time(line.speed_profile(platform, 1.0))
	return p


## A new state from the car's game, received at server time `now`; `track` places resets.
## Returns the reasons found (empty if fine).
func check(s: CarState, now: float, track: TrackData, contact := false) -> PackedStringArray:
	var out := PackedStringArray()
	if s.time - now > CLOCK_AHEAD_S or now - s.time > CLOCK_BEHIND_S:
		out.append("clock")
	if s.kart & CarState.KART_TOWED:
		# Under the tow drone: carried, not driven.
		_grace_until = now + ACCEL_GRACE_S
		_last = null
		return out
	if s.velocity.length() > top_speed * SPEED_MARGIN + SPEED_EXTRA:
		out.append("speed")
		if Game.dev.has("net-stats"): # what it was doing (checks)
			print("PLAUSIBILITY car %d speed %.1f m/s (top %.1f) at %s, flags %d, kart %d" % [s.id, s.velocity.length(), top_speed, s.xform.origin.snapped(Vector3.ONE * 0.1), s.flags, s.kart])
	if contact:
		_grace_until = now + ACCEL_GRACE_S
	var placed := s.flags & CarState.FLAG_TELEPORT != 0
	if placed:
		_grace_until = now + ACCEL_GRACE_S
		if _last and track and _ahead(track, _last.xform.origin, s.xform.origin) > RESET_AHEAD_M:
			out.append("reset ahead")
	elif _last and s.time > _last.time:
		var dt := s.time - _last.time
		if s.flags & CarState.FLAG_KNOCK and s.velocity.length() <= _last.velocity.length() + knock_gain:
			_grace_until = now + ACCEL_GRACE_S # a knock stops a car hard; it never speeds one up much
		var moved := _last.xform.origin.distance_to(s.xform.origin)
		var could := maxf(_last.velocity.length(), s.velocity.length()) * dt + JUMP_SLACK_M
		if moved > could and s.flags & CarState.FLAG_WAITING == 0:
			out.append("teleport")
		var dv := s.velocity - _last.velocity
		# Round a kart's loop the way it's going turns over and over (D137).
		var looping := track != null and track.kart != null and track.kart.by_a_loop(s.xform.origin)
		# Taking off or landing (a kart off a jump) jolts it.
		var air := (s.kart | _last.kart) & (VehicleSim.KART_FLAG_AIRBORNE | CarState.KART_STICK) != 0 # or on a wall-ride
		if looping or air:
			_grace_until = now + ACCEL_GRACE_S
		if dt > 0.01 and now >= _grace_until and Vector2(dv.x, dv.z).length() / dt > MAX_ACCEL:
			out.append("acceleration")
			if Game.dev.has("net-stats"): # what it was doing (checks)
				print("PLAUSIBILITY car %d acceleration %.0f m/s² at %s: %.1f -> %.1f m/s, flags %d, kart %d, dt %.3f" % [s.id,
					Vector2(dv.x, dv.z).length() / dt, s.xform.origin.snapped(Vector3.ONE * 0.1), _last.velocity.length(), s.velocity.length(), s.flags, s.kart, dt])
	_last = s
	return out


## The platform's top speed in its top gear at the limiter (m/s).
static func geared_top(platform: Dictionary) -> float:
	var ratios: Array = platform.get("gearbox", {}).get("ratios", [1.0])
	var ratio := float(ratios.back()) * float(platform.get("gearbox", {}).get("final_drive", 1.0))
	var rpm := float(platform.get("engine", {}).get("limiter_rpm", 7000.0))
	var r := float(platform.get("geometry", {}).get("wheel_radius_m", {}).get("ref", 0.3))
	return rpm / maxf(ratio, 0.01) * TAU / 60.0 * r


## A lap of `seconds` was timed for the car: too fast to be true?
func check_lap(seconds: float) -> bool:
	return ideal_lap > 0.0 and seconds > 0.0 and seconds < ideal_lap * LAP_FLOOR


## Records `reasons` at `now`; true once the car has STRIKES within WINDOW_S.
func strike(reasons: PackedStringArray, now: float) -> bool:
	for r in reasons:
		_strikes.append({ "time": now, "reason": r })
	_strikes = _strikes.filter(func(x: Dictionary) -> bool: return now - float(x.time) <= WINDOW_S)
	return _strikes.size() >= STRIKES


func reasons() -> String:
	var seen := {}
	for x: Dictionary in _strikes:
		seen[x.reason] = true
	return ", ".join(PackedStringArray(seen.keys()))


func clear() -> void:
	_strikes.clear()


## How far `to` is ahead of `from` along the track (m; negative behind).
static func _ahead(track: TrackData, from: Vector3, to: Vector3) -> float:
	var a: float = track.project(from).distance
	var b: float = track.project(to).distance
	var d := fposmod(b - a, track.length)
	return d if d < track.length / 2.0 else d - track.length
