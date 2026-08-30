extends Node2D
class_name ChessHandRig

signal pose_changed(pose: StringName)
signal piece_grabbed(piece: Node2D)
signal piece_released(piece: Node2D)
signal carry_path_started(path: StringName)
signal capture_stage_changed(stage: StringName)
signal captured_piece_grabbed(piece: Node2D)
signal attack_contact(piece: Node2D)
signal move_animation_finished()
signal setup_piece_placed(piece: Node2D)
signal depth_state_changed(state: DepthState, base_depth: int)

const CARRY_PATH_SLIDE := &"slide"
const CARRY_PATH_JUMP := &"jump"
const SOUND_GRAB := &"grab"
const SOUND_CAPTURE_PICKUP := &"capture_pickup"
const SOUND_PLACE := &"place"
const SOUND_RELEASE := &"release"
enum Seat { NEAR, FAR }
enum DepthState { GROUNDED, ELEVATED }
## Absolute board-canvas interaction stack above ordinary pieces (0-70).
const GRIP_BACK_Z := 72
const ACTIVE_PIECE_Z := 73
const CAPTURED_PIECE_Z := 74
const HAND_OVERLAY_Z := 75
const GRIP_FRONT_Z := 76
const ARM_FOREGROUND_Z := 80
## Grounded slots live inside one board row's ten-level depth band.
const GROUNDED_GRIP_BACK_OFFSET := 2
const GROUNDED_ACTIVE_PIECE_OFFSET := 3
const GROUNDED_CAPTURED_PIECE_OFFSET := 4
const GROUNDED_GRIP_FRONT_OFFSET := 6
const DEPTH_BAND_STRIDE := 10
@export var hand_style: ChessHandStyle
@export var seat := Seat.NEAR
@export_group("Debug")
@export var show_approach_path_debug := false: # Draws the computed Bezier in-game; toggle this and edit the handles in Godot's Remote inspector.
	set(value):
		show_approach_path_debug = value
		_refresh_live_approach()
@export_group("")

var motion_override: ChessHandMotionProfile
var grip_anchor_pixels: Vector2: get = _get_grip_anchor_pixels
var piece_grip_offset: Vector2: get = _get_piece_grip_offset
var art_scale_multiplier: float: get = _get_art_scale_multiplier
var approach_duration: float: get = _get_approach_duration, set = _set_approach_duration
var approach_departure_progress: float: get = _get_approach_departure_progress, set = _set_approach_departure_progress
var approach_departure_lift: float: get = _get_approach_departure_lift, set = _set_approach_departure_lift
var approach_arrival_handle: Vector2: get = _get_approach_arrival_handle, set = _set_approach_arrival_handle
var grasp_hold_duration: float: get = _get_grasp_hold_duration, set = _set_grasp_hold_duration
var carry_duration: float: get = _get_carry_duration, set = _set_carry_duration
var jump_arc_height: float: get = _get_jump_arc_height, set = _set_jump_arc_height
var jump_carry_duration: float: get = _get_jump_carry_duration, set = _set_jump_carry_duration
var attack_slam_duration: float: get = _get_attack_slam_duration, set = _set_attack_slam_duration
var attack_rebound_duration: float: get = _get_attack_rebound_duration, set = _set_attack_rebound_duration
var capture_approach_offset: float: get = _get_capture_approach_offset, set = _set_capture_approach_offset
var capture_approach_arc_height: float: get = _get_capture_approach_arc_height, set = _set_capture_approach_arc_height
var capture_approach_duration: float: get = _get_capture_approach_duration, set = _set_capture_approach_duration
var capture_swipe_distance: float: get = _get_capture_swipe_distance, set = _set_capture_swipe_distance
var capture_swipe_duration: float: get = _get_capture_swipe_duration, set = _set_capture_swipe_duration
var captured_piece_grip_offset: Vector2: get = _get_captured_piece_grip_offset, set = _set_captured_piece_grip_offset
var captured_piece_rotation_degrees: float: get = _get_captured_piece_rotation_degrees, set = _set_captured_piece_rotation_degrees
var capture_placement_arc_height: float: get = _get_capture_placement_arc_height, set = _set_capture_placement_arc_height
var capture_placement_duration: float: get = _get_capture_placement_duration, set = _set_capture_placement_duration
var release_hold_duration: float: get = _get_release_hold_duration, set = _set_release_hold_duration
var retreat_duration: float: get = _get_retreat_duration, set = _set_retreat_duration
var offscreen_margin: float: get = _get_offscreen_margin, set = _set_offscreen_margin

