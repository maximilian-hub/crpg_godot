extends ChessAiBrain
class_name LeMayAiBrain

const KingAiRegistry = preload("res://scripts/ai/chess_king_ai_registry.gd")
const ActionCodec = preload("res://scripts/state/chess_action_codec.gd")
const DEFAULT_MAX_REPLY_LEAVES := 4096
const DEFAULT_THINK_BUDGET_MSEC := 5000
const DEFAULT_COMPUTE_SLICE_USEC := 3000
const MATERIAL_VALUES := {
	&"pawn": 1.0,
	&"bone_pawn": 1.0,
	&"knight": 3.0,
	&"bishop": 3.0,
	&"rook": 5.0,
	&"queen": 9.0,
}

enum CandidateStatus { COMPLETED, PRUNED, INCOMPLETE, INVALID }

# Mutable limits make timeout and exhaustive-reference behavior testable without
# changing the production defaults.
var max_reply_leaves := DEFAULT_MAX_REPLY_LEAVES
var think_budget_msec := DEFAULT_THINK_BUDGET_MSEC
var compute_slice_usec := DEFAULT_COMPUTE_SLICE_USEC
var alpha_beta_enabled := true
var last_profile: Dictionary = {}

var _search_started_usec := 0
var _slice_started_usec := 0
var _root_revision := 0


static func unsupported_king_ids(model: ChessBoardModel) -> Array[StringName]:
	var result: Array[StringName] = []
	for color in ["white", "black"]:
		var king := model.get_king(color)
		if king == null:
			continue
		var type_id := king.get_position_type_id()
		if not KingAiRegistry.supports(type_id) and type_id not in result:
			result.append(type_id)
	return result


func get_last_profile() -> Dictionary:
	return last_profile.duplicate(true)


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	_begin_profile(actions.size())
	if actions.is_empty() or not unsupported_king_ids(player.model).is_empty():
		_finish_profile()
		return null
	_root_revision = player.model.position_revision
	var root_position: ChessPosition = player.model.capture_position()
	var ordered_roots := await _ordered_root_actions(actions)
	var exact_candidates: Array[Dictionary] = []
	var best_exact_score := -INF

	for root_entry in ordered_roots:
		if _budget_exhausted():
			last_profile.incomplete_root_candidates += 1
			continue
		var candidate: Dictionary = await _search_root_candidate(
			root_position,
			root_entry.action,
			best_exact_score
		)
		var status: CandidateStatus = candidate.status
		match status:
			CandidateStatus.COMPLETED:
				last_profile.exact_root_candidates += 1
				exact_candidates.append(candidate)
				best_exact_score = maxf(best_exact_score, float(candidate.score))
			CandidateStatus.PRUNED:
				last_profile.pruned_root_candidates += 1
			CandidateStatus.INCOMPLETE:
				last_profile.incomplete_root_candidates += 1
			CandidateStatus.INVALID:
				last_profile.invalid_root_candidates += 1
		await _cooperate()
		if not _search_is_current():
			_finish_profile()
			return null

	var selected_action: ChessPrimaryAction
	var selected_score := 0.0
	if exact_candidates.is_empty():
		# A partial minimizing score is only an optimistic upper bound. It is never
		# eligible here. Falling back to the strongest stable root heuristic is less
		# informed, but mathematically honest and cannot reward a failed simulation.
		last_profile.fallback_used = true
		last_profile.selected_status = &"fallback"
		selected_action = ordered_roots[0].action
		selected_score = float(ordered_roots[0].heuristic)
	else:
		var best: Array[Dictionary] = []
		for candidate in exact_candidates:
			if is_equal_approx(float(candidate.score), best_exact_score):
				best.append(candidate)
		var selected: Dictionary = best[player.rng.randi_range(0, best.size() - 1)]
		selected_action = selected.action
		selected_score = selected.score
		last_profile.selected_status = &"exact"

	var plan := ChessAiPlan.new(selected_action)
	plan.brain_id = &"lemay"
	plan.score = selected_score
	plan.analyzed_leaf_count = last_profile.evaluated_reply_count
	_finish_profile()
	plan.search_profile = get_last_profile()
	var diagnostics: Array[Dictionary] = []
	for entry in ordered_roots.slice(0, mini(12, ordered_roots.size())):
		diagnostics.append({"action": ActionCodec.describe(entry.action), "score": entry.heuristic, "status": "root_heuristic"})
	plan.candidates = diagnostics
	return plan


