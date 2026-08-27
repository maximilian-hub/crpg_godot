extends Node
class_name ChessKingActivationSequence

signal phase_changed(phase: int)
signal elapsed_changed(seconds: float)
signal activation_completed()
signal audio_cue(cue: StringName)

enum Phase { RESET, INVOCATION, RESPONSE, BUILDUP, CLIMAX, AFTERIMAGE, COMPLETE }

var profile: Resource
var hand_root: Node2D
var hand_connection_anchor: Node2D
var king_sprite: Sprite2D
var stone_sprite: Sprite2D
var hand_aura: ChessAura2D
var king_aura: ChessAura2D
var lightning: Node2D
var audio_players: Dictionary = {}
var elapsed := 0.0
var playback_speed := 1.0
var running := false
var current_phase := Phase.RESET
var base_hand_position := Vector2.ZERO
var tremor_rng := RandomNumberGenerator.new()
var last_tremor_tick := -1
var crackle_schedule := PackedFloat32Array()
var fired_crackles: Dictionary = {}
var active_crackle_until := -1.0
var active_climax_beam_index := -1
var tremor_offset := Vector2.ZERO
var lightning_hand_offset := Vector2.ZERO
var crackle_hand_target := Vector2.ZERO
var crackle_hand_started_at := -1.0
var climax_hand_target := Vector2.ZERO


func configure(
	activation_profile: Resource,
	hand: Node2D,
	connection_anchor: Node2D,
	colored_king: Sprite2D,
	stone: Sprite2D,
	hand_energy: ChessAura2D,
	king_energy: ChessAura2D,
	lightning_effect: Node2D,
	players := {}
) -> void:
	profile = activation_profile
	hand_root = hand
	hand_connection_anchor = connection_anchor
	king_sprite = colored_king
	stone_sprite = stone
	hand_aura = hand_energy
	king_aura = king_energy
	lightning = lightning_effect
	audio_players = players
	base_hand_position = hand_root.position
	restart(false)


func play() -> void:
	if current_phase == Phase.COMPLETE:
		restart(false)
	hand_aura.set_simulation_paused(false)
	king_aura.set_simulation_paused(false)
	running = true


func pause() -> void:
	running = false
	hand_aura.set_simulation_paused(true)
	king_aura.set_simulation_paused(true)
	_pause_audio(true)


func resume() -> void:
	running = true
	hand_aura.set_simulation_paused(false)
	king_aura.set_simulation_paused(false)
	_pause_audio(false)


func restart(autoplay := true) -> void:
	running = false
	elapsed = 0.0
	current_phase = Phase.RESET
	last_tremor_tick = -1
	active_crackle_until = -1.0
	active_climax_beam_index = -1
	tremor_offset = Vector2.ZERO
	lightning_hand_offset = Vector2.ZERO
	crackle_hand_target = Vector2.ZERO
	crackle_hand_started_at = -1.0
	climax_hand_target = Vector2.ZERO
	fired_crackles.clear()
	tremor_rng.seed = profile.random_seed if profile != null else 0
	_build_crackle_schedule()
	_stop_all_audio()
	if is_instance_valid(hand_root):
		hand_root.position = base_hand_position
	if is_instance_valid(hand_aura):
		hand_aura.set_simulation_paused(false)
		hand_aura.reset_effect()
	if is_instance_valid(king_aura):
		king_aura.set_simulation_paused(false)
		king_aura.reset_effect()
	if is_instance_valid(lightning):
		lightning.clear()
	_apply_visual_state()
	phase_changed.emit(current_phase)
	elapsed_changed.emit(elapsed)
	running = autoplay


func advance_to_next_phase() -> void:
	if current_phase == Phase.RESET:
		_enter_phase(Phase.INVOCATION)
		_apply_visual_state()
		return
	var boundaries := _phase_boundaries()
	for boundary in boundaries:
		if boundary > elapsed + 0.0001:
			elapsed = boundary
			last_tremor_tick = -1
			active_crackle_until = -1.0
			lightning.clear()
			_update_phase(true)
			_apply_visual_state()
			_update_hand_motion()
			elapsed_changed.emit(elapsed)
			return


