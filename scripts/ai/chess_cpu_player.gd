extends Node
class_name ChessCpuPlayer

const ChessAiThoughtData = preload("res://scripts/ai/chess_ai_thought.gd")

signal thought_changed(thought)

## Headless client that chooses actions for one color and submits Model commands.

@export var model: ChessBoardModel

enum ExecutionMode { DISABLED, AUTO, MANUAL }

var controlled_color: String = "black"
var is_enabled: bool = false
var execution_mode := ExecutionMode.DISABLED
var rng := RandomNumberGenerator.new()
var last_thought
var king_safety_turns_remaining := 0
var _king_safety_revision := 0

var _primary_action_scheduled: bool = false
var _reaction_scheduled: bool = false
var _schedule_generation: int = 0


func _ready() -> void:
	rng.randomize()
	if model == null:
		return
	model.action_finished.connect(_on_action_finished)
	model.action_cancelled.connect(_on_action_cancelled)
	model.forced_pass_sequence_finished.connect(_on_forced_pass_sequence_finished)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.battle_finished.connect(_on_battle_finished)
	model.piece_damaged.connect(_on_piece_damaged)


func configure(enabled: bool, color: String) -> void:
	configure_mode(ExecutionMode.AUTO if enabled else ExecutionMode.DISABLED, color)

func configure_mode(mode: ExecutionMode, color: String) -> void:
	execution_mode = mode
	is_enabled = mode != ExecutionMode.DISABLED
	controlled_color = color if color == "white" else "black"
	_primary_action_scheduled = false
	_reaction_scheduled = false
	_schedule_generation += 1
	king_safety_turns_remaining = 0
	_king_safety_revision += 1
	clear_thought()
	if execution_mode == ExecutionMode.AUTO:
		_schedule_primary_action()


func set_random_seed(value: int) -> void:
	rng.seed = value
	clear_thought()

func think():
	clear_thought()
	if not is_enabled or execution_mode == ExecutionMode.DISABLED or model == null or model.battle_over or not model.is_settled() or model.current_turn != controlled_color:
		return null
	var action := choose_primary_action(model.get_legal_primary_actions(controlled_color))
	if action == null:
		return null
	var thought = ChessAiThoughtData.new()
	thought.model_revision = model.position_revision
	thought.color = controlled_color
	thought.action_kind = action.kind
	thought.piece_coordinate = action.piece.coordinate
	thought.piece_type_id = action.piece.get_position_type_id()
	thought.target = action.target
	thought.path.assign(action.path)
	thought.score = _score_primary_action(action)
	last_thought = thought
	thought_changed.emit(last_thought)
	return thought

func get_last_thought():
	return last_thought

func clear_thought() -> void:
	if last_thought == null:
		return
	last_thought = null
	thought_changed.emit(null)

func execute_thought() -> bool:
	if last_thought == null or model == null or last_thought.model_revision != model.position_revision or model.current_turn != last_thought.color or not model.is_settled():
		return false
	var matching: ChessPrimaryAction = null
	for action in model.get_legal_primary_actions(controlled_color):
		if action.kind == last_thought.action_kind and action.target == last_thought.target and action.path == last_thought.path and action.piece.coordinate == last_thought.piece_coordinate and action.piece.get_position_type_id() == last_thought.piece_type_id:
			matching = action
			break
	clear_thought()
	if matching == null:
		return false
	var safety_revision_before_action := _king_safety_revision
	var consumes_safety_turn := king_safety_turns_remaining > 0
	var accepted: bool
	if matching.kind == ChessPrimaryAction.Kind.MOVE:
		if matching.path.size() > 1:
			accepted = await model.submit_move_path(matching.piece, matching.path)
		else:
			accepted = await model.submit_move(matching.piece, matching.target)
	else:
		accepted = await model.submit_active_ability(matching.piece as KingPiece, matching.target)
	if accepted and consumes_safety_turn and safety_revision_before_action == _king_safety_revision:
		king_safety_turns_remaining -= 1
	if accepted and execution_mode == ExecutionMode.MANUAL:
		await _resolve_manual_reactions()
	return accepted

func step() -> bool:
	if think() == null:
		return false
	return await execute_thought()

func cancel_pending_schedule() -> void:
	_schedule_generation += 1
	_primary_action_scheduled = false
	_reaction_scheduled = false

func _resolve_manual_reactions() -> void:
	while model.has_pending_reaction():
		var pending := model.get_pending_reaction()
		var calling_piece: ModelPiece = pending.get("calling_piece")
		if not is_instance_valid(calling_piece) or calling_piece.color != controlled_color:
			return
		var targets: Array = pending.get("targets", [])
		if targets.is_empty():
			return
		await model.submit_reaction_selection(_choose_reaction_target(calling_piece, targets))


