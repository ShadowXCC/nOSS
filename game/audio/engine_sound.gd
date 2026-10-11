class_name EngineSound
extends Node3D
## Engine, tire and wind sound for one vehicle (docs/ART_AUDIO.md §6-7, AV-05, AV-06).
##
## The engine plays a built-in profile (data/sound_profiles/<id>.json): loops synthesized at a
## few rpm points (NossAudio, original sound), on- and off-load, for three emitters (engine,
## exhaust, intake). Each emitter cross-fades the two rpm points around the current rpm and
## pitches them to it. The profile's rpm range is mapped onto the platform's idle-redline.
## The car's sound/profile.json picks the profile and tunes it (pitch, mix, idle lope, turbo,
## blow-off, supercharger, gear whine, crackle, limiter). Sound never affects the sim.

const PROFILE_DIR := "res://data/sound_profiles/"
const DEFAULT_PROFILE := "v8_crossplane"
const EMITTERS := ["engine", "exhaust", "intake"]
const RATE := 44100
const BASE_DB := -6.0
## Car sounds play on volume-group buses under "Cars" (AudioMix), which splitscreen turns down.
## Sound levels of detail, picked by the session from how close the car is to a camera.
enum Detail { FULL, DISTANT, OFF }
## Distant cars play only their exhaust.
const DISTANT_EMITTERS := ["exhaust"]

static var _profiles := {} # id -> {profile, loops: {emitter: {on: [stream...], off: [...], rpm: [...]}}}
static var _extras := {}

var vehicle: Vehicle
## A local player's car (the "own engine" volume) rather than another's.
var own := false:
	set(value):
		own = value
		_route()
## FULL: every layer; DISTANT: the exhaust only; OFF: silent and stopped.
var detail := Detail.FULL:
	set(value):
		if value != detail:
			detail = value
			_apply_detail()
## Without a vehicle (the Fitting Bay) the engine state comes from here:
## {rpm, load, throttle, idle, redline, speed}.
var manual := {}

var _profile := {}
var _loops := {}
## Recorded emitters' own rpm range ([idle, max]); the others use the built-in profile's.
var _spaces := {}
## Own recorded extras (start, limiter, backfire, turbo, blowoff) -> stream(s).
var _recorded := {}
var _limiter: AudioStreamPlayer3D
var _started := false
var _tweaks := {}
var _layers := {}
var _extra_players := {}
var _tires: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _load := 0.0
var _throttle_was := 0.0
var _grinds := 0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 11
	_tires = AudioStreamPlayer3D.new()
	_wind = AudioStreamPlayer3D.new()
	for p: Array in [[_tires, "tires"], [_wind, "wind"]]:
		_setup_player(p[0], _extra(p[1]))
		add_child(p[0])
		p[0].play()
	for kind in ["turbo", "supercharger", "gear"]:
		var player := AudioStreamPlayer3D.new()
		_setup_player(player, _extra(kind))
		add_child(player)
		player.play()
		_extra_players[kind] = player
	for kind in ["pop", "blowoff"]:
		var player := AudioStreamPlayer3D.new()
		_setup_player(player, _extra(kind))
		player.volume_db = 0.0
		add_child(player)
		_extra_players[kind] = player
	if _profile.is_empty():
		set_profile(vehicle.package.sound if vehicle and vehicle.package else {}, vehicle.package.sound_streams if vehicle and vehicle.package else {})
	_route()


## Picks the car's profile and tweaks (its sound/profile.json; empty: the default). `streams` are
## its own recordings (VehiclePackage.sound_streams, AV-06): recorded emitters play them, over the
## profile's rpm range; the built-in base fills the rest.
func set_profile(sound: Dictionary, streams := {}) -> void:
	var id := String(sound.get("base", DEFAULT_PROFILE))
	var entry := _load_profile(id)
	if entry.is_empty():
		entry = _load_profile(DEFAULT_PROFILE)
	_profile = entry.profile
	_loops = entry.loops.duplicate()
	_spaces.clear()
	_recorded.clear()
	if _limiter:
		_limiter.queue_free()
		_limiter = null
	if _extra_players.has("turbo"):
		(_extra_players.turbo as AudioStreamPlayer3D).stream = _extra("turbo")
	if not streams.is_empty():
		_use_recordings(sound, streams)
	_tweaks = sound.get("tweaks", {})
	for emitter in EMITTERS:
		if not _layers.has(emitter):
			var node := Node3D.new()
			node.name = emitter.capitalize()
			add_child(node)
			var slots := {}
			for kind in ["on", "off"]:
				slots[kind] = []
				for i in 2:
					var player := AudioStreamPlayer3D.new()
					_setup_player(player, null)
					node.add_child(player)
					slots[kind].append({ "player": player, "index": -1 })
			_layers[emitter] = { "node": node, "slots": slots }
		for kind in ["on", "off"]:
			for slot: Dictionary in _layers[emitter].slots[kind]:
				slot.index = -1
	_place_emitters()