func set_playback_speed(value: float) -> void:
	playback_speed = clampf(value, 0.05, 16.0)
	if is_instance_valid(hand_aura): hand_aura.set_simulation_speed(playback_speed)
	if is_instance_valid(king_aura): king_aura.set_simulation_speed(playback_speed)


func phase_name() -> String:
	return Phase.keys()[current_phase].capitalize()


func _process(delta: float) -> void:
	if not running or profile == null:
		return
	elapsed = minf(elapsed + delta * playback_speed, profile.total_duration())
	_update_phase(false)
	_apply_visual_state()
	_update_tremor()
	_update_lightning()
	_update_hand_motion()
	elapsed_changed.emit(elapsed)
	if elapsed >= profile.total_duration() and current_phase != Phase.COMPLETE:
		_enter_phase(Phase.COMPLETE)


func _phase_boundaries() -> PackedFloat32Array:
	if profile == null:
		return PackedFloat32Array([0.0])
	var invocation_end: float = profile.invocation_duration
	var response_end: float = invocation_end + profile.response_duration
	var buildup_end: float = response_end + profile.buildup_duration
	var climax_end: float = buildup_end + profile.climax_duration
	var afterimage_end: float = climax_end + maxf(profile.afterimage_duration, profile.aura_release_duration)
	return PackedFloat32Array([0.0, invocation_end, response_end, buildup_end, climax_end, afterimage_end, profile.total_duration()])


func _phase_for_time(time: float) -> int:
	var boundaries := _phase_boundaries()
	if time < boundaries[1]: return Phase.INVOCATION
	if time < boundaries[2]: return Phase.RESPONSE
	if time < boundaries[3]: return Phase.BUILDUP
	if time < boundaries[4]: return Phase.CLIMAX
	if time < boundaries[5]: return Phase.AFTERIMAGE
	if time < boundaries[6]: return Phase.AFTERIMAGE
	return Phase.COMPLETE


func _update_phase(force_enter: bool) -> void:
	var desired := _phase_for_time(elapsed)
	if desired > current_phase:
		while current_phase < desired:
			_enter_phase(current_phase + 1)
	elif force_enter and desired != current_phase:
		_enter_phase(desired)


func _enter_phase(next_phase: int) -> void:
	if next_phase == Phase.CLIMAX and current_phase <= Phase.BUILDUP:
		# A fast playback step or frame hitch may cross the entire buildup
		# before its normal per-frame poll. Preserve every authored event that
		# belongs inside the phase before entering CLIMAX.
		_fire_crossed_buildup_crackles(profile.buildup_duration)
	current_phase = next_phase
	phase_changed.emit(current_phase)
	match current_phase:
		Phase.INVOCATION:
			_play_loop(&"hand_hum")
		Phase.RESPONSE:
			_fire_crackle(0)
			_play_loop(&"king_hum")
		Phase.BUILDUP:
			pass
		Phase.CLIMAX:
			_stop_player(&"crackle")
			climax_hand_target = _hand_shift_toward_king(profile.climax_hand_shift_distance)
			lightning_hand_offset = climax_hand_target
			_apply_hand_position()
			_show_climax_beam(0)
			_play_one_shot(&"beam")
		Phase.AFTERIMAGE:
			# The final flurry punctuates the conclusion of the full multi-beam
			# sequence. The hand stops emitting, while the awakened King settles
			# gradually toward its persistent resting aura.
			hand_aura.emit_burst(profile.burst_multiplier)
			king_aura.emit_burst(profile.burst_multiplier)
			hand_aura.set_continuous_emission_enabled(false)
			lightning.clear()
			_stop_player(&"hand_hum")
			_stop_player(&"king_hum")
			_play_one_shot(&"resolve")
		Phase.COMPLETE:
			running = false
			tremor_offset = Vector2.ZERO
			lightning_hand_offset = Vector2.ZERO
			_apply_hand_position()
			hand_aura.set_power(0.0)
			king_aura.set_silhouette_power(profile.resting_aura_power)
			king_aura.set_particle_power(profile.resting_particle_power)
			hand_aura.set_continuous_emission_enabled(false)
			king_aura.set_continuous_emission_enabled(profile.resting_particle_power > 0.0)
			king_aura.set_runtime_multipliers(profile.resting_density_multiplier, profile.resting_speed_multiplier)
			lightning.clear()
			_stop_all_audio()
			activation_completed.emit()


