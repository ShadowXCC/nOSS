class_name NetDiscovery
extends RefCounted
## LAN discovery (MP-04, D85): clients broadcast a query to the discovery ports; each server
## answers on its game port + 1 with its name, players and event. Two copies on one PC each use
## their own port, and the query also goes to 127.0.0.1, so local servers show up too.

const QUERY := "NOSS?"
const ANSWER := "NOSS!"
## Servers on game ports 47800-47815 answer on 47801-47816.
const PORTS := 16
const MAX_ANSWER := 1024
const SCAN_EVERY_S := 1.0
## A server not heard from for this long drops off the list.
const FORGET_S := 3.5


static func discovery_port(game_port: int) -> int:
	return game_port + 1


## Answers queries for a server. `info` is called for the current answer ({name, players, …}).
class Responder:
	extends Node

	var port := 0
	var info := Callable()
	var _udp := PacketPeerUDP.new()

	func start(game_port: int, p_info: Callable) -> Error:
		port = NetDiscovery.discovery_port(game_port)
		info = p_info
		process_mode = Node.PROCESS_MODE_ALWAYS
		return _udp.bind(port, "0.0.0.0")

	func stop() -> void:
		_udp.close()

	func _process(_delta: float) -> void:
		poll()

	func poll() -> void:
		while _udp.is_bound() and _udp.get_available_packet_count() > 0:
			var packet := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var from := _udp.get_packet_port()
			if packet.size() > 64 or not packet.get_string_from_utf8().begins_with(NetDiscovery.QUERY) or not info.is_valid():
				continue
			var answer := (NetDiscovery.ANSWER + JSON.stringify(info.call())).to_utf8_buffer()
			if answer.size() <= NetDiscovery.MAX_ANSWER:
				_udp.set_dest_address(ip, from)
				_udp.put_packet(answer)

	func _exit_tree() -> void:
		stop()


## Finds servers on the LAN and this PC. `servers` maps "ip:port" to {name, port, ip, players,
## max, password, track, class, state, version, seen}.
class Scanner:
	extends Node

	signal changed

	var servers := {}
	var _udp := PacketPeerUDP.new()
	var _next := 0.0
	var _time := 0.0

	func start() -> Error:
		process_mode = Node.PROCESS_MODE_ALWAYS
		var err := _udp.bind(0, "0.0.0.0")
		_udp.set_broadcast_enabled(true)
		return err

	func stop() -> void:
		_udp.close()

	func _process(delta: float) -> void:
		poll(delta)

	func poll(delta: float) -> void:
		if not _udp.is_bound():
			return
		_time += delta
		if _time >= _next:
			_next = _time + NetDiscovery.SCAN_EVERY_S
			_query()
		var dirty := false
		while _udp.get_available_packet_count() > 0:
			var packet := _udp.get_packet()
			var entry := _parse(packet, _udp.get_packet_ip())
			if entry.is_empty():
				continue
			var key := "%s:%d" % [entry.ip, entry.port]
			# One server can answer on several addresses (this PC and the LAN): list it once.
			for other: String in servers.keys():
				if other != key and servers[other].get("fp") == entry.fp and servers[other].port == entry.port:
					key = other
			entry.seen = _time
			dirty = dirty or not servers.has(key) or servers[key].get("players") != entry.players \
				or servers[key].get("name") != entry.name or servers[key].get("state") != entry.state
			entry.ip = servers[key].ip if servers.has(key) else entry.ip
			servers[key] = entry
		for key: String in servers.keys():
			if _time - float(servers[key].seen) > NetDiscovery.FORGET_S:
				servers.erase(key)
				dirty = true
		if dirty:
			changed.emit()

	func _query() -> void:
		var query := (NetDiscovery.QUERY + str(NetProtocol.VERSION)).to_utf8_buffer()
		var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
		for ip: String in IP.get_local_addresses():
			var parts := ip.split(".")
			if parts.size() == 4 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]]) # a /24 network's broadcast
		for target in targets:
			for i in NetDiscovery.PORTS:
				_udp.set_dest_address(target, NetDiscovery.discovery_port(NetProtocol.DEFAULT_PORT + i))
				_udp.put_packet(query)

	func _parse(packet: PackedByteArray, ip: String) -> Dictionary:
		if packet.size() > NetDiscovery.MAX_ANSWER:
			return {}
		var text := packet.get_string_from_utf8()
		if not text.begins_with(NetDiscovery.ANSWER):
			return {}
		var d: Variant = JSON.parse_string(text.substr(NetDiscovery.ANSWER.length()))
		if not d is Dictionary or not NetProtocol.has_fields(d, { "name": [TYPE_STRING, 48], "port": TYPE_FLOAT,
				"players": TYPE_FLOAT, "max": TYPE_FLOAT, "password": TYPE_BOOL, "track": [TYPE_STRING, 64],
				"class": [TYPE_STRING, 64], "state": [TYPE_STRING, 16], "version": [TYPE_STRING, 32], "fp": [TYPE_STRING, 24] }):
			return {}
		var port := int(d.port)
		if port < 1 or port > 65535:
			return {}
		return { "name": NetChat.clean(d.name), "port": port, "ip": ip, "players": int(d.players), "max": int(d.max),
			"password": d.password, "track": NetChat.clean(d.track), "class": NetChat.clean(d["class"]),
			"state": d.state, "version": d.version, "fp": d.fp }

	func _exit_tree() -> void:
		stop()
