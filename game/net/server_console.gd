class_name ServerConsole
extends Node
## The dedicated server's console (docs/NETWORKING.md §9): commands typed on stdin. Reading
## blocks, so a thread reads lines and hands them to the main thread. It only starts when stdin is
## a terminal or a pipe.

const HELP := "Commands: players, kick <name>, ban <name>, say <text>, start, next, restart, quit"

## Kept for the process's life: a read can't be interrupted, so the thread is never joined.
static var _thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var kind := OS.get_stdin_type()
	if kind != OS.STD_HANDLE_CONSOLE and kind != OS.STD_HANDLE_PIPE:
		return
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_read.bind(get_instance_id()))
	NetLog.line(HELP)


static func _read(owner_id: int) -> void:
	var pending := ""
	while true:
		var chunk := OS.read_string_from_stdin(1024)
		if chunk.is_empty():
			return # end of input
		pending += chunk
		while pending.contains("\n"):
			var line := pending.get_slice("\n", 0).strip_edges()
			pending = pending.substr(pending.find("\n") + 1)
			var target := instance_from_id(owner_id)
			if line and target:
				target.call_deferred("run", line)


## Runs one command line.
func run(line: String) -> void:
	var parts := line.split(" ", false, 1)
	var cmd := parts[0].to_lower().trim_prefix("/")
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	var host := Net.host_logic
	if host == null:
		return
	match cmd:
		"help", "?":
			NetLog.line(HELP)
		"players", "status":
			NetLog.line("%d/%d players, %s, %s" % [host.server.player_count(), host.config.max_players,
				host.lobby_dict().track_name, host.lobby_dict().class_name])
			for p: NetPlayer in host.server.players.values():
				NetLog.line("  %d %s  %s  %s  %d ms" % [p.id, p.name, NetIdentity.short(p.fingerprint),
					host.server.address_of(p.peer), host.server.rtt_ms(p.peer)])
		"say":
			if arg:
				host.say("Server: " + NetChat.clean(arg))
		"kick", "ban", "start", "next", "restart":
			host.admin(1, cmd, arg)
		"quit", "stop", "exit":
			get_tree().quit()
		_:
			NetLog.line("Unknown command. " + HELP)
