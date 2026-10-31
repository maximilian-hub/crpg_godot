extends LeMayAiBrain
class_name DupreAiBrain

const DuprePolicy = preload("res://scripts/ai/dupre_move_policy.gd")
const TacticalMap = preload("res://scripts/ai/dupre_tactical_map.gd")
const OpeningBook = preload("res://scripts/ai/dupre_opening_book.gd")
const OpeningSession = preload("res://scripts/ai/dupre_opening_session.gd")
const DEFAULT_CANDIDATE_LIMIT := 6
const DEFAULT_MAX_BOOK_MOVES := 7
const TACTICAL_SAFETY_MARGIN := 5.0
const FORCING_ABILITY_CAP := 3
const DIRECT_KING_ATTACK_CAP := 3
const MAX_OBLIGATION_RESPONSES := 4
const SEVERE_MATERIAL_LOSS := 3.0

enum ScreenStatus { READY, EXACT, INCOMPLETE, INVALID, PRUNED }
enum ExecutionStatus { COMPLETED, INCOMPLETE, INVALID }

var candidate_limit := DEFAULT_CANDIDATE_LIMIT
var max_book_moves := DEFAULT_MAX_BOOK_MOVES
var quiescence_enabled := true
var previous_own_actions: Dictionary = {}
var opening_session = OpeningSession.new()
var _pending_book_action: Dictionary = {}
var _tactical_map: DupreTacticalMap
var _last_evaluation_complete := true
var _evaluation_context_forcing := false


static func unsupported_king_ids(model: ChessBoardModel) -> Array[StringName]:
	var result: Array[StringName] = []
	for color in ["white", "black"]:
		var king := model.get_king(color)
		if king == null:
			continue
		var type_id := king.get_position_type_id()
		if not KingAiRegistry.supports_dupre(type_id) and type_id not in result:
			result.append(type_id)
	return result


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	_begin_profile(actions.size())
	_begin_book_profile()
	last_profile["king_support"] = _king_support_profile(player.model)
	_pending_book_action.clear()
	if actions.is_empty() or not unsupported_king_ids(player.model).is_empty():
		_finish_profile()
		return null
	_root_revision = player.model.position_revision
	_ensure_tactical_map()
	_populate_tactical_profile()
	_ensure_opening_session()
	var book_metrics := OpeningBook.load_metrics()
	last_profile["opening_book_load_usec"] = book_metrics.load_usec
	last_profile["opening_book_data_bytes"] = book_metrics.data_bytes
	last_profile["opening_book_family_count"] = book_metrics.family_count
	var book_plan = _try_opening_book(actions)
	if book_plan != null:
		return book_plan
	var policy := DuprePolicy.new(player, previous_own_actions, _tactical_map)
	var ranked := await _rank_actions(actions, policy)
	if ranked.is_empty():
		_populate_policy_profile(policy)
		_finish_profile()
		return null
	var candidates := _select_candidates(ranked, policy)
	_populate_policy_profile(policy)
	last_profile["policy_candidate_count"] = candidates.size()
	last_profile["unverified_selection"] = false
	var root_position: ChessPosition = player.model.capture_position()
	var records: Array[Dictionary] = []
	for entry in candidates:
		records.append(_new_candidate_record(entry))
	# Preparation is deliberately breadth-first: every selected action gets a
	# fallback record before any one candidate is allowed to spend the budget on
	# opponent-reply evaluation.
	for record in records:
		if _budget_exhausted(): break
		var screen_started := Time.get_ticks_usec()
		await _prepare_candidate(root_position, record)
		last_profile.screening_usec += Time.get_ticks_usec() - screen_started
		if bool(record.get("terminal", false)) and float(record.get("score", 0.0)) >= 1000000.0:
			last_profile.terminal_win_early_stop = true
			break
		await _cooperate()
	# First screen one forcing reply per candidate per round.
	while not _budget_exhausted():
		var advanced := false
		for record in records:
			if _budget_exhausted(): break
			var screen_started := Time.get_ticks_usec()
			if await _advance_candidate_reply(record, true, -INF): advanced = true
			last_profile.screening_usec += Time.get_ticks_usec() - screen_started
		if not advanced: break
		last_profile.breadth_screen_rounds += 1
	# Then complete remaining replies with the same round-robin fairness.
	while not _budget_exhausted():
		var advanced := false
		var completed_scores: Array[float] = []
		for candidate in records:
			if candidate.screen_status == ScreenStatus.EXACT: completed_scores.append(float(candidate.score))
		var alpha: float = float(completed_scores.max()) - TACTICAL_SAFETY_MARGIN if not completed_scores.is_empty() else -INF
		for record in records:
			if _budget_exhausted(): break
			var verification_started := Time.get_ticks_usec()
			if await _advance_candidate_reply(record, false, alpha): advanced = true
			last_profile.exhaustive_verification_usec += Time.get_ticks_usec() - verification_started
		if not advanced: break
		last_profile.breadth_completion_rounds += 1

	var exact: Array[Dictionary] = records.filter(func(record: Dictionary): return record.screen_status == ScreenStatus.EXACT)
	var best_tactical := -INF
	for record in records:
		match int(record.screen_status):
			ScreenStatus.EXACT:
				last_profile.exact_root_candidates += 1
				best_tactical = maxf(best_tactical, float(record.score))
				_record_first_completion()
			ScreenStatus.INVALID: last_profile.invalid_root_candidates += 1
			ScreenStatus.PRUNED: pass
			_: last_profile.incomplete_root_candidates += 1

	var selected_action: ChessPrimaryAction
	var selected_score := 0.0
	if exact.is_empty():
		var fallback_record := _best_screened_fallback(records)
		selected_action = fallback_record.action if not fallback_record.is_empty() else (candidates[0].action if not candidates.is_empty() else ranked[0].action)
		selected_score = float(fallback_record.get("policy", 0.0)) if not fallback_record.is_empty() else (candidates[0].policy if not candidates.is_empty() else ranked[0].policy)
		last_profile.fallback_used = true
		last_profile.unverified_selection = true
		last_profile.selected_status = &"breadth_fallback"
		last_profile.timeout_fallback_source = fallback_record.get("phase", &"not_prepared") if not fallback_record.is_empty() else &"ranked"
		last_profile.selected_candidate_reason = fallback_record.get("candidate_reason", &"policy") if not fallback_record.is_empty() else (candidates[0].get("candidate_reason", &"policy") if not candidates.is_empty() else &"policy")
	else:
		var safe: Array[Dictionary] = exact.filter(func(candidate: Dictionary): return float(candidate.score) >= best_tactical - TACTICAL_SAFETY_MARGIN)
		safe.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.policy) > float(b.policy))
		selected_action = safe[0].action
		selected_score = safe[0].score
		last_profile.selected_policy_reactions = int(safe[0].get("policy_reactions", 0))
		last_profile.selected_status = &"verified_policy_reactions" if last_profile.selected_policy_reactions > 0 else &"verified"
		last_profile.conditional_verification = last_profile.selected_policy_reactions > 0
		last_profile.selected_candidate_reason = safe[0].get("candidate_reason", &"policy")

	var plan := ChessAiPlan.new(selected_action)
	plan.brain_id = &"dupre"
	plan.score = selected_score
	plan.analyzed_leaf_count = last_profile.evaluated_reply_count
	_finish_profile()
	plan.search_profile = get_last_profile()
	var diagnostics: Array[Dictionary] = []
	for record in records:
		if diagnostics.size() >= 12: break
		diagnostics.append({
			"action": ActionCodec.describe(record.action),
			"policy_score": record.policy,
			"search_score": record.score,
			"status": String(record.get("phase", &"not_prepared")),
			"reason": String(record.get("candidate_reason", &"policy")),
			"replies_evaluated": record.reply_scores.size(),
			"replies_available": record.replies.size(),
			"selected": record.action == selected_action,
		})
	if not diagnostics.any(func(candidate: Dictionary): return bool(candidate.get("selected", false))):
		for record in records:
			if record.action != selected_action: continue
			if diagnostics.size() >= 12: diagnostics.pop_back()
			diagnostics.append({
				"action": ActionCodec.describe(record.action), "policy_score": record.policy,
				"search_score": record.score, "status": String(record.get("phase", &"not_prepared")),
				"reason": String(record.get("candidate_reason", &"policy")),
				"replies_evaluated": record.reply_scores.size(), "replies_available": record.replies.size(), "selected": true,
			})
			break
	if diagnostics.is_empty():
		for entry in ranked.slice(0, mini(12, ranked.size())):
			diagnostics.append({"action": ActionCodec.describe(entry.action), "policy_score": entry.policy, "status": "not_searched", "reason": "policy"})
	plan.candidates = diagnostics
	return plan