func _place_emitters() -> void:
	if vehicle == null or vehicle.fitted == null:
		return
	var e := vehicle.fitted.envelope
	# Emitters sit relative to this node, which the session puts at the car's middle.
	var exhausts: Array = vehicle.package.fit.get("exhaust_points", []) if vehicle.package else []
	var exhaust := Vector3(0, e.position.y + 0.3, e.position.z) - position
	if not exhausts.is_empty():
		exhaust = vehicle.fitted.model_xform * Vector3(exhausts[0][0], exhausts[0][1], exhausts[0][2]) - position
	_layers.exhaust.node.position = exhaust
	_layers.intake.node.position = Vector3(0, e.end.y * 0.6, e.end.z * 0.6) - position
	_layers.engine.node.position = Vector3.ZERO


func _process(delta: float) -> void:
	if _profile.is_empty() or detail == Detail.OFF:
		return
	_time += delta
	var state := _state()
	if state.is_empty():
		return
	var idle: float = state.idle
	var redline: float = maxf(state.redline, idle + 100.0)
	var norm := clampf((float(state.rpm) - idle) / (redline - idle), 0.0, 1.2)
	# The profile's rpm range on the platform's idle-redline.
	var p_idle := float(_profile.rpm_idle)
	var p_max := float(_profile.rpm_max)
	var rpm_p := p_idle + norm * (p_max - p_idle)
	if not _started and _recorded.has("start"):
		_started = true
		_play_recorded("start", 1.0)
	_load = lerpf(_load, clampf(float(state.load), 0.0, 1.0), 1.0 - exp(-delta * 10.0))
	var pitch := float(_tweaks.get("pitch", 1.0))
	# Idle lope: a lumpy cam rocks the idle.
	var lope := float(_tweaks.get("idle_lope", 0.0)) * clampf(1.0 - norm * 4.0, 0.0, 1.0)
	pitch *= 1.0 + 0.035 * lope * sin(_time * TAU * 2.3) * sin(_time * TAU * 0.7 + 1.0)
	var level := 0.45 + 0.55 * clampf(norm, 0.0, 1.0)
	level *= 1.0 - 0.25 * lope * (0.5 + 0.5 * sin(_time * TAU * 2.3))
	# Limiter character.
	if norm > 0.97 and float(state.throttle) > 0.7:
		match String(_tweaks.get("limiter", "soft")):
			"bounce":
				level *= 0.65 + 0.35 * (0.5 + 0.5 * sin(_time * TAU * 17.0))
			"cut":
				level *= 1.0 if fmod(_time * 23.0, 1.0) < 0.55 else 0.15
	var mix: Dictionary = _tweaks.get("mix", {})
	var on_limiter := norm > 0.97 and float(state.throttle) > 0.7
	if _limiter:
		_limiter.volume_db = linear_to_db(0.8 if on_limiter and detail == Detail.FULL else 0.0001) + BASE_DB
	for emitter in EMITTERS if detail == Detail.FULL else DISTANT_EMITTERS:
		var gain := level * float(_profile.mix.get(emitter, 1.0)) * float(mix.get(emitter, 1.0))
		var space: Array = _spaces.get(emitter, [])
		var rpm_e := rpm_p if space.is_empty() else float(space[0]) + norm * (float(space[1]) - float(space[0]))
		_update_layer(emitter, rpm_e, gain, pitch)
	if is_node_ready() and detail == Detail.FULL:
		_update_extras(state, norm, delta)
		_update_road(state, delta)


## Stops the players a lower detail doesn't use; a higher one starts them again on the next
## update (the rpm layers re-pick their loops, the steady ones play now).
func _apply_detail() -> void:
	for emitter: String in _layers:
		var used := detail == Detail.FULL or (detail == Detail.DISTANT and emitter in DISTANT_EMITTERS)
		for kind in ["on", "off"]:
			for slot: Dictionary in _layers[emitter].slots[kind]:
				if not used:
					(slot.player as AudioStreamPlayer3D).stop()
					slot.index = -1
	var full := detail == Detail.FULL
	for player: AudioStreamPlayer3D in [_tires, _wind, _extra_players.get("turbo"), _extra_players.get("supercharger"), _extra_players.get("gear")]:
		if player == null:
			continue
		if full and not player.playing:
			player.play()
		elif not full:
			player.stop()


