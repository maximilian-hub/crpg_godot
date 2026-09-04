extends "res://scripts/view/chess_king_activation_sequence.gd"
class_name ChessHoodActivationSequence

## Decisive uses the same phase/resolve machinery but compresses the invocation
## into a locked silhouette followed by one abrupt, overwhelming reveal.
func _uses_response_crackle() -> bool:
	return false


func _apply_visual_state() -> void:
	super._apply_visual_state()
	if profile == null:
		return
	var boundaries := _phase_boundaries()
	var phase := _phase_for_time(elapsed)
	match phase:
		Phase.INVOCATION:
			var progress := _range_progress(elapsed, boundaries[1], boundaries[2])
			var hand_power := lerpf(0.0, 0.85, progress * progress)
			hand_aura.set_silhouette_power(hand_power)
			hand_aura.set_particle_power(hand_power)
			king_aura.set_power(0.0)
			king_aura.set_silhouette_fill(0.0)
		Phase.RESPONSE, Phase.BUILDUP:
			var start: float = boundaries[2]
			var finish: float = boundaries[4]
			var progress := _range_progress(elapsed, start, finish)
			var charge := progress * progress
			var hand_power := lerpf(0.85, 1.0, progress)
			var king_power := lerpf(0.0, 0.65, progress)
			hand_aura.set_silhouette_power(hand_power)
			hand_aura.set_particle_power(hand_power)
			king_aura.set_silhouette_power(king_power)
			king_aura.set_particle_power(king_power)
			king_aura.set_silhouette_fill(0.0)
			var density := lerpf(1.0, profile.final_density_multiplier, charge)
			var speed := lerpf(1.0, profile.final_speed_multiplier, charge)
			hand_aura.set_runtime_multipliers(density, speed)
			king_aura.set_runtime_multipliers(density, speed)
		Phase.CLIMAX:
			var progress := _range_progress(elapsed, boundaries[4], boundaries[5])
			var sudden := pow(progress, 0.35)
			hand_aura.set_power(1.0)
			king_aura.set_power(1.0)
			king_aura.set_runtime_multipliers(profile.final_density_multiplier, profile.final_speed_multiplier)
			king_aura.set_silhouette_fill(sudden, Color.WHITE)
			king_sprite.self_modulate.a = sudden
			stone_sprite.visible = progress < 1.0
			if stone_sprite.material is ShaderMaterial:
				(stone_sprite.material as ShaderMaterial).set_shader_parameter("opacity", 1.0 - sudden)