@onready var grip_back_sprite: Sprite2D = $GripBack
@onready var captured_piece_pivot: Node2D = $CapturedPiecePivot
@onready var piece_slot: Node2D = $PieceSlot
@onready var grip_front_sprite: Sprite2D = $GripFront
@onready var arm_foreground_sprite: Sprite2D = $ArmForeground
@onready var approach_path_debug: Line2D = $ApproachPathDebug
@onready var grab_sound: AudioStreamPlayer = $GrabSound
@onready var capture_pickup_sound: AudioStreamPlayer = $CapturePickupSound
@onready var place_sound: AudioStreamPlayer = $PlaceSound
@onready var release_sound: AudioStreamPlayer = $ReleaseSound
@onready var slide_sound: AudioStreamPlayer = $SlideSound

var is_animating := false
var board_sound_set: ChessBoardSoundSet
var slide_fade_tween: Tween
var animation_duration_scale := 1.0
var has_approach_preview := false
var approach_preview_start := Vector2.ZERO
var approach_preview_target := Vector2.ZERO
var approach_preview_world_scale := 1.0
var approach_preview_progress := 0.0
var depth_state := DepthState.ELEVATED
var grounded_base_depth := 0
var visual_mirrored := false
var setup_paused := false
var setup_generation := 0
var setup_piece: Node2D
var setup_piece_parent: Node
var setup_piece_scale := Vector2.ONE
var setup_piece_z := 0
var fallback_motion := ChessHandMotionProfile.new()


func _motion() -> ChessHandMotionProfile:
	if motion_override != null:
		return motion_override
	if hand_style != null and hand_style.motion_profile != null:
		return hand_style.motion_profile
	return fallback_motion


func _motion_for_write() -> ChessHandMotionProfile:
	if motion_override == null:
		motion_override = _motion().duplicate(true)
	return motion_override


func _get_grip_anchor_pixels() -> Vector2: return hand_style.grip_anchor_pixels if hand_style != null else Vector2(11.0, 29.0)
func _get_piece_grip_offset() -> Vector2: return hand_style.piece_grip_offset if hand_style != null else Vector2(0.0, 6.0)
func _get_art_scale_multiplier() -> float: return hand_style.art_scale_multiplier if hand_style != null else 3.5
func _get_approach_duration() -> float: return _motion().approach_duration
func _set_approach_duration(value: float) -> void: _motion_for_write().approach_duration = value
func _get_approach_departure_progress() -> float: return _motion().approach_departure_progress
func _set_approach_departure_progress(value: float) -> void: _motion_for_write().approach_departure_progress = value; _refresh_live_approach()
func _get_approach_departure_lift() -> float: return _motion().approach_departure_lift
func _set_approach_departure_lift(value: float) -> void: _motion_for_write().approach_departure_lift = value; _refresh_live_approach()
func _get_approach_arrival_handle() -> Vector2: return _motion().approach_arrival_handle
func _set_approach_arrival_handle(value: Vector2) -> void: _motion_for_write().approach_arrival_handle = value; _refresh_live_approach()
func _get_grasp_hold_duration() -> float: return _motion().grasp_hold_duration
func _set_grasp_hold_duration(value: float) -> void: _motion_for_write().grasp_hold_duration = value
func _get_carry_duration() -> float: return _motion().carry_duration
func _set_carry_duration(value: float) -> void: _motion_for_write().carry_duration = value
func _get_jump_arc_height() -> float: return _motion().jump_arc_height
func _set_jump_arc_height(value: float) -> void: _motion_for_write().jump_arc_height = value
func _get_jump_carry_duration() -> float: return _motion().jump_carry_duration
func _set_jump_carry_duration(value: float) -> void: _motion_for_write().jump_carry_duration = value
func _get_attack_slam_duration() -> float: return _motion().attack_slam_duration
func _set_attack_slam_duration(value: float) -> void: _motion_for_write().attack_slam_duration = value
func _get_attack_rebound_duration() -> float: return _motion().attack_rebound_duration
func _set_attack_rebound_duration(value: float) -> void: _motion_for_write().attack_rebound_duration = value
func _get_capture_approach_offset() -> float: return _motion().capture_approach_offset
func _set_capture_approach_offset(value: float) -> void: _motion_for_write().capture_approach_offset = value
func _get_capture_approach_arc_height() -> float: return _motion().capture_approach_arc_height
func _set_capture_approach_arc_height(value: float) -> void: _motion_for_write().capture_approach_arc_height = value
func _get_capture_approach_duration() -> float: return _motion().capture_approach_duration
func _set_capture_approach_duration(value: float) -> void: _motion_for_write().capture_approach_duration = value
func _get_capture_swipe_distance() -> float: return _motion().capture_swipe_distance
func _set_capture_swipe_distance(value: float) -> void: _motion_for_write().capture_swipe_distance = value
func _get_capture_swipe_duration() -> float: return _motion().capture_swipe_duration
func _set_capture_swipe_duration(value: float) -> void: _motion_for_write().capture_swipe_duration = value
func _get_captured_piece_grip_offset() -> Vector2: return _motion().captured_piece_grip_offset
func _set_captured_piece_grip_offset(value: Vector2) -> void: _motion_for_write().captured_piece_grip_offset = value
func _get_captured_piece_rotation_degrees() -> float: return _motion().captured_piece_rotation_degrees
func _set_captured_piece_rotation_degrees(value: float) -> void: _motion_for_write().captured_piece_rotation_degrees = value
func _get_capture_placement_arc_height() -> float: return _motion().capture_placement_arc_height
func _set_capture_placement_arc_height(value: float) -> void: _motion_for_write().capture_placement_arc_height = value
func _get_capture_placement_duration() -> float: return _motion().capture_placement_duration
func _set_capture_placement_duration(value: float) -> void: _motion_for_write().capture_placement_duration = value
func _get_release_hold_duration() -> float: return _motion().release_hold_duration
func _set_release_hold_duration(value: float) -> void: _motion_for_write().release_hold_duration = value
func _get_retreat_duration() -> float: return _motion().retreat_duration
func _set_retreat_duration(value: float) -> void: _motion_for_write().retreat_duration = value
func _get_offscreen_margin() -> float: return _motion().offscreen_margin
func _set_offscreen_margin(value: float) -> void: _motion_for_write().offscreen_margin = value


