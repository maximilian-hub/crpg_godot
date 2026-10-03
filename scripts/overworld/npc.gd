extends StaticBody2D
class_name OverworldNpc

const CELL_SIZE := 16

@export var encounter_profile: ChessEncounterProfile
@export var down_texture: Texture2D
@export var up_texture: Texture2D
@export var right_texture: Texture2D
@export_range(0.0, 10.0, 0.1) var return_facing_delay: float = 2.0

@onready var body: Sprite2D = $Body

var grid_cell: Vector2i
var facing := Vector2i.UP
var original_facing := Vector2i.UP
var return_facing_time_remaining: float = -1.0

func _ready() -> void:
	grid_cell = Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	position = cell_center(grid_cell)
	original_facing = facing
	_sync_visual()

func _physics_process(delta: float) -> void:
	if return_facing_time_remaining < 0.0:
		return
	return_facing_time_remaining -= delta
	if return_facing_time_remaining <= 0.0:
		return_facing_time_remaining = -1.0
		facing = original_facing
		_sync_visual()

func configure_at_cell(cell: Vector2i) -> void:
	grid_cell = cell
	position = cell_center(grid_cell)

func face_toward(cell: Vector2i) -> void:
	var difference := cell - grid_cell
	if difference == Vector2i.ZERO:
		return
	return_facing_time_remaining = -1.0
	if abs(difference.x) > abs(difference.y):
		facing = Vector2i(sign(difference.x), 0)
	else:
		facing = Vector2i(0, sign(difference.y))
	_sync_visual()

func return_to_original_facing_after_delay() -> void:
	if return_facing_delay <= 0.0:
		facing = original_facing
		_sync_visual()
		return
	return_facing_time_remaining = return_facing_delay

func _sync_visual() -> void:
	if not is_instance_valid(body):
		return
	body.flip_h = facing == Vector2i.LEFT
	var requested_texture := right_texture
	match facing:
		Vector2i.DOWN: requested_texture = down_texture
		Vector2i.UP: requested_texture = up_texture
	if requested_texture != null:
		body.texture = requested_texture

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)
