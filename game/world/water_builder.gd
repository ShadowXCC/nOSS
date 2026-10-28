class_name WaterBuilder
extends RefCounted
## A track's water (its `water` list, D224): lakes off the road, each a flat surface at its level
## over a catch volume that sends a car going in back to the road, as a fitted scene's water does
## (an Area3D named Water…, meta noss_water, a direct child of the track: TrackSession._on_water).

## The catch volume reaches this far under the surface, m: deep enough to catch a car.
const DEPTH_M := 6.0
## The surface's texture repeats every this many metres.
const TILE_M := 24.0


static func build(data: TrackData, root: Node3D, visual := true) -> void:
	for i in data.water.size():
		var w: Dictionary = data.water[i]
		var outline: PackedVector2Array = w.outline
		var tris := Geometry2D.triangulate_polygon(outline)
		if tris.is_empty():
			push_warning("Water %s: its outline crosses itself" % w.name)
			continue
		var y := float(w.y)
		if visual:
			var mi := MeshInstance3D.new()
			mi.name = "Lake%d" % i
			mi.mesh = surface(outline, tris, y).mesh()
			mi.material_override = WorldMaterials.water()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		var area := Area3D.new()
		area.name = "Water%d" % i
		area.set_meta(&"noss_water", true)
		area.monitorable = false
		area.collision_layer = 0
		area.collision_mask = Vehicle.LAYER_VEHICLES
		for k in range(0, tris.size(), 3):
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for depth in [0.0, -DEPTH_M]:
				for j in 3:
					var p := outline[tris[k + j]]
					points.append(Vector3(p.x, y + depth, p.y))
			shape.points = points
			var cs := CollisionShape3D.new()
			cs.shape = shape
			area.add_child(cs)
		root.add_child(area)


## The flat surface over `outline` (triangles `tris`) at height `y`, facing up.
static func surface(outline: PackedVector2Array, tris: PackedInt32Array, y: float) -> MeshBatch:
	var b := MeshBatch.new()
	for p in outline:
		b.vertex(Vector3(p.x, y, p.y), Vector3.UP, p / TILE_M)
	for k in range(0, tris.size(), 3):
		var a := Vector3(outline[tris[k]].x, 0.0, outline[tris[k]].y)
		var c := Vector3(outline[tris[k + 1]].x, 0.0, outline[tris[k + 1]].y)
		var d := Vector3(outline[tris[k + 2]].x, 0.0, outline[tris[k + 2]].y)
		# Godot's fronts are clockwise: from above, (c - a) × (d - a) points down for one.
		if (c - a).cross(d - a).y < 0.0:
			b.index.append_array([tris[k], tris[k + 1], tris[k + 2]])
		else:
			b.index.append_array([tris[k], tris[k + 2], tris[k + 1]])
	return b