## rpm, load, throttle, idle and redline from the sim, or from `manual`.
func _state() -> Dictionary:
	if vehicle and is_instance_valid(vehicle) and vehicle.remote:
		var r := vehicle.remote_state
		if r == null:
			return {}
		return {
			"rpm": r.rpm, "load": r.throttle, "throttle": r.throttle, "speed": vehicle.remote_velocity.length(),
			"idle": float(vehicle.platform.engine.idle_rpm), "redline": float(vehicle.platform.engine.redline_rpm),
		}
	if vehicle and is_instance_valid(vehicle):
		var sim := vehicle.sim
		var load := maxf(sim.get_engine_load(), sim.get_throttle())
		return {
			"rpm": sim.get_rpm(), "load": load, "throttle": sim.get_throttle(), "speed": absf(sim.get_speed()),
			"idle": float(vehicle.platform.engine.idle_rpm), "redline": float(vehicle.platform.engine.redline_rpm),
		}
	return manual


func _update_layer(emitter: String, rpm_p: float, gain: float, pitch: float) -> void:
	var loops: Dictionary = _loops[emitter]
	var points: Array = loops.rpm
	var i := 0
	while i < points.size() - 2 and rpm_p > float(points[i + 1]):
		i += 1
	var t := clampf((rpm_p - float(points[i])) / (float(points[i + 1]) - float(points[i])), 0.0, 1.0)
	for kind in ["on", "off"]:
		var load_w := _load if kind == "on" else (1.0 - _load) * 0.75
		var slots: Array = _layers[emitter].slots[kind]
		_assign(slots, loops[kind], i, i + 1)
		for slot: Dictionary in slots:
			var w := (1.0 - t) if slot.index == i else t
			var player: AudioStreamPlayer3D = slot.player
			player.volume_db = linear_to_db(maxf(gain * w * load_w, 0.0001)) + BASE_DB
			player.pitch_scale = clampf(rpm_p / float(loops.exact[kind][slot.index]) * pitch, 0.05, 8.0)


## Makes the two players play rpm points a and b, keeping one that already does.
static func _assign(slots: Array, streams: Array, a: int, b: int) -> void:
	var have := [slots[0].index, slots[1].index]
	if a in have and b in have:
		return
	for want in [a, b]:
		if want in have:
			continue
		for slot: Dictionary in slots:
			if slot.index != a and slot.index != b:
				slot.index = want
				var player: AudioStreamPlayer3D = slot.player
				player.stream = streams[want]
				player.play()
				break
		have = [slots[0].index, slots[1].index]


func _update_extras(state: Dictionary, norm: float, delta: float) -> void:
	var throttle := float(state.throttle)
	var turbo := String(_tweaks.get("turbo", "none"))
	var boost := clampf(_load - 0.3, 0.0, 1.0) * clampf(norm * 1.4, 0.0, 1.0)
	var t_player: AudioStreamPlayer3D = _extra_players.turbo
	t_player.volume_db = linear_to_db(maxf(boost * (0.0 if turbo == "none" else 0.35 if turbo == "single" else 0.5), 0.0001)) + BASE_DB
	t_player.pitch_scale = 0.6 + norm * 1.8
	# Blow-off: lifting off after boost.
	if _tweaks.get("blowoff", false) and turbo != "none" and _throttle_was > 0.7 and throttle < 0.2 and norm > 0.45:
		_one_shot("blowoff", 1.0)
	var s_player: AudioStreamPlayer3D = _extra_players.supercharger
	s_player.volume_db = linear_to_db(maxf((0.12 + 0.3 * _load) * norm if _tweaks.get("supercharger", false) else 0.0, 0.0001)) + BASE_DB
	s_player.pitch_scale = 0.5 + norm * 2.0
	var speed := clampf(float(state.get("speed", 0.0)) / 60.0, 0.0, 1.5)
	var g_player: AudioStreamPlayer3D = _extra_players.gear
	var whine := 0.22 if _tweaks.get("gear_whine", "normal") == "straight_cut" else 0.04
	g_player.volume_db = linear_to_db(maxf(whine * speed * (0.4 + 0.6 * _load), 0.0001)) + BASE_DB
	g_player.pitch_scale = 0.4 + norm * 1.6
	# Crackle on the overrun.
	var crackle := float(_tweaks.get("crackle", 0.0))
	if crackle > 0.0 and throttle < 0.1 and norm > 0.4 and _rng.randf() < crackle * 7.0 * delta:
		_one_shot("pop", _rng.randf_range(0.8, 1.3))
	_throttle_was = throttle


