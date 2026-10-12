class_name TrackPackage
extends RefCounted
## A loaded track (TrackLoader): its manifest and content hash, the sampled track, its terrain,
## and the files the editor and the network work with.

var path := ""
## sha256 of manifest.json ("" for a bare track.json).
var hash := ""
var manifest := {}
## track.json as noss.track/1.
var layout := {}
var track: TrackData
var terrain: TerrainData
## A track made from a 3D scene: the scene and its tags (Track Fitting).
var scene: SceneTrack
var thumb := PackedByteArray()
var minimap := PackedByteArray()
var error := ""
var load_ms := 0.0


func ok() -> bool:
	return error.is_empty() and track != null


func display_name() -> String:
	return String(manifest.get("name", track.display_name if track else path.get_file()))


func builtin() -> bool:
	return path.begins_with("res://")
