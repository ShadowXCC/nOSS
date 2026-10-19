class_name SumoHud
extends Node
## Each player's sumo HUD (SumoPanel) and its news (D162): landing on a lower platform, the
## platform about to shrink, who went in and who is left. Captions always; spoken with race
## narration ("Out", "Last one" and "Winner" come from SumoControl).

var session: TrackSession
var _panels := {} # SessionPlayer -> SumoPanel
var _warned := {} # SessionPlayer -> the tier it was last warned about


func _ready() -> void:
	var sumo := session.sumo
	sumo.pushed_out.connect(_on_out)
	sumo.tier_reached.connect(func(r: Racer, tier: int) -> void:
		if r is SessionPlayer and tier > 0:
			_news(r, "Tier %d" % (tier + 1)))


## A sumo match has no laps, sectors or places to show (the Kart Battle complaint in Changes.md).
func apply_hud(p: SessionPlayer) -> void:
	p.hud.session_hidden = PackedStringArray(SumoControl.HUD_HIDDEN)
	p.hud.apply_profile(p.slot.profile)


func _process(_delta: float) -> void:
	var sumo := session.sumo
	var layout := sumo.layout
	var left := sumo.standing().size()
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null or p.vehicle == null:
			continue
		var panel: SumoPanel = _panels.get(p)
		if panel == null or not is_instance_valid(panel):
			panel = SumoPanel.new()
			panel.name = "SumoPanel"
			p.hud.add_child(panel)
			_panels[p] = panel
		panel.palette = Palette.of(p.slot.profile)
		panel.calm = bool(p.slot.profile.data.get("reduce_flashing", false))
		var tier := sumo.tier(p)
		var shrink := 1.0 if tier < 0 else layout.shrink_of(tier)
		var warn := tier >= 0 and layout.stepping(tier)
		panel.show_sumo(left, session.racers.size(), tier, layout.count(), shrink, sumo.charge(p), warn, p.out)
		if warn and int(_warned.get(p, -2)) != tier:
			_warned[p] = tier
			_news(p, "Shrinking")
		elif not warn and int(_warned.get(p, -2)) == tier:
			_warned.erase(p)


func _on_out(r: Racer) -> void:
	for other in session.racers:
		var p := other as SessionPlayer
		if p == null or p.hud == null:
			continue
		if p == r:
			_news(p, "In the goo")
		else:
			_news(p, "%s out" % r.display_name)


func _news(p: SessionPlayer, text: String) -> void:
	p.hud.caption(text, 2.0)
	if Narrator.race_on(p.slot.profile) and not p.slot.ai:
		# Several players share one speaker: say whose it is.
		Narrator.say(text if session.players.size() == 1 else "%s %s" % [p.slot.tag(), text])
