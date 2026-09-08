extends Node2D
class_name ChessSpecialMoveSourceCue

var profile: ChessSpecialMovePresentationProfile
var world_scale := 1.0
var rng := RandomNumberGenerator.new()
var lines := PackedVector2Array()


func configure(value: ChessSpecialMovePresentationProfile, scale_factor: float, seed: int) -> void:
	profile = value
	world_scale = maxf(scale_factor, 0.01)
	rng.seed = seed
	z_index = ChessBoardView.BOARD_EFFECT_Z + 3
	z_as_relative = false
	visible = false


func play(duration_scale := 1.0) -> void:
	_play_sound(profile.cry_sound, profile.cry_volume_db)
	var cue_time := 0.0
	for blink in range(profile.wiggle_blink_count):
		_build_lines(blink)
		visible = true
		_play_sound(profile.wiggle_sound, profile.wiggle_volume_db)
		var on_time: float = profile.wiggle_on_time * duration_scale
		cue_time += on_time
		if on_time > 0.0:
			await get_tree().create_timer(on_time).timeout
		visible = false
		if blink < profile.wiggle_blink_count - 1:
			var off_time: float = profile.wiggle_off_time * duration_scale
			cue_time += off_time
			if off_time > 0.0:
				await get_tree().create_timer(off_time).timeout
	var remaining := maxf(profile.cry_duration * duration_scale - cue_time, 0.0)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout


func _build_lines(blink: int) -> void:
	lines.clear()
	var count := maxi(profile.wiggle_line_count, 1)
	for index in range(count):
		var angle := TAU * float(index) / float(count) + rng.randf_range(-0.18, 0.18) + float(blink) * 0.12
		var direction := Vector2.RIGHT.rotated(angle)
		var tangent := Vector2(-direction.y, direction.x)
		var start := direction * profile.wiggle_radius * world_scale
		var finish := start + direction * profile.wiggle_length * world_scale
		lines.append(start.round())
		lines.append((start.lerp(finish, 0.5) + tangent * rng.randf_range(-3.0, 3.0) * world_scale).round())
		lines.append(finish.round())
	queue_redraw()


func _draw() -> void:
	for index in range(0, lines.size(), 3):
		draw_polyline(PackedVector2Array([lines[index], lines[index + 1], lines[index + 2]]), Color.BLACK, profile.wiggle_width * world_scale, false)


func _play_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
