extends SceneTree
## Builds the Track Fitting test scene (M6, EDT-08) from the Kenney Racing Kit (CC0): a closed
## circuit of the kit's road pieces, a grass ground and some trackside pieces, as one GLB, plus
## its centreline (what a player would click along the road) and the kit's license.
##
##   tools/godot.sh --headless -s res://tools/make_kenney_circuit.gd
##
## The kit isn't in the repository. Get it once (INSTALLED_SOFTWARE.md):
##   https://kenney.nl/media/pages/assets/racing-kit/933b8fd9fd-1677580949/kenney_racing-kit.zip
##   sha256 8a71ea16219315a01d00d5a90c4f6b5c090faddbc56d80ecf727e2b3b853c6c0
## unzipped into .tools/test_models/kenney_racing-kit/.
##
## The kit's pieces are 1-unit tiles. Seen from the piece's own origin, a road enters at
## ENTRY heading -z; a straight leaves `len` units on, a corner of radius r leaves r across and
## r on, heading +x (a right turn). Driven the other way, a corner is a left turn. Pieces are
## placed one after another like a turtle; every exit lands on the same half-unit grid, so the
## circuit closes exactly.

const KIT := "res://.tools/test_models/kenney_racing-kit/Models/GLTF format/"
const OUT := "res://tests/fixtures/tracks/kenney/"
const LICENSE := "res://.tools/test_models/kenney_racing-kit/License.txt"
## Metres per kit unit: the road (0.69 units) comes out 12.4 m wide.
const SCALE := 18.0
## Where a road enters a piece, in the piece's own space.
const ENTRY := Vector3(0.15, 0.0, -0.65)
const ROAD_WIDTH := 0.69
## Pieces whose road isn't in the middle of the tile: how far its middle is off.
const OFF_MIDDLE := { "roadStart": Vector3(0.13, 0, 0) }
## The start line, this far into the roadStart piece.
const START_IN := 1.075
## The circuit: [piece, kind, size]. kind: "s" straight (size: length), "r"/"l" corner (size: radius).
const LAYOUT := [
	["roadStart", "s", 2], ["roadStraightLong", "s", 2], ["roadStraightLong", "s", 2],
	["roadCornerLarger", "r", 2.5], ["roadStraight", "s", 1], ["roadStraightLong", "s", 2],
	["roadCornerLarge", "r", 1.5], ["roadStraight", "s", 1], ["roadCornerLarge", "l", 1.5],
	["roadStraight", "s", 1], ["roadCornerLarge", "r", 1.5],
	["roadStraightLong", "s", 2], ["roadStraightLong", "s", 2], ["roadStraight", "s", 1],
	["roadCornerLarger", "r", 2.5], ["roadStraightLong", "s", 2], ["roadStraightLong", "s", 2], ["roadStraightLong", "s", 2],
	["roadCornerLarger", "r", 2.5], ["roadStraightLong", "s", 2],
]
## Trackside pieces: [piece, x, z (where its middle stands), turn (degrees)], in kit units.
const PROPS := [
	["grandStand", -1.1, -0.8, -90.0], ["grandStand", -1.1, -1.8, -90.0], ["grandStand", -1.1, -2.8, -90.0],
	["grandStandCovered", -1.1, -3.8, -90.0], ["lightPostLarge", 0.85, -1.2, 0.0], ["lightPostLarge", 0.85, -4.2, 0.0],
	["pitsGarage", 1.2, -2.0, 90.0], ["pitsGarage", 1.2, -3.0, 90.0], ["pitsOffice", 1.2, -4.0, 90.0],
	["bannerTowerRed", 5.0, -10.0, 0.0], ["bannerTowerGreen", 6.0, -10.0, 0.0], ["billboard", 12.5, -1.0, 90.0],
	["flagCheckers", -0.8, -1.1, 0.0], ["tent", 4.5, 2.6, 0.0], ["tentClosed", 6.0, 2.6, 0.0],
	["treeLarge", 4.0, -2.0, 0.0], ["treeLarge", 6.5, -1.0, 30.0], ["treeSmall", 5.0, 0.5, 0.0], ["treeSmall", 3.0, -5.5, 0.0],
]

var _cache := {}


