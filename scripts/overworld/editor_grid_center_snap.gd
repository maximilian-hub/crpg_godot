@tool
extends Node2D
class_name OverworldEditorGridCenterSnap

const CELL_SIZE := 16

var editor_snap_armed := false
var editor_snap_active := false

func _enter_tree() -> void:
	set_notify_transform(true)

func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_arm_editor_snap")

func _notification(what: int) -> void:
	if (
		what != NOTIFICATION_TRANSFORM_CHANGED
		or not Engine.is_editor_hint()
		or not editor_snap_armed
		or editor_snap_active
	):
		return
	var snapped_position := snap_position_to_cell_center(position)
	if position.is_equal_approx(snapped_position):
		return
	editor_snap_active = true
	position = snapped_position
	editor_snap_active = false

func _arm_editor_snap() -> void:
	editor_snap_armed = true

static func snap_position_to_cell_center(source_position: Vector2) -> Vector2:
	var cell := Vector2i(
		floori(source_position.x / CELL_SIZE),
		floori(source_position.y / CELL_SIZE)
	)
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)
