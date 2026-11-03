extends RefCounted
class_name DupreClassicCoreBackend

const MATERIAL_VALUES := {
	&"pawn": 1.0, &"knight": 3.0, &"bishop": 3.0,
	&"rook": 5.0, &"queen": 9.0,
}
const QuarterlyPolicy := preload("res://scripts/ai/quarterly_initiative_ai_policy.gd")
const QuarterlyRules := preload("res://scripts/core/pure/quarterly_initiative_core_rules.gd")
const CannonRules := preload("res://scripts/core/pure/cannon_core_rules.gd")
const RhetoricianRules := preload("res://scripts/core/pure/rhetorician_core_rules.gd")
const WraithRules := preload("res://scripts/core/pure/wraith_core_rules.gd")
const WraithPolicy := preload("res://scripts/ai/wraith_ai_policy.gd")
const EndgamePolicy := preload("res://scripts/ai/dupre_endgame_policy.gd")
const RHETORICIAN_LUNACY_VALUE := 2.0
const RHETORICIAN_SOCRATIC_TURN_VALUE := 8.0


static func action_for_descriptor(state: ChessCoreState, descriptor: Dictionary) -> ChessCoreAction:
	if state == null: return null
	var piece := state.piece_by_id(String(descriptor.get("piece_id", "")))
	if piece == null: return null
	var action := ChessCoreAction.new()
	action.kind = int(descriptor.get("kind", -1))
	action.piece_id = piece.piece_id
	action.color = piece.color
	action.from = descriptor.get("from", piece.coordinate)
	action.target = descriptor.get("target", Vector2i(-1, -1))
	action.path.assign(descriptor.get("path", []))
	return action


static func describe(action: ChessCoreAction) -> Dictionary:
	return {
		"kind": action.kind, "piece_id": action.piece_id,
		"from": action.from, "target": action.target, "path": action.path.duplicate(),
	}


static func resolve(state: ChessCoreState, descriptor: Dictionary) -> ChessCoreStepResult:
	var action := action_for_descriptor(state, descriptor)
	if action == null: return ChessCoreStepResult.rejected(state, "Descriptor does not match a legal Classic action.")
	var result := ClassicChessCore.resolve_action(state, action, false)
	var reaction_colors: Array[String] = []
	while result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		if result.choice == null: return ChessCoreStepResult.rejected(state, "Pure simulation exposed an empty choice.")
		var option
		if result.choice.kind == &"promotion":
			if &"queen" not in result.choice.options: return ChessCoreStepResult.rejected(state, "Dupre's Queen promotion is unavailable.")
			option = &"queen"
		elif result.choice.kind == &"raise_dead":
			var caller := result.state.piece_by_id(result.choice.piece_id)
			if caller != null: reaction_colors.append(caller.color)
			option = _best_raise_dead_target(result.state, result.choice)
			if option == null: return ChessCoreStepResult.rejected(state, "Dupre could not settle Raise Dead.")
		elif result.choice.kind == &"movement_type_grant":
			option = _best_quarterly_grant(result.state, result.choice)
			if option == null: return ChessCoreStepResult.rejected(state, "Dupre could not settle Stakeholder Pandering.")
		elif result.choice.kind == &"lingering_malice":
			option = _best_lingering_malice(result.state, result.choice)
			if option == null: return ChessCoreStepResult.rejected(state, "Dupre could not settle Lingering Malice.")
		else:
			return ChessCoreStepResult.rejected(state, "Dupre does not support this pure-core choice.")
		result = ClassicChessCore.resolve_choice(result.state, option, false)
	result.resolved_reaction_colors.assign(reaction_colors)
	return result


static func ordered_replies(state: ChessCoreState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions := _analysis_actions(state, state.current_turn)
	for index in range(actions.size()):
		var action: ChessCoreAction = actions[index]
		var reply_class := _reply_class(state, action)
		var descriptor := describe(action)
		descriptor["reply_class"] = reply_class
		descriptor["forcing"] = reply_class > 0
		descriptor["priority"] = float(reply_class * 10000) + _reply_priority(state, action)
		descriptor["index"] = index
		result.append(descriptor)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.priority), float(b.priority)): return float(a.priority) > float(b.priority)
		return int(a.index) < int(b.index)
	)
	return result


