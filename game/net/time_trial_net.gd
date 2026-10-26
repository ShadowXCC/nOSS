class_name TimeTrialNet
extends Node
## A time trial online (docs/UI_FLOW.md §7.7, docs/NETWORKING.md §15): a timed session of hot laps,
## everyone ghosted. RaceControl ends it when the host's minutes are up (each car finishing the
## lap it's on), and its results go out as any session's (NetRace). This keeps the live board:
## the server times every car, and each driver's best lap so far, fastest first, goes to everyone
## (BOARD "live") when it changes and to a game that joins. Each improved best also goes on the
## server's own board for the track and class (not a flagged car's, D87). Clients show the live
## board on each player's HUD and in the pause menu; each player's own ghost and delta stay their
## game's (TimeTrial).

const BOARD := "live"
## How often the server looks at the bests.
const LOOK_S := 0.5

var session: TrackSession
## The live board, fastest first: [{id, name, car, time, laps}] (the server's, as it last sent it).
var entries: Array = []

var _time := 0.0
var _sent := "" # server: the board as last sent (JSON)
var _told := {} # server: peers that have it
var _bests := {} # server: car id -> best lap last put on the server's board


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -50 # after the lap timers
	if not Net.is_server():
		Net.board_received.connect(_on_board)


func _exit_tree() -> void:
	if Net.board_received.is_connected(_on_board):
		Net.board_received.disconnect(_on_board)


func _physics_process(delta: float) -> void:
	if not Net.is_server():
		return
	_time += delta
	if _time < LOOK_S:
		return
	_time = 0.0
	entries = board()
	_record()
	var text := JSON.stringify(entries)
	var data := { "board": BOARD, "entries": entries }
	if text != _sent:
		_sent = text
		_told.clear()
	for peer: int in Net.server.peers:
		if peer != 1 and Net.server.peers[peer].connected and not _told.has(peer):
			_told[peer] = true
			Net.server.send(peer, NetProtocol.Msg.BOARD, data)


## Server: each driver's best lap this session, fastest first (drivers without one left out).
func board() -> Array:
	return board_of(session.racers)


## The board of `racers`: [{id, name, car, time, laps}], fastest first.
static func board_of(racers: Array) -> Array:
	var out := []
	for r: Racer in racers:
		if r.net_id <= 0 or r.net_id >= NetProtocol.FIRST_POLICE_ID or r.timer == null or r.timer.best_lap <= 0.0:
			continue
		var car := r.vehicle.package.display_name() if r.vehicle and r.vehicle.package else ""
		out.append({ "id": r.net_id, "name": r.display_name, "car": car.left(64), "time": r.timer.best_lap, "laps": maxi(r.timer.lap - 1, 0) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	return out


## Server: a driver's new best goes on the server's board for this track and class.
func _record() -> void:
	for r in session.racers:
		if not r.is_human or r.net_id <= 0 or r.timer == null or r.timer.best_lap <= 0.0 or r.has_meta(&"flagged"):
			continue
		if r.timer.best_lap < float(_bests.get(r.net_id, INF)):
			_bests[r.net_id] = r.timer.best_lap
			Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(r, { "time": r.timer.best_lap }), "", true)


## Client: the server's board.
func _on_board(board_name: String, list: Array) -> void:
	if board_name == BOARD:
		entries = list


## 1-based place of car `id` on the board, or 0 (no lap yet).
func place_of(id: int) -> int:
	for i in entries.size():
		if int(entries[i].get("id", 0)) == id:
			return i + 1
	return 0
