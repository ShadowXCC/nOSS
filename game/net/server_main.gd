class_name ServerMain
extends Node
## The dedicated server (MP-02, docs/NETWORKING.md §9): `noss_server --config server.json`, or
## from the project `tools/godot.sh --headless -- --server --config=server.json`. No player of its
## own and nothing drawn; it logs to stdout and user://logs/server.log.

var config: ServerConfig


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


func _exit_tree() -> void:
	Net.leave()
	NetLog.line("Server stopped")
	NetLog.close()
