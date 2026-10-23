extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name ClassicKingAiLayer


func supports(king_type: StringName) -> bool:
	return king_type == &"classic_king"


func support_level() -> SupportLevel:
	return SupportLevel.GENERIC
