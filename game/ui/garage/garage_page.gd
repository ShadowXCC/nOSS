class_name GaragePage
extends MenuPage
## The Garage's first page (docs/UI_FLOW.md §8): My cars | Built-in tabs over a grid of cars, the
## New car card first, and the focused car turning in the pane with its details. Confirm on a car
## opens its page (CarPage); New car and Fitting Bay open the bay. The grid has as many columns
## as fit (3 at text 1.0, 2 with bigger text).
##
## Traffic cars (D222) is a mode of the grid: each card shows whether its car drives in endless
## traffic (a border in the palette's good or bad colour and a tag, or greyed when no traffic type
## takes it), a press switches it, and the bar has All on, All off and Done. Back leaves the mode.

const CARD := Vector2(272, 178)
const CARD_FONT := 26
const GAP := 16
const TABS := ["My cars", "Built-in"]
const MY_CARS := 0
const BUILT_IN := 1
## Traffic cars: the focus ring sits this far outside a card's border.
const RING_OUT := 7

var garage: Garage
## The tab shown; -1 until the page first fills.
var tab := -1
## The shown tab's cars (`cards` are theirs, in order).
var cars: Array[Dictionary] = []
var cards: Array[Button] = []
var new_card: Button
var tab_row: TabRow
var grid: GridContainer
var bay_button: Button
var status: Label
## The picked car's index in `cars`; -1 for the New car card.
var selected := -1
## Traffic cars (D222): on, a card's press switches its car into traffic or out of it.
var traffic_mode := false
var traffic_button: Button
var all_on_button: Button
var all_off_button: Button

## The car last picked on each tab, to come back to.
var _picked := {}
var _details: VBoxContainer
## Traffic cars: the cars some traffic type takes (path -> true), found as the mode comes on.
var _fits := {}


func _ready() -> void:
	title = "Garage"
	crumbs = ["Garage"]
	back_hint = "Back to the main menu"
	prompts = [["tabs", "Tabs"]]
	autofocus = false # the picked card takes it (reload())
	super._ready()


func _build() -> void:
	tab_row = TabRow.new(PackedStringArray(TABS))
	tab_row.changed.connect(func(i: int, on_row: bool) -> void:
		tab = i
		reload("", on_row))
	add_header(tab_row)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	body.add_child(grid) # not a row: the cards link among themselves (_link_grid())
	# The "+" is its picture: a name that differs from the text is read as both ("New car: + New car").
	new_card = _card("New car", _plus())
	new_card.accessibility_description = "Import a model in the Fitting Bay"
	new_card.pressed.connect(garage.open_bay)
	new_card.focus_entered.connect(_select_new)
	grid.add_child(new_card)
	bay_button = add_action(UiKit.button("Fitting Bay", garage.open_bay, "Import and fit your own car"))
	all_on_button = add_action(UiKit.button("All on", _all_traffic.bind(true), "Every car on this tab in traffic"))
	all_off_button = add_action(UiKit.button("All off", _all_traffic.bind(false), "No car on this tab in traffic"))
	traffic_button = add_action(UiKit.button("Traffic cars", func() -> void: set_traffic_mode(not traffic_mode)))
	_show_bar()
	status = _status_line()
	add_footer(status)
	var box := VBoxContainer.new()
	set_pane(box)
	_details = VBoxContainer.new()
	box.add_child(_details)
	garage.lend_preview(self, box)
	grid.columns = 3
	resized.connect(_fit_columns.call_deferred)
	_fit_columns.call_deferred()
	reload(garage.start_car)


## Fills the grid with the shown tab's cars and picks the one at `select_path` (on its tab), else
## the one last picked there, else the first. The focus goes to that card, or with `focus_tabs` to
## the tab row (only while this page shows: under a car's page it's put back when that closes).
func reload(select_path := "", focus_tabs := false) -> void:
	for c in cards:
		c.focus_mode = Control.FOCUS_NONE # a late grab_focus mustn't pick a car off the old list
		c.queue_free()
	cards.clear()
	selected = -1
	garage.reload_cars()
	if select_path:
		tab = BUILT_IN if select_path.begins_with("res://") else MY_CARS
	elif tab < 0: # opening: the player's own cars, when there are any
		tab = MY_CARS if garage.cars.any(func(c: Dictionary) -> bool: return not c.official) else BUILT_IN
	select_path = select_path if select_path else String(_picked.get(tab, ""))
	tab_row.select(tab)
	cars = garage.cars.filter(func(c: Dictionary) -> bool: return c.official == (tab == BUILT_IN))
	var at := 0
	for i in cars.size():
		var car := cars[i]
		var m: Dictionary = car.manifest
		var b := _card(String(m.name), car.thumbnail)
		b.pressed.connect(_press.bind(i))
		b.focus_entered.connect(_select.bind(i))
		grid.add_child(b)
		cards.append(b)
		_style_card(i)
		if car.path == select_path:
			at = i
	_link_grid()
	if cards.is_empty():
		_select_new()
	else:
		_select(at)
	if is_visible_in_tree():
		UiKit.focus_later(tab_row.button() if focus_tabs else _picked_card())


