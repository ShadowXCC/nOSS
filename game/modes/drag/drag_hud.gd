class_name DragHud
extends Node
## Each player's drag HUD (DragPanel) and its news (D169): what the pass is up to, what the
## driver has to do next on the device they are holding, how each shift was graded, and the
## numbers at the end of it. Captions always; spoken with race narration.
##
## Players waiting their turn watch the pass that is running and are told whose it is, so a
## splitscreen crowd always knows why they are not driving (D170).

var session: TrackSession
var _panels := {} # SessionPlayer -> DragPanel
## Prompt text by player, device and what it is for. Naming an input means a keycode lookup, so
## it is worked out when something changes rather than every frame; a new pass clears it, which
## is soon enough after a rebinding.
var _labels := {}


func _ready() -> void:
	var drag := session.drag
	drag.pass_started.connect(func(_cars: Array) -> void: _labels.clear())
	drag.pass_started.connect(_on_pass_started)
	drag.pass_ended.connect(_on_pass_ended)
	drag.shift_graded.connect(_on_shift)
	drag.fouled.connect(func(r: Racer, why: String) -> void:
		_news(r, { "red": "Red light", "centreline": "Centreline", "off": "Off the strip",
			"reset": "Reset", "stopped": "Stopped", "timeout": "Too slow" }.get(why, "Out")))
	drag.run_finished.connect(func(r: Racer, et: float, _trap: float) -> void:
		_news(r, "%.3f" % et))
	drag.engine_blown.connect(func(r: Racer) -> void: _news(r, "Engine gone"))
	drag.boost_used.connect(func(r: Racer) -> void: _news(r, "Boost"))
	drag.shake_changed.connect(func(r: Racer, on: bool) -> void:
		if on:
			_news(r, "Shake"))


## A drag pass has no laps, sectors or places to show. With the shifts timed, the engine's own
## RPM bar goes too: the panel's needle is the one to read (D169).
func apply_hud(p: SessionPlayer) -> void:
	p.hud.session_hidden = PackedStringArray(DragControl.HUD_HIDDEN)
	p.hud.session_rpm = not session.event.drag_timing
	p.hud.apply_profile(p.slot.profile)


func _process(_delta: float) -> void:
	var drag := session.drag
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null or p.vehicle == null:
			continue
		var panel: DragPanel = _panels.get(p)
		if panel == null or not is_instance_valid(panel):
			panel = DragPanel.new()
			panel.name = "DragPanel"
			p.hud.add_child(panel)
			_panels[p] = panel
		panel.palette = Palette.of(p.slot.profile)
		panel.calm = bool(p.slot.profile.data.get("reduce_flashing", false))
		panel.show_drag(_read(drag, p))


## The pass as this player sees it. A player who is not in it gets the ladder's news instead of
## a tachometer they cannot use.
func _read(drag: DragControl, p: SessionPlayer) -> Dictionary:
	var state: Dictionary = drag.run_of(p)
	var units := String(Settings.units)
	if state.is_empty():
		return { "state": _waiting_text(drag, p), "prompt": _watch_text(drag, p), "units": units }
	var gear := p.vehicle.sim.get_gear() if p.vehicle else 0
	return {
		"state": _state_text(drag, state),
		"gear": gear,
		"needle": drag.needle(p),
		"window": drag.window(p),
		"chain": int(state.chain),
		"boosts": int(state.boosts),
		"boost_name": _cached(p, "boost", "", func() -> String: return DragPrompts.boost_text(p)),
		"prompt": _prompt_text(drag, p, state, gear),
		"reaction": float(state.reaction),
		"et": float(state.et),
		"trap": float(state.trap),
		"shake": float(state.shake) > 0.0,
		"over_rev": float(state.strain) > 0.0,
		"blown": bool(state.blown),
		"foul": String(state.foul),
		"units": units,
	}


