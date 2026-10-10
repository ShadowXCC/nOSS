class_name VehiclePackage
extends RefCounted
## A loaded, validated .noss package: its data files plus the generated model scenes.

var path := ""
## SHA-256 of manifest.json; identifies the whole package (docs/VEHICLE_PACKAGE.md §2).
var hash := ""
var manifest := {}
var fit := {}
var paint := {}
var sound := {}
## Generated glTF scenes, LOD0 first. Not in the tree; CarVisual takes ownership.
var lods: Array[Node3D] = []
var triangles := 0
var load_ms := 0
var error := ""


func ok() -> bool:
	return error.is_empty()


func display_name() -> String:
	return manifest.get("name", path.get_file())


## Frees the model scenes if nobody took them.
func free_scenes() -> void:
	for lod in lods:
		if is_instance_valid(lod) and lod.get_parent() == null:
			lod.free()
	lods.clear()
