class_name UpnpMapper
extends Node
## Asks the router to forward the server's UDP port (MP-04, docs/NETWORKING.md §3). Discovery
## blocks for a few seconds, so it runs on a thread. The mapping is leased for LEASE_S and renewed
## while the server runs, so a crash can't leave the port open for good; it's removed on close.

## ok, the router's public address (or ""), and a short message for the host.
signal done(ok: bool, external_ip: String, message: String)

const LEASE_S := 7200
const RENEW_S := 3600.0
const DESCRIPTION := "nOSS server"

var port := 0
var mapped := false
var external_ip := ""

var _upnp: UPNP
var _thread: Thread
var _renew_in := 0.0
var _permanent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(game_port: int) -> void:
	port = game_port
	_thread = Thread.new()
	_thread.start(_map)


func _map() -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	var ok := false
	var permanent := false
	var ip := ""
	if err == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		ok = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", LEASE_S) == UPNP.UPNP_RESULT_SUCCESS
		if not ok: # some routers only take permanent mappings; removed on close
			ok = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
			permanent = ok
		if ok:
			ip = upnp.query_external_address()
	_finish.call_deferred(upnp, ok, permanent, ip)


func _finish(upnp: UPNP, ok: bool, permanent: bool, ip: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_upnp = upnp
	mapped = ok
	_permanent = permanent
	external_ip = ip
	_renew_in = RENEW_S
	if ok:
		done.emit(true, ip, "Port open: %s:%d" % [ip, port] if ip else "Port open")
	else:
		done.emit(false, "", "Port closed. Forward UDP %d." % port)


func _process(delta: float) -> void:
	if not mapped or _permanent or _thread:
		return
	_renew_in -= delta
	if _renew_in <= 0.0:
		_renew_in = RENEW_S
		_thread = Thread.new()
		_thread.start(func() -> void:
			_upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", LEASE_S)
			_renewed.call_deferred())


func _renewed() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null


func close() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	if mapped and _upnp:
		_upnp.delete_port_mapping(port, "UDP")
	mapped = false


func _exit_tree() -> void:
	close()


## This PC's addresses others could join, for the host to share: IPv4 LAN addresses and global
## IPv6 ones (a friend may reach IPv6 without any port forwarding).
static func local_addresses() -> PackedStringArray:
	var v4 := PackedStringArray()
	var v6 := PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.contains(":"):
			var low := ip.to_lower()
			var loopback := low.replace("0:", "").replace(":", "") == "1"
			if not (loopback or low.begins_with("fe80") or low.begins_with("fd") or low.begins_with("fc")):
				v6.append(ip)
		elif not ip.begins_with("127.") and not ip.begins_with("169.254."):
			v4.append(ip)
	v4.append_array(v6)
	return v4
