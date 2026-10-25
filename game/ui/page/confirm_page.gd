class_name ConfirmPage
extends MenuPage
## A second press before something that can't be taken back (docs/UI_FLOW.md §4): the title is
## the question, the safe answer comes first and has the focus, and cancel is the safe answer too.

signal confirmed

var no_text := "Keep going"
var no_hint := ""
var yes_text := "Yes"
var yes_hint := ""
## A line under the question, saying what goes ("Custom buttons and keys go too.").
var detail := ""


func _init() -> void:
	back_text = "" # "no" is the way back


func _build() -> void:
	if detail:
		add_text(detail)
	var no := UiKit.button(no_text, func() -> void: closed.emit(), no_hint)
	no.name = "No"
	add_row(no)
	var yes := UiKit.button(yes_text, func() -> void: confirmed.emit(), yes_hint)
	yes.name = "Yes"
	add_row(yes)
