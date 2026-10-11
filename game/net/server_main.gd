class_name ServerMain
extends Node
## The dedicated server (MP-02, docs/NETWORKING.md §9): `noss_server --config server.json`, or
## from the project `tools/godot.sh --headless -- --server --config=server.json`. No player of its
## own and nothing drawn; it logs to stdout and user://logs/server.log. It starts the event once
## everyone in the lobby is ready (after START_DELAY_S), and goes back to the lobby when the last
## player leaves.

const START_DELAY_S := 5.0

var config: ServerConfig
var session: TrackSession
var _countdown := -1.0


func _ready() -> void:
	NetLog.open()
	var errors := PackedStringArray()
	var file := String(Game.dev.get("config", ""))
	config = ServerConfig.load_file(file, errors) if file else ServerConfig.defaults()
	if config == null:
		for e in errors:
			NetLog.line("Config: " + e)
		get_tree().quit(1)
		return
	if Game.dev.has("port"):
		config.port = int(Game.dev.port)
	NetLog.line("nOSS %s dedicated server, %d players max%s" % [NetProtocol.game_version(), config.max_players,
		", password" if config.password else ""])
	if not Game.headless:
		NetLog.line("Not headless: start it with --headless to skip drawing")
	Net.notice.connect(NetLog.line) # answers to console commands
	Net.chat_line.connect(func(line: Dictionary) -> void:
		if line.kind == "server":
			NetLog.line(line.text))
	if Net.host(config, [], NetLog.line) != OK:
		get_tree().quit(1)
		return
	NetLog.line("Server key: " + NetIdentity.short(Net.identity().fingerprint))
	add_child(ServerConsole.new())
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_end_session)


func _process(delta: float) -> void:
	var host := Net.host_logic
	if host == null:
		return
	if host.state == "lobby":
		if host.all_ready():
			if _countdown < 0.0:
				_countdown = START_DELAY_S
				host.say("Starting in %d" % int(START_DELAY_S))
			_countdown -= delta
			if _countdown <= 0.0:
				_countdown = -1.0
				host.start_session()
		elif _countdown >= 0.0:
			_countdown = -1.0
			host.say("Start held: not everyone's ready")
	elif host.state == "session" and host.server.player_count() == 0:
		host.end_session()


func _on_session_started(data: Dictionary) -> void:
	_end_session()
	session = Game.online_session(data)
	if session == null:
		NetLog.line("Track not found: " + String(data.track))
		Net.host_logic.end_session()
		return
	add_child(session)


func _end_session() -> void:
	if session:
		session.queue_free()
		session = null


func _exit_tree() -> void:
	Net.leave()
	NetLog.line("Server stopped")
	NetLog.close()
