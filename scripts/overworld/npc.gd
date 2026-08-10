extends StaticBody2D
class_name OverworldNpc

const CELL_SIZE := 16

@export var encounter_id: String = "forest_challenger"
var grid_cell: Vector2i
var facing := Vector2i.DOWN

func _ready() -> void:
	grid_cell = Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	position = cell_center(grid_cell)

func configure_at_cell(cell: Vector2i) -> void:
	grid_cell = cell
	position = cell_center(grid_cell)

func face_toward(cell: Vector2i) -> void:
	var difference := cell - grid_cell
	if abs(difference.x) > abs(difference.y):
		facing = Vector2i(sign(difference.x), 0)
	else:
		facing = Vector2i(0, sign(difference.y))

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)
