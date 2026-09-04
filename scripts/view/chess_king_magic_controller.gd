extends Node
class_name ChessKingMagicController

signal capture_impact(defender: PieceView)

const KingPresentationProfile = preload("res://scripts/view/chess_king_presentation_profile.gd")
const PresentationTransform = preload("res://scripts/view/chess_presentation_transform.gd")
const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")
const HoodActivationSequence := preload("res://scripts/view/chess_hood_activation_sequence.gd")

## Runtime owner for one King's persistent aura and self-propelled actions.
var board: ChessBoardView
var hand: ChessHandRig
var king: PieceView
var profile: Resource
var resolved_aura_profile: ChessAuraProfile
var resolved_aura_mode := ChessAura2D.AuraMode.HYBRID
var king_aura: ChessAura2D
var hand_aura: ChessAura2D
var activation_sequence: ChessKingActivationSequence
var lightning: ChessLightning2D
var connection_anchor: Marker2D
var stone_sprite: Sprite2D
var running := false
var rng := RandomNumberGenerator.new()
var _gesture_direction := Vector2.RIGHT
var _hand_gesture_running := false
var _command_reached := false
var _king_move_released := false
signal hand_command_reached()
signal king_move_released()
signal hand_gesture_completed()


func configure(board_view: ChessBoardView, hand_rig: ChessHandRig, king_view: PieceView, king_profile: Resource, king_type_id: StringName = &"classic_king") -> void:
	board = board_view
	hand = hand_rig
	king = king_view
	profile = king_profile if king_profile != null else KingPresentationProfile.new()
	profile.ensure_defaults()
	var aura_entry: Resource = profile.resolve_aura_entry(king_type_id)
	resolved_aura_profile = aura_entry.aura_profile if aura_entry != null else profile.aura_profile
	resolved_aura_mode = aura_entry.aura_mode if aura_entry != null else profile.aura_mode
	rng.randomize()
	_build_effects()


func _build_effects() -> void:
	king_aura = ChessAura2D.new()
	king_aura.profile = resolved_aura_profile.duplicate(true)
	king_aura.mode = resolved_aura_mode
	add_child(king_aura)
	king_aura.bind_targets([king.sprite])
	king_aura.set_silhouette_power(profile.activation_profile.resting_aura_power)
	king_aura.set_particle_power(profile.activation_profile.resting_particle_power)
	king_aura.set_runtime_multipliers(profile.activation_profile.resting_density_multiplier, profile.activation_profile.resting_speed_multiplier)
	if is_instance_valid(hand) and hand.can_animate():
		hand_aura = ChessAura2D.new()
		hand_aura.profile = resolved_aura_profile.duplicate(true)
		hand_aura.mode = resolved_aura_mode
		add_child(hand_aura)
		hand.bind_aura(hand_aura)
		hand_aura.set_power(0.0)


func refresh_geometry() -> void:
	if activation_sequence == null or activation_sequence.running or not is_instance_valid(hand) or not is_instance_valid(king):
		return
	var effective_scale := board.get_world_scale() * hand.art_scale_multiplier
	hand.scale = Vector2.ONE * effective_scale
	activation_sequence.base_hand_position = king.position + PresentationTransform.king_hover_offset(
		activation_sequence.profile.hand_hover_offset,
		hand.seat,
		hand.visual_mirrored
	)
	activation_sequence.hand_rest_position = hand._offscreen_rest_position(effective_scale)
	activation_sequence.mirror_hand_motion = hand.visual_mirrored != (hand.seat == ChessHandRig.Seat.FAR)


func prepare_for_activation() -> void:
	if not is_instance_valid(hand) or not hand.can_animate():
		return
	if activation_sequence == null:
		_build_activation_sequence()
	else:
		activation_sequence.restart(false)
	refresh_geometry()


func play_activation(playback_speed := 1.0) -> void:
	if not is_instance_valid(hand) or not hand.can_animate() or running:
		return
	if activation_sequence == null:
		_build_activation_sequence()
	refresh_geometry()
	activation_sequence.set_playback_speed(playback_speed)
	running = true
	activation_sequence.play()
	await activation_sequence.activation_completed
	running = false


func finish_activation_immediately() -> void:
	if activation_sequence != null and activation_sequence.running:
		activation_sequence.complete_immediately()
	running = false


