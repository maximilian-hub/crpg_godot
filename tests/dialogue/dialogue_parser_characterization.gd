extends Node

const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const TextSpanScript := preload("res://scripts/dialogue/dialogue_text_span.gd")
const VALID_FIXTURE := "res://content/dialogue/hood_authoring_demo.dialogue"
const INVALID_FIXTURE := "res://content/dialogue/invalid_authoring_demo.dialogue"

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_valid_fixture()
	_test_visible_character_indices()
	_test_invalid_fixture()
	_test_missing_file()
	if failures.is_empty():
		print("DIALOGUE PARSER CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE PARSER FAILURE: ", failure)
		get_tree().quit(1)


func _test_valid_fixture() -> void:
	var result = DialogueParserScript.parse_file(VALID_FIXTURE)
	_check(result.is_valid(), "representative authored conversation parses without errors: %s" % "; ".join(result.errors))
	_check(result.conversation.id == "hood_authoring_demo", "conversation ID is retained")
	_check(result.conversation.pages.size() == 4, "ordered pages are retained")
	var unknown_page = result.conversation.pages[0]
	_check(unknown_page.speaker_id == "hood" and unknown_page.speaker_name == "Hood", "speaker identity and display name are distinct fields")
	_check(not unknown_page.speaker_known, "unknown-name presentation state is retained")
	_check(unknown_page.initial_portrait_id == "hood_neutral", "initial portrait ID is retained without an asset path")
	var laugh_page = result.conversation.pages[1]
	_check(laugh_page.text == "hahahaha. The stones remember.", "inline portrait tags are removed from visible text")
	_check(laugh_page.events.size() == 4, "frequent authored portrait changes are retained")
	_check(_event_indices(laugh_page) == PackedInt32Array([0, 2, 4, 6]), "alternating laugh portraits resolve to exact visible-character indices")
	_check(_event_values(laugh_page) == PackedStringArray(["laugh_a", "laugh_b", "laugh_a", "laugh_b"]), "portrait event order and IDs are retained")
	_check(laugh_page.character_speed_multipliers.size() == laugh_page.text.length(), "every visible character receives an authored speed multiplier")
	_check(laugh_page.character_speed_multipliers[0] == 2.0 and laugh_page.character_speed_multipliers[8] == 2.0, "fast span applies through its final punctuation")
	_check(laugh_page.character_speed_multipliers[9] == 1.0 and laugh_page.character_speed_multipliers[10] == 0.5, "default and slow timing resume at exact visible-character boundaries")
	var choice_page = result.conversation.pages[2]
	_check(choice_page.choices.size() == 2, "page choices are retained")
	_check(choice_page.choices[0].text == "Yes" and choice_page.choices[0].target == "accept_challenge", "choice label and target remain separate")
	var font_page = result.conversation.pages[3]
	_check(font_page.speaker_name == "Ernest the Unreasonably Named" and font_page.text.contains("Q7?!"), "font-evaluation page retains long names, numbers, and punctuation")
	_check(font_page.text.contains("MIXED CASE"), "caps spans precompute capitalization into final visible text")
	_check(font_page.presentation_spans.size() == 5, "fixture retains semantic color, capitalization, and font-size spans")
	var opening_spans: Array = font_page.presentation_spans.filter(func(span): return span.start_index == 0 and span.end_index == 19)
	_check(opening_spans.size() == 2, "nested size and color ranges share final visible-character indices")
	_check(font_page.presentation_spans.any(func(span): return span.kind == TextSpanScript.Kind.FONT_SIZE and span.value == "small"), "fixture retains its semantic small-text span")


