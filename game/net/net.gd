extends Node
## Online play (autoload "Net", docs/NETWORKING.md): holds this game's server (when hosting or
## running as a dedicated server) or client (when joined), and this install's identity.

signal state_changed

var server: NetServer
var client: NetClient

var _identity: NetIdentity


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## This install's key pair, made on first use.
func identity() -> NetIdentity:
	if _identity == null:
		_identity = NetIdentity.load_or_create(NetIdentity.dir)
	return _identity


## Uses `ident` instead of the saved one (bots, tests).
func use_identity(ident: NetIdentity) -> void:
	_identity = ident


func forget_identity() -> void:
	_identity = null


## Starts a server with `config`. `local`: this machine's players ([{name, color}]) for a listen
## server; empty for a dedicated one. `on_log` gets the server's log lines.
func host(config: ServerConfig, local: Array = [], on_log := Callable()) -> Error:
	leave()
	server = NetServer.new()
	server.name = "NetServer"
	add_child(server)
	if on_log.is_valid():
		server.log_line.connect(on_log)
	var err := server.start(config, identity(), local)
	if err != OK:
		server.queue_free()
		server = null
	state_changed.emit()
	return err


func join(host_name: String, port: int, local: Array, password := "") -> Error:
	leave()
	client = NetClient.new()
	client.name = "NetClient"
	add_child(client)
	client.left.connect(func(_reason: String) -> void: state_changed.emit())
	var err := client.join(host_name, port, local, password, identity())
	if err != OK:
		client.queue_free()
		client = null
	state_changed.emit()
	return err


func leave() -> void:
	if server:
		server.stop()
		server.queue_free()
		server = null
	if client:
		client.leave()
		client.queue_free()
		client = null
	state_changed.emit()


func is_server() -> bool:
	return server != null


func is_client() -> bool:
	return client != null and client.state != NetClient.State.IDLE


func online() -> bool:
	return is_server() or is_client()


## This machine's joined players as [{name, color}] for a server: the Players slots, or P1.
static func local_players() -> Array:
	var out := []
	for slot in Players.slots:
		if not slot.ai:
			out.append({ "name": slot.profile.display_name(), "color": slot.color().to_html(false) })
	if out.is_empty():
		out.append({ "name": Settings.primary.display_name(), "color": Palette.color(Settings.primary, "p1").to_html(false) })
	return out
