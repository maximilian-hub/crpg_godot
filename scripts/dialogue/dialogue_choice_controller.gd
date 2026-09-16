extends RefCounted
class_name DialogueChoiceController

signal selection_changed(selected_index: int)
signal choice_confirmed(selected_index: int, text: String, target: String)
signal cancel_requested
signal sound_requested(cue: StringName)

const CUE_NAVIGATE := &"navigate"
const CUE_CONFIRM := &"confirm"
const CUE_CANCEL := &"cancel"

var choices: Array = []
var selected_index := -1
var page_complete := false


func start(new_choices: Array) -> void:
	choices = new_choices.duplicate()
	selected_index = 0 if not choices.is_empty() else -1
	page_complete = false
	selection_changed.emit(selected_index)


func set_page_complete(value: bool) -> void:
	page_complete = value


func is_active() -> bool:
	return page_complete and not choices.is_empty()


func move(direction: int) -> bool:
	if not is_active() or choices.size() <= 1 or direction == 0:
		return false
	selected_index = posmod(selected_index + signi(direction), choices.size())
	selection_changed.emit(selected_index)
	sound_requested.emit(CUE_NAVIGATE)
	return true


func confirm() -> bool:
	if not is_active() or selected_index < 0 or selected_index >= choices.size():
		return false
	var choice = choices[selected_index]
	sound_requested.emit(CUE_CONFIRM)
	choice_confirmed.emit(selected_index, choice.text, choice.target)
	return true


func cancel() -> bool:
	if not is_active():
		return false
	sound_requested.emit(CUE_CANCEL)
	cancel_requested.emit()
	return true