func choose_primary_action(actions: Array[ChessPrimaryAction]) -> ChessPrimaryAction:
	if actions.is_empty():
		return null
	var eligible: Array[ChessPrimaryAction] = actions.filter(_is_acceptable_primary_action)
	if eligible.is_empty():
		return null

	var winning: Array[ChessPrimaryAction] = eligible.filter(_is_immediate_win)
	if not winning.is_empty():
		eligible = winning
	elif king_safety_turns_remaining > 0:
		var safest_threat_count := 999
		var safest: Array[ChessPrimaryAction] = []
		for action in eligible:
			var threat_count := _projected_king_threat_count(action)
			if threat_count < safest_threat_count:
				safest_threat_count = threat_count
				safest.assign([action])
			elif threat_count == safest_threat_count:
				safest.append(action)
		eligible = safest

	var best_score := -INF
	var best_actions: Array[ChessPrimaryAction] = []
	for action in eligible:
		var score := _score_primary_action(action)
		if score > best_score:
			best_score = score
			best_actions.assign([action])
		elif is_equal_approx(score, best_score):
			best_actions.append(action)

	return best_actions[rng.randi_range(0, best_actions.size() - 1)]


func _is_acceptable_primary_action(action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return true
	if action.piece is MinotaurKing:
		var occupant: ModelPiece = model.board[action.target.x][action.target.y]
		return occupant == null or occupant.color != action.piece.color
	if action.piece is NecromancerKing:
		return not _is_doomed_bone_pawn_square(action.piece.color, action.target)
	return true


func _is_immediate_win(action: ChessPrimaryAction) -> bool:
	var target := _get_target_piece(action)
	if target == null or not target.is_king or target.color == action.piece.color:
		return false
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		return target.current_hp <= action.piece.attack_power
	if action.piece is ArakneKing:
		return target.current_hp <= ArakneKing.SPIKE_BURST_DAMAGE
	if action.piece is MinotaurKing:
		return target.current_hp <= 2
	return false


func _score_primary_action(action: ChessPrimaryAction) -> float:
	var score := 0.0
	var target_piece := _get_target_piece(action)
	if target_piece != null and target_piece.color != action.piece.color:
		score += _get_piece_value(target_piece)
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		score += 0.25
	elif action.kind == ChessPrimaryAction.Kind.MOVE:
		score += _score_movement_path(action.piece, action.path)
	return score


## Future terrain evaluators can override or extend this without collapsing
## routes that share a destination but cross different intermediate squares.
func _score_movement_path(piece: ModelPiece, path: Array[Vector2i]) -> float:
	var score := 0.0
	for step in path:
		score += _score_landing(piece, step)
	return score


func _score_landing(_piece: ModelPiece, _coordinate: Vector2i) -> float:
	return 0.0


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


func _projected_king_threat_count(action: ChessPrimaryAction) -> int:
	var board := _project_board_after(action)
	var king_coordinate := Vector2i(-1, -1)
	for coordinate in board:
		var occupant = board[coordinate]
		if occupant is ModelPiece and occupant.is_king and occupant.color == controlled_color:
			king_coordinate = coordinate
			break
	if king_coordinate.x < 0:
		return 999

	var threats := 0
	for coordinate in board:
		var piece = board[coordinate]
		if not piece is ModelPiece or piece.color == controlled_color:
			continue
		if _piece_attacks_square(piece, coordinate, king_coordinate, board):
			threats += 1
			continue
		if piece is ArakneKing and piece.is_active_ability_ready() and _is_adjacent(coordinate, king_coordinate):
			threats += 1
		elif piece is MinotaurKing and piece.is_active_ability_ready() and _charge_attacks_square(coordinate, king_coordinate, board):
			threats += 1
	return threats


func _project_board_after(action: ChessPrimaryAction) -> Dictionary:
	var projected := {}
	for row in range(model.board.size()):
		for column in range(model.board[row].size()):
			var piece: ModelPiece = model.board[row][column]
			if piece != null:
				projected[Vector2i(row, column)] = piece

	var origin := action.piece.coordinate
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		var defender: ModelPiece = model.board[action.target.x][action.target.y]
		# Durable defenders take damage without yielding their square, so the
		# attacker does not change the board's threat geometry.
		if defender != null and defender.color != action.piece.color and defender.current_hp > action.piece.attack_power:
			return projected
		projected.erase(origin)
		if defender != null:
			projected.erase(action.target)
		elif action.piece.type == "pawn" and origin.y != action.target.y:
			projected.erase(Vector2i(origin.x, action.target.y))
		projected[action.target] = action.piece
		if action.piece is KingPiece and origin.x == action.target.x and absi(origin.y - action.target.y) == 2:
			var rook_origin := Vector2i(origin.x, 0 if action.target.y == 2 else 7)
			var rook_target := Vector2i(origin.x, 3 if action.target.y == 2 else 5)
			if projected.has(rook_origin):
				projected[rook_target] = projected[rook_origin]
				projected.erase(rook_origin)
		return projected

	if action.piece is ArakneKing:
		var spike_target: ModelPiece = model.board[action.target.x][action.target.y]
		if spike_target != null and spike_target.current_hp <= ArakneKing.SPIKE_BURST_DAMAGE:
			projected.erase(action.target)
	elif action.piece is MinotaurKing:
		var charge_target: ModelPiece = model.board[action.target.x][action.target.y]
		var destination := action.target
		if charge_target != null and charge_target.max_hp > 1:
			var direction := Vector2i(signi(action.target.x - origin.x), signi(action.target.y - origin.y))
			destination -= direction
			if charge_target.current_hp <= 2:
				projected.erase(action.target)
		elif charge_target != null:
			projected.erase(action.target)
		projected.erase(origin)
		projected[destination] = action.piece
	elif action.piece is NecromancerKing:
		# Only occupancy and allegiance matter for threat rays; avoid constructing
		# a live ModelPiece merely to represent the prospective blocker.
		projected[action.target] = {"color": action.piece.color}
	return projected


func _piece_attacks_square(piece: ModelPiece, origin: Vector2i, target: Vector2i, board: Dictionary) -> bool:
	var delta := target - origin
	match piece.type:
		"pawn", "bone_pawn":
			var direction := -1 if piece.color == "white" else 1
			return delta.x == direction and absi(delta.y) == 1
		"knight":
			return Vector2i(absi(delta.x), absi(delta.y)) in [Vector2i(1, 2), Vector2i(2, 1)]
		"rook":
			return (delta.x == 0 or delta.y == 0) and _ray_is_clear(origin, target, board)
		"bishop":
			return absi(delta.x) == absi(delta.y) and _ray_is_clear(origin, target, board)
		"queen":
			return (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y)) and _ray_is_clear(origin, target, board)
		_:
			return piece is KingPiece and _is_adjacent(origin, target)


