extends Node

const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")
const ProfileScript := preload("res://scripts/dialogue/dialogue_speaker_profile.gd")
const EmitterScript := preload("res://scripts/dialogue/dialogue_voice_emitter.gd")
const CATALOG := preload("res://assets/ui/dialogue/dialogue_speaker_catalog.tres")
const SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_catalog_resolution()
	_test_voice_policy_and_determinism()
	_test_text_size_volume()
	_test_completion_emits_one_loudest_remaining_request()
	_test_bulk_reveal_edge_cases()
	if failures.is_empty():
		print("DIALOGUE SPEAKER CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE SPEAKER FAILURE: ", failure)
		get_tree().quit(1)


func _test_catalog_resolution() -> void:
	var hood = CATALOG.profile("hood")
	_check(hood != null and hood.default_display_name == "Hood", "speaker ID resolves to its data-driven profile")
	_check(CATALOG.portrait("hood", "hood_neutral") != null, "portrait ID resolves through the speaker profile")
	_check(CATALOG.portrait("hood", "laugh_a") != CATALOG.portrait("hood", "laugh_b"), "expression IDs resolve to their distinct supplied assets")
	_check(hood.voice_clips.size() == 1 and hood.voice_clips[0] != null, "Hood profile resolves its supplied character voice clip")
	_check(CATALOG.portrait("hood", "missing") == null and CATALOG.profile("missing") == null, "unknown IDs fail safely into empty presentation")
	var ernest = CATALOG.profile("ernest_the_unreasonably_named")
	_check(ernest != null and not ernest.voice_enabled, "catalog supports explicitly silent speakers")


func _test_voice_policy_and_determinism() -> void:
	var profile = ProfileScript.new()
	profile.speaker_id = "test"
	profile.minimum_pitch = 0.8
	profile.maximum_pitch = 1.2
	profile.voice_seed = 42
	var clips: Array[AudioStream] = [AudioStreamWAV.new()]
	profile.voice_clips = clips
	var emitter = EmitterScript.new()
	emitter.set_profile(profile)
	var requests: Array = []
	emitter.voice_requested.connect(func(stream, pitch, _volume, index, character): requests.append([stream, pitch, index, character]))
	for index in range(4):
		emitter.on_character_revealed(index, "A !\n"[index])
	_check(requests.size() == 2, "letters and punctuation request voices while spaces and newlines remain silent")
	_check(requests[0][0] != null and requests[0][2] == 0 and requests[1][2] == 2, "requests retain clip and visible-character index")
	var first_pitch: float = requests[0][1]
	emitter.set_profile(profile)
	emitter.on_character_revealed(0, "A")
	_check(is_equal_approx(requests.back()[1], first_pitch), "pitch selection is repeatable for the same seed and character index")
	profile.voice_enabled = false
	emitter.on_character_revealed(4, "Z")
	_check(requests.size() == 3, "silent profiles emit no voice requests")


func _test_text_size_volume() -> void:
	var result = DialogueParserScript.parse_text("@conversation sized\n@page speaker=test name=Test\n[size=small]s[/size]n[size=large]L[size=small]q[/size][/size][size=unknown]u[/size]", "sized.dialogue")
	var page = result.conversation.pages[0]
	var profile = ProfileScript.new()
	var clips: Array[AudioStream] = [AudioStreamWAV.new()]
	profile.voice_clips = clips
	profile.volume_db = 2.0
	var emitter = EmitterScript.new()
	emitter.set_profile(profile)
	emitter.set_page(page)
	emitter.set_skin(SKIN)
	var volumes := PackedFloat32Array()
	for index in range(page.text.length()):
		emitter.voice_requested.connect(func(_stream, _pitch, volume, _index, _character): volumes.append(volume), CONNECT_ONE_SHOT)
		emitter.on_character_revealed(index, page.text[index])
	_check(volumes == PackedFloat32Array([-10.0, 2.0, 8.0, -10.0, 2.0]), "small, normal, large, nested-small, and unknown-size text use the configured additive volumes")


