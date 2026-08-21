extends Resource
class_name ChessLastMoveState

@export var is_present := false
@export var from: Vector2i = Vector2i.ZERO
@export var to: Vector2i = Vector2i.ZERO
@export var piece_type_id: StringName = &""
@export var piece_color: String = ""

func copy() -> ChessLastMoveState:
	var result := ChessLastMoveState.new()
	result.is_present = is_present
	result.from = from
	result.to = to
	result.piece_type_id = piece_type_id
	result.piece_color = piece_color
	return result
