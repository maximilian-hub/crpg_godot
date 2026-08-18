extends StaticBody2D
class_name OverworldNpc

const CELL_SIZE := 16

@export var encounter_id: String = "forest_challenger"
@export var down_texture: Texture2D
@export var up_texture: Texture2D
@export var right_texture: Texture2D

@onready var body: Sprite2D = $Body

var grid_cell: Vector2i
var facing := Vector2i.DOWN

func _ready() -> void:
	grid_cell = Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	position = cell_center(grid_cell)
	_sync_visual()

func configure_at_cell(cell: Vector2i) -> void:
	grid_cell = cell
	position = cell_center(grid_cell)

func face_toward(cell: Vector2i) -> void:
	var difference := cell - grid_cell
	if difference == Vector2i.ZERO:
		return
	if abs(difference.x) > abs(difference.y):
		facing = Vector2i(sign(difference.x), 0)
	else:
		facing = Vector2i(0, sign(difference.y))
	_sync_visual()

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
