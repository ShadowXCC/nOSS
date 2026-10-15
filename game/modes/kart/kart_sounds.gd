class_name KartSounds
extends Node3D
## Kart item sounds (D139): synthesized one-shots (NossAudio.render_fx) where things happen: a box
## taken, an item fired, dropped or put up, a hit, an EMP, a boost, a drift tier reached, and the
## roulette ticking for players' own karts.

const POOL := 12
const ROULETTE_TICK_S := 0.1
const FIRED := ["bolt", "seeker", "leader_hunter"]

var session: TrackSession
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _flags := {} # Vehicle -> its kart flags last frame
var _ticks := {} # SessionPlayer -> time to its next roulette tick
static var _streams := {}


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = 10.0
		p.max_distance = 220.0
		add_child(p)
		_players.append(p)
	var items := session.kart.items
	items.got.connect(func(r: Racer, _item: String) -> void: _at(r, "pickup"))
	items.used.connect(_on_used)
	items.hit_landed.connect(func(victim: Racer, _attacker: Racer, _kind: String, blocked: bool) -> void:
		_at(victim, "shield" if blocked else "hit"))


static func stream(kind: String) -> AudioStreamWAV:
	if not _streams.has(kind):
		_streams[kind] = EngineSound._wav(NossAudio.render_fx(kind), false)
	return _streams[kind]


func play(kind: String, at: Vector3, pitch := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream(kind)
	p.pitch_scale = pitch
	p.global_position = at
	p.play()


func _at(r: Racer, kind: String, pitch := 1.0) -> void:
	if r.vehicle and is_instance_valid(r.vehicle):
		play(kind, r.vehicle.global_position, pitch)


func _on_used(r: Racer, item: String) -> void:
	if item in FIRED:
		_at(r, "fire")
	elif item == "oil_slick":
		_at(r, "slick")
	elif item == "shield":
		_at(r, "shield")
	elif item == "emp":
		_at(r, "emp")


func _process(delta: float) -> void:
	for r: Racer in session.racers:
		var v := r.vehicle
		if v == null or not is_instance_valid(v):
			continue
		var now := v.kart_flags()
		var before: int = _flags.get(v, now)
		_flags[v] = now
		var tier := (now >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3
		var was := (before >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3
		if tier > was:
			_at(r, "tier", 0.9 + 0.15 * tier)
		if now & VehicleSim.KART_FLAG_BOOST and not before & VehicleSim.KART_FLAG_BOOST:
			_at(r, "boost")
		if r is SessionPlayer and session.kart.items.slot(r).roulette > 0.0:
			_ticks[r] = float(_ticks.get(r, 0.0)) - delta
			if _ticks[r] <= 0.0:
				_ticks[r] = ROULETTE_TICK_S
				_at(r, "roulette")