static func evaluate_static(state: ChessCoreState, perspective: String, tactical_detail := true, generate_actions := true, endgame_policy_enabled := true, endgame_technique_enabled := true) -> Dictionary:
	if state.battle_over:
		return {"score": terminal_score(state, perspective), "own_actions": [], "enemy_actions": []}
	var enemy := _other_color(perspective)
	var score := 0.0
	var non_pawn_material := 0.0
	var total_material := 0.0
	var material_balance := 0.0
	for piece in state.pieces:
		var sign_value := 1.0 if piece.color == perspective else -1.0
		if piece.is_king():
			score += sign_value * float(piece.current_hp) * 50.0
		else:
			var value := _material_value(piece) * 10.0
			var raw_material := _material_value(piece)
			total_material += raw_material
			material_balance += raw_material if piece.color == perspective else -raw_material
			if piece.type_id not in [&"pawn", &"bone_pawn"]: non_pawn_material += raw_material
			var hp_ratio := float(piece.current_hp) / float(maxi(1, piece.max_hp))
			value -= value * 0.3 * (1.0 - hp_ratio)
			score += sign_value * value
		var grant_bonus := float(piece.granted_movement_types.size()) * 0.6
		score += grant_bonus if piece.color == perspective else -grant_bonus
	var own_actions: Array[ChessCoreAction] = []
	var enemy_actions: Array[ChessCoreAction] = []
	if generate_actions:
		own_actions = _analysis_actions(state, perspective)
		enemy_actions = _analysis_actions(state, enemy)
	score += float(own_actions.size() - enemy_actions.size()) * 0.1
	if tactical_detail:
		for piece in state.pieces:
			if piece.is_king() or _material_value(piece) < 5.0: continue
			if is_hanging(state, piece):
				var penalty := _material_value(piece) * 4.0
				score += -penalty if piece.color == perspective else penalty
		score -= float(king_attackers(state, perspective).size()) * 25.0
		score += float(king_attackers(state, enemy).size()) * 25.0
	if generate_actions and _has_lethal_action(state, enemy_actions, perspective): score -= 500.0
	if generate_actions and _has_lethal_action(state, own_actions, enemy): score += 500.0
	score += _minotaur_evaluation_bonus(state, perspective)
	score += _arc_mortar_evaluation_bonus(state, perspective)
	score += _rhetorician_evaluation_bonus(state, perspective)
	score += _wraith_evaluation_bonus(state, perspective)
	var endgame := EndgamePolicy.analyze_core(state, perspective, endgame_technique_enabled) if endgame_policy_enabled and non_pawn_material < EndgamePolicy.ENDGAME_BLEND_START else EndgamePolicy.middlegame_analysis(material_balance, total_material, non_pawn_material)
	score += float(endgame.score)
	return {"score": score, "own_actions": own_actions, "enemy_actions": enemy_actions, "endgame": endgame}


static func classify_quiescence(state: ChessCoreState, action: ChessCoreAction) -> Dictionary:
	var action_piece := state.piece_by_id(action.piece_id)
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"necromancer_king":
		var summon_priority := _necromancer_placement_score(state, action_piece, action.target, action.color)
		if _summon_is_forcing(state, state.piece_by_id(action.piece_id), action.target):
			return {"category": 1, "priority": 15000.0 + summon_priority, "reason": &"consequential_summon"}
		return {"category": 0, "priority": summon_priority, "reason": &"quiet_summon"}
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"minotaur_king":
		var charge_target := state.occupant(action.target)
		if charge_target == null or charge_target.color == action.color:
			return {"category": 0, "priority": 0.0, "reason": &"positional_ability"}
		var charge_value := 100.0 if charge_target.is_king() else _material_value(charge_target)
		if charge_target.is_king():
			return {"category": 2, "priority": 60002.0, "reason": &"king_damage"}
		if MinotaurCoreRules.CHARGE_DAMAGE >= charge_target.current_hp:
			return {"category": 1, "priority": 40000.0 + charge_value * 100.0, "reason": &"lethal_material_damage"}
		if charge_value >= 5.0:
			return {"category": 1, "priority": 25000.0 + charge_value * 100.0, "reason": &"major_damage"}
		return {"category": 0, "priority": 0.0, "reason": &"positional_ability"}
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"quarterly_initiative_king":
		return {"category": 0, "priority": _quarterly_action_score(state, action_piece, state.occupant(action.target)), "reason": &"positional_ability"}
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"cannon_king":
		return {"category": 0, "priority": _cannon_footprint_score(state, action.target, action.color), "reason": &"positional_ability"}
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"rhetorician_king":
		return _classify_rhetorician_compel(state, action_piece, state.occupant(action.target))
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece.type_id == &"wraith_king":
		return {"category": 0, "priority": _wraith_summon_score(state, action_piece, state.occupant(action.target), action.color), "reason": &"delayed_ability"}
	var target := state.occupant(action.target)
	if target == null or target.color == action.color:
		return {"category": 0, "priority": 0.0, "reason": &"quiet_move"}
	var attacker := state.piece_by_id(action.piece_id)
	var value := 100.0 if target.is_king() else _material_value(target)
	if target.is_king():
		return {"category": 2, "priority": 50000.0 + value, "reason": &"king_damage"}
	if attacker.attack_power >= target.current_hp:
		return {"category": 1, "priority": 30000.0 + value * 100.0, "reason": &"ordinary_capture"}
	if value >= 5.0:
		return {"category": 1, "priority": 20000.0 + value * 100.0, "reason": &"major_damage"}
	return {"category": 0, "priority": 0.0, "reason": &"nonlethal_minor_damage"}


