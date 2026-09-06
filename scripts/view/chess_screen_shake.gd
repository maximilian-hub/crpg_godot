extends Node
class_name ChessScreenShake

const ScreenShakeProfile := preload("res://scripts/view/chess_screen_shake_profile.gd")

signal offset_changed(logical_offset: Vector2)

@export var maximum_combined_offset := Vector2i(24, 18)

var active_impulses: Array[Dictionary] = []
var current_offset := Vector2.ZERO
var request_serial := 0
var target_canvas_layers: Array = []
var target_canvas_items: Array = []


func configure(canvas_layers: Array, canvas_items: Array) -> void:
	_reset_targets()
	target_canvas_layers = canvas_layers.filter(func(target): return is_instance_valid(target))
	target_canvas_items = canvas_items.filter(func(target): return is_instance_valid(target))
	_apply_offset(Vector2.ZERO)


func play(profile: Resource, direction := Vector2.ZERO, intensity := 1.0) -> void:
	if profile == null or not profile.enabled or profile.duration <= 0.0 or intensity <= 0.0:
		return
	request_serial += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.random_seed + request_serial - 1
	var resolved_direction: Vector2 = direction.normalized()
	if resolved_direction.is_zero_approx():
		resolved_direction = Vector2.RIGHT.rotated(float(rng.randi_range(0, 7)) * PI / 4.0)
	var kick: Vector2 = Vector2(
		resolved_direction.x * float(profile.horizontal_pixels),
		resolved_direction.y * float(profile.vertical_pixels)
	) * profile.initial_kick_multiplier * intensity
	active_impulses.append({
		"profile": profile,
		"rng": rng,
		"elapsed": 0.0,
		"sample_time": profile.step_interval,
		"sample": kick.round(),
		"intensity": intensity,
	})
	set_process(true)
	_resolve_offset()


func cancel_all() -> void:
	active_impulses.clear()
	set_process(false)
	_apply_offset(Vector2.ZERO)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	for index in range(active_impulses.size() - 1, -1, -1):
		var impulse: Dictionary = active_impulses[index]
		var profile: Resource = impulse.profile
		impulse.elapsed = float(impulse.elapsed) + delta
		if float(impulse.elapsed) >= profile.duration:
			active_impulses.remove_at(index)
			continue
		impulse.sample_time = float(impulse.sample_time) - delta
		if float(impulse.sample_time) <= 0.0:
			var progress := clampf(float(impulse.elapsed) / profile.duration, 0.0, 1.0)
			var envelope := pow(1.0 - progress, profile.falloff_exponent) * float(impulse.intensity)
			var limit_x := maxi(0, roundi(float(profile.horizontal_pixels) * envelope))
			var limit_y := maxi(0, roundi(float(profile.vertical_pixels) * envelope))
			var rng := impulse.rng as RandomNumberGenerator
			impulse.sample = Vector2(rng.randi_range(-limit_x, limit_x), rng.randi_range(-limit_y, limit_y))
			impulse.sample_time = float(impulse.sample_time) + profile.step_interval
		active_impulses[index] = impulse
	_resolve_offset()
	if active_impulses.is_empty():
		set_process(false)


func _resolve_offset() -> void:
	var combined := Vector2.ZERO
	for impulse in active_impulses:
		combined += Vector2(impulse.sample)
	combined.x = clampf(combined.x, -maximum_combined_offset.x, maximum_combined_offset.x)
	combined.y = clampf(combined.y, -maximum_combined_offset.y, maximum_combined_offset.y)
	_apply_offset(combined.round())


func _apply_offset(offset: Vector2) -> void:
	var resolved_offset := offset.round()
	var delta := resolved_offset - current_offset
	for layer in target_canvas_layers:
		if is_instance_valid(layer):
			layer.offset += delta
	for item in target_canvas_items:
		if is_instance_valid(item):
			item.position += delta
	current_offset = resolved_offset
	offset_changed.emit(current_offset)


func _reset_targets() -> void:
	for layer in target_canvas_layers:
		if is_instance_valid(layer):
			layer.offset -= current_offset
	for item in target_canvas_items:
		if is_instance_valid(item):
			item.position -= current_offset
	target_canvas_layers.clear()
	target_canvas_items.clear()
	current_offset = Vector2.ZERO


func _exit_tree() -> void:
	_reset_targets()
	current_offset = Vector2.ZERO
