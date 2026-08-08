extends Node
class_name ChessCpuPlayer

const ChessActionSimulatorScript = preload("res://scripts/ai/chess_action_simulator.gd")

## Headless client that chooses actions for one color and submits Model commands.

@export var model: ChessBoardModel
@export_range(0.0, 5.0, 0.1) var thinking_delay_seconds: float = 0.5
@export_range(0.0, 50.0, 1.0) var evaluation_frame_budget_ms: float = 8.0

signal command_rejected(color: String, command_type: String, attempt: int)
signal decision_stalled(color: String, decision_type: String)

var controlled_color: String = "black"
var is_enabled: bool = false
var rng := RandomNumberGenerator.new()

var _primary_action_scheduled: bool = false
var _reaction_scheduled: bool = false
var _primary_rejection_count: int = 0
var _reaction_rejection_count: int = 0

const MAX_COMMAND_RETRIES: int = 1
const ACTIVE_ABILITY_BONUS: float = 0.25
const SELF_MATERIAL_LOSS_WEIGHT: float = 1.0
const REPLY_MATERIAL_LOSS_WEIGHT: float = 1.0
const KING_HP_LOSS_PENALTY: float = 100.0
const KING_DEFEAT_PENALTY: float = 10000.0
const INVALID_SIMULATION_SCORE: float = -1.0e20

var _simulator: RefCounted = ChessActionSimulatorScript.new()


func _ready() -> void:
	rng.randomize()
	if model == null:
		return
	model.action_finished.connect(_on_action_finished)
	model.action_cancelled.connect(_on_action_cancelled)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.reaction_selection_resolved.connect(_on_reaction_selection_resolved)
	model.battle_finished.connect(_on_battle_finished)


func configure(enabled: bool, color: String) -> void:
	is_enabled = enabled
	controlled_color = color
	_primary_action_scheduled = false
	_reaction_scheduled = false
	_primary_rejection_count = 0
	_reaction_rejection_count = 0
	if is_enabled:
		_schedule_primary_action()


func set_random_seed(value: int) -> void:
	rng.seed = value


func choose_primary_action(actions: Array[ChessPrimaryAction]) -> ChessPrimaryAction:
	if actions.is_empty():
		return null

	var best_score := -INF
	var best_actions: Array[ChessPrimaryAction] = []
	for action in actions:
		var score := _score_primary_action(action)
		if score > best_score:
			best_score = score
			best_actions.assign([action])
		elif is_equal_approx(score, best_score):
			best_actions.append(action)

	return best_actions[rng.randi_range(0, best_actions.size() - 1)]


func choose_tactical_action(actions: Array[ChessPrimaryAction]) -> ChessPrimaryAction:
	if actions.is_empty():
		return null

	var budget_state := {"deadline_usec": _next_evaluation_deadline_usec()}
	var best_score := INVALID_SIMULATION_SCORE
	var best_actions: Array[ChessPrimaryAction] = []
	for action in actions:
		var score: float = await _score_tactical_action(action, budget_state)
		if score <= INVALID_SIMULATION_SCORE:
			continue
		if score > best_score and not is_equal_approx(score, best_score):
			best_score = score
			best_actions.assign([action])
		elif is_equal_approx(score, best_score):
			best_actions.append(action)

	if best_actions.is_empty():
		push_warning("CPU ", controlled_color, " could not simulate any legal action; using greedy fallback.")
		return choose_primary_action(actions)
	return best_actions[rng.randi_range(0, best_actions.size() - 1)]