func _test_visible_character_indices() -> void:
	var source := "@conversation unicode\n@page speaker=test name=Test portrait=neutral\né[portrait=changed]x"
	var result = DialogueParserScript.parse_text(source, "unicode.dialogue")
	_check(result.is_valid(), "Unicode index fixture parses")
	var page = result.conversation.pages[0]
	_check(page.text == "éx", "Unicode visible text is preserved")
	_check(page.events[0].visible_character_index == 1, "event indices count Unicode characters rather than source bytes or tag characters")
	var nested := DialogueParserScript.parse_text("@conversation nested\n@page speaker=test name=Test\n[speed=2]a[speed=0.5]b[/speed]c[/speed]d", "nested.dialogue")
	_check(nested.is_valid(), "nested speed spans parse")
	_check(nested.conversation.pages[0].character_speed_multipliers == PackedFloat32Array([2.0, 1.0, 2.0, 1.0]), "nested speed spans multiply and restore authored rates")
	var presentation := DialogueParserScript.parse_text("@conversation presentation\n@page speaker=test name=Test\n[size=large][color=warning][caps]ab[portrait=changed][speed=2]c![/speed][/caps][/color][/size]", "presentation.dialogue")
	_check(presentation.is_valid(), "nested presentation and reveal tags parse together")
	var presentation_page = presentation.conversation.pages[0]
	_check(presentation_page.text == "ABC!" and presentation_page.events[0].visible_character_index == 2, "capitalization and color markup do not shift portrait indices")
	_check(presentation_page.character_speed_multipliers == PackedFloat32Array([1.0, 1.0, 2.0, 2.0]), "presentation markup does not shift authored speed indices")
	_check(presentation_page.presentation_spans.size() == 3 and presentation_page.presentation_spans.all(func(span): return span.start_index == 0 and span.end_index == 4), "nested size, color, and capitalization share stable visible bounds")


func _test_invalid_fixture() -> void:
	var result = DialogueParserScript.parse_file(INVALID_FIXTURE)
	_check(not result.is_valid(), "invalid authored fixture is rejected")
	var joined := "\n".join(result.errors)
	_check(joined.contains("@choice must appear inside a page"), "choice placement error is actionable")
	_check(joined.contains("@conversation requires an ID"), "missing conversation ID is actionable")
	_check(joined.contains("@page requires speaker=<ID>"), "missing speaker is actionable")
	_check(joined.contains("@page has unknown attribute 'typo'"), "misspelled attributes are rejected instead of silently ignored")
	_check(joined.contains("'known' must be true or false"), "invalid known flag is actionable")
	_check(joined.contains("unknown inline tag"), "unknown inline tag is actionable")
	_check(joined.contains("portrait tag requires"), "empty portrait event is actionable")
	_check(joined.contains("@choice requires text=<label> and target=<ID>"), "incomplete choice is actionable")
	_check(joined.contains("speed tag requires a positive finite number"), "non-positive speed is actionable")
	_check(joined.contains("closing speed tag has no matching opening tag"), "unmatched closing speed tag is actionable")
	_check(joined.contains("color tag requires a semantic color ID"), "empty semantic color IDs are rejected")
	_check(joined.contains("closing color tag has no matching opening tag"), "unmatched closing color tags are actionable")
	_check(joined.contains("unclosed caps tag"), "unclosed capitalization tags are actionable")
	_check(joined.contains("size tag requires a semantic size ID"), "empty semantic size IDs are rejected")
	_check(joined.contains("closing size tag has no matching opening tag"), "unmatched closing size tags are actionable")
	_check(joined.contains("unclosed size tag"), "unclosed size tags are actionable")
	_check(result.errors[0].begins_with(INVALID_FIXTURE + ":2:"), "diagnostics include source path and line number")


func _test_missing_file() -> void:
	var result = DialogueParserScript.parse_file("res://content/dialogue/not_present.dialogue")
	_check(not result.is_valid() and result.errors[0].contains("file does not exist"), "missing files return a validation result instead of crashing")


func _event_indices(page) -> PackedInt32Array:
	var values := PackedInt32Array()
	for event in page.events:
		values.append(event.visible_character_index)
	return values


func _event_values(page) -> PackedStringArray:
	var values := PackedStringArray()
	for event in page.events:
		values.append(event.value)
	return values


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
