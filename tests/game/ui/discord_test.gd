extends GdUnitTestSuite
## Discord Rich Presence (D186): the strings it publishes. They go to the player's friends list,
## so what is in them -- and what is deliberately kept out -- is worth pinning down. The native
## side is not exercised here; these are the pure parts that decide what gets sent.


func test_the_mode_and_track_read_as_one_line() -> void:
	assert_str(Discord._session_name("Highway", "Pacific Coast")).is_equal("Highway · Pacific Coast")


## Endless, sumo and drag build their own world, so there is no track file to name and the mode
## has to stand on its own rather than trailing a stray separator.
func test_a_session_without_a_track_names_just_the_mode() -> void:
	assert_str(Discord._session_name("Endless", "")).is_equal("Endless")
	assert_str(Discord._session_name("", "Pacific Coast")).is_equal("Pacific Coast")
	assert_str(Discord._session_name("", "")).is_equal("Driving")


## One player alone is not a party: Discord would render a pointless "1 of 1".
func test_one_player_is_not_a_party() -> void:
	assert_dict(Discord._party(false, 1, Players.MAX)).is_empty()
	assert_dict(Discord._party(true, 1, 16)).is_empty()


func test_a_shared_screen_and_a_server_are_told_apart() -> void:
	var local := Discord._party(false, 3, Players.MAX)
	assert_str(String(local.get("party_id", ""))).is_equal("noss-local")
	assert_int(int(local.get("party_size", 0))).is_equal(3)
	assert_int(int(local.get("party_max", 0))).is_equal(Players.MAX)
	var online := Discord._party(true, 5, 16)
	assert_str(String(online.get("party_id", ""))).is_equal("noss-online")
	assert_int(int(online.get("party_max", 0))).is_equal(16)
	# A server fuller than its stated size still reads sensibly rather than "17 of 16".
	assert_int(int(Discord._party(true, 17, 16).get("party_max", 0))).is_equal(17)


func test_the_menus_are_named_and_carry_the_logo() -> void:
	var activity := Discord._describe()
	assert_str(String(activity.get("details", ""))).is_equal("In the menus")
	assert_str(String(activity.get("large_image", ""))).is_equal(Discord.LOGO)
	assert_int(int(activity.get("start_unix", 0))).is_greater(0)
	# Deliberately absent outside a session: no party, and nothing naming a server.
	assert_bool(activity.has("party_id")).is_false()
	assert_bool(activity.has("state")).is_false()


## A dedicated server or a headless run has no player to speak for, so it never starts. The
## suite itself runs headless, which is what makes this checkable.
func test_a_headless_run_publishes_nothing() -> void:
	assert_bool(Game.headless or Game.dedicated).is_true()
	assert_bool(Discord._running).is_false()