func _search_root_candidate(root_position: ChessPosition, action: ChessPrimaryAction, alpha: float) -> Dictionary:
	var simulation := await _make_model(root_position)
	if simulation == null:
		return _candidate(action, CandidateStatus.INVALID)
	var accepted := await _execute_descriptor(simulation, _describe_action(action))
	await _cooperate()
	if not accepted or not simulation.is_settled():
		_free_model(simulation)
		return _candidate(action, CandidateStatus.INVALID)
	if simulation.battle_over:
		var terminal_score := _evaluate_terminal(simulation)
		_free_model(simulation)
		return _candidate(action, CandidateStatus.COMPLETED, terminal_score)

	var legal_started := Time.get_ticks_usec()
	var reply_actions := simulation.get_legal_primary_actions(simulation.current_turn)
	_record_legal_generation(legal_started)
	var replies := _ordered_reply_descriptors(simulation, reply_actions)
	last_profile.total_available_replies += replies.size()
	if replies.is_empty():
		var no_reply_score := await _evaluate_model(simulation, {simulation.current_turn: reply_actions})
		_free_model(simulation)
		return _candidate(action, CandidateStatus.COMPLETED, no_reply_score)

	var capture_started := Time.get_ticks_usec()
	var child_position := simulation.capture_position()
	_record_phase(&"position_capture_usec", capture_started)
	_free_model(simulation)
	await _cooperate()

	var worst_score := INF
	for reply in replies:
		if _budget_exhausted():
			return _candidate(action, CandidateStatus.INCOMPLETE, worst_score)
		var leaf := await _make_model(child_position)
		if leaf == null:
			return _candidate(action, CandidateStatus.INVALID)
		var reply_accepted := await _execute_descriptor(leaf, reply)
		await _cooperate()
		if not reply_accepted or not leaf.is_settled():
			_free_model(leaf)
			return _candidate(action, CandidateStatus.INVALID)
		var score := await _evaluate_model(leaf)
		_free_model(leaf)
		last_profile.evaluated_reply_count += 1
		worst_score = minf(worst_score, score)
		if alpha_beta_enabled and alpha > -INF and worst_score <= alpha:
			last_profile.alpha_beta_cutoffs += 1
			return _candidate(action, CandidateStatus.PRUNED, worst_score)
		await _cooperate()
		if not _search_is_current():
			return _candidate(action, CandidateStatus.INCOMPLETE, worst_score)
	return _candidate(action, CandidateStatus.COMPLETED, worst_score)


func _candidate(action: ChessPrimaryAction, status: CandidateStatus, score := 0.0) -> Dictionary:
	return {"action": action, "status": status, "score": score}


func _ordered_root_actions(actions: Array[ChessPrimaryAction]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(actions.size()):
		result.append({
			"action": actions[index],
			"heuristic": player._score_primary_action(actions[index]),
			"index": index,
		})
		await _cooperate()
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.heuristic), float(b.heuristic)):
			return float(a.heuristic) > float(b.heuristic)
		return int(a.index) < int(b.index)
	)
	return result


func _ordered_reply_descriptors(model: ChessBoardModel, actions: Array[ChessPrimaryAction]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(actions.size()):
		var descriptor := _describe_action(actions[index])
		descriptor["priority"] = _reply_priority(model, actions[index])
		descriptor["index"] = index
		result.append(descriptor)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.priority), float(b.priority)):
			return float(a.priority) > float(b.priority)
		return int(a.index) < int(b.index)
	)
	return result


func _describe_action(action: ChessPrimaryAction) -> Dictionary:
	return {
		"kind": action.kind,
		"piece_id": action.piece.piece_id,
		"target": action.target,
		"path": action.path.duplicate(),
	}


