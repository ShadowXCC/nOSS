extends GdUnitTestSuite
## Online basics (D78, D81): the message format, identities, password proofs, the server config
## and the command line.


func before() -> void:
	Settings.use_folder("user://tests/net_core")


func after() -> void:
	Settings.use_folder("user://")


func test_messages_round_trip_and_reject_junk() -> void:
	var bytes := NetProtocol.encode(NetProtocol.Msg.BYE, { "reason": "Kicked" })
	var msg := NetProtocol.decode(bytes)
	assert_int(msg.type).is_equal(NetProtocol.Msg.BYE)
	assert_str(msg.data.reason).is_equal("Kicked")
	assert_dict(NetProtocol.decode(PackedByteArray([10]))).is_empty()
	assert_dict(NetProtocol.decode(PackedByteArray([10, 1, 2, 3, 4, 5]))).is_empty()
	var not_dict := PackedByteArray([10])
	not_dict.append_array(var_to_bytes([1, 2]))
	assert_dict(NetProtocol.decode(not_dict)).is_empty()
	assert_dict(NetProtocol.decode(bytes, 4)).is_empty() # longer than allowed


func test_field_checks() -> void:
	var spec := { "name": [TYPE_STRING, 4], "n": TYPE_INT, "x": TYPE_FLOAT, "list": [TYPE_ARRAY, 2] }
	assert_bool(NetProtocol.has_fields({ "name": "abc", "n": 1, "x": 2, "list": [1] }, spec)).is_true()
	assert_bool(NetProtocol.has_fields({ "name": "abcde", "n": 1, "x": 2.0, "list": [] }, spec)).is_false()
	assert_bool(NetProtocol.has_fields({ "name": "a", "n": 1.5, "x": 2.0, "list": [] }, spec)).is_false()
	assert_bool(NetProtocol.has_fields({ "name": "a", "n": 1, "x": 2.0, "list": [1, 2, 3] }, spec)).is_false()
	assert_bool(NetProtocol.has_fields({ "name": "a", "n": 1, "list": [] }, spec)).is_false()


func test_names_are_cleaned() -> void:
	assert_str(NetProtocol.clean_name("  Ann\n\u0007 ")).is_equal("Ann")
	assert_str(NetProtocol.clean_name("")).is_equal("Player")
	assert_int(NetProtocol.clean_name("x".repeat(100)).length()).is_equal(NetProtocol.MAX_NAME)


func test_addresses() -> void:
	assert_dict(NetProtocol.parse_address("192.168.1.5")).is_equal({ "host": "192.168.1.5", "port": 47800 })
	assert_dict(NetProtocol.parse_address(" host.lan:47802 ")).is_equal({ "host": "host.lan", "port": 47802 })
	assert_dict(NetProtocol.parse_address("[::1]:5000")).is_equal({ "host": "::1", "port": 5000 })
	assert_dict(NetProtocol.parse_address("[fe80::1]")).is_equal({ "host": "fe80::1", "port": 47800 })
	assert_dict(NetProtocol.parse_address("")).is_empty()
	assert_dict(NetProtocol.parse_address("a:0")).is_empty()


func test_identity_is_kept_and_signs() -> void:
	var dir := "user://tests/net_core/id_a/"
	DirAccess.remove_absolute(dir.path_join(NetIdentity.KEY_FILE))
	var a := NetIdentity.load_or_create(dir)
	var b := NetIdentity.load_or_create(dir)
	assert_str(a.fingerprint).has_length(64)
	assert_str(b.fingerprint).is_equal(a.fingerprint)
	var perms := FileAccess.get_unix_permissions(ProjectSettings.globalize_path(dir.path_join(NetIdentity.KEY_FILE)))
	assert_int(perms & 0x3F).is_equal(0) # only the owner can read it
	var nonce := NetAuth.nonce()
	var sig := a.sign(nonce)
	assert_bool(NetIdentity.verify(a.public_pem, nonce, sig)).is_true()
	assert_bool(NetIdentity.verify(a.public_pem, NetAuth.nonce(), sig)).is_false()
	var other := NetIdentity.throwaway()
	assert_bool(NetIdentity.verify(other.public_pem, nonce, sig)).is_false()
	assert_bool(NetIdentity.verify("junk", nonce, sig)).is_false()
	assert_str(NetIdentity.short(a.fingerprint)).has_length(19)


