extends RefCounted
class_name DupreClassicCoreBackend

const MATERIAL_VALUES := {
	&"pawn": 1.0, &"knight": 3.0, &"bishop": 3.0,
	&"rook": 5.0, &"queen": 9.0,
}


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
		else:
			return ChessCoreStepResult.rejected(state, "Dupre does not support this pure-core choice.")
		result = ClassicChessCore.resolve_choice(result.state, option, false)
	result.resolved_reaction_colors.assign(reaction_colors)
	return result


static func ordered_replies(state: ChessCoreState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions := ClassicChessCore.legal_actions(state, state.current_turn)
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


static func evaluate_static(state: ChessCoreState, perspective: String, tactical_detail := true, generate_actions := true) -> Dictionary:
	if state.battle_over:
		return {"score": terminal_score(state, perspective), "own_actions": [], "enemy_actions": []}
	var enemy := _other_color(perspective)
	var score := 0.0
	for piece in state.pieces:
		var sign_value := 1.0 if piece.color == perspective else -1.0
		if piece.is_king():
			score += sign_value * float(piece.current_hp) * 50.0
		else:
			var value := _material_value(piece) * 10.0
			var hp_ratio := float(piece.current_hp) / float(maxi(1, piece.max_hp))
			value -= value * 0.3 * (1.0 - hp_ratio)
			score += sign_value * value
	var own_actions: Array[ChessCoreAction] = ClassicChessCore.analysis_actions(state, perspective) if generate_actions else []
	var enemy_actions: Array[ChessCoreAction] = ClassicChessCore.analysis_actions(state, enemy) if generate_actions else []
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
	return {"score": score, "own_actions": own_actions, "enemy_actions": enemy_actions}


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
			return ClassicChessCore.attackers(state, piece.coordinate, _other_color(color))
	return []


static func is_hanging(state: ChessCoreState, piece: ChessCorePiece) -> bool:
	return (
		not ClassicChessCore.attackers(state, piece.coordinate, _other_color(piece.color)).is_empty()
		and ClassicChessCore.attackers(state, piece.coordinate, piece.color).is_empty()
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
			if ClassicChessCore.directly_attacks_in_occupancy(attacker, action.target, piece.coordinate, projected): return true
	return false


static func _has_lethal_action(state: ChessCoreState, actions: Array[ChessCoreAction], defender_color: String) -> bool:
	var king: ChessCorePiece
	for piece in state.pieces:
		if piece.color == defender_color and piece.is_king(): king = piece; break
	if king == null: return true
	for action in actions:
		var attacker := state.piece_by_id(action.piece_id)
		if action.target == king.coordinate and attacker != null and attacker.attack_power >= king.current_hp: return true
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
			if piece.color != necromancer.color and ClassicChessCore.directly_attacks_in_occupancy(piece, piece.coordinate, own_king.coordinate, occupancy): after_attackers += 1
	var score := 1.0 + float(before_attackers - after_attackers) * 25.0
	for piece in state.pieces:
		if piece.color != necromancer.color and ClassicChessCore.directly_attacks_in_occupancy(pawn, target, piece.coordinate, occupancy):
			score += 5.0 if piece.is_king() else _material_value(piece) * 0.6
	var enemy := _other_color(necromancer.color)
	var enemy_attacks := 0; var own_defenses := 0
	for piece in state.pieces:
		if ClassicChessCore.directly_attacks_in_occupancy(piece, piece.coordinate, target, occupancy):
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
			if piece.color != necromancer.color and ClassicChessCore.directly_attacks_in_occupancy(piece, piece.coordinate, own_king.coordinate, occupancy): after += 1
		if after < king_attackers(state, necromancer.color).size(): return true
	for piece in state.pieces:
		if piece.color != necromancer.color and (piece.is_king() or _material_value(piece) >= 5.0) and ClassicChessCore.directly_attacks_in_occupancy(pawn, target, piece.coordinate, occupancy): return true
	return false


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"