func _new_candidate_record(entry: Dictionary) -> Dictionary:
	return {
		"action": entry.action,
		"policy": entry.policy,
		"candidate_reason": entry.get("candidate_reason", &"policy"),
		"screen_status": ScreenStatus.INCOMPLETE,
		"phase": &"not_prepared",
		"screen_bound": INF,
		"score": 0.0,
		"replies": [],
		"reply_scores": {},
		"policy_reactions": 0,
		"terminal": false,
		"forcing_cursor": 0,
		"completion_cursor": 0,
		"worst": INF,
	}


func _prepare_candidate(root_position: ChessPosition, record: Dictionary) -> void:
	var simulation := await _make_model(root_position)
	if simulation == null:
		record.screen_status = ScreenStatus.INVALID
		record.phase = &"invalid"
		return
	var execution := await _execute_dupre_descriptor(simulation, _describe_action(record.action))
	record.policy_reactions = int(execution.policy_reactions)
	await _cooperate()
	if execution.status != ExecutionStatus.COMPLETED:
		record.screen_status = ScreenStatus.INCOMPLETE if execution.status == ExecutionStatus.INCOMPLETE else ScreenStatus.INVALID
		record.phase = &"incomplete" if execution.status == ExecutionStatus.INCOMPLETE else &"invalid"
		_free_model(simulation)
		return
	last_profile.prepared_root_candidates += 1
	if simulation.battle_over:
		record.screen_status = ScreenStatus.EXACT
		record.score = _evaluate_terminal(simulation)
		record.screen_bound = record.score
		record.terminal = true
		record.phase = &"complete"
		_free_model(simulation)
		return
	var legal_started := Time.get_ticks_usec()
	var reply_actions := simulation.get_legal_primary_actions(simulation.current_turn)
	_record_legal_generation(legal_started)
	var replies := _ordered_screen_replies(simulation, reply_actions)
	last_profile.total_available_replies += replies.size()
	if replies.is_empty():
		record.screen_status = ScreenStatus.EXACT
		record.score = await _evaluate_model(simulation, {simulation.current_turn: reply_actions})
		record.screen_bound = record.score
		record.phase = &"complete"
		_free_model(simulation)
		return
	var capture_started := Time.get_ticks_usec()
	record["child_position"] = simulation.capture_position()
	_record_phase(&"position_capture_usec", capture_started)
	_free_model(simulation)
	record.replies = replies
	record.screen_status = ScreenStatus.READY
	record.phase = &"prepared"


func _advance_candidate_reply(record: Dictionary, forcing_only: bool, alpha: float) -> bool:
	if record.screen_status != ScreenStatus.READY: return false
	var cursor_key := "forcing_cursor" if forcing_only else "completion_cursor"
	var cursor := int(record[cursor_key])
	while cursor < record.replies.size():
		var reply: Dictionary = record.replies[cursor]
		cursor += 1
		record[cursor_key] = cursor
		var key := _reply_cache_key(reply)
		if forcing_only and not bool(reply.forcing): continue
		if not forcing_only and record.reply_scores.has(key):
			last_profile.reused_screened_reply_count += 1
			continue
		var evaluated := await _evaluate_record_reply(record, reply)
		if not evaluated.valid:
			record.screen_status = ScreenStatus.INVALID
			record.phase = &"invalid"
			return true
		if not evaluated.complete:
			record.screen_status = ScreenStatus.INCOMPLETE
			record.phase = &"incomplete"
			return true
		record.worst = minf(float(record.worst), float(evaluated.score))
		record.screen_bound = record.worst
		record.phase = &"screening"
		if forcing_only:
			last_profile.screened_reply_count += 1
		else:
			last_profile.exhaustive_quiet_reply_count += 1
			if alpha_beta_enabled and alpha > -INF and float(record.worst) <= alpha:
				record.phase = &"pruned"
				record.screen_status = ScreenStatus.PRUNED
				last_profile.pruned_root_candidates += 1
				last_profile.alpha_beta_cutoffs += 1
				last_profile.screen_pruned_candidates += 1
		await _cooperate()
		return true
	if not forcing_only:
		record.screen_status = ScreenStatus.EXACT
		record.score = float(record.worst)
		record.phase = &"complete"
	return false


