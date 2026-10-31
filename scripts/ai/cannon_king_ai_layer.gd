extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name CannonKingAiLayer

const FRIENDLY_FIRE_MULTIPLIER := 1.5


func supports(king_type: StringName) -> bool:
	return king_type == &"cannon_king"


func should_describe_for_quiescence(_model: ChessBoardModel, _action: ChessPrimaryAction, _tactical_map: DupreTacticalMap) -> bool:
	# Mortars are scheduled pressure, never an immediate leaf-resolution action.
	return false


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is CannonKing:
		return 0.0
	return _footprint_score(model, action.piece, action.target, perspective)


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is CannonKing:
		return false
	for coordinate in model.get_mortar_area(action.target):
		var piece: ModelPiece = model.board[coordinate.x][coordinate.y]
		if piece != null and piece.color != action.piece.color and piece.is_king:
			return true
	return _footprint_score(model, action.piece, action.target, perspective) >= 8.0


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, _occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is CannonKing:
		return []
	var affected_ids: Array[String] = []
	var contains_enemy_king := false
	for coordinate in model.get_mortar_area(action.target):
		var piece: ModelPiece = model.board[coordinate.x][coordinate.y]
		if piece != null:
			affected_ids.append(piece.piece_id)
			contains_enemy_king = contains_enemy_king or (piece.color != action.piece.color and piece.is_king)
	var effect := AbilityEffect.new()
	effect.source_piece_id = action.piece.piece_id
	effect.source_color = action.piece.color
	effect.ability_id = CannonKing.ACTIVE_ABILITY_ID
	effect.target_coordinate = action.target
	effect.trigger = AbilityEffect.Trigger.SCHEDULED
	effect.kind = AbilityEffect.Kind.AREA_HAZARD
	effect.certainty = AbilityEffect.Certainty.CONDITIONAL
	effect.metadata = {
		"area": model.get_mortar_area(action.target),
		"affected_piece_ids": affected_ids,
		"landing_turn": model.global_turn_number + CannonKing.ARC_MORTAR_DELAY_ROUNDS,
		"damage": CannonKing.ARC_MORTAR_DAMAGE,
		"friendly_fire": true,
		"high_impact": contains_enemy_king or _footprint_score(model, action.piece, action.target, action.piece.color) >= 8.0,
	}
	return [effect]


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var result := 0.0
	for entity in model.autonomous_entities:
		if entity.type_id != &"arc_mortar":
			continue
		var remaining := maxi(1, int(entity.custom_state.get("landing_turn", model.global_turn_number + CannonKing.ARC_MORTAR_DELAY_ROUNDS)) - model.global_turn_number)
		var urgency := 0.3 if remaining >= 3 else (0.7 if remaining == 2 else 1.4)
		for coordinate in model.get_mortar_area(entity.coordinate):
			var piece: ModelPiece = model.board[coordinate.x][coordinate.y]
			if piece == null:
				continue
			var exposure := (12.0 if piece.is_king else _piece_value(piece)) * urgency
			if piece.current_hp <= CannonKing.ARC_MORTAR_DAMAGE:
				exposure *= 1.5
			result += -exposure if piece.color == perspective else exposure
	return result


func _footprint_score(model: ChessBoardModel, cannon: ModelPiece, anchor: Vector2i, perspective: String) -> float:
	var score := 0.2
	var perspective_sign := 1.0 if cannon.color == perspective else -1.0
	for coordinate in model.get_mortar_area(anchor):
		var piece: ModelPiece = model.board[coordinate.x][coordinate.y]
		if piece == null:
			continue
		var value := 20.0 if piece.is_king else _piece_value(piece)
		if piece.current_hp <= CannonKing.ARC_MORTAR_DAMAGE:
			value *= 1.25
		if piece.color == cannon.color:
			score -= value * FRIENDLY_FIRE_MULTIPLIER
		else:
			score += value
	return score * perspective_sign


func _piece_value(piece: ModelPiece) -> float:
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
