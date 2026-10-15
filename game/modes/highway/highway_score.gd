class_name HighwayScore
extends Node
## Score attack in a highway session (D114): each player on this game gets the rules
## (ScoreAttack) and a pass detector (NearMiss) fed every tick from the traffic round their car,
## and a panel on their HUD. Banked and lost points are read out with race narration and shown
## as captions. Each player's best this session goes on the local board when it ends.
## Online the server scores every player too, from its own view of the cars and the traffic
## (a remote car's knocks come in its states, CarState.FLAG_KNOCK), and its totals go on the
## server's boards: what a client's HUD shows is its own count, never sent.

## Traffic this near is looked at.
const REACH_M := 30.0

var session: TrackSession
var _rules := {} # SessionPlayer -> ScoreAttack
var _miss := {} # SessionPlayer -> NearMiss
var _panels := {} # SessionPlayer -> ScorePanel
var _best := {} # SessionPlayer -> best banked this session
var _clock := 0.0


func _ready() -> void:
	process_physics_priority = -40 # after the traffic and the drivers have moved


func _physics_process(delta: float) -> void:
	_clock += delta
	for p: Racer in _scored():
		if p.vehicle == null or not is_instance_valid(p.vehicle) or p.waiting:
			continue
		var rules := rules_for(p)
		rules.paused = p.wrong_way
		var speed_kmh := p.vehicle.speed() * 3.6
		var rows: Array = session.traffic.near_rows(p.vehicle, REACH_M) if session.traffic else []
		for d: Dictionary in (_miss[p] as NearMiss).step(rows, _clock):
			if d.has("split"):
				rules.lane_split(speed_kmh, _clock)
			else:
				rules.near_miss(float(d.gap), float(d.relative_kmh), speed_kmh, _clock)
		var knock := maxf(p.vehicle.traffic_impulse, p.vehicle.wall_impulse)
		if p.vehicle.remote and p.vehicle.remote_state and p.vehicle.remote_state.flags & CarState.FLAG_KNOCK:
			knock = ScoreAttack.CONTACT_NS * 10.0 # its own game felt a knock
		if knock >= ScoreAttack.CONTACT_NS:
			rules.contact(knock, _clock)
		rules.update(_clock)
		_best[p] = maxi(int(_best.get(p, 0)), rules.banked)
		if p is SessionPlayer:
			_show(p, rules, speed_kmh)
		else:
			rules.news.clear()


## Who's scored here: this game's players; on a server, every player's car.
func _scored() -> Array:
	var out: Array = []
	out.append_array(session.players) # a plain array: other games' cars go in too
	if Net.is_server():
		for r in session.racers:
			if r is NetRacer and r.is_human:
				out.append(r)
	return out


## Player `p`'s rules (made, with its panel if it plays here, the first time).
func rules_for(p: Racer) -> ScoreAttack:
	if not _rules.has(p):
		_rules[p] = ScoreAttack.new()
		_miss[p] = NearMiss.new()
		if p is SessionPlayer and (p as SessionPlayer).hud:
			var panel := ScorePanel.new()
			panel.name = "ScorePanel"
			(p as SessionPlayer).hud.add_child(panel)
			_panels[p] = panel
	return _rules[p]


func _show(p: SessionPlayer, rules: ScoreAttack, speed_kmh: float) -> void:
	var panel: ScorePanel = _panels.get(p)
	if panel == null:
		rules.news.clear()
		return
	panel.show_rules(rules, speed_kmh, _clock)
	for news: Dictionary in rules.news:
		panel.pop(news)
		if String(news.kind) in ["banked", "lost"] and p.hud:
			p.hud.caption(String(news.text), 2.5)
			if Narrator.race_on(p.slot.profile):
				Narrator.say(String(news.text))
	rules.news.clear()


func _exit_tree() -> void:
	# What's still in the chain when the session ends banks: it ended cleanly.
	for p: Racer in _rules:
		var rules: ScoreAttack = _rules[p]
		rules.update(INF)
		_best[p] = maxi(int(_best.get(p, 0)), rules.banked)
	if session.is_online() and not Net.is_server():
		return # online scores are the server's
	for p: Racer in _best:
		if int(_best[p]) > 0 and is_instance_valid(p) and p.vehicle:
			Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(p, { "score": int(_best[p]) }), session.platform_id + "|score",
				session.is_online())
