extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _drive_button: Button = %FreeDriveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

var _classes: ClassPicker
var _players: PlayersMenu
var _settings: SettingsMenu
var _event: EventMenu
## What the class picker leads to: "free", "race" or "time_trial".
var _mode := "free"


func _ready() -> void:
	theme = UiKit.theme()
	_apply_text_scale()
	Settings.changed.connect(_apply_text_scale)
	Players.slots_changed.connect(_apply_text_scale)
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	_drive_button.accessibility_description = "Drive the Proving Ground"
	_drive_button.pressed.connect(_open_classes.bind("free"))
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(get_tree().quit)
	var bay_button := Button.new()
	bay_button.name = "FittingBayButton"
	bay_button.text = "Fitting Bay"
	bay_button.accessibility_description = "Import your own car"
	bay_button.custom_minimum_size = _drive_button.custom_minimum_size
	bay_button.pressed.connect(func() -> void: Game.open_fitting_bay())
	_drive_button.add_sibling(bay_button)
	var garage_button := Button.new()
	garage_button.name = "GarageButton"
	garage_button.text = "Garage"
	garage_button.accessibility_description = "Your cars"
	garage_button.custom_minimum_size = _drive_button.custom_minimum_size
	garage_button.pressed.connect(func() -> void: Game.open_garage())
	_drive_button.add_sibling(garage_button)
	var trial_button := Button.new()
	trial_button.name = "TimeTrialButton"
	trial_button.text = "Time Trial"
	trial_button.accessibility_description = "Solo laps against your ghost"
	trial_button.custom_minimum_size = _drive_button.custom_minimum_size
	trial_button.pressed.connect(_open_classes.bind("time_trial"))
	_drive_button.add_sibling(trial_button)
	var race_button := Button.new()
	race_button.name = "RaceButton"
	race_button.text = "Race"
	race_button.accessibility_description = "Practice, qualifying and a race against AI"
	race_button.custom_minimum_size = _drive_button.custom_minimum_size
	race_button.pressed.connect(_open_classes.bind("race"))
	_drive_button.add_sibling(race_button)
	var order := [_drive_button, race_button, trial_button, garage_button, bay_button, _settings_button, _quit_button]
	for b: Button in order:
		b.accessibility_name = b.text
	UiKit.chain_focus(order)
	# First boot: the accessibility screen comes before anything else (ACC-09).
	if (not Settings.first_boot_done and DisplayServer.get_name() != "headless") or Game.dev.get("menu", "") == "access":
		var first := FirstBootMenu.new()
		first.done.connect(func() -> void:
			first.queue_free()
			_drive_button.grab_focus())
		add_child(first)
		return
	match Game.dev.get("menu", ""): # dev: open a menu directly
		"classes": _open_classes("free")
		"event": _open_event(String(Settings.profile.get("last_platform", "official.track.gt")))
		"players": _open_players(String(Settings.profile.get("last_platform", "official.track.gt")))
		"settings": _open_settings()


## Free Drive: class first (how it drives), then the players, who each pick a car (how it looks).
## Race: class, then the event, then the players. Time Trial: class, then P1 drives.
func _open_classes(mode: String) -> void:
	_mode = mode
	_classes = ClassPicker.new()
	_classes.current = String(Settings.profile.get("last_platform", ""))
	if mode != "free":
		_classes.mode_filter = "track"
	_classes.picked.connect(_on_class_picked)
	_classes.closed.connect(func() -> void:
		_classes.queue_free()
		_drive_button.grab_focus())
	add_child(_classes)


func _on_class_picked(id: String) -> void:
	_classes.visible = false
	if _mode == "race":
		_open_event(id)
	elif _mode == "time_trial":
		Settings.profile.last_platform = id
		Game.start_event(RaceEvent.time_trial(), id)
	else:
		_open_players(id)


func _open_event(platform_id: String) -> void:
	_event = EventMenu.new()
	_event.picked.connect(func(e: RaceEvent) -> void:
		_event.visible = false
		_open_players(platform_id, e))
	_event.closed.connect(func() -> void:
		_event.queue_free()
		if is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_drive_button.grab_focus())
	add_child(_event)


func _open_players(platform_id: String, event: RaceEvent = null) -> void:
	_players = PlayersMenu.new()
	_players.platform_id = platform_id
	_players.started.connect(func() -> void:
		if event:
			Game.start_event(event, platform_id)
		else:
			Game.start_free_drive("", platform_id, false, false))
	_players.closed.connect(func() -> void:
		_players.queue_free()
		if is_instance_valid(_event):
			_event.visible = true
			_event.grab_focus_first()
		elif is_instance_valid(_classes):
			_classes.visible = true
			_classes.grab_focus_first()
		else:
			_drive_button.grab_focus())
	add_child(_players)


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_settings_button.grab_focus())
	add_child(_settings)


## Menu text size (docs/ACCESSIBILITY.md §2): the whole menu screen scales.
func _apply_text_scale() -> void:
	get_tree().root.content_scale_factor = Players.menu_text_scale()
	theme = UiKit.theme()


func _exit_tree() -> void:
	get_tree().root.content_scale_factor = 1.0
