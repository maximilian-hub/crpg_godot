extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name MinotaurKingAiLayer

const EMPTY_WALL_STUN_PENALTY := 6.0


func supports(king_type: StringName) -> bool:
	return king_type == &"minotaur_king"


func active_ability_is_lethal(action: ChessPrimaryAction, target: ModelPiece) -> bool:
	return (
		action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY
		and action.piece is MinotaurKing
		and action.target == target.coordinate
		and target.color != action.piece.color
		and target.current_hp <= 2
	)


func collect_ability_threats(model: ChessBoardModel, king: KingPiece, occupancy: Dictionary, horizon: int = 0) -> Array[DupreAbilityEffect]:
	var result: Array[DupreAbilityEffect] = []
	if not king is MinotaurKing:
		return result
	var ready_in := active_ability_ready_in_turn_entries(model, king)
	if ready_in > horizon:
		return result
	for target_coordinate in _charge_targets(model, king.coordinate, occupancy):
		var target = occupancy.get(target_coordinate)
		if not target is ModelPiece or target.color == king.color:
			continue
		var effect := _charge_effect(king, target, target_coordinate)
		effect.ready_in_turn_entries = ready_in
		result.append(effect)
	return result


func has_ability_threat_effects() -> bool:
	return true


func describe_ability_action(_model: ChessBoardModel, action: ChessPrimaryAction, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is MinotaurKing:
		return []
	var target = occupancy.get(action.target)
	if not target is ModelPiece:
		var wall_effect := AbilityEffect.new()
		wall_effect.source_piece_id = action.piece.piece_id
		wall_effect.source_color = action.piece.color
		wall_effect.ability_id = MinotaurKing.ACTIVE_ABILITY_ID
		wall_effect.target_coordinate = action.target
		wall_effect.kind = AbilityEffect.Kind.STUN
		wall_effect.metadata = {"self_stun": true}
		return [wall_effect]
	return [_charge_effect(action.piece, target, action.target)]


func describe_action_reactions(_model: ChessBoardModel, action: ChessPrimaryAction, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return []
	var target = occupancy.get(action.target)
	if not target is MinotaurKing or target.color == action.piece.color or action.piece.attack_power >= target.current_hp:
		return []
	var effect := AbilityEffect.new()
	effect.source_piece_id = target.piece_id
	effect.source_color = target.color
	effect.ability_id = &"retaliating_rage"
	effect.target_piece_id = action.piece.piece_id
	effect.target_coordinate = action.target
	effect.trigger = AbilityEffect.Trigger.REACTION
	effect.kind = AbilityEffect.Kind.DAMAGE
	effect.damage = 1
	effect.certainty = AbilityEffect.Certainty.SIMULATION_REQUIRED
	effect.metadata = {"area": "adjacent_after_damage"}
	return [effect]


func has_action_reaction_effects() -> bool:
	return true


func _charge_effect(king: ModelPiece, target: ModelPiece, coordinate: Vector2i) -> DupreAbilityEffect:
	var effect := AbilityEffect.new()
	effect.source_piece_id = king.piece_id
	effect.source_color = king.color
	effect.ability_id = MinotaurKing.ACTIVE_ABILITY_ID
	effect.target_piece_id = target.piece_id
	effect.target_coordinate = coordinate
	effect.kind = AbilityEffect.Kind.DAMAGE
	effect.damage = 2
	effect.lethal = target.current_hp <= 2
	effect.metadata = {"displaces_source": true}
	return effect


func _charge_targets(model: ChessBoardModel, origin: Vector2i, occupancy: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var coordinate: Vector2i = origin + direction
		var empty_count := 0
		while model.is_in_bounds(coordinate.x, coordinate.y) and not occupancy.has(coordinate):
			empty_count += 1
			coordinate += direction
		if empty_count >= 2:
			result.append(coordinate if model.is_in_bounds(coordinate.x, coordinate.y) else coordinate - direction)
	return result


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is MinotaurKing:
		return 0.0
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null:
		return -EMPTY_WALL_STUN_PENALTY
	# The generic CPU score assumes targeting means capturing. Correct that for
	# durable Charge targets, which take two damage but retain their square.
	if target.current_hp > 2:
		return -_piece_value(target) + minf(2.0, float(target.current_hp)) / float(target.current_hp) * _piece_value(target)
	return 2.0 if target.is_king else 0.5


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is MinotaurKing:
		return false
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	return target != null and target.color != action.piece.color and (target.is_king or target.current_hp <= 2 or _piece_value(target) >= 3.0)


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var result := 0.0
	for color in [perspective, model.get_other_color(perspective)]:
		var king: ModelPiece = model.get_king(color)
		if not king is MinotaurKing or not (king as MinotaurKing).is_active_ability_ready():
			continue
		var pressure := 0.0
		for target_coordinate in (king as MinotaurKing).get_active_ability_targets():
			var target: ModelPiece = model.board[target_coordinate.x][target_coordinate.y]
			if target != null and target.color != color:
				pressure = maxf(pressure, 5.0 if target.is_king else minf(_piece_value(target), 3.0))
		result += pressure if color == perspective else -pressure
	return result


func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
