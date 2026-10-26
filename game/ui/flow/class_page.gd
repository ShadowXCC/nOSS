class_name ClassPage
extends MenuPage
## Picks the class (docs/UI_FLOW.md §5.6): the type's classes on the left, each "GT   RWD · 380 kW ·
## 1300 kg", named "Track GT" for screen readers; on the right P1's last car on a turntable,
## fitted to the class in focus, or the class's default car when it can't take that one. The fit
## waits until the focus has stayed put for FIT_DELAY. Confirm goes on to the players, or hosting,
## starts the server (its lobby follows), or from the lobby, goes back to it with the event.
##
## Without a flow (the Garage's Drive) it lists every class that takes `car`, shows that car, and
## reports the pick (`picked`).

const FIT_DELAY := 0.15

## The class was picked, on a page without a flow.
signal picked(id: String)

var flow: EventFlow
## Without a flow: the car to drive (a package path).
var car := ""
## The class and car the turntable shows (or would: no models load headless).
var shown_class := ""
var shown_car := ""
var preview: BayPreview
## Hosting: why the server couldn't start.
var status: Label

var _wanted := "" # the class in focus, waiting for the fit
var _timer: Timer
var _packages := {} # car path -> VehiclePackage, each loaded once
var _current: Button


func _ready() -> void:
	title = "Choose class"
	if flow:
		crumbs = flow.crumbs("Class")
		steps = flow.steps()
		step = steps.find("Class")
	else:
		var car_name := String(PackageLoader.read_manifest(car).get("name", ""))
		crumbs = ["Garage", car_name, "Class"]
		back_hint = "Back to " + car_name
	super._ready()


## The classes listed: the flow's, or every one that takes `car`.
func classes() -> Array[PlatformLoader.Result]:
	if flow:
		return flow.classes()
	var family := String(PackageLoader.read_manifest(car).get("family", ""))
	var out: Array[PlatformLoader.Result] = []
	for mode in GameModes.list():
		out.append_array(GameModes.classes(mode).filter(func(r: PlatformLoader.Result) -> bool: return Fitting.compatible(r.platform, family)))
	return out


func _build() -> void:
	var current := flow.class_id if flow else String(Settings.profile.get("last_platform", ""))
	var modes := {}
	for r in classes():
		var mode := GameModes.mode_for(r.platform.id)
		if not modes.has(mode.id):
			modes[mode.id] = [mode, []]
		modes[mode.id][1].append(r)
	for id: String in modes:
		var mode: Dictionary = modes[id][0]
		if modes.size() > 1:
			add_heading(String(mode.name))
		for r: PlatformLoader.Result in modes[id][1]:
			var p := r.platform
			var last: bool = p.id == current
			var info := GameModes.describe(p)
			var b := UiKit.button("", _pick.bind(String(p.id)), info)
			b.name = String(p.id).validate_node_name()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			UiKit.set_shown_text(b, "%s   %s%s" % [p.name, info, "  •" if last else ""])
			b.accessibility_name = "%s %s%s" % [mode.name, p.name, ", last used" if last else ""]
			b.set_meta(&"class_id", String(p.id))
			add_row(b)
			if last:
				_current = b
	if flow and flow.context == "host":
		status = Label.new()
		status.name = "Status"
		status.theme_type_variation = &"PageCrumb"
		status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
		add_footer(status)
	preview = BayPreview.new()
	preview.turntable = true
	set_pane(preview)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = FIT_DELAY
	_timer.timeout.connect(_fit_now)
	add_child(_timer)


## The rows, with the focus on the class used last.
func chain(focus_first := true) -> void:
	super.chain(focus_first and _current == null)
	if focus_first and _current:
		UiKit.focus_later(_current)


func _focused(c: Control) -> void:
	if c and c.has_meta(&"class_id") and is_ancestor_of(c):
		_wanted = String(c.get_meta(&"class_id"))
		_timer.start()


func _pick(id: String) -> void:
	if not flow:
		picked.emit(id)
		return
	flow.class_id = id
	if flow.context == "host":
		status.text = flow.host()
		return
	if flow.context == "change":
		flow.start()
		return
	flow.remember()
	open_over(flow.players_page())


## The car the turntable shows for `platform`: `own` (the Garage's car), else P1's last car if the
## class takes it, else the class's default.
static func car_for(platform: Dictionary, own := "") -> String:
	if own:
		return own
	var last := String(Settings.profile.get("last_car", ""))
	if last and Fitting.compatible(platform, String(PackageLoader.read_manifest(last).get("family", ""))):
		return last
	return GameModes.default_car(platform)


func _fit_now() -> void:
	var r := PlatformLoader.load_official(_wanted)
	if not r.ok():
		return
	shown_class = _wanted
	shown_car = car_for(r.platform, car)
	# Headless (tests) loads no models: a worker's model load there hangs the run.
	if not MeshBatch.threaded() or not pane_shown():
		return
	var pkg: Variant = _packages.get(shown_car)
	if pkg is VehiclePackage:
		preview.show_package(PackageLoader.copy(pkg), r.platform)
	elif pkg == null:
		_packages[shown_car] = "loading"
		# A method, not a lambda: the page may be gone by the time the car is in (garage.gd).
		PackageLoader.load_async(shown_car, _on_car_loaded)


func _on_car_loaded(pkg: VehiclePackage) -> void:
	if not is_inside_tree():
		pkg.free_scenes()
		return
	if not pkg.ok():
		_packages.erase(pkg.path)
		return
	_packages[pkg.path] = pkg
	if pkg.path == shown_car:
		preview.show_package(PackageLoader.copy(pkg), PlatformLoader.load_official(shown_class).platform)


func _exit_tree() -> void:
	super._exit_tree()
	if preview:
		preview.clear()
	for pkg: Variant in _packages.values():
		if pkg is VehiclePackage:
			(pkg as VehiclePackage).free_scenes()
	_packages.clear()