func _build_activation_sequence() -> void:
	stone_sprite = Sprite2D.new()
	stone_sprite.texture = king.sprite.texture
	stone_sprite.centered = king.sprite.centered
	stone_sprite.offset = king.sprite.offset
	var stone_material := ShaderMaterial.new()
	stone_material.shader = STONE_SHADER
	stone_sprite.material = stone_material
	king.sprite.add_child(stone_sprite)
	connection_anchor = Marker2D.new()
	connection_anchor.position = hand.get_connection_anchor_position()
	hand.add_child(connection_anchor)
	lightning = ChessLightning2D.new()
	lightning.z_index = ChessHandRig.ACTIVE_PIECE_Z
	add_child(lightning)
	activation_sequence = HoodActivationSequence.new() if profile.activation_choreography == ChessKingPresentationProfile.ActivationChoreography.HOOD_DECISIVE else ChessKingActivationSequence.new()
	add_child(activation_sequence)
	var effective_scale := board.get_world_scale() * hand.art_scale_multiplier
	hand.scale = Vector2.ONE * effective_scale
	hand.position = king.position + PresentationTransform.king_hover_offset(profile.activation_profile.hand_hover_offset, hand.seat, hand.visual_mirrored)
	activation_sequence.configure(
		profile.activation_profile.duplicate(true), hand, connection_anchor, king.sprite, stone_sprite,
		hand_aura, king_aura, lightning, {}, hand._offscreen_rest_position(effective_scale), 1.0,
		hand.visual_mirrored != (hand.seat == ChessHandRig.Seat.FAR)
	)


func play_move(from: Vector2i, to: Vector2i) -> void:
	await _begin_gesture(from, to)
	king.coordinate = to
	await _travel_king(board.grid_to_screen(to.x, to.y), profile.movement_profile.travel_duration)
	board._update_piece_depth(king)
	await _end_gesture()


func play_capture(from: Vector2i, to: Vector2i, defender: PieceView) -> void:
	await _begin_gesture(from, to)
	king.coordinate = to
	await _travel_with_knockoff(board.grid_to_screen(to.x, to.y), defender, from, to)
	board._update_piece_depth(king)
	await _end_gesture()


func play_attack(_from: Vector2i, target: Vector2i, contact_callback := Callable()) -> void:
	await _begin_gesture(_from, target)
	var origin := king.position
	await _travel_king(board.grid_to_screen(target.x, target.y), profile.movement_profile.travel_duration)
	if contact_callback.is_valid(): contact_callback.call()
	await _travel_king(origin, profile.movement_profile.attack_rebound_duration)
	board._update_piece_depth(king)
	await _end_gesture()


func _begin_gesture(from: Vector2i, to: Vector2i) -> void:
	running = true
	var move: Resource = profile.movement_profile
	if is_instance_valid(hand) and hand.can_animate():
		var effective_scale := board.get_world_scale() * hand.art_scale_multiplier
		hand.scale = Vector2.ONE * effective_scale
		hand._apply_pose(false)
		hand.set_magical_foreground(true, self)
		if is_instance_valid(hand_aura):
			hand_aura.set_layer_z(ChessHandRig.MAGIC_AURA_Z, ChessHandRig.MAGIC_AURA_Z)
		hand.visible = true
		hand.position = hand._offscreen_rest_position(effective_scale)
		var base_hover := king.position + PresentationTransform.king_hover_offset(move.hand_hover_offset, hand.seat)
		var points := gesture_points(
			board.grid_to_screen(from.x, from.y), board.grid_to_screen(to.x, to.y), base_hover,
			move.gesture_corridor_clearance * board.get_world_scale(), move.gesture_sweep_distance * board.get_world_scale()
		)
		_gesture_direction = (board.grid_to_screen(to.x, to.y) - board.grid_to_screen(from.x, from.y)).normalized()
		if _gesture_direction.is_zero_approx(): _gesture_direction = Vector2.RIGHT
		await _tween_position(hand, points[0], move.hand_approach_duration)
		hand_aura.set_silhouette_power(move.hand_silhouette_power)
		hand_aura.set_particle_power(move.hand_particle_power)
	king_aura.set_silhouette_power(move.king_silhouette_power)
	king_aura.set_particle_power(move.king_particle_power)
	if move.gesture_lock_duration > 0.0:
		await get_tree().create_timer(move.gesture_lock_duration * board.animation_duration_scale).timeout
	if is_instance_valid(hand) and hand.can_animate():
		var base_hover := king.position + PresentationTransform.king_hover_offset(move.hand_hover_offset, hand.seat)
		var points := gesture_points(board.grid_to_screen(from.x, from.y), board.grid_to_screen(to.x, to.y), base_hover, move.gesture_corridor_clearance * board.get_world_scale(), move.gesture_sweep_distance * board.get_world_scale())
		_start_unified_hand_gesture(points[0], points[1], hand._offscreen_rest_position(board.get_world_scale() * hand.art_scale_multiplier))
		_start_king_move_delay(move.king_move_delay)
		if not _king_move_released:
			await king_move_released
	else:
		await get_tree().create_timer(move.king_move_delay * board.animation_duration_scale).timeout