## Opens the page of the car at `path` over the grid, picking it first (on its tab).
func open_car(path: String) -> void:
	var is_it := func(c: Dictionary) -> bool: return c.path == path
	if cars.find_custom(is_it) < 0:
		reload(path)
	var i := cars.find_custom(is_it)
	if i >= 0:
		_open(i)


## A card's picture, once the turntable has rendered one.
func set_thumbnail(path: String, texture: Texture2D) -> void:
	var i := cars.find_custom(func(c: Dictionary) -> bool: return c.path == path)
	if i >= 0:
		cards[i].icon = texture


## Back in Traffic cars leaves the mode, not the Garage.
func _unhandled_input(event: InputEvent) -> void:
	if traffic_mode and event.is_action_pressed("ui_cancel") and scroll().is_visible_in_tree():
		get_viewport().set_input_as_handled()
		set_traffic_mode(false)
		return
	super._unhandled_input(event)


## The tab row, the grid, then the action bar, and round (_link_grid()).
func chain(focus_first := true) -> void:
	super.chain(false)
	_link_grid()
	if focus_first:
		UiKit.focus_later(_picked_card())


## The picked card (back here when the one that had the focus is gone).
func focus_first() -> void:
	_picked_card().grab_focus()


func _picked_card() -> Button:
	if selected >= 0 and selected < cards.size():
		return cards[selected]
	if traffic_mode: # no New car card: the first car, or the bar on a tab with none
		return cards[0] if not cards.is_empty() else all_on_button
	return new_card


## Traffic cars on or off (D222). On, the cards show which cars drive in traffic and the status
## line counts them; off, the focus goes back to the Traffic cars button.
func set_traffic_mode(on: bool) -> void:
	traffic_mode = on
	if on:
		_fits = GarageFiles.traffic_fits(PackedStringArray(garage.cars.map(func(c: Dictionary) -> String: return String(c.path))))
	MenuStack.set_shown(new_card, not on)
	_show_bar()
	for i in cards.size():
		_style_card(i)
	_link_grid()
	status.text = _traffic_count() if on else ""
	if on and selected < 0 and not cards.is_empty():
		_select(0)
	else:
		_show_picked()
	UiKit.focus_later(_picked_card() if on else traffic_button)


## Arrow keys and pads move around the grid. Up from its top row goes to the tabs, down from its
## last row to the bar (Fitting Bay, Traffic cars, Back; in Traffic cars All on, All off, Done),
## then round to the tabs.
func _link_grid() -> void:
	if back_button == null: # still building: chain() comes back here
		return
	var all: Array[Button] = []
	if new_card.visible:
		all.append(new_card)
	all.append_array(cards)
	var tab_button := tab_row.button()
	var bar: Array[Control] = []
	bar.assign([all_on_button, all_off_button, traffic_button] if traffic_mode else [bay_button, traffic_button, back_button])
	var n := grid.columns
	for i in all.size():
		var c := all[i]
		var left := all[i - 1] if i % n > 0 else c
		var right := all[i + 1] if i % n < n - 1 and i + 1 < all.size() else c
		var up: Control = all[i - n] if i >= n else tab_button
		var down: Control = all[i + n] if i + n < all.size() else bar[0]
		c.focus_neighbor_left = c.get_path_to(left)
		c.focus_neighbor_right = c.get_path_to(right)
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_previous = c.get_path_to(all[i - 1] if i > 0 else tab_button)
		c.focus_next = c.get_path_to(all[i + 1] if i + 1 < all.size() else bar[0])
	# Down and Tab go tabs → grid → the bar → tabs; up and Shift+Tab the other way. The grid (null)
	# is come into at its first card and left from its last.
	var ring: Array = [tab_button]
	if not all.is_empty():
		ring.append(null)
	ring.append_array(bar)
	for k in ring.size():
		var c: Control = ring[k]
		if c == null:
			continue
		var before: Control = ring[k - 1] if ring[k - 1] != null else all[-1]
		var after: Control = ring[(k + 1) % ring.size()] if ring[(k + 1) % ring.size()] != null else all[0]
		c.focus_neighbor_top = c.get_path_to(before)
		c.focus_neighbor_bottom = c.get_path_to(after)
		c.focus_previous = c.get_path_to(before)
		c.focus_next = c.get_path_to(after)
	# Left and right along the bar's shown buttons.
	var shown := _actions.get_children().filter(func(c: Node) -> bool: return c is Button and (c as Button).visible)
	for i in shown.size():
		var c: Button = shown[i]
		c.focus_neighbor_left = c.get_path_to(shown[maxi(i - 1, 0)])
		c.focus_neighbor_right = c.get_path_to(shown[mini(i + 1, shown.size() - 1)])
	tab_row.link()


