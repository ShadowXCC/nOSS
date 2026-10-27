class_name CupBuilderPage
extends MenuPage
## Makes or changes a cup (D145, docs/UI_FLOW.md §6.1): its name, four tracks (any circuit) and the
## laps of each, saved to user://cups/ ("Save", in the action bar). The built-in cups can't be
## changed here. Its opener sets the crumbs and closes it once it's saved.

## The cup was saved (its file).
signal saved(path: String)

## The cup being made ({} for a new one).
var cup := {}
var status: Label


func _init() -> void:
	back_hint = "Without saving"


func _ready() -> void:
	title = "Cup builder"
	super._ready()


func _build() -> void:
	if cup.is_empty():
		cup = { "schema": CupRun.SCHEMA, "id": "", "name": "My cup", "races": [] }
	var tracks := TrackLibrary.list(true, true, "circuit")
	var races: Array = cup.races
	while races.size() < 4:
		races.append({ "track": String(tracks[races.size() % maxi(tracks.size(), 1)].id) if not tracks.is_empty() else "", "laps": 3 })
	add_row(UiKit.text_field("Name", String(cup.name), func(t: String) -> void: cup.name = t.strip_edges(), 40))
	# By id (it survives the track being changed), or by its content when the id won't do.
	var plain := RegEx.create_from_string("^[a-z0-9_]{1,64}$")
	var choices := tracks.map(func(e: Dictionary) -> Array:
		return [String(e.id) if plain.search(String(e.id)) else String(e.hash), TrackLibrary.label(e, Settings.units == "imperial")])
	for i in 4:
		var race: Dictionary = races[i]
		var known := choices.any(func(c: Array) -> bool: return c[0] == race.track)
		var these := choices if known else [[String(race.track), "Track missing"]] + choices
		add_row(UiKit.spinner("Race %d" % (i + 1), these, String(race.track), func(v: String) -> void: race.track = v))
		add_row(UiKit.spinner("Race %d laps" % (i + 1), EventForms.numbers(1, 10), clampi(int(race.laps), 1, 10),
			func(v: int) -> void: race.laps = v))
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	var save := UiKit.button("Save", _save, "Keep it in your cups")
	save.name = "Save"
	add_action(save)


func _save() -> void:
	var why := CupRun.save(cup)
	if why:
		status.text = why
		return
	saved.emit(CupRun.user_dir + String(cup.id) + ".cup.json")
