extends Node
class_name ChessAura2D

enum AuraMode { SILHOUETTE, SQUARE_FLAME, HYBRID }

const AURA_SHADER := preload("res://effects/chess_aura_overlay.gdshader")
const SquareEmitter := preload("res://scripts/view/chess_square_emitter_2d.gd")

@export var profile: ChessAuraProfile
@export var mode := AuraMode.HYBRID

var power := 0.0
var elapsed := 0.0
var bindings: Array[Dictionary] = []
var power_tween: Tween


func _ready() -> void:
	if profile == null:
		profile = ChessAuraProfile.new()
	set_process(true)
	set_power(profile.idle_power)


func bind_targets(targets: Array[Sprite2D]) -> void:
	clear_targets()
	if profile == null:
		profile = ChessAuraProfile.new()
	for index in range(targets.size()):
		var source := targets[index]
		if not is_instance_valid(source):
			continue
		var overlay := Sprite2D.new()
		overlay.name = "ChessAuraOverlay"
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.z_index = 0
		overlay.z_as_relative = true
		var material := ShaderMaterial.new()
		material.shader = AURA_SHADER
		overlay.material = material
		source.add_child(overlay)

		var emitter := SquareEmitter.new() as ChessSquareEmitter2D
		emitter.name = "ChessSquareEmitter"
		emitter.z_index = 0
		emitter.z_as_relative = true
		source.add_child(emitter)
		emitter.configure(source, profile, index * 101)
		bindings.append({"source": source, "overlay": overlay, "material": material, "emitter": emitter})
	_sync_bindings()
	_apply_mode()
	set_power(power)


func clear_targets() -> void:
	for binding in bindings:
		var overlay: Sprite2D = binding["overlay"]
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		if is_instance_valid(overlay):
			overlay.queue_free()
		if is_instance_valid(emitter):
			emitter.queue_free()
	bindings.clear()


func set_mode(value: int) -> void:
	mode = value
	_apply_mode()


func set_power(value: float) -> void:
	power = clampf(value, 0.0, 1.0)
	for binding in bindings:
		var material: ShaderMaterial = binding["material"]
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		material.set_shader_parameter("power", power)
		emitter.set_emission_power(power)


func power_up(duration_override := -1.0) -> void:
	_tween_power(1.0, profile.power_up_duration if duration_override < 0.0 else duration_override)


func power_down(duration_override := -1.0) -> void:
	_tween_power(0.0, profile.power_down_duration if duration_override < 0.0 else duration_override)


func active_particle_count() -> int:
	var count := 0
	for binding in bindings:
		count += (binding["emitter"] as ChessSquareEmitter2D).active_particle_count()
	return count


func reset_effect() -> void:
	if power_tween != null and power_tween.is_valid():
		power_tween.kill()
	set_power(profile.idle_power)
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).clear_particles()


func _tween_power(target: float, duration: float) -> void:
	if power_tween != null and power_tween.is_valid():
		power_tween.kill()
	if duration <= 0.0:
		set_power(target)
		return
	power_tween = create_tween()
	power_tween.tween_method(set_power, power, target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	elapsed += delta
	_sync_bindings()
	for binding in bindings:
		(binding["material"] as ShaderMaterial).set_shader_parameter("elapsed", elapsed)


func _sync_bindings() -> void:
	for binding in bindings:
		var source: Sprite2D = binding["source"]
		var overlay: Sprite2D = binding["overlay"]
		var material: ShaderMaterial = binding["material"]
		if not is_instance_valid(source) or not is_instance_valid(overlay):
			continue
		overlay.texture = source.texture
		overlay.centered = source.centered
		overlay.offset = source.offset
		overlay.flip_h = source.flip_h
		overlay.flip_v = source.flip_v
		overlay.region_enabled = source.region_enabled
		overlay.region_rect = source.region_rect
		overlay.hframes = source.hframes
		overlay.vframes = source.vframes
		overlay.frame = source.frame
		material.set_shader_parameter("core_color", profile.core_color)
		material.set_shader_parameter("accent_color", profile.accent_color)
		material.set_shader_parameter("outline_width", profile.outline_width)
		material.set_shader_parameter("outline_intensity", profile.outline_intensity)
		material.set_shader_parameter("interior_intensity", profile.interior_intensity)
		material.set_shader_parameter("motion_speed", profile.rise_speed / 14.0)


func _apply_mode() -> void:
	for binding in bindings:
		var overlay: Sprite2D = binding["overlay"]
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		overlay.visible = mode in [AuraMode.SILHOUETTE, AuraMode.HYBRID]
		emitter.enabled = mode in [AuraMode.SQUARE_FLAME, AuraMode.HYBRID]
		if mode == AuraMode.SILHOUETTE:
			emitter.clear_particles()
