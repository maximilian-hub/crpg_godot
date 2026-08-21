extends Node
class_name ChessCpuPlayer

const ChessAiThoughtData = preload("res://scripts/ai/chess_ai_thought.gd")

## Headless client that chooses actions for one color and submits Model commands.

@export var model: ChessBoardModel

enum ExecutionMode { DISABLED, AUTO, MANUAL }

var controlled_color: String = "black"
var is_enabled: bool = false
var execution_mode := ExecutionMode.DISABLED
var rng := RandomNumberGenerator.new()
var last_thought

var _primary_action_scheduled: bool = false
var _reaction_scheduled: bool = false
var _schedule_generation: int = 0


func _ready() -> void:
	rng.randomize()
	if model == null:
		return
	model.action_finished.connect(_on_action_finished)
	model.action_cancelled.connect(_on_action_cancelled)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.battle_finished.connect(_on_battle_finished)


func configure(enabled: bool, color: String) -> void:
	configure_mode(ExecutionMode.AUTO if enabled else ExecutionMode.DISABLED, color)

func configure_mode(mode: ExecutionMode, color: String) -> void:
	execution_mode = mode
	is_enabled = mode != ExecutionMode.DISABLED
	controlled_color = color if color == "white" else "black"
	_primary_action_scheduled = false
	_reaction_scheduled = false
	_schedule_generation += 1
	last_thought = null
	if execution_mode == ExecutionMode.AUTO:
		_schedule_primary_action()


func set_random_seed(value: int) -> void:
	rng.seed = value
	last_thought = null

func think():
	last_thought = null
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
	thought.score = _score_primary_action(action)
	last_thought = thought
	return thought

func get_last_thought():
	return last_thought

func clear_thought() -> void:
	last_thought = null

func execute_thought() -> bool:
	if last_thought == null or model == null or last_thought.model_revision != model.position_revision or model.current_turn != last_thought.color or not model.is_settled():
		return false
	var matching: ChessPrimaryAction = null
	for action in model.get_legal_primary_actions(controlled_color):
		if action.kind == last_thought.action_kind and action.target == last_thought.target and action.piece.coordinate == last_thought.piece_coordinate and action.piece.get_position_type_id() == last_thought.piece_type_id:
			matching = action
			break
	last_thought = null
	if matching == null:
		return false
	var accepted: bool
	if matching.kind == ChessPrimaryAction.Kind.MOVE:
		accepted = await model.submit_move(matching.piece, matching.target)
	else:
		accepted = await model.submit_active_ability(matching.piece as KingPiece, matching.target)
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
		await model.submit_reaction_selection(targets[rng.randi_range(0, targets.size() - 1)])


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


func _score_primary_action(action: ChessPrimaryAction) -> float:
	var score := 0.0
	var target_piece := _get_target_piece(action)
	if target_piece != null and target_piece.color != action.piece.color:
		score += _get_piece_value(target_piece)
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		score += 0.25
	return score


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

	var target: Vector2i = targets[rng.randi_range(0, targets.size() - 1)]
	await model.submit_reaction_selection(target)


func _on_action_finished() -> void:
	_schedule_primary_action()


func _on_action_cancelled() -> void:
	_schedule_primary_action()


func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, _targets: Array) -> void:
	if execution_mode == ExecutionMode.AUTO and calling_piece.color == controlled_color:
		_schedule_reaction()


func _on_battle_finished(_winner_color: String) -> void:
	_primary_action_scheduled = false
	_reaction_scheduled = false