func _ready() -> void:
	# Keep the tuning overlay in board space so hiding the hand does not also hide
	# the last computed curve.
	_detach_approach_path_debug.call_deferred()
	visible = false
	grip_back_sprite.z_index = GRIP_BACK_Z
	piece_slot.z_index = ACTIVE_PIECE_Z
	captured_piece_pivot.z_index = CAPTURED_PIECE_Z
	grip_front_sprite.z_index = GRIP_FRONT_Z
	arm_foreground_sprite.z_index = ARM_FOREGROUND_Z
	_set_elevated_depth()
	_apply_pose(false)


func _set_grounded_depth(base_depth: int) -> void:
	var state_changed := depth_state != DepthState.GROUNDED or grounded_base_depth != base_depth
	depth_state = DepthState.GROUNDED
	grounded_base_depth = base_depth
	grip_back_sprite.z_index = base_depth + GROUNDED_GRIP_BACK_OFFSET
	piece_slot.z_index = base_depth + GROUNDED_ACTIVE_PIECE_OFFSET
	captured_piece_pivot.z_index = base_depth + GROUNDED_CAPTURED_PIECE_OFFSET
	grip_front_sprite.z_index = (
		base_depth + GROUNDED_GRIP_FRONT_OFFSET
		if hand_style == null or hand_style.grip_front_follows_board_depth
		else GRIP_FRONT_Z
	)
	arm_foreground_sprite.z_index = ARM_FOREGROUND_Z
	if state_changed:
		depth_state_changed.emit(depth_state, grounded_base_depth)


func _set_elevated_depth() -> void:
	var state_changed := depth_state != DepthState.ELEVATED
	depth_state = DepthState.ELEVATED
	grip_back_sprite.z_index = GRIP_BACK_Z
	piece_slot.z_index = ACTIVE_PIECE_Z
	captured_piece_pivot.z_index = CAPTURED_PIECE_Z
	grip_front_sprite.z_index = GRIP_FRONT_Z
	arm_foreground_sprite.z_index = ARM_FOREGROUND_Z
	if state_changed:
		depth_state_changed.emit(depth_state, grounded_base_depth)


func _detach_approach_path_debug() -> void:
	if is_instance_valid(approach_path_debug) and approach_path_debug.get_parent() == self:
		approach_path_debug.reparent(get_parent(), false)


func set_hand_style(style: Resource) -> void:
	hand_style = style
	motion_override = null
	if is_node_ready():
		_apply_pose(false)
		if depth_state == DepthState.GROUNDED:
			_set_grounded_depth(grounded_base_depth)
		else:
			_set_elevated_depth()


func set_board_sound_set(sound_set: ChessBoardSoundSet) -> void:
	board_sound_set = sound_set


## Mirrors the hand around its grip without mirroring a carried chess piece.
func set_visual_mirrored(mirrored: bool) -> void:
	visual_mirrored = mirrored
	if is_node_ready():
		_apply_pose(false)


func get_aura_sprites() -> Array[Sprite2D]:
	return [grip_back_sprite, grip_front_sprite, arm_foreground_sprite]


func get_connection_anchor_position() -> Vector2:
	var connection_pixels := hand_style.connection_anchor_pixels if hand_style != null else Vector2(23.0, 24.0)
	var anchor: Vector2 = connection_pixels - grip_anchor_pixels
	return Vector2(-anchor.x, anchor.y) if visual_mirrored else anchor


