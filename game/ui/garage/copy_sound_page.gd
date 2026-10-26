class_name CopySoundPage
extends MenuPage
## Gives another of the player's cars this car's sounds (docs/UI_FLOW.md §8): their engine and
## tire profiles and own recordings. Built-in cars can't take them.

var garage: Garage
## The car whose sounds go (a package path), and its name.
var path := ""
var car_name := ""


func _ready() -> void:
	title = "Copy sound to"
	crumbs = ["Garage", car_name, "Copy sound to"]
	back_hint = "Without copying"
	super._ready()


func _build() -> void:
	var none := true
	for car in garage.cars:
		if car.official or car.path == path:
			continue
		none = false
		var other := String(car.manifest.name)
		add_row(UiKit.button(other, _copy.bind(String(car.path), other), "Give it the sounds of " + car_name))
	if none:
		add_text("No other cars in the garage")
	var box := VBoxContainer.new()
	set_pane(box)
	garage.lend_preview(self, box)


func _copy(to: String, to_name: String) -> void:
	var result := GarageFiles.copy_sound(path, to)
	garage.grid.reload(path) # the other car's version went up
	closed.emit()
	garage.say("Sound copied to %s" % to_name if result.ok else String(result.error))
