extends Node2D
class_name PlayerHandRig

signal pose_changed(pose: StringName)
signal piece_grabbed(piece: Node2D)
signal piece_released(piece: Node2D)
signal carry_path_started(path: StringName)
signal capture_stage_changed(stage: StringName)
signal captured_piece_grabbed(piece: Node2D)
signal attack_contact(piece: Node2D)
signal move_animation_finished()
signal setup_piece_placed(piece: Node2D)

const CARRY_PATH_SLIDE := &"slide"
const CARRY_PATH_JUMP := &"jump"
const SOUND_GRAB := &"grab"
const SOUND_CAPTURE_PICKUP := &"capture_pickup"
const SOUND_PLACE := &"place"
const SOUND_RELEASE := &"release"
## Absolute board-canvas interaction stack above ordinary pieces (0-70).
const REAR_FINGERS_Z := 72
const ACTIVE_PIECE_Z := 73
const CAPTURED_PIECE_Z := 74
const PLACEMENT_OCCLUDER_Z := 75
const THUMB_FOREGROUND_Z := 76
const INTERACTION_OCCLUDER_Z := 77
const ARM_FOREGROUND_Z := 80
## Palm point in the 96 x 160 source artwork where activation energy originates.
## Keeping this in source-pixel space makes it independent of the rig's grip
## origin and of whatever scale the board applies to the hand.
const CONNECTION_ANCHOR_PIXELS := Vector2(23.0, 24.0)

@export var hand_style: Resource
## Grip location measured from the top-left of the 96 x 160 source artwork.
@export var grip_anchor_pixels := Vector2(11.0, 29.0)
## Offset from the piece's configured GripAnchor, measured in local piece pixels.
@export var piece_grip_offset := Vector2(0.0, 6.0)
@export_range(0.25, 4.0, 0.05) var art_scale_multiplier := 3.5
@export_group("Approach Curve")
@export_range(0.01, 2.0, 0.01) var approach_duration := 0.24 # Time taken to travel from the lower-right rest point to the first piece.
@export_range(0.0, 1.0, 0.01) var approach_departure_progress := 0.45: # Places the first Bezier handle this far along the start-to-piece line.
	set(value):
		approach_departure_progress = value
		_refresh_live_approach()
@export_range(0.0, 256.0, 1.0) var approach_departure_lift := 96.0: # Pulls the first handle upward, controlling how early the hand rises.
	set(value):
		approach_departure_lift = value
		_refresh_live_approach()
@export var approach_arrival_handle := Vector2(32.0, -96.0): # Offset from the grip to the second handle; negative Y makes the hand arrive from above.
	set(value):
		approach_arrival_handle = value
		_refresh_live_approach()
@export var show_approach_path_debug := false: # Draws the computed Bezier in-game; toggle this and edit the handles in Godot's Remote inspector.
	set(value):
		show_approach_path_debug = value
		_refresh_live_approach()
@export_group("")
@export_range(0.0, 1.0, 0.01) var grasp_hold_duration := 0.18
@export_range(0.01, 2.0, 0.01) var carry_duration := .24
@export_range(0.0, 128.0, 1.0) var jump_arc_height := 32.0
@export_range(0.01, 2.0, 0.01) var jump_carry_duration := 0.36
@export_range(0.01, 2.0, 0.01) var attack_slam_duration := 0.16
@export_range(0.01, 2.0, 0.01) var attack_rebound_duration := 0.28
@export_range(0.0, 64.0, 1.0) var capture_approach_offset := 18.0 # Distance left of the defender where the capture approach ends.
@export_range(0.0, 128.0, 1.0) var capture_approach_arc_height := 32.0 # Height of the arc used to approach a capture.
@export_range(0.01, 2.0, 0.01) var capture_approach_duration := 0.18 # Time taken to arc toward the defender's left side.
@export_range(0.0, 128.0, 1.0) var capture_swipe_distance := 36.0 # Total left-to-right distance of the pickup swipe.
@export_range(0.01, 2.0, 0.01) var capture_swipe_duration := 0.18 # Time taken to swipe across and collect the defender.
@export var captured_piece_grip_offset := Vector2.ZERO # Fine-tunes the captured grip relative to the attacker's grip.
@export_range(-180.0, 180.0, 1.0) var captured_piece_rotation_degrees := -20.0 # Tilts the captured piece while it is carried away.
@export_range(0.0, 128.0, 1.0) var capture_placement_arc_height := 32.0 # Height of the arc used to place the attacker.
@export_range(0.01, 2.0, 0.01) var capture_placement_duration := 0.30 # Time taken to arc back and place the attacker.
@export_range(0.0, 1.0, 0.01) var release_hold_duration := 0.35
@export_range(0.01, 2.0, 0.01) var retreat_duration := 0.24
@export_range(0.0, 128.0, 1.0) var offscreen_margin := 8.0

