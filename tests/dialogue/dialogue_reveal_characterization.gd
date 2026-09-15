extends Node

const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_deterministic_timing_and_punctuation()
	_test_authored_and_player_speed()
	_test_portrait_event_order()
	_test_confirm_and_instant_semantics()
	if failures.is_empty():
		print("DIALOGUE REVEAL CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE REVEAL FAILURE: ", failure)
		get_tree().quit(1)


func _test_deterministic_timing_and_punctuation() -> void:
	var page = _page("A,B.")
	var reveal = RevealScript.new()
	reveal.base_character_delay = 0.1
	reveal.start(page)
	reveal.advance(0.099)
	_check(reveal.visible_character_count == 0, "character remains hidden before its complete delay")
	reveal.advance(0.001)
	_check(reveal.visible_character_count == 1, "character appears exactly when accumulated time reaches its delay")
	reveal.advance(0.1)
	_check(reveal.visible_character_count == 2, "ordinary next-character delay is deterministic")
	reveal.advance(0.199)
	_check(reveal.visible_character_count == 2, "comma pauses before the following character")
	reveal.advance(0.001)
	_check(reveal.visible_character_count == 3, "comma pause uses the configured multiplier")
	reveal.advance(1.0)
	_check(reveal.visible_character_count == 4 and reveal.completed, "large delta catches up and completes without frame-rate dependence")
	var pause_page = _page(".\nA")
	var pause_reveal = RevealScript.new()
	pause_reveal.base_character_delay = 0.1
	pause_reveal.start(pause_page)
	pause_reveal.reveal_one()
	_check(is_equal_approx(pause_reveal.delay_before_next_character(), 0.4), "sentence punctuation applies the configured post-character pause")
	pause_reveal.reveal_one()
	_check(is_equal_approx(pause_reveal.delay_before_next_character(), 0.3), "newline applies the configured post-character pause")


func _test_authored_and_player_speed() -> void:
	var page = _page("[speed=0.5]a[/speed][speed=2]b[/speed]")
	var reveal = RevealScript.new()
	reveal.base_character_delay = 0.1
	reveal.set_player_speed(2.0)
	reveal.start(page)
	_check(is_equal_approx(reveal.delay_before_next_character(), 0.1), "player speed multiplies the authored slow span")
	reveal.advance(0.1)
	_check(reveal.visible_character_count == 1, "slow authored character reveals at scaled delay")
	_check(is_equal_approx(reveal.delay_before_next_character(), 0.025), "fast authored span retains its relative rate under player scaling")
	reveal.advance(0.025)
	_check(reveal.completed, "fast authored character completes at scaled delay")


func _test_portrait_event_order() -> void:
	var page = _page("[portrait=a]ha[portrait=b]ha")
	var reveal = RevealScript.new()
	reveal.base_character_delay = 0.1
	var log := PackedStringArray()
	reveal.portrait_changed.connect(func(id: String, index: int): log.append("portrait:%s@%d" % [id, index]))
	reveal.character_revealed.connect(func(index: int, character: String): log.append("char:%s@%d" % [character, index]))
	reveal.start(page)
	reveal.advance(0.1)
	_check(log[1] == "portrait:a@0" and log[2] == "char:h@0", "index-zero portrait event fires immediately before character zero")
	reveal.complete_immediately()
	_check(log.find("portrait:b@2") >= 0, "completion fires remaining portrait event at its exact index")
	_check(log.find("portrait:b@2") < log.find("char:h@2"), "remaining portrait event fires before its indexed character during completion")


func _test_confirm_and_instant_semantics() -> void:
	var page = _page("Test")
	var reveal = RevealScript.new()
	var completion_count := [0]
	var advance_count := [0]
	reveal.page_completed.connect(func(): completion_count[0] += 1)
	reveal.advance_requested.connect(func(): advance_count[0] += 1)
	reveal.start(page)
	var first_result = reveal.confirm()
	_check(first_result == RevealScript.ConfirmResult.COMPLETED_PAGE and reveal.visible_character_count == 4, "first confirm completes an active page")
	_check(completion_count[0] == 1 and advance_count[0] == 0, "completion confirm does not also advance")
	var second_result = reveal.confirm()
	_check(second_result == RevealScript.ConfirmResult.REQUESTED_ADVANCE and advance_count[0] == 1, "second confirm requests advancement")
	reveal.start(page)
	reveal.set_instant_text(true)
	_check(reveal.completed and reveal.visible_character_count == 4, "enabling instant text completes the current page")
	reveal.start(page)
	_check(reveal.completed, "instant-text setting completes subsequently started pages")
	reveal.set_instant_text(false)
	reveal.start(page)
	reveal.paused = true
	reveal.advance(10.0)
	_check(reveal.visible_character_count == 0, "paused controller does not consume time")
	reveal.reveal_one()
	_check(reveal.visible_character_count == 1, "manual single-character stepping remains deterministic while paused")


func _page(body: String):
	var source := "@conversation test\n@page speaker=test name=Test portrait=neutral\n%s" % body
	var result = DialogueParserScript.parse_text(source, "reveal_test.dialogue")
	if not result.is_valid():
		failures.append("test fixture failed to parse: %s" % "; ".join(result.errors))
	return result.conversation.pages[0]


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
