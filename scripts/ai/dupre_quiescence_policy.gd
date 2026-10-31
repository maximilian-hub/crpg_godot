extends RefCounted
class_name DupreQuiescencePolicy

const AbilityEffect := preload("res://scripts/ai/dupre_ability_effect.gd")
const KingAiRegistry := preload("res://scripts/ai/chess_king_ai_registry.gd")

enum Category { QUIET, TACTICAL, CRITICAL }

const MATERIAL_VALUES := {
	&"pawn": 1.0,
	&"bone_pawn": 1.0,
	&"knight": 3.0,
	&"bishop": 3.0,
	&"rook": 5.0,
	&"queen": 9.0,
}


static func classify(model: ChessBoardModel, action: ChessPrimaryAction, tactical_map: DupreTacticalMap) -> Dictionary:
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		return _classify_move(model, action)
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is KingPiece:
		return _result(Category.QUIET, 0.0, &"non_tactical_action")
	var layer = KingAiRegistry.layer_for(action.piece.get_position_type_id())
	if layer == null:
		return _result(Category.QUIET, 0.0, &"unsupported_ability")
	if not layer.should_describe_for_quiescence(model, action, tactical_map):
		return _result(Category.QUIET, 0.0, &"positional_ability")
	var best := _result(Category.QUIET, 0.0, &"positional_ability")
	for effect in layer.describe_ability_action(model, action, tactical_map.occupancy):
		var classified := _classify_effect(model, action, effect, tactical_map)
		if int(classified.category) > int(best.category) or (int(classified.category) == int(best.category) and float(classified.priority) > float(best.priority)):
			best = classified
	return best


static func _classify_move(model: ChessBoardModel, action: ChessPrimaryAction) -> Dictionary:
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null or target.color == action.piece.color:
		return _result(Category.QUIET, 0.0, &"quiet_move")
	var damage := action.piece.attack_power
	var value := _piece_value(target)
	if target.is_king:
		return _result(Category.CRITICAL, 50000.0 + value, &"king_damage")
	if damage >= target.current_hp:
		return _result(Category.TACTICAL, 30000.0 + value * 100.0, &"ordinary_capture")
	if value >= 5.0:
		return _result(Category.TACTICAL, 20000.0 + value * 100.0, &"major_damage")
	return _result(Category.QUIET, 0.0, &"nonlethal_minor_damage")


static func _classify_effect(model: ChessBoardModel, action: ChessPrimaryAction, effect: DupreAbilityEffect, tactical_map: DupreTacticalMap) -> Dictionary:
	if effect.trigger != AbilityEffect.Trigger.ACTIVE or effect.ready_in_turn_entries > 0:
		return _result(Category.QUIET, 0.0, &"scheduled_effect")
	if effect.certainty != AbilityEffect.Certainty.CERTAIN:
		return _result(Category.QUIET, 0.0, &"uncertain_effect")
	var target: ModelPiece = _effect_target(model, effect, tactical_map)
	var enemy_target := target is ModelPiece and target.color != action.piece.color
	var target_value := _piece_value(target) if target is ModelPiece else 0.0
	match effect.kind:
		AbilityEffect.Kind.DAMAGE:
			if enemy_target and target.is_king and effect.damage > 0:
				return _result(Category.CRITICAL, 60000.0 + float(effect.damage), &"king_damage")
			if enemy_target and effect.lethal:
				return _result(Category.TACTICAL, 40000.0 + target_value * 100.0, &"lethal_material_damage")
			if enemy_target and target_value >= 5.0 and effect.damage > 0:
				return _result(Category.TACTICAL, 25000.0 + target_value * 100.0, &"major_damage")
		AbilityEffect.Kind.FORCED_MOVEMENT, AbilityEffect.Kind.DISPLACEMENT:
			if effect.lethal:
				return _result(Category.CRITICAL, 55000.0, &"forced_king_capture")
			if bool(effect.metadata.get("king_exposure", false)):
				return _result(Category.TACTICAL, 35000.0, &"forced_king_exposure")
			if effect.material_delta > 0.0 or _captures_enemy(effect, action.piece.color):
				return _result(Category.TACTICAL, 30000.0 + maxf(0.0, effect.material_delta) * 100.0, &"forced_material_capture")
		AbilityEffect.Kind.STUN:
			if enemy_target and target.is_king:
				return _result(Category.CRITICAL, 45000.0, &"king_stun")
			if enemy_target and target_value >= 5.0:
				return _result(Category.TACTICAL, 22000.0 + target_value * 100.0, &"major_stun")
		AbilityEffect.Kind.BLOCK:
			if int(effect.metadata.get("king_attackers_removed", 0)) > 0:
				return _result(Category.CRITICAL, 52000.0, &"emergency_king_block")
		AbilityEffect.Kind.AREA_HAZARD:
			return _result(Category.QUIET, 0.0, &"scheduled_effect")
		AbilityEffect.Kind.MOVEMENT_GRANT:
			return _result(Category.QUIET, 0.0, &"positional_ability")
	return _result(Category.QUIET, 0.0, &"positional_ability")


static func _effect_target(model: ChessBoardModel, effect: DupreAbilityEffect, tactical_map: DupreTacticalMap) -> ModelPiece:
	if not effect.target_piece_id.is_empty():
		for piece in tactical_map.occupancy.values():
			if piece is ModelPiece and piece.piece_id == effect.target_piece_id:
				return piece
	if model.is_in_bounds(effect.target_coordinate.x, effect.target_coordinate.y):
		return tactical_map.occupancy.get(effect.target_coordinate)
	return null


static func _captures_enemy(effect: DupreAbilityEffect, source_color: String) -> bool:
	var captured_color := String(effect.metadata.get("captured_color", ""))
	return not captured_color.is_empty() and captured_color != source_color


static func _piece_value(piece: ModelPiece) -> float:
	if not piece is ModelPiece:
		return 0.0
	if piece.is_king:
		return 100.0
	return float(MATERIAL_VALUES.get(piece.get_position_type_id(), 1.0))


static func _result(category: int, priority: float, reason: StringName) -> Dictionary:
	return {"category": category, "priority": priority, "reason": reason}