func _evaluate_record_reply(record: Dictionary, reply: Dictionary) -> Dictionary:
	var leaf := await _make_model(record.child_position)
	if leaf == null:
		return {"valid": false}
	var execution := await _execute_dupre_descriptor(leaf, reply)
	await _cooperate()
	if execution.status != ExecutionStatus.COMPLETED:
		_free_model(leaf)
		return {"valid": execution.status != ExecutionStatus.INVALID, "complete": false}
	record.policy_reactions = int(record.get("policy_reactions", 0)) + int(execution.policy_reactions)
	_evaluation_context_forcing = bool(reply.get("forcing", false))
	var score := await _evaluate_model(leaf)
	_evaluation_context_forcing = false
	var complete := _last_evaluation_complete
	_free_model(leaf)
	last_profile.evaluated_reply_count += 1
	record.reply_scores[_reply_cache_key(reply)] = score
	return {"valid": true, "complete": complete, "score": score}


func _best_screened_fallback(records: Array[Dictionary]) -> Dictionary:
	var eligible: Array[Dictionary] = records.filter(func(record: Dictionary): return record.screen_status not in [ScreenStatus.INVALID, ScreenStatus.PRUNED])
	if eligible.is_empty():
		return {}
	# Partial minimizing scores are optimistic upper bounds. They can explain why
	# verification stopped, but must never outrank another fallback as if exact.
	eligible.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_priority := _candidate_reason_priority(a.get("candidate_reason", &"policy"))
		var b_priority := _candidate_reason_priority(b.get("candidate_reason", &"policy"))
		if a_priority != b_priority: return a_priority > b_priority
		return float(a.policy) > float(b.policy)
	)
	return eligible[0]


func _candidate_reason_priority(reason: StringName) -> int:
	match reason:
		&"immediate_win": return 6
		&"king_safety": return 5
		&"king_attack": return 4
		&"material_obligation": return 3
		&"capture_king_attacker": return 3
		&"king_ability": return 2
		&"favorable_capture": return 2
		&"major_piece_defense": return 1
	return 0


func _ordered_screen_replies(model: ChessBoardModel, actions: Array[ChessPrimaryAction]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(actions.size()):
		var action := actions[index]
		var descriptor := _describe_action(action)
		var reply_class := _reply_class(model, action)
		descriptor["reply_class"] = reply_class
		descriptor["forcing"] = reply_class > 0
		if reply_class > 0:
			last_profile.forcing_reply_count += 1
		else:
			last_profile.quiet_reply_count += 1
		descriptor["priority"] = float(reply_class * 10000) + _reply_priority(model, action)
		descriptor["index"] = index
		result.append(descriptor)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.priority), float(b.priority)):
			return float(a.priority) > float(b.priority)
		return int(a.index) < int(b.index)
	)
	return result


func _reply_class(model: ChessBoardModel, action: ChessPrimaryAction) -> int:
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target != null and target.color != action.piece.color:
		if target.is_king and _action_damage(action) >= target.current_hp:
			return 4
		if target.is_king:
			return 3
		return 2
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return 3 if _layer_action_is_forcing(model, action, action.piece.color) else 2
	if _directly_threatens_major(model, action):
		return 1
	return 0


