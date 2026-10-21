extends RefCounted
class_name ChessKingAiLayer


func supports(_king_type: StringName) -> bool:
	return false


func active_ability_is_lethal(_action: ChessPrimaryAction, _target: ModelPiece) -> bool:
	return false


func evaluation_bonus(_model: ChessBoardModel, _perspective: String) -> float:
	return 0.0

