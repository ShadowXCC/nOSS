extends Node
## Game flow (autoload "Game"): title, sessions, quitting. Also reads dev options passed
## after "--" on the command line:
##   --drive              start free-drive right away
##   --car=<path>         car package for --drive
##   --platform=<id>      platform class for --drive, e.g. official.highway.street
##   --autodrive          let the line follower drive (tests, screenshots)
##   --camera=<mode>      chase_near, chase_far or cockpit
##   --shot=<file.png>    save a screenshot at --shot-at=<s> (default 5)
##   --quit-at=<s>        quit after this many seconds

const TITLE := "res://game/ui/title/title_screen.tscn"

var dev := {}
var _time := 0.0
var _shot_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			dev[kv[0]] = kv[1] if kv.size() > 1 else "true"


## First scene after boot.
func first_scene() -> String:
	return "" if dev.has("drive") else TITLE


func start_free_drive(car_path := "", platform_id := "") -> void:
	get_tree().paused = false
	var session := FreeDrive.new()
	session.car_path = car_path if car_path else String(dev.get("car", ""))
	session.platform_id = platform_id if platform_id else String(dev.get("platform", Settings.profile.get("last_platform", "")))
	session.autodrive = dev.has("autodrive")
	if dev.has("camera"):
		Settings.profile.camera = dev.camera
	get_tree().change_scene_to_node(session)


func go_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE)


func quit() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	_time += delta
	if dev.has("shot") and not _shot_done and _time >= float(dev.get("shot-at", "5")):
		_shot_done = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(dev.shot)
		print("Screenshot: ", dev.shot)
	if dev.has("quit-at") and _time >= float(dev["quit-at"]):
		get_tree().quit()