@onready var rear_fingers_sprite: Sprite2D = $RearFingers
@onready var captured_piece_pivot: Node2D = $CapturedPiecePivot
@onready var piece_slot: Node2D = $PieceSlot
@onready var thumb_sprite: Sprite2D = $Thumb
@onready var arm_sprite: Sprite2D = $Arm
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
var interaction_occluder_depths: Dictionary = {}
var visual_mirrored := false
var setup_paused := false
var setup_generation := 0
var setup_piece: Node2D
var setup_piece_parent: Node
var setup_piece_scale := Vector2.ONE
var setup_piece_z := 0


func _ready() -> void:
	# Keep the tuning overlay in board space so hiding the hand does not also hide
	# the last computed curve.
	_detach_approach_path_debug.call_deferred()
	visible = false
	rear_fingers_sprite.z_index = REAR_FINGERS_Z
	piece_slot.z_index = ACTIVE_PIECE_Z
	captured_piece_pivot.z_index = CAPTURED_PIECE_Z
	thumb_sprite.z_index = THUMB_FOREGROUND_Z
	arm_sprite.z_index = ARM_FOREGROUND_Z
	_apply_pose(false)


func _detach_approach_path_debug() -> void:
	if is_instance_valid(approach_path_debug) and approach_path_debug.get_parent() == self:
		approach_path_debug.reparent(get_parent(), false)


func set_hand_style(style: Resource) -> void:
	hand_style = style
	if is_node_ready():
		_apply_pose(false)


func set_board_sound_set(sound_set: ChessBoardSoundSet) -> void:
	board_sound_set = sound_set


## Mirrors the hand around its grip without mirroring a carried chess piece.
func set_visual_mirrored(mirrored: bool) -> void:
	visual_mirrored = mirrored
	if is_node_ready():
		_apply_pose(false)


func get_aura_sprites() -> Array[Sprite2D]:
	return [rear_fingers_sprite, thumb_sprite, arm_sprite]


func get_connection_anchor_position() -> Vector2:
	var anchor := CONNECTION_ANCHOR_PIXELS - grip_anchor_pixels
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
	var contact_position := _piece_grip_position(piece_node)
	position = contact_position
	piece_node.visible = true
	piece_node.z_index = ACTIVE_PIECE_Z
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
	visible = false
	is_animating = false
	setup_paused = false


func _setup_rest_position(world_scale: float) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var x := -(grip_anchor_pixels.x + offscreen_margin) * world_scale if visual_mirrored else viewport_size.x + (grip_anchor_pixels.x + offscreen_margin) * world_scale
	return Vector2(x, viewport_size.y + (grip_anchor_pixels.y + offscreen_margin) * world_scale)


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
	interaction_occluders: Array[Node2D] = [],
	pickup_occluders: Array[Node2D] = [],
	placement_occluders: Array[Node2D] = [],
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
		_restore_interaction_occluders()
		position = _offscreen_rest_position(effective_hand_scale)
	_promote_interaction_occluders(interaction_occluders, piece_node)
	_promote_interaction_occluders(pickup_occluders, piece_node, PLACEMENT_OCCLUDER_Z)
	piece_node.z_index = ACTIVE_PIECE_Z
	visible = true
	if enter_from_offscreen:
		await _tween_approach_position(contact_position, approach_duration, world_scale)
	else:
		await _tween_position(contact_position, approach_duration)

	# Place the piece between the rear fingers and front thumb, then close the hand.
	piece_node.reparent(piece_slot, true)
	piece_node.z_index = 0
	piece_grabbed.emit(piece_node)
	_apply_pose(true)
	pose_changed.emit(&"closed")
	_play_hand_sound(SOUND_GRAB)
	await _wait(grasp_hold_duration)

	# Carry the closed hand and grabbed piece to the destination together.
	_promote_interaction_occluders(placement_occluders, piece_node, PLACEMENT_OCCLUDER_Z)
	carry_path_started.emit(carry_path)
	if carry_path == CARRY_PATH_JUMP:
		await _tween_jump_position(destination_contact, jump_carry_duration, jump_arc_height * world_scale)
	else:
		_start_slide_sound()
		await _tween_position(destination_contact, carry_duration)
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
	if retreat_offscreen:
		await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
		visible = false
		_restore_interaction_occluders()
		is_animating = false
		move_animation_finished.emit()


