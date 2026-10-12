extends GdUnitTestSuite
## Cars and tracks travel by hash over real ENet (MP-05, D80, EDT-08): a client fetches the
## host's car tier by tier and loads it from the cache; the server fetches a client's car when
## it's picked; a car over the server's cap is refused. A user track goes whole, is checked and
## loads; personal-use tracks never go; one too large is refused.

var port := 0
var server: NetServer
var host: NetHost
var server_content: NetContent
var client: NetClient
var client_content: NetContent
var pkg_path := ""
var pkg_hash := ""
var dir := "user://tests/net_content/"


func before() -> void:
	Settings.use_folder("user://tests/net_content")
	ContentStore.root = dir.path_join("cache")
	# A car only one side has: the built-in box under another name (so another hash).
	pkg_path = dir.path_join("only_here.noss")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(pkg_path)
	var files := PackageWriter.read_folder("res://content/cars/noss_box")
	var info := { "name": "Only Here", "author": "test", "license": "CC0-1.0", "family": "car" }
	var result := PackageWriter.write(pkg_path, info, files)
	assert_bool(result.ok).is_true()
	pkg_hash = Net.package_hash(pkg_path)


func after() -> void:
	ContentStore.root = "user://cache/content/"
	Settings.use_folder("user://")


func before_test() -> void:
	ContentStore.clear()
	NetTransfer.clear_blobs()
	port = 47900 + randi() % 90


func after_test() -> void:
	for n: Variant in [client_content, server_content, host, client]:
		if is_instance_valid(n):
			(n as Node).free()
	if is_instance_valid(server):
		server.stop()
		server.free()