func can_animate() -> bool:
	return hand_style != null and hand_style.has_method("is_complete") and hand_style.is_complete()


## Places a piece from an unseen off-board supply. This is intentionally
## separate from play_piece_move: the piece begins in the hand, not on a square.
func play_setup_placement(
	piece_node: Node2D,
	destination: Vector2,
	world_scale: float,
	motion: ChessSetupMotionProfile,
	final_piece_z_index: int
) -> void:
	if not can_animate() or not is_instance_valid(piece_node) or motion == null:
		return
	cancel_setup_placement()
	var setup_token := setup_generation
	is_animating = true
	setup_piece = piece_node
	setup_piece_parent = piece_node.get_parent()
	setup_piece_scale = piece_node.scale
	setup_piece_z = piece_node.z_index
	var effective_hand_scale := world_scale * art_scale_multiplier
	scale = Vector2.ONE * effective_hand_scale
	_set_elevated_depth()
	var contact_position := _piece_grip_position(piece_node)
	position = contact_position
	piece_node.visible = true
	piece_node.reparent(piece_slot, true)
	piece_node.z_index = 0
	_apply_pose(true)
	visible = false
	_play_hand_sound(SOUND_GRAB)
	if not await _setup_wait(motion.pickup_delay, setup_token):
		return
	position = _setup_rest_position(effective_hand_scale)
	visible = true
	if not await _setup_curve(position, contact_position, motion.entry_departure_handle, motion.entry_arrival_handle, motion.entry_duration, world_scale, setup_token):
		return
	_set_grounded_depth(final_piece_z_index)
	_play_board_sound(SOUND_PLACE)
	if not await _setup_wait(motion.placement_hold, setup_token):
		return
	_apply_pose(false)
	piece_node.reparent(setup_piece_parent, true)
	piece_node.scale = setup_piece_scale
	piece_node.position = destination
	piece_node.z_index = final_piece_z_index
	piece_node.visible = true
	setup_piece_placed.emit(piece_node)
	_play_hand_sound(SOUND_RELEASE)
	setup_piece = null
	if not await _setup_wait(motion.release_hold, setup_token):
		return
	_set_elevated_depth()
	var rest := _setup_rest_position(effective_hand_scale)
	if not await _setup_curve(position, rest, motion.retreat_departure_handle, motion.retreat_arrival_handle, motion.retreat_duration, world_scale, setup_token):
		return
	visible = false
	is_animating = false


func set_setup_paused(value: bool) -> void:
	setup_paused = value


func cancel_setup_placement() -> void:
	setup_generation += 1
	if is_instance_valid(setup_piece) and is_instance_valid(setup_piece_parent):
		setup_piece.reparent(setup_piece_parent, true)
		setup_piece.scale = setup_piece_scale
		setup_piece.z_index = setup_piece_z
		setup_piece.visible = false
	setup_piece = null
	if is_node_ready():
		_set_elevated_depth()
	visible = false
	is_animating = false
	setup_paused = false


func _setup_rest_position(world_scale: float) -> Vector2:
	return _offscreen_rest_position(world_scale)


func _setup_curve(start: Vector2, finish: Vector2, departure: Vector2, arrival: Vector2, duration: float, world_scale: float, token: int) -> bool:
	var mirror := -1.0 if visual_mirrored else 1.0
	var control_a := start + Vector2(departure.x * mirror, departure.y) * world_scale
	var control_b := finish + Vector2(arrival.x * mirror, arrival.y) * world_scale
	var elapsed := 0.0
	var resolved_duration := maxf(duration * animation_duration_scale, 0.001)
	while elapsed < resolved_duration:
		await get_tree().process_frame
		if token != setup_generation:
			return false
		if setup_paused:
			continue
		elapsed += get_process_delta_time()
		var progress := clampf(elapsed / resolved_duration, 0.0, 1.0)
		var eased_progress := -(cos(PI * progress) - 1.0) * 0.5
		position = calculate_bezier_position(start, control_a, control_b, finish, eased_progress)
	position = finish
	return token == setup_generation


func _setup_wait(duration: float, token: int) -> bool:
	var remaining := duration * animation_duration_scale
	while remaining > 0.0:
		await get_tree().process_frame
		if token != setup_generation:
			return false
		if not setup_paused:
			remaining -= get_process_delta_time()
	return token == setup_generation