func _update_road(state: Dictionary, _delta: float) -> void:
	var slip := 0.0
	if vehicle and is_instance_valid(vehicle) and not vehicle.remote:
		var t := vehicle.sim.get_telemetry()
		# A refused gear change (H-pattern without the clutch) grinds.
		var grinds := int(t.get("grinds", 0))
		if grinds > _grinds:
			_one_shot("pop", 0.35)
		_grinds = grinds
		for w: Dictionary in t.wheels:
			if w.contact and w.surface <= VehicleSim.SURFACE_PAINT:
				slip = maxf(slip, w.slip_speed)
	var squeal := clampf((slip - 1.5) / 6.0, 0.0, 1.0)
	_tires.volume_db = linear_to_db(maxf(squeal * 0.7, 0.0001))
	_tires.pitch_scale = 0.9 + squeal * 0.25
	var speed := vehicle.linear_velocity.length() if vehicle and is_instance_valid(vehicle) else float(state.get("speed", 0.0))
	_wind.volume_db = linear_to_db(maxf(clampf(speed / 80.0, 0.0, 1.0) * 0.5, 0.0001))
	_wind.pitch_scale = 0.7 + clampf(speed / 80.0, 0.0, 1.0) * 0.6


func _one_shot(kind: String, pitch: float) -> void:
	var own_kind := "backfire" if kind == "pop" else kind
	if _recorded.has(own_kind):
		_play_recorded(own_kind, pitch)
		return
	var player: AudioStreamPlayer3D = _extra_players[kind]
	player.pitch_scale = pitch
	player.position = _layers.exhaust.node.position if _layers.has("exhaust") else Vector3.ZERO
	player.play()


## Own recordings (AV-06): each recorded emitter's loops come from the files, sorted by rpm, over
## the profile's rpm_idle-rpm_max; an off-load file falls back to the on-load one. Recorded extras
## replace the synthesized start, limiter, backfire, turbo and blow-off.
func _use_recordings(sound: Dictionary, streams: Dictionary) -> void:
	var space := [float(sound.get("rpm_idle", 800.0)), float(sound.get("rpm_max", 7000.0))]
	for layer: Dictionary in sound.get("layers", []):
		var samples: Array = layer.samples.duplicate()
		samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rpm) < float(b.rpm))
		var entry := { "rpm": [], "on": [], "off": [], "exact": { "on": [], "off": [] } }
		for sample: Dictionary in samples:
			var on: AudioStream = streams.get(sample.on)
			if on == null:
				entry = {}
				break
			var off: AudioStream = streams.get(sample.get("off", ""), on)
			entry.rpm.append(float(sample.rpm))
			entry.on.append(on)
			entry.off.append(off)
			entry.exact.on.append(float(sample.rpm))
			entry.exact.off.append(float(sample.rpm))
		if entry.is_empty() or entry.rpm.is_empty():
			continue
		if entry.rpm.size() == 1: # one rpm point: pitched from it both ways
			for key in ["rpm", "on", "off"]:
				entry[key].append(entry[key][0])
			entry.rpm[1] = float(entry.rpm[0]) + 1.0
			entry.exact.on.append(entry.exact.on[0])
			entry.exact.off.append(entry.exact.off[0])
		_loops[layer.emitter] = entry
		_spaces[layer.emitter] = space
	var extras: Dictionary = sound.get("extras", {})
	for key in ["start", "limiter", "turbo", "blowoff"]:
		if extras.get(key) is String and streams.has(extras[key]):
			_recorded[key] = streams[extras[key]]
	var backfires := []
	for rel: Variant in extras.get("backfire", []):
		if streams.has(rel):
			backfires.append(streams[rel])
	if not backfires.is_empty():
		_recorded.backfire = backfires
	if _recorded.has("turbo") and _extra_players.has("turbo"):
		(_extra_players.turbo as AudioStreamPlayer3D).stream = _recorded.turbo
		(_extra_players.turbo as AudioStreamPlayer3D).play()
	if _recorded.has("limiter") and is_inside_tree():
		_limiter = AudioStreamPlayer3D.new()
		_setup_player(_limiter, _recorded.limiter)
		add_child(_limiter)
		_limiter.play()
		_route()


