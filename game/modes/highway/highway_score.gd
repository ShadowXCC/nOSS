class_name HighwayScore
extends Node
## Score attack in a highway session (D114): each player on this game gets the rules
## (ScoreAttack) and a pass detector (NearMiss) fed every tick from the traffic round their car,
## and a panel on their HUD. Banked and lost points are read out with race narration and shown
## as captions. Each player's best this session goes on the local board when it ends.

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
	for p in session.players:
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
		if knock >= ScoreAttack.CONTACT_NS:
			rules.contact(knock, _clock)
		rules.update(_clock)
		_best[p] = maxi(int(_best.get(p, 0)), rules.banked)
		_show(p, rules, speed_kmh)


## Player `p`'s rules (made, with its panel, the first time).
func rules_for(p: SessionPlayer) -> ScoreAttack:
	if not _rules.has(p):
		_rules[p] = ScoreAttack.new()
		_miss[p] = NearMiss.new()
		var panel := ScorePanel.new()
		panel.name = "ScorePanel"
		if p.hud:
			p.hud.add_child(panel)
		_panels[p] = panel
	return _rules[p]


func _show(p: SessionPlayer, rules: ScoreAttack, speed_kmh: float) -> void:
	var panel: ScorePanel = _panels[p]
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
	for p: SessionPlayer in _rules:
		var rules: ScoreAttack = _rules[p]
		rules.update(INF)
		_best[p] = maxi(int(_best.get(p, 0)), rules.banked)
	if session.is_online():
		return # online scores are the server's (per-server boards)
	for p: SessionPlayer in _best:
		if int(_best[p]) > 0 and is_instance_valid(p) and p.vehicle:
			Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(p, { "score": int(_best[p]) }), session.platform_id + "|score")
