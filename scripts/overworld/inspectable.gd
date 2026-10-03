@tool
extends Node2D
class_name OverworldInspectable

const CELL_SIZE := 16
const INTERACTION_POINT_SCRIPT := preload("res://scripts/overworld/inspectable_interaction_point.gd")

@export_file("*.dialog") var dialogue_path: String = ""


func _enter_tree() -> void:
	add_to_group(&"overworld_inspectable")
	set_notify_transform(true)


func get_grid_cell() -> Vector2i:
	return Vector2i(floor(global_position.x / CELL_SIZE), floor(global_position.y / CELL_SIZE))


func can_interact(player_cell: Vector2i, player_facing: Vector2i) -> bool:
	for child in get_children():
		if child.get_script() == INTERACTION_POINT_SCRIPT and child.matches(player_cell, player_facing):
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var cell_center := Vector2(get_grid_cell() * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)
	var local_center := to_local(cell_center)
	draw_rect(Rect2(local_center - Vector2.ONE * 8.0, Vector2.ONE * 16.0), Color(0.95, 0.75, 0.2, 0.85), false, 1.0)
	draw_line(local_center + Vector2(-3, 0), local_center + Vector2(3, 0), Color(0.95, 0.75, 0.2, 0.85), 1.0)
	draw_line(local_center + Vector2(0, -3), local_center + Vector2(0, 3), Color(0.95, 0.75, 0.2, 0.85), 1.0)
