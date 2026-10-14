class_name TrafficSound
extends Node
## Traffic going by (docs/ART_AUDIO.md §7): an engine hum on the few traffic cars nearest a
## camera, pitched by their speed. Cars and vans hum like an I4, trucks and buses like a big V8
## at low revs. Synthesized once (NossAudio), shared by every player.

const VOICES := 6
const RANGE_M := 70.0
const UPDATE_S := 0.2

var manager: TrafficManager
var _players: Array[AudioStreamPlayer3D] = []
var _streams := {} # "light" / "heavy" -> AudioStreamWAV
var _time := 0.0


func _ready() -> void:
	for kind: String in ["light", "heavy"]:
		var path := EngineSound.PROFILE_DIR + ("i4" if kind == "light" else "v8_crossplane") + ".json"
		var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var synth: Dictionary = profile.get("synth", {}) if profile is Dictionary else {}
		var r: Dictionary = NossAudio.render_loop(synth, 2300.0 if kind == "light" else 1100.0, 0.35, "exhaust", 0.5)
		_streams[kind] = EngineSound._wav(r.data)
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.name = "Hum%d" % i
		p.bus = &"OtherEngines"
		p.max_distance = RANGE_M * 1.3
		p.unit_size = 6.0
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	_time += delta
	if _time < UPDATE_S:
		_follow()
		return
	_time = 0.0
	var cameras := PackedVector3Array()
	for p in manager.session.players:
		if p.cameras and p.cameras.camera:
			cameras.append(p.cameras.camera.global_position)
	var near := []
	for c in cameras:
		for car in manager.sim.cars_near(c, RANGE_M):
			near.append([TrafficManager._nearest(cameras, _pos(car)), car])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var used := {}
	var k := 0
	for n: Array in near:
		if k >= _players.size():
			break
		var car: int = n[1]
		if used.has(car):
			continue
		used[car] = true
		var p := _players[k]
		var heavy := int(manager.sim.car(car).type) in [TrafficTypes.index_of("truck"), TrafficTypes.index_of("bus")]
		var stream: AudioStreamWAV = _streams["heavy" if heavy else "light"]
		if p.stream != stream:
			p.stream = stream
		p.set_meta(&"car", car)
		if not p.playing:
			p.play()
		k += 1
	for i in range(k, _players.size()):
		_players[i].stop()
		_players[i].remove_meta(&"car")
	_follow()


func _follow() -> void:
	for p in _players:
		if not p.playing or not p.has_meta(&"car"):
			continue
		var car: int = p.get_meta(&"car")
		p.global_position = _pos(car)
		var v := absf(float(manager.sim.car(car).get("v", 0.0)))
		if manager.cars.has(car):
			v = absf((manager.cars[car] as TrafficCar).vehicle.speed())
		p.pitch_scale = clampf(0.7 + v / 30.0 * 0.5, 0.6, 1.35)


func _pos(car: int) -> Vector3:
	if manager.cars.has(car):
		return (manager.cars[car] as TrafficCar).vehicle.global_position
	var l := manager.sim.car(car)
	var p := manager.sim.lane_point(int(l.lane), float(l.s)) if int(l.get("lane", -1)) >= 0 else PackedFloat32Array()
	return Vector3(p[0], p[1] + 0.5, p[2]) if p.size() >= 3 else Vector3(0, -1000, 0)