func _execute_descriptor(simulation: ChessBoardModel, descriptor: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	var piece := simulation.find_piece_by_id(descriptor.piece_id)
	var accepted := false
	if piece != null:
		if descriptor.kind == ChessPrimaryAction.Kind.MOVE:
			var path: Array[Vector2i] = []
			path.assign(descriptor.path)
			accepted = await simulation.submit_move_path(piece, path) if path.size() > 1 else await simulation.submit_move(piece, descriptor.target)
		elif piece is KingPiece:
			accepted = await simulation.submit_active_ability(piece as KingPiece, descriptor.target)
	_record_phase(&"action_execution_usec", started)
	return accepted


func _reply_priority(model: ChessBoardModel, action: ChessPrimaryAction) -> float:
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target != null and target.color != action.piece.color:
		if target.is_king:
			return 10000.0
		return 1000.0 + float(MATERIAL_VALUES.get(target.get_position_type_id(), 1.0))
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return 500.0
	return 0.0


func _evaluate_model(model: ChessBoardModel, cached_actions: Dictionary = {}) -> float:
	var started := Time.get_ticks_usec()
	var yielded_usec := 0
	if model.battle_over:
		var terminal := _evaluate_terminal(model)
		_record_evaluation(started)
		return terminal
	var enemy := "black" if player.controlled_color == "white" else "white"
	var score := 0.0
	for row in model.board:
		for piece in row:
			if piece == null:
				continue
			var sign_value := 1.0 if piece.color == player.controlled_color else -1.0
			if piece.is_king:
				score += sign_value * float(piece.current_hp) * 50.0
			else:
				score += sign_value * float(MATERIAL_VALUES.get(piece.get_position_type_id(), 1.0)) * 10.0
	yielded_usec += await _cooperate()

	var own_actions: Array = cached_actions.get(player.controlled_color, [])
	if not cached_actions.has(player.controlled_color):
		own_actions = _collect_actions_for(model, player.controlled_color)
		yielded_usec += await _cooperate()
	var enemy_actions: Array = cached_actions.get(enemy, [])
	if not cached_actions.has(enemy):
		enemy_actions = _collect_actions_for(model, enemy)
		yielded_usec += await _cooperate()
	score += float(own_actions.size() - enemy_actions.size()) * 0.1
	if _has_lethal_action(model, enemy_actions, player.controlled_color):
		score -= 500.0
	if _has_lethal_action(model, own_actions, enemy):
		score += 500.0
	_record_evaluation(started, yielded_usec)
	return score


func _evaluate_terminal(model: ChessBoardModel) -> float:
	if model.battle_result == player.controlled_color:
		return 1000000.0
	if model.battle_result == "draw":
		return 0.0
	return -1000000.0


func _collect_actions_for(model: ChessBoardModel, color: String) -> Array:
	var started := Time.get_ticks_usec()
	var original_turn := model.current_turn
	model.current_turn = color
	var actions := model._collect_legal_primary_actions(color)
	model.current_turn = original_turn
	_record_legal_generation(started)
	return actions


func _has_lethal_action(model: ChessBoardModel, actions: Array, defender_color: String) -> bool:
	var king := model.get_king(defender_color)
	if king == null:
		return true
	for action in actions:
		if action.target != king.coordinate:
			continue
		if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece.attack_power >= king.current_hp:
			return true
		var layer: Variant = KingAiRegistry.layer_for(action.piece.get_position_type_id()) if action.piece is KingPiece else null
		if layer != null and layer.active_ability_is_lethal(action, king):
			return true
	return false


func _make_model(position: ChessPosition) -> ChessBoardModel:
	var started := Time.get_ticks_usec()
	var simulation := ChessBoardModel.new()
	simulation.diagnostic_logging_enabled = false
	player.add_child(simulation)
	last_profile.model_construction_count += 1
	_record_phase(&"model_construction_usec", started)
	simulation.forced_pass_delay_seconds = 0.0
	started = Time.get_ticks_usec()
	var loaded := simulation.load_position(position.copy())
	last_profile.position_load_count += 1
	_record_phase(&"position_load_usec", started)
	await _cooperate()
	if not loaded:
		_free_model(simulation)
		return null
	return simulation


func _free_model(simulation: ChessBoardModel) -> void:
	var started := Time.get_ticks_usec()
	simulation.free()
	last_profile.model_destruction_count += 1
	_record_phase(&"model_destruction_usec", started)


func _begin_profile(root_action_count: int) -> void:
	_search_started_usec = Time.get_ticks_usec()
	_slice_started_usec = _search_started_usec
	last_profile = {
		"root_action_count": root_action_count,
		"evaluated_reply_count": 0,
		"total_available_replies": 0,
		"model_construction_count": 0,
		"model_destruction_count": 0,
		"position_load_count": 0,
		"legal_action_generation_count": 0,
		"evaluation_count": 0,
		"exact_root_candidates": 0,
		"pruned_root_candidates": 0,
		"incomplete_root_candidates": 0,
		"invalid_root_candidates": 0,
		"alpha_beta_cutoffs": 0,
		"yield_count": 0,
		"fallback_used": false,
		"selected_status": &"none",
		"thinking_usec": 0,
		"model_construction_usec": 0,
		"model_destruction_usec": 0,
		"position_load_usec": 0,
		"position_capture_usec": 0,
		"action_execution_usec": 0,
		"legal_action_generation_usec": 0,
		"evaluation_usec": 0,
		"average_evaluation_usec": 0.0,
		"maximum_evaluation_usec": 0,
		"maximum_model_construction_usec": 0,
		"maximum_model_destruction_usec": 0,
		"maximum_position_load_usec": 0,
		"maximum_position_capture_usec": 0,
		"maximum_action_execution_usec": 0,
		"maximum_legal_action_generation_usec": 0,
		"maximum_uninterrupted_usec": 0,
	}


func _finish_profile() -> void:
	_record_slice()
	last_profile.thinking_usec = Time.get_ticks_usec() - _search_started_usec
	if last_profile.evaluation_count > 0:
		last_profile.average_evaluation_usec = float(last_profile.evaluation_usec) / float(last_profile.evaluation_count)


func _record_phase(key: StringName, started_usec: int) -> void:
	var elapsed := Time.get_ticks_usec() - started_usec
	last_profile[key] = int(last_profile.get(key, 0)) + elapsed
	var maximum_key := StringName("maximum_" + String(key))
	if last_profile.has(maximum_key):
		last_profile[maximum_key] = maxi(int(last_profile[maximum_key]), elapsed)
	_record_slice()


func _record_legal_generation(started_usec: int) -> void:
	last_profile.legal_action_generation_count += 1
	_record_phase(&"legal_action_generation_usec", started_usec)


func _record_evaluation(started_usec: int, excluded_usec := 0) -> void:
	var elapsed := Time.get_ticks_usec() - started_usec - excluded_usec
	last_profile.evaluation_count += 1
	last_profile.evaluation_usec += elapsed
	last_profile.maximum_evaluation_usec = maxi(last_profile.maximum_evaluation_usec, elapsed)
	_record_slice()


func _record_slice() -> void:
	last_profile.maximum_uninterrupted_usec = maxi(
		last_profile.maximum_uninterrupted_usec,
		Time.get_ticks_usec() - _slice_started_usec
	)


func _cooperate() -> int:
	_record_slice()
	if Time.get_ticks_usec() - _slice_started_usec < compute_slice_usec:
		return 0
	last_profile.yield_count += 1
	var wait_started := Time.get_ticks_usec()
	await player.get_tree().process_frame
	_slice_started_usec = Time.get_ticks_usec()
	return _slice_started_usec - wait_started


func _budget_exhausted() -> bool:
	return (
		last_profile.evaluated_reply_count >= max_reply_leaves
		or Time.get_ticks_usec() - _search_started_usec >= think_budget_msec * 1000
	)


func _search_is_current() -> bool:
	return (
		is_instance_valid(player)
		and player.is_enabled
		and is_instance_valid(player.model)
		and not player.model.battle_over
		and player.model.position_revision == _root_revision
		and player.model.current_turn == player.controlled_color
	)