func _test_completion_emits_one_loudest_remaining_request() -> void:
	var result = DialogueParserScript.parse_text("@conversation voice\n@page speaker=hood name=Hood\nA[size=small]b[/size] [size=large]C![/size]", "voice.dialogue")
	var page = result.conversation.pages[0]
	var reveal = RevealScript.new()
	var emitter = EmitterScript.new()
	emitter.set_profile(CATALOG.profile("hood"))
	emitter.set_page(page)
	emitter.set_skin(SKIN)
	var requests: Array = []
	emitter.voice_requested.connect(func(_stream, pitch, volume, index, character): requests.append([pitch, volume, index, character]))
	reveal.character_revealed.connect(emitter.on_character_revealed)
	reveal.bulk_reveal_started.connect(emitter.on_bulk_reveal_started)
	reveal.bulk_reveal_finished.connect(emitter.on_bulk_reveal_finished)
	reveal.start(page)
	reveal.reveal_one()
	reveal.complete_immediately()
	_check(requests.size() == 2 and requests[0][2] == 0 and requests[1][2] == 3, "bulk completion replaces all remaining character blips with the first loudest eligible character")
	_check(is_equal_approx(requests[1][1], 6.0), "bulk completion applies the large-text offset to the speaker base volume")
	_check(is_equal_approx(requests[1][0], CATALOG.profile("hood").pitch_for(3)), "consolidated blip uses its representative character's deterministic pitch")
	_check(reveal.completed and emitter.request_count == 2, "completion returns after exactly one consolidated skip request")


func _test_bulk_reveal_edge_cases() -> void:
	var whitespace_result = DialogueParserScript.parse_text("@conversation whitespace\n@page speaker=hood name=Hood\nA \t ", "whitespace.dialogue")
	var whitespace_page = whitespace_result.conversation.pages[0]
	var reveal = RevealScript.new()
	var emitter = EmitterScript.new()
	emitter.set_profile(CATALOG.profile("hood"))
	emitter.set_page(whitespace_page)
	emitter.set_skin(SKIN)
	reveal.character_revealed.connect(emitter.on_character_revealed)
	reveal.bulk_reveal_started.connect(emitter.on_bulk_reveal_started)
	reveal.bulk_reveal_finished.connect(emitter.on_bulk_reveal_finished)
	reveal.start(whitespace_page)
	reveal.reveal_one()
	reveal.complete_immediately()
	_check(emitter.request_count == 1, "a skipped range containing only whitespace emits no consolidated blip")

	var instant_result = DialogueParserScript.parse_text("@conversation instant\n@page speaker=hood name=Hood\n[size=small]quiet[/size] [size=large]LOUD[/size]", "instant.dialogue")
	var instant_page = instant_result.conversation.pages[0]
	var instant_reveal = RevealScript.new()
	var instant_emitter = EmitterScript.new()
	instant_emitter.set_profile(CATALOG.profile("hood"))
	instant_emitter.set_page(instant_page)
	instant_emitter.set_skin(SKIN)
	var instant_requests: Array = []
	instant_emitter.voice_requested.connect(func(_stream, _pitch, volume, index, _character): instant_requests.append([volume, index]))
	instant_reveal.character_revealed.connect(instant_emitter.on_character_revealed)
	instant_reveal.bulk_reveal_started.connect(instant_emitter.on_bulk_reveal_started)
	instant_reveal.bulk_reveal_finished.connect(instant_emitter.on_bulk_reveal_finished)
	instant_reveal.instant_text = true
	instant_reveal.start(instant_page)
	_check(instant_requests.size() == 1 and instant_requests[0][1] == 6 and is_equal_approx(instant_requests[0][0], 6.0), "instant text emits one blip using the first loudest character in the complete page")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