func _init() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(KIT)):
		printerr("No kit at %s: see the header of this script." % KIT)
		quit(1)
		return
	var root := Node3D.new()
	root.name = "KenneyCircuit"
	var circuit := Node3D.new()
	circuit.name = "Circuit"
	circuit.scale = Vector3.ONE * SCALE
	root.add_child(circuit)
	var pos := Vector3.ZERO
	var heading := 0.0 # radians about +Y; 0 is -z
	var line: Array[Vector3] = [pos]
	var n := 0
	for item: Array in LAYOUT:
		var piece := _piece(String(item[0]))
		var size := float(item[2])
		var a := ENTRY
		var alpha := 0.0
		var b := ENTRY + Vector3(0, 0, -size)
		var beta := 0.0
		var off: Vector3 = OFF_MIDDLE.get(item[0], Vector3.ZERO)
		a += off
		b += off
		match String(item[1]):
			"r":
				b = ENTRY + Vector3(size, 0, -size)
				beta = -PI / 2.0
			"l":
				a = ENTRY + Vector3(size, 0, -size)
				alpha = PI / 2.0
				b = ENTRY
				beta = PI
		var turn := heading - alpha
		var xf := Transform3D(Basis(Vector3.UP, turn), pos) * Transform3D(Basis(), -a)
		piece.transform = xf
		piece.name = "%s_%02d" % [_snake(String(item[0])), n]
		n += 1
		circuit.add_child(piece)
		# The centreline: arcs every 10 degrees.
		var exit_pos := xf * b
		var exit_heading := turn + beta
		if item[1] == "s":
			line.append(exit_pos)
		else:
			var left: bool = item[1] == "l"
			var right := Vector3(-sin(heading), 0, -cos(heading)).rotated(Vector3.UP, -PI / 2.0)
			var center := pos + right * (-size if left else size)
			var steps := 9
			for k in range(1, steps + 1):
				var t := float(k) / steps * (PI / 2.0) * (1.0 if left else -1.0)
				line.append(center + (pos - center).rotated(Vector3.UP, t))
		pos = exit_pos
		heading = exit_heading
	if pos.length() > 1e-3 or absf(wrapf(heading, -PI, PI)) > 1e-3:
		printerr("The circuit doesn't close: ends at %s heading %.1f°" % [pos, rad_to_deg(heading)])
		quit(1)
		return
	line.pop_back() # the last point is the first
	for p: Array in PROPS:
		var prop := _piece(String(p[0]))
		var middle := _middle(prop)
		prop.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[3]))), Vector3(p[1], 0, p[2])) * Transform3D(Basis(), -middle)
		prop.name = _snake(String(p[0])) + "_%02d" % n
		n += 1
		circuit.add_child(prop)
	circuit.add_child(_ground(line))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_scene(root, state) != OK:
		printerr("Export failed")
		quit(1)
		return
	var glb := doc.generate_buffer(state)
	_write(OUT + "kenney_circuit.glb", glb)
	var points := []
	var length := 0.0
	for i in line.size():
		var p := line[i] * SCALE
		points.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		length += (line[i] - line[(i + 1) % line.size()]).length() * SCALE
	var sidecar := {
		"source": "Kenney Racing Kit 2.0 (CC0), tools/make_kenney_circuit.gd",
		"scale": SCALE, "road_width_m": snappedf(ROAD_WIDTH * SCALE, 0.01), "length_m": snappedf(length, 0.1),
		"start_m": snappedf(START_IN * SCALE, 0.01), "points": points,
	}
	_write(OUT + "centreline.json", (JSON.stringify(sidecar, "  ") + "\n").to_utf8_buffer())
	_write(OUT + "LICENSE.txt", FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(LICENSE)))
	print("kenney_circuit.glb: %d bytes, %d pieces, %d centreline points, %.0f m" % [glb.size(), n, points.size(), length])
	root.free()
	for piece: Node in _cache.values():
		piece.free()
	quit()


## A kit piece, loaded once and copied.
func _piece(name: String) -> Node3D:
	if not _cache.has(name):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(KIT + name + ".glb"), state) != OK:
			printerr("Can't load " + name)
			return Node3D.new()
		_cache[name] = doc.generate_scene(state)
	return (_cache[name] as Node3D).duplicate()


## The middle of a piece's footprint, in its own space.
func _middle(piece: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var a := mi.transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return Vector3(box.get_center().x, 0.0, box.get_center().z)


## A grass plane under the circuit, a little below the road, 4 units past it all round.
func _ground(line: Array[Vector3]) -> MeshInstance3D:
	var box := Rect2(Vector2(line[0].x, line[0].z), Vector2.ZERO)
	for p in line:
		box = box.expand(Vector2(p.x, p.z))
	box = box.grow(4.0)
	var mesh := PlaneMesh.new()
	mesh.size = box.size
	var grass := _material("roadStraight", "grass")
	mesh.material = grass
	var mi := MeshInstance3D.new()
	mi.name = "ground"
	mi.mesh = mesh
	mi.position = Vector3(box.get_center().x, -0.004, box.get_center().y)
	return mi


## A piece's material by name (to share the kit's own colours).
func _material(piece: String, material: String) -> Material:
	var p := _piece(piece)
	for mi: MeshInstance3D in p.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == material:
				p.free()
				return m
	p.free()
	return StandardMaterial3D.new()


static func _snake(name: String) -> String:
	var out := ""
	for c in name:
		out += ("_" + c.to_lower()) if c != c.to_lower() else c
	return out


static func _write(res_path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(res_path), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
