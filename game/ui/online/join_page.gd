class_name JoinPage
extends TabbedPage
## Join (docs/UI_FLOW.md §7.3, MP-04): the games on this network, or one by its address, and a
## tab for official servers ("Coming soon"). Direct keeps the player's favourites (named by them,
## at the top) and the last servers joined (`Settings.net_favourites`, `net_recent`). A locked
## server asks for its password first (PasswordPage); so does a direct join that turns out to
## need one, which then goes again. Joined, the lobby follows (DriveOnlinePage).

const TABS := ["On your network", "Direct", "Official"]
## Recent servers kept.
const RECENT_MAX := 8

var status: Label

var _scanner: NetDiscovery.Scanner
var _address := ""
var _password := ""
## The join under way: {address, name}; {} when none.
var _joining := {}
var _password_page: PasswordPage


func _ready() -> void:
	title = "Join"
	crumbs = ["Drive Online", "Join"]
	back_hint = "Back to Drive Online"
	tabs = PackedStringArray(TABS)
	tabs_off = { TABS.find("Official"): "Coming soon" }
	_address = Settings.net_address
	_scanner = NetDiscovery.Scanner.new()
	add_child(_scanner)
	super._ready()
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"PageCrumb"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	add_footer(status)
	_scanner.changed.connect(refresh_lan)
	_scanner.start()
	Net.joined.connect(_on_joined)
	Net.disconnected.connect(_on_failed)


func _exit_tree() -> void:
	super._exit_tree()
	Net.joined.disconnect(_on_joined)
	Net.disconnected.disconnect(_on_failed)


func _can_reset(_name: String) -> bool:
	return false


func _build_tab(which: String) -> void:
	match which:
		"On your network":
			_lan_rows()
		"Direct":
			_direct_rows()
		_:
			add_text("Coming soon")


## The servers found on the LAN: "Name   2/16   class, track   (password)".
func _lan_rows() -> void:
	for key: String in _scanner.servers:
		var s: Dictionary = _scanner.servers[key]
		var address := "%s:%d" % [s.ip, s.port]
		var b := UiKit.button("", _pick_lan.bind(key), "%s at %s" % [String(s.state).capitalize(), address])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiKit.set_shown_text(b, "%s   %d/%d   %s, %s%s" % [s.name, s.players, s.max, s["class"], s.track, "   (password)" if s.password else ""])
		b.accessibility_name = "%s, %d of %d players, %s, %s%s" % [s.name, s.players, s.max, s["class"], s.track, ", password" if s.password else ""]
		b.set_meta(&"server", key)
		if s.version != NetProtocol.game_version():
			b.disabled = true
			b.accessibility_description = "Version %s" % s.version
		add_row(b)
	if _rows.is_empty():
		add_text("None found")


## Favourites, recent servers, then an address to type.
func _direct_rows() -> void:
	var favourites := favourites()
	if not favourites.is_empty():
		add_heading("Favourites")
	for f: Dictionary in favourites:
		var edit := UiKit.button("Edit", _edit_favourite.bind(f.address), "Rename or remove " + String(f.name))
		add_row(_server_row(f, edit))
	var recent := recent()
	if not recent.is_empty():
		add_heading("Recent")
	for r: Dictionary in recent:
		var kept := favourites.any(func(f: Dictionary) -> bool: return f.address == r.address)
		var save := UiKit.button("Save", _save_favourite.bind(r), "In your favourites" if kept else "Add %s to your favourites" % r.name)
		save.disabled = kept
		add_row(_server_row(r, save))
	add_row(UiKit.text_field("Address", _address, func(t: String) -> void: _address = t, 80,
		"IP or name, and :port if not 47800", func(_t: String) -> void: join(_address, _password)))
	add_row(UiKit.text_field("Password", _password, func(t: String) -> void: _password = t, 128,
		"Only if the server has one", func(_t: String) -> void: join(_address, _password), true))
	var join_button := UiKit.button("Join", func() -> void: join(_address, _password), "Join the server at this address")
	join_button.name = "JoinAddress"
	add_row(join_button)


