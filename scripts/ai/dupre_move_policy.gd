extends RefCounted
class_name DupreMovePolicy

const ExchangeAnalyzer = preload("res://scripts/ai/dupre_exchange_analyzer.gd")

const REVERSAL_PENALTY := 4.0
const BACK_RANK_ROOK_SHUFFLE_PENALTY := 1.25
const DEVELOPMENT_REWARD := 2.0
const ROOK_ACTIVITY_REWARD := 1.5
const SAFE_RESCUE_MULTIPLIER := 1.25
const HANGING_DESTINATION_MULTIPLIER := 1.5
const THREAT_MULTIPLIER := 0.6
const NEW_KING_THREAT_PENALTY := 10000.0
const EXPOSED_UNDEFENDED_ALLY_MULTIPLIER := 4.0

var player: ChessCpuPlayer
var model: ChessBoardModel
var color: String
var previous_own_actions: Dictionary
var tactical_map: DupreTacticalMap
var exchange_analyzer
var _projected_maps: Dictionary = {}
var _exchange_results: Dictionary = {}
var _ability_effect_cache: Dictionary = {}
var _action_effect_cache: Dictionary = {}
var _action_assessment_cache: Dictionary = {}
var ability_threat_query_count := 0
var ability_threat_query_usec := 0
var ability_effect_collection_count := 0
var ability_effect_collection_usec := 0
var ability_effect_cache_hits := 0
var ability_action_effect_collection_count := 0
var ability_action_effect_collection_usec := 0


func _init(p_player: ChessCpuPlayer, p_previous_own_action: Dictionary = {}, p_tactical_map: DupreTacticalMap = null) -> void:
	player = p_player
	model = player.model
	color = player.controlled_color
	previous_own_actions = p_previous_own_action
	tactical_map = p_tactical_map if p_tactical_map != null else DupreTacticalMap.from_model(model)
	exchange_analyzer = ExchangeAnalyzer.new(model)


func score(action: ChessPrimaryAction) -> float:
	if player._is_immediate_win(action):
		return 10000.0
	var result := player._score_primary_action(action)
	var evaluated_layers := {}
	for side in [color, _other_color(color)]:
		var king: ModelPiece = model.get_king(side)
		if king == null or evaluated_layers.has(king.get_position_type_id()):
			continue
		var layer = ChessKingAiRegistry.layer_for(king.get_position_type_id())
		if layer != null:
			evaluated_layers[king.get_position_type_id()] = true
			result += float(layer.action_policy_bonus(model, action, color, tactical_map))
	var exchange := exchange_result(action)
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		var captured: ModelPiece = model.board[action.target.x][action.target.y]
		if captured != null and captured.color != action.piece.color:
			result += float(exchange.delta) - _piece_value(captured)
	for type_id in evaluated_layers:
		var exchange_layer = ChessKingAiRegistry.layer_for(type_id)
		result += float(exchange_layer.exchange_policy_adjustment(model, action, color, exchange, tactical_map))
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return result
	if creates_new_king_threat(action):
		result -= NEW_KING_THREAT_PENALTY
	var origin := action.piece.coordinate
	var destination := action.target
	var target: ModelPiece = model.board[destination.x][destination.y]
	var quiet := target == null
	var back_rank := model.get_back_rank(action.piece.color)

	if action.piece.type in ["knight", "bishop"] and origin.x == back_rank and destination.x != back_rank:
		result += DEVELOPMENT_REWARD
	elif action.piece.type == "pawn":
		var starting_rank := back_rank - 1 if action.piece.color == "white" else back_rank + 1
		if origin.x == starting_rank:
			result += DEVELOPMENT_REWARD * 0.45
	elif action.piece.type == "rook":
		if origin.x == back_rank and destination.x != back_rank:
			result += ROOK_ACTIVITY_REWARD
		elif quiet and origin.x == back_rank and destination.x == back_rank:
			result -= BACK_RANK_ROOK_SHUFFLE_PENALTY

	if action.piece.type in ["knight", "bishop", "queen"]:
		result += float(_center_distance(origin) - _center_distance(destination)) * 0.2
	if _is_immediate_reversal(action):
		result -= REVERSAL_PENALTY

	var projected := projected_map(action)
	var piece_value := _piece_value(action.piece)
	var projected_piece_coordinate := destination if _projected_piece_is(projected, destination, action.piece) else origin
	var was_attacked := tactical_map.attack_count(origin, _other_color(color)) > 0
	var becomes_attacked := projected.attack_count(projected_piece_coordinate, _other_color(color)) > 0
	if was_attacked and not becomes_attacked and piece_value >= 3.0:
		result += piece_value * SAFE_RESCUE_MULTIPLIER
	elif becomes_attacked and piece_value >= 3.0:
		result -= piece_value * HANGING_DESTINATION_MULTIPLIER

	var best_threat := 0.0
	for coordinate in projected.occupancy:
		var enemy = projected.occupancy[coordinate]
		if enemy is ModelPiece and enemy.color != color:
			if coordinate in projected.attacks_from(action.piece):
				best_threat = maxf(best_threat, 8.0 if enemy.is_king else _piece_value(enemy))
	result += best_threat * THREAT_MULTIPLIER
	result -= newly_exposed_undefended_value(action) * EXPOSED_UNDEFENDED_ALLY_MULTIPLIER
	return result