func _end_gesture() -> void:
	var move: Resource = profile.movement_profile
	king_aura.set_silhouette_power(profile.activation_profile.resting_aura_power)
	king_aura.set_particle_power(profile.activation_profile.resting_particle_power)
	if _hand_gesture_running:
		await hand_gesture_completed
	if move.settle_duration > 0.0:
		await get_tree().create_timer(move.settle_duration * board.animation_duration_scale).timeout
	running = false


func _start_unified_hand_gesture(lock: Vector2, swipe_end: Vector2, rest: Vector2) -> void:
	if _hand_gesture_running:
		return
	_hand_gesture_running = true
	_command_reached = false
	var move: Resource = profile.movement_profile
	var path := build_gesture_path(lock, swipe_end, rest, move.gesture_minimum_turn_radius * board.get_world_scale())
	build_path_timing(path, move.gesture_launch_speed, move.gesture_turn_speed, move.gesture_exit_speed)
	var initial_silhouette: float = move.hand_silhouette_power
	var initial_particles: float = move.hand_particle_power
	var tween := create_tween()
	tween.tween_method(func(progress: float):
		var sample := sample_timed_path(path, progress)
		hand.position = sample.position
		if not _command_reached and sample.distance + 0.01 >= float(path.straight_length):
			_command_reached = true
			hand_command_reached.emit()
		var curve_progress := clampf((sample.distance - float(path.straight_length)) / maxf(float(path.total_length) - float(path.straight_length), 0.001), 0.0, 1.0)
		var aura_factor := 1.0 - smoothstep(0.0, 1.0, curve_progress)
		hand_aura.set_silhouette_power(initial_silhouette * aura_factor)
		hand_aura.set_particle_power(initial_particles * aura_factor)
	, 0.0, 1.0, move.gesture_duration * board.animation_duration_scale)
	await tween.finished
	if not _command_reached:
		_command_reached = true
		hand_command_reached.emit()
	hand.position = rest
	hand_aura.set_power(0.0)
	hand.visible = false
	hand.set_magical_foreground(false, self)
	hand_aura.set_layer_z(ChessHandRig.GRIP_BACK_Z - 1, ChessHandRig.ARM_FOREGROUND_Z + 1)
	_hand_gesture_running = false
	hand_gesture_completed.emit()


func _start_king_move_delay(delay: float) -> void:
	_king_move_released = false
	if delay > 0.0:
		await get_tree().create_timer(delay * board.animation_duration_scale).timeout
	_king_move_released = true
	king_move_released.emit()