static func king_attackers(state: ChessCoreState, color: String) -> Array[ChessCorePiece]:
	for piece in state.pieces:
		if piece.color == color and piece.is_king():
			return _tactical_attackers(state, piece.coordinate, _other_color(color))
	return []


static func is_hanging(state: ChessCoreState, piece: ChessCorePiece) -> bool:
	return (
		not _tactical_attackers(state, piece.coordinate, _other_color(piece.color)).is_empty()
		and _tactical_attackers(state, piece.coordinate, piece.color).is_empty()
	)


static func terminal_score(state: ChessCoreState, perspective: String) -> float:
	if state.battle_result == perspective: return 1000000.0
	if state.battle_result == "draw": return 0.0
	return -1000000.0


static func _reply_class(state: ChessCoreState, action: ChessCoreAction) -> int:
	var action_piece := state.piece_by_id(action.piece_id)
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"necromancer_king":
		return 1 if _summon_is_forcing(state, action_piece, action.target) else 0
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"minotaur_king":
		return 3 if _minotaur_charge_is_forcing(state, action_piece, action.target) else 2
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"quarterly_initiative_king":
		return 1 if _quarterly_action_score(state, action_piece, state.occupant(action.target)) >= 20.0 else 0
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"cannon_king":
		return 1 if _cannon_footprint_contains_enemy_king(state, action.target, action.color) or _cannon_footprint_score(state, action.target, action.color) >= 8.0 else 0
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"rhetorician_king":
		return 3 if _rhetorician_compel_is_forcing(state, action_piece, state.occupant(action.target)) else 0
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action_piece != null and action_piece.type_id == &"wraith_king":
		return 0
	var target := state.occupant(action.target)
	var attacker := action_piece
	if target != null and target.color != action.color:
		if target.is_king() and attacker.attack_power >= target.current_hp: return 4
		if target.is_king(): return 3
		return 2
	if _directly_threatens_major(state, action): return 1
	return 0


static func _reply_priority(state: ChessCoreState, action: ChessCoreAction) -> float:
	var target := state.occupant(action.target)
	if target != null and target.color != action.color:
		if target.is_king(): return 10000.0
		return 1000.0 + _material_value(target)
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY: return 500.0
	return 0.0


static func _minotaur_charge_is_forcing(state: ChessCoreState, minotaur: ChessCorePiece, target_coordinate: Vector2i) -> bool:
	var target := state.occupant(target_coordinate)
	return target != null and target.color != minotaur.color and (target.is_king() or target.current_hp <= MinotaurCoreRules.CHARGE_DAMAGE or _material_value(target) >= 3.0)


static func _minotaur_evaluation_bonus(state: ChessCoreState, perspective: String) -> float:
	var result := 0.0
	for minotaur in state.pieces:
		if minotaur.type_id != &"minotaur_king" or minotaur.stunned or not (state.active_ability_cooldowns_disabled or (minotaur.current_cooldown == 0 and not minotaur.cooldown_reset_pending)):
			continue
		var pressure := 0.0
		for coordinate in MinotaurCoreRules.active_targets(state, minotaur):
			var target := state.occupant(coordinate)
			if target == null or target.color == minotaur.color: continue
			pressure = maxf(pressure, 5.0 if target.is_king() else minf(_material_value(target), 3.0))
		result += pressure if minotaur.color == perspective else -pressure
	return result