func _ray_is_clear(origin: Vector2i, target: Vector2i, board: Dictionary) -> bool:
	var delta := target - origin
	if delta == Vector2i.ZERO:
		return false
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var coordinate := origin + step
	while coordinate != target:
		if board.has(coordinate):
			return false
		coordinate += step
	return true


func _charge_attacks_square(origin: Vector2i, target: Vector2i, board: Dictionary) -> bool:
	var delta := target - origin
	if delta.x != 0 and delta.y != 0:
		return false
	var distance := maxi(absi(delta.x), absi(delta.y))
	if distance < 3:
		return false
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var coordinate := origin + step
	while coordinate != target:
		if board.has(coordinate):
			return false
		coordinate += step
	return true


func _is_adjacent(first: Vector2i, second: Vector2i) -> bool:
	var delta := second - first
	return delta != Vector2i.ZERO and absi(delta.x) <= 1 and absi(delta.y) <= 1


func _is_doomed_bone_pawn_square(color: String, coordinate: Vector2i) -> bool:
	return coordinate.x == model.get_back_rank(model.get_other_color(color))


func _choose_reaction_target(calling_piece: ModelPiece, targets: Array) -> Vector2i:
	var choices := targets
	if calling_piece is NecromancerKing:
		var safe := targets.filter(func(target): return not _is_doomed_bone_pawn_square(calling_piece.color, target))
		if not safe.is_empty():
			choices = safe
	return choices[rng.randi_range(0, choices.size() - 1)]


func _schedule_primary_action() -> void:
	if _primary_action_scheduled or not is_enabled or execution_mode != ExecutionMode.AUTO:
		return
	_primary_action_scheduled = true
	var generation := _schedule_generation
	call_deferred("_take_primary_action", generation)


func _take_primary_action(generation: int = -1) -> void:
	_primary_action_scheduled = false
	if (
		execution_mode != ExecutionMode.AUTO
		or (generation >= 0 and generation != _schedule_generation)
		or model == null
		or model.battle_over
		or model.action_in_progress
		or model.has_pending_reaction()
		or model.current_turn != controlled_color
	):
		return

	if think() == null:
		return
	await execute_thought()


func _schedule_reaction() -> void:
	if _reaction_scheduled or not is_enabled or execution_mode != ExecutionMode.AUTO:
		return
	_reaction_scheduled = true
	call_deferred("_take_reaction")


func _take_reaction() -> void:
	_reaction_scheduled = false
	if not is_enabled or model == null or model.battle_over or not model.has_pending_reaction():
		return

	var pending := model.get_pending_reaction()
	var calling_piece: ModelPiece = pending.get("calling_piece")
	if not is_instance_valid(calling_piece) or calling_piece.color != controlled_color:
		return
	var targets: Array = pending.get("targets", [])
	if targets.is_empty():
		return

	var target := _choose_reaction_target(calling_piece, targets)
	await model.submit_reaction_selection(target)


func _on_action_finished() -> void:
	_schedule_primary_action()


func _on_action_cancelled() -> void:
	_schedule_primary_action()


func _on_forced_pass_sequence_finished() -> void:
	_schedule_primary_action()


func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, _targets: Array) -> void:
	if execution_mode == ExecutionMode.AUTO and calling_piece.color == controlled_color:
		_schedule_reaction()


func _on_piece_damaged(piece: ModelPiece, _amount: int, current_hp: int, _max_hp: int) -> void:
	if piece.is_king and piece.color == controlled_color and current_hp > 0:
		king_safety_turns_remaining = 3
		_king_safety_revision += 1
		clear_thought()


func _on_battle_finished(_winner_color: String) -> void:
	_primary_action_scheduled = false
	_reaction_scheduled = false
	king_safety_turns_remaining = 0
	_king_safety_revision += 1
