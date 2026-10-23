extends LeMayAiBrain
class_name DupreAiBrain

const DuprePolicy = preload("res://scripts/ai/dupre_move_policy.gd")
const OpeningBook = preload("res://scripts/ai/dupre_opening_book.gd")
const OpeningSession = preload("res://scripts/ai/dupre_opening_session.gd")
const DEFAULT_CANDIDATE_LIMIT := 6
const DEFAULT_MAX_BOOK_MOVES := 7
const TACTICAL_SAFETY_MARGIN := 12.0

var candidate_limit := DEFAULT_CANDIDATE_LIMIT
var max_book_moves := DEFAULT_MAX_BOOK_MOVES
var previous_own_actions: Dictionary = {}
var opening_session = OpeningSession.new()
var _pending_book_action: Dictionary = {}


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	_begin_profile(actions.size())
	_begin_book_profile()
	_pending_book_action.clear()
	if actions.is_empty() or not unsupported_king_ids(player.model).is_empty():
		_finish_profile()
		return null
	_root_revision = player.model.position_revision
	_ensure_opening_session()
	var book_plan = _try_opening_book(actions)
	if book_plan != null:
		return book_plan
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

	var plan := ChessAiPlan.new(selected_action)
	plan.brain_id = &"dupre"
	plan.score = selected_score
	plan.analyzed_leaf_count = last_profile.evaluated_reply_count
	_finish_profile()
	plan.search_profile = get_last_profile()
	return plan


func reset_session(_reason: StringName = &"reset") -> void:
	opening_session.reset()
	# A reset makes the next valid position eligible for a fresh family.  The
	# reason is intentionally not an exit state, which would permanently suppress
	# reinitialization after sandbox position replacement.
	_pending_book_action.clear()
	previous_own_actions.clear()


func on_action_executed(action: ChessPrimaryAction, origin: Vector2i) -> void:
	_remember_action(action, origin)
	if not opening_session.active:
		_pending_book_action.clear()
		return
	opening_session.own_actions_played += 1
	if not _pending_book_action.is_empty() and _descriptor_matches_executed_action(_pending_book_action, action, origin):
		opening_session.book_moves_played += 1
		if not opening_session.deviated:
			_advance_lines_for_descriptor(_pending_book_action)
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


func _ensure_opening_session() -> void:
	if opening_session.active or opening_session.exit_reason != &"not_started":
		return
	if max_book_moves <= 0:
		opening_session.leave(&"disabled")
		return
	if not _is_compatible_classic_position():
		opening_session.leave(&"incompatible_position")
		return
	var families: Array[Dictionary] = OpeningBook.families()
	var eligible: Array[Dictionary] = []
	eligible.assign(families)
	var initial_lines: Array[int] = []
	var initial_cursor := 0
	var last := _last_move_descriptor()
	if player.controlled_color == "black" and not last.is_empty() and last.color == "white":
		eligible.clear()
		for family in families:
			if not _matching_line_indices(family, 0, last).is_empty(): eligible.append(family)
		if eligible.is_empty(): eligible.assign(families)
	var selected: Dictionary = eligible[player.rng.randi_range(0, eligible.size() - 1)]
	if player.controlled_color == "black" and not last.is_empty() and last.color == "white":
		initial_lines = _matching_line_indices(selected, 0, last)
		if not initial_lines.is_empty(): initial_cursor = 1
	opening_session.begin(selected, player.model.global_turn_number, initial_cursor, initial_lines)
	if player.controlled_color == "black" and initial_cursor == 0:
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
	var policy := DuprePolicy.new(player, previous_own_actions)
	var matches: Array[ChessPrimaryAction] = []
	for descriptor in _current_book_descriptors():
		for action in actions:
			if _descriptor_matches_action(descriptor, action) and player._is_acceptable_primary_action(action) and policy.score(action) >= -2.0 and action not in matches:
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
	_populate_book_profile()
	var plan := ChessAiPlan.new(selected)
	plan.brain_id = &"dupre"
	plan.score = policy.score(selected)
	plan.analyzed_leaf_count = 0
	_finish_profile()
	plan.search_profile = get_last_profile()
	return plan


func _has_mandatory_override(actions: Array[ChessPrimaryAction]) -> bool:
	for action in actions:
		if player._is_acceptable_primary_action(action) and player._is_immediate_win(action): return true
	var king: ModelPiece = player.model.get_king(player.controlled_color)
	if king == null or player.king_safety_turns_remaining > 0: return true
	if player._king_threat_count(king, king.coordinate, player._current_board_state()) > 0: return true
	var policy := DuprePolicy.new(player, previous_own_actions)
	for row in player.model.board:
		for piece in row:
			if piece != null and piece.color == player.controlled_color and policy.is_valuable_piece_threatened(piece): return true
	for action in actions:
		if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and player._is_acceptable_primary_action(action) and player._score_primary_action(action) >= 8.0: return true
	return false


