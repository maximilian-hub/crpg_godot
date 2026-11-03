extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name WraithKingAiLayer

const WraithPolicy := preload("res://scripts/ai/wraith_ai_policy.gd")


func supports(king_type: StringName) -> bool:
	return king_type == &"wraith_king"


func should_describe_for_quiescence(_model: ChessBoardModel, _action: ChessPrimaryAction, _tactical_map: DupreTacticalMap) -> bool:
	return false


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is WraithKing:
		return 0.0
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null: return -1000.0
	var value := WraithPolicy.damage_pressure(target.get_position_type_id(), target.current_hp, target.is_king, WraithPolicy.travel_rounds(action.piece.coordinate, target.coordinate))
	var replacement := model.get_wraith_replacement_candidate(action.piece.piece_id)
	if replacement != null:
		value -= _entity_value(model, replacement)
	return value if action.piece.color == perspective else -value


func action_is_forcing(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String) -> bool:
	return false


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, _occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is WraithKing:
		return []
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null: return []
	var effect := AbilityEffect.new()
	effect.source_piece_id = action.piece.piece_id
	effect.source_color = action.piece.color
	effect.ability_id = WraithKing.ACTIVE_ABILITY_ID
	effect.target_piece_id = target.piece_id
	effect.target_coordinate = target.coordinate
	effect.trigger = AbilityEffect.Trigger.SCHEDULED
	effect.kind = AbilityEffect.Kind.DAMAGE
	effect.damage = WraithKing.SUMMON_WRAITH_DAMAGE
	effect.lethal = target.current_hp <= effect.damage
	effect.certainty = AbilityEffect.Certainty.CONDITIONAL
	effect.ready_in_turn_entries = WraithPolicy.travel_rounds(action.piece.coordinate, target.coordinate)
	var already_targeted := model.get_wraith_entities_from_source(action.piece.piece_id).any(
		func(entity: ChessAutonomousEntityState): return entity.target_piece_id == target.piece_id
	)
	effect.metadata = {
		"autonomous_entity": &"wraith",
		"tracks_piece": true,
		"high_impact": target.is_king,
		"candidate_group": &"wraith_summon",
		"strategic_priority": 2 if target.is_king and not already_targeted else 0,
		"strategic_reason": &"wraith_king_pressure" if target.is_king and not already_targeted else &"",
	}
	return [effect]


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var score := 0.0
	for entity in model.autonomous_entities:
		if entity.type_id != &"wraith": continue
		var target := model.find_piece_by_id(entity.target_piece_id)
		if target == null: continue
		var pressure := _entity_value(model, entity)
		score += pressure if entity.owner_color == perspective else -pressure
	return score


func reaction_target_score(model: ChessBoardModel, calling_piece: ModelPiece, action_type: String, _event_data, target: Vector2i, perspective: String, tactical_map = null) -> float:
	if not calling_piece is WraithKing or action_type != "lingering_malice": return -INF
	if target == calling_piece.coordinate: return 0.0
	var base_map: DupreTacticalMap = tactical_map if tactical_map != null else DupreTacticalMap.from_model(model)
	var occupant = base_map.occupancy.get(target)
	var score := 0.0
	if occupant is ModelPiece and occupant.color != calling_piece.color:
		var value := WraithPolicy.material_value(occupant.get_position_type_id(), occupant.is_king)
		score += 40.0 if occupant.is_king else (value * 10.0 if occupant.current_hp <= calling_piece.attack_power else value * 2.0)
		if occupant.current_hp > calling_piece.attack_power: return score
	var projected_occupancy := base_map.occupancy.duplicate()
	projected_occupancy.erase(calling_piece.coordinate)
	projected_occupancy.erase(target)
	projected_occupancy[target] = calling_piece
	var projected := base_map.project(projected_occupancy)
	var before := base_map.king_attackers(calling_piece.color).size()
	var after := projected.king_attackers(calling_piece.color).size()
	score += float(before - after) * 25.0
	if after > before: score -= float(after - before) * 35.0
	var center_distance := absf(float(target.x) - 3.5) + absf(float(target.y) - 3.5)
	score += (7.0 - center_distance) * 0.1
	return score if calling_piece.color == perspective else -score


func _entity_value(model: ChessBoardModel, entity: ChessAutonomousEntityState) -> float:
	var target := model.find_piece_by_id(entity.target_piece_id)
	if target == null: return 0.0
	var next_turn := int(entity.custom_state.get("next_move_turn", model.global_turn_number + WraithKing.WRAITH_MOVE_INTERVAL_ROUNDS))
	return WraithPolicy.entity_pressure(target.get_position_type_id(), target.current_hp, target.is_king, entity.coordinate, target.coordinate, maxi(0, next_turn - model.global_turn_number))