func play_piece_move(
	piece_node: Node2D,
	destination: Vector2,
	world_scale: float,
	carry_path: StringName = CARRY_PATH_SLIDE,
	enter_from_offscreen := true,
	retreat_offscreen := true,
	final_piece_z_index := -1
) -> void:
	if not can_animate() or not is_instance_valid(piece_node):
		return

	# Prepare the open hand at the same visual scale as the board.
	is_animating = true
	var effective_hand_scale := world_scale * art_scale_multiplier
	scale = Vector2.ONE * effective_hand_scale
	_apply_pose(false)
	pose_changed.emit(&"open")

	# Remember how the piece belongs on the board before temporarily picking it up.
	var original_parent := piece_node.get_parent()
	var original_scale := piece_node.scale
	var original_z_index := piece_node.z_index
	var release_z_index := final_piece_z_index if final_piece_z_index >= 0 else original_z_index
	var origin := piece_node.position
	var contact_position := _piece_grip_position(piece_node)
	var destination_contact := contact_position + destination - origin

	# Arc the open hand from its lower-right rest point to the piece's grip point.
	if enter_from_offscreen:
		position = _offscreen_rest_position(effective_hand_scale)
	visible = true
	if enter_from_offscreen:
		_set_grounded_depth(original_z_index)
		await _tween_approach_position(contact_position, approach_duration, world_scale)
	else:
		_set_elevated_depth()
		await _tween_position(contact_position, approach_duration)
		_set_grounded_depth(original_z_index)

	# Place the piece between the back and front grip layers, then close the hand.
	piece_node.reparent(piece_slot, true)
	piece_node.z_index = 0
	piece_grabbed.emit(piece_node)
	_apply_pose(true)
	pose_changed.emit(&"closed")
	_play_hand_sound(SOUND_GRAB)
	await _wait(grasp_hold_duration)

	# Carry the closed hand and grabbed piece to the destination together.
	carry_path_started.emit(carry_path)
	if carry_path == CARRY_PATH_JUMP:
		_set_elevated_depth()
		await _tween_jump_position(destination_contact, jump_carry_duration, jump_arc_height * world_scale)
		_set_grounded_depth(release_z_index)
	else:
		_start_slide_sound()
		await _tween_grounded_position(destination_contact, carry_duration, original_z_index, release_z_index)
		_stop_slide_sound()
	_play_board_sound(SOUND_PLACE)
	await _wait(release_hold_duration)

	# Open the hand, return the piece to the board, and snap it to its exact square.
	_apply_pose(false)
	pose_changed.emit(&"open")
	piece_node.reparent(original_parent, true)
	piece_node.scale = original_scale
	piece_node.z_index = release_z_index
	piece_node.position = destination
	piece_released.emit(piece_node)
	_play_hand_sound(SOUND_RELEASE)

	# A compound move such as castling can keep the open hand on the board and
	# continue directly to its next piece.
	_set_elevated_depth()
	if retreat_offscreen:
		await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
		visible = false
		is_animating = false
		move_animation_finished.emit()


