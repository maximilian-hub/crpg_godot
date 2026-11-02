extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name ArcherKingAiLayer

## Rules-compatible fallback only. Archer variants intentionally receive no
## bespoke strategic weighting until the final variant is selected.
func supports(king_type: StringName) -> bool:
	return king_type in [&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge"]


func support_level() -> SupportLevel:
	return SupportLevel.GENERIC
