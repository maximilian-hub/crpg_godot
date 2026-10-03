@tool
extends Node2D
class_name OverworldInspectableInteractionPoint

enum Facing {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

const CELL_SIZE := 16

@export var required_facing: Facing = Facing.UP:
	set(value):
		required_facing = value
		queue_redraw()


func _enter_tree() -> void:
	set_notify_transform(true)


func get_grid_cell() -> Vector2i:
	return Vector2i(floor(global_position.x / CELL_SIZE), floor(global_position.y / CELL_SIZE))


func get_required_facing() -> Vector2i:
	match required_facing:
		Facing.DOWN:
			return Vector2i.DOWN
		Facing.LEFT:
			return Vector2i.LEFT
		Facing.RIGHT:
			return Vector2i.RIGHT
		_:
			return Vector2i.UP


func matches(player_cell: Vector2i, player_facing: Vector2i) -> bool:
	return get_grid_cell() == player_cell and get_required_facing() == player_facing


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var cell_center := Vector2(get_grid_cell() * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)
	var local_center := to_local(cell_center)
	var facing := Vector2(get_required_facing())
	var color := Color(0.25, 0.9, 1.0, 0.9)
	draw_rect(Rect2(local_center - Vector2.ONE * 7.0, Vector2.ONE * 14.0), color, false, 1.0)
	draw_line(local_center - facing * 4.0, local_center + facing * 4.0, color, 2.0)
	var tip := local_center + facing * 4.0
	var side := facing.orthogonal() * 2.5
	draw_line(tip, tip - facing * 3.0 + side, color, 2.0)
	draw_line(tip, tip - facing * 3.0 - side, color, 2.0)