func play_piece_capture(
	attacker_node: Node2D,
	defender_node: Node2D,
	destination: Vector2,
	world_scale: float,
	final_piece_z_index := -1
) -> bool:
	if not can_animate() or not is_instance_valid(attacker_node) or not is_instance_valid(defender_node):
		return false

	# Raise the open hand to the attacker and close around it just like a normal move.
	is_animating = true
	captured_piece_pivot.position = Vector2.ZERO
	captured_piece_pivot.rotation = 0.0
	var effective_hand_scale := world_scale * art_scale_multiplier
	scale = Vector2.ONE * effective_hand_scale
	_apply_pose(false)
	pose_changed.emit(&"open")

	var attacker_parent := attacker_node.get_parent()
	var attacker_scale := attacker_node.scale
	var attacker_z_index := attacker_node.z_index
	var release_z_index := final_piece_z_index if final_piece_z_index >= 0 else attacker_z_index
	var attacker_origin := attacker_node.position
	var attacker_contact := _piece_grip_position(attacker_node)
	var destination_contact := attacker_contact + destination - attacker_origin
	var defender_contact := _piece_grip_position(defender_node)
	var defender_z_index := defender_node.z_index
	var capture_swipe_base_depth := mini(attacker_z_index, defender_z_index - DEPTH_BAND_STRIDE)

	position = _offscreen_rest_position(effective_hand_scale)
	_set_grounded_depth(attacker_z_index)
	visible = true
	await _tween_approach_position(attacker_contact, approach_duration, world_scale)
	attacker_node.reparent(piece_slot, true)
	attacker_node.z_index = 0
	piece_grabbed.emit(attacker_node)
	_apply_pose(true)
	pose_changed.emit(&"closed")
	_play_hand_sound(SOUND_GRAB)
	await _wait(grasp_hold_duration)

	# Arc to the defender's left, then swipe across it in a straight line.
	# Keep the waiting defender at its board depth so the approaching hand passes
	# over it. At contact, _attach_captured_piece moves it between the hand's
	# back and front artwork.
	capture_stage_changed.emit(&"initiation")
	carry_path_started.emit(CARRY_PATH_JUMP)
	var role_x := -1.0 if seat == Seat.FAR else 1.0
	var swipe_start := defender_contact + Vector2.LEFT * role_x * capture_approach_offset * world_scale
	_set_elevated_depth()
	await _tween_jump_position(swipe_start, capture_approach_duration, capture_approach_arc_height * world_scale)
	# Until contact, treat the defender as the naturally nearer object so it can
	# remain in front of board-occludable grip artwork without changing its z.
	_set_grounded_depth(capture_swipe_base_depth)
	var swipe_end := swipe_start + Vector2.RIGHT * role_x * capture_swipe_distance * world_scale
	capture_stage_changed.emit(&"swipe")
	var pickup_progress := 0.0
	if capture_swipe_distance > 0.0:
		pickup_progress = clampf(capture_approach_offset / capture_swipe_distance, 0.0, 1.0)
	var pickup_state := {"attached": false}
	var swipe_tween := create_tween()
	swipe_tween.tween_method(
		func(progress: float):
			position = swipe_start.lerp(swipe_end, progress)
			if not pickup_state["attached"] and progress >= pickup_progress:
				pickup_state["attached"] = true
				_set_grounded_depth(defender_z_index)
				_attach_captured_piece(attacker_node, defender_node, world_scale),
		0.0,
		1.0,
		capture_swipe_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await swipe_tween.finished
	if not pickup_state["attached"]:
		_set_grounded_depth(defender_z_index)
		_attach_captured_piece(attacker_node, defender_node, world_scale)

	# Jump to the destination and leave the attacker on its exact square. Keep the
	# hand closed around the captured defender while carrying it offscreen.
	capture_stage_changed.emit(&"placement")
	_set_elevated_depth()
	await _tween_jump_position(destination_contact, capture_placement_duration, capture_placement_arc_height * world_scale)
	_set_grounded_depth(release_z_index)
	_play_board_sound(SOUND_PLACE)
	await _wait(release_hold_duration)
	attacker_node.reparent(attacker_parent, true)
	attacker_node.scale = attacker_scale
	attacker_node.z_index = release_z_index
	attacker_node.position = destination
	piece_released.emit(attacker_node)
	_play_hand_sound(SOUND_RELEASE)

	# Retreat below the screen with the captured piece; its normal removal can now be silent.
	capture_stage_changed.emit(&"exit")
	_set_elevated_depth()
	await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
	visible = false
	is_animating = false
	move_animation_finished.emit()
	return true


func play_piece_attack(piece_node: Node2D, target: Vector2, world_scale: float, contact_callback: Callable = Callable(), final_piece_z_index := -1) -> void:
	if not can_animate() or not is_instance_valid(piece_node):
		return

	is_animating = true
	var effective_hand_scale := world_scale * art_scale_multiplier
	scale = Vector2.ONE * effective_hand_scale
	_apply_pose(false)
	pose_changed.emit(&"open")

	var original_parent := piece_node.get_parent()
	var original_scale := piece_node.scale
	var original_z_index := piece_node.z_index
	var release_z_index := final_piece_z_index if final_piece_z_index >= 0 else original_z_index
	var origin := piece_node.position
	var contact_position := _piece_grip_position(piece_node)
	var target_contact := contact_position + target - origin

	position = _offscreen_rest_position(effective_hand_scale)
	_set_grounded_depth(original_z_index)
	visible = true
	await _tween_approach_position(contact_position, approach_duration, world_scale)
	piece_node.reparent(piece_slot, true)
	piece_node.z_index = 0
	piece_grabbed.emit(piece_node)
	_apply_pose(true)
	pose_changed.emit(&"closed")
	_play_hand_sound(SOUND_GRAB)
	await _wait(grasp_hold_duration)

	carry_path_started.emit(&"slam")
	_set_elevated_depth()
	await _tween_attack_position(target_contact, attack_slam_duration, Tween.EASE_IN)
	if contact_callback.is_valid():
		contact_callback.call()
	attack_contact.emit(piece_node)
	await _tween_attack_position(contact_position, attack_rebound_duration, Tween.EASE_OUT)
	_set_grounded_depth(original_z_index)

	_apply_pose(false)
	pose_changed.emit(&"open")
	piece_node.reparent(original_parent, true)
	piece_node.scale = original_scale
	piece_node.z_index = release_z_index
	piece_node.position = origin
	piece_released.emit(piece_node)
	_play_hand_sound(SOUND_RELEASE)

	_set_elevated_depth()
	await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
	visible = false
	is_animating = false
	move_animation_finished.emit()


func _attach_captured_piece(attacker_node: Node2D, defender_node: Node2D, world_scale: float) -> void:
	# Pin the defender's grip to the pivot, so tilting it cannot lift the entire piece.
	defender_node.reparent(captured_piece_pivot, true)
	defender_node.z_index = 0
	var attacker_anchor := _get_grip_anchor(attacker_node)
	var defender_anchor := _get_grip_anchor(defender_node)
	if attacker_anchor != null:
		captured_piece_pivot.global_position = attacker_anchor.global_position + captured_piece_grip_offset * world_scale
	captured_piece_pivot.rotation = deg_to_rad(captured_piece_rotation_degrees)
	if defender_anchor != null:
		defender_node.global_position += captured_piece_pivot.global_position - defender_anchor.global_position
	_play_board_sound(SOUND_CAPTURE_PICKUP)
	captured_piece_grabbed.emit(defender_node)


func _play_hand_sound(cue: StringName) -> void:
	if hand_style == null or hand_style.sounds == null:
		return
	var sound_set: ChessHandSoundSet = hand_style.sounds
	var player: AudioStreamPlayer
	var stream: AudioStream
	match cue:
		SOUND_GRAB:
			player = grab_sound
			stream = sound_set.grab
		SOUND_RELEASE:
			player = release_sound
			stream = sound_set.release
	_play_one_shot(player, stream, sound_set.volume_db, sound_set.pitch_variation)


func _play_board_sound(cue: StringName) -> void:
	if board_sound_set == null:
		return
	# Universal cues are temporary; future piece/board material properties will
	# resolve the appropriate stream before this playback step.
	var player: AudioStreamPlayer
	var stream: AudioStream
	match cue:
		SOUND_CAPTURE_PICKUP:
			player = capture_pickup_sound
			stream = board_sound_set.default_capture_pickup
		SOUND_PLACE:
			player = place_sound
			stream = board_sound_set.default_place
	_play_one_shot(player, stream, board_sound_set.volume_db, board_sound_set.pitch_variation)


func _play_one_shot(player: AudioStreamPlayer, stream: AudioStream, volume_db: float, pitch_variation: float) -> void:
	if player == null or stream == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.play()


func _start_slide_sound() -> void:
	if board_sound_set == null or board_sound_set.default_slide == null:
		return
	if slide_fade_tween != null and slide_fade_tween.is_valid():
		slide_fade_tween.kill()
	slide_sound.stream = board_sound_set.default_slide
	slide_sound.volume_db = board_sound_set.volume_db
	slide_sound.pitch_scale = randf_range(1.0 - board_sound_set.pitch_variation, 1.0 + board_sound_set.pitch_variation)
	slide_sound.play()


func _stop_slide_sound() -> void:
	if not slide_sound.playing:
		return
	if board_sound_set == null or board_sound_set.slide_fade_duration <= 0.0:
		slide_sound.stop()
		return
	slide_fade_tween = create_tween()
	slide_fade_tween.tween_property(slide_sound, "volume_db", -60.0, board_sound_set.slide_fade_duration)
	slide_fade_tween.tween_callback(slide_sound.stop)


func _piece_grip_position(piece_node: Node2D) -> Vector2:
	var anchor := _get_grip_anchor(piece_node)
	if anchor != null:
		return get_parent().to_local(anchor.to_global(piece_grip_offset))
	return piece_node.position


func _get_grip_anchor(piece_node: Node2D) -> Node2D:
	if piece_node.has_method("get_grip_anchor"):
		return piece_node.get_grip_anchor() as Node2D
	return null


func _offscreen_rest_position(world_scale: float) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var bounds := _art_bounds_from_grip()
	var margin := offscreen_margin * world_scale
	if seat == Seat.FAR:
		return Vector2(-bounds.end.x * world_scale - margin, -bounds.end.y * world_scale - margin)
	return Vector2(viewport_size.x - bounds.position.x * world_scale + margin, viewport_size.y - bounds.position.y * world_scale + margin)


func _art_bounds_from_grip() -> Rect2:
	var combined := Rect2(-grip_anchor_pixels, Vector2.ONE)
	var initialized := false
	if hand_style != null:
		for texture in [hand_style.open_grip_back, hand_style.open_grip_front, hand_style.open_arm_foreground, hand_style.closed_grip_back, hand_style.closed_grip_front, hand_style.closed_arm_foreground]:
			if texture == null:
				continue
			var texture_rect := Rect2(-grip_anchor_pixels, texture.get_size())
			combined = texture_rect if not initialized else combined.merge(texture_rect)
			initialized = true
	if visual_mirrored:
		combined = Rect2(Vector2(-combined.end.x, combined.position.y), combined.size)
	return combined


func _apply_pose(closed: bool) -> void:
	if hand_style == null:
		arm_foreground_sprite.texture = null
		grip_back_sprite.texture = null
		grip_front_sprite.texture = null
		return
	arm_foreground_sprite.texture = hand_style.closed_arm_foreground if closed else hand_style.open_arm_foreground
	grip_back_sprite.texture = hand_style.closed_grip_back if closed else hand_style.open_grip_back
	grip_front_sprite.texture = hand_style.closed_grip_front if closed else hand_style.open_grip_front
	for sprite in [arm_foreground_sprite, grip_back_sprite, grip_front_sprite]:
		_position_sprite_from_grip(sprite)
		sprite.visible = sprite.texture != null


func _position_sprite_from_grip(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	var unmirrored_position := Vector2(sprite.texture.get_size()) * 0.5 - grip_anchor_pixels
	sprite.flip_h = visual_mirrored
	sprite.position = Vector2(-unmirrored_position.x, unmirrored_position.y) if visual_mirrored else unmirrored_position


func _tween_position(target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration * animation_duration_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _tween_grounded_position(target: Vector2, duration: float, start_depth: int, destination_depth: int) -> void:
	var start := position
	var tween := create_tween()
	tween.tween_method(
		func(progress: float):
			position = start.lerp(target, progress)
			# Depth bands are discrete ten-slot rows. Snap to the nearest band so
			# local offsets never spill into the next row's ordinary piece slot.
			var interpolated_band := calculate_grounded_base_depth(start_depth, destination_depth, progress)
			_set_grounded_depth(interpolated_band),
		0.0,
		1.0,
		duration * animation_duration_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	position = target
	_set_grounded_depth(destination_depth)


static func calculate_grounded_base_depth(start_depth: int, destination_depth: int, progress: float) -> int:
	return roundi(lerpf(float(start_depth), float(destination_depth), clampf(progress, 0.0, 1.0)) / float(DEPTH_BAND_STRIDE)) * DEPTH_BAND_STRIDE


func _tween_attack_position(target: Vector2, duration: float, easing: Tween.EaseType) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration * animation_duration_scale).set_trans(Tween.TRANS_QUAD).set_ease(easing)
	await tween.finished


func _tween_approach_position(target: Vector2, duration: float, world_scale: float) -> void:
	has_approach_preview = true
	approach_preview_start = position
	approach_preview_target = target
	approach_preview_world_scale = world_scale
	approach_preview_progress = 0.0
	_refresh_live_approach()
	var tween := create_tween()
	tween.tween_method(
		func(progress: float):
			approach_preview_progress = progress
			_refresh_live_approach(),
		0.0,
		1.0,
		duration * animation_duration_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _refresh_live_approach() -> void:
	if not is_node_ready() or not has_approach_preview:
		return
	# Seat changes which side the hand enters from, but lift is board-relative:
	# both hands must rise toward screen-up rather than rotating the choreography
	# 180 degrees. Only mirror the horizontal arrival-handle component.
	var role_basis := Vector2(-1.0, 1.0) if seat == Seat.FAR else Vector2.ONE
	var departure_control := approach_preview_start.lerp(approach_preview_target, approach_departure_progress) + Vector2.UP * approach_departure_lift * approach_preview_world_scale
	var arrival_control := approach_preview_target + approach_arrival_handle * role_basis * approach_preview_world_scale
	position = calculate_bezier_position(approach_preview_start, departure_control, arrival_control, approach_preview_target, approach_preview_progress)
	_update_approach_path_debug(approach_preview_start, departure_control, arrival_control, approach_preview_target)


func _update_approach_path_debug(start: Vector2, departure_control: Vector2, arrival_control: Vector2, target: Vector2) -> void:
	approach_path_debug.visible = show_approach_path_debug
	if not show_approach_path_debug:
		return
	var points := PackedVector2Array()
	for index in range(33):
		points.append(calculate_bezier_position(start, departure_control, arrival_control, target, index / 32.0))
	approach_path_debug.points = points


static func calculate_bezier_position(start: Vector2, departure_control: Vector2, arrival_control: Vector2, destination: Vector2, progress: float) -> Vector2:
	return start.bezier_interpolate(departure_control, arrival_control, destination, clampf(progress, 0.0, 1.0))


func _tween_jump_position(target: Vector2, duration: float, arc_height: float) -> void:
	var start := position
	var tween := create_tween()
	tween.tween_method(
		# A jump represents lifting away from the board, so its screen-space arc
		# remains upward for near and far hands alike.
		func(progress: float): position = calculate_jump_position(start, target, progress, arc_height),
		0.0,
		1.0,
			duration * animation_duration_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


static func calculate_jump_position(start: Vector2, destination: Vector2, progress: float, arc_height: float) -> Vector2:
	var normalized_progress := clampf(progress, 0.0, 1.0)
	var straight_position := start.lerp(destination, normalized_progress)
	var lift := 4.0 * arc_height * normalized_progress * (1.0 - normalized_progress)
	return straight_position + Vector2.UP * lift


func _wait(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration * animation_duration_scale).timeout