static func _cannon_footprint_score(state: ChessCoreState, anchor: Vector2i, owner_color: String) -> float:
	var score := 0.2
	for coordinate in CannonRules.area(anchor):
		var piece := state.occupant(coordinate)
		if piece == null: continue
		var value := 20.0 if piece.is_king() else _material_value(piece)
		if piece.current_hp <= CannonRules.DAMAGE: value *= 1.25
		score += value if piece.color != owner_color else -value * 1.5
	return score


static func _cannon_footprint_contains_enemy_king(state: ChessCoreState, anchor: Vector2i, owner_color: String) -> bool:
	for coordinate in CannonRules.area(anchor):
		var piece := state.occupant(coordinate)
		if piece != null and piece.color != owner_color and piece.is_king(): return true
	return false


static func _arc_mortar_evaluation_bonus(state: ChessCoreState, perspective: String) -> float:
	var result := 0.0
	for entity in state.autonomous_entities:
		if entity.type_id != &"arc_mortar": continue
		var remaining := maxi(1, int(entity.custom_state.get("landing_turn", state.global_turn_number + CannonRules.DELAY_ROUNDS)) - state.global_turn_number)
		var urgency := 1.4 if remaining <= 1 else (0.7 if remaining == 2 else 0.3)
		for coordinate in CannonRules.area(entity.coordinate):
			var piece := state.occupant(coordinate)
			if piece == null: continue
			var exposure := (12.0 if piece.is_king() else _material_value(piece)) * urgency
			if piece.current_hp <= CannonRules.DAMAGE: exposure *= 1.5
			result += -exposure if piece.color == perspective else exposure
	return result


static func _rhetorician_evaluation_bonus(state: ChessCoreState, perspective: String) -> float:
	var enemy := _other_color(perspective)
	return (
		float(state.lunacy_by_color.get(enemy, 0) - state.lunacy_by_color.get(perspective, 0)) * RHETORICIAN_LUNACY_VALUE
		+ float(state.socratic_turns_by_color.get(enemy, 0) - state.socratic_turns_by_color.get(perspective, 0)) * RHETORICIAN_SOCRATIC_TURN_VALUE
	)


static func _rhetorician_compel_destination(rhetorician: ChessCorePiece, compelled: ChessCorePiece) -> Vector2i:
	var delta := rhetorician.coordinate - compelled.coordinate
	return compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))


static func _rhetorician_compel_policy_score(state: ChessCoreState, rhetorician: ChessCorePiece, compelled: ChessCorePiece) -> float:
	if rhetorician == null or compelled == null:
		return -INF
	var result := -_material_value(compelled)
	var destination := _rhetorician_compel_destination(rhetorician, compelled)
	var occupant := state.occupant(destination)
	if occupant != null:
		result += _material_value(occupant) if occupant.color != rhetorician.color else -_material_value(occupant)
	return result


static func _rhetorician_compel_is_forcing(state: ChessCoreState, rhetorician: ChessCorePiece, compelled: ChessCorePiece) -> bool:
	if rhetorician == null or compelled == null:
		return false
	var occupant := state.occupant(_rhetorician_compel_destination(rhetorician, compelled))
	return occupant != null or compelled.is_king() or _material_value(compelled) >= 5.0


