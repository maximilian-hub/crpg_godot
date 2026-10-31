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


func active_ability_threat(model: ChessBoardModel, king: KingPiece, target: ModelPiece, target_coordinate: Vector2i, _occupancy: Dictionary, horizon: int = 0) -> Dictionary:
	if not king is ArakneKing or target == null or target.color == king.color:
		return {}
	var delta := target_coordinate - king.coordinate
	if delta == Vector2i.ZERO or absi(delta.x) > 1 or absi(delta.y) > 1:
		return {}
	var ready_in := active_ability_ready_in_turn_entries(model, king)
	if ready_in > horizon:
		return {}
	return {
		"ability_id": ArakneKing.ACTIVE_ABILITY_ID,
		"damage": ArakneKing.SPIKE_BURST_DAMAGE,
		"lethal": ArakneKing.SPIKE_BURST_DAMAGE >= target.current_hp,
		"ready_in_turn_entries": ready_in,
	}