func _score_tactical_action(action: ChessPrimaryAction, budget_state: Dictionary) -> float:
	var before_material := _material_total(model, controlled_color)
	var before_king_hp := _king_hp_total(model, controlled_color)
	var context: Dictionary = _simulator.clone_model(model)
	var simulated: ChessBoardModel = context["model"]
	var copied_action: ChessPrimaryAction = _simulator.map_action(action, context["piece_map"])
	if copied_action == null or not await _simulator.submit_action(simulated, copied_action):
		simulated.free()
		return INVALID_SIMULATION_SCORE

	var score := _score_primary_action(action)
	score -= SELF_MATERIAL_LOSS_WEIGHT * maxf(0.0, before_material - _material_total(simulated, controlled_color))
	score -= KING_HP_LOSS_PENALTY * maxi(0, before_king_hp - _king_hp_total(simulated, controlled_color))
	if _is_color_defeated(simulated, controlled_color):
		score -= KING_DEFEAT_PENALTY

	if simulated.battle_over:
		simulated.free()
		return score

	var post_action_material := _material_total(simulated, controlled_color)
	var post_action_king_hp := _king_hp_total(simulated, controlled_color)
	var worst_reply_penalty := 0.0
	var opponent := simulated.get_other_color(controlled_color)
	for reply in simulated.get_legal_primary_actions(opponent):
		var reply_context: Dictionary = _simulator.clone_model(simulated)
		var reply_model: ChessBoardModel = reply_context["model"]
		var copied_reply: ChessPrimaryAction = _simulator.map_action(reply, reply_context["piece_map"])
		if copied_reply == null or not await _simulator.submit_action(reply_model, copied_reply):
			reply_model.free()
			simulated.free()
			return INVALID_SIMULATION_SCORE
		var penalty := REPLY_MATERIAL_LOSS_WEIGHT * maxf(
			0.0, post_action_material - _material_total(reply_model, controlled_color)
		)
		penalty += KING_HP_LOSS_PENALTY * maxi(
			0, post_action_king_hp - _king_hp_total(reply_model, controlled_color)
		)
		if _is_color_defeated(reply_model, controlled_color):
			penalty += KING_DEFEAT_PENALTY
		worst_reply_penalty = maxf(worst_reply_penalty, penalty)
		reply_model.free()
		await _yield_if_evaluation_budget_expired(budget_state)

	simulated.free()
	return score - worst_reply_penalty


func _next_evaluation_deadline_usec() -> int:
	if evaluation_frame_budget_ms <= 0.0:
		return 0
	return Time.get_ticks_usec() + int(evaluation_frame_budget_ms * 1000.0)


func _yield_if_evaluation_budget_expired(budget_state: Dictionary) -> void:
	var deadline_usec: int = budget_state.get("deadline_usec", 0)
	if deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec:
		return
	await get_tree().process_frame
	budget_state["deadline_usec"] = _next_evaluation_deadline_usec()


func _score_primary_action(action: ChessPrimaryAction) -> float:
	var score := 0.0
	var target_piece := _get_target_piece(action)
	if target_piece != null and target_piece.color != action.piece.color:
		score += _get_piece_value(target_piece)
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		score += ACTIVE_ABILITY_BONUS
	return score


func _material_total(board_model: ChessBoardModel, color: String) -> float:
	var total := 0.0
	for row in board_model.board:
		for piece: ModelPiece in row:
			if piece != null and piece.color == color:
				total += _get_piece_value(piece)
	return total


func _king_hp_total(board_model: ChessBoardModel, color: String) -> int:
	var total := 0
	for row in board_model.board:
		for piece: ModelPiece in row:
			if piece != null and piece.color == color and piece.is_king:
				total += piece.current_hp
	return total


func _is_color_defeated(board_model: ChessBoardModel, color: String) -> bool:
	return color in board_model.defeated_king_colors


func _get_target_piece(action: ChessPrimaryAction) -> ModelPiece:
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target != null:
		return target

	# En passant has an empty destination, so score the adjacent captured pawn.
	if (
		action.kind == ChessPrimaryAction.Kind.MOVE
		and action.piece.type == "pawn"
		and action.piece.coordinate.y != action.target.y
	):
		return model.board[action.piece.coordinate.x][action.target.y]
	return null


func _get_piece_value(piece: ModelPiece) -> float:
	if piece.is_king:
		return 100.0
	match piece.type:
		"queen":
			return 9.0
		"rook":
			return 5.0
		"bishop", "knight":
			return 3.0
		"pawn", "bone_pawn":
			return 1.0
		_:
			return 1.0


func _schedule_primary_action() -> void:
	if _primary_action_scheduled or not is_enabled:
		return
	_primary_action_scheduled = true
	call_deferred("_take_primary_action")


