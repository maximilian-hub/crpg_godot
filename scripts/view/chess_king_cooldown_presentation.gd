extends Node2D
class_name ChessKingCooldownPresentation

const Mote := preload("res://scripts/view/chess_cooldown_mote_2d.gd")
const SelectionOrb := preload("res://scripts/view/chess_selection_orb_2d.gd")

var board: ChessBoardView
var king: PieceView
var aura: ChessAura2D
var profile: ChessKingCooldownPresentationProfile
var aura_profile: ChessAuraProfile
var motes: Array[ChessCooldownMote2D] = []
var selection_orb: ChessSelectionOrb2D
var authoritative_count := 0
var awakened := true
var selected := false
var targeting := false
var aura_suppressed := false
var elapsed := 0.0
var next_identity := 1
var resting_silhouette := 0.0
var resting_particles := 0.0
var resting_density := 1.0
var resting_speed := 1.0
var pulse_tween: Tween
var pulse_base_scale := Vector2.ONE
var has_active_ability := true
var charge_player := AudioStreamPlayer.new()
var absorption_player := AudioStreamPlayer.new()
var completion_player := AudioStreamPlayer.new()
var selection_player := AudioStreamPlayer.new()


func configure(board_view: ChessBoardView, king_view: PieceView, king_aura: ChessAura2D, tuning: ChessKingCooldownPresentationProfile, colors: ChessAuraProfile, cooldown: int, baseline: Dictionary) -> void:
	board = board_view
	king = king_view
	aura = king_aura
	profile = tuning if tuning != null else ChessKingCooldownPresentationProfile.new()
	aura_profile = colors if colors != null else ChessAuraProfile.new()
	has_active_ability = king.model != null and king.model is KingPiece and (king.model as KingPiece).has_active_ability()
	resting_silhouette = float(baseline.get("silhouette", 0.0))
	resting_particles = float(baseline.get("particles", 0.0))
	resting_density = float(baseline.get("density", 1.0))
	resting_speed = float(baseline.get("speed", 1.0))
	for player in [charge_player, absorption_player, completion_player, selection_player]: add_child(player)
	selection_orb = SelectionOrb.new()
	selection_orb.z_as_relative = false
	selection_orb.visible = false
	add_child(selection_orb)
	selection_orb.configure(profile.selection_orb_size * board.get_world_scale(), profile.selection_orb_opacity, profile.selection_orb_speed, aura_profile.core_color, aura_profile.accent_color)
	sync_immediate(cooldown)
	set_process(true)


func sync_immediate(count: int) -> void:
	authoritative_count = maxi(count, 0)
	_clear_motes()
	for index in range(authoritative_count):
		var mote := _create_mote()
		mote.motion_state = Mote.MotionState.ORBITING
		motes.append(mote)
	_assign_formation(true)
	for mote in motes:
		mote.position = _desired_position(mote)
		mote.set_visual_charge(0.0)
	_apply_visibility_and_aura()


func set_cooldown(count: int, animate := true) -> void:
	var previous := authoritative_count
	authoritative_count = maxi(count, 0)
	if not animate:
		sync_immediate(authoritative_count)
		return
	_reconcile_motes()
	if authoritative_count < previous:
		_play(charge_player, profile.charge_sound, profile.charge_volume_db)
	_apply_visibility_and_aura()


func set_awakened(value: bool) -> void:
	awakened = value
	_apply_visibility_and_aura()


func set_selected(value: bool) -> void:
	var was_visible := selection_orb.visible if is_instance_valid(selection_orb) else false
	selected = value
	_update_orb()
	if selection_orb.visible and not was_visible:
		_play(selection_player, profile.selection_sound, profile.selection_volume_db)


func set_targeting(value: bool) -> void:
	targeting = value
	_update_orb()


func set_aura_suppressed(value: bool) -> void:
	aura_suppressed = value
	if not value:
		_apply_persistent_aura()


func refresh_profile() -> void:
	if profile == null or not is_instance_valid(board): return
	for mote in motes:
		if is_instance_valid(mote):
			mote.configure(mote.identity, aura_profile.core_color.lerp(aura_profile.accent_color, 0.35), profile.mote_size * board.get_world_scale(), profile.mote_opacity)
	if is_instance_valid(selection_orb):
		selection_orb.configure(profile.selection_orb_size * board.get_world_scale(), profile.selection_orb_opacity, profile.selection_orb_speed, aura_profile.core_color, aura_profile.accent_color)
	_apply_visibility_and_aura()


