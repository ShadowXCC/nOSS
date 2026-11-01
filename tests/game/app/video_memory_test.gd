extends GdUnitTestSuite
## Settings › Video memory (D247): the video memory garage traffic loads cars up to. Auto is a
## share of the card (D246's 3.5 GB when the card's unknown), a size is that many GB, No limit is
## none; the row's choices; a saved value it doesn't know reads as Auto.

const DIR := "user://tests/video_memory"
const GB := 1 << 30


func before() -> void:
	Settings.use_folder(DIR)
	Settings.reset_keys(Settings.MACHINE.keys()) # not this machine's own


func after() -> void:
	Settings.card_bytes = -1
	Settings.use_folder("user://")


func after_test() -> void:
	Settings.card_bytes = -1
	Settings.reset_keys(["video_memory"])


func test_the_limit() -> void:
	assert_str(Settings.video_memory).is_equal("auto")
	Settings.card_bytes = 10 * GB
	assert_float(Settings.video_limit()).is_equal(7.5 * GB)
	Settings.card_bytes = 0
	assert_float(Settings.video_limit()).is_equal(float(3584 << 20))
	Settings.set_value("video_memory", "6")
	assert_float(Settings.video_limit()).is_equal(6.0 * GB)
	Settings.set_value("video_memory", "unlimited")
	assert_bool(is_inf(Settings.video_limit())).is_true()


## Headless there's no card to ask: unknown.
func test_headless_the_card_is_unknown() -> void:
	assert_int(Settings.card_memory()).is_equal(0)


func test_the_choices() -> void:
	Settings.card_bytes = 10 * GB
	var choices := Settings.video_choices()
	assert_array(choices.map(func(c: Array) -> String: return c[0])).is_equal(["auto", "2", "3", "4", "5", "6", "8", "10", "12",
		"16", "24", "unlimited"])
	assert_array(choices.map(func(c: Array) -> String: return c[1])).is_equal(["Auto (7.5 GB)", "2 GB", "3 GB", "4 GB", "5 GB",
		"6 GB", "8 GB", "10 GB", "12 GB", "16 GB", "24 GB", "No limit"])
	for card: Array in [[6 * GB, "Auto (4.5 GB)"], [8 * GB, "Auto (6 GB)"], [3 * GB, "Auto (2.3 GB)"], [0, "Auto (3.5 GB)"]]:
		Settings.card_bytes = card[0]
		assert_str(String(Settings.video_choices()[0][1])).is_equal(card[1])


func test_saved_and_read_back() -> void:
	Settings.set_value("video_memory", "12")
	Settings.load_all()
	assert_str(Settings.video_memory).is_equal("12")
	var cfg := ConfigFile.new()
	cfg.load(Settings.settings_path)
	assert_str(String(cfg.get_value("graphics", "video_memory"))).is_equal("12")
	for bad: String in ["7", "huge"]:
		cfg.set_value("graphics", "video_memory", bad)
		cfg.save(Settings.settings_path)
		Settings.load_all()
		assert_str(Settings.video_memory).is_equal("auto")