func creates_new_king_threat(action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return false
	var king: ModelPiece = model.get_king(color)
	if king == null:
		return false
	var projected := projected_map(action)
	var projected_coordinate := action.target if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece == king and _projected_piece_is(projected, action.target, king) else king.coordinate
	var current := tactical_map.attack_count(king.coordinate, _other_color(color))
	return projected.attack_count(projected_coordinate, _other_color(color)) > current


func newly_exposed_undefended_value(action: ChessPrimaryAction) -> float:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return 0.0
	return tactical_map.newly_exposed_undefended_value(projected_map(action), color, _piece_value)


func is_valuable_piece_threatened(piece: ModelPiece) -> bool:
	return not piece.is_king and _piece_value(piece) >= 5.0 and tactical_map.attack_count(piece.coordinate, _other_color(piece.color)) > 0


func ability_threat(piece: ModelPiece, horizon: int = 0, projected: DupreTacticalMap = null) -> Dictionary:
	var started := Time.get_ticks_usec()
	ability_threat_query_count += 1
	var result := _ability_threat(piece, horizon, projected)
	ability_threat_query_usec += Time.get_ticks_usec() - started
	return result


func _ability_threat(piece: ModelPiece, horizon: int, projected: DupreTacticalMap) -> Dictionary:
	if piece == null or piece.is_king:
		return {}
	var position := tactical_map if projected == null else projected
	var coordinate = position.piece_coordinates.get(piece.piece_id)
	if coordinate == null:
		return {}
	var projected_piece = position.occupancy.get(coordinate)
	if not projected_piece is ModelPiece:
		return {}
	for effect in ability_effects(horizon, position):
		if effect.target_piece_id == projected_piece.piece_id or (effect.target_piece_id.is_empty() and effect.target_coordinate == coordinate):
			return {
				"ability_id": effect.ability_id,
				"damage": effect.damage,
				"lethal": effect.lethal,
				"ready_in_turn_entries": effect.ready_in_turn_entries,
				"certainty": effect.certainty,
				"effect": effect,
			}
	return {}


func ability_effects(horizon: int = 0, projected: DupreTacticalMap = null) -> Array[DupreAbilityEffect]:
	var position := tactical_map if projected == null else projected
	var enemy_king: ModelPiece = model.get_king(_other_color(color))
	if not enemy_king is KingPiece:
		return []
	if not position.piece_coordinates.has(enemy_king.piece_id):
		return []
	var key := "%s|%s|%s|%s|%s" % [position.get_instance_id(), horizon, enemy_king.piece_id, enemy_king.current_cooldown, enemy_king.cooldown_reset_pending]
	if _ability_effect_cache.has(key):
		ability_effect_cache_hits += 1
		return _ability_effect_cache[key]
	var layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
	if layer == null:
		return []
	var started := Time.get_ticks_usec()
	ability_effect_collection_count += 1
	var effects: Array[DupreAbilityEffect] = layer.collect_ability_threats(model, enemy_king, position.occupancy, horizon)
	ability_effect_collection_usec += Time.get_ticks_usec() - started
	_ability_effect_cache[key] = effects
	return effects


func ability_threat_after(action: ChessPrimaryAction, piece: ModelPiece, horizon: int = 0) -> Dictionary:
	return ability_threat(piece, horizon, projected_map(action))


func ability_loss_after(action: ChessPrimaryAction, piece: ModelPiece, horizon: int = 1) -> float:
	if piece == null:
		return 0.0
	var position := projected_map(action)
	for effect in ability_effects(horizon, position):
		if effect.certainty != DupreAbilityEffect.Certainty.CERTAIN:
			continue
		if _effect_impacts_piece(effect, piece.piece_id) and (effect.lethal or bool(effect.metadata.get("king_exposure", false))):
			return _piece_value(piece)
	return 0.0


func ability_obligations(horizon: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for effect in ability_effects(horizon):
		if effect.certainty != DupreAbilityEffect.Certainty.CERTAIN or (not effect.lethal and not bool(effect.metadata.get("king_exposure", false))):
			continue
		for piece_id in _effect_impacted_piece_ids(effect):
			if piece_id.is_empty() or seen.has(piece_id):
				continue
			var piece := _piece_by_id(tactical_map, piece_id)
			if piece == null or piece.color != color:
				continue
			var value := 100.0 if piece.is_king else _piece_value(piece)
			result.append({"piece": piece, "loss": value, "effect": effect, "ability_id": effect.ability_id})
			seen[piece_id] = true
	return result


func creates_new_ability_emergency(action: ChessPrimaryAction, horizon: int = 1) -> bool:
	var enemy_king: ModelPiece = model.get_king(_other_color(color))
	if not enemy_king is KingPiece:
		return false
	var enemy_layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
	if enemy_layer == null or not enemy_layer.has_ability_threat_effects():
		return false
	var current_ids := {}
	for obligation in ability_obligations(horizon):
		current_ids[obligation.piece.piece_id] = true
	var projected := projected_map(action)
	for effect in ability_effects(horizon, projected):
		if effect.certainty != DupreAbilityEffect.Certainty.CERTAIN or (not effect.lethal and not bool(effect.metadata.get("king_exposure", false))):
			continue
		var piece_id := _effect_impacted_piece_id(effect)
		if current_ids.has(piece_id):
			continue
		var piece := _piece_by_id(projected, piece_id)
		if piece != null and piece.color == color and (piece.is_king or _piece_value(piece) >= 3.0):
			return true
	return false


func action_effects(action: ChessPrimaryAction) -> Array[DupreAbilityEffect]:
	var key := _action_key(action)
	if _action_effect_cache.has(key):
		ability_effect_cache_hits += 1
		return _action_effect_cache[key]
	var result: Array[DupreAbilityEffect] = []
	var started := Time.get_ticks_usec()
	ability_action_effect_collection_count += 1
	var own_layer = ChessKingAiRegistry.layer_for(action.piece.get_position_type_id()) if action.piece is KingPiece else null
	if own_layer != null:
		result.append_array(own_layer.describe_ability_action(model, action, tactical_map.occupancy))
	var enemy_king: ModelPiece = model.get_king(_other_color(action.piece.color))
	if enemy_king is KingPiece:
		var enemy_layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
		if enemy_layer != null:
			result.append_array(enemy_layer.describe_action_reactions(model, action, tactical_map.occupancy))
	_action_effect_cache[key] = result
	ability_action_effect_collection_usec += Time.get_ticks_usec() - started
	return result


func action_may_have_effects(action: ChessPrimaryAction) -> bool:
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.piece is KingPiece and ChessKingAiRegistry.layer_for(action.piece.get_position_type_id()) != null:
		return true
	var enemy_king: ModelPiece = model.get_king(_other_color(action.piece.color))
	if not enemy_king is KingPiece:
		return false
	var enemy_layer = ChessKingAiRegistry.layer_for(enemy_king.get_position_type_id())
	return enemy_layer != null and enemy_layer.has_action_reaction_effects()


func action_effect_assessment(action: ChessPrimaryAction) -> Dictionary:
	var key := _action_key(action)
	if _action_assessment_cache.has(key):
		return _action_assessment_cache[key]
	var result := {
		"certain_value": 0.0,
		"high_impact": false,
		"forcing": false,
		"requires_verification": false,
		"uncertain": false,
		"king_damage": 0,
		"lethal_king": false,
		"effect_count": 0,
		"effects": [],
	}
	for effect in action_effects(action):
		if not effect.is_valid():
			continue
		result.effect_count += 1
		result.effects.append(effect.to_diagnostic())
		if effect.certainty != DupreAbilityEffect.Certainty.CERTAIN:
			result.uncertain = true
			result.requires_verification = true
			if effect.certainty == DupreAbilityEffect.Certainty.SIMULATION_REQUIRED or effect.lethal or effect.damage > 0:
				result.high_impact = true
			continue
		if bool(effect.metadata.get("king_exposure", false)):
			result.certain_value += 30.0
			result.high_impact = true
			result.forcing = true
		var target := _piece_by_id(tactical_map, _effect_impacted_piece_id(effect))
		match effect.kind:
			DupreAbilityEffect.Kind.DAMAGE:
				if target != null and target.color != color:
					if target.is_king:
						result.king_damage += effect.damage
						result.lethal_king = result.lethal_king or effect.lethal
						result.certain_value += 1000.0 if effect.lethal else 20.0 * maxf(1.0, effect.damage)
						result.high_impact = true
						result.forcing = true
					elif effect.lethal:
						result.certain_value += _piece_value(target)
						result.high_impact = result.high_impact or _piece_value(target) >= 3.0
						result.forcing = result.forcing or _piece_value(target) >= 3.0
			DupreAbilityEffect.Kind.FORCED_MOVEMENT:
				result.certain_value += effect.material_delta
				result.lethal_king = result.lethal_king or effect.lethal
				result.high_impact = result.high_impact or effect.lethal or absf(effect.material_delta) >= 3.0
				result.forcing = result.forcing or result.high_impact
			DupreAbilityEffect.Kind.BLOCK:
				var removed := int(effect.metadata.get("king_attackers_removed", 0))
				result.certain_value += float(removed) * 25.0
				result.high_impact = result.high_impact or removed > 0
				result.forcing = result.forcing or removed > 0
			DupreAbilityEffect.Kind.STUN:
				if bool(effect.metadata.get("self_stun", false)):
					result.certain_value -= 6.0
	_action_assessment_cache[key] = result
	return result


func _effect_impacts_piece(effect: DupreAbilityEffect, piece_id: String) -> bool:
	return piece_id in _effect_impacted_piece_ids(effect)


func _effect_impacted_piece_ids(effect: DupreAbilityEffect) -> Array[String]:
	var result: Array[String] = []
	var primary := _effect_impacted_piece_id(effect)
	if not primary.is_empty():
		result.append(primary)
	var exposed := String(effect.metadata.get("exposed_king_id", ""))
	if not exposed.is_empty() and exposed not in result:
		result.append(exposed)
	return result


func _effect_impacted_piece_id(effect: DupreAbilityEffect) -> String:
	if effect.kind == DupreAbilityEffect.Kind.FORCED_MOVEMENT:
		var captured := String(effect.metadata.get("captured_piece_id", ""))
		if not captured.is_empty():
			return captured
	return effect.target_piece_id


func _piece_by_id(position: DupreTacticalMap, piece_id: String) -> ModelPiece:
	var coordinate = position.piece_coordinates.get(piece_id)
	if coordinate == null:
		return null
	var piece = position.occupancy.get(coordinate)
	return piece if piece is ModelPiece else null


func _action_key(action: ChessPrimaryAction) -> String:
	return "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]


func projected_map(action: ChessPrimaryAction) -> DupreTacticalMap:
	var key := "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]
	if not _projected_maps.has(key):
		_projected_maps[key] = tactical_map.project(player._project_board_after(action))
	return _projected_maps[key]


func direct_king_threat_count_after(action: ChessPrimaryAction) -> int:
	var king: ModelPiece = model.get_king(color)
	if king == null:
		return 0
	var projected := projected_map(action)
	var coordinate := action.target if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece == king and _projected_piece_is(projected, action.target, king) else king.coordinate
	return projected.attack_count(coordinate, _other_color(color))


func _projected_piece_is(projected: DupreTacticalMap, coordinate: Vector2i, piece: ModelPiece) -> bool:
	var occupant = projected.occupancy.get(coordinate)
	return occupant is ModelPiece and occupant == piece


func capture_material_swing(action: ChessPrimaryAction) -> float:
	var result := exchange_result(action)
	# Compatibility: callers use this method to identify actual material
	# captures. Nonlethal HP damage is valued by score(), but is not a capture.
	return 0.0 if result.reason == &"durable_target" else float(result.delta)


func exchange_result(action: ChessPrimaryAction) -> Dictionary:
	var key := "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]
	if not _exchange_results.has(key):
		_exchange_results[key] = exchange_analyzer.analyze_capture(action, projected_map(action))
	return _exchange_results[key]


func material_risk(piece: ModelPiece) -> Dictionary:
	return exchange_analyzer.analyze_piece_risk(piece, tactical_map)


func material_risk_after(action: ChessPrimaryAction, piece: ModelPiece) -> Dictionary:
	var projected := projected_map(action)
	var coordinate = projected.piece_coordinates.get(piece.piece_id)
	if coordinate == null:
		return {"delta": 0.0, "loss": 0.0, "confidence": ExchangeAnalyzer.Confidence.HIGH, "reason": &"removed", "sequence": []}
	var projected_piece = projected.occupancy.get(coordinate)
	if not projected_piece is ModelPiece:
		return {"delta": 0.0, "loss": 0.0, "confidence": ExchangeAnalyzer.Confidence.LOW, "reason": &"unknown", "sequence": []}
	return exchange_analyzer.analyze_piece_risk(projected_piece, projected)


func captures_current_king_attacker(action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return false
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null or target.color == color or target.current_hp > action.piece.attack_power:
		return false
	for attacker in tactical_map.king_attackers(color):
		if attacker == target:
			return true
	return false


func projection_metrics() -> Dictionary:
	var recalculations := 0
	var attack_calls := 0
	var projection_usec := 0
	for projected in _projected_maps.values():
		recalculations += projected.incremental_recalculations
		attack_calls += projected.direct_attack_calls
		projection_usec += projected.build_usec + projected.query_usec
	return {
		"count": _projected_maps.size(),
		"recalculations": recalculations,
		"attack_calls": attack_calls,
		"usec": projection_usec,
		"exchange": exchange_analyzer.metrics(),
		"ability_threat_queries": ability_threat_query_count,
		"ability_threat_usec": ability_threat_query_usec,
		"ability_effect_collections": ability_effect_collection_count,
		"ability_effect_collection_usec": ability_effect_collection_usec,
		"ability_effect_cache_hits": ability_effect_cache_hits,
		"ability_effect_count": _cached_effect_count(),
		"ability_action_effect_collections": ability_action_effect_collection_count,
		"ability_action_effect_collection_usec": ability_action_effect_collection_usec,
	}


func _cached_effect_count() -> int:
	var result := 0
	for effects in _ability_effect_cache.values():
		result += effects.size()
	for effects in _action_effect_cache.values():
		result += effects.size()
	return result


func _is_immediate_reversal(action: ChessPrimaryAction) -> bool:
	var previous: Dictionary = previous_own_actions.get(action.piece.piece_id, {})
	# Accept the original single-action shape as well; it is useful to isolated
	# policy callers and older serialized prototype fixtures.
	if previous.is_empty() and previous_own_actions.get("piece_id", "") == action.piece.piece_id:
		previous = previous_own_actions
	return (
		not previous.is_empty()
		and action.kind == ChessPrimaryAction.Kind.MOVE
		and previous.get("from", Vector2i(-1, -1)) == action.target
		and previous.get("to", Vector2i(-1, -1)) == action.piece.coordinate
	)


func _piece_value(piece: ModelPiece) -> float:
	return player._get_piece_value(piece)


func _other_color(value: String) -> String:
	return "black" if value == "white" else "white"


func _center_distance(coordinate: Vector2i) -> int:
	return mini(
		absi(coordinate.x - 3) + absi(coordinate.y - 3),
		absi(coordinate.x - 4) + absi(coordinate.y - 4)
	)
