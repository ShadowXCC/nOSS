class_name DragSounds
extends Node3D
## Drag sounds (D169): the tree's bulbs counting down, the grind of a missed shift, the surge of
## a perfect one, the bottle, and the bang of an engine let go. The bulbs and the grind are made
## here so no new native sound kind is needed and every platform's build stays as it is; the
## surge and the bottle reuse the synthesized kart one-shots (NossAudio.render_fx).

const POOL := 6
## The tree's bulbs: a short blip, the green one lower and longer.
const BLIP_S := 0.10
const GREEN_S := 0.30
## A missed shift grinding, and an engine letting go.
const GRIND_S := 0.45
const BANG_S := 0.8

var session: TrackSession
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
static var _blip: AudioStreamWAV
static var _green: AudioStreamWAV
static var _grind: AudioStreamWAV
static var _bang: AudioStreamWAV


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = 12.0
		p.max_distance = 300.0
		add_child(p)
		_players.append(p)
	var drag := session.drag
	drag.shift_graded.connect(func(r: Racer, grade: String, _gear: int) -> void:
		if r.vehicle == null or not is_instance_valid(r.vehicle):
			return
		if grade == "perfect":
			surge(r.vehicle.global_position)
		elif grade == "miss":
			grind(r.vehicle.global_position))
	drag.boost_used.connect(func(r: Racer) -> void:
		if r.vehicle and is_instance_valid(r.vehicle):
			bottle(r.vehicle.global_position))
	drag.engine_blown.connect(func(r: Racer) -> void:
		if r.vehicle and is_instance_valid(r.vehicle):
			bang(r.vehicle.global_position))


func play(stream: AudioStream, at: Vector3, pitch := 1.0) -> void:
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.global_position = at
	p.play()


## An amber coming on (`green` false) or the green itself.
func bulb(at: Vector3, green := false) -> void:
	play(stream_green() if green else stream_blip(), at)


## A perfect shift: the kart boost, short and bright.
func surge(at: Vector3) -> void:
	play(KartSounds.stream("boost"), at, 1.25)


## A missed shift: the box grinding.
func grind(at: Vector3) -> void:
	play(stream_grind(), at, randf_range(0.94, 1.06))


## A bottle going in.
func bottle(at: Vector3) -> void:
	play(KartSounds.stream("boost"), at, 0.7)


## An engine letting go.
func bang(at: Vector3) -> void:
	play(stream_bang(), at, randf_range(0.95, 1.05))


## A short high blip: the amber bulbs.
static func stream_blip() -> AudioStreamWAV:
	if _blip == null:
		_blip = _tone(BLIP_S, 880.0, 880.0, 0.0, 0.5)
	return _blip


## Lower and longer: the green.
static func stream_green() -> AudioStreamWAV:
	if _green == null:
		_green = _tone(GREEN_S, 520.0, 500.0, 0.0, 0.55)
	return _green


## Gear teeth refusing each other: a buzz through a closing filter.
static func stream_grind() -> AudioStreamWAV:
	if _grind:
		return _grind
	var n := int(EngineSound.RATE * GRIND_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6417
	var low := 0.0
	for i in n:
		var t := float(i) / EngineSound.RATE
		var at := t / GRIND_S
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.35)
		# A rasp under the noise, the teeth skipping over each other.
		var rasp := signf(sin(TAU * lerpf(120.0, 70.0, at) * t))
		var envelope := minf(1.0, at / 0.01) * pow(1.0 - at, 1.4)
		var v := clampf(low * 0.8 + rasp * 0.35, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * envelope * 0.55 * 32767.0))
	_grind = EngineSound._wav(data, false)
	return _grind


## A bang and a hiss falling away: an engine that has had enough.
static func stream_bang() -> AudioStreamWAV:
	if _bang:
		return _bang
	var n := int(EngineSound.RATE * BANG_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x8a71
	var low := 0.0
	for i in n:
		var t := float(i) / EngineSound.RATE
		var at := t / BANG_S
		low = lerpf(low, rng.randf_range(-1.0, 1.0), lerpf(0.6, 0.08, at))
		var thump := sin(TAU * lerpf(90.0, 35.0, sqrt(at)) * t)
		var envelope := minf(1.0, at / 0.004) * pow(1.0 - at, 2.0)
		var v := clampf(low * 1.2 + thump * 0.7, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * envelope * 0.8 * 32767.0))
	_bang = EngineSound._wav(data, false)
	return _bang


## A tone from `from` Hz to `to` Hz, with an attack and a fall.
static func _tone(seconds: float, from: float, to: float, _unused: float, gain: float) -> AudioStreamWAV:
	var n := int(EngineSound.RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / EngineSound.RATE
		var at := t / seconds
		var hz := lerpf(from, to, at)
		var envelope := minf(1.0, at / 0.01) * minf(1.0, (1.0 - at) / 0.2)
		# A little of the octave above, so it reads as a lamp rather than a test tone.
		var v := sin(TAU * hz * t) * 0.8 + sin(TAU * hz * 2.0 * t) * 0.2
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * envelope * gain * 32767.0))
	return EngineSound._wav(data, false)
