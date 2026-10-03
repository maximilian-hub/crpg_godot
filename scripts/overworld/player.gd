extends CharacterBody2D
class_name OverworldPlayer

signal step_finished(cell: Vector2i)

enum MovementState { GRID_IDLE, TURNING, GRID_STEPPING, INPUT_LOCKED }

const CELL_SIZE := 16
const DIRECTIONS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

@onready var body: AnimatedSprite2D = $Body
@onready var bump_sound: AudioStreamPlayer = $BumpSound

@export_range(0.05, 1.0, 0.01) var step_duration: float = 0.14
## Actual pixels travelled before advancing to the next of the four gait phases.
@export_range(1.0, 32.0, 0.5) var walking_distance_per_gait_phase: float = 8.0
## Standstill direction changes anticipate movement for this long.
@export_range(0.01, 0.3, 0.01) var turn_in_place_duration: float = 0.08
## Relative gait speed while held against an obstruction.
@export_range(0.05, 1.0, 0.05) var blocked_walk_speed_scale: float = 0.5
## Maximum bump cadence while held against an obstruction.
@export_range(30.0, 600.0, 1.0) var bump_repeat_bpm: float = 200.0
@export_range(-80.0, 24.0, 0.5) var bump_volume_db: float = -6.0

var movement_state := MovementState.INPUT_LOCKED
var grid_cell := Vector2i.ZERO
var facing := Vector2i.UP
var target_cell := Vector2i.ZERO
var step_origin_cell := Vector2i.ZERO
var step_origin_gait_phase: int = 0
var step_origin_gait_distance: float = 0.0
var input_lock_pending: bool = false
var gait_phase: int = 0
var walking_distance_accumulator: float = 0.0
var turn_time_remaining: float = 0.0
var turn_direction := Vector2i.ZERO
var collision_grid: OverworldCollisionGrid
var blocking_npc: OverworldNpc
var blocked_walk_active: bool = false
var blocked_walk_direction := Vector2i.ZERO
var blocked_walk_time: float = 0.0
var bump_cooldown_remaining: float = 0.0

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
	step_origin_gait_phase = 0
	step_origin_gait_distance = 0.0
	facing = start_facing
	position = cell_center(start_cell)
	velocity = Vector2.ZERO
	input_lock_pending = false
	gait_phase = 0
	walking_distance_accumulator = 0.0
	turn_time_remaining = 0.0
	turn_direction = Vector2i.ZERO
	bump_cooldown_remaining = 0.0
	_reset_blocked_walk(false)
	movement_state = MovementState.GRID_IDLE
	_sync_animation()

func set_input_enabled(enabled: bool) -> void:
	_reset_blocked_walk()
	if enabled:
		input_lock_pending = false
		if movement_state == MovementState.INPUT_LOCKED:
			movement_state = MovementState.GRID_IDLE
	else:
		turn_direction = Vector2i.ZERO
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
			if movement_state == MovementState.GRID_STEPPING:
				# Keep facing locked to the active step. Landing samples held input.
				pass
			elif movement_state == MovementState.TURNING:
				_begin_turn(direction)
			elif direction != facing:
				_begin_turn(direction)
			else:
				_try_begin_step(direction)
			get_viewport().set_input_as_handled()
			return

func _physics_process(delta: float) -> void:
	bump_cooldown_remaining = maxf(0.0, bump_cooldown_remaining - delta)
	if movement_state == MovementState.GRID_IDLE and blocked_walk_active:
		_process_blocked_walk(delta)
		if movement_state != MovementState.GRID_IDLE or blocked_walk_active:
			velocity = Vector2.ZERO
			return
	if movement_state == MovementState.TURNING:
		velocity = Vector2.ZERO
		turn_time_remaining -= delta
		if turn_time_remaining <= 0.0:
			_finish_turn()
		return
	if movement_state != MovementState.GRID_STEPPING:
		velocity = Vector2.ZERO
		return

	var target_position := cell_center(target_cell)
	var remaining := target_position - position
	var max_travel := (float(CELL_SIZE) / step_duration) * delta
	if remaining.length() <= max_travel:
		var previous_position := position
		var collision := move_and_collide(remaining)
		if collision != null:
			_cancel_step_after_contact()
			return
		position = target_position
		_advance_gait_from_displacement(position.distance_to(previous_position))
		grid_cell = target_cell
		velocity = Vector2.ZERO
		_settle_gait_to_neutral()
		movement_state = MovementState.GRID_IDLE
		_sync_animation()
		step_finished.emit(grid_cell)
		if input_lock_pending:
			input_lock_pending = false
			movement_state = MovementState.INPUT_LOCKED
		else:
			_begin_held_step()
		_sync_animation()
		return

	velocity = remaining.normalized() * (float(CELL_SIZE) / step_duration)
	var previous_position := position
	var collision := move_and_collide(velocity * delta)
	_advance_gait_from_displacement(position.distance_to(previous_position))
	if collision != null:
		_cancel_step_after_contact()