func play_piece_capture(
	attacker_node: Node2D,
	defender_node: Node2D,
	destination: Vector2,
	world_scale: float,
	interaction_occluders: Array[Node2D] = [],
	pickup_occluders: Array[Node2D] = [],
	placement_occluders: Array[Node2D] = [],
	final_piece_z_index := -1
) -> bool:
	if not can_animate() or not is_instance_valid(attacker_node) or not is_instance_valid(defender_node):
		return false

	# Raise the open hand to the attacker and close around it just like a normal move.
	is_animating = true
	_restore_interaction_occluders()
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

	position = _offscreen_rest_position(effective_hand_scale)
	_promote_interaction_occluders(interaction_occluders, attacker_node)
	_promote_interaction_occluders(pickup_occluders, attacker_node, PLACEMENT_OCCLUDER_Z)
	attacker_node.z_index = ACTIVE_PIECE_Z
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
	var swipe_start := defender_contact + Vector2.LEFT * capture_approach_offset * world_scale
	await _tween_jump_position(swipe_start, capture_approach_duration, capture_approach_arc_height * world_scale)
	var swipe_end := swipe_start + Vector2.RIGHT * capture_swipe_distance * world_scale
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
				_attach_captured_piece(attacker_node, defender_node, world_scale),
		0.0,
		1.0,
		capture_swipe_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await swipe_tween.finished
	if not pickup_state["attached"]:
		_attach_captured_piece(attacker_node, defender_node, world_scale)

	# Jump to the destination and leave the attacker on its exact square. Keep the
	# hand closed around the captured defender while carrying it offscreen.
	capture_stage_changed.emit(&"placement")
	_promote_interaction_occluders(placement_occluders, attacker_node, PLACEMENT_OCCLUDER_Z)
	await _tween_jump_position(destination_contact, capture_placement_duration, capture_placement_arc_height * world_scale)
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
	await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
	visible = false
	_restore_interaction_occluders()
	is_animating = false
	move_animation_finished.emit()
	return true


func play_piece_attack(piece_node: Node2D, target: Vector2, world_scale: float, contact_callback: Callable = Callable(), interaction_occluders: Array[Node2D] = [], pickup_occluders: Array[Node2D] = [], final_piece_z_index := -1) -> void:
	if not can_animate() or not is_instance_valid(piece_node):
		return

	is_animating = true
	_restore_interaction_occluders()
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
	_promote_interaction_occluders(interaction_occluders, piece_node)
	_promote_interaction_occluders(pickup_occluders, piece_node, PLACEMENT_OCCLUDER_Z)
	piece_node.z_index = ACTIVE_PIECE_Z
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
	await _tween_attack_position(target_contact, attack_slam_duration, Tween.EASE_IN)
	if contact_callback.is_valid():
		contact_callback.call()
	attack_contact.emit(piece_node)
	await _tween_attack_position(contact_position, attack_rebound_duration, Tween.EASE_OUT)

	_apply_pose(false)
	pose_changed.emit(&"open")
	piece_node.reparent(original_parent, true)
	piece_node.scale = original_scale
	piece_node.z_index = release_z_index
	piece_node.position = origin
	piece_released.emit(piece_node)
	_play_hand_sound(SOUND_RELEASE)

	await _tween_position(_offscreen_rest_position(effective_hand_scale), retreat_duration)
	visible = false
	_restore_interaction_occluders()
	is_animating = false
	move_animation_finished.emit()


func _attach_captured_piece(attacker_node: Node2D, defender_node: Node2D, world_scale: float) -> void:
	# Pin the defender's grip to the pivot, so tilting it cannot lift the entire piece.
	_release_interaction_occluder(defender_node)
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


func _promote_interaction_occluders(occluders: Array[Node2D], active_piece: Node2D = null, target_z_index := INTERACTION_OCCLUDER_Z) -> void:
	for occluder in occluders:
		if not is_instance_valid(occluder) or occluder == active_piece:
			continue
		if not interaction_occluder_depths.has(occluder):
			interaction_occluder_depths[occluder] = occluder.z_index
		occluder.z_index = maxi(occluder.z_index, target_z_index)


func _release_interaction_occluder(occluder: Node2D) -> void:
	if not interaction_occluder_depths.has(occluder):
		return
	if is_instance_valid(occluder):
		occluder.z_index = int(interaction_occluder_depths[occluder])
	interaction_occluder_depths.erase(occluder)


func _restore_interaction_occluders() -> void:
	for occluder in interaction_occluder_depths.keys():
		if is_instance_valid(occluder):
			occluder.z_index = int(interaction_occluder_depths[occluder])
	interaction_occluder_depths.clear()


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
	return Vector2(
		viewport_size.x + (grip_anchor_pixels.x + offscreen_margin) * world_scale,
		viewport_size.y + (grip_anchor_pixels.y + offscreen_margin) * world_scale
	)


func _apply_pose(closed: bool) -> void:
	if hand_style == null:
		arm_sprite.texture = null
		rear_fingers_sprite.texture = null
		thumb_sprite.texture = null
		return
	arm_sprite.texture = hand_style.closed_arm if closed else hand_style.open_arm
	rear_fingers_sprite.texture = hand_style.closed_rear_fingers if closed else hand_style.open_rear_fingers
	thumb_sprite.texture = hand_style.closed_thumb if closed else hand_style.open_thumb
	for sprite in [arm_sprite, rear_fingers_sprite, thumb_sprite]:
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
	var departure_control := approach_preview_start.lerp(approach_preview_target, approach_departure_progress) + Vector2.UP * approach_departure_lift * approach_preview_world_scale
	var arrival_control := approach_preview_target + approach_arrival_handle * approach_preview_world_scale
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