func _directly_threatens_major(model: ChessBoardModel, action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return false
	var occupancy := {}
	for row in model.board:
		for piece in row:
			if piece != null: occupancy[piece.coordinate] = piece
	var origin := action.piece.coordinate
	var defender: ModelPiece = model.board[action.target.x][action.target.y]
	if defender != null and defender.color != action.piece.color and defender.current_hp > action.piece.attack_power:
		return false
	occupancy.erase(origin)
	occupancy.erase(action.target)
	occupancy[action.target] = action.piece
	var position := ChessAttackPosition.from_occupancy(Vector2i(model.board.size(), model.board[0].size()), occupancy)
	for coordinate in occupancy:
		var piece = occupancy[coordinate]
		if piece is ModelPiece and piece.color != action.piece.color and not piece.is_king and _material_value(piece) >= 5.0:
			if action.piece.can_directly_attack_square(action.target, coordinate, position):
				return true
	return false


func _action_damage(action: ChessPrimaryAction) -> int:
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		return action.piece.attack_power
	if action.piece is ArakneKing:
		return ArakneKing.SPIKE_BURST_DAMAGE
	if action.piece is MinotaurKing:
		return 2
	return 0


func _reply_cache_key(reply: Dictionary) -> String:
	return "%s|%s|%s|%s" % [reply.kind, reply.piece_id, reply.target, reply.path]


func _material_value(piece: ModelPiece) -> float:
	return float(MATERIAL_VALUES.get(piece.get_position_type_id(), 1.0))


func _evaluate_model(model: ChessBoardModel, cached_actions: Dictionary = {}) -> float:
	_last_evaluation_complete = true
	var static_result := await _evaluate_dupre_static(model, cached_actions, _evaluation_context_forcing)
	if not quiescence_enabled or model.battle_over or model.current_turn != player.controlled_color:
		return static_result.score
	var forcing: Array[ChessPrimaryAction] = []
	for action in static_result.own_actions:
		if _reply_class(model, action) >= 2:
			forcing.append(action)
	var unstable := not forcing.is_empty() or (_evaluation_context_forcing and _has_hanging_major(static_result.tactical_map))
	if not unstable:
		return static_result.score
	var best := float(static_result.score)
	var position: ChessPosition = model.capture_position()
	for action in forcing:
		if _dupre_budget_exhausted():
			_last_evaluation_complete = false
			last_profile.quiescence_incomplete_count = int(last_profile.get("quiescence_incomplete_count", 0)) + 1
			return best
		var continuation := await _make_model(position)
		if continuation == null:
			_last_evaluation_complete = false
			last_profile.quiescence_incomplete_count = int(last_profile.get("quiescence_incomplete_count", 0)) + 1
			return best
		var execution := await _execute_dupre_descriptor(continuation, _describe_action(action))
		await _cooperate()
		if execution.status != ExecutionStatus.COMPLETED:
			_free_model(continuation)
			_last_evaluation_complete = false
			last_profile.quiescence_incomplete_count = int(last_profile.get("quiescence_incomplete_count", 0)) + 1
			return best
		var result := await _evaluate_dupre_static(continuation, {}, true)
		best = maxf(best, float(result.score))
		last_profile.quiescence_node_count = int(last_profile.get("quiescence_node_count", 0)) + 1
		_free_model(continuation)
		await _cooperate()
	return best


func _evaluate_dupre_static(model: ChessBoardModel, cached_actions: Dictionary = {}, tactical_detail := true) -> Dictionary:
	var started := Time.get_ticks_usec()
	var yielded_usec := 0
	if model.battle_over:
		var terminal := _evaluate_terminal(model)
		_record_evaluation(started)
		return {"score": terminal, "own_actions": [], "enemy_actions": [], "tactical_map": TacticalMap.from_model(model)}
	var enemy := model.get_other_color(player.controlled_color)
	var score := 0.0
	for row in model.board:
		for piece in row:
			if piece == null:
				continue
			var sign_value := 1.0 if piece.color == player.controlled_color else -1.0
			if piece.is_king:
				score += sign_value * float(piece.current_hp) * 50.0
			else:
				var value := _material_value(piece) * 10.0
				var hp_ratio := float(piece.current_hp) / float(maxi(1, piece.max_hp))
				value -= value * 0.3 * (1.0 - hp_ratio)
				score += sign_value * value
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
	var tactical := TacticalMap.from_model(model)
	if tactical_detail:
		for coordinate in tactical.occupancy:
			var piece = tactical.occupancy[coordinate]
			# Minor pieces are already valued by material and by the actual opponent
			# replies. Reserve the horizon penalty for majors to keep leaf evaluation
			# cheap enough for the authoritative simulator.
			if not piece is ModelPiece or piece.is_king or _material_value(piece) < 5.0:
				continue
			if tactical.is_hanging(piece):
				var penalty := _material_value(piece) * 4.0
				score += -penalty if piece.color == player.controlled_color else penalty
		score -= float(tactical.king_attackers(player.controlled_color).size()) * 25.0
		score += float(tactical.king_attackers(enemy).size()) * 25.0
	if _has_lethal_action(model, enemy_actions, player.controlled_color): score -= 500.0
	if _has_lethal_action(model, own_actions, enemy): score += 500.0
	var evaluated_layers := {}
	for color in [player.controlled_color, enemy]:
		var king: ModelPiece = model.get_king(color)
		if king != null and not evaluated_layers.has(king.get_position_type_id()):
			var layer = KingAiRegistry.layer_for(king.get_position_type_id())
			if layer != null:
				evaluated_layers[king.get_position_type_id()] = true
				score += float(layer.evaluation_bonus(model, player.controlled_color))
	_record_evaluation(started, yielded_usec)
	return {"score": score, "own_actions": own_actions, "enemy_actions": enemy_actions, "tactical_map": tactical}


func _has_hanging_major(tactical: DupreTacticalMap) -> bool:
	for coordinate in tactical.occupancy:
		var piece = tactical.occupancy[coordinate]
		if piece is ModelPiece and not piece.is_king and _material_value(piece) >= 5.0 and tactical.is_hanging(piece):
			return true
	return false


func _dupre_budget_exhausted() -> bool:
	return _budget_exhausted() or int(last_profile.get("quiescence_node_count", 0)) + int(last_profile.get("evaluated_reply_count", 0)) >= max_reply_leaves


func choose_reaction_target(model: ChessBoardModel, calling_piece: ModelPiece, action_type: String, event_data, targets: Array):
	if targets.is_empty():
		return null
	var layer = KingAiRegistry.layer_for(calling_piece.get_position_type_id())
	if layer == null:
		return null
	var tactical := TacticalMap.from_model(model)
	var best_target = null
	var best_score := -INF
	for target in targets:
		if not target is Vector2i:
			continue
		var score := float(layer.reaction_target_score(model, calling_piece, action_type, event_data, target, calling_piece.color, tactical))
		if score > best_score:
			best_score = score
			best_target = target
	return best_target


func _execute_dupre_descriptor(simulation: ChessBoardModel, descriptor: Dictionary) -> Dictionary:
	var accepted := await super._execute_descriptor(simulation, descriptor)
	if not accepted:
		return {"status": ExecutionStatus.INVALID, "policy_reactions": 0}
	var reaction_count := 0
	while simulation.has_pending_reaction():
		if _dupre_budget_exhausted():
			return {"status": ExecutionStatus.INCOMPLETE, "policy_reactions": reaction_count}
		var pending := simulation.get_pending_reaction()
		var calling_piece: ModelPiece = pending.get("calling_piece")
		var targets: Array = pending.get("targets", [])
		if not is_instance_valid(calling_piece) or targets.is_empty():
			return {"status": ExecutionStatus.INVALID, "policy_reactions": reaction_count}
		var target = choose_reaction_target(simulation, calling_piece, String(pending.get("action_type", "")), pending.get("event_data"), targets)
		if not target is Vector2i or target not in targets:
			return {"status": ExecutionStatus.INVALID, "policy_reactions": reaction_count}
		if not await simulation.submit_reaction_selection(target):
			return {"status": ExecutionStatus.INVALID, "policy_reactions": reaction_count}
		reaction_count += 1
		last_profile.policy_reactions_resolved += 1
		if calling_piece.color == player.controlled_color:
			last_profile.own_policy_reactions_resolved += 1
		else:
			last_profile.opponent_policy_reactions_resolved += 1
		await _cooperate()
	if not simulation.is_settled():
		return {"status": ExecutionStatus.INVALID, "policy_reactions": reaction_count}
	return {"status": ExecutionStatus.COMPLETED, "policy_reactions": reaction_count}


func _record_first_completion() -> void:
	if int(last_profile.get("time_to_first_completed_usec", -1)) < 0:
		last_profile.time_to_first_completed_usec = Time.get_ticks_usec() - _search_started_usec


func reset_session(_reason: StringName = &"reset") -> void:
	opening_session.reset()
	# A reset makes the next valid position eligible for a fresh family.  The
	# reason is intentionally not an exit state, which would permanently suppress
	# reinitialization after sandbox position replacement.
	_pending_book_action.clear()
	previous_own_actions.clear()
	_tactical_map = null


func capture_debug_state() -> Dictionary:
	return {
		"candidate_limit": candidate_limit, "max_book_moves": max_book_moves, "quiescence_enabled": quiescence_enabled,
		"previous_own_actions": previous_own_actions.duplicate(true),
		"opening": {
			"active": opening_session.active, "family": String(opening_session.selected_family_id), "node_id": opening_session.node_id,
			"book_moves_played": opening_session.book_moves_played, "own_actions_played": opening_session.own_actions_played,
			"started_global_turn": opening_session.started_global_turn, "deviated": opening_session.deviated,
			"exit_reason": String(opening_session.exit_reason), "last_observed_enemy_move": opening_session.last_observed_enemy_move,
		},
	}


func on_action_executed(action: ChessPrimaryAction, origin: Vector2i) -> void:
	_remember_action(action, origin)
	if not opening_session.active:
		_pending_book_action.clear()
		return
	opening_session.own_actions_played += 1
	if not _pending_book_action.is_empty() and _descriptor_matches_executed_action(_pending_book_action, action, origin):
		opening_session.book_moves_played += 1
		if not opening_session.deviated:
			_advance_node_for_descriptor(_pending_book_action)
		if opening_session.book_moves_played >= max_book_moves:
			opening_session.leave(&"move_limit")
	_pending_book_action.clear()
	_expire_opening_session()


func _begin_book_profile() -> void:
	last_profile["opening_book_hit"] = false
	last_profile["opening_book_fallback"] = false
	last_profile["opening_book_override"] = false
	last_profile["opening_book_active"] = false
	last_profile["opening_family"] = &""
	last_profile["opening_book_moves_played"] = 0
	last_profile["opening_exit_reason"] = &""
	last_profile["opening_book_load_usec"] = 0
	last_profile["opening_book_data_bytes"] = 0
	last_profile["opening_book_family_count"] = 0
	last_profile["tactical_map_build_usec"] = 0
	last_profile["tactical_map_direct_attack_calls"] = 0
	last_profile["tactical_projection_count"] = 0
	last_profile["tactical_incremental_recalculations"] = 0
	last_profile["tactical_projection_attack_calls"] = 0
	last_profile["tactical_projection_usec"] = 0
	last_profile["mandatory_candidate_count"] = 0
	last_profile["selected_candidate_reason"] = &""
	last_profile["screened_reply_count"] = 0
	last_profile["reused_screened_reply_count"] = 0
	last_profile["exhaustive_quiet_reply_count"] = 0
	last_profile["screen_pruned_candidates"] = 0
	last_profile["quiescence_node_count"] = 0
	last_profile["quiescence_incomplete_count"] = 0
	last_profile["forcing_reply_count"] = 0
	last_profile["quiet_reply_count"] = 0
	last_profile["screening_usec"] = 0
	last_profile["exhaustive_verification_usec"] = 0
	last_profile["time_to_first_completed_usec"] = -1
	last_profile["forcing_ability_retained"] = 0
	last_profile["forcing_ability_deferred"] = 0
	last_profile["policy_reactions_resolved"] = 0
	last_profile["own_policy_reactions_resolved"] = 0
	last_profile["opponent_policy_reactions_resolved"] = 0
	last_profile["selected_policy_reactions"] = 0
	last_profile["conditional_verification"] = false
	last_profile["danger_class"] = &"quiet"
	last_profile["material_obligation_count"] = 0
	last_profile["ability_obligation_count"] = 0
	last_profile["ability_threat_current_count"] = 0
	last_profile["ability_threat_next_turn_count"] = 0
	last_profile["ability_threat_query_count"] = 0
	last_profile["ability_threat_query_usec"] = 0
	last_profile["obligation_response_count"] = 0
	last_profile["exchange_analysis_calls"] = 0
	last_profile["exchange_analysis_usec"] = 0
	last_profile["exchange_high_confidence"] = 0
	last_profile["exchange_medium_confidence"] = 0
	last_profile["exchange_low_confidence"] = 0
	last_profile["terminal_win_early_stop"] = false
	last_profile["prepared_root_candidates"] = 0
	last_profile["breadth_screen_rounds"] = 0
	last_profile["breadth_completion_rounds"] = 0
	last_profile["timeout_fallback_source"] = &""


func _ensure_opening_session() -> void:
	if opening_session.active or opening_session.exit_reason != &"not_started":
		return
	if max_book_moves <= 0:
		opening_session.leave(&"disabled")
		return
	if not _is_compatible_opening_position():
		opening_session.leave(&"incompatible_position")
		return
	var families: Array[Dictionary] = OpeningBook.families()
	if families.is_empty():
		opening_session.leave(&"book_data_unavailable")
		return
	var eligible: Array[Dictionary] = []
	eligible.assign(families)
	var initial_node := 0
	var last := _last_move_descriptor()
	if player.controlled_color == "black" and not last.is_empty() and last.color == "white":
		eligible.clear()
		for family in families:
			if OpeningBook.matching_child_node(StringName(family.id), 0, last) >= 0: eligible.append(family)
		if eligible.is_empty(): eligible.assign(families)
	var selected: Dictionary = eligible[player.rng.randi_range(0, eligible.size() - 1)]
	if player.controlled_color == "black" and not last.is_empty() and last.color == "white":
		initial_node = OpeningBook.matching_child_node(StringName(selected.id), 0, last)
	opening_session.begin(StringName(selected.id), player.model.global_turn_number, maxi(initial_node, 0))
	if player.controlled_color == "black" and initial_node < 0:
		opening_session.deviated = true
	if not last.is_empty() and last.color != player.controlled_color:
		opening_session.last_observed_enemy_move = _descriptor_key(last)


func _try_opening_book(actions: Array[ChessPrimaryAction]):
	if not opening_session.active:
		_populate_book_profile()
		return null
	_expire_opening_session()
	if not opening_session.active:
		_populate_book_profile()
		return null
	_sync_opponent_move()
	if _has_mandatory_override(actions):
		last_profile.opening_book_override = true
		last_profile.opening_book_fallback = true
		_populate_book_profile()
		return null
	var policy := DuprePolicy.new(player, previous_own_actions, _tactical_map)
	var matches: Array[ChessPrimaryAction] = []
	for descriptor in _current_book_descriptors():
		for action in actions:
			if (
				_descriptor_matches_action(descriptor, action)
				and player._is_acceptable_primary_action(action)
				and not policy.creates_new_king_threat(action)
				and policy.newly_exposed_undefended_value(action) <= 0.0
				and policy.score(action) >= -2.0
				and action not in matches
			):
				matches.append(action)
	if matches.is_empty():
		opening_session.leave(&"no_legal_continuation")
		last_profile.opening_book_fallback = true
		_populate_book_profile()
		return null
	var selected: ChessPrimaryAction = matches[player.rng.randi_range(0, matches.size() - 1)]
	_pending_book_action = _action_descriptor(selected)
	last_profile.opening_book_hit = true
	last_profile.selected_status = &"book_fast_path"
	last_profile.selected_candidate_reason = &"opening_book"
	_populate_book_profile()
	var plan := ChessAiPlan.new(selected)
	plan.brain_id = &"dupre"
	plan.score = policy.score(selected)
	_populate_policy_profile(policy)
	plan.analyzed_leaf_count = 0
	_finish_profile()
	plan.search_profile = get_last_profile()
	for match_action in matches.slice(0, mini(12, matches.size())):
		plan.candidates.append({"action": ActionCodec.describe(match_action), "score": policy.score(match_action), "status": "book", "reason": "opening_book"})
	return plan


func _has_mandatory_override(actions: Array[ChessPrimaryAction]) -> bool:
	for action in actions:
		if player._is_acceptable_primary_action(action) and player._is_immediate_win(action): return true
	for action in actions:
		if player._is_acceptable_primary_action(action) and _is_direct_king_attack(action): return true
	var king: ModelPiece = player.model.get_king(player.controlled_color)
	if king == null or player.king_safety_turns_remaining > 0: return true
	if player._king_threat_count(king, king.coordinate, player._current_board_state()) > 0: return true
	var policy := DuprePolicy.new(player, previous_own_actions, _tactical_map)
	for row in player.model.board:
		for piece in row:
			if piece == null or piece.color != player.controlled_color:
				continue
			if policy.is_valuable_piece_threatened(piece):
				_accumulate_ability_threat_profile(policy)
				return true
			if not piece.is_king and _material_value(piece) >= 3.0:
				var ability_threat: Dictionary = policy.ability_threat(piece, 1)
				if bool(ability_threat.get("lethal", false)):
					_accumulate_ability_threat_profile(policy)
					return true
	_accumulate_ability_threat_profile(policy)
	for action in actions:
		if (
			action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY
			and player._is_acceptable_primary_action(action)
			and (_layer_action_is_forcing(player.model, action, player.controlled_color) or policy.score(action) >= 8.0)
		): return true
	return false


func _sync_opponent_move() -> void:
	var descriptor := _last_move_descriptor()
	if descriptor.is_empty() or descriptor.color == player.controlled_color: return
	var key := _descriptor_key(descriptor)
	if key == opening_session.last_observed_enemy_move: return
	opening_session.last_observed_enemy_move = key
	if opening_session.deviated: return
	var matching_node := OpeningBook.matching_child_node(opening_session.selected_family_id, opening_session.node_id, descriptor)
	if matching_node < 0:
		opening_session.deviated = true
		return
	opening_session.node_id = matching_node


func _current_book_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys := {}
	if not opening_session.deviated:
		for descriptor in OpeningBook.child_descriptors(opening_session.selected_family_id, opening_session.node_id, player.controlled_color):
			_append_descriptor(result, keys, descriptor)
	if not result.is_empty(): return result
	for descriptor in OpeningBook.recovery_descriptors(opening_session.selected_family_id, player.controlled_color, opening_session.book_moves_played):
		_append_descriptor(result, keys, descriptor)
	return result


func _append_descriptor(result: Array[Dictionary], keys: Dictionary, descriptor: Dictionary) -> void:
	var key := _descriptor_key(descriptor)
	if keys.has(key): return
	keys[key] = true
	result.append(descriptor)


func _advance_node_for_descriptor(descriptor: Dictionary) -> void:
	var matching_node := OpeningBook.matching_child_node(opening_session.selected_family_id, opening_session.node_id, descriptor)
	if matching_node < 0:
		opening_session.deviated = true
		return
	opening_session.node_id = matching_node


func _is_compatible_opening_position() -> bool:
	if player.model.board.size() != 8 or player.model.board[0].size() != 8: return false
	for color in ["white", "black"]:
		var king: ModelPiece = player.model.get_king(color)
		if king == null: return false
		var layer = KingAiRegistry.layer_for(king.get_position_type_id())
		if layer == null or not layer.allows_traditional_opening(): return false
		var counts := {&"pawn": 0, &"knight": 0, &"bishop": 0, &"rook": 0, &"queen": 0}
		for row in player.model.board:
			for piece in row:
				if piece != null and piece.color == color and counts.has(piece.get_position_type_id()): counts[piece.get_position_type_id()] += 1
		if counts[&"pawn"] < 8 or counts[&"knight"] < 2 or counts[&"bishop"] < 2 or counts[&"rook"] < 2 or counts[&"queen"] < 1: return false
	return true


func _expire_opening_session() -> void:
	if not opening_session.active: return
	if opening_session.book_moves_played >= max_book_moves: opening_session.leave(&"move_limit")
	elif opening_session.own_actions_played >= maxi(max_book_moves * 2, 8): opening_session.leave(&"own_action_expiry")
	elif player.model.global_turn_number - opening_session.started_global_turn >= maxi(max_book_moves * 3, 10): opening_session.leave(&"turn_expiry")


func _populate_book_profile() -> void:
	last_profile.opening_book_active = opening_session.active
	last_profile.opening_family = opening_session.selected_family_id
	last_profile.opening_book_moves_played = opening_session.book_moves_played
	last_profile.opening_exit_reason = opening_session.exit_reason


func _last_move_descriptor() -> Dictionary:
	var last: Dictionary = player.model.last_move
	var piece: ModelPiece = last.get("piece")
	if piece == null or not is_instance_valid(piece): return {}
	return {"kind": ChessPrimaryAction.Kind.MOVE, "color": piece.color, "piece": _opening_piece_type(piece), "from": last.get("from"), "to": last.get("to"), "path": [last.get("to")]}


func _action_descriptor(action: ChessPrimaryAction) -> Dictionary:
	return {"kind": action.kind, "color": action.piece.color, "piece": _opening_piece_type(action.piece), "from": action.piece.coordinate, "to": action.target, "path": action.path.duplicate()}


func _descriptor_matches_action(descriptor: Dictionary, action: ChessPrimaryAction) -> bool:
	return int(descriptor.kind) == action.kind and descriptor.color == action.piece.color and StringName(descriptor.piece) == _opening_piece_type(action.piece) and descriptor.from == action.piece.coordinate and descriptor.to == action.target and descriptor.get("path", [descriptor.to]) == action.path


func _descriptor_matches_executed_action(descriptor: Dictionary, action: ChessPrimaryAction, origin: Vector2i) -> bool:
	return int(descriptor.kind) == action.kind and descriptor.color == action.piece.color and StringName(descriptor.piece) == _opening_piece_type(action.piece) and descriptor.from == origin and descriptor.to == action.target and descriptor.get("path", [descriptor.to]) == action.path


func _descriptor_key(descriptor: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s" % [descriptor.get("kind", -1), descriptor.get("color", ""), descriptor.get("piece", ""), descriptor.get("from", Vector2i(-1, -1)), descriptor.get("to", Vector2i(-1, -1)), descriptor.get("path", [])]


func _rank_actions(actions: Array[ChessPrimaryAction], policy) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for index in range(actions.size()):
		var action := actions[index]
		if not player._is_acceptable_primary_action(action):
			continue
		ranked.append({"action": action, "policy": policy.score(action), "index": index})
		await _cooperate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.policy), float(b.policy)):
			return float(a.policy) > float(b.policy)
		return int(a.index) < int(b.index)
	)
	return ranked


