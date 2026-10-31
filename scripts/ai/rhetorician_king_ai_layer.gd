extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name RhetoricianKingAiLayer

const LUNACY_VALUE := 2.0
const SOCRATIC_TURN_VALUE := 8.0


func supports(king_type: StringName) -> bool:
	return king_type == &"rhetorician_king"


func collect_ability_threats(model: ChessBoardModel, king: KingPiece, occupancy: Dictionary, horizon: int = 0) -> Array[DupreAbilityEffect]:
	var result: Array[DupreAbilityEffect] = []
	if not king is RhetoricianKing:
		return result
	var ready_in := active_ability_ready_in_turn_entries(model, king)
	if ready_in > horizon:
		return result
	for coordinate in occupancy:
		var compelled = occupancy[coordinate]
		if not compelled is ModelPiece or compelled.color == king.color:
			continue
		var distance := maxi(absi(coordinate.x - king.coordinate.x), absi(coordinate.y - king.coordinate.y))
		if distance != 2:
			continue
		var effect := _compel_effect(model, king, compelled, coordinate, occupancy)
		effect.ready_in_turn_entries = ready_in
		result.append(effect)
	return result


func has_ability_threat_effects() -> bool:
	return true


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is RhetoricianKing:
		return []
	var compelled = occupancy.get(action.target)
	if not compelled is ModelPiece:
		return []
	return [_compel_effect(model, action.piece, compelled, action.target, occupancy)]


func _compel_effect(model: ChessBoardModel, king: ModelPiece, compelled: ModelPiece, coordinate: Vector2i, occupancy: Dictionary) -> DupreAbilityEffect:
	var effect := AbilityEffect.new()
	effect.source_piece_id = king.piece_id
	effect.source_color = king.color
	effect.ability_id = RhetoricianKing.ACTIVE_ABILITY_ID
	effect.target_piece_id = compelled.piece_id
	effect.target_coordinate = coordinate
	effect.kind = AbilityEffect.Kind.FORCED_MOVEMENT
	var delta: Vector2i = king.coordinate - coordinate
	effect.destination = coordinate + Vector2i(signi(delta.x), signi(delta.y))
	if not model.is_in_bounds(effect.destination.x, effect.destination.y) or effect.destination == king.coordinate:
		effect.certainty = AbilityEffect.Certainty.CONDITIONAL
		effect.metadata = {"invalid_destination": true}
		return effect
	var occupant = occupancy.get(effect.destination)
	if occupant is ModelPiece:
		effect.metadata = {"captured_piece_id": occupant.piece_id, "captured_color": occupant.color}
		effect.material_delta = _piece_value(occupant) * (1.0 if occupant.color != king.color else -1.0)
		effect.lethal = occupant.is_king
	else:
		effect.metadata = {"vacates_target": true}
	var projected_occupancy := occupancy.duplicate()
	projected_occupancy.erase(coordinate)
	projected_occupancy.erase(effect.destination)
	projected_occupancy[effect.destination] = compelled
	var base_map := DupreTacticalMap.from_model(model).project(occupancy)
	var projected_map := base_map.project(projected_occupancy)
	var exposed_king: ModelPiece
	for candidate in occupancy.values():
		if candidate is ModelPiece and candidate.is_king and candidate.color == compelled.color:
			exposed_king = candidate
			break
	if exposed_king != null:
		var before_attackers := base_map.attack_count(exposed_king.coordinate, king.color)
		var projected_king_coordinate = effect.destination if exposed_king == compelled else exposed_king.coordinate
		var after_attackers := projected_map.attack_count(projected_king_coordinate, king.color)
		if after_attackers > before_attackers:
			effect.metadata["king_exposure"] = true
			effect.metadata["exposed_king_id"] = exposed_king.piece_id
			effect.metadata["king_attackers_added"] = after_attackers - before_attackers
	return effect


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is RhetoricianKing:
		return 0.0
	var compelled: ModelPiece = model.board[action.target.x][action.target.y]
	if compelled == null:
		return 0.0
	# Generic targeting scores the compelled piece as captured. It survives; the
	# occupant of its forced destination is the piece actually captured.
	var result := -_piece_value(compelled)
	var delta := action.piece.coordinate - compelled.coordinate
	var destination := compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))
	if model.is_in_bounds(destination.x, destination.y):
		var occupant: ModelPiece = model.board[destination.x][destination.y]
		if occupant != null:
			result += _piece_value(occupant) if occupant.color != action.piece.color else -_piece_value(occupant)
	return result


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is RhetoricianKing:
		return false
	var compelled: ModelPiece = model.board[action.target.x][action.target.y]
	if compelled == null:
		return false
	var delta := action.piece.coordinate - compelled.coordinate
	var destination := compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))
	if not model.is_in_bounds(destination.x, destination.y):
		return false
	var occupant: ModelPiece = model.board[destination.x][destination.y]
	return occupant != null or compelled.is_king or _piece_value(compelled) >= 5.0


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var enemy := model.get_other_color(perspective)
	return (
		float(model.lunacy_by_color.get(enemy, 0) - model.lunacy_by_color.get(perspective, 0)) * LUNACY_VALUE
		+ float(model.socratic_turns_by_color.get(enemy, 0) - model.socratic_turns_by_color.get(perspective, 0)) * SOCRATIC_TURN_VALUE
	)


func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