func _apply_visual_state() -> void:
	if profile == null or not is_instance_valid(king_sprite):
		return
	var boundaries := _phase_boundaries()
	var hand_silhouette_power := 0.0
	var hand_particle_power := 0.0
	var king_silhouette_power := 0.0
	var king_particle_power := 0.0
	var fill := 0.0
	var stone_opacity := 1.0
	var color_opacity := 0.0
	var density := 1.0
	var speed := 1.0
	match _phase_for_time(elapsed):
		Phase.INVOCATION:
			var progress := _range_progress(elapsed, boundaries[0], boundaries[1])
			hand_silhouette_power = lerpf(0.0, profile.invocation_hand_power, progress)
			# The initial hover establishes only the hand's luminous outline.
			hand_particle_power = 0.0
		Phase.RESPONSE:
			var progress := _range_progress(elapsed, boundaries[1], boundaries[2])
			hand_silhouette_power = profile.invocation_hand_power
			# RESPONSE begins with the first crackle; particles enter after that
			# punctuation instead of accompanying the initial hover.
			hand_particle_power = lerpf(0.0, profile.invocation_hand_power, progress)
			king_silhouette_power = lerpf(0.0, profile.response_king_power, progress)
			king_particle_power = king_silhouette_power
			fill = progress * 0.12
		Phase.BUILDUP:
			var progress := _range_progress(elapsed, boundaries[2], boundaries[3])
			hand_silhouette_power = lerpf(profile.invocation_hand_power, 1.0, progress)
			hand_particle_power = hand_silhouette_power
			king_silhouette_power = lerpf(profile.response_king_power, 1.0, progress)
			king_particle_power = king_silhouette_power
			fill = lerpf(0.12, 1.0, progress * progress)
			density = lerpf(1.0, profile.final_density_multiplier, progress)
			speed = lerpf(1.0, profile.final_speed_multiplier, progress)
		Phase.CLIMAX:
			var progress := _range_progress(elapsed, boundaries[3], boundaries[4])
			hand_silhouette_power = 1.0
			hand_particle_power = 1.0
			king_silhouette_power = 1.0
			king_particle_power = 1.0
			fill = 1.0
			stone_opacity = 1.0 - progress
			color_opacity = progress
			density = profile.final_density_multiplier
			speed = profile.final_speed_multiplier
		Phase.AFTERIMAGE:
			var white_fade_end: float = boundaries[4] + profile.afterimage_duration
			var aura_release_end: float = boundaries[4] + profile.aura_release_duration
			var white_progress := _range_progress(elapsed, boundaries[4], white_fade_end)
			var aura_progress := _range_progress(elapsed, boundaries[4], aura_release_end)
			var hand_fade_progress := clampf((elapsed - boundaries[4]) / maxf(profile.hand_fade_duration, 0.001), 0.0, 1.0)
			hand_silhouette_power = 1.0 - hand_fade_progress
			hand_particle_power = hand_silhouette_power
			king_silhouette_power = lerpf(1.0, profile.resting_aura_power, aura_progress)
			king_particle_power = lerpf(1.0, profile.resting_particle_power, aura_progress)
			fill = 1.0 - white_progress
			density = lerpf(profile.final_density_multiplier, profile.resting_density_multiplier, aura_progress)
			speed = lerpf(profile.final_speed_multiplier, profile.resting_speed_multiplier, aura_progress)
			stone_opacity = 0.0
			color_opacity = 1.0
		Phase.COMPLETE:
			king_silhouette_power = profile.resting_aura_power
			king_particle_power = profile.resting_particle_power
			density = profile.resting_density_multiplier
			speed = profile.resting_speed_multiplier
			stone_opacity = 0.0
			color_opacity = 1.0
	hand_aura.set_silhouette_power(hand_silhouette_power)
	hand_aura.set_particle_power(hand_particle_power)
	king_aura.set_silhouette_power(king_silhouette_power)
	king_aura.set_particle_power(king_particle_power)
	hand_aura.set_runtime_multipliers(density, speed)
	king_aura.set_runtime_multipliers(density, speed)
	king_aura.set_silhouette_fill(fill, Color.WHITE)
	king_sprite.self_modulate.a = color_opacity
	stone_sprite.visible = stone_opacity > 0.0
	if stone_sprite.material is ShaderMaterial:
		(stone_sprite.material as ShaderMaterial).set_shader_parameter("opacity", stone_opacity)


