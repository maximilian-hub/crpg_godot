extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name NecromancerKingAiLayer

const BonePawnPiece = preload("res://scripts/pieces/bone_pawn.gd")
const DOOMED_SCORE := -100000.0
const REMOVABLE_SUMMON_PENALTY := 6.0


func supports(king_type: StringName) -> bool:
	return king_type == &"necromancer_king"


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is NecromancerKing:
		return []
	return _describe_summon(model, action.piece, action.target, occupancy)


func _describe_summon(model: ChessBoardModel, necromancer: ModelPiece, target: Vector2i, occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	var result: Array[DupreAbilityEffect] = []
	if occupancy.has(target):
		return result
	var summon := AbilityEffect.new()
	summon.source_piece_id = necromancer.piece_id
	summon.source_color = necromancer.color
	summon.ability_id = &"summon_bone_pawn"
	summon.target_coordinate = target
	summon.kind = AbilityEffect.Kind.SUMMON
	summon.metadata = {"piece_type": "bone_pawn"}
	result.append(summon)
	var pawn := BonePawnPiece.new(necromancer.color, target)
	pawn.piece_id = "dupre_effect_bone_%s_%s" % [target.x, target.y]
	var projected_occupancy := occupancy.duplicate()
	projected_occupancy[target] = pawn
	var board_size := Vector2i(model.board.size(), model.board[0].size())
	var attack_position := ChessAttackPosition.from_occupancy(board_size, projected_occupancy)
	for coordinate in projected_occupancy:
		var piece = projected_occupancy[coordinate]
		if not piece is ModelPiece or piece == pawn:
			continue
		if piece.color != necromancer.color and pawn.can_directly_attack_square(target, coordinate, attack_position):
			var pressure := AbilityEffect.new()
			pressure.source_piece_id = pawn.piece_id
			pressure.source_color = pawn.color
			pressure.ability_id = &"summon_bone_pawn"
			pressure.target_piece_id = piece.piece_id
			pressure.target_coordinate = coordinate
			pressure.kind = AbilityEffect.Kind.DAMAGE
			pressure.damage = pawn.attack_power
			pressure.lethal = pressure.damage >= piece.current_hp
			pressure.certainty = AbilityEffect.Certainty.CONDITIONAL
			pressure.metadata = {"summoned_attack": true}
			result.append(pressure)
	# Build both views from the caller's state; speculative occupancies must not
	# silently fall back to the live board while describing an action.
	var before := DupreTacticalMap.from_model(model).project(occupancy)
	var after := before.project(projected_occupancy)
	if after.king_attackers(necromancer.color).size() < before.king_attackers(necromancer.color).size():
		var block := AbilityEffect.new()
		block.source_piece_id = necromancer.piece_id
		block.source_color = necromancer.color
		block.ability_id = &"summon_bone_pawn"
		block.target_piece_id = necromancer.piece_id
		block.target_coordinate = target
		block.kind = AbilityEffect.Kind.BLOCK
		block.metadata = {"king_attackers_removed": before.king_attackers(necromancer.color).size() - after.king_attackers(necromancer.color).size()}
		result.append(block)
	return result


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String, tactical_map = null) -> float:
	var result := 0.0
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.piece is NecromancerKing:
		result += placement_score(model, action.piece, action.target, perspective, tactical_map)
	return result


func exchange_policy_adjustment(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String, _exchange: Dictionary, tactical_map = null) -> float:
	# Capturing a major or minor against a Necromancer is not the whole material
	# gain: Raise Dead immediately restores a Bone Pawn. Price that authoritative
	# consequence into the cheap policy without duplicating its execution rules.
	var result := 0.0
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		var target: ModelPiece = model.board[action.target.x][action.target.y]
		if target != null and target.color != action.piece.color and target.current_hp <= action.piece.attack_power and _is_raise_dead_piece(target):
			var enemy_king: ModelPiece = model.get_king(target.color)
			if enemy_king is NecromancerKing:
				var best_raise := DOOMED_SCORE
				for square in _raise_dead_targets(model, target.coordinate):
					best_raise = maxf(best_raise, placement_score(model, enemy_king, square, perspective, tactical_map))
				if best_raise > DOOMED_SCORE:
					result += best_raise
	return result


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is NecromancerKing:
		return false
	return _placement_is_forcing(model, action.piece, action.target, perspective)


func reaction_target_score(model: ChessBoardModel, calling_piece: ModelPiece, action_type: String, _event_data, target: Vector2i, perspective: String, tactical_map = null) -> float:
	if not calling_piece is NecromancerKing or action_type != "raise_dead":
		return -INF
	return placement_score(model, calling_piece, target, perspective, tactical_map)