static func _classify_rhetorician_compel(state: ChessCoreState, rhetorician: ChessCorePiece, compelled: ChessCorePiece) -> Dictionary:
	if rhetorician == null or compelled == null:
		return {"category": 0, "priority": 0.0, "reason": &"positional_ability"}
	var destination := _rhetorician_compel_destination(rhetorician, compelled)
	var occupant := state.occupant(destination)
	if occupant != null and occupant.is_king():
		return {"category": 2, "priority": 55000.0, "reason": &"forced_king_capture"}
	if occupant != null and occupant.color != rhetorician.color:
		return {"category": 1, "priority": 30000.0 + _material_value(occupant) * 100.0, "reason": &"forced_material_capture"}
	# Preserve the model policy's tactical extension when vacating the compelled
	# square newly exposes that side's King.
	var enemy_king: ChessCorePiece
	for piece in state.pieces:
		if piece.color == compelled.color and piece.is_king(): enemy_king = piece; break
	if enemy_king != null:
		var before := _tactical_attackers(state, enemy_king.coordinate, rhetorician.color).size()
		var projected := state.copy()
		var projected_compelled := projected.piece_by_id(compelled.piece_id)
		var projected_occupant := projected.occupant(destination)
		if projected_occupant != null: projected.remove_piece(projected_occupant)
		projected.move_piece(projected_compelled, destination)
		var projected_king := projected.piece_by_id(enemy_king.piece_id)
		if projected_king != null and _tactical_attackers(projected, projected_king.coordinate, rhetorician.color).size() > before:
			return {"category": 1, "priority": 35000.0, "reason": &"forced_king_exposure"}
	return {"category": 0, "priority": _rhetorician_compel_policy_score(state, rhetorician, compelled), "reason": &"positional_ability"}


static func _directly_threatens_major(state: ChessCoreState, action: ChessCoreAction) -> bool:
	var target := state.occupant(action.target)
	var attacker := state.piece_by_id(action.piece_id)
	if target != null and target.color != action.color and target.current_hp > attacker.attack_power:
		return false
	var projected := state.occupancy.duplicate()
	projected.erase(action.from)
	projected.erase(action.target)
	projected[action.target] = attacker
	for piece in state.pieces:
		if piece == target: continue
		if piece.color != attacker.color and not piece.is_king() and _material_value(piece) >= 5.0:
			if ClassicChessCore.geometrically_attacks_in_occupancy(attacker, action.target, piece.coordinate, projected): return true
	return false


static func _has_lethal_action(state: ChessCoreState, actions: Array[ChessCoreAction], defender_color: String) -> bool:
	var king: ChessCorePiece
	for piece in state.pieces:
		if piece.color == defender_color and piece.is_king(): king = piece; break
	if king == null: return true
	for action in actions:
		var attacker := state.piece_by_id(action.piece_id)
		if action.target != king.coordinate or attacker == null: continue
		if action.kind == ChessCoreAction.Kind.MOVE and attacker.attack_power >= king.current_hp: return true
		if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY:
			if attacker.type_id == &"arakne_king" and king.current_hp <= 2: return true
			if attacker.type_id == &"minotaur_king" and king.current_hp <= 2: return true
	return false


static func _material_value(piece: ChessCorePiece) -> float:
	return float(MATERIAL_VALUES.get(piece.type_id, 1.0))


static func _best_raise_dead_target(state: ChessCoreState, choice: ChessCoreChoice):
	var necromancer := state.piece_by_id(choice.piece_id)
	if necromancer == null: return null
	var best = null
	var best_score := -INF
	for target in choice.options:
		if not target is Vector2i: continue
		var score := _necromancer_placement_score(state, necromancer, target, necromancer.color)
		if score > best_score:
			best_score = score
			best = target
	return best


static func _best_quarterly_grant(state: ChessCoreState, choice: ChessCoreChoice):
	var recipient := state.piece_by_id(choice.target_piece_id)
	if recipient == null: return null
	var best = null
	var best_score := -INF
	for raw_option in choice.options:
		var option := StringName(raw_option)
		var score := _quarterly_grant_score(state, recipient, option)
		if score > best_score or (is_equal_approx(score, best_score) and (best == null or String(option) < String(best))):
			best_score = score
			best = option
	return best if best != null else (choice.options[0] if not choice.options.is_empty() else null)


static func _best_lingering_malice(state: ChessCoreState, choice: ChessCoreChoice):
	var wraith := state.piece_by_id(choice.piece_id)
	if wraith == null: return null
	var best = null
	var best_score := -INF
	for option in choice.options:
		if not option is Vector2i: continue
		var score := _lingering_malice_score(state, wraith, option)
		if score > best_score:
			best_score = score
			best = option
	return best


