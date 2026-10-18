class_name SumoSounds
extends Node3D
## Sumo sounds (D162): the shove when cars meet, the ram boost, and the splash into the goo.
## Shoves and rams reuse the synthesized kart one-shots (NossAudio.render_fx); the splash is made
## here, so no new native sound kind is needed and every platform's build stays as it is.

const POOL := 8
## A contact below this change in speed is driving, not a shove.
const SHOVE_DV := 2.5
## One car can only set off a shove this often.
const SHOVE_GAP_S := 0.25
const SPLASH_S := 0.9

var session: TrackSession
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _quiet := {} # Vehicle -> seconds until it may be heard again
static var _splash: AudioStreamWAV


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = 10.0
		p.max_distance = 220.0
		add_child(p)
		_players.append(p)


func play(stream: AudioStream, at: Vector3, pitch := 1.0) -> void:
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.global_position = at
	p.play()


## A car lunging.
func ram(at: Vector3) -> void:
	play(KartSounds.stream("boost"), at, 0.85)


## A car going into the lava or acid.
func splash(at: Vector3) -> void:
	play(stream_splash(), at, randf_range(0.92, 1.08))


func _process(delta: float) -> void:
	for v: Variant in _quiet.keys():
		if not is_instance_valid(v):
			_quiet.erase(v)
			continue
		_quiet[v] = float(_quiet[v]) - delta
		if float(_quiet[v]) <= 0.0:
			_quiet.erase(v)
	for r: Racer in session.racers:
		var v := r.vehicle
		if v == null or not is_instance_valid(v) or r.out or _quiet.has(v):
			continue
		# Vehicle gathers car-to-car impulse each tick; a big one is a shove worth hearing.
		if v.car_impulse / maxf(v.mass, 1.0) >= SHOVE_DV:
			_quiet[v] = SHOVE_GAP_S
			play(KartSounds.stream("hit"), v.global_position, randf_range(0.85, 1.0))


## A thick glooping splash: filtered noise falling away over a low thud, made once.
static func stream_splash() -> AudioStreamWAV:
	if _splash:
		return _splash
	var n := int(EngineSound.RATE * SPLASH_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5117
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / EngineSound.RATE
		var at := t / SPLASH_S
		# Noise through a one-pole low pass that closes as it goes: a splash settling.
		var cut := lerpf(0.45, 0.04, at * at)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), cut)
		# A low tone bending down under it: the weight of the car going in.
		band = sin(TAU * lerpf(130.0, 45.0, sqrt(at)) * t)
		var envelope := minf(1.0, at / 0.02) * pow(1.0 - at, 2.2)
		var v := clampf(low * 1.6 + band * 0.45, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * envelope * 0.7 * 32767.0))
	_splash = EngineSound._wav(data, false)
	return _splash
