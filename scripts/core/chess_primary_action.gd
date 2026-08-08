extends RefCounted
class_name ChessPrimaryAction

## A legal primary command candidate exposed by ChessBoardModel.

enum Kind {
	MOVE,
	ACTIVE_ABILITY,
}

var kind: Kind
var piece: ModelPiece
var target: Vector2i


func _init(p_kind: Kind, p_piece: ModelPiece, p_target: Vector2i) -> void:
	kind = p_kind
	piece = p_piece
	target = p_target
