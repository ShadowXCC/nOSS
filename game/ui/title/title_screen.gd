extends Control
## Title screen.

@onready var _version_label: Label = %VersionLabel
@onready var _drive_button: Button = %FreeDriveButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

var _classes: ClassPicker
var _players: PlayersMenu
var _settings: SettingsMenu


func _ready() -> void:
	theme = UiKit.theme()
	_apply_text_scale()
	Settings.changed.connect(_apply_text_scale)
	Players.slots_changed.connect(_apply_text_scale)
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	_drive_button.accessibility_description = "Drive the Proving Ground"
	_drive_button.pressed.connect(_open_classes)
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
	for b: Button in [_drive_button, garage_button, bay_button, _settings_button, _quit_button]:
		b.accessibility_name = b.text
	UiKit.chain_focus([_drive_button, garage_button, bay_button, _settings_button, _quit_button])
	match Game.dev.get("menu", ""): # dev: open a menu directly
		"classes": _open_classes()
		"players": _open_players(String(Settings.profile.get("last_platform", "official.track.gt")))
		"settings": _open_settings()


## Free Drive: class first (how it drives), then the players, who each pick a car (how it looks).
func _open_classes() -> void:
	_classes = ClassPicker.new()
	_classes.current = String(Settings.profile.get("last_platform", ""))
	_classes.picked.connect(func(id: String) -> void:
		_classes.visible = false
		_open_players(id))
	_classes.closed.connect(func() -> void:
		_classes.queue_free()
		_drive_button.grab_focus())
	add_child(_classes)


func _open_players(platform_id: String) -> void:
	_players = PlayersMenu.new()
	_players.platform_id = platform_id
	_players.started.connect(func() -> void: Game.start_free_drive("", platform_id, false, false))
	_players.closed.connect(func() -> void:
		_players.queue_free()
		if is_instance_valid(_classes):
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
