class_name Ambience
extends Node
## The world's sound round the players (D153, docs/ART_AUDIO.md §7): rain and wind with the
## weather, thunder after lightning, and (endless) each biome's own: surf, birds by day,
## crickets at night. Synthesized loops (NossAudio.render_weather) on the Ambience bus, the same
## for every player on this machine.

const LOOPS := ["rain", "wind", "surf", "birds", "crickets"]
## How fast a loop's level follows (per second).
const FOLLOW := 0.5
const QUIET_DB := -60.0

static var _streams := {}
var _players := {}
var _levels := {}
var _targets := {}


func _ready() -> void:
	name = "Ambience"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for kind: String in LOOPS:
		_levels[kind] = 0.0
		_targets[kind] = 0.0


## How loud each loop should be, 0..1 ({rain, wind, surf, birds, crickets}; missing: 0).
func set_levels(levels: Dictionary) -> void:
	for kind: String in LOOPS:
		_targets[kind] = clampf(float(levels.get(kind, 0.0)), 0.0, 1.0)


## Thunder after `delay` seconds at `level` (0..1, nearer is louder).
func thunder(delay: float, level: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream("thunder")
	p.bus = &"Ambience"
	p.volume_db = linear_to_db(clampf(level, 0.05, 1.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	get_tree().create_timer(maxf(delay, 0.0), false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.play())


func level(kind: String) -> float:
	return float(_levels.get(kind, 0.0))


func _process(delta: float) -> void:
	for kind: String in LOOPS:
		var now: float = move_toward(_levels[kind], _targets[kind], FOLLOW * delta)
		_levels[kind] = now
		var p: AudioStreamPlayer = _players.get(kind)
		if now <= 0.001:
			if p and p.playing:
				p.stop()
			continue
		if p == null:
			p = AudioStreamPlayer.new()
			p.stream = stream(kind)
			p.bus = &"Ambience"
			add_child(p)
			_players[kind] = p
		p.volume_db = maxf(linear_to_db(now), QUIET_DB)
		if not p.playing:
			p.play(randf() * p.stream.get_length())


## A sound, made once (loops loop).
static func stream(kind: String) -> AudioStreamWAV:
	if not _streams.has(kind):
		_streams[kind] = EngineSound._wav(NossAudio.render_weather(kind), kind != "thunder")
	return _streams[kind]
