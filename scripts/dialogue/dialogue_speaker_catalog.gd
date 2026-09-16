extends Resource
class_name DialogueSpeakerCatalog

@export var profiles: Array[DialogueSpeakerProfile] = []


func profile(speaker_id: String) -> DialogueSpeakerProfile:
	for candidate in profiles:
		if candidate != null and candidate.speaker_id == speaker_id:
			return candidate
	return null


func portrait(speaker_id: String, portrait_id: String) -> Texture2D:
	var speaker_profile := profile(speaker_id)
	return speaker_profile.portrait(portrait_id) if speaker_profile != null else null
