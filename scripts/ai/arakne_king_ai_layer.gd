extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name ArakneKingAiLayer


func supports(king_type: StringName) -> bool:
	return king_type == &"arakne_king"


func active_ability_is_lethal(action: ChessPrimaryAction, target: ModelPiece) -> bool:
	return (
		action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY
		and action.piece is ArakneKing
		and action.target == target.coordinate
		and ArakneKing.SPIKE_BURST_DAMAGE >= target.current_hp
	)
