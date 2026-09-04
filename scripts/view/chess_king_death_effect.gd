extends Node2D
class_name ChessKingDeathEffect

signal completed()

const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")
const RIFT_SHADER := preload("res://effects/chess_lightning_rift.gdshader")
const RED_FLASH_SHADER := preload("res://effects/chess_king_death_flash.gdshader")
const DEATH_TRANSITION_SHADER := preload("res://effects/chess_king_death_transition.gdshader")
const DeathProfile = preload("res://scripts/view/chess_king_death_profile.gd")

var piece: PieceView
var profile: Resource
var world_scale := 1.0
var running := false
var finished := false
var rift_circles: Array[Polygon2D] = []
var base_piece_position := Vector2.ZERO
var tremor_rng := RandomNumberGenerator.new()
var tremor_elapsed := 0.0
var tremor_tick := -1
var tremor_strength := 0.0
var circle_animation_elapsed := 0.0


func configure(piece_view: PieceView, death_profile: Resource, scale_factor: float) -> void:
	piece = piece_view
	profile = death_profile if death_profile != null else DeathProfile.new()
	world_scale = maxf(scale_factor, 0.01)
	tremor_rng.seed = 8301
	# Activation climax beams use king_sprite.global_position as their canonical
	# fixed target. Death rifts originate from that exact same visual center.
	if is_instance_valid(piece) and is_instance_valid(piece.sprite):
		global_position = piece.sprite.global_position


func play() -> void:
	if running or finished:
		return
	running = true
	if not is_instance_valid(piece) or not is_instance_valid(piece.sprite):
		_finish()
		return
	base_piece_position = piece.position
	tremor_strength = 1.0
	set_process(true)
	var sprite := piece.sprite
	var original_material := sprite.material
	var red_flash_material := ShaderMaterial.new()
	red_flash_material.shader = RED_FLASH_SHADER
	for blink in range(profile.red_blink_count):
		sprite.material = red_flash_material
		await _wait(profile.blink_on_duration)
		if blink < profile.red_blink_count - 1:
			sprite.material = original_material
			await _wait(profile.blink_off_duration)
	# The final blink remains red during the authored pre-death tension hold.
	await _wait(profile.pre_death_hold_duration)
	_play_sound()
	_spawn_rift_circles()
	var transition_material := ShaderMaterial.new()
	transition_material.shader = DEATH_TRANSITION_SHADER
	transition_material.set_shader_parameter("stone_progress", 0.0)
	sprite.material = transition_material
	sprite.self_modulate = Color.WHITE
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_method(func(value: float): transition_material.set_shader_parameter("stone_progress", value), 0.0, 1.0, profile.stone_fade_duration)
	death_tween.tween_method(func(value: float): tremor_strength = value, 1.0, 0.0, profile.tremor_slowdown_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await death_tween.finished
	tremor_strength = 0.0
	piece.position = base_piece_position
	var stone_material := ShaderMaterial.new()
	stone_material.shader = STONE_SHADER
	stone_material.set_shader_parameter("opacity", 1.0)
	sprite.material = stone_material
	# Completion releases the capture gate and therefore the battle result. It is
	# an authored beat, not a side effect of viewport size or circle travel time.
	var remaining := maxf(profile.result_delay - maxf(profile.stone_fade_duration, profile.tremor_slowdown_duration), 0.0)
	await _wait(remaining)
	_finish()


func _process(delta: float) -> void:
	if not running:
		return
	if is_instance_valid(piece) and tremor_strength > 0.0:
		tremor_elapsed += delta
		var interval := maxf(profile.tremor_interval / maxf(tremor_strength, 0.08), 0.01)
		var next_tick := int(floor(tremor_elapsed / interval))
		if next_tick != tremor_tick:
			tremor_tick = next_tick
			var amplitude := int(round(profile.tremor_max_pixels * world_scale * tremor_strength))
			piece.position = base_piece_position + Vector2(
				tremor_rng.randi_range(-amplitude, amplitude),
				tremor_rng.randi_range(-amplitude, amplitude)
			)
	circle_animation_elapsed += delta
	var frame := int(floor(circle_animation_elapsed / maxf(profile.rift_frame_duration, 0.02))) % 3
	var circle_scale: float = 1.0 + float(frame) * float(profile.rift_frame_growth)
	for circle in rift_circles:
		if is_instance_valid(circle):
			circle.scale = Vector2.ONE * circle_scale


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
		var maximum_radius: float = float(profile.rift_radius) * world_scale * (1.0 + 2.0 * float(profile.rift_frame_growth))
		var distance := _distance_to_viewport_exit(global_position, direction, maximum_radius * 2.0)
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
	set_process(false)
	if is_instance_valid(piece):
		piece.position = base_piece_position
	completed.emit()
	queue_free()