func _update_tremor() -> void:
	var boundaries := _phase_boundaries()
	if current_phase != Phase.BUILDUP:
		tremor_offset = Vector2.ZERO
		return
	var progress := _range_progress(elapsed, boundaries[2], boundaries[3])
	var tick := int(floor((elapsed - boundaries[2]) / maxf(profile.tremor_interval, 0.01)))
	if tick == last_tremor_tick:
		return
	last_tremor_tick = tick
	var ramped_progress := pow(progress, profile.tremor_ramp_exponent)
	var amplitude := maxi(int(round(profile.tremor_max_pixels * ramped_progress)), 1)
	tremor_offset = Vector2(
		tremor_rng.randi_range(-amplitude, amplitude),
		tremor_rng.randi_range(-amplitude, amplitude)
	)


func _update_hand_motion() -> void:
	var boundaries := _phase_boundaries()
	if current_phase == Phase.CLIMAX:
		lightning_hand_offset = climax_hand_target
	elif current_phase == Phase.AFTERIMAGE and not climax_hand_target.is_zero_approx():
		var return_progress := clampf((elapsed - boundaries[4]) / maxf(profile.climax_hand_return_duration, 0.01), 0.0, 1.0)
		lightning_hand_offset = climax_hand_target * (1.0 - _ease_out_cubic(return_progress))
	elif crackle_hand_started_at >= 0.0:
		var impulse_age := elapsed - crackle_hand_started_at
		if impulse_age <= profile.crackle_hand_hold_duration:
			lightning_hand_offset = crackle_hand_target
		else:
			var return_progress := clampf(
				(impulse_age - profile.crackle_hand_hold_duration) / maxf(profile.crackle_hand_return_duration, 0.01),
				0.0,
				1.0
			)
			lightning_hand_offset = crackle_hand_target * (1.0 - _ease_out_cubic(return_progress))
			if return_progress >= 1.0:
				crackle_hand_started_at = -1.0
	else:
		lightning_hand_offset = Vector2.ZERO
	_apply_hand_position()


func _apply_hand_position() -> void:
	hand_root.position = base_hand_position + lightning_hand_offset.round() + tremor_offset.round()


func _hand_shift_toward_king(distance: float) -> Vector2:
	var direction := (king_sprite.global_position - hand_connection_anchor.global_position).normalized()
	if direction.is_zero_approx() or distance <= 0.0:
		return Vector2.ZERO
	var parent := hand_root.get_parent() as Node2D
	if parent == null:
		return (direction * distance).round()
	var local_origin := parent.to_local(hand_root.global_position)
	var local_target := parent.to_local(hand_root.global_position + direction * distance)
	return (local_target - local_origin).round()