func _play_recorded(kind: String, pitch: float) -> void:
	var stream: Variant = _recorded.get(kind)
	if stream is Array:
		stream = (stream as Array)[_rng.randi() % (stream as Array).size()]
	var player := AudioStreamPlayer3D.new()
	_setup_player(player, stream)
	player.volume_db = 0.0
	player.pitch_scale = pitch
	player.position = _layers.exhaust.node.position if _layers.has("exhaust") else Vector3.ZERO
	add_child(player)
	player.bus = &"OwnEngines" if own else &"OtherEngines"
	player.play()
	player.finished.connect(player.queue_free)


## Splitscreen mix: with n views listening, each player's own engine is loud in their own
## view, so car sound is scaled by 1/√n to keep the total level (docs/ARCHITECTURE.md §6).
static func set_listeners(n: int) -> void:
	AudioMix.set_listeners(n)


## Engines (and their turbo, gears, pops) on the own or other engines bus; tires and wind on
## the tires bus.
func _route() -> void:
	var engine := &"OwnEngines" if own else &"OtherEngines"
	AudioMix.bus(engine)
	AudioMix.bus(&"Tires")
	for player: AudioStreamPlayer3D in find_children("*", "AudioStreamPlayer3D", true, false):
		player.bus = &"Tires" if player == _tires or player == _wind else engine


static func _setup_player(player: AudioStreamPlayer3D, stream: AudioStream) -> void:
	player.bus = &"OtherEngines"
	AudioMix.bus(player.bus)
	player.stream = stream
	player.unit_size = 6.0
	player.max_db = 3.0
	player.volume_db = -80.0
	player.attenuation_filter_db = 0.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP


## A built-in profile and its rendered loops (made once per run).
static func _load_profile(id: String) -> Dictionary:
	if _profiles.has(id):
		return _profiles[id]
	var path := PROFILE_DIR + id + ".json"
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not profile is Dictionary or profile.get("schema") != "noss.sound_profile/1":
		return {}
	var loops := {}
	for emitter in EMITTERS:
		var entry := { "rpm": profile.rpm_points, "on": [], "off": [], "exact": { "on": [], "off": [] } }
		for kind in ["on", "off"]:
			for rpm: float in profile.rpm_points:
				var r: Dictionary = NossAudio.render_loop(profile.synth, rpm, 1.0 if kind == "on" else 0.0, emitter, 0.5)
				entry[kind].append(_wav(r.data))
				entry.exact[kind].append(r.rpm)
		loops[emitter] = entry
	_profiles[id] = { "profile": profile, "loops": loops }
	return _profiles[id]


## Ids and names of the built-in profiles.
static func profiles() -> Array:
	var out := []
	for file in DirAccess.get_files_at(PROFILE_DIR):
		if file.ends_with(".json"):
			var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_DIR + file))
			if p is Dictionary and p.get("schema") == "noss.sound_profile/1":
				out.append([p.id, p.name])
	return out


static func _wav(data: PackedByteArray, loop := true) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav


## Tire, wind and the tweak layers: original sounds synthesized once.
static func _extra(kind: String) -> AudioStreamWAV:
	if _extras.has(kind):
		return _extras[kind]
	var one_shot := kind in ["pop", "blowoff"]
	var seconds := 0.25 if kind == "pop" else 0.6 if kind == "blowoff" else 0.5
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	var bp_a := 0.0
	var bp_b := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		match kind:
			"tires":
				var wobble := sin(TAU * 12.0 * t) * 0.02
				s = 0.4 * sin(TAU * 950.0 * t * (1.0 + wobble)) + 0.25 * sin(TAU * 1426.0 * t) + rng.randf_range(-0.15, 0.15)
			"wind":
				noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.05)
				s = noise * 1.6
			"turbo": # whistle: 2 kHz with a little noise
				s = 0.5 * sin(TAU * 2000.0 * t) + 0.15 * sin(TAU * 4000.0 * t) + rng.randf_range(-0.05, 0.05)
			"supercharger":
				s = 0.45 * sin(TAU * 1200.0 * t) + 0.25 * sin(TAU * 2400.0 * t) + 0.1 * sin(TAU * 3600.0 * t)
			"gear":
				s = 0.5 * sin(TAU * 900.0 * t) + 0.2 * sin(TAU * 1800.0 * t)
			"pop": # a short, sharp crack
				s = rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) + 0.6 * sin(TAU * 90.0 * t) * exp(-t * 25.0)
			"blowoff": # a hiss that falls
				var white := rng.randf_range(-1.0, 1.0)
				bp_a = lerpf(bp_a, white, 0.35)
				bp_b = lerpf(bp_b, bp_a, 0.35)
				s = (bp_a - bp_b) * 3.0 * exp(-t * 6.0) * minf(t * 40.0, 1.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	_extras[kind] = _wav(data, not one_shot)
	return _extras[kind]
