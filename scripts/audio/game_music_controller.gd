extends Node
class_name GameMusicController

@export var overworld_track: AudioStream
@export_range(-80.0, 24.0, 0.5) var overworld_volume_db := 0.0
@export var battle_track: AudioStream
@export_range(-80.0, 24.0, 0.5) var battle_volume_db := 0.0
@export_range(0.0, 2.0, 0.01) var battle_defeat_fade_duration := 0.3

@onready var player: AudioStreamPlayer = $MusicPlayer

var current_track: StringName = &""
var fade_tween: Tween


func play_overworld() -> void:
	_play_loop(&"overworld", overworld_track, overworld_volume_db)


func play_battle() -> void:
	_play_loop(&"battle", battle_track, battle_volume_db)


func stop_bgm() -> void:
	_cancel_fade()
	current_track = &""
	player.stop()


func fade_out_battle() -> void:
	if current_track != &"battle" or not player.playing:
		return
	_cancel_fade()
	if battle_defeat_fade_duration <= 0.0:
		stop_bgm()
		return
	var fading_track := current_track
	fade_tween = create_tween()
	fade_tween.tween_property(player, "volume_db", -80.0, battle_defeat_fade_duration)
	fade_tween.tween_callback(func():
		if current_track == fading_track:
			current_track = &""
			player.stop()
	)


func _play_loop(track_name: StringName, stream: AudioStream, volume_db: float) -> void:
	_cancel_fade()
	if stream == null:
		stop_bgm()
		return
	if current_track == track_name and player.playing:
		player.volume_db = volume_db
		return
	current_track = track_name
	# Loop points belong to the imported audio resource. Keeping that resource
	# intact also avoids duplicating large compressed WAV sample buffers.
	_configure_whole_stream_loop(stream)
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _cancel_fade() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = null


func _configure_whole_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_begin = 0
		if wav.loop_end <= wav.loop_begin:
			wav.loop_end = roundi(wav.get_length() * float(wav.mix_rate))
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
