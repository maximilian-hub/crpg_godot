extends RefCounted
class_name DialogueVoiceEmitter

signal voice_requested(stream: AudioStream, pitch: float, volume_db: float, visible_character_index: int, character: String)

var profile: DialogueSpeakerProfile
var enabled := true
var request_count := 0


func set_profile(value: DialogueSpeakerProfile) -> void:
	profile = value
	request_count = 0


func on_character_revealed(visible_character_index: int, character: String) -> void:
	if not enabled or profile == null or not profile.voice_enabled or not is_character_eligible(character):
		return
	request_count += 1
	voice_requested.emit(
		profile.clip_for(visible_character_index),
		profile.pitch_for(visible_character_index),
		profile.volume_db,
		visible_character_index,
		character
	)


static func is_character_eligible(character: String) -> bool:
	return not character.is_empty() and character != " " and character != "\t" and character != "\n" and character != "\r"
