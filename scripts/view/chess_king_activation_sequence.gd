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
	var afterimage_end: float = climax_end + profile.afterimage_duration
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
			_show_climax_beam(0)
			hand_aura.emit_burst(profile.burst_multiplier)
			king_aura.emit_burst(profile.burst_multiplier)
			# The beam and final flurry are one climax event. Stop continuous
			# emission here while allowing the burst particles to finish living.
			hand_aura.set_continuous_emission_enabled(false)
			king_aura.set_continuous_emission_enabled(false)
			_play_one_shot(&"beam")
		Phase.AFTERIMAGE:
			hand_root.position = base_hand_position
			lightning.clear()
			_stop_player(&"hand_hum")
			_stop_player(&"king_hum")
			_play_one_shot(&"resolve")
		Phase.COMPLETE:
			running = false
			hand_root.position = base_hand_position
			hand_aura.set_power(0.0)
			king_aura.set_power(0.0)
			hand_aura.set_continuous_emission_enabled(false)
			king_aura.set_continuous_emission_enabled(false)
			lightning.clear()
			_stop_all_audio()
			activation_completed.emit()


func _apply_visual_state() -> void:
	if profile == null or not is_instance_valid(king_sprite):
		return
	var boundaries := _phase_boundaries()
	var hand_power := 0.0
	var king_power := 0.0
	var fill := 0.0
	var stone_opacity := 1.0
	var color_opacity := 0.0
	var density := 1.0
	var speed := 1.0
	match _phase_for_time(elapsed):
		Phase.INVOCATION:
			var progress := _range_progress(elapsed, boundaries[0], boundaries[1])
			hand_power = lerpf(0.0, profile.invocation_hand_power, progress)
		Phase.RESPONSE:
			var progress := _range_progress(elapsed, boundaries[1], boundaries[2])
			hand_power = profile.invocation_hand_power
			king_power = lerpf(0.0, profile.response_king_power, progress)
			fill = progress * 0.12
		Phase.BUILDUP:
			var progress := _range_progress(elapsed, boundaries[2], boundaries[3])
			hand_power = lerpf(profile.invocation_hand_power, 1.0, progress)
			king_power = lerpf(profile.response_king_power, 1.0, progress)
			fill = lerpf(0.12, 1.0, progress * progress)
			density = lerpf(1.0, profile.final_density_multiplier, progress)
			speed = lerpf(1.0, profile.final_speed_multiplier, progress)
		Phase.CLIMAX:
			var progress := _range_progress(elapsed, boundaries[3], boundaries[4])
			hand_power = 1.0
			king_power = 1.0
			fill = 1.0
			stone_opacity = 1.0 - progress
			color_opacity = progress
			density = profile.final_density_multiplier
			speed = profile.final_speed_multiplier
		Phase.AFTERIMAGE:
			var progress := _range_progress(elapsed, boundaries[4], boundaries[5])
			var hand_fade_progress := clampf((elapsed - boundaries[4]) / maxf(profile.hand_fade_duration, 0.001), 0.0, 1.0)
			hand_power = 1.0 - hand_fade_progress
			fill = 1.0 - progress
			stone_opacity = 0.0
			color_opacity = 1.0
		Phase.COMPLETE:
			stone_opacity = 0.0
			color_opacity = 1.0
	hand_aura.set_power(hand_power)
	king_aura.set_power(king_power)
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
		if current_phase >= Phase.CLIMAX:
			hand_root.position = base_hand_position
		return
	var progress := _range_progress(elapsed, boundaries[2], boundaries[3])
	if progress < profile.tremor_start_fraction:
		return
	var tick := int(floor((elapsed - boundaries[2]) / maxf(profile.tremor_interval, 0.01)))
	if tick == last_tremor_tick:
		return
	last_tremor_tick = tick
	var amplitude := maxi(int(round(profile.tremor_max_pixels * progress)), 1)
	hand_root.position = base_hand_position + Vector2(
		tremor_rng.randi_range(-amplitude, amplitude),
		tremor_rng.randi_range(-amplitude, amplitude)
	)


func _build_crackle_schedule() -> void:
	crackle_schedule.clear()
	if profile == null or profile.secondary_crackle_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.random_seed + 500
	for index in range(profile.secondary_crackle_count):
		var base_fraction := float(index + 1) / float(profile.secondary_crackle_count + 1)
		var jitter := rng.randf_range(-0.08, 0.08)
		crackle_schedule.append(clampf(base_fraction + jitter, 0.08, 0.92))
	crackle_schedule.sort()


func _update_lightning() -> void:
	var boundaries := _phase_boundaries()
	if current_phase == Phase.RESPONSE:
		if elapsed > active_crackle_until:
			lightning.clear()
	elif current_phase == Phase.BUILDUP:
		var progress := _range_progress(elapsed, boundaries[2], boundaries[3])
		for index in range(crackle_schedule.size()):
			if progress >= crackle_schedule[index] and not fired_crackles.has(index):
				fired_crackles[index] = true
				_fire_crackle(index + 1)
		if elapsed > active_crackle_until:
			lightning.clear()
	elif current_phase == Phase.CLIMAX:
		var progress := _range_progress(elapsed, boundaries[3], boundaries[4])
		var beam_count: int = maxi(profile.climax_beam_count, 1)
		var beam_index := mini(int(floor(progress * beam_count)), beam_count - 1)
		if beam_index != active_climax_beam_index:
			_show_climax_beam(beam_index)
		lightning.show_strength(sin(progress * PI) * 0.35 + 0.65)


func _show_climax_beam(index: int) -> void:
	active_climax_beam_index = index
	# Each successive seed redraws the same connection with a new jagged path,
	# reading as one energetic beam writhing between the hand and King Piece.
	_configure_lightning(true, profile.beam_branch_count, profile.beam_width, profile.random_seed + 900 + index * 113)
	lightning.show_strength(1.0)


func _fire_crackle(index: int) -> void:
	_configure_lightning(false, 0, profile.crackle_width, profile.random_seed + index * 71)
	lightning.show_strength(1.0)
	active_crackle_until = elapsed + profile.crackle_duration
	_play_one_shot(&"crackle")


func _configure_lightning(beam: bool, branch_count: int, line_width: float, seed: int) -> void:
	var start := lightning.to_local(hand_connection_anchor.global_position)
	var finish := lightning.to_local(king_sprite.global_position)
	lightning.width = line_width
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
