extends GdUnitTestSuite

const TITLE_SCENE := "res://game/ui/title/title_screen.tscn"


func before() -> void:
	Settings.use_folder("user://tests/title_screen")


func after() -> void:
	Settings.use_folder("user://")


## The bottle is the title (D198): screen readers hear its name.
func test_logo_reads_noss() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var logo: TextureRect = runner.find_child("Logo")
	assert_object(logo.texture).is_not_null()
	assert_str(String(logo.accessibility_name)).is_equal("nOSS")


## The logo and tagline on the left half, the buttons on the right, at any text size.
func test_logo_left_buttons_right() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var runner := scene_runner(TITLE_SCENE)
	var screen := runner.scene() as Control
	var logo: TextureRect = runner.find_child("Logo")
	var tagline: Label = runner.find_child("TaglineLabel")
	var scroll: ScrollContainer = runner.find_child("Buttons")
	for text_scale in [1.0, 1.5]:
		root.content_scale_factor = text_scale
		await runner.simulate_frames(6)
		var half := screen.size.x / 2.0
		var area := Rect2(Vector2.ZERO, screen.size)
		assert_float(logo.get_global_rect().end.x).override_failure_message("scale %s: logo past the middle" % text_scale).is_less_equal(half)
		assert_float(logo.size.y).override_failure_message("scale %s: logo too short" % text_scale).is_greater(screen.size.y * 0.7)
		assert_float(tagline.get_global_rect().position.y).is_greater_equal(logo.get_global_rect().end.y)
		assert_float(tagline.get_global_rect().end.x).is_less_equal(half)
		assert_bool(area.encloses(tagline.get_global_rect())).override_failure_message("scale %s: tagline off screen" % text_scale).is_true()
		assert_float(scroll.get_global_rect().position.x).override_failure_message("scale %s: buttons left of the middle" % text_scale).is_greater_equal(half)
	root.content_scale_factor = 1.0
	root.size = old_size


func test_shows_game_version() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var version: Label = runner.find_child("VersionLabel")
	assert_str(version.text).is_equal("v" + ProjectSettings.get_setting("application/config/version"))


func test_local_drive_button_has_focus() -> void:
	var runner := scene_runner(TITLE_SCENE)
	await runner.simulate_frames(2)
	var drive: Button = runner.find_child("LocalDriveButton")
	assert_bool(drive.has_focus()).is_true()


## Local Drive (docs/UI_FLOW.md §5.2) is a page of the event types: each named and described, in
## the focus order, and Back (or cancel) comes back to Local Drive on the main menu.
func test_local_drive_lists_the_types() -> void:
	Settings.profile.last_drive = {} # no Drive again
	var runner := scene_runner(TITLE_SCENE)
	await runner.simulate_frames(2)
	var drive: Button = runner.find_child("LocalDriveButton")
	drive.pressed.emit()
	await runner.simulate_frames(3)
	var page: LocalDrivePage = runner.find_child("LocalDrive")
	assert_object(page).is_not_null()
	assert_str(page.title).is_equal("Local Drive")
	var names: Array = []
	for b: Button in page.body.get_children() + [page.back_button]:
		assert_str(String(b.accessibility_description)).is_not_empty()
		names.append(String(b.accessibility_name))
	assert_array(names).contains_exactly(["Racing", "Endless", "Highway", "Mini Games", "Free Drive", "Back"])
	assert_str(String(page.get_viewport().gui_get_focus_owner().accessibility_name)).is_equal("Racing")
	page.closed.emit()
	await runner.simulate_frames(3)
	assert_bool(drive.has_focus()).is_true()


## The main menu (docs/UI_FLOW.md §3): six buttons in this order, named and described, and down
## goes through them in the order they're shown (Changes.md: focus once went from Garage to
## Fitting Bay, past Track Editor above it). The Fitting Bay is the Garage's now.
func test_buttons_order_names_and_focus() -> void:
	var runner := scene_runner(TITLE_SCENE)
	var names := ["LocalDriveButton", "DriveOnlineButton", "GarageButton", "TrackEditorButton", "SettingsButton", "ExitButton"]
	var texts := ["Local Drive", "Drive Online", "Garage", "Track Editor", "Settings", "Exit Game"]
	var list: VBoxContainer = runner.find_child("List")
	assert_int(list.get_child_count()).is_equal(names.size())
	assert_object(runner.find_child("FittingBayButton")).is_null()
	for i in names.size():
		var b: Button = runner.find_child(names[i])
		assert_str(b.text).is_equal(texts[i])
		assert_str(b.accessibility_name).is_equal(texts[i])
		assert_str(b.accessibility_description).is_not_empty()
		var below := b.get_node(b.focus_neighbor_bottom) as Button
		assert_str(below.name).is_equal(names[(i + 1) % names.size()])
		assert_int(b.get_index()).is_equal(i)


## 480 x 96 buttons with 40 px text, 24 px apart, the group centred up and down beside the logo.
func test_buttons_are_big_and_spaced() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var runner := scene_runner(TITLE_SCENE)
	var screen := runner.scene() as Control
	await runner.simulate_frames(6)
	var buttons: Array = (runner.find_child("List") as VBoxContainer).get_children()
	for b: Button in buttons:
		assert_vector(b.size).override_failure_message("%s is %s" % [b.name, b.size]).is_equal(Vector2(480, 96))
		assert_int(b.get_theme_font_size("font_size")).is_equal(40)
	for i in range(1, buttons.size()):
		var gap: float = (buttons[i] as Button).get_global_rect().position.y - (buttons[i - 1] as Button).get_global_rect().end.y
		assert_float(gap).is_equal_approx(24.0, 0.5)
	var top: float = (buttons[0] as Button).get_global_rect().position.y
	var bottom: float = (buttons[-1] as Button).get_global_rect().end.y
	assert_float(top).override_failure_message("not centred: %s above, %s below" % [top, screen.size.y - bottom]).is_equal_approx(screen.size.y - bottom, 2.0)
	root.size = old_size


## Every button is on screen at text scale 1.0 (Changes.md: Quit was cut off once); with big text
## (1.5) the buttons scroll, and the focused one is always shown.
func test_buttons_stay_on_screen() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var runner := scene_runner(TITLE_SCENE)
	var screen := runner.scene() as Control
	var scroll: ScrollContainer = runner.find_child("Buttons")
	var exit: Button = runner.find_child("ExitButton")
	for text_scale in [1.0, 1.5]:
		root.content_scale_factor = text_scale
		await runner.simulate_frames(6)
		var area := Rect2(Vector2.ZERO, screen.size)
		assert_bool(area.encloses(scroll.get_global_rect())).override_failure_message("scale %s: buttons area off screen" % text_scale).is_true()
		if text_scale == 1.0:
			for b: Button in scroll.find_children("*", "Button", true, false):
				assert_bool(area.encloses(b.get_global_rect())).override_failure_message("%s off screen" % b.name).is_true()
			assert_float(scroll.get_v_scroll_bar().max_value - scroll.size.y).override_failure_message("scale 1.0: the buttons scroll").is_less_equal(0.5)
		exit.grab_focus()
		await runner.simulate_frames(4)
		assert_bool(scroll.get_global_rect().grow(1.0).encloses(exit.get_global_rect())).override_failure_message("scale %s: focused Exit Game not shown" % text_scale).is_true()
	root.content_scale_factor = 1.0
	root.size = old_size