func placement_score(model: ChessBoardModel, necromancer: ModelPiece, target: Vector2i, perspective: String, tactical_map = null) -> float:
	if target.x == model.get_back_rank(model.get_other_color(necromancer.color)):
		return DOOMED_SCORE
	var base_map: DupreTacticalMap = tactical_map if tactical_map != null else DupreTacticalMap.from_model(model)
	var occupancy: Dictionary = base_map.occupancy.duplicate()
	if occupancy.has(target):
		return DOOMED_SCORE
	var pawn := BonePawnPiece.new(necromancer.color, target)
	pawn.piece_id = "dupre_projected_bone_%s_%s" % [target.x, target.y]
	occupancy[target] = pawn
	var projected: DupreTacticalMap = base_map.project(occupancy)
	var attack_position := ChessAttackPosition.from_occupancy(projected.board_size, projected.occupancy)
	var own_sign := 1.0 if necromancer.color == perspective else -1.0
	var score := 1.0
	var before_attackers: int = base_map.king_attackers(necromancer.color).size()
	var after_attackers: int = projected.king_attackers(necromancer.color).size()
	score += float(before_attackers - after_attackers) * 25.0
	for coordinate in occupancy:
		var piece = occupancy[coordinate]
		if not piece is ModelPiece or piece == pawn:
			continue
		if piece.color != necromancer.color and pawn.can_directly_attack_square(target, coordinate, attack_position):
			score += 5.0 if piece.is_king else _piece_value(piece) * 0.6
		elif piece.color == necromancer.color and not piece.is_king and _piece_value(piece) >= 5.0:
			# A new defender does not save a major which can still be captured; it
			# merely promises a recapture after the expensive piece is gone. Reward
			# only placements which actually remove every direct attacker (typically
			# by blocking a ray).
			if base_map.attack_count(coordinate, model.get_other_color(piece.color)) > 0 and projected.attack_count(coordinate, model.get_other_color(piece.color)) == 0:
				score += _piece_value(piece) * 4.0
	var enemy_king: ModelPiece = model.get_king(model.get_other_color(necromancer.color))
	if enemy_king is KingPiece:
		var enemy_layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
		if enemy_layer != null:
			if _piece_has_lethal_effect(enemy_layer.collect_ability_threats(model, enemy_king, projected.occupancy, 0), pawn, target):
				score -= REMOVABLE_SUMMON_PENALTY
	var enemy := model.get_other_color(necromancer.color)
	if projected.attack_count(target, enemy) > 0 and projected.attack_count(target, necromancer.color) == 0:
		score -= REMOVABLE_SUMMON_PENALTY
	var advance := float(model.get_back_rank(necromancer.color) - target.x) if necromancer.color == "white" else float(target.x - model.get_back_rank(necromancer.color))
	var center := 3.5 - absf(float(target.y) - 3.5)
	score += advance * 0.08 + center * 0.04
	return score * own_sign


func _placement_is_forcing(model: ChessBoardModel, necromancer: ModelPiece, target: Vector2i, perspective: String) -> bool:
	var tactical := DupreTacticalMap.from_model(model)
	if placement_score(model, necromancer, target, perspective, tactical) <= DOOMED_SCORE:
		return false
	var occupancy := tactical.occupancy.duplicate()
	var pawn := BonePawnPiece.new(necromancer.color, target)
	pawn.piece_id = "dupre_forcing_bone_%s_%s" % [target.x, target.y]
	occupancy[target] = pawn
	var projected: DupreTacticalMap = tactical.project(occupancy)
	if projected.king_attackers(necromancer.color).size() < tactical.king_attackers(necromancer.color).size():
		return true
	var enemy_king: ModelPiece = model.get_king(model.get_other_color(necromancer.color))
	if enemy_king is KingPiece:
		var enemy_layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
		if enemy_layer != null:
			if _piece_has_lethal_effect(enemy_layer.collect_ability_threats(model, enemy_king, projected.occupancy, 0), pawn, target):
				return false
	if projected.attack_count(target, model.get_other_color(necromancer.color)) > 0 and projected.attack_count(target, necromancer.color) == 0:
		return false
	var attack_position := ChessAttackPosition.from_occupancy(projected.board_size, projected.occupancy)
	for coordinate in occupancy:
		var piece = occupancy[coordinate]
		if piece is ModelPiece and piece.color != necromancer.color and (piece.is_king or _piece_value(piece) >= 5.0):
			if pawn.can_directly_attack_square(target, coordinate, attack_position):
				return true
		if piece is ModelPiece and piece.color == necromancer.color and not piece.is_king and _piece_value(piece) >= 5.0:
			if tactical.attack_count(coordinate, model.get_other_color(piece.color)) > 0 and projected.attack_count(coordinate, model.get_other_color(piece.color)) == 0:
				return true
	return false


func _raise_dead_targets(model: ChessBoardModel, square: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(square.x - 1, square.x + 2):
		for column in range(square.y - 1, square.y + 2):
			var candidate := Vector2i(row, column)
			if model.is_in_bounds(row, column) and model.board[row][column] == null:
				result.append(candidate)
	return result


func _is_raise_dead_piece(piece: ModelPiece) -> bool:
	for base_type in ["knight", "rook", "bishop", "queen"]:
		if piece.type.contains(base_type):
			return true
	return false


func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0


func _piece_has_lethal_effect(effects: Array[DupreAbilityEffect], piece: ModelPiece, coordinate: Vector2i) -> bool:
	for effect in effects:
		if effect.lethal and (effect.target_piece_id == piece.piece_id or (effect.target_piece_id.is_empty() and effect.target_coordinate == coordinate)):
			return true
	return false