func _select_candidates(ranked: Array[Dictionary], policy) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var selected_keys := {}
	# Mandatory tactical actions are searched before the ordinary policy slots so
	# a soft timeout cannot strand an obvious win or check response at the end.
	for entry in ranked:
		if player._is_immediate_win(entry.action):
			_append_unique(selected, selected_keys, entry, &"immediate_win")
	var king: ModelPiece = player.model.get_king(player.controlled_color)
	var king_danger := false
	if king != null:
		var current_threats: int = maxi(
			policy.tactical_map.king_attackers(player.controlled_color).size(),
			player._king_threat_count(king, king.coordinate, player._current_board_state())
		)
		if current_threats > 0 or player.king_safety_turns_remaining > 0:
			king_danger = true
			var minimum := 999
			for entry in ranked:
				minimum = mini(minimum, maxi(policy.direct_king_threat_count_after(entry.action), player._projected_king_threat_count(entry.action)))
			for entry in ranked:
				if maxi(policy.direct_king_threat_count_after(entry.action), player._projected_king_threat_count(entry.action)) == minimum:
					_append_unique(selected, selected_keys, entry, &"king_safety")
	var retained_king_attacks := 0
	for entry in ranked:
		if retained_king_attacks >= DIRECT_KING_ATTACK_CAP: break
		if _is_direct_king_attack(entry.action) and not player._is_immediate_win(entry.action):
			var before := selected.size()
			_append_unique(selected, selected_keys, entry, &"king_attack")
			if selected.size() > before: retained_king_attacks += 1
	var obligations := _material_obligations(policy)
	last_profile.material_obligation_count = obligations.size()
	for obligation in obligations:
		var responses: Array[Dictionary] = []
		var attacker_ids := {}
		for exchange_step in obligation.get("sequence", []):
			attacker_ids[String(exchange_step.get("attacker", ""))] = true
		for entry in ranked:
			var risk: Dictionary
			if bool(obligation.get("ability", false)):
				var remaining: Dictionary = policy.ability_threat_after(entry.action, obligation.piece, 1)
				risk = {"loss": obligation.loss if bool(remaining.get("lethal", false)) else 0.0, "confidence": DupreExchangeAnalyzer.Confidence.HIGH}
			else:
				risk = policy.material_risk_after(entry.action, obligation.piece)
			if float(risk.loss) + 0.01 < float(obligation.loss):
				var target_piece: ModelPiece = player.model.board[entry.action.target.x][entry.action.target.y]
				responses.append({
					"entry": entry,
					"loss": float(risk.loss),
					"confidence": int(risk.confidence),
					"captures_attacker": target_piece != null and attacker_ids.has(target_piece.piece_id),
				})
		responses.sort_custom(func(a: Dictionary, b: Dictionary):
			if bool(a.captures_attacker) != bool(b.captures_attacker): return bool(a.captures_attacker)
			if not is_equal_approx(float(a.loss), float(b.loss)): return float(a.loss) < float(b.loss)
			if int(a.confidence) != int(b.confidence): return int(a.confidence) > int(b.confidence)
			return float(a.entry.policy) > float(b.entry.policy)
		)
		for index in range(mini(MAX_OBLIGATION_RESPONSES, responses.size())):
			var before := selected.size()
			_append_unique(selected, selected_keys, responses[index].entry, &"material_obligation")
			if selected.size() > before: last_profile.obligation_response_count += 1
	for entry in ranked:
		if policy.captures_current_king_attacker(entry.action):
			_append_unique(selected, selected_keys, entry, &"capture_king_attacker")
		elif policy.capture_material_swing(entry.action) >= 3.0:
			_append_unique(selected, selected_keys, entry, &"favorable_capture")
	var retained_forcing := 0
	for entry in ranked:
		if not _layer_action_is_forcing(player.model, entry.action, player.controlled_color):
			continue
		if retained_forcing < FORCING_ABILITY_CAP:
			var before := selected.size()
			_append_unique(selected, selected_keys, entry, &"king_ability")
			if selected.size() > before:
				retained_forcing += 1
		else:
			last_profile.forcing_ability_deferred += 1
	last_profile.forcing_ability_retained = retained_forcing
	if king_danger or not obligations.is_empty():
		last_profile.danger_class = &"critical"
	elif retained_forcing > 0 or selected.size() > 0:
		last_profile.danger_class = &"tactical"
	last_profile.mandatory_candidate_count = selected.size()
	var ordinary_count := 0
	for entry in ranked:
		if ordinary_count >= candidate_limit:
			break
		var before := selected.size()
		_append_unique(selected, selected_keys, entry, &"policy")
		if selected.size() > before:
			ordinary_count += 1
	return selected