func active_mote_count() -> int:
	var count := 0
	for mote in motes:
		if is_instance_valid(mote) and mote.motion_state != Mote.MotionState.ABSORBING: count += 1
	return count


func absorbing_mote_count() -> int:
	var count := 0
	for mote in motes:
		if is_instance_valid(mote) and mote.motion_state == Mote.MotionState.ABSORBING: count += 1
	return count


func shutdown() -> void:
	set_process(false)
	if pulse_tween != null and pulse_tween.is_valid():
		pulse_tween.kill()
		if is_instance_valid(king) and is_instance_valid(king.sprite): king.sprite.scale = pulse_base_scale
	for player in [charge_player, absorption_player, completion_player, selection_player]: player.stop()
	_clear_motes()
	if is_instance_valid(selection_orb): selection_orb.visible = false


func _process(delta: float) -> void:
	if not awakened or not is_instance_valid(king) or not is_instance_valid(board):
		return
	var scaled_delta := delta / maxf(board.animation_duration_scale, 0.01)
	elapsed += scaled_delta
	selection_orb.duration_scale = board.animation_duration_scale
	_update_motes(scaled_delta)
	_update_orb_position()
	if has_active_ability and authoritative_count == 0 and not aura_suppressed:
		_apply_persistent_aura()


func _reconcile_motes() -> void:
	var active: Array[ChessCooldownMote2D] = []
	var absorbing: Array[ChessCooldownMote2D] = []
	for mote in motes:
		if mote.motion_state == Mote.MotionState.ABSORBING: absorbing.append(mote)
		else: active.append(mote)
	while active.size() < authoritative_count and not absorbing.is_empty():
		var reclaimed: ChessCooldownMote2D = absorbing.pop_front() as ChessCooldownMote2D
		reclaimed.motion_state = Mote.MotionState.ORBITING
		reclaimed.transition_elapsed = 0.0
		reclaimed.transition_started = false
		reclaimed.velocity = Vector2.ZERO
		reclaimed.set_visual_charge(0.0)
		active.append(reclaimed)
	while active.size() < authoritative_count:
		var mote := _create_mote()
		mote.position = _anchor_position()
		mote.motion_state = Mote.MotionState.EMERGING
		mote.transition_duration = profile.release_duration
		motes.append(mote)
		active.append(mote)
	while active.size() > authoritative_count:
		var mote: ChessCooldownMote2D = active.pop_back() as ChessCooldownMote2D
		mote.motion_state = Mote.MotionState.ABSORBING
		mote.transition_elapsed = 0.0
		mote.transition_started = false
		mote.transition_delay = float(absorbing.size()) * profile.absorption_stagger
		mote.transition_duration = profile.absorption_duration
		mote.transition_start = mote.position
		absorbing.append(mote)
	_assign_formation(false)


func _assign_formation(immediate: bool) -> void:
	var active: Array[ChessCooldownMote2D] = []
	for mote in motes:
		if mote.motion_state != Mote.MotionState.ABSORBING: active.append(mote)
	active.sort_custom(func(a, b): return a.identity < b.identity)
	for index in range(active.size()):
		var ring_start := (index / profile.motes_per_ring) * profile.motes_per_ring
		var ring_count := mini(profile.motes_per_ring, active.size() - ring_start)
		active[index].target_angle = -PI * 0.5 + TAU * float(index - ring_start) / float(maxi(ring_count, 1))
		if immediate: active[index].formation_angle = active[index].target_angle


