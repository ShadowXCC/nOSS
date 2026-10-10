class_name EngineSound
extends Node3D
## Placeholder engine and tire sound (docs/ART_AUDIO.md §6-7). On-load and off-load loops are
## synthesized at a base rpm and pitched with the sim's rpm; built-in sampled profiles
## replace this in M2. The sound only follows the sim, it never affects it.

const BASE_RPM := 2500.0
const RATE := 44100
const LOOP_S := 0.48 # 20 cycles of the half-order at BASE_RPM: loops seamlessly

static var _streams := {}

var vehicle: Vehicle
var _on := AudioStreamPlayer3D.new()
var _off := AudioStreamPlayer3D.new()
var _tires := AudioStreamPlayer3D.new()
var _wind := AudioStreamPlayer3D.new()
var _load := 0.0


func _ready() -> void:
	for p: Array in [[_on, "on"], [_off, "off"], [_tires, "tires"], [_wind, "wind"]]:
		var player: AudioStreamPlayer3D = p[0]
		player.stream = _stream(p[1])
		player.unit_size = 6.0
		player.max_db = 3.0
		player.volume_db = -80.0
		player.attenuation_filter_db = 0.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(player)
		player.play()


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var sim := vehicle.sim
	var rpm := maxf(sim.get_rpm(), 300.0)
	var pitch := clampf(rpm / BASE_RPM, 0.1, 4.0)
	_load = lerpf(_load, clampf(sim.get_throttle(), 0.0, 1.0), 1.0 - exp(-delta * 12.0))
	_on.pitch_scale = pitch
	_off.pitch_scale = pitch
	var level := 0.55 + 0.45 * clampf(rpm / float(vehicle.platform.engine.redline_rpm), 0.0, 1.0)
	_on.volume_db = linear_to_db(maxf(level * (0.15 + 0.85 * _load), 0.0001)) - 4.0
	_off.volume_db = linear_to_db(maxf(level * (1.0 - _load) * 0.6, 0.0001)) - 4.0

	var slip := 0.0
	for w: Dictionary in sim.get_telemetry().wheels:
		if w.contact and w.surface <= VehicleSim.SURFACE_PAINT:
			slip = maxf(slip, w.slip_speed)
	var squeal := clampf((slip - 1.5) / 6.0, 0.0, 1.0)
	_tires.volume_db = linear_to_db(maxf(squeal * 0.7, 0.0001))
	_tires.pitch_scale = 0.9 + squeal * 0.25
	var speed := vehicle.linear_velocity.length()
	_wind.volume_db = linear_to_db(maxf(clampf(speed / 80.0, 0.0, 1.0) * 0.5, 0.0001))
	_wind.pitch_scale = 0.7 + clampf(speed / 80.0, 0.0, 1.0) * 0.6


static func _stream(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var n := int(RATE * LOOP_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var fire := BASE_RPM / 60.0 * 4.0 # V8 firing frequency
	var half := fire / 8.0 # half-order burble: the loop holds a whole number of its cycles
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		match kind:
			"on":
				s = 0.5 * sin(TAU * fire * t) + 0.32 * sin(TAU * fire * 2.0 * t + 0.4) \
					+ 0.18 * sin(TAU * fire * 3.0 * t + 1.1) + 0.12 * sin(TAU * fire * 0.5 * t) \
					+ 0.22 * sin(TAU * half * t) * sin(TAU * fire * t) + 0.08 * sin(TAU * fire * 5.0 * t)
				noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.3)
				s = s * 0.8 + noise * 0.12
			"off":
				s = 0.45 * sin(TAU * fire * t) + 0.15 * sin(TAU * fire * 2.0 * t) + 0.25 * sin(TAU * half * 2.0 * t) * sin(TAU * fire * t)
				noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.15)
				s = s * 0.6 + noise * 0.1
			"tires":
				var wobble := sin(TAU * 12.5 * t) * 0.02
				s = 0.4 * sin(TAU * 950.0 * t * (1.0 + wobble)) + 0.25 * sin(TAU * 1425.0 * t) + rng.randf_range(-0.15, 0.15)
			"wind":
				noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.05)
				s = noise * 1.6
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_streams[kind] = wav
	return wav
