extends Node2D
class_name PlayerHandRig

signal pose_changed(pose: StringName)
signal piece_grabbed(piece: Node2D)
signal piece_released(piece: Node2D)
signal move_animation_finished()

@export var hand_style: Resource
## Grip location measured from the top-left of the 96 x 160 source artwork.
@export var grip_anchor_pixels := Vector2(11.0, 29.0)
## Offset from the piece's HeadAnchor, measured in the piece's local pixels.
@export var piece_grip_offset := Vector2(0.0, 6.0)
@export_range(0.25, 4.0, 0.05) var art_scale_multiplier := 3.5
@export_range(0.01, 2.0, 0.01) var approach_duration := 0.24
@export_range(0.0, 1.0, 0.01) var grasp_hold_duration := 0.18
@export_range(0.01, 2.0, 0.01) var carry_duration := .24
@export_range(0.0, 1.0, 0.01) var release_hold_duration := 0.35
@export_range(0.01, 2.0, 0.01) var retreat_duration := 0.24
@export_range(0.0, 128.0, 1.0) var offscreen_margin := 8.0

@onready var back_sprite: Sprite2D = $Back
@onready var piece_slot: Node2D = $PieceSlot
@onready var front_sprite: Sprite2D = $Front

var is_animating := false


func _ready() -> void:
	visible = false
	_apply_pose(false)


func set_hand_style(style: Resource) -> void:
	hand_style = style
	if is_node_ready():
		_apply_pose(false)


func can_animate() -> bool:
	return hand_style != null and hand_style.has_method("is_complete") and hand_style.is_complete()


func play_piece_move(piece_node: Node2D, destination: Vector2, world_scale: float) -> void:
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
	var origin := piece_node.position
	var contact_position := _piece_grip_position(piece_node)
	var destination_contact := contact_position + destination - origin

	# Raise the open hand from below the screen to the piece's grip point.
	position = _offscreen_position(contact_position.x, effective_hand_scale)
	visible = true
	await _tween_position(contact_position, approach_duration)

	# Place the piece between the rear fingers and front thumb, then close the hand.
	piece_node.reparent(piece_slot, true)
	piece_node.z_index = 0
	piece_grabbed.emit(piece_node)
	_apply_pose(true)
	pose_changed.emit(&"closed")
	await _wait(grasp_hold_duration)

	# Carry the closed hand and grabbed piece to the destination together.
	await _tween_position(destination_contact, carry_duration)
	await _wait(release_hold_duration)

	# Open the hand, return the piece to the board, and snap it to its exact square.
	_apply_pose(false)
	pose_changed.emit(&"open")
	piece_node.reparent(original_parent, true)
	piece_node.scale = original_scale
	piece_node.z_index = original_z_index
	piece_node.position = destination
	piece_released.emit(piece_node)

	# Lower the empty open hand until it is fully out of view.
	await _tween_position(_offscreen_position(destination_contact.x, effective_hand_scale), retreat_duration)
	visible = false
	is_animating = false
	move_animation_finished.emit()


func _piece_grip_position(piece_node: Node2D) -> Vector2:
	if piece_node.has_method("get_grip_anchor"):
		var anchor := piece_node.get_grip_anchor() as Node2D
		return get_parent().to_local(anchor.to_global(piece_grip_offset))
	return piece_node.position


func _offscreen_position(horizontal_position: float, world_scale: float) -> Vector2:
	var viewport_bottom := get_viewport_rect().size.y
	return Vector2(
		horizontal_position,
		viewport_bottom + (grip_anchor_pixels.y + offscreen_margin) * world_scale
	)


func _apply_pose(closed: bool) -> void:
	if hand_style == null:
		back_sprite.texture = null
		front_sprite.texture = null
		return
	back_sprite.texture = hand_style.closed_back if closed else hand_style.open_back
	front_sprite.texture = hand_style.closed_front if closed else hand_style.open_front
	_position_sprite_from_grip(back_sprite)
	_position_sprite_from_grip(front_sprite)
	front_sprite.visible = front_sprite.texture != null


func _position_sprite_from_grip(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	sprite.position = Vector2(sprite.texture.get_size()) * 0.5 - grip_anchor_pixels


func _tween_position(target: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _wait(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
