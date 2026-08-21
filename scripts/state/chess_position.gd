extends Resource
class_name ChessPosition

const CURRENT_SCHEMA_VERSION := 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var board_size := Vector2i(8, 8)
@export var board_type: StringName = &"default"
@export var pieces: Array[ChessPieceState] = []
@export_enum("white", "black") var current_turn := "white"
@export var last_move: ChessLastMoveState = ChessLastMoveState.new()
@export var battle_over := false
@export var battle_result := ""
@export var defeated_king_colors: Array[String] = []

func copy() -> ChessPosition:
	var result := ChessPosition.new()
	result.schema_version = schema_version
	result.board_size = board_size
	result.board_type = board_type
	for piece in pieces:
		result.pieces.append(piece.copy())
	result.current_turn = current_turn
	result.last_move = last_move.copy() if last_move != null else ChessLastMoveState.new()
	result.battle_over = battle_over
	result.battle_result = battle_result
	result.defeated_king_colors.assign(defeated_king_colors)
	return result
