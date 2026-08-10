@tool
extends TileMapLayer
class_name OverworldCollisionGrid

const GRID_SIZE := Vector2i(10, 10)
const CELL_SIZE := 16

@export var show_collision_overlay_in_game: bool = false

func _ready() -> void:
	collision_enabled = true
	# TileMapLayer deactivates its physics quadrants when hidden. Keep the layer
	# active and make only its debug artwork transparent at runtime.
	visible = true
	modulate.a = 1.0 if Engine.is_editor_hint() or show_collision_overlay_in_game else 0.0

func is_cell_blocked(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_SIZE.x or cell.y >= GRID_SIZE.y:
		return true
	return get_cell_source_id(cell) != -1