static func _lingering_malice_score(state: ChessCoreState, wraith: ChessCorePiece, target: Vector2i) -> float:
	if target == wraith.coordinate: return 0.0
	var occupant := state.occupant(target)
	var score := 0.0
	if occupant != null and occupant.color != wraith.color:
		var value := WraithPolicy.material_value(occupant.type_id, occupant.is_king())
		score += 40.0 if occupant.is_king() else (value * 10.0 if occupant.current_hp <= wraith.attack_power else value * 2.0)
		if occupant.current_hp > wraith.attack_power: return score
	var before := king_attackers(state, wraith.color).size()
	var projected := state.copy()
	var projected_wraith := projected.piece_by_id(wraith.piece_id)
	var projected_target := projected.occupant(target)
	if projected_target != null: projected.remove_piece(projected_target)
	projected.move_piece(projected_wraith, target)
	var after := king_attackers(projected, wraith.color).size()
	score += float(before - after) * 25.0
	if after > before: score -= float(after - before) * 35.0
	var center_distance := absf(float(target.x) - 3.5) + absf(float(target.y) - 3.5)
	return score + (7.0 - center_distance) * 0.1


static func _wraith_summon_score(state: ChessCoreState, wraith: ChessCorePiece, target: ChessCorePiece, perspective: String) -> float:
	if wraith == null or target == null: return -1000.0
	var score := WraithPolicy.damage_pressure(target.type_id, target.current_hp, target.is_king(), WraithPolicy.travel_rounds(wraith.coordinate, target.coordinate))
	var owned := WraithRules.entities_from_source(state, wraith.piece_id)
	if owned.size() >= WraithRules.MAX_ACTIVE_WRAITHS: score -= _wraith_entity_value(state, owned[0])
	return score if wraith.color == perspective else -score


static func _wraith_entity_value(state: ChessCoreState, entity: ChessCoreAutonomousEntity) -> float:
	var target := state.piece_by_id(entity.target_piece_id)
	if target == null: return 0.0
	var next_turn := int(entity.custom_state.get("next_move_turn", state.global_turn_number + WraithRules.MOVE_INTERVAL_ROUNDS))
	return WraithPolicy.entity_pressure(target.type_id, target.current_hp, target.is_king(), entity.coordinate, target.coordinate, maxi(0, next_turn - state.global_turn_number))


static func _wraith_evaluation_bonus(state: ChessCoreState, perspective: String) -> float:
	var result := 0.0
	for entity in state.autonomous_entities:
		if entity.type_id != &"wraith": continue
		var pressure := _wraith_entity_value(state, entity)
		result += pressure if entity.owner_color == perspective else -pressure
	return result


static func _quarterly_action_score(state: ChessCoreState, quarterly: ChessCorePiece, recipient: ChessCorePiece) -> float:
	if quarterly == null or recipient == null: return -INF
	var best := -INF
	for option in QuarterlyRules.GRANT_OPTIONS:
		if QuarterlyPolicy.is_redundant_values(recipient.type_id, recipient.granted_movement_types, option): continue
		best = maxf(best, _quarterly_grant_score(state, recipient, option))
	if best == -INF: return -INF
	return (QuarterlyPolicy.FREE_CYCLE_REWARD if state.global_turn_number % 4 == 0 else -QuarterlyPolicy.OFF_CYCLE_COST) + best


static func _quarterly_grant_score(state: ChessCoreState, recipient: ChessCorePiece, movement_type: StringName) -> float:
	if QuarterlyPolicy.is_redundant_values(recipient.type_id, recipient.granted_movement_types, movement_type): return -INF
	return QuarterlyPolicy.score_grant_analysis(recipient.type_id, movement_type, _quarterly_grant_targets(state, recipient, movement_type))


static func _quarterly_grant_targets(state: ChessCoreState, recipient: ChessCorePiece, movement_type: StringName) -> Array:
	var result := []
	var native_moves: Array = ClassicChessCore._legal_destinations(state, recipient)
	for destination in ClassicChessCore._moves_as(state, recipient, movement_type):
		if destination in native_moves: continue
		var target := state.occupant(destination)
		if target == null or target.color == recipient.color: continue
		result.append({
			"type_id": target.type_id,
			"is_king": target.is_king(),
			"protected": not _tactical_attackers(state, target.coordinate, target.color).is_empty(),
		})
	return result