func _is_direct_king_attack(action: ChessPrimaryAction) -> bool:
	if action == null: return false
	var target: ModelPiece = player.model.board[action.target.x][action.target.y]
	return target != null and target.color != action.piece.color and target.is_king and _action_damage(action) > 0


func _material_obligations(policy) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for coordinate in policy.tactical_map.occupancy:
		var piece = policy.tactical_map.occupancy[coordinate]
		if not piece is ModelPiece or piece.color != player.controlled_color or piece.is_king:
			continue
		var value := _material_value(piece)
		if value < 3.0:
			continue
		var ability_threat: Dictionary = policy.ability_threat(piece, 1)
		if bool(ability_threat.get("lethal", false)):
			result.append({"piece": piece, "loss": value, "confidence": DupreExchangeAnalyzer.Confidence.HIGH, "sequence": [], "ability": true, "ability_id": ability_threat.get("ability_id", &"")})
			last_profile.ability_obligation_count += 1
			if int(ability_threat.get("ready_in_turn_entries", 0)) == 0:
				last_profile.ability_threat_current_count += 1
			else:
				last_profile.ability_threat_next_turn_count += 1
			continue
		var risk: Dictionary = policy.material_risk(piece)
		var threshold := 0.01 if value >= 5.0 else SEVERE_MATERIAL_LOSS
		if float(risk.loss) >= threshold:
			result.append({"piece": piece, "loss": float(risk.loss), "confidence": int(risk.confidence), "sequence": risk.sequence})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.loss) > float(b.loss))
	return result


