extends Node
class_name ChessAura2D

enum AuraMode { SILHOUETTE, SQUARE_FLAME, HYBRID }

const AURA_SHADER := preload("res://effects/chess_aura_overlay.gdshader")
const SquareEmitter := preload("res://scripts/view/chess_square_emitter_2d.gd")

@export var profile: ChessAuraProfile
@export var mode := AuraMode.HYBRID

var power := 0.0
var silhouette_power := 0.0
var particle_power := 0.0
var elapsed := 0.0
var bindings: Array[Dictionary] = []
var power_tween: Tween
var silhouette_fill := 0.0
var silhouette_fill_color := Color.WHITE
var density_multiplier := 1.0
var speed_multiplier := 1.0
var simulation_speed := 1.0
var continuous_emission_enabled := true


func _ready() -> void:
	if profile == null:
		profile = ChessAuraProfile.new()
	set_process(true)
	set_power(profile.idle_power)


func bind_targets(targets: Array[Sprite2D]) -> void:
	_bind_targets(targets, true, 1, true, 2)


## Layered rigs need one uninterrupted exterior treatment. Each overlay still
## follows its source sprite, but all overlays render beneath the entire rig;
## particles remain independently controllable above it.
func bind_layered_targets(targets: Array[Sprite2D], silhouette_z: int, particle_z: int) -> void:
	_bind_targets(targets, false, silhouette_z, false, particle_z)


func _bind_targets(targets: Array[Sprite2D], silhouette_relative: bool, silhouette_z: int, particle_relative: bool, particle_z: int) -> void:
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
		overlay.z_index = silhouette_z
		overlay.z_as_relative = silhouette_relative
		var material := ShaderMaterial.new()
		material.shader = AURA_SHADER
		overlay.material = material
		source.add_child(overlay)

		var emitter := SquareEmitter.new() as ChessSquareEmitter2D
		emitter.name = "ChessSquareEmitter"
		emitter.z_index = particle_z
		emitter.z_as_relative = particle_relative
		source.add_child(emitter)
		emitter.configure(source, profile, index * 101)
		bindings.append({"source": source, "overlay": overlay, "material": material, "emitter": emitter})
	_sync_bindings()
	_apply_mode()
	set_silhouette_power(silhouette_power)
	set_particle_power(particle_power)


func clear_targets() -> void:
	for binding in bindings:
		var overlay: Variant = binding.get("overlay")
		var emitter: Variant = binding.get("emitter")
		if is_instance_valid(overlay):
			overlay.queue_free()
		if is_instance_valid(emitter):
			emitter.queue_free()
	bindings.clear()


func set_mode(value: int) -> void:
	mode = value
	_apply_mode()


func set_power(value: float) -> void:
	var resolved_power := clampf(value, 0.0, 1.0)
	set_silhouette_power(resolved_power)
	set_particle_power(resolved_power)


func set_layer_z(silhouette_z: int, particle_z: int) -> void:
	for binding in bindings:
		var overlay: Sprite2D = binding["overlay"]
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		overlay.z_index = silhouette_z
		emitter.z_index = particle_z


func set_silhouette_power(value: float) -> void:
	silhouette_power = clampf(value, 0.0, 1.0)
	for binding in bindings:
		var material: ShaderMaterial = binding["material"]
		material.set_shader_parameter("power", silhouette_power)
	_sync_combined_power()


func set_particle_power(value: float) -> void:
	particle_power = clampf(value, 0.0, 1.0)
	for binding in bindings:
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		emitter.set_emission_power(particle_power)
	_sync_combined_power()


func _sync_combined_power() -> void:
	power = (silhouette_power + particle_power) * 0.5


func set_silhouette_fill(value: float, color := Color.WHITE) -> void:
	silhouette_fill = clampf(value, 0.0, 1.0)
	silhouette_fill_color = color
	for binding in bindings:
		var material: ShaderMaterial = binding["material"]
		material.set_shader_parameter("silhouette_fill", silhouette_fill)
		material.set_shader_parameter("silhouette_fill_color", silhouette_fill_color)


func set_runtime_multipliers(density: float, speed: float) -> void:
	density_multiplier = maxf(density, 0.0)
	speed_multiplier = maxf(speed, 0.0)
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).set_runtime_multipliers(density_multiplier, speed_multiplier)


func emit_burst(multiplier := 1.0) -> void:
	var count := maxi(int(round(profile.square_density * maxf(multiplier, 0.0))), 1)
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).emit_burst(count, 1.0)


func set_simulation_speed(value: float) -> void:
	simulation_speed = maxf(value, 0.0)
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).set_simulation_speed(simulation_speed)


func set_continuous_emission_enabled(value: bool) -> void:
	continuous_emission_enabled = value
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).set_continuous_emission_enabled(value)


func set_simulation_paused(paused: bool) -> void:
	set_process(not paused)
	for binding in bindings:
		(binding["emitter"] as ChessSquareEmitter2D).set_process(not paused)


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
	set_silhouette_fill(0.0)
	set_runtime_multipliers(1.0, 1.0)
	set_continuous_emission_enabled(true)
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
	elapsed += delta * simulation_speed
	_sync_bindings()
	for binding in bindings:
		(binding["material"] as ShaderMaterial).set_shader_parameter("elapsed", elapsed)


func _sync_bindings() -> void:
	for binding in bindings:
		var source_value: Variant = binding.get("source")
		var overlay_value: Variant = binding.get("overlay")
		var material_value: Variant = binding.get("material")
		if not is_instance_valid(source_value) or not is_instance_valid(overlay_value) or not is_instance_valid(material_value):
			continue
		var source := source_value as Sprite2D
		var overlay := overlay_value as Sprite2D
		var material := material_value as ShaderMaterial
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
		material.set_shader_parameter("silhouette_fill", silhouette_fill)
		material.set_shader_parameter("silhouette_fill_color", silhouette_fill_color)


func _apply_mode() -> void:
	for binding in bindings:
		var overlay: Sprite2D = binding["overlay"]
		var emitter: ChessSquareEmitter2D = binding["emitter"]
		overlay.visible = mode in [AuraMode.SILHOUETTE, AuraMode.HYBRID]
		emitter.enabled = mode in [AuraMode.SQUARE_FLAME, AuraMode.HYBRID]
		if mode == AuraMode.SILHOUETTE:
			emitter.clear_particles()