func _take_primary_action() -> void:
	_primary_action_scheduled = false
	if not _can_take_primary_action():
		return
	await _wait_for_thinking_delay()
	if not _can_take_primary_action():
		return

	var action := await choose_tactical_action(model.get_legal_primary_actions(controlled_color))
	if action == null:
		_report_stall("no_legal_primary_actions")
		return

	# Tactical evaluation may make the frame containing it much longer than the
	# movement tween itself. Cross two frame boundaries so the live tween is not
	# advanced by that oversized frame delta on its first update.
	await get_tree().process_frame
	await get_tree().process_frame
	if not _can_take_primary_action():
		return
	action = _find_matching_action(
		action,
		model.get_legal_primary_actions(controlled_color)
	)
	if action == null:
		_handle_primary_rejection()
		return

	var accepted: bool
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		accepted = await model.submit_move(action.piece, action.target)
	else:
		accepted = await model.submit_active_ability(action.piece as KingPiece, action.target)

	if not accepted:
		_handle_primary_rejection()


func _find_matching_action(
	desired: ChessPrimaryAction,
	legal_actions: Array[ChessPrimaryAction]
) -> ChessPrimaryAction:
	for legal_action in legal_actions:
		if (
			legal_action.kind == desired.kind
			and legal_action.piece == desired.piece
			and legal_action.target == desired.target
		):
			return legal_action
	return null


func _can_take_primary_action() -> bool:
	return (
		is_enabled
		and model != null
		and not model.battle_over
		and not model.action_in_progress
		and not model.has_pending_reaction()
		and model.current_turn == controlled_color
	)


func _handle_primary_rejection() -> void:
	_primary_rejection_count += 1
	command_rejected.emit(controlled_color, "primary", _primary_rejection_count)
	if _primary_rejection_count <= MAX_COMMAND_RETRIES and _can_take_primary_action():
		_schedule_primary_action()
	else:
		_report_stall("primary_command_rejected")


func _schedule_reaction() -> void:
	if _reaction_scheduled or not is_enabled:
		return
	_reaction_scheduled = true
	call_deferred("_take_reaction")


func _take_reaction() -> void:
	_reaction_scheduled = false
	if not _owns_pending_reaction():
		return
	await _wait_for_thinking_delay()
	if not _owns_pending_reaction():
		return

	var pending := model.get_pending_reaction()
	var calling_piece: ModelPiece = pending.get("calling_piece")
	var targets: Array = pending.get("targets", [])
	if targets.is_empty():
		_report_stall("no_reaction_targets")
		return

	var target: Vector2i = targets[rng.randi_range(0, targets.size() - 1)]
	var accepted := await model.submit_reaction_selection(target)
	if not accepted:
		_handle_reaction_rejection()


func _owns_pending_reaction() -> bool:
	if not is_enabled or model == null or model.battle_over or not model.has_pending_reaction():
		return false
	var pending := model.get_pending_reaction()
	var calling_piece: ModelPiece = pending.get("calling_piece")
	return is_instance_valid(calling_piece) and calling_piece.color == controlled_color


func _handle_reaction_rejection() -> void:
	_reaction_rejection_count += 1
	command_rejected.emit(controlled_color, "reaction", _reaction_rejection_count)
	if _reaction_rejection_count <= MAX_COMMAND_RETRIES and _owns_pending_reaction():
		_schedule_reaction()
	else:
		_report_stall("reaction_command_rejected")


func _report_stall(decision_type: String) -> void:
	push_warning("CPU ", controlled_color, " stopped: ", decision_type)
	decision_stalled.emit(controlled_color, decision_type)


func _wait_for_thinking_delay() -> void:
	if thinking_delay_seconds <= 0.0:
		return
	await get_tree().create_timer(thinking_delay_seconds).timeout


func _on_action_finished() -> void:
	_primary_rejection_count = 0
	_schedule_primary_action()


func _on_action_cancelled() -> void:
	_primary_rejection_count = 0
	_schedule_primary_action()


func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, _targets: Array) -> void:
	if is_enabled and calling_piece.color == controlled_color:
		_reaction_rejection_count = 0
		_schedule_reaction()


func _on_reaction_selection_resolved(calling_piece: ModelPiece, _action_type: String, _target: Vector2i) -> void:
	if calling_piece.color == controlled_color:
		_reaction_rejection_count = 0


func _on_battle_finished(_winner_color: String) -> void:
	_primary_action_scheduled = false
	_reaction_scheduled = false
