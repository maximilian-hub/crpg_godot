extends Node2D
class_name ChessKingDeathEffect

signal completed()
signal result_ready_for_display()

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
var result_ready := false
var rift_circles: Array[Polygon2D] = []
var base_piece_position := Vector2.ZERO
var tremor_rng := RandomNumberGenerator.new()
var tremor_elapsed := 0.0
var tremor_tick := -1
var tremor_strength := 0.0
var circle_animation_elapsed := 0.0
var discharge_rng := RandomNumberGenerator.new()
var discharge_active := false
var discharge_elapsed := 0.0
var discharge_budget := 0.0
var discharge_markers: Array[Dictionary] = []
var spawned_discharge_count := 0


func configure(piece_view: PieceView, death_profile: Resource, scale_factor: float) -> void:
	piece = piece_view
	profile = death_profile if death_profile != null else DeathProfile.new()
	world_scale = maxf(scale_factor, 0.01)
	tremor_rng.seed = 8301
	discharge_rng.seed = 9407
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
	var rift_travel_duration := _spawn_rift_circles()
	discharge_active = true
	_spawn_discharge_marker()
	_release_result_after_delay()
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
	# Result flow has its own timer. Visual ownership continues independently so
	# circles can keep crossing the board beneath the result overlay.
	var visual_duration := maxf(rift_travel_duration, profile.discharge_duration + profile.discharge_marker_lifetime)
	visual_duration = maxf(visual_duration, profile.result_delay)
	var remaining := maxf(visual_duration - maxf(profile.stone_fade_duration, profile.tremor_slowdown_duration), 0.0)
	await _wait(remaining)
	_finish()


func _release_result_after_delay() -> void:
	await _wait(profile.result_delay)
	if result_ready:
		return
	result_ready = true
	result_ready_for_display.emit()


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
	_update_discharge(delta)


func _update_discharge(delta: float) -> void:
	if discharge_active:
		discharge_elapsed += delta
		var progress := clampf(discharge_elapsed / maxf(profile.discharge_duration, 0.05), 0.0, 1.0)
		discharge_budget += discharge_rate(progress, profile.discharge_frequency, profile.discharge_falloff_exponent) * delta
		while discharge_budget >= 1.0:
			discharge_budget -= 1.0
			_spawn_discharge_marker()
		if progress >= 1.0:
			discharge_active = false
	for index in range(discharge_markers.size() - 1, -1, -1):
		var entry: Dictionary = discharge_markers[index]
		var marker := entry.marker as ChessLightning2D
		if not is_instance_valid(marker):
			discharge_markers.remove_at(index)
			continue
		entry.age = float(entry.age) + delta
		var life_progress := clampf(float(entry.age) / maxf(float(entry.lifetime), 0.02), 0.0, 1.0)
		marker.show_strength(1.0 - life_progress)
		if life_progress >= 1.0:
			marker.queue_free()
			discharge_markers.remove_at(index)
		else:
			discharge_markers[index] = entry


func _spawn_discharge_marker() -> void:
	if not is_instance_valid(piece) or not is_instance_valid(piece.sprite):
		return
	var marker := ChessLightning2D.new()
	marker.name = "DeathDischargeMarker"
	marker.position = _random_opaque_king_point()
	marker.z_index = 2
	marker.checker_size = profile.checker_size
	marker.edge_roughness = maxf(profile.discharge_marker_size * world_scale * 0.08, 1.0)
	add_child(marker)
	var marker_size: float = float(profile.discharge_marker_size) * world_scale
	var marker_width: float = float(profile.discharge_marker_width) * world_scale
	marker.configure_impact_marker(Vector2.ZERO, marker_size, marker_width, discharge_rng.randi(), 5)
	marker.show_strength(1.0)
	discharge_markers.append({"marker": marker, "age": 0.0, "lifetime": profile.discharge_marker_lifetime})
	spawned_discharge_count += 1


func _random_opaque_king_point() -> Vector2:
	var sprite := piece.sprite
	if sprite.texture == null:
		return to_local(sprite.global_position)
	var image := sprite.texture.get_image()
	if image == null or image.is_empty():
		return to_local(sprite.global_position)
	var size := image.get_size()
	var origin := Vector2.ZERO if not sprite.centered else -Vector2(size) * 0.5
	origin += sprite.offset
	for _attempt in range(128):
		var x := discharge_rng.randi_range(0, size.x - 1)
		var y := discharge_rng.randi_range(0, size.y - 1)
		if image.get_pixel(x, y).a > 0.2:
			return to_local(sprite.to_global(origin + Vector2(x + 0.5, y + 0.5)))
	return to_local(sprite.global_position)


static func discharge_rate(progress: float, initial_frequency: float, falloff_exponent: float) -> float:
	return maxf(initial_frequency, 0.0) * pow(1.0 - clampf(progress, 0.0, 1.0), maxf(falloff_exponent, 0.01))


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
