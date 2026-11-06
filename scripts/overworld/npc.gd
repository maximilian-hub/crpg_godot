@tool
extends StaticBody2D
class_name OverworldNpc

const CELL_SIZE := 16

@export var encounter_profile: ChessEncounterProfile
@export var down_texture: Texture2D:
	set(value):
		down_texture = value
		_sync_visual()
@export var up_texture: Texture2D:
	set(value):
		up_texture = value
		_sync_visual()
@export var right_texture: Texture2D:
	set(value):
		right_texture = value
		_sync_visual()
@export var left_texture: Texture2D:
	set(value):
		left_texture = value
		_sync_visual()
@export_file("*.dialog", "*.dialogue") var dialogue_path := ""
@export_range(0.0, 10.0, 0.1) var return_facing_delay: float = 2.0

@onready var body: Sprite2D = $Body

var grid_cell: Vector2i
@export var facing := Vector2i.DOWN:
	set(value):
		facing = value
		_sync_visual()
var original_facing := Vector2i.DOWN
var return_facing_time_remaining: float = -1.0
var editor_transform_snap_active := false

func _enter_tree() -> void:
	set_notify_transform(true)

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"overworld_npc")
	grid_cell = Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	if not Engine.is_editor_hint():
		position = snap_position_to_cell_center(position)
	original_facing = facing
	_sync_visual()

func _notification(what: int) -> void:
	if (
		what != NOTIFICATION_TRANSFORM_CHANGED
		or not Engine.is_editor_hint()
		or editor_transform_snap_active
		or not _is_authored_under_y_sorted_world()
	):
		return
	var snapped_position := snap_position_to_cell_center(position)
	if position.is_equal_approx(snapped_position):
		return
	editor_transform_snap_active = true
	position = snapped_position
	editor_transform_snap_active = false

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
	body.flip_h = false
	var requested_texture := right_texture
	match facing:
		Vector2i.DOWN: requested_texture = down_texture
		Vector2i.UP: requested_texture = up_texture
		Vector2i.LEFT:
			if left_texture != null:
				requested_texture = left_texture
			else:
				requested_texture = right_texture
				body.flip_h = true
	if requested_texture != null:
		body.texture = requested_texture

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)

static func snap_position_to_cell_center(source_position: Vector2) -> Vector2:
	var cell := Vector2i(
		floori(source_position.x / CELL_SIZE),
		floori(source_position.y / CELL_SIZE)
	)
	return Vector2(cell * CELL_SIZE) + Vector2.ONE * (CELL_SIZE * 0.5)

func _is_authored_under_y_sorted_world() -> bool:
	return get_parent() != null and get_parent().name == &"YSortedWorld"
