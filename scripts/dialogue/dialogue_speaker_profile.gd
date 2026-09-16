extends Resource
class_name DialogueSpeakerProfile

@export var speaker_id := ""
@export var default_display_name := ""
@export var portrait_ids := PackedStringArray()
@export var portrait_textures: Array[Texture2D] = []
@export var voice_enabled := true
@export var voice_clips: Array[AudioStream] = []
@export_range(0.1, 4.0, 0.01) var minimum_pitch := 1.0
@export_range(0.1, 4.0, 0.01) var maximum_pitch := 1.0
@export_range(-80.0, 24.0, 0.1) var volume_db := 0.0
@export var voice_seed := 0


func portrait(portrait_id: String) -> Texture2D:
	var index := portrait_ids.find(portrait_id)
	if index < 0 or index >= portrait_textures.size():
		return null
	return portrait_textures[index]


func pitch_for(visible_character_index: int) -> float:
	var low := minf(minimum_pitch, maximum_pitch)
	var high := maxf(minimum_pitch, maximum_pitch)
	if is_equal_approx(low, high):
		return low
	var random := RandomNumberGenerator.new()
	random.seed = voice_seed + visible_character_index * 104729
	return random.randf_range(low, high)


func clip_for(visible_character_index: int) -> AudioStream:
	if voice_clips.is_empty():
		return null
	var random := RandomNumberGenerator.new()
	random.seed = voice_seed + visible_character_index * 130363
	return voice_clips[random.randi_range(0, voice_clips.size() - 1)]
