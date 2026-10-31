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


func collect_ability_threats(model: ChessBoardModel, king: KingPiece, occupancy: Dictionary, horizon: int = 0) -> Array[DupreAbilityEffect]:
	var result: Array[DupreAbilityEffect] = []
	if not king is ArakneKing:
		return result
	var ready_in := active_ability_ready_in_turn_entries(model, king)
	if ready_in > horizon:
		return result
	for coordinate in occupancy:
		var target = occupancy[coordinate]
		if not target is ModelPiece or target.color == king.color:
			continue
		var delta: Vector2i = coordinate - king.coordinate
		if delta == Vector2i.ZERO or absi(delta.x) > 1 or absi(delta.y) > 1:
			continue
		var effect := AbilityEffect.new()
		effect.source_piece_id = king.piece_id
		effect.source_color = king.color
		effect.ability_id = ArakneKing.ACTIVE_ABILITY_ID
		effect.target_piece_id = target.piece_id
		effect.target_coordinate = coordinate
		effect.ready_in_turn_entries = ready_in
		effect.kind = AbilityEffect.Kind.DAMAGE
		effect.damage = ArakneKing.SPIKE_BURST_DAMAGE
		effect.lethal = effect.damage >= target.current_hp
		result.append(effect)
	return result


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is ArakneKing:
		return []
	return collect_ability_threats(model, action.piece, occupancy, 0).filter(func(effect): return effect.target_coordinate == action.target)