## As many columns as the body has room for, worked out from the page's width as MenuPage lays it
## out (the scroll can't say: it's never narrower than the grid it holds).
func _fit_columns() -> void:
	var room := size.x - 2 * MARGIN
	if size.x >= PANE_MIN_WIDTH: # the pane shows: the body's share of the row
		room = (room - 48) * 0.55
	room = minf(room, BODY_MAX_WIDTH) - 16 - 12 # the frame's sides, the scroll bar
	var n := maxi(1, floori((room + GAP) / (CARD.x + GAP)))
	if n != grid.columns:
		grid.columns = n
		_link_grid()


func _select(i: int) -> void:
	if i == selected and _details.get_child_count() > 0:
		return
	selected = i
	var car := cars[i]
	_picked[tab] = String(car.path)
	_show_picked()
	garage.show_car(String(car.path))


## The picked car's details in the pane; in Traffic cars, whether it drives in traffic too.
func _show_picked() -> void:
	if selected < 0:
		return
	var car := cars[selected]
	var lines := Garage.details(car)
	if traffic_mode:
		lines.append(_traffic_line(car))
	_show_details(String(car.manifest.name), lines)


## The New car card: what it does, and no car on the turntable (in Traffic cars, a tab with none).
func _select_new() -> void:
	selected = -1
	if traffic_mode:
		_show_details("Traffic cars", PackedStringArray(["No cars here"]))
	else:
		_show_details("New car", PackedStringArray(["Import a model in the Fitting Bay"]))
	garage.clear_car()


func _show_details(heading: String, lines: PackedStringArray) -> void:
	for child in _details.get_children():
		child.queue_free()
	_details.add_child(UiKit.label(heading, 34))
	for line in lines:
		var l := UiKit.label(line, 26)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(l)


## A card pressed: its page, or in Traffic cars, its car switched into traffic or out of it.
func _press(i: int) -> void:
	if traffic_mode:
		_switch_traffic(i)
	else:
		_open(i)


func _open(i: int) -> void:
	_select(i)
	var page := CarPage.new()
	page.garage = garage
	page.path = String(cars[i].path)
	open_over(page)


func _card(text: String, icon: Texture2D) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.text = text
	b.clip_text = true
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override(&"font_size", CARD_FONT)
	b.accessibility_name = text
	# Traffic cars' tag, in the top corner over the picture.
	var tag := Label.new()
	tag.name = "Tag"
	tag.visible = false
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.position = Vector2(10, 10)
	tag.add_theme_font_size_override(&"font_size", 20)
	var plate := UiKit._box(Color(UiKit.BACKGROUND, 0.85), UiKit.MUTED, 2, 4)
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	tag.add_theme_stylebox_override(&"normal", plate)
	b.add_child(tag)
	return b


# --- Traffic cars (D222) ------------------------------------------------------------------------


## The bar: Fitting Bay, Traffic cars and Back; in Traffic cars, All on, All off and Done (shown
## and hidden for screen readers too: MenuStack.set_shown).
func _show_bar() -> void:
	MenuStack.set_shown(bay_button, not traffic_mode)
	MenuStack.set_shown(all_on_button, traffic_mode)
	MenuStack.set_shown(all_off_button, traffic_mode)
	if back_button:
		MenuStack.set_shown(back_button, not traffic_mode)
	traffic_button.text = "Done" if traffic_mode else "Traffic cars"
	traffic_button.accessibility_name = traffic_button.text
	traffic_button.accessibility_description = "Back to the cars" if traffic_mode else "Pick which cars drive in traffic"


## "in", "out", or "no fit" (no traffic type takes it as it is).
func _traffic_state(car: Dictionary) -> String:
	if not _fits.has(String(car.path)):
		return "no fit"
	return "in" if GarageFiles.in_traffic(String(car.manifest.get("id", ""))) else "out"


