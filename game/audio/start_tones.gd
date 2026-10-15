class_name StartTones
extends Node
## The start's sounds (Changes.md): a short beep as each start light comes on, and a longer,
## higher tone when they go out (or at a rolling start's green). Made once as tones, played on
## the Effects bus once for the whole screen, not per view. Online they follow the server's
## lights, and the go tone comes at the scheduled lights-out.

const BEEP_HZ := 600.0
const BEEP_S := 0.2
const GO_HZ := 1200.0
const GO_S := 0.6

static var _streams := {} # "beep" / "go" -> AudioStreamWAV

var race: RaceControl
## How many have played (tests).
var beeps := 0
var gos := 0

var _player := AudioStreamPlayer.new()
var _lights := 0
var _phase := -1


func _ready() -> void:
	_player.name = "StartTone"
	_player.bus = &"Effects"
	add_child(_player)


func _process(_delta: float) -> void:
	if race == null:
		return
	var lights := race.lights if race.phase == RaceControl.Phase.COUNTDOWN else 0
	if lights > _lights:
		beeps += 1
		_play("beep")
	_lights = lights
	if race.phase == RaceControl.Phase.RUNNING and _phase in [RaceControl.Phase.COUNTDOWN, RaceControl.Phase.FORMATION]:
		gos += 1
		_play("go")
	_phase = race.phase


func _play(tone: String) -> void:
	_player.stream = stream(tone)
	_player.play()


## The tone `name` ("beep" or "go"), made once: a sine with a little of its third harmonic, a
## quick fade in and a short fade out, so it doesn't click.
static func stream(tone: String) -> AudioStreamWAV:
	if not _streams.has(tone):
		var hz := GO_HZ if tone == "go" else BEEP_HZ
		var seconds := GO_S if tone == "go" else BEEP_S
		var n := int(EngineSound.RATE * seconds)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in n:
			var t := float(i) / EngineSound.RATE
			var envelope := minf(1.0, minf(t / 0.005, (seconds - t) / 0.03))
			var v := (sin(TAU * hz * t) + 0.25 * sin(TAU * 3.0 * hz * t)) / 1.25
			data.encode_s16(i * 2, int(v * envelope * 0.6 * 32767.0))
		_streams[tone] = EngineSound._wav(data, false)
	return _streams[tone]