func _update_motes(delta: float) -> void:
	for index in range(motes.size() - 1, -1, -1):
		var mote := motes[index]
		if not is_instance_valid(mote):
			motes.remove_at(index)
			continue
		if mote.motion_state == Mote.MotionState.ABSORBING:
			mote.transition_elapsed += delta
			if mote.transition_elapsed <= mote.transition_delay:
				_follow(mote, _desired_position(mote), delta)
				continue
			if not mote.transition_started:
				_begin_absorption_curve(mote)
			var p := clampf((mote.transition_elapsed - mote.transition_delay) / maxf(mote.transition_duration, 0.001), 0.0, 1.0)
			mote.set_visual_charge(smoothstep(0.0, 0.45, p))
			var eased := smoothstep(0.0, 1.0, p)
			var anchor := _absorption_anchor_position()
			mote.position = _cubic_bezier(mote.transition_start, mote.transition_control_a, anchor + mote.transition_control_b_offset, anchor, eased).round()
			mote.scale = Vector2.ONE * (1.0 - p * 0.45)
			if p >= 1.0:
				motes.remove_at(index)
				mote.queue_free()
				_play(absorption_player, profile.absorption_sound, profile.absorption_volume_db)
				_pulse_king()
				if authoritative_count == 0 and not _has_absorbing_motes():
					_play(completion_player, profile.completion_sound, profile.completion_volume_db)
			continue
		mote.formation_angle = lerp_angle(mote.formation_angle, mote.target_angle, 1.0 - exp(-profile.formation_angular_smoothing * delta))
		if mote.motion_state == Mote.MotionState.EMERGING:
			mote.transition_elapsed += delta
			if mote.transition_elapsed >= mote.transition_duration: mote.motion_state = Mote.MotionState.ORBITING
		_follow(mote, _desired_position(mote), delta)
		mote.set_visual_charge(0.0)
		var anchor_y := _anchor_position().y
		mote.z_as_relative = false
		mote.z_index = king.z_index + (1 if mote.position.y >= anchor_y else -1)


func _follow(mote: ChessCooldownMote2D, desired: Vector2, delta: float) -> void:
	var offset := desired - mote.position
	if offset.length() < 0.25:
		mote.position = desired.round()
		mote.velocity = Vector2.ZERO
		return
	var speed := minf(profile.follow_max_speed, profile.follow_base_speed + offset.length() * profile.follow_distance_gain)
	var desired_velocity := offset.normalized() * speed
	mote.velocity = mote.velocity.move_toward(desired_velocity, profile.follow_acceleration * delta)
	var damping := 1.0 - exp(-profile.arrival_smoothing * delta / maxf(offset.length(), 1.0))
	mote.velocity = mote.velocity.lerp(desired_velocity, damping)
	mote.position += mote.velocity * delta


func _begin_absorption_curve(mote: ChessCooldownMote2D) -> void:
	var anchor := _absorption_anchor_position()
	var radial := mote.position - anchor
	var radius := maxf(radial.length(), 1.0)
	var orbit_sign := signf(profile.orbit_speed)
	if is_zero_approx(orbit_sign): orbit_sign = 1.0
	var tangent := Vector2(-radial.y, radial.x).normalized() * orbit_sign
	var travel_direction := mote.velocity.normalized() if mote.velocity.length() > 1.0 else tangent
	var side := signf(travel_direction.x)
	if is_zero_approx(side): side = signf(tangent.x)
	if is_zero_approx(side): side = 1.0
	var outward_distance := profile.absorption_outward_distance * board.get_world_scale() * profile.absorption_curve_strength
	mote.transition_start = mote.position
	# Preserve the mote's current travel first, then pull the far control point
	# beyond the selected side of the silhouette. The final tangent approaches
	# BodyAnchor laterally, keeping the last part of the absorption readable.
	mote.transition_control_a = mote.position + travel_direction * maxf(radius * 0.6, outward_distance * 0.55)
	mote.transition_control_b_offset = Vector2(side * outward_distance, 0.0)
	mote.transition_started = true
	mote.velocity = Vector2.ZERO
	mote.z_as_relative = false
	mote.z_index = king.z_index + 1


static func _cubic_bezier(start: Vector2, control_a: Vector2, control_b: Vector2, finish: Vector2, progress: float) -> Vector2:
	var inverse := 1.0 - progress
	return inverse * inverse * inverse * start + 3.0 * inverse * inverse * progress * control_a + 3.0 * inverse * progress * progress * control_b + progress * progress * progress * finish


func _desired_position(mote: ChessCooldownMote2D) -> Vector2:
	var active_index := 0
	for candidate in motes:
		if candidate == mote: break
		if candidate.motion_state != Mote.MotionState.ABSORBING: active_index += 1
	var ring := active_index / maxi(profile.motes_per_ring, 1)
	var radius := (profile.orbit_radius + Vector2.ONE * profile.ring_spacing * float(ring)) * board.get_world_scale()
	var angle := mote.formation_angle + elapsed * profile.orbit_speed
	var variation := 1.0 + sin(float(mote.identity) * 7.17) * profile.hover_variation
	var hover := sin(elapsed * profile.hover_frequency * TAU * variation + mote.hover_phase) * profile.hover_amplitude * board.get_world_scale()
	return _anchor_position() + Vector2(cos(angle) * radius.x, sin(angle) * radius.y + hover)