func test_password_proofs() -> void:
	var nonce := NetAuth.nonce()
	var proof := NetAuth.password_proof("hunter2", nonce)
	assert_bool(NetAuth.check_password("hunter2", nonce, proof)).is_true()
	assert_bool(NetAuth.check_password("hunter3", nonce, proof)).is_false()
	assert_bool(NetAuth.check_password("hunter2", NetAuth.nonce(), proof)).is_false()
	assert_bool(NetAuth.check_password("hunter2", nonce, PackedByteArray())).is_false()
	assert_bool(NetAuth.check_password("", nonce, PackedByteArray())).is_true()
	assert_bool(proof.hex_encode().contains("hunter2".to_utf8_buffer().hex_encode())).is_false()


func test_example_config_loads() -> void:
	var errors := PackedStringArray()
	var c := ServerConfig.load_file("res://data/server.example.json", errors)
	assert_array(errors).is_empty()
	assert_int(c.port).is_equal(47800)
	assert_int(c.max_players).is_equal(16)
	assert_int(c.rotation.size()).is_equal(2)
	assert_str(c.track_path(0)).is_equal("res://content/tracks/proving_ground/track.json")
	var e := c.event(0)
	assert_str(e.kind).is_equal("race")
	assert_int(e.practice_min).is_equal(5)
	assert_int(e.race_laps).is_equal(5)
	assert_str(e.grid).is_equal("random")
	assert_str(c.event(1).kind).is_equal("free")
	assert_int(c.package_limits().max_zip_bytes).is_equal(50 << 20)


func test_bad_configs_are_refused() -> void:
	var errors := PackedStringArray()
	assert_object(ServerConfig.from_dict({ "schema": "noss.server/1", "max_players": 40 }, errors)).is_null()
	assert_array(errors).is_not_empty()
	errors.clear()
	assert_object(ServerConfig.from_dict({ "schema": "noss.server/1", "rotation": [{ "class": "official.track.gt", "event": { "kind": "time_trial" } }] }, errors)).is_null()
	errors.clear()
	assert_object(ServerConfig.load_file("user://tests/net_core/none.json", errors)).is_null()
	assert_array(errors).is_not_empty()


func test_config_defaults_and_track_paths() -> void:
	var c := ServerConfig.defaults()
	assert_str(c.event(0).kind).is_equal("free")
	c.path = "/srv/noss/server.json"
	c.rotation[0].track = "tracks/my_track.json"
	assert_str(c.track_path(0)).is_equal("/srv/noss/tracks/my_track.json")
	c.rotation[0].track = "/abs/t.json"
	assert_str(c.track_path(0)).is_equal("/abs/t.json")


func test_bans_are_saved_to_the_config_file() -> void:
	var file := "user://tests/net_core/server.json"
	var c := ServerConfig.defaults()
	c.path = file
	c.bans.append("a".repeat(64))
	assert_int(c.save()).is_equal(OK)
	var back := ServerConfig.load_file(file)
	assert_bool(back.is_banned("a".repeat(64))).is_true()
	assert_bool(back.is_allowed("b".repeat(64))).is_true()
	back.whitelist.append("c".repeat(64))
	assert_bool(back.is_allowed("b".repeat(64))).is_false()


func test_command_line() -> void:
	var dev := Game.parse_args(PackedStringArray(["-s", "x.gd", "--config", "server.json", "--server", "--port=47810", "--drive"]),
		PackedStringArray(["--autodrive", "--ai=3"]))
	assert_str(dev.config).is_equal("server.json")
	assert_str(dev.server).is_equal("true")
	assert_str(dev.port).is_equal("47810")
	assert_bool(dev.has("drive")).is_false() # only after "--"
	assert_str(dev.autodrive).is_equal("true")
	assert_str(dev.ai).is_equal("3")