func _travel_king(target: Vector2, duration: float) -> void:
	var start := king.position
	var original_z := king.z_index
	king.z_index = ChessHandRig.ACTIVE_PIECE_Z
	var tween := create_tween()
	tween.tween_method(func(progress: float): king.position = _arc(start, target, progress, profile.movement_profile.lift_height), 0.0, 1.0, duration * board.animation_duration_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	king.position = target
	king.z_index = original_z


func _travel_with_knockoff(target: Vector2, defender: PieceView, from: Vector2i, to: Vector2i) -> void:
	if not is_instance_valid(defender):
		await _travel_king(target, profile.movement_profile.travel_duration)
		return
	var move: Resource = profile.movement_profile
	var king_start := king.position
	var defender_start := defender.position
	var world_scale := board.get_world_scale()
	var knockoff := build_ballistic_knockoff(
		king_start, target, defender_start, board.get_viewport_rect().size,
		piece_visual_radius(defender), move.knockoff_horizontal_speed * world_scale,
		move.knockoff_upward_speed * world_scale, move.knockoff_gravity * world_scale, rng)
	var side: int = knockoff.side
	var king_duration: float = move.travel_duration
	var knock_duration: float = knockoff.duration
	var impact_fraction: float = clampf(move.capture_impact_fraction, 0.1, 0.95)
	var approach_duration := king_duration * impact_fraction
	var finish_duration := king_duration - approach_duration
	var capture_depths := capture_collision_depths(king_start, target)
	king.z_index = capture_depths.king
	defender.z_index = capture_depths.defender
	var start_rotation := defender.rotation
	var approach := create_tween()
	approach.tween_method(func(progress: float): king.position = _arc(king_start, target, progress * impact_fraction, move.lift_height), 0.0, 1.0, approach_duration * board.animation_duration_scale)
	await approach.finished
	king.position = _arc(king_start, target, impact_fraction, move.lift_height)
	capture_impact.emit(defender)
	var total: float = maxf(finish_duration, knock_duration)
	var impact := create_tween()
	impact.tween_method(func(elapsed: float):
		var kp := impact_fraction + (1.0 - impact_fraction) * clampf(elapsed / maxf(finish_duration, 0.001), 0.0, 1.0)
		var flight_time := minf(elapsed, knock_duration)
		king.position = _arc(king_start, target, kp, move.lift_height)
		defender.position = ballistic_position(defender_start, knockoff.initial_velocity, knockoff.gravity, flight_time)
		defender.rotation = start_rotation + deg_to_rad(move.knockoff_angular_speed * side) * flight_time
	, 0.0, total, total * board.animation_duration_scale)
	await impact.finished
	king.position = target


func disable_effects() -> void:
	if is_instance_valid(king_aura): king_aura.set_power(0.0)
	if is_instance_valid(hand_aura): hand_aura.set_power(0.0)


static func gesture_points(origin: Vector2, destination: Vector2, base_hover: Vector2, clearance: float, sweep_distance: float) -> PackedVector2Array:
	var direction := (destination - origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	# Clearance is retained in the signature for saved-resource/test compatibility.
	# The authored hover is deliberately the same recognizable lock in all eight
	# directions; only the command endpoint changes.
	return PackedVector2Array([base_hover, base_hover + direction * sweep_distance])


## Builds a straight command followed by the shortest clockwise/counterclockwise
## bounded-radius arc and its tangent line to the offscreen home.
static func build_gesture_path(lock: Vector2, swipe_end: Vector2, rest: Vector2, requested_radius: float, curve_samples := 96, straight_samples := 12) -> Dictionary:
	var direction := (swipe_end - lock).normalized()
	if direction.is_zero_approx():
		direction = (rest - lock).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var endpoint_distance := swipe_end.distance_to(rest)
	var effective_radius := minf(maxf(requested_radius, 1.0), endpoint_distance * 0.49)
	var clockwise := _turn_candidate(swipe_end, direction, rest, effective_radius, 1)
	var counterclockwise := _turn_candidate(swipe_end, direction, rest, effective_radius, -1)
	var chosen: Dictionary
	if clockwise.is_empty():
		chosen = counterclockwise
	elif counterclockwise.is_empty():
		chosen = clockwise
	elif float(clockwise.total_length) <= float(counterclockwise.total_length) + 0.001:
		chosen = clockwise
	else:
		chosen = counterclockwise
	var points := PackedVector2Array([lock])
	var cumulative := PackedFloat32Array([0.0])
	for index in range(1, maxi(straight_samples, 2) + 1):
		var point := lock.lerp(swipe_end, float(index) / float(maxi(straight_samples, 2)))
		cumulative.append(cumulative[-1] + points[-1].distance_to(point))
		points.append(point)
	var join_index := points.size() - 1
	var arc_angle: float = chosen.arc_angle
	var arc_samples := maxi(12, ceili(arc_angle / (TAU / float(maxi(curve_samples, 24)))))
	for index in range(1, arc_samples + 1):
		var angle: float = float(chosen.start_angle) + float(chosen.turn_sign) * arc_angle * float(index) / float(arc_samples)
		var point: Vector2 = chosen.center + Vector2.RIGHT.rotated(angle) * effective_radius
		cumulative.append(cumulative[-1] + points[-1].distance_to(point))
		points.append(point)
	var turn_end_index := points.size() - 1
	for index in range(1, 25):
		var point: Vector2 = chosen.tangent.lerp(rest, float(index) / 24.0)
		cumulative.append(cumulative[-1] + points[-1].distance_to(point))
		points.append(point)
	return {
		"points": points,
		"cumulative_lengths": cumulative,
		"straight_length": lock.distance_to(swipe_end),
		"total_length": cumulative[-1],
		"join_index": join_index,
		"turn_end_index": turn_end_index,
		"turn_sign": chosen.turn_sign,
		"effective_radius": effective_radius,
		"turn_center": chosen.center,
		"tangent_point": chosen.tangent,
	}


static func _turn_candidate(start: Vector2, heading: Vector2, target: Vector2, radius: float, turn_sign: int) -> Dictionary:
	var normal := Vector2(-heading.y, heading.x)
	var center := start + normal * float(turn_sign) * radius
	var to_target := target - center
	var center_distance := to_target.length()
	if center_distance <= radius:
		return {}
	var offset_angle := acos(clampf(radius / center_distance, -1.0, 1.0))
	var start_radius := start - center
	var start_angle := start_radius.angle()
	for tangent_angle in [to_target.angle() + offset_angle, to_target.angle() - offset_angle]:
		var radial := Vector2.RIGHT.rotated(tangent_angle)
		var tangent := center + radial * radius
		var travel_heading := Vector2(-radial.y, radial.x) * float(turn_sign)
		var home_heading := (target - tangent).normalized()
		if travel_heading.dot(home_heading) < 0.999:
			continue
		var arc_angle := fposmod(tangent_angle - start_angle, TAU) if turn_sign > 0 else fposmod(start_angle - tangent_angle, TAU)
		return {
			"center": center,
			"tangent": tangent,
			"start_angle": start_angle,
			"arc_angle": arc_angle,
			"turn_sign": turn_sign,
			"total_length": radius * arc_angle + tangent.distance_to(target),
		}
	return {}


## Adds a normalized travel-time lookup to an arc-length path. Speed values are
## relative weights; total gesture duration remains authoritative.
static func build_path_timing(path: Dictionary, launch_speed: float, turn_speed: float, exit_speed: float) -> void:
	var lengths: PackedFloat32Array = path.cumulative_lengths
	var total_length: float = maxf(float(path.total_length), 0.001)
	var straight_length: float = clampf(float(path.straight_length), 0.0, total_length)
	var safe_launch := maxf(launch_speed, 0.05)
	var safe_exit := maxf(exit_speed, 0.05)
	var safe_turn := clampf(turn_speed, 0.05, minf(safe_launch, safe_exit))
	var times := PackedFloat32Array([0.0])
	for index in range(1, lengths.size()):
		var segment_distance := float(lengths[index] - lengths[index - 1])
		var midpoint := (float(lengths[index]) + float(lengths[index - 1])) * 0.5
		var weight: float
		if midpoint <= straight_length:
			var phase := midpoint / maxf(straight_length, 0.001)
			weight = lerpf(safe_launch, safe_turn, smoothstep(0.0, 1.0, phase))
		else:
			var phase := (midpoint - straight_length) / maxf(total_length - straight_length, 0.001)
			weight = lerpf(safe_turn, safe_exit, smoothstep(0.0, 1.0, phase))
		times.append(times[-1] + segment_distance / maxf(weight, 0.001))
	var total_time := maxf(times[-1], 0.001)
	for index in range(times.size()):
		times[index] /= total_time
	path["cumulative_times"] = times
	path["effective_turn_speed"] = safe_turn


static func sample_timed_path(path: Dictionary, time_progress: float) -> Dictionary:
	var times: PackedFloat32Array = path.cumulative_times
	var lengths: PackedFloat32Array = path.cumulative_lengths
	var points: PackedVector2Array = path.points
	var progress := clampf(time_progress, 0.0, 1.0)
	var upper := 1
	if times.size() < 2:
		return {"position": points[0], "distance": 0.0}
	while upper < times.size() - 1 and float(times[upper]) < progress:
		upper += 1
	var lower := maxi(upper - 1, 0)
	var span := maxf(float(times[upper] - times[lower]), 0.000001)
	var local := clampf((progress - float(times[lower])) / span, 0.0, 1.0)
	return {
		"position": points[lower].lerp(points[upper], local),
		"distance": lerpf(float(lengths[lower]), float(lengths[upper]), local),
	}


static func knockoff_side(origin: Vector2, destination: Vector2, random: RandomNumberGenerator) -> int:
	var delta_x := destination.x - origin.x
	if absf(delta_x) > 0.5:
		return 1 if delta_x > 0.0 else -1
	return -1 if random.randi_range(0, 1) == 0 else 1


static func capture_collision_depths(king_origin: Vector2, target: Vector2) -> Dictionary:
	var defender_depth := ChessBoardView.BOARD_EFFECT_Z
	# A King arriving from screen-below visually crosses in front of its target.
	# Approaches from above or level retain the defender-over-King impact stack.
	return {
		"king": defender_depth + 1 if king_origin.y > target.y + 0.5 else ChessHandRig.ACTIVE_PIECE_Z,
		"defender": defender_depth,
	}


static func build_ballistic_knockoff(king_origin: Vector2, king_destination: Vector2, defender_origin: Vector2, viewport_size: Vector2, visual_radius: float, horizontal_speed: float, upward_speed: float, gravity: float, random: RandomNumberGenerator, sample_count := 64) -> Dictionary:
	var side := knockoff_side(king_origin, king_destination, random)
	var initial_velocity := Vector2(float(side) * maxf(horizontal_speed, 1.0), -maxf(upward_speed, 0.0))
	var safe_gravity := maxf(gravity, 1.0)
	var duration := ballistic_exit_time(defender_origin, initial_velocity, safe_gravity, viewport_size, maxf(visual_radius, 0.0))
	var points := PackedVector2Array()
	for index in range(maxi(sample_count, 2) + 1):
		points.append(ballistic_position(defender_origin, initial_velocity, safe_gravity, duration * float(index) / float(maxi(sample_count, 2))))
	return {
		"side": side,
		"initial_velocity": initial_velocity,
		"gravity": safe_gravity,
		"duration": duration,
		"points": points,
		"target": points[-1],
	}


static func ballistic_position(origin: Vector2, initial_velocity: Vector2, gravity: float, time: float) -> Vector2:
	return origin + initial_velocity * time + Vector2(0.0, 0.5 * gravity * time * time)


static func ballistic_exit_time(origin: Vector2, initial_velocity: Vector2, gravity: float, viewport_size: Vector2, radius: float) -> float:
	var candidates: Array[float] = []
	if initial_velocity.x > 0.0:
		candidates.append((viewport_size.x + radius - origin.x) / initial_velocity.x)
	elif initial_velocity.x < 0.0:
		candidates.append((-radius - origin.x) / initial_velocity.x)
	_append_positive_roots(candidates, 0.5 * gravity, initial_velocity.y, origin.y + radius)
	_append_positive_roots(candidates, 0.5 * gravity, initial_velocity.y, origin.y - viewport_size.y - radius)
	var earliest := 8.0
	for candidate in candidates:
		if candidate > 0.0:
			earliest = minf(earliest, candidate)
	return maxf(earliest, 0.01)


static func _append_positive_roots(results: Array[float], a: float, b: float, c: float) -> void:
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return
	var root := sqrt(discriminant)
	results.append((-b - root) / (2.0 * a))
	results.append((-b + root) / (2.0 * a))


static func piece_visual_radius(piece: PieceView) -> float:
	if not is_instance_valid(piece) or piece.sprite == null or piece.sprite.texture == null:
		return 32.0
	var width := float(piece.sprite.texture.get_width()) * absf(piece.sprite.scale.x)
	var height := float(piece.sprite.texture.get_height()) * absf(piece.sprite.scale.y)
	var local_radius := Vector2(width * 0.5, height).length()
	return local_radius * maxf(absf(piece.scale.x), absf(piece.scale.y))


static func _arc(start: Vector2, finish: Vector2, progress: float, height: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	return start.lerp(finish, p) + Vector2.UP * (4.0 * height * p * (1.0 - p))


func _tween_position(node: Node2D, target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position", target, duration * board.animation_duration_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


static func _cubic_bezier(start: Vector2, control_a: Vector2, control_b: Vector2, finish: Vector2, progress: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var inverse := 1.0 - p
	return inverse * inverse * inverse * start + 3.0 * inverse * inverse * p * control_a + 3.0 * inverse * p * p * control_b + p * p * p * finish


func _exit_tree() -> void:
	if is_instance_valid(hand) and hand.magical_foreground_active:
		hand.set_magical_foreground(false, self)
	if is_instance_valid(king_aura): king_aura.clear_targets()
	if is_instance_valid(hand_aura): hand_aura.clear_targets()
	if is_instance_valid(connection_anchor): connection_anchor.queue_free()
	if is_instance_valid(stone_sprite): stone_sprite.queue_free()
