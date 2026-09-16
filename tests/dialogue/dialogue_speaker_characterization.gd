extends Node

const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")
const ProfileScript := preload("res://scripts/dialogue/dialogue_speaker_profile.gd")
const EmitterScript := preload("res://scripts/dialogue/dialogue_voice_emitter.gd")
const CATALOG := preload("res://assets/ui/dialogue/dialogue_speaker_catalog.tres")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_catalog_resolution()
	_test_voice_policy_and_determinism()
	_test_completion_emits_every_remaining_request()
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
	_check(CATALOG.portrait("hood", "laugh_a") == CATALOG.portrait("hood", "laugh_b"), "temporary expression IDs may intentionally share an asset")
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


func _test_completion_emits_every_remaining_request() -> void:
	var result = DialogueParserScript.parse_text("@conversation voice\n@page speaker=hood name=Hood\nA B!", "voice.dialogue")
	var reveal = RevealScript.new()
	var emitter = EmitterScript.new()
	emitter.set_profile(CATALOG.profile("hood"))
	var indices := PackedInt32Array()
	emitter.voice_requested.connect(func(_stream, _pitch, _volume, index, _character): indices.append(index))
	reveal.character_revealed.connect(emitter.on_character_revealed)
	reveal.start(result.conversation.pages[0])
	reveal.reveal_one()
	reveal.complete_immediately()
	_check(indices == PackedInt32Array([0, 2, 3]), "completion synchronously emits every remaining eligible character request in source order")
	_check(reveal.completed and emitter.request_count == 3, "completion returns with the full voice-request batch emitted")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