## What a waiting player is told: whose pass this is, and which round.
func _waiting_text(drag: DragControl, p: SessionPlayer) -> String:
	if drag.ended:
		return "Match over"
	if drag.cars.is_empty():
		return drag.ladder.round_text()
	var names: Array[String] = []
	for r in drag.cars:
		names.append(r.display_name)
	var who := " vs ".join(names)
	var what := "skipping" if drag.skipping else ("your turn next" if _next_up(drag, p) else "watching")
	return "%s  ·  %s" % [who, what]


## What a waiting player can do about it: hurry a pass of bots along (D178). Nothing to say when
## one of the cars is somebody's.
func _watch_text(drag: DragControl, p: SessionPlayer) -> String:
	if not drag.skipping and not drag.can_skip():
		return ""
	return _cached(p, "skip", "", func() -> String: return DragPrompts.skip_text(p))


## This player is in the pair that runs after this one.
func _next_up(drag: DragControl, p: SessionPlayer) -> bool:
	var at := drag.ladder.pair_index + 1
	if at >= drag.ladder.pairs.size():
		return false
	return p in (drag.ladder.pairs[at] as Array)


func _state_text(drag: DragControl, state: Dictionary) -> String:
	if String(state.foul):
		return "Pass lost"
	if float(state.et) >= 0.0:
		return "Through the lights"
	match drag.phase:
		DragControl.Phase.BURNOUT:
			return "Burnout"
		DragControl.Phase.STAGE:
			return "Stage"
		DragControl.Phase.TREE:
			return "Tree"
		DragControl.Phase.RUN:
			return "Go"
	return drag.ladder.round_text()


## What to do now, named for the device in their hands (DragPrompts).
func _prompt_text(drag: DragControl, p: SessionPlayer, state: Dictionary, gear: int) -> String:
	if float(state.shake) > 0.0:
		return _cached(p, "shake", "", func() -> String: return DragPrompts.shake_text(p))
	match drag.phase:
		DragControl.Phase.BURNOUT:
			return _cached(p, "burnout", "", func() -> String: return DragPrompts.burnout_text(p))
		DragControl.Phase.STAGE, DragControl.Phase.TREE:
			var action := drag.launch_action(p)
			return _cached(p, "two_step", action, func() -> String: return DragPrompts.two_step_text(p, action))
		DragControl.Phase.RUN:
			if not bool(state.launched):
				var action := drag.launch_action(p)
				return _cached(p, "launch", action, func() -> String: return DragPrompts.launch_text(p, action))
			var window: Array = drag.window(p)
			if not window.is_empty() and drag.needle(p) >= float(window[0]) - float(window[1]):
				var next := maxi(gear, 1) + 1
				return _cached(p, "shift", str(next), func() -> String: return DragPrompts.shift_text(p, next))
	return ""


## `make`'s text, worked out once per player, device and argument.
func _cached(p: SessionPlayer, what: String, arg: String, make: Callable) -> String:
	var key := "%d|%s|%s|%s" % [p.get_instance_id(), DragPrompts.device_of(p), what, arg]
	if not _labels.has(key):
		_labels[key] = String(make.call())
	return String(_labels[key])


func _on_pass_started(cars: Array) -> void:
	var names: Array[String] = []
	for r: Racer in cars:
		names.append(r.display_name)
	var who := " vs ".join(names)
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null:
			continue
		_news(p, "Your pass" if p in cars else who)


func _on_pass_ended(won: Racer) -> void:
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null or won == null:
			continue
		_news(p, "You won it" if p == won else "%s won it" % won.display_name)


func _on_shift(r: Racer, grade: String, _gear: int) -> void:
	if grade == "good":
		return # only the ones worth saying something about
	_news(r, "Perfect" if grade == "perfect" else "Missed it")


func _news(r: Racer, text: String) -> void:
	var p := r as SessionPlayer
	if p == null or p.hud == null:
		return
	p.hud.caption(text, 2.0)
	if Narrator.race_on(p.slot.profile) and not p.slot.ai:
		# Several players share one speaker: say whose it is.
		Narrator.say(text if session.players.size() == 1 else "%s %s" % [p.slot.tag(), text])