static func _necromancer_placement_score(state: ChessCoreState, necromancer: ChessCorePiece, target: Vector2i, perspective: String) -> float:
	if target.x == (0 if necromancer.color == "white" else 7) or state.occupant(target) != null: return -100000.0
	var before_attackers := king_attackers(state, necromancer.color).size()
	var pawn := ChessCorePiece.new(); pawn.type_id = &"bone_pawn"; pawn.color = necromancer.color; pawn.coordinate = target; pawn.piece_id = "dupre_core_bone"
	var occupancy := state.occupancy.duplicate(); occupancy[target] = pawn
	var after_attackers := 0
	var own_king: ChessCorePiece
	for piece in state.pieces:
		if piece.color == necromancer.color and piece.is_king(): own_king = piece; break
	if own_king != null:
		for piece in state.pieces:
			if piece.color != necromancer.color and ClassicChessCore.geometrically_attacks_in_occupancy(piece, piece.coordinate, own_king.coordinate, occupancy): after_attackers += 1
	var score := 1.0 + float(before_attackers - after_attackers) * 25.0
	for piece in state.pieces:
		if piece.color != necromancer.color and ClassicChessCore.geometrically_attacks_in_occupancy(pawn, target, piece.coordinate, occupancy):
			score += 5.0 if piece.is_king() else _material_value(piece) * 0.6
	var enemy := _other_color(necromancer.color)
	var enemy_attacks := 0; var own_defenses := 0
	for piece in state.pieces:
		if ClassicChessCore.geometrically_attacks_in_occupancy(piece, piece.coordinate, target, occupancy):
			if piece.color == enemy: enemy_attacks += 1
			else: own_defenses += 1
	if enemy_attacks > 0 and own_defenses == 0: score -= 6.0
	# A ready adjacent Arakne can erase the summon immediately.
	for piece in state.pieces:
		if piece.color == enemy and piece.type_id == &"arakne_king" and maxi(absi(piece.coordinate.x - target.x), absi(piece.coordinate.y - target.y)) <= 1 and (state.active_ability_cooldowns_disabled or (piece.current_cooldown == 0 and not piece.cooldown_reset_pending)):
			score -= 6.0
	var advance := float(7 - target.x) if necromancer.color == "white" else float(target.x)
	score += advance * 0.08 + (3.5 - absf(float(target.y) - 3.5)) * 0.04
	return score if necromancer.color == perspective else -score


static func _summon_is_forcing(state: ChessCoreState, necromancer: ChessCorePiece, target: Vector2i) -> bool:
	if _necromancer_placement_score(state, necromancer, target, necromancer.color) <= -100000.0: return false
	var pawn := ChessCorePiece.new(); pawn.type_id = &"bone_pawn"; pawn.color = necromancer.color; pawn.coordinate = target
	var occupancy := state.occupancy.duplicate(); occupancy[target] = pawn
	if king_attackers(state, necromancer.color).size() > 0:
		var own_king: ChessCorePiece
		for piece in state.pieces:
			if piece.color == necromancer.color and piece.is_king(): own_king = piece; break
		var after := 0
		for piece in state.pieces:
			if piece.color != necromancer.color and ClassicChessCore.geometrically_attacks_in_occupancy(piece, piece.coordinate, own_king.coordinate, occupancy): after += 1
		if after < king_attackers(state, necromancer.color).size(): return true
	for piece in state.pieces:
		if piece.color != necromancer.color and (piece.is_king() or _material_value(piece) >= 5.0) and ClassicChessCore.geometrically_attacks_in_occupancy(pawn, target, piece.coordinate, occupancy): return true
	return false


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"


static func _tactical_attackers(state: ChessCoreState, target: Vector2i, color := "") -> Array[ChessCorePiece]:
	var profiling := state.performance_metrics != null and state.performance_metrics.detailed_analysis_enabled
	var started := Time.get_ticks_usec() if profiling else 0
	var result: Array[ChessCorePiece] = []
	for piece in state.pieces:
		if (color.is_empty() or piece.color == color) and ClassicChessCore.geometrically_attacks_in_occupancy(piece, piece.coordinate, target, state.occupancy):
			result.append(piece)
	if profiling:
		state.performance_metrics.record_tactical_attackers(Time.get_ticks_usec() - started, false)
	return result


static func _analysis_actions(state: ChessCoreState, color: String) -> Array[ChessCoreAction]:
	var profiling := state.performance_metrics != null and state.performance_metrics.detailed_analysis_enabled
	var started := Time.get_ticks_usec() if profiling else 0
	var result := ClassicChessCore.analysis_actions(state, color)
	if profiling:
		state.performance_metrics.record_analysis_actions(Time.get_ticks_usec() - started, result.size(), false)
	return result
