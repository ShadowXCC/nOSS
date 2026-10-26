class_name GaragePage
extends MenuPage
## The Garage's first page (docs/UI_FLOW.md §8): My cars | Built-in tabs over a grid of cars, the
## New car card first, and the focused car turning in the pane with its details. Confirm on a car
## opens its page (CarPage); New car and Fitting Bay open the bay. The grid has as many columns
## as fit (3 at text 1.0, 2 with bigger text).

const CARD := Vector2(272, 178)
const CARD_FONT := 26
const GAP := 16
const TABS := ["My cars", "Built-in"]
const MY_CARS := 0
const BUILT_IN := 1

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

## The car last picked on each tab, to come back to.
var _picked := {}
var _details: VBoxContainer


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
		b.accessibility_description = "%s by %s, %s" % [Garage.family_name(m.family), m.author, "built in" if car.official else "your car"]
		b.pressed.connect(_open.bind(i))
		b.focus_entered.connect(_select.bind(i))
		grid.add_child(b)
		cards.append(b)
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


## The tab row, the grid, then the action bar (Fitting Bay, Back), and round.
func chain(focus_first := true) -> void:
	super.chain(false)
	_link_grid()
	if focus_first:
		UiKit.focus_later(_picked_card())


## The picked card (back here when the one that had the focus is gone).
func focus_first() -> void:
	_picked_card().grab_focus()


func _picked_card() -> Button:
	return cards[selected] if selected >= 0 and selected < cards.size() else new_card


## Arrow keys and pads move around the grid. Up from its top row goes to the tabs, down from its
## last row to Fitting Bay, then Back, then round to the tabs.
func _link_grid() -> void:
	if back_button == null: # still building: chain() comes back here
		return
	var all: Array[Button] = [new_card]
	all.append_array(cards)
	var tab_button := tab_row.button()
	var n := grid.columns
	for i in all.size():
		var c := all[i]
		var left := all[i - 1] if i % n > 0 else c
		var right := all[i + 1] if i % n < n - 1 and i + 1 < all.size() else c
		var up: Control = all[i - n] if i >= n else tab_button
		var down: Control = all[i + n] if i + n < all.size() else bay_button
		c.focus_neighbor_left = c.get_path_to(left)
		c.focus_neighbor_right = c.get_path_to(right)
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_previous = c.get_path_to(all[i - 1] if i > 0 else tab_button)
		c.focus_next = c.get_path_to(all[i + 1] if i + 1 < all.size() else bay_button)
	# Down and Tab go tabs → grid → Fitting Bay → Back → tabs; up and Shift+Tab the other way.
	var ring: Array[Control] = [tab_button, all[0], bay_button, back_button]
	for k in [0, 2, 3]:
		var c := ring[k]
		var before := all[-1] if k == 2 else ring[(k + 3) % 4]
		var after := ring[(k + 1) % 4]
		c.focus_neighbor_top = c.get_path_to(before)
		c.focus_neighbor_bottom = c.get_path_to(after)
		c.focus_previous = c.get_path_to(before)
		c.focus_next = c.get_path_to(after)
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
	_show_details(String(car.manifest.name), Garage.details(car))
	garage.show_car(String(car.path))


## The New car card: what it does, and no car on the turntable.
func _select_new() -> void:
	selected = -1
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
	return b


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
