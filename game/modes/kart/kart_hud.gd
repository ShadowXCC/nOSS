class_name KartHud
extends Node
## Each player's kart HUD (KartPanel) and its news (D146): the item they got once the roulette
## stops, a hit ("Hit by Rook", "Shield took it"), a Shield up, a Seeker or the Hunter coming for
## them; a battle's lives and hits. Captions always; spoken with race narration (the battle's
## "Lost a life", "Out" and "Winner" come from BattleControl).

const INCOMING_M := 150.0

var session: TrackSession
var _panels := {} # SessionPlayer -> KartPanel
var _rolling := {} # SessionPlayer -> rolling last frame
var _warned := {} # entity id -> true
var _leader: Racer # a most-hits match's leader, last heard


func _ready() -> void:
	var items := session.kart.items
	items.hit_landed.connect(_on_hit)
	items.used.connect(func(r: Racer, item: String) -> void:
		if item == "shield" and r is SessionPlayer:
			_news(r, "Shield up"))


func _process(delta: float) -> void:
	var items := session.kart.items
	_lead_news()
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null or p.vehicle == null:
			continue
		var panel: KartPanel = _panels.get(p)
		if panel == null or not is_instance_valid(panel):
			panel = KartPanel.new()
			panel.name = "KartPanel"
			p.hud.add_child(panel)
			_panels[p] = panel
		panel.palette = Palette.of(p.slot.profile)
		panel.calm = bool(p.slot.profile.data.get("reduce_flashing", false))
		var slot := items.slot(p)
		panel.show_kart(slot, p.vehicle.kart_flags(), p.vehicle.sim.get_kart_state(), delta)
		var battle := session.battle
		if battle:
			if battle.rule() == "hits":
				var order := battle.standings()
				panel.show_battle(-1, battle.hits(p), p.out, order.find(p) + 1, order.size(), battle.target_hits(), _board(battle, order, p))
			else:
				panel.show_battle(battle.lives(p), battle.hits(p), p.out)
		var rolling: bool = slot.item != "" and float(slot.roulette) > 0.0
		if _rolling.get(p, false) and not rolling and slot.item != "":
			_news(p, ItemOdds.item_name(slot.item))
		_rolling[p] = rolling
		_incoming(p)


## The top of a most-hits match: "1 Rook 5 · 2 You 3 · 3 Vega 2 · 4 Juno 1".
func _board(battle: BattleControl, order: Array[Racer], p: Racer) -> String:
	var bits := PackedStringArray()
	for i in mini(4, order.size()):
		var r := order[i]
		bits.append("%d %s %d" % [i + 1, "You" if r == p else r.display_name, battle.hits(r)])
	return "  ·  ".join(bits)


## A most-hits match's new leader, told to every player (once a hit is scored).
func _lead_news() -> void:
	var battle := session.battle
	if battle == null or battle.rule() != "hits":
		return
	var order := battle.standings()
	var top: Racer = order[0] if not order.is_empty() and battle.hits(order[0]) > 0 else null
	if top == null or top == _leader:
		return
	_leader = top
	for r in session.racers:
		var p := r as SessionPlayer
		if p and p.hud:
			_news(p, "You lead" if p == top else "%s leads" % top.display_name)


func _incoming(p: SessionPlayer) -> void:
	for e: Dictionary in session.kart.entities.list.values():
		if e.target != p or _warned.has(e.id) or not e.kind in ["seeker", "leader_hunter"]:
			continue
		if (e.pos as Vector3).distance_to(p.com()) < INCOMING_M:
			_warned[e.id] = true
			_news(p, "%s incoming" % ItemOdds.item_name(e.kind))


func _on_hit(victim: Racer, attacker: Racer, kind: String, blocked: bool) -> void:
	if not victim is SessionPlayer:
		return
	if blocked:
		_news(victim, "Shield took it")
	elif kind == "emp":
		_news(victim, "EMP")
	elif attacker and attacker != victim:
		_news(victim, "Hit by " + attacker.display_name)
	else:
		_news(victim, "Spun")


func _news(p: SessionPlayer, text: String) -> void:
	p.hud.caption(text, 2.0)
	if Narrator.race_on(p.slot.profile) and not p.slot.ai:
		# Several players share one speaker: say whose it is.
		Narrator.say(text if session.players.size() == 1 else "%s %s" % [p.slot.tag(), text])