func _ease_out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - clampf(value, 0.0, 1.0), 3.0)


func _build_crackle_schedule() -> void:
	crackle_schedule.clear()
	if profile == null:
		return
	for authored_time in profile.buildup_crackle_times:
		if authored_time >= 0.0:
			crackle_schedule.append(authored_time)
	crackle_schedule.sort()


func _update_lightning() -> void:
	var boundaries := _phase_boundaries()
	if current_phase == Phase.RESPONSE:
		if elapsed > active_crackle_until:
			lightning.clear()
	elif current_phase == Phase.BUILDUP:
		var buildup_elapsed := elapsed - boundaries[2]
		_fire_crossed_buildup_crackles(buildup_elapsed)
		if elapsed > active_crackle_until:
			lightning.clear()
	elif current_phase == Phase.CLIMAX:
		var progress := _range_progress(elapsed, boundaries[3], boundaries[4])
		var beam_count: int = maxi(profile.climax_beam_count, 1)
		var beam_index := mini(int(floor(progress * beam_count)), beam_count - 1)
		if beam_index != active_climax_beam_index:
			_show_climax_beam(beam_index)
		lightning.show_strength(sin(progress * PI) * 0.35 + 0.65)


func _fire_crossed_buildup_crackles(buildup_elapsed: float) -> void:
	for index in range(crackle_schedule.size()):
		var authored_time := crackle_schedule[index]
		if authored_time < profile.buildup_duration and buildup_elapsed >= authored_time and not fired_crackles.has(index):
			fired_crackles[index] = true
			_fire_crackle(index + 1)


func _show_climax_beam(index: int) -> void:
	active_climax_beam_index = index
	# Each successive seed redraws the same connection with a new jagged path,
	# reading as one energetic beam writhing between the hand and King Piece.
	_configure_lightning(true, profile.beam_branch_count, profile.beam_width, profile.random_seed + 900 + index * 113)
	lightning.show_strength(1.0)


func _fire_crackle(index: int) -> void:
	crackle_hand_target = _hand_shift_toward_king(profile.crackle_hand_shift_distance)
	crackle_hand_started_at = elapsed
	lightning_hand_offset = crackle_hand_target
	_apply_hand_position()
	_configure_lightning(false, 0, profile.crackle_width, profile.random_seed + index * 71)
	lightning.show_strength(1.0)
	active_crackle_until = elapsed + profile.crackle_duration
	_play_one_shot(&"crackle")


func _configure_lightning(beam: bool, branch_count: int, line_width: float, seed: int) -> void:
	var start := lightning.to_local(hand_connection_anchor.global_position)
	var finish := lightning.to_local(king_sprite.global_position)
	lightning.width = line_width
	lightning.checker_size = profile.lightning_checker_size
	lightning.edge_roughness = profile.rift_edge_roughness
	lightning.curve_max = profile.lightning_curve_max
	lightning.configure_path(start, finish, profile.lightning_segment_length, profile.lightning_displacement, seed, beam, branch_count)


func _range_progress(value: float, start: float, finish: float) -> float:
	return clampf(inverse_lerp(start, finish, value), 0.0, 1.0) if finish > start else 1.0


func _play_loop(cue: StringName) -> void:
	audio_cue.emit(cue)
	var player := audio_players.get(cue) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.play()


func _play_one_shot(cue: StringName) -> void:
	audio_cue.emit(cue)
	var player := audio_players.get(cue) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.play()


func _stop_player(cue: StringName) -> void:
	var player := audio_players.get(cue) as AudioStreamPlayer
	if player != null:
		player.stop()


func _stop_all_audio() -> void:
	for player in audio_players.values():
		if player is AudioStreamPlayer:
			player.stop()


func _pause_audio(paused: bool) -> void:
	for player in audio_players.values():
		if player is AudioStreamPlayer:
			player.stream_paused = paused