func _try_begin_step(direction: Vector2i) -> bool:
	if movement_state != MovementState.GRID_IDLE:
		return false
	facing = direction
	var requested_cell := grid_cell + direction
	if not _is_traversable(requested_cell):
		_begin_blocked_walk(direction)
		_sync_animation()
		return false
	_reset_blocked_walk(false)
	step_origin_cell = grid_cell
	step_origin_gait_phase = gait_phase
	step_origin_gait_distance = walking_distance_accumulator
	target_cell = requested_cell
	movement_state = MovementState.GRID_STEPPING
	_sync_animation()
	return true

func _begin_turn(direction: Vector2i) -> void:
	_reset_blocked_walk()
	facing = direction
	turn_direction = direction
	turn_time_remaining = turn_in_place_duration
	movement_state = MovementState.TURNING
	_sync_animation()

func _finish_turn() -> void:
	var completed_direction := turn_direction
	turn_direction = Vector2i.ZERO
	turn_time_remaining = 0.0
	movement_state = MovementState.GRID_IDLE
	_sync_animation()
	if completed_direction != Vector2i.ZERO and _is_direction_held(completed_direction):
		_try_begin_step(completed_direction)

func _is_direction_held(direction: Vector2i) -> bool:
	for action in DIRECTIONS:
		if DIRECTIONS[action] == direction:
			return Input.is_action_pressed(action)
	return false

func _advance_gait_from_displacement(distance: float) -> void:
	if distance <= 0.0:
		return
	walking_distance_accumulator += distance
	var phase_distance := maxf(walking_distance_per_gait_phase, 0.001)
	while walking_distance_accumulator >= phase_distance:
		walking_distance_accumulator -= phase_distance
		gait_phase = (gait_phase + 1) % 4
	_sync_animation()

func _settle_gait_to_neutral() -> void:
	if gait_phase % 2 == 1:
		gait_phase = (gait_phase + 1) % 4

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
	gait_phase = step_origin_gait_phase
	walking_distance_accumulator = step_origin_gait_distance
	velocity = Vector2.ZERO
	movement_state = MovementState.INPUT_LOCKED if input_lock_pending else MovementState.GRID_IDLE
	input_lock_pending = false
	_settle_gait_to_neutral()
	if movement_state == MovementState.GRID_IDLE:
		_begin_blocked_walk(facing)
	_sync_animation()

func _begin_blocked_walk(direction: Vector2i) -> void:
	if blocked_walk_active and blocked_walk_direction == direction:
		return
	blocked_walk_active = true
	blocked_walk_direction = direction
	blocked_walk_time = 0.0
	_play_bump_sound()

func _process_blocked_walk(delta: float) -> void:
	if not _is_direction_held(blocked_walk_direction):
		_reset_blocked_walk()
		return
	if _is_traversable(grid_cell + blocked_walk_direction):
		var released_direction := blocked_walk_direction
		_reset_blocked_walk(false)
		_try_begin_step(released_direction)
		return

	blocked_walk_time += delta
	var movement_speed := float(CELL_SIZE) / maxf(step_duration, 0.001)
	var normal_phase_duration := maxf(walking_distance_per_gait_phase, 0.001) / movement_speed
	var blocked_phase_duration := normal_phase_duration / maxf(blocked_walk_speed_scale, 0.001)
	while blocked_walk_time >= blocked_phase_duration:
		blocked_walk_time -= blocked_phase_duration
		gait_phase = (gait_phase + 1) % 4
		_sync_animation()
	if bump_cooldown_remaining <= 0.0:
		_play_bump_sound()

func _reset_blocked_walk(settle_gait := true) -> void:
	blocked_walk_active = false
	blocked_walk_direction = Vector2i.ZERO
	blocked_walk_time = 0.0
	if settle_gait:
		_settle_gait_to_neutral()
	_sync_animation()

func _play_bump_sound() -> void:
	if bump_cooldown_remaining > 0.0:
		return
	if not is_instance_valid(bump_sound) or bump_sound.stream == null:
		return
	bump_sound.volume_db = bump_volume_db
	bump_sound.play()
	bump_cooldown_remaining = 60.0 / maxf(bump_repeat_bpm, 0.001)

func _begin_held_step() -> void:
	var next_direction := _get_held_direction()
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
	var requested_animation := StringName("walk_" + direction_name)
	body.flip_h = facing == Vector2i.LEFT
	body.animation = requested_animation
	body.pause()
	var displayed_phase := gait_phase
	if movement_state == MovementState.TURNING:
		# Briefly show the upcoming stride, then return to the preserved neutral.
		displayed_phase = 1 if gait_phase == 0 else 3
	body.set_frame_and_progress(displayed_phase, 0.0)

func _direction_name(direction: Vector2i) -> String:
	match direction:
		Vector2i.DOWN: return "down"
		Vector2i.LEFT: return "left"
		Vector2i.RIGHT: return "right"
		_: return "up"
