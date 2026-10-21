extends LeMayAiBrain
class_name DupreAiBrain

const DuprePolicy = preload("res://scripts/ai/dupre_move_policy.gd")
const DEFAULT_CANDIDATE_LIMIT := 6
const TACTICAL_SAFETY_MARGIN := 12.0

var candidate_limit := DEFAULT_CANDIDATE_LIMIT
var previous_own_actions: Dictionary = {}


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	_begin_profile(actions.size())
	if actions.is_empty() or not unsupported_king_ids(player.model).is_empty():
		_finish_profile()
		return null
	_root_revision = player.model.position_revision
	var policy := DuprePolicy.new(player, previous_own_actions)
	var ranked := await _rank_actions(actions, policy)
	if ranked.is_empty():
		_finish_profile()
		return null
	var candidates := _select_candidates(ranked, policy)
	last_profile["policy_candidate_count"] = candidates.size()
	last_profile["unverified_selection"] = false
	var root_position: ChessPosition = player.model.capture_position()
	var exact: Array[Dictionary] = []
	var best_tactical := -INF

	for entry in candidates:
		if _budget_exhausted():
			last_profile.incomplete_root_candidates += 1
			continue
		var rejection_floor := best_tactical - TACTICAL_SAFETY_MARGIN if best_tactical > -INF else -INF
		var result := await _search_root_candidate(root_position, entry.action, rejection_floor)
		match result.status:
			CandidateStatus.COMPLETED:
				last_profile.exact_root_candidates += 1
				result["policy"] = entry.policy
				exact.append(result)
				best_tactical = maxf(best_tactical, float(result.score))
			CandidateStatus.PRUNED:
				last_profile.pruned_root_candidates += 1
			CandidateStatus.INCOMPLETE:
				last_profile.incomplete_root_candidates += 1
			CandidateStatus.INVALID:
				last_profile.invalid_root_candidates += 1
		await _cooperate()

	var selected_action: ChessPrimaryAction
	var selected_score := 0.0
	if exact.is_empty():
		selected_action = ranked[0].action
		selected_score = ranked[0].policy
		last_profile.fallback_used = true
		last_profile.unverified_selection = true
		last_profile.selected_status = &"policy_fallback"
	else:
		var safe: Array[Dictionary] = exact.filter(func(candidate: Dictionary): return float(candidate.score) >= best_tactical - TACTICAL_SAFETY_MARGIN)
		safe.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.policy) > float(b.policy))
		selected_action = safe[0].action
		selected_score = safe[0].score
		last_profile.selected_status = &"verified"

	_remember_action(selected_action)
	var plan := ChessAiPlan.new(selected_action)
	plan.brain_id = &"dupre"
	plan.score = selected_score
	plan.analyzed_leaf_count = last_profile.evaluated_reply_count
	_finish_profile()
	plan.search_profile = get_last_profile()
	return plan


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
	for entry in ranked:
		if selected.size() >= candidate_limit:
			break
		_append_unique(selected, selected_keys, entry)

	# Winning moves and best king-safety responses are mandatory regardless of rank.
	for entry in ranked:
		if player._is_immediate_win(entry.action):
			_append_unique(selected, selected_keys, entry)
	var king: ModelPiece = player.model.get_king(player.controlled_color)
	if king != null:
		var current_threats: int = player._king_threat_count(king, king.coordinate, player._current_board_state())
		if current_threats > 0 or player.king_safety_turns_remaining > 0:
			var minimum := 999
			for entry in ranked:
				minimum = mini(minimum, player._projected_king_threat_count(entry.action))
			for entry in ranked:
				if player._projected_king_threat_count(entry.action) == minimum:
					_append_unique(selected, selected_keys, entry)
	var valuable_defenses_by_piece := {}
	for entry in ranked:
		var piece: ModelPiece = entry.action.piece
		if policy.is_valuable_piece_threatened(piece):
			var defense_count := int(valuable_defenses_by_piece.get(piece.piece_id, 0))
			if defense_count < 3:
				_append_unique(selected, selected_keys, entry)
				valuable_defenses_by_piece[piece.piece_id] = defense_count + 1
	return selected


func _append_unique(result: Array[Dictionary], keys: Dictionary, entry: Dictionary) -> void:
	var action: ChessPrimaryAction = entry.action
	var key := "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]
	if keys.has(key):
		return
	keys[key] = true
	result.append(entry)


func _remember_action(action: ChessPrimaryAction) -> void:
	previous_own_actions[action.piece.piece_id] = {
		"from": action.piece.coordinate,
		"to": action.target,
	}
