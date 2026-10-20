extends Node
## Discord Rich Presence (autoload "Discord", docs/DECISIONS.md D186): tells the Discord app on
## this machine what the player is doing, so it shows on their profile.
##
## Presence only. The SDK's Connect() is never called, so there is no Discord login, no token and
## no account handling: the Discord app already running here knows who the user is and publishes
## what we hand it. Invites and lobbies would need the connected path and are not wired up.
##
## It shows the mode and track, whether the game is online or splitscreen with how many players,
## and how long the current race has run. Never the car (imported model names are the player's
## own business) and never the server address. Game settings → Discord status turns it off.

## The nOSS application in the Discord Developer Portal. Public by design, not a secret.
const APP_ID := 1561746945394081832
## The art asset uploaded in the portal (Rich Presence → Art Assets).
const LOGO := "logo"
## Discord rate-limits presence updates, and nothing here changes faster than this.
const PUSH_INTERVAL := 2.0

var _running := false
## When the game started and when the current session did. The elapsed time counts from the
## session while driving, and from the launch everywhere else, so it never flickers on a menu.
var _launched := 0
var _session_start := 0
var _in_session := false
## The last activity pushed, so an unchanged one is not sent again.
var _pushed := {}
var _since_push := PUSH_INTERVAL # push the first one straight away


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_launched = int(Time.get_unix_time_from_system())
	# No presence for a dedicated server or a headless run, and none without the native class.
	if Game.dedicated or Game.headless or not ClassDB.class_exists(&"NossDiscord"):
		return
	_running = NossDiscord.start(APP_ID)
	if _running:
		print("Discord status: %s" % NossDiscord.library_path().get_file())
	else:
		print("Discord status off: %s" % NossDiscord.get_error())


func _exit_tree() -> void:
	if _running:
		NossDiscord.stop()
		_running = false


func _process(delta: float) -> void:
	if not _running:
		return
	NossDiscord.poll()
	_since_push += delta
	if _since_push < PUSH_INTERVAL:
		return
	_since_push = 0.0
	# Turned off mid-game: take the presence down and leave the client loaded for later.
	if not Settings.discord_presence:
		if not _pushed.is_empty():
			_pushed = {}
			NossDiscord.clear_presence()
		return
	var activity := _describe()
	if activity != _pushed:
		_pushed = activity
		NossDiscord.set_presence(activity)


## What to show, read off the current scene so no mode script has to report anything.
func _describe() -> Dictionary:
	var activity := { "large_image": LOGO, "large_text": "nOSS", "start_unix": _launched }
	var session := get_tree().current_scene as TrackSession
	if session == null:
		_in_session = false
		activity["details"] = _screen_name(get_tree().current_scene)
		return activity
	if not _in_session:
		_in_session = true
		_session_start = int(Time.get_unix_time_from_system())
	activity["start_unix"] = _session_start
	# All the session poking lives here, so the two helpers below stay pure and testable.
	var mode_name := String(session.mode.get("name", "")) if session.mode else ""
	var track_name := String(session.track.display_name) if session.track else ""
	activity["details"] = _session_name(mode_name, track_name)
	var online := session.is_online()
	# Online that is everyone on the server; offline, the players sharing this screen.
	var humans := Net.roster.size() if online else session.players.filter(
		func(p: SessionPlayer) -> bool: return not p.slot.ai).size()
	var most := int(Net.lobby.get("max", 16)) if online else Players.MAX
	var party := _party(online, humans, most)
	if not party.is_empty():
		activity.merge(party)
		activity["state"] = "Online" if online else "Splitscreen"
	return activity


## "Highway · Pacific Coast". Endless, sumo and drag build their own world, so there is no track
## to name and the mode stands alone rather than trailing a separator.
static func _session_name(mode_name: String, track_name: String) -> String:
	if mode_name and track_name:
		return "%s · %s" % [mode_name, track_name]
	return mode_name if mode_name else track_name if track_name else "Driving"


## Party size, or {} for one player alone (Discord would show a pointless "1 of 1").
static func _party(online: bool, humans: int, most: int) -> Dictionary:
	if humans < 2 or most < 2:
		return {}
	# The id groups the party on Discord's side; it only has to match for everyone in it.
	return { "party_id": "noss-online" if online else "noss-local",
		"party_size": humans, "party_max": maxi(most, humans) }


func _screen_name(scene: Node) -> String:
	if scene is Garage:
		return "In the Garage"
	if scene is FittingBay:
		return "In the Fitting Bay"
	if scene is TrackEditor:
		return "Editing a track"
	return "In the menus"