func _traffic_line(car: Dictionary) -> String:
	return { "in": "In traffic", "out": "Out of traffic", "no fit": "Doesn't fit traffic" }[_traffic_state(car)]


## "14 of 20 in traffic": of every car some traffic type takes, on both tabs (traffic takes both).
func _traffic_count() -> String:
	var fit := garage.cars.filter(func(c: Dictionary) -> bool: return _fits.has(String(c.path)))
	var on := fit.filter(func(c: Dictionary) -> bool: return _traffic_state(c) == "in")
	return "%d of %d in traffic" % [on.size(), fit.size()]


func _switch_traffic(i: int) -> void:
	var car := cars[i]
	if _traffic_state(car) == "no fit":
		cards[i].set_pressed_no_signal(false)
		status.text = "Doesn't fit traffic"
		return
	GarageFiles.set_in_traffic(PackedStringArray([String(car.manifest.get("id", ""))]), _traffic_state(car) == "out")
	_style_card(i)
	_show_picked()
	status.text = _traffic_count()


## Every car on the shown tab that traffic takes, in (`on`) or out.
func _all_traffic(on: bool) -> void:
	var ids := PackedStringArray()
	for car in cars:
		if _fits.has(String(car.path)):
			ids.append(String(car.manifest.get("id", "")))
	GarageFiles.set_in_traffic(ids, on)
	for i in cards.size():
		_style_card(i)
	_show_picked()
	status.text = _traffic_count()


## Card `i` as the mode shows it. In Traffic cars: in traffic, a border in the palette's good
## colour and "In traffic"; out, its bad colour and "Out"; no fit, greyed and "Doesn't fit". The
## focus ring sits outside the border. A car that fits is a toggle, so a screen reader says which.
## Out of the mode, the plain card.
func _style_card(i: int) -> void:
	var b := cards[i]
	var car := cars[i]
	var m: Dictionary = car.manifest
	var about := "%s by %s, %s" % [Garage.family_name(m.family), m.author, "built in" if car.official else "your car"]
	var tag := b.get_node(^"Tag") as Label
	for style: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		b.remove_theme_stylebox_override(style)
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		b.remove_theme_color_override(c)
	b.self_modulate = Color.WHITE
	MenuStack.set_shown(tag, traffic_mode)
	if not traffic_mode:
		b.toggle_mode = false
		b.set_pressed_no_signal(false)
		b.accessibility_description = about
		return
	var state := _traffic_state(car)
	var palette := Palette.of(Settings.primary)
	var color: Color = { "in": palette.good, "out": palette.bad, "no fit": UiKit.MUTED }[state]
	tag.text = { "in": "In traffic", "out": "Out", "no fit": "Doesn't fit" }[state]
	tag.add_theme_color_override(&"font_color", color)
	(tag.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color = color
	var fits := state != "no fit"
	var look := UiKit._box(UiKit.BUTTON if fits else UiKit.BUTTON.darkened(0.3), color if fits else Color(0.2, 0.2, 0.22), 4 if fits else 2, 14)
	var lit := look.duplicate() as StyleBoxFlat
	lit.bg_color = look.bg_color.lightened(0.1)
	b.add_theme_stylebox_override(&"normal", look)
	b.add_theme_stylebox_override(&"pressed", look)
	b.add_theme_stylebox_override(&"hover", lit)
	b.add_theme_stylebox_override(&"hover_pressed", lit)
	var ring := UiKit._box(Color(0, 0, 0, 0), UiKit.ACCENT, 4, 14)
	ring.set_expand_margin_all(RING_OUT)
	b.add_theme_stylebox_override(&"focus", ring)
	if not fits:
		b.self_modulate = Color(1, 1, 1, 0.55) # the picture and name, dimmed; not the tag (a child)
		for c: StringName in [&"font_color", &"font_hover_color", &"font_focus_color"]:
			b.add_theme_color_override(c, UiKit.MUTED)
	b.toggle_mode = fits
	b.set_pressed_no_signal(state == "in")
	b.accessibility_description = "%s, %s" % [about, _traffic_line(car).to_lower()]


## A status line under the body, read out when it changes.
static func _status_line() -> Label:
	var l := Label.new()
	l.name = "Status"
	l.theme_type_variation = &"PageCrumb"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	return l


## A "+" in the accent colour, for the New car card's picture.
static func _plus() -> Texture2D:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(40, 16, 16, 64), UiKit.ACCENT)
	image.fill_rect(Rect2i(16, 40, 64, 16), UiKit.ACCENT)
	return ImageTexture.create_from_image(image)
