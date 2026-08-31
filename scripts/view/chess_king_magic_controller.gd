extends Node
class_name ChessKingMagicController

const KingPresentationProfile = preload("res://scripts/view/chess_king_presentation_profile.gd")
const PresentationTransform = preload("res://scripts/view/chess_presentation_transform.gd")
const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")

## Runtime owner for one King's persistent aura and self-propelled actions.
var board: ChessBoardView
var hand: ChessHandRig
var king: PieceView
var profile: Resource
var king_aura: ChessAura2D
var hand_aura: ChessAura2D
var activation_sequence: ChessKingActivationSequence
var lightning: ChessLightning2D
var connection_anchor: Marker2D
var stone_sprite: Sprite2D
var running := false
var rng := RandomNumberGenerator.new()


func configure(board_view: ChessBoardView, hand_rig: ChessHandRig, king_view: PieceView, king_profile: Resource) -> void:
	board = board_view
	hand = hand_rig
	king = king_view
	profile = king_profile if king_profile != null else KingPresentationProfile.new()
	profile.ensure_defaults()
	rng.randomize()
	_build_effects()


func _build_effects() -> void:
	king_aura = ChessAura2D.new()
	king_aura.profile = profile.aura_profile.duplicate(true)
	king_aura.mode = profile.aura_mode
	add_child(king_aura)
	king_aura.bind_targets([king.sprite])
	king_aura.set_silhouette_power(profile.activation_profile.resting_aura_power)
	king_aura.set_particle_power(profile.activation_profile.resting_particle_power)
	king_aura.set_runtime_multipliers(profile.activation_profile.resting_density_multiplier, profile.activation_profile.resting_speed_multiplier)
	if is_instance_valid(hand) and hand.can_animate():
		hand_aura = ChessAura2D.new()
		hand_aura.profile = profile.aura_profile.duplicate(true)
		hand_aura.mode = profile.aura_mode
		add_child(hand_aura)
		hand_aura.bind_targets(hand.get_aura_sprites())
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
	activation_sequence = ChessKingActivationSequence.new()
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
	await _begin_gesture()
	king.coordinate = to
	await _travel_king(board.grid_to_screen(to.x, to.y), profile.movement_profile.travel_duration)
	board._update_piece_depth(king)
	await _end_gesture()


func play_capture(from: Vector2i, to: Vector2i, defender: PieceView) -> void:
	await _begin_gesture()
	king.coordinate = to
	await _travel_with_knockoff(board.grid_to_screen(to.x, to.y), defender, from, to)
	board._update_piece_depth(king)
	await _end_gesture()


func play_attack(_from: Vector2i, target: Vector2i, contact_callback := Callable()) -> void:
	await _begin_gesture()
	var origin := king.position
	await _travel_king(board.grid_to_screen(target.x, target.y), profile.movement_profile.travel_duration)
	if contact_callback.is_valid(): contact_callback.call()
	await _travel_king(origin, profile.movement_profile.attack_rebound_duration)
	board._update_piece_depth(king)
	await _end_gesture()


func _begin_gesture() -> void:
	running = true
	var move: Resource = profile.movement_profile
	if is_instance_valid(hand) and hand.can_animate():
		var effective_scale := board.get_world_scale() * hand.art_scale_multiplier
		hand.scale = Vector2.ONE * effective_scale
		hand._apply_pose(false)
		hand.visible = true
		hand.position = hand._offscreen_rest_position(effective_scale)
		var hover := king.position + PresentationTransform.king_hover_offset(move.hand_hover_offset, hand.seat)
		await _tween_position(hand, hover, move.hand_approach_duration)
		hand_aura.set_silhouette_power(move.hand_silhouette_power)
		hand_aura.set_particle_power(move.hand_particle_power)
	king_aura.set_silhouette_power(move.king_silhouette_power)
	king_aura.set_particle_power(move.king_particle_power)
	if move.invocation_duration > 0.0:
		await get_tree().create_timer(move.invocation_duration * board.animation_duration_scale).timeout


func _end_gesture() -> void:
	var move: Resource = profile.movement_profile
	king_aura.set_silhouette_power(profile.activation_profile.resting_aura_power)
	king_aura.set_particle_power(profile.activation_profile.resting_particle_power)
	if move.settle_duration > 0.0:
		await get_tree().create_timer(move.settle_duration * board.animation_duration_scale).timeout
	if is_instance_valid(hand) and hand.can_animate():
		hand_aura.set_power(0.0)
		await _tween_position(hand, hand._offscreen_rest_position(board.get_world_scale() * hand.art_scale_multiplier), move.hand_retreat_duration)
		hand.visible = false
	running = false


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
	var side := knockoff_side(king_start, target, rng)
	var defender_target := Vector2(-move.knockoff_side_margin if side < 0 else board.get_viewport_rect().size.x + move.knockoff_side_margin, defender_start.y - move.knockoff_arc_height * 0.35)
	var king_duration: float = move.travel_duration * board.animation_duration_scale
	var knock_duration: float = move.knockoff_duration * board.animation_duration_scale
	var total: float = maxf(king_duration, knock_duration)
	king.z_index = ChessHandRig.ACTIVE_PIECE_Z
	defender.z_index = ChessBoardView.BOARD_EFFECT_Z
	var start_rotation := defender.rotation
	var tween := create_tween()
	tween.tween_method(func(elapsed: float):
		var kp := clampf(elapsed / maxf(king_duration, 0.001), 0.0, 1.0)
		var dp := clampf(elapsed / maxf(knock_duration, 0.001), 0.0, 1.0)
		king.position = _arc(king_start, target, kp, move.lift_height)
		defender.position = _arc(defender_start, defender_target, dp, move.knockoff_arc_height)
		defender.rotation = start_rotation + deg_to_rad(move.knockoff_spin_degrees * side) * dp
	, 0.0, total, total)
	await tween.finished
	king.position = target


static func knockoff_side(origin: Vector2, destination: Vector2, random: RandomNumberGenerator) -> int:
	var delta_x := destination.x - origin.x
	if absf(delta_x) > 0.5:
		return 1 if delta_x > 0.0 else -1
	return -1 if random.randi_range(0, 1) == 0 else 1


static func _arc(start: Vector2, finish: Vector2, progress: float, height: float) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	return start.lerp(finish, p) + Vector2.UP * (4.0 * height * p * (1.0 - p))


func _tween_position(node: Node2D, target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "position", target, duration * board.animation_duration_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _exit_tree() -> void:
	if is_instance_valid(king_aura): king_aura.clear_targets()
	if is_instance_valid(hand_aura): hand_aura.clear_targets()
	if is_instance_valid(connection_anchor): connection_anchor.queue_free()
	if is_instance_valid(stone_sprite): stone_sprite.queue_free()
