extends RefCounted
class_name DialogueVoiceEmitter

const TextSpanScript := preload("res://scripts/dialogue/dialogue_text_span.gd")

signal voice_requested(stream: AudioStream, pitch: float, volume_db: float, visible_character_index: int, character: String)

var profile: DialogueSpeakerProfile
var page
var skin
var enabled := true
var request_count := 0
var bulk_reveal_active := false


func set_profile(value: DialogueSpeakerProfile) -> void:
	profile = value
	request_count = 0


func set_page(value) -> void:
	page = value
	bulk_reveal_active = false


func set_skin(value) -> void:
	skin = value


func on_character_revealed(visible_character_index: int, character: String) -> void:
	if bulk_reveal_active:
		return
	_request_voice(visible_character_index, character)


func on_bulk_reveal_started(start_index: int, end_index: int) -> void:
	bulk_reveal_active = true
	if not _can_emit() or page == null:
		return
	var representative_index := -1
	var representative_rank := -1
	var clamped_start := clampi(start_index, 0, page.text.length())
	var clamped_end := clampi(end_index, clamped_start, page.text.length())
	for index in range(clamped_start, clamped_end):
		var character: String = page.text[index]
		if not is_character_eligible(character):
			continue
		var rank := _size_rank(_size_name_at(index))
		if rank > representative_rank:
			representative_index = index
			representative_rank = rank
	if representative_index >= 0:
		_request_voice(representative_index, page.text[representative_index])


func on_bulk_reveal_finished(_start_index: int, _end_index: int) -> void:
	bulk_reveal_active = false


func _request_voice(visible_character_index: int, character: String) -> void:
	if not _can_emit() or not is_character_eligible(character):
		return
	request_count += 1
	voice_requested.emit(
		profile.clip_for(visible_character_index),
		profile.pitch_for(visible_character_index),
		profile.volume_db + _volume_offset_db(_size_name_at(visible_character_index)),
		visible_character_index,
		character
	)


func _can_emit() -> bool:
	return enabled and profile != null and profile.voice_enabled


func _size_name_at(visible_character_index: int) -> String:
	if page == null:
		return "normal"
	return TextSpanScript.effective_value_at(page.presentation_spans, TextSpanScript.Kind.FONT_SIZE, visible_character_index, "normal")


func _size_rank(size_name: String) -> int:
	match size_name:
		"small":
			return 0
		"large":
			return 2
		_:
			return 1


func _volume_offset_db(size_name: String) -> float:
	if skin != null:
		return skin.semantic_size_voice_volume_offset_db(size_name)
	match size_name:
		"small":
			return -12.0
		"large":
			return 6.0
		_:
			return 0.0


static func is_character_eligible(character: String) -> bool:
	return not character.is_empty() and character != " " and character != "\t" and character != "\n" and character != "\r"
