extends Node2D
class_name ChessKingDeathEffect

signal completed()

const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")
const RIFT_SHADER := preload("res://effects/chess_lightning_rift.gdshader")
const DeathProfile = preload("res://scripts/view/chess_king_death_profile.gd")

var piece: PieceView
var profile: Resource
var world_scale := 1.0
var running := false
var finished := false
var rift_circles: Array[Polygon2D] = []


func configure(piece_view: PieceView, death_profile: Resource, scale_factor: float) -> void:
	piece = piece_view
	profile = death_profile if death_profile != null else DeathProfile.new()
	world_scale = maxf(scale_factor, 0.01)


func play() -> void:
	if running or finished:
		return
	running = true
	_play_sound()
	if not is_instance_valid(piece) or not is_instance_valid(piece.sprite):
		_finish()
		return
	var sprite := piece.sprite
	for _blink in range(profile.red_blink_count):
		sprite.self_modulate = Color(1.0, 0.12, 0.12, 1.0)
		await _wait(profile.blink_on_duration)
		sprite.self_modulate = Color.WHITE
		await _wait(profile.blink_off_duration)
	var stone_material := ShaderMaterial.new()
	stone_material.shader = STONE_SHADER
	stone_material.set_shader_parameter("opacity", 1.0)
	sprite.material = stone_material
	sprite.self_modulate = Color.WHITE
	var rift_travel_duration := _spawn_rift_circles()
	await _wait(profile.stone_hold_duration)
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_method(func(value: float): stone_material.set_shader_parameter("opacity", value), 1.0, 0.0, profile.stone_fade_duration)
	fade.tween_property(sprite, "self_modulate:a", 0.0, profile.stone_fade_duration)
	await fade.finished
	var remaining := maxf(rift_travel_duration - profile.stone_hold_duration - profile.stone_fade_duration, 0.0)
	await _wait(remaining)
	if is_instance_valid(piece):
		piece.queue_free()
	_finish()


func _spawn_rift_circles() -> float:
	var count := maxi(profile.rift_circle_count, 1)
	var longest_duration := 0.0
	for index in range(count):
		var circle := Polygon2D.new()
		circle.polygon = _circle_polygon(profile.rift_radius * world_scale, 20)
		var material := ShaderMaterial.new()
		material.shader = RIFT_SHADER
		material.set_shader_parameter("checker_size", profile.checker_size)
		circle.material = material
		circle.z_index = 90
		circle.z_as_relative = false
		add_child(circle)
		rift_circles.append(circle)
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(count))
		var distance := _distance_to_viewport_exit(global_position, direction, profile.rift_radius * world_scale * 2.0)
		var duration := distance / maxf(profile.rift_speed * world_scale, 1.0)
		longest_duration = maxf(longest_duration, duration)
		var tween := create_tween()
		tween.tween_property(circle, "position", direction * distance, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	return longest_duration


func _distance_to_viewport_exit(origin: Vector2, direction: Vector2, margin: float) -> float:
	var viewport_size := get_viewport_rect().size
	var candidates: Array[float] = []
	if direction.x > 0.0001: candidates.append((viewport_size.x + margin - origin.x) / direction.x)
	if direction.x < -0.0001: candidates.append((-margin - origin.x) / direction.x)
	if direction.y > 0.0001: candidates.append((viewport_size.y + margin - origin.y) / direction.y)
	if direction.y < -0.0001: candidates.append((-margin - origin.y) / direction.y)
	var distance := INF
	for candidate in candidates:
		if candidate >= 0.0: distance = minf(distance, candidate)
	return distance if is_finite(distance) else maxf(viewport_size.x, viewport_size.y) + margin


func _circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments):
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / float(segments)) * radius)
	return points


func _play_sound() -> void:
	if profile.death_sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = profile.death_sound
	player.volume_db = profile.sound_volume_db
	add_child(player)
	player.play()


func _wait(duration: float) -> void:
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	completed.emit()
	queue_free()