func _sync_opponent_move() -> void:
	var descriptor := _last_move_descriptor()
	if descriptor.is_empty() or descriptor.color == player.controlled_color: return
	var key := _descriptor_key(descriptor)
	if key == opening_session.last_observed_enemy_move: return
	opening_session.last_observed_enemy_move = key
	if opening_session.deviated: return
	var matching := _matching_line_indices(opening_session.selected_family, opening_session.cursor, descriptor, opening_session.candidate_line_indices)
	if matching.is_empty():
		opening_session.deviated = true
		return
	opening_session.candidate_line_indices = matching
	opening_session.cursor += 1


func _current_book_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys := {}
	if not opening_session.deviated:
		for line_index in opening_session.candidate_line_indices:
			var line: Array = opening_session.selected_family.lines[line_index]
			if opening_session.cursor < line.size():
				var descriptor: Dictionary = line[opening_session.cursor]
				if descriptor.color == player.controlled_color: _append_descriptor(result, keys, descriptor)
	if not result.is_empty(): return result
	for line in opening_session.selected_family.get("lines", []):
		var own_index := 0
		for descriptor in line:
			if descriptor.color != player.controlled_color: continue
			if own_index == opening_session.book_moves_played:
				_append_descriptor(result, keys, descriptor)
				break
			own_index += 1
	return result


func _append_descriptor(result: Array[Dictionary], keys: Dictionary, descriptor: Dictionary) -> void:
	var key := _descriptor_key(descriptor)
	if keys.has(key): return
	keys[key] = true
	result.append(descriptor)


func _advance_lines_for_descriptor(descriptor: Dictionary) -> void:
	var matching := _matching_line_indices(opening_session.selected_family, opening_session.cursor, descriptor, opening_session.candidate_line_indices)
	if matching.is_empty():
		opening_session.deviated = true
		return
	opening_session.candidate_line_indices = matching
	opening_session.cursor += 1


func _matching_line_indices(family: Dictionary, cursor: int, descriptor: Dictionary, source: Array[int] = []) -> Array[int]:
	var result: Array[int] = []
	var indices: Array[int] = []
	if source.is_empty():
		for index in range(family.get("lines", []).size()): indices.append(index)
	else: indices.assign(source)
	for index in indices:
		var line: Array = family.lines[index]
		if cursor < line.size() and _descriptors_equal(line[cursor], descriptor): result.append(index)
	return result


func _is_compatible_classic_position() -> bool:
	if player.model.board.size() != 8 or player.model.board[0].size() != 8: return false
	for color in ["white", "black"]:
		var king: ModelPiece = player.model.get_king(color)
		if king == null or king.get_position_type_id() != &"classic_king": return false
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
	last_profile.opening_family = opening_session.selected_family.get("id", &"")
	last_profile.opening_book_moves_played = opening_session.book_moves_played
	last_profile.opening_exit_reason = opening_session.exit_reason


func _last_move_descriptor() -> Dictionary:
	var last: Dictionary = player.model.last_move
	var piece: ModelPiece = last.get("piece")
	if piece == null or not is_instance_valid(piece): return {}
	return {"kind": ChessPrimaryAction.Kind.MOVE, "color": piece.color, "piece": piece.get_position_type_id(), "from": last.get("from"), "to": last.get("to"), "path": [last.get("to")]}


func _action_descriptor(action: ChessPrimaryAction) -> Dictionary:
	return {"kind": action.kind, "color": action.piece.color, "piece": action.piece.get_position_type_id(), "from": action.piece.coordinate, "to": action.target, "path": action.path.duplicate()}


func _descriptor_matches_action(descriptor: Dictionary, action: ChessPrimaryAction) -> bool:
	return int(descriptor.kind) == action.kind and descriptor.color == action.piece.color and StringName(descriptor.piece) == action.piece.get_position_type_id() and descriptor.from == action.piece.coordinate and descriptor.to == action.target and descriptor.get("path", [descriptor.to]) == action.path


func _descriptor_matches_executed_action(descriptor: Dictionary, action: ChessPrimaryAction, origin: Vector2i) -> bool:
	return int(descriptor.kind) == action.kind and descriptor.color == action.piece.color and StringName(descriptor.piece) == action.piece.get_position_type_id() and descriptor.from == origin and descriptor.to == action.target and descriptor.get("path", [descriptor.to]) == action.path


func _descriptors_equal(a: Dictionary, b: Dictionary) -> bool:
	return int(a.kind) == int(b.kind) and a.color == b.color and StringName(a.piece) == StringName(b.piece) and a.from == b.from and a.to == b.to and a.get("path", [a.to]) == b.get("path", [b.to])


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


func _remember_action(action: ChessPrimaryAction, origin: Vector2i = Vector2i(-1, -1)) -> void:
	previous_own_actions[action.piece.piece_id] = {
		"from": action.piece.coordinate if origin == Vector2i(-1, -1) else origin,
		"to": action.target,
	}
