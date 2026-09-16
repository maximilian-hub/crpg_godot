extends Node
class_name DialogueVoicePlayer

var enabled := true
var played_count := 0


func play_request(stream: AudioStream, pitch: float, volume_db: float, _visible_character_index: int, _character: String) -> void:
	if not enabled or stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	add_child(player)
	played_count += 1
	player.finished.connect(player.queue_free)
	player.play()
