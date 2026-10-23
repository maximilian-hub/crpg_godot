extends RefCounted
class_name ChessKingAiLayer

enum SupportLevel { UNSUPPORTED, GENERIC, ENHANCED }


func supports(_king_type: StringName) -> bool:
	return false


func support_level() -> SupportLevel:
	return SupportLevel.ENHANCED


func allows_traditional_opening() -> bool:
	return true


func action_policy_bonus(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	return 0.0


func action_is_forcing(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String) -> bool:
	return false


func active_ability_is_lethal(_action: ChessPrimaryAction, _target: ModelPiece) -> bool:
	return false


func evaluation_bonus(_model: ChessBoardModel, _perspective: String) -> float:
	return 0.0


func reaction_target_score(_model: ChessBoardModel, _calling_piece: ModelPiece, _action_type: String, _event_data, _target: Vector2i, _perspective: String, _tactical_map = null) -> float:
	return -INF