func _anchor_position() -> Vector2:
	if not is_instance_valid(king): return Vector2.ZERO
	var per_piece: Vector2 = king.art_profile.cooldown_anchor_offset if king.art_profile != null else Vector2.ZERO
	return king.get_anchor_position_in(board, king.get_body_anchor()) + (profile.anchor_offset + per_piece) * board.get_world_scale()


func _absorption_anchor_position() -> Vector2:
	if not is_instance_valid(king): return Vector2.ZERO
	# This is the same base point used by Spike Burst. Its separately authored
	# projectile launch_offset is currently zero in the published profile.
	return king.get_anchor_position_in(board, king.get_body_anchor())


func _update_orb_position() -> void:
	if not is_instance_valid(selection_orb) or not is_instance_valid(king) or not is_instance_valid(board): return
	var per_piece: Vector2 = king.art_profile.selection_orb_offset if king.art_profile != null else Vector2.ZERO
	selection_orb.position = (_anchor_position() + (profile.selection_orb_offset + per_piece) * board.get_world_scale()).round()
	selection_orb.z_index = king.z_index + 8


func _update_orb() -> void:
	if not is_instance_valid(selection_orb): return
	selection_orb.visible = is_instance_valid(king) and awakened and has_active_ability and authoritative_count == 0 and selected and not targeting
	_update_orb_position()


func _apply_visibility_and_aura() -> void:
	visible = awakened and has_active_ability
	_update_orb()
	_apply_persistent_aura()


func _apply_persistent_aura() -> void:
	if aura_suppressed or not is_instance_valid(aura): return
	if not awakened:
		aura.set_power(0.0)
		return
	# The model becomes ready as soon as its count reaches zero, but the aura's
	# presentation beat belongs to the final mote making contact with the King.
	if authoritative_count > 0 or _has_absorbing_motes() or not has_active_ability:
		aura.set_silhouette_power(resting_silhouette)
		aura.set_particle_power(resting_particles)
		aura.set_runtime_multipliers(resting_density, resting_speed)
		return
	var period := maxf(profile.ready_brightening_period, 0.1)
	var phase := fmod(elapsed, period) / period
	var width := clampf(profile.ready_brightening_fraction, 0.05, 1.0)
	var distance := minf(phase, 1.0 - phase)
	var pulse := 1.0 - smoothstep(0.0, width * 0.5, distance)
	aura.set_silhouette_power(clampf(maxf(resting_silhouette, profile.ready_silhouette_power) + pulse * profile.ready_brightening_intensity, 0.0, 1.0))
	aura.set_particle_power(maxf(resting_particles, profile.ready_particle_power))
	aura.set_runtime_multipliers(maxf(resting_density, profile.ready_density_multiplier), maxf(resting_speed, profile.ready_speed_multiplier))


func _create_mote() -> ChessCooldownMote2D:
	var mote := Mote.new() as ChessCooldownMote2D
	mote.z_as_relative = false
	add_child(mote)
	mote.configure(next_identity, aura_profile.core_color.lerp(aura_profile.accent_color, 0.35), profile.mote_size * board.get_world_scale(), profile.mote_opacity)
	next_identity += 1
	return mote


func _pulse_king() -> void:
	if aura_suppressed or not is_instance_valid(king) or not is_instance_valid(king.sprite): return
	if pulse_tween != null and pulse_tween.is_valid():
		pulse_tween.kill()
		king.sprite.scale = pulse_base_scale
	pulse_base_scale = king.sprite.scale
	var peak := pulse_base_scale * profile.pulse_scale
	pulse_tween = create_tween()
	pulse_tween.tween_property(king.sprite, "scale", peak, profile.pulse_duration * board.animation_duration_scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(king.sprite, "scale", pulse_base_scale, profile.pulse_duration * board.animation_duration_scale * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _has_absorbing_motes() -> bool:
	for mote in motes:
		if mote.motion_state == Mote.MotionState.ABSORBING: return true
	return false


func _clear_motes() -> void:
	for mote in motes:
		if is_instance_valid(mote): mote.queue_free()
	motes.clear()


func _play(player: AudioStreamPlayer, stream: AudioStream, volume_db: float) -> void:
	if stream == null: return
	player.stream = stream
	player.volume_db = volume_db
	player.play()
