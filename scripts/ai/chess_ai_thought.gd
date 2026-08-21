extends RefCounted
class_name ChessAiThought

var model_revision: int
var color: String
var action_kind: ChessPrimaryAction.Kind
var piece_coordinate: Vector2i
var piece_type_id: StringName
var target: Vector2i
var score: float
