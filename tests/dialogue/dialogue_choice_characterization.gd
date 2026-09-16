extends Node

const ChoiceScript := preload("res://scripts/dialogue/dialogue_choice.gd")
const ChoiceControllerScript := preload("res://scripts/dialogue/dialogue_choice_controller.gd")
const SoundPlayerScript := preload("res://scripts/ui/dialogue_choice_sound_player.gd")
const ParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")
const DIALOGUE_SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_empty_choices()
	_test_single_choice_and_reveal_gate()
	_test_multi_choice_wrapping_and_targets()
	_test_two_stage_confirm_contract()
	_test_optional_sound_slots()
	if failures.is_empty():
		print("DIALOGUE CHOICE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE CHOICE FAILURE: ", failure)
		get_tree().quit(1)


func _test_empty_choices() -> void:
	var controller = ChoiceControllerScript.new()
	controller.start([])
	controller.set_page_complete(true)
	_check(controller.selected_index == -1 and not controller.is_active(), "empty pages never activate choice selection")
	_check(not controller.move(1) and not controller.confirm() and not controller.cancel(), "empty pages ignore navigation, confirmation, and cancel")


func _test_single_choice_and_reveal_gate() -> void:
	var controller = ChoiceControllerScript.new()
	var confirmed := PackedStringArray()
	controller.choice_confirmed.connect(func(_index: int, _text: String, target: String): confirmed.append(target))
	controller.start([ChoiceScript.new("Continue", "continue_target")])
	_check(controller.selected_index == 0 and not controller.is_active(), "single choice is selected but inactive while text reveals")
	_check(not controller.move(1) and not controller.confirm() and confirmed.is_empty(), "reveal gate blocks all choice interaction")
	controller.set_page_complete(true)
	_check(controller.is_active() and not controller.move(1), "single completed choice activates without meaningless navigation")
	_check(controller.confirm() and confirmed == PackedStringArray(["continue_target"]), "completed single choice emits its authored target")


func _test_multi_choice_wrapping_and_targets() -> void:
	var controller = ChoiceControllerScript.new()
	var choices: Array = [
		ChoiceScript.new("One", "target_one"),
		ChoiceScript.new("Two", "target_two"),
		ChoiceScript.new("Three", "target_three"),
	]
	var selections := PackedInt32Array()
	var cues := PackedStringArray()
	var confirmed := PackedStringArray()
	var cancel_count := [0]
	controller.selection_changed.connect(func(index: int): selections.append(index))
	controller.sound_requested.connect(func(cue: StringName): cues.append(String(cue)))
	controller.choice_confirmed.connect(func(index: int, text: String, target: String): confirmed.append("%d:%s:%s" % [index, text, target]))
	controller.cancel_requested.connect(func(): cancel_count[0] += 1)
	controller.start(choices)
	controller.set_page_complete(true)
	_check(controller.move(-1) and controller.selected_index == 2, "up navigation wraps first choice to last")
	_check(controller.move(1) and controller.selected_index == 0, "down navigation wraps last choice to first")
	controller.move(1)
	_check(controller.selected_index == 1 and selections == PackedInt32Array([0, 2, 0, 1]), "selection changes are deterministic and include initial state")
	_check(controller.confirm() and confirmed == PackedStringArray(["1:Two:target_two"]), "confirm emits selected index, visible text, and stable target ID without executing it")
	_check(controller.cancel() and cancel_count[0] == 1, "cancel emits a neutral request without changing selection")
	_check(cues == PackedStringArray(["navigate", "navigate", "navigate", "confirm", "cancel"]), "successful interactions emit presentation sound cues in order")


func _test_optional_sound_slots() -> void:
	var player = SoundPlayerScript.new()
	add_child(player)
	var skin = DIALOGUE_SKIN.duplicate(true)
	player.set_skin(skin)
	_check(player.stream_for_cue(ChoiceControllerScript.CUE_NAVIGATE) == null, "empty optional choice sound slot remains silent")
	var placeholder_sound := AudioStreamWAV.new()
	skin.choice_navigation_sound = placeholder_sound
	_check(player.stream_for_cue(ChoiceControllerScript.CUE_NAVIGATE) == placeholder_sound, "navigation cue resolves its configured optional sound slot")
	_check(player.stream_for_cue(ChoiceControllerScript.CUE_CONFIRM) == null and player.stream_for_cue(ChoiceControllerScript.CUE_CANCEL) == null, "confirm and cancel sound slots remain independently optional")
	skin.choice_navigation_sound = null
	player.free()


func _test_two_stage_confirm_contract() -> void:
	var parsed = ParserScript.parse_text("@conversation choices\n@page speaker=test name=Test\nChoose after reveal.\n@choice text=Yes target=yes_target\n@choice text=No target=no_target", "choice_contract.dialogue")
	var page = parsed.conversation.pages[0]
	var reveal = RevealScript.new()
	var controller = ChoiceControllerScript.new()
	var confirmed := PackedStringArray()
	controller.choice_confirmed.connect(func(_index: int, _text: String, target: String): confirmed.append(target))
	reveal.page_completed.connect(func(): controller.set_page_complete(true))
	controller.start(page.choices)
	reveal.start(page)
	if not reveal.completed:
		reveal.confirm()
	else:
		controller.confirm()
	_check(reveal.completed and confirmed.is_empty(), "first confirm completes revealing text without selecting a choice")
	_check(controller.is_active(), "reveal completion activates authored choices")
	if not reveal.completed:
		reveal.confirm()
	else:
		controller.confirm()
	_check(confirmed == PackedStringArray(["yes_target"]), "second confirm emits the highlighted target without requesting page advancement")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