func _start(cfg := ServerConfig.defaults(), server_has := {}, client_has := {}) -> void:
	cfg.port = port
	cfg.lan = false
	server = NetServer.new()
	server.manual_poll = true
	add_child(server)
	assert_int(server.start(cfg, NetIdentity.throwaway(), [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	server_content = NetContent.new()
	server_content.setup(true, func(peer: int, type: int, d: Dictionary) -> void: server.send(peer, type, d),
		func(peer: int, bytes: PackedByteArray) -> void: server.send_raw(peer, bytes, NetProtocol.CH_CONTENT))
	server_content.car_cap = int(cfg.caps.max_package_mb) << 20
	server_content._local = server_has
	server_content._local_scanned = true
	server_content.set_physics_process(false)
	add_child(server_content)
	server.raw.connect(func(peer: int, bytes: PackedByteArray) -> void: server_content.handle_raw(peer, bytes))
	host = NetHost.new(server)
	host.content = server_content
	host.set_physics_process(false)
	add_child(host)
	client = NetClient.new()
	client.manual_poll = true
	add_child(client)
	client_content = NetContent.new()
	client_content.setup(false, func(_peer: int, type: int, d: Dictionary) -> void: client.send(type, d),
		func(_peer: int, bytes: PackedByteArray) -> void: client.send_raw(bytes, NetProtocol.CH_CONTENT))
	client_content._local = client_has
	client_content._local_scanned = true
	client_content.set_physics_process(false)
	add_child(client_content)
	client.raw.connect(func(bytes: PackedByteArray) -> void: client_content.handle_raw(1, bytes))
	client.message.connect(func(type: int, d: Dictionary) -> void: client_content.handle_control(1, type, d))
	client.join("127.0.0.1", port, [{ "name": "Ann", "color": "ff0000" }], "", NetIdentity.throwaway())


func _pump(done: Callable, seconds := 8.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		server.poll()
		host._physics_process(0.0)
		client.poll()
		server_content._physics_process(1.0 / 120.0)
		client_content._physics_process(1.0 / 120.0)
		await get_tree().process_frame
		if done.call():
			return true
	return false


func test_a_client_fetches_the_hosts_car_tier_by_tier() -> void:
	_start(ServerConfig.defaults(), { pkg_hash: pkg_path }, {})
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	server_content.share_car(pkg_hash)
	var seen := []
	client_content.car_changed.connect(func(h: String) -> void: seen.append(NetContent.cached_tier(h)))
	assert_dict(client_content.car(pkg_hash)).is_empty() # nothing yet: a placeholder
	client_content.fetch_car(pkg_hash, 1)
	assert_bool(await _pump(func() -> bool: return client_content.car(pkg_hash).get("tier", "") == "full")).is_true()
	assert_array(seen).contains(["data"])
	assert_str(seen[-1]).is_equal("full")
	var at := client_content.car(pkg_hash)
	assert_str(at.path).is_equal(ContentStore.car_dir(pkg_hash))
	var pkg := PackageLoader.load_package(at.path)
	assert_str(pkg.error).is_empty()
	assert_str(pkg.hash).is_equal(pkg_hash)
	assert_str(pkg.display_name()).is_equal("Only Here")
	pkg.free_scenes()


func test_the_server_fetches_a_picked_car() -> void:
	_start(ServerConfig.defaults(), {}, { pkg_hash: pkg_path })
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	client_content.share_car(pkg_hash)
	client.send(NetProtocol.Msg.PICK, { "player": client.player_ids()[0], "car": pkg_hash, "bytes": NetContent.package_bytes(pkg_path),
		"car_name": "Only Here", "family": "car" })
	assert_bool(await _pump(func() -> bool: return NetContent.cached_tier(pkg_hash) == "full")).is_true()
	assert_str(server.players[client.player_ids()[0]].car_note).is_empty()


## Personal-use cars (FM4 conversions) never leave this machine (Requirements §6).
func test_personal_use_cars_are_never_sent() -> void:
	assert_bool(ContentIndex.shareable({ "license": "CC0-1.0" })).is_true()
	assert_bool(ContentIndex.shareable({ "license": ContentIndex.PERSONAL })).is_false()
	var personal := dir.path_join("personal.noss")
	DirAccess.remove_absolute(personal)
	var info := { "name": "Ripped", "author": "test", "license": ContentIndex.PERSONAL, "family": "car" }
	assert_bool(PackageWriter.write(personal, info, PackageWriter.read_folder("res://content/cars/noss_box")).ok).is_true()
	var h := Net.package_hash(personal)
	_start(ServerConfig.defaults(), { h: personal, pkg_hash: pkg_path })
	server_content.share_car(h)
	server_content.share_car(pkg_hash)
	assert_bool(server_content.index.has(h)).is_false()
	assert_bool(server_content.index.has(pkg_hash)).is_true()
	# Asked for it anyway, the server has nothing to send.
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	client_content.fetch_car(h, 1)
	await _pump(func() -> bool: return false, 1.5)
	assert_str(NetContent.cached_tier(h)).is_empty()


func test_a_car_over_the_cap_is_refused() -> void:
	var cfg := ServerConfig.defaults()
	cfg.caps.max_package_mb = 1
	_start(cfg, {}, { pkg_hash: pkg_path })
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	client_content.share_car(pkg_hash)
	var notes := []
	client.message.connect(func(type: int, d: Dictionary) -> void:
		if type == NetProtocol.Msg.NOTICE:
			notes.append(d.text))
	# It says it's small, but its files add up to more than the cap.
	server_content.car_cap = 20_000
	client.send(NetProtocol.Msg.PICK, { "player": client.player_ids()[0], "car": pkg_hash, "bytes": 100,
		"car_name": "Only Here", "family": "car" })
	assert_bool(await _pump(func() -> bool: return notes.has("Car too large for this server"))).is_true()
	assert_str(server.players[client.player_ids()[0]].car_note).is_equal("Car too large for this server")
	assert_str(NetContent.cached_tier(pkg_hash)).is_not_equal("full")
	# Saying so up front is refused at once.
	notes.clear()
	client.send(NetProtocol.Msg.PICK, { "player": client.player_ids()[0], "car": pkg_hash, "bytes": 5 << 20,
		"car_name": "Only Here", "family": "car" })
	assert_bool(await _pump(func() -> bool: return notes.has("Car too large for this server"))).is_true()


func test_partial_cars_load_at_their_tier() -> void:
	# Data only: no model; then the smallest LOD as a preview.
	var source := PackageSource.open(pkg_path, PackageLoader.DEFAULT_LIMITS)
	for rel in ["manifest.json", "fit.json", "paint.json", "sound/profile.json"]:
		assert_str(ContentStore.put_car_file(pkg_hash, rel, source.read(rel))).is_empty()
	var dir_path := ContentStore.car_dir(pkg_hash)
	assert_str(PackageLoader.load_package(dir_path).error).starts_with("Missing file")
	var data := PackageLoader.load_package(dir_path, {}, { "models": "none", "partial": true })
	assert_str(data.error).is_empty()
	assert_str(data.tier).is_equal("data")
	assert_int(data.lods.size()).is_equal(0)
	assert_str(ContentStore.put_car_file(pkg_hash, "model/body.glb", source.read("model/body.glb"))).is_empty()
	var preview := PackageLoader.load_package(dir_path, {}, { "models": "smallest", "partial": true })
	assert_str(preview.error).is_empty()
	assert_int(preview.lods.size()).is_equal(1)
	preview.free_scenes()
	source.close()


## A track only the server has (an editor track, not in anyone's library).
func _user_track(file: String, license := "CC-BY-SA-4.0") -> String:
	var path := dir.path_join(file)
	DirAccess.remove_absolute(path)
	var d := TrackTemplates.make("oval")
	d.info.name = file.get_basename()
	d.info.license = license
	assert_bool(d.save(path).ok).is_true()
	return path


func test_a_user_track_travels_and_loads() -> void:
	var path := _user_track("net_oval.nosstrack")
	var cfg := ServerConfig.defaults()
	cfg.rotation[0].track = path
	_start(cfg)
	var info := host.track_info()
	assert_str(info.path).is_equal(path)
	assert_str(info.hash).is_equal(TrackLibrary.manifest_hash(path))
	assert_int(info.bytes).is_greater(1000)
	var lobby := host.lobby_dict()
	assert_str(lobby.track).is_equal(info.hash)
	assert_str(lobby.track_name).is_equal("net_oval")
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	var h: String = info.hash
	assert_str(client_content.track_path(h)).is_empty()
	var ready := []
	client_content.track_ready.connect(func(t: String) -> void: ready.append(t))
	client_content.fetch_track(h, 1, info.bytes)
	assert_bool(await _pump(func() -> bool: return not ready.is_empty(), 20.0)).is_true()
	assert_float(client_content.track_progress(h)).is_equal(1.0)
	assert_int(client_content.track_ms(h)).is_greater_equal(0)
	# Here by hash, checked against its manifest as it loads.
	var here := TrackLibrary.by_hash(h)
	assert_str(here).is_equal(ContentStore.pkg_dir("tracks", h))
	var pkg := TrackLoader.load_package(here)
	assert_str(pkg.error).is_empty()
	assert_str(pkg.track.display_name).is_equal("net_oval")
	assert_object(pkg.terrain).is_not_null()
	# A session on it starts from the cache.
	var session := Game.online_session(host.session_dict())
	assert_object(session).is_not_null()
	assert_str(session.track_path).is_equal(here)
	for n: Node in [session.views, session.field, session.race, session]: # made with it, added in _ready
		n.free()


func test_personal_use_tracks_stay_offline() -> void:
	var path := _user_track("net_mine.nosstrack", ContentIndex.PERSONAL)
	var h := TrackLibrary.manifest_hash(path)
	var cfg := ServerConfig.defaults()
	cfg.rotation[0].track = path
	_start(cfg)
	var lines := []
	host.log_line.connect(func(l: String) -> void: lines.append(l))
	# The server runs the Proving Ground instead, and says why.
	assert_str(host.track_info().path).is_equal(TrackLibrary.DEFAULT)
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("Personal-use tracks stay offline"))).is_true()
	assert_str(server_content.share_track(path)).is_empty()
	assert_bool(server_content.index.has(h)).is_false()
	# Asked for it anyway, nothing comes.
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	client_content.fetch_track(h, 1)
	await _pump(func() -> bool: return false, 1.5)
	assert_str(TrackLibrary.by_hash(h)).is_empty()


func test_a_track_too_large_is_refused() -> void:
	var path := _user_track("net_big.nosstrack")
	var cfg := ServerConfig.defaults()
	cfg.rotation[0].track = path
	_start(cfg)
	var info := host.track_info()
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	var refused := []
	client_content.track_refused.connect(func(_h: String, why: String) -> void: refused.append(why))
	# Said up front: refused at once.
	client_content.track_cap = 1000
	client_content.fetch_track(info.hash, 1, info.bytes)
	assert_array(refused).is_equal(["Track too large"])
	assert_float(client_content.track_progress(info.hash)).is_equal(-1.0)
	# Said small, but its files add up to more.
	var other := _user_track("net_big2.nosstrack")
	var cfg2 := ServerConfig.defaults()
	cfg2.rotation[0].track = other
	host.config = cfg2
	host._tracks.clear()
	var h2: String = host.track_info().hash
	refused.clear()
	client_content.track_cap = 20_000
	client_content.fetch_track(h2, 1, 100)
	assert_bool(await _pump(func() -> bool: return not refused.is_empty())).is_true()
	assert_str(refused[0]).is_equal("Track too large")
	assert_str(TrackLibrary.by_hash(h2)).is_empty()
	# A server won't send one over its own cap: it runs the Proving Ground.
	var cfg3 := ServerConfig.defaults()
	cfg3.rotation[0].track = other
	cfg3.caps.max_track_mb = 0
	host.config = cfg3
	host._tracks.clear()
	assert_str(host.track_info().path).is_equal(TrackLibrary.DEFAULT)
