extends Node

const ParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const ConversationScript := preload("res://scripts/dialogue/dialogue_conversation.gd")
const RunnerScript := preload("res://scripts/dialogue/dialogue_session_runner.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_multi_page_progression_and_choice_target()
	_test_restart_and_signal_order()
	_test_centralized_settings()
	_test_empty_conversation()
	if failures.is_empty():
		print("DIALOGUE SESSION RUNNER CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE SESSION RUNNER FAILURE: ", failure)
		get_tree().quit(1)


func _test_multi_page_progression_and_choice_target() -> void:
	var runner = RunnerScript.new()
	add_child(runner)
	var pages := PackedInt32Array()
	var targets := PackedStringArray()
	var finished := PackedStringArray()
	var portraits := PackedStringArray()
	runner.page_started.connect(func(_page, index: int, _count: int): pages.append(index))
	runner.target_emitted.connect(func(target: String): targets.append(target))
	runner.conversation_finished.connect(func(id: String): finished.append(id))
	runner.portrait_changed.connect(func(id: String, index: int): portraits.append("%s@%d" % [id, index]))
	runner.set_instant_text(true)
	var conversation = _conversation()
	_check(runner.start(conversation), "valid conversation starts a session")
	_check(runner.current_page_index == 0 and runner.is_page_complete(), "session starts and completes its requested first page under instant text")
	_check(portraits[0] == "first@-1", "runner forwards initial portrait events")
	_check(runner.confirm() == RunnerScript.ConfirmResult.ADVANCED_PAGE and runner.current_page_index == 1, "confirm advances a completed ordinary page")
	_check(runner.choices_are_active(), "completed authored choice page activates its choices")
	runner.move_choice(1)
	_check(runner.confirm() == RunnerScript.ConfirmResult.CONFIRMED_CHOICE, "confirm commits the highlighted choice instead of advancing")
	_check(targets == PackedStringArray(["decline"]) and runner.current_page_index == 1, "runner emits target ID without interpreting it or changing pages")
	_check(runner.confirm() == RunnerScript.ConfirmResult.IGNORED and targets.size() == 1, "committed choice cannot emit its target repeatedly")
	_check(runner.advance_page() and runner.current_page_index == 2, "host may explicitly continue after handling a neutral target")
	_check(runner.confirm() == RunnerScript.ConfirmResult.FINISHED_CONVERSATION and not runner.active, "confirm on completed final ordinary page finishes the conversation")
	_check(finished == PackedStringArray(["runner_demo"]) and pages == PackedInt32Array([0, 1, 2]), "session emits ordered page starts and one conversation completion")


func _test_restart_and_signal_order() -> void:
	var runner = RunnerScript.new()
	add_child(runner)
	var log := PackedStringArray()
	runner.page_started.connect(func(_page, index: int, _count: int): log.append("page:%d" % index))
	runner.visibility_changed.connect(func(count: int): log.append("visible:%d" % count))
	runner.start(_conversation())
	_check(log[0] == "page:0" and log[1] == "visible:0", "page start is emitted before reveal state so hosts can configure presentation")
	runner.reveal_one()
	_check(runner.visible_character_count() == 1, "runner exposes deterministic single-character reveal")
	_check(runner.restart_page(), "active page can be restarted")
	_check(runner.current_page_index == 0 and runner.visible_character_count() == 0, "restart resets current page reveal without changing page index")
	_check(log.count("page:0") == 2, "restart emits a fresh page-start lifecycle")


func _test_centralized_settings() -> void:
	var runner = RunnerScript.new()
	add_child(runner)
	var changes := PackedStringArray()
	var cues := PackedStringArray()
	var bulk_ranges: Array = []
	runner.setting_changed.connect(func(setting: StringName, value): changes.append("%s=%s" % [setting, value]))
	runner.choice_sound_requested.connect(func(cue: StringName): cues.append(String(cue)))
	runner.bulk_reveal_started.connect(func(start_index: int, end_index: int): bulk_ranges.append([start_index, end_index]))
	runner.set_player_speed(2.5)
	runner.set_animated_text_enabled(false)
	runner.set_reduced_motion(true)
	runner.set_voice_enabled(false)
	runner.set_ui_sounds_enabled(false)
	_check(is_equal_approx(runner.reveal_controller.player_speed_multiplier, 2.5), "central player-speed setting propagates to reveal timing")
	_check(not runner.settings.animated_text_enabled and runner.settings.reduced_motion and not runner.settings.voice_enabled, "central accessibility and voice settings retain their values")
	_check(changes.size() == 5, "each centralized setting change is observable by presentation hosts")
	runner.set_instant_text(true)
	runner.start(_conversation(), 1)
	_check(bulk_ranges == [[0, 7]], "session runner forwards the exact instant-text bulk reveal range")
	runner.move_choice(1)
	_check(cues.is_empty(), "disabled UI sounds suppress otherwise valid choice cues")
	runner.set_ui_sounds_enabled(true)
	runner.move_choice(-1)
	_check(cues == PackedStringArray(["navigate"]), "re-enabled UI sounds forward neutral presentation cues")


func _test_empty_conversation() -> void:
	var runner = RunnerScript.new()
	add_child(runner)
	_check(not runner.start(null) and not runner.active, "null conversation is rejected safely")
	_check(not runner.start(ConversationScript.new()) and runner.confirm() == RunnerScript.ConfirmResult.IGNORED, "empty conversation remains inactive and ignores confirmation")


func _conversation():
	var source := """@conversation runner_demo
@page speaker=test name=Test portrait=first
First.
@page speaker=test name=Test portrait=second
Choose.
@choice text=Yes target=accept
@choice text=No target=decline
@page speaker=test name=Test portrait=third
Last.
"""
	var parsed = ParserScript.parse_text(source, "runner_demo.dialogue")
	if not parsed.is_valid():
		failures.append("runner fixture failed to parse: %s" % "; ".join(parsed.errors))
	return parsed.conversation


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
