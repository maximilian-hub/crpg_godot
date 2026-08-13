extends CharacterBody2D
class_name OverworldPlayer

signal step_finished(cell: Vector2i)

enum MovementState { GRID_IDLE, GRID_STEPPING, INPUT_LOCKED }

const CELL_SIZE := 16
const DIRECTIONS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

@onready var body: AnimatedSprite2D = $Body

@export_range(0.05, 1.0, 0.01) var step_duration: float = 0.14

var movement_state := MovementState.INPUT_LOCKED
var grid_cell := Vector2i.ZERO
var facing := Vector2i.UP
var target_cell := Vector2i.ZERO
var step_origin_cell := Vector2i.ZERO
var queued_direction := Vector2i.ZERO
var input_lock_pending: bool = false
var step_landing_frame: int = 2
var collision_grid: OverworldCollisionGrid
var blocking_npc: OverworldNpc

func configure(
	p_collision_grid: OverworldCollisionGrid,
	p_blocking_npc: OverworldNpc,
	start_cell: Vector2i,
	start_facing: Vector2i
) -> void:
	collision_grid = p_collision_grid
	blocking_npc = p_blocking_npc
	grid_cell = start_cell
	target_cell = start_cell
	step_origin_cell = start_cell
	facing = start_facing
	position = cell_center(start_cell)
	velocity = Vector2.ZERO
	queued_direction = Vector2i.ZERO
	input_lock_pending = false
	movement_state = MovementState.GRID_IDLE
	_sync_animation()

func set_input_enabled(enabled: bool) -> void:
	if enabled:
		input_lock_pending = false
		if movement_state == MovementState.INPUT_LOCKED:
			movement_state = MovementState.GRID_IDLE
	else:
		queued_direction = Vector2i.ZERO
		velocity = Vector2.ZERO
		if movement_state == MovementState.GRID_STEPPING:
			input_lock_pending = true
		else:
			movement_state = MovementState.INPUT_LOCKED
	_sync_animation()

func is_grid_idle() -> bool:
	return movement_state == MovementState.GRID_IDLE

func _unhandled_input(event: InputEvent) -> void:
	if movement_state == MovementState.INPUT_LOCKED:
		return
	for action in DIRECTIONS:
		if event.is_action_pressed(action):
			var direction: Vector2i = DIRECTIONS[action]
			facing = direction
			if movement_state == MovementState.GRID_STEPPING:
				queued_direction = direction
			else:
				_try_begin_step(direction)
			get_viewport().set_input_as_handled()
			return

func _physics_process(delta: float) -> void:
	if movement_state != MovementState.GRID_STEPPING:
		velocity = Vector2.ZERO
		return

	var target_position := cell_center(target_cell)
	var remaining := target_position - position
	var max_travel := (float(CELL_SIZE) / step_duration) * delta
	if remaining.length() <= max_travel:
		var collision := move_and_collide(remaining)
		if collision != null:
			_cancel_step_after_contact()
			return
		position = target_position
		grid_cell = target_cell
		velocity = Vector2.ZERO
		body.set_frame_and_progress(step_landing_frame, 0.0)
		movement_state = MovementState.GRID_IDLE
		step_finished.emit(grid_cell)
		if input_lock_pending:
			input_lock_pending = false
			movement_state = MovementState.INPUT_LOCKED
		else:
			_begin_buffered_or_held_step()
		_sync_animation()
		return

	velocity = remaining.normalized() * (float(CELL_SIZE) / step_duration)
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_cancel_step_after_contact()

func _try_begin_step(direction: Vector2i) -> bool:
	if movement_state != MovementState.GRID_IDLE:
		return false
	facing = direction
	var requested_cell := grid_cell + direction
	if not _is_traversable(requested_cell):
		_sync_animation()
		return false
	step_origin_cell = grid_cell
	target_cell = requested_cell
	var requested_walk := StringName("walk_" + _direction_name(direction))
	step_landing_frame = 0 if body.animation == requested_walk and body.is_playing() and body.frame == 2 else 2
	movement_state = MovementState.GRID_STEPPING
	_sync_animation()
	return true

func _is_traversable(cell: Vector2i) -> bool:
	if collision_grid == null or collision_grid.is_boundary_blocked(grid_cell, cell):
		return false
	if blocking_npc != null and blocking_npc.grid_cell == cell:
		return false
	return true

func _cancel_step_after_contact() -> void:
	position = cell_center(step_origin_cell)
	target_cell = step_origin_cell
	grid_cell = step_origin_cell
	velocity = Vector2.ZERO
	queued_direction = Vector2i.ZERO
	movement_state = MovementState.INPUT_LOCKED if input_lock_pending else MovementState.GRID_IDLE
	input_lock_pending = false
	_sync_animation()

func _begin_buffered_or_held_step() -> void:
	var next_direction := queued_direction
	queued_direction = Vector2i.ZERO
	if next_direction == Vector2i.ZERO:
		next_direction = _get_held_direction()
	if next_direction != Vector2i.ZERO:
		_try_begin_step(next_direction)

func _get_held_direction() -> Vector2i:
	# Favor the current facing direction, then use a stable fallback order.
	for action in DIRECTIONS:
		if DIRECTIONS[action] == facing and Input.is_action_pressed(action):
			return facing
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			return DIRECTIONS[action]
	return Vector2i.ZERO

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)

func _sync_animation() -> void:
	if not is_instance_valid(body):
		return
	var direction_name := _direction_name(facing)
	var is_walking := movement_state == MovementState.GRID_STEPPING
	var requested_animation := StringName(("walk_" if is_walking else "idle_") + direction_name)
	body.flip_h = facing == Vector2i.LEFT
	if is_walking:
		# Advance two frame intervals per grid step: 0001 -> 0002 -> 0003,
		# then 0003 -> 0004 -> 0001 while continuous movement is held.
		body.speed_scale = 0.5 / step_duration
		if body.animation != requested_animation or not body.is_playing():
			body.play(requested_animation)
	elif body.animation != requested_animation or body.is_playing():
		body.play(requested_animation)
		body.pause()
		body.frame = 0

func _direction_name(direction: Vector2i) -> String:
	match direction:
		Vector2i.DOWN: return "down"
		Vector2i.LEFT: return "left"
		Vector2i.RIGHT: return "right"
		_: return "up"
