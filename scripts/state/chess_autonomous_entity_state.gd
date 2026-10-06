extends Resource
class_name ChessAutonomousEntityState

@export var entity_id: String = ""
@export var type_id: StringName = &""
@export var coordinate := Vector2i.ZERO
@export var owner_color: String = ""
@export var source_piece_id: String = ""
@export var target_piece_id: String = ""
@export var custom_state: Dictionary = {}

func copy() -> ChessAutonomousEntityState:
	var result := ChessAutonomousEntityState.new()
	result.entity_id = entity_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.target_piece_id = target_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result
