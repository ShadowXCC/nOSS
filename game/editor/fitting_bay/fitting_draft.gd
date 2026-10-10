class_name FittingDraft
extends RefCounted
## A car being fitted in the Fitting Bay (docs/VEHICLE_PACKAGE.md §7): its model, fit.json,
## paint, sound and credits. It lives as an unpacked package in user://fitting/<id>/ (autosave
## and test drives) until it's packed into the garage with its LODs and thumbnail.

const DIR := "user://fitting/"
const DEFAULT_SOUND := { "car": "v8_crossplane", "open": "flat6", "truck": "v8_crossplane", "moto": "i4" }

var id := ""
var car_name := ""
var author := ""
var license := "Unknown"
var family := "car"
var tags := []
## The file it was imported from (shown, and noted in the manifest).
var source := ""
## model/body.glb, and that model parsed (owned by the draft; the bay previews it).
var glb := PackedByteArray()
var scene: Node3D
var fit := {}
var paint := {}
var sound := {}
var notes := PackedStringArray()
## The scene was changed (wheels split out) and has to be exported again.
var scene_changed := false
## The garage file this draft edits, or "" for a new car.
var edit_path := ""
## An edited package's own LODs ({path: bytes}) and their fit.json settings, kept while its
## model stays the same; and its thumbnail.
var kept_lods := {}
var kept_lod_fit := {}
var kept_thumbnail := PackedByteArray()


## A new car from an imported model, with everything the analysis could work out.
static func from_import(result: ModelImport.Result) -> FittingDraft:
	var d := FittingDraft.new()
	d.id = PackageWriter.new_uuid()
	d.source = result.path.get_file()
	d.car_name = _pretty(result.path.get_file().get_basename())
	d.author = String(Settings.profile.get("name", "Player"))
	d.glb = result.glb
	d.scene = result.scene
	d.notes.append_array(result.notes)
	var analysis := ModelAnalysis.analyze(d.scene)
	d.fit = analysis.fit
	d.paint = analysis.paint
	d.family = analysis.family
	d.scene_changed = analysis.scene_changed
	d.notes.append_array(analysis.notes)
	d.sound = { "schema": "noss.sound/1", "name": "Default", "base": DEFAULT_SOUND.get(d.family, "v8_crossplane") }
	return d


## A draft that edits a car from the garage (or official content, as a copy).
static func from_package(pkg: VehiclePackage) -> FittingDraft:
	var d := FittingDraft.new()
	var m := pkg.manifest
	var official := pkg.path.begins_with("res://")
	d.id = PackageWriter.new_uuid() if official else String(m.id)
	d.edit_path = "" if official else pkg.path
	d.car_name = String(m.name) + (" copy" if official else "")
	d.author = String(m.author)
	d.license = String(m.license)
	d.family = String(m.family)
	d.tags = m.get("tags", []).duplicate()
	d.source = String(m.get("source", ""))
	d.fit = pkg.fit.duplicate(true)
	d.paint = pkg.paint.duplicate(true)
	d.sound = pkg.sound.duplicate(true) if not pkg.sound.is_empty() else { "schema": "noss.sound/1", "name": "Default", "base": DEFAULT_SOUND.get(d.family, "v8_crossplane") }
	var source := PackageSource.open(pkg.path, PackageLoader.DEFAULT_LIMITS)
	if not source.error:
		d.glb = source.read("model/body.glb")
		for rel in source.files():
			if rel.begins_with("model/lod"):
				d.kept_lods[rel] = source.read(rel)
		if source.has("thumb.png"):
			d.kept_thumbnail = source.read("thumb.png")
	source.close()
	d.scene = ModelImport._parse_glb(d.glb, "")
	for key in ["lod_materials", "lod_distances_m"]:
		if d.fit.has(key):
			d.kept_lod_fit[key] = d.fit[key]
	d.fit.erase("lod_materials")
	d.fit.lod_distances_m = [0]
	return d


func info() -> Dictionary:
	return { "id": id, "name": car_name, "author": author, "license": license, "family": family, "tags": tags,
		"source": ("nOSS Fitting Bay from " + source).left(256) if source else "nOSS Fitting Bay" }


## The model as stored: re-exported first if the analysis changed it.
func model_bytes() -> PackedByteArray:
	if scene_changed and scene:
		var bytes := ModelImport.export_glb(scene)
		if not bytes.is_empty():
			glb = bytes
			scene_changed = false
			kept_lods.clear() # they were made from the old model
	return glb


## Every package file. With `lods`, lower LODs are generated (LodBuilder).
func files(lods := false, thumbnail := PackedByteArray()) -> Dictionary:
	var out := {
		"model/body.glb": model_bytes(),
		"paint.json": PackageWriter.canonical_json(paint).to_utf8_buffer(),
		"sound/profile.json": PackageWriter.canonical_json(sound).to_utf8_buffer(),
	}
	var fit_out := fit.duplicate(true)
	if lods and not kept_lods.is_empty():
		out.merge(kept_lods)
		fit_out.merge(kept_lod_fit, true)
	elif lods and scene:
		var env: Dictionary = fit.envelope
		var length := (_vec(env.max) - _vec(env.min))[(_vec(env.max) - _vec(env.min)).max_axis_index()]
		var built := LodBuilder.build(scene, length)
		for i in built.size():
			if not built[i].is_empty():
				out["model/lod%d.glb" % (i + 1)] = built[i]
		if built.size() > 0:
			fit_out.lod_materials = "shared"
			fit_out.lod_distances_m = LodBuilder.DISTANCES.slice(0, built.size() + 1)
	out["fit.json"] = PackageWriter.canonical_json(fit_out).to_utf8_buffer()
	if not thumbnail.is_empty():
		out["thumb.png"] = thumbnail
	elif not kept_thumbnail.is_empty():
		out["thumb.png"] = kept_thumbnail
	return out


func draft_dir() -> String:
	return DIR + id + "/"


## Writes the draft as an unpacked package (no LODs) for autosave and test drives.
func save_draft() -> String:
	var dir := draft_dir()
	if DirAccess.dir_exists_absolute(dir):
		_remove_tree(dir)
	return PackageWriter.write_folder(dir, info(), files())


## Packs the car into the garage. Returns PackageWriter.write()'s result.
func pack(thumbnail := PackedByteArray()) -> Dictionary:
	var path := edit_path if edit_path else PackageWriter.garage_path(car_name, id)
	var result := PackageWriter.write(path, info(), files(true, thumbnail))
	if result.ok:
		edit_path = path
	return result


## Removes the draft's folder (the car is saved, or thrown away).
func delete_draft() -> void:
	if id and DirAccess.dir_exists_absolute(draft_dir()):
		_remove_tree(draft_dir())


func free_scene() -> void:
	if scene:
		scene.free()
		scene = null


static func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


## "sedan-sports" -> "Sedan Sports"
static func _pretty(text: String) -> String:
	var words := text.replace("_", " ").replace("-", " ").split(" ", false)
	return " ".join(Array(words).map(func(w: String) -> String: return w.capitalize())).left(96) if not words.is_empty() else "New car"


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