func _append_unique(result: Array[Dictionary], keys: Dictionary, entry: Dictionary, reason: StringName = &"") -> void:
	var action: ChessPrimaryAction = entry.action
	var key := "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]
	if keys.has(key):
		return
	keys[key] = true
	entry["candidate_reason"] = reason
	result.append(entry)


func _ensure_tactical_map() -> void:
	if _tactical_map == null or _tactical_map.revision != player.model.position_revision:
		_tactical_map = TacticalMap.from_model(player.model)


func _populate_tactical_profile() -> void:
	if _tactical_map == null:
		return
	last_profile.tactical_map_build_usec = _tactical_map.build_usec
	last_profile.tactical_map_direct_attack_calls = _tactical_map.direct_attack_calls


func _populate_policy_profile(policy) -> void:
	var metrics: Dictionary = policy.projection_metrics()
	last_profile.ability_threat_query_count += int(metrics.get("ability_threat_queries", 0))
	last_profile.ability_threat_query_usec += int(metrics.get("ability_threat_usec", 0))
	last_profile.tactical_map_direct_attack_calls = _tactical_map.direct_attack_calls
	last_profile.tactical_map_build_usec = _tactical_map.build_usec + _tactical_map.query_usec
	last_profile.tactical_projection_count = metrics.count
	last_profile.tactical_incremental_recalculations = metrics.recalculations
	last_profile.tactical_projection_attack_calls = metrics.attack_calls
	last_profile.tactical_projection_usec = metrics.usec
	var exchange: Dictionary = metrics.get("exchange", {})
	last_profile.exchange_analysis_calls = int(exchange.get("calls", 0))
	last_profile.exchange_analysis_usec = int(exchange.get("usec", 0))
	last_profile.exchange_high_confidence = int(exchange.get("high", 0))
	last_profile.exchange_medium_confidence = int(exchange.get("medium", 0))
	last_profile.exchange_low_confidence = int(exchange.get("low", 0))