## A favourite's or recent server's row: it joins, `side` (Edit or Save) beside it.
func _server_row(s: Dictionary, side: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var b := UiKit.button("", join.bind(String(s.address), "", String(s.name)), "Join this server")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.set_shown_text(b, "%s   %s" % [s.name, s.address])
	b.accessibility_name = "%s, %s" % [s.name, s.address]
	b.set_meta(&"address", s.address)
	row.add_child(b)
	side.custom_minimum_size.x = 200
	row.add_child(side)
	return row


## The rows top to bottom; a row's Edit or Save is right of it, up and down going where the row does.
func chain(focus_first := true) -> void:
	super.chain(focus_first)
	for row: Control in _rows:
		if row is HBoxContainer and row.get_child_count() == 2 and row.get_child(1) is Button:
			var b := row.get_child(0) as Button
			var side := row.get_child(1) as Button
			b.focus_neighbor_right = b.get_path_to(side)
			side.focus_neighbor_left = side.get_path_to(b)
			side.focus_neighbor_right = side.get_path_to(side)
			# Siblings: the row's paths lead from the side button to the same places.
			side.focus_neighbor_top = b.focus_neighbor_top
			side.focus_neighbor_bottom = b.focus_neighbor_bottom
			side.focus_previous = side.get_path_to(b)
			side.focus_next = b.focus_next


## No rows (nothing on the network yet): the tab row, so LB/RB and left/right are right there.
func _first_row() -> Control:
	for c: Control in _rows:
		var t := UiKit._focus_target(c)
		if t and t.is_visible_in_tree():
			return t
	return tab_row.button() if tab_row and tab_row.button() else back_button


## The LAN list changed: its rows again, the focus staying on the server it was on (or where it
## was off the list). Not while a page is over this one: then when it closes.
func refresh_lan() -> void:
	if tab_name() != "On your network" or not scroll().is_visible_in_tree():
		return
	var focus := UiKit.focus_owner(self)
	var key := String(focus.get_meta(&"server", "")) if focus else ""
	var on_rows := focus != null and body.is_ancestor_of(focus)
	var id := focus.get_instance_id() if focus else 0
	rebuild_rows(_fill, func() -> Control:
		if not on_rows:
			return instance_from_id(id) as Control if id else null
		for c: Control in _rows:
			if c.get_meta(&"server", "") == key:
				return c
		return null)


func _pick_lan(key: String) -> void:
	var s: Dictionary = _scanner.servers.get(key, {})
	if s.is_empty():
		return
	var address := "%s:%d" % [s.ip, s.port]
	if s.password:
		ask_password(String(s.name), address)
	else:
		join(address, "", String(s.name))


## Joins the server at `address` ("" `server_name`: it's named by its address until it answers).
func join(address: String, password := "", server_name := "") -> void:
	var at := NetProtocol.parse_address(address)
	if at.is_empty():
		say("Enter an address")
		return
	address = address.strip_edges()
	Settings.set_value("net_address", address)
	_joining = { "address": address, "name": server_name }
	say("Joining %s" % address)
	if Net.join(at.host, at.port, Net.local_players(), password) != OK:
		_joining = {}
		say("Can't reach %s" % address)


## A line under the rows, or on the password page while it's up.
func say(text: String) -> void:
	if is_instance_valid(_password_page) and _password_page.is_inside_tree():
		_password_page.status.text = text
	elif status:
		status.text = text


## The password page for `server_name` at `address`; its Join tries again with what's typed.
func ask_password(server_name: String, address: String) -> PasswordPage:
	_password_page = PasswordPage.new()
	_password_page.server_name = server_name
	_password_page.submitted.connect(func(password: String) -> void: join(address, password, server_name))
	open_over(_password_page, func() -> void:
		_password_page = null
		refresh_lan())
	return _password_page


func _on_joined() -> void:
	if _joining.is_empty():
		return
	var server_name := Net.client.server_name if Net.client and Net.client.server_name else String(_joining.name)
	remember_recent(server_name if server_name else String(_joining.address), String(_joining.address))
	_joining = {}
	say("")


func _on_failed(reason: String) -> void:
	if _joining.is_empty():
		return
	var was := _joining
	_joining = {}
	if reason == "Password needed" and not is_instance_valid(_password_page):
		say("")
		ask_password(String(was.name) if was.name else String(was.address), String(was.address))
		return
	say(reason)


func _save_favourite(r: Dictionary) -> void:
	var list := favourites()
	list.append({ "name": String(r.name), "address": String(r.address) })
	Settings.set_value("net_favourites", list)
	show_tab(tab, String(r.name) + ",")


## A favourite's page: its name and address, and Remove.
func _edit_favourite(address: String) -> void:
	var list := favourites()
	var at := list.find_custom(func(f: Dictionary) -> bool: return f.address == address)
	if at < 0:
		return
	var page := FavouritePage.new()
	page.favourite = list[at].duplicate()
	page.crumbs = crumbs + PackedStringArray([String(list[at].name)])
	var removed := [false]
	page.removed.connect(func() -> void:
		removed[0] = true
		page.closed.emit())
	open_over(page, func() -> void:
		var now := favourites()
		var i := now.find_custom(func(f: Dictionary) -> bool: return f.address == address)
		if i >= 0:
			if removed[0]:
				now.remove_at(i)
			else:
				now[i] = page.favourite
			Settings.set_value("net_favourites", now)
		show_tab(tab, "" if removed[0] else String(page.favourite.name) + ","))


## The favourites, each {name, address} (anything else in the settings file left out).
static func favourites() -> Array[Dictionary]:
	return _servers(Settings.net_favourites)


## The servers joined last, newest first.
static func recent() -> Array[Dictionary]:
	return _servers(Settings.net_recent)


static func _servers(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for d: Variant in v:
			if d is Dictionary and d.get("address") is String and not NetProtocol.parse_address(d.address).is_empty():
				out.append({ "name": String(d.get("name", d.address)).left(48), "address": String(d.address) })
	return out


## `address` joined as `server_name`: first in the recent list, which keeps RECENT_MAX.
static func remember_recent(server_name: String, address: String) -> void:
	var list := recent().filter(func(r: Dictionary) -> bool: return r.address != address)
	list.push_front({ "name": server_name.left(48), "address": address })
	Settings.set_value("net_recent", list.slice(0, RECENT_MAX))


## A favourite (docs/UI_FLOW.md §7.3): "Name" and "Address" as typed, "Remove", and Back keeps
## them.
class FavouritePage:
	extends MenuPage

	signal removed

	## {name, address}: changed as they're typed.
	var favourite := {}

	func _init() -> void:
		back_hint = "Back to Join"

	func _ready() -> void:
		title = String(favourite.name)
		super._ready()

	func _build() -> void:
		add_row(UiKit.text_field("Name", String(favourite.name), func(t: String) -> void:
			if t.strip_edges():
				favourite.name = t.strip_edges().left(48), 48, "What it's called here"))
		add_row(UiKit.text_field("Address", String(favourite.address), func(t: String) -> void:
			if not NetProtocol.parse_address(t).is_empty():
				favourite.address = t.strip_edges(), 80, "IP or name, and :port if not 47800"))
		var remove := UiKit.button("Remove", func() -> void: removed.emit(), "Take it off your favourites")
		remove.name = "Remove"
		add_row(remove)