func _accumulate_ability_threat_profile(policy) -> void:
	last_profile.ability_threat_query_count += int(policy.ability_threat_query_count)
	last_profile.ability_threat_query_usec += int(policy.ability_threat_query_usec)


func _remember_action(action: ChessPrimaryAction, origin: Vector2i = Vector2i(-1, -1)) -> void:
	previous_own_actions[action.piece.piece_id] = {
		"from": action.piece.coordinate if origin == Vector2i(-1, -1) else origin,
		"to": action.target,
	}


func _layer_action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, perspective: String) -> bool:
	if not action.piece is KingPiece:
		return false
	var layer = KingAiRegistry.layer_for(action.piece.get_position_type_id())
	return layer != null and layer.action_is_forcing(model, action, perspective)


func _opening_piece_type(piece: ModelPiece) -> StringName:
	if piece is KingPiece:
		var layer = KingAiRegistry.layer_for(piece.get_position_type_id())
		if layer != null and layer.allows_traditional_opening():
			return &"classic_king"
	return piece.get_position_type_id()


static func _king_support_profile(model: ChessBoardModel) -> Dictionary:
	var result := {}
	for color in ["white", "black"]:
		var king := model.get_king(color)
		if king == null:
			continue
		var type_id := king.get_position_type_id()
		result[color] = {
			"type": type_id,
			"level": KingAiRegistry.dupre_support_level(type_id),
			"reason": KingAiRegistry.dupre_unsupported_reason(type_id),
		}
	return result
