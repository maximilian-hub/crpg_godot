extends Node
class_name ChessCpuPlayer

const ChessAiThoughtData = preload("res://scripts/ai/chess_ai_thought.gd")
const RyckBrain = preload("res://scripts/ai/ryck_ai_brain.gd")
const LeMayBrain = preload("res://scripts/ai/lemay_ai_brain.gd")
const DupreBrain = preload("res://scripts/ai/dupre_ai_brain.gd")

const RHETORICIAN_CLOSE_THREAT_REWARD := 12.0
const RHETORICIAN_BACK_UP_PENALTY := 16.0
const RHETORICIAN_PULL_THREAT_REWARD := 14.0
const RHETORICIAN_PULL_ALLY_ATTACK_BONUS := 8.0
const RHETORICIAN_KNIGHT_CAPTURE_BONUS := 5.0
const QUARTERLY_FREE_CYCLE_REWARD := 24.0
const QUARTERLY_OFF_CYCLE_COST := 12.0
const QUARTERLY_MIN_HP_SACRIFICE_ROUND := 15
const QUARTERLY_PAWN_UPGRADE_REWARD := 8.0
const QUARTERLY_QUEEN_HYBRID_REWARD := 11.0
const QUARTERLY_UNPROTECTED_TARGET_REWARD := 12.0
const QUARTERLY_KING_TARGET_REWARD := 40.0
const MORTAR_DISTANT_URGENCY := 2.0
const MORTAR_NEAR_URGENCY := 8.0
const MORTAR_IMMINENT_URGENCY := 40.0
const MORTAR_LETHAL_MULTIPLIER := 2.5

signal thought_changed(thought)

## Headless client that chooses actions for one color and submits Model commands.

@export var model: ChessBoardModel

enum ExecutionMode { DISABLED, AUTO, MANUAL }
enum BrainKind { RYCK, LEMAY, DUPRE }

var controlled_color: String = "black"
var is_enabled: bool = false
var execution_mode := ExecutionMode.DISABLED
var brain_kind := BrainKind.RYCK
var brain: ChessAiBrain
var rng := RandomNumberGenerator.new()
var last_thought
var last_pre_decision_context: Dictionary = {}
var king_safety_turns_remaining := 0
var _king_safety_revision := 0

var _primary_action_scheduled: bool = false
var _reaction_scheduled: bool = false
var _schedule_generation: int = 0


func _ready() -> void:
	rng.randomize()
	_set_brain_instance()
	if model == null:
		return
	model.action_finished.connect(_on_action_finished)
	model.board_rebuilt.connect(_on_board_rebuilt)
	model.action_cancelled.connect(_on_action_cancelled)
	model.forced_pass_sequence_finished.connect(_on_forced_pass_sequence_finished)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.battle_finished.connect(_on_battle_finished)
	model.piece_damaged.connect(_on_piece_damaged)
	model.movement_type_selection_requested.connect(_on_movement_type_selection_requested)


func configure(enabled: bool, color: String) -> void:
	configure_mode(ExecutionMode.AUTO if enabled else ExecutionMode.DISABLED, color)

func configure_mode(mode: ExecutionMode, color: String) -> void:
	var side_changed := controlled_color != color
	execution_mode = mode
	is_enabled = mode != ExecutionMode.DISABLED
	controlled_color = color if color == "white" else "black"
	_primary_action_scheduled = false
	_reaction_scheduled = false
	_schedule_generation += 1
	king_safety_turns_remaining = 0
	_king_safety_revision += 1
	clear_thought()
	if brain != null and side_changed:
		brain.reset_session(&"side_changed")
	if execution_mode == ExecutionMode.AUTO:
		_schedule_primary_action()


func set_brain(kind: BrainKind) -> void:
	brain_kind = kind
	_set_brain_instance()
	clear_thought()


func get_brain_name() -> String:
	match brain_kind:
		BrainKind.LEMAY: return "LeMay"
		BrainKind.DUPRE: return "Dupre"
		_: return "Ryck"


func _set_brain_instance() -> void:
	match brain_kind:
		BrainKind.LEMAY: brain = LeMayBrain.new(self)
		BrainKind.DUPRE: brain = DupreBrain.new(self)
		_: brain = RyckBrain.new(self)


func set_random_seed(value: int) -> void:
	rng.seed = value
	clear_thought()

func think():
	clear_thought()
	if not is_enabled or execution_mode == ExecutionMode.DISABLED or model == null or model.battle_over or not model.is_settled() or model.current_turn != controlled_color:
		return null
	if brain == null:
		_set_brain_instance()
	# Capture this before candidate ordering/search advances the RNG or mutates a
	# stateful brain, so an exported decision can be reproduced faithfully.
	last_pre_decision_context = capture_debug_context()
	var thinking_brain := brain
	var starting_revision := model.position_revision
	var plan: ChessAiPlan = await thinking_brain.choose_plan(model.get_legal_primary_actions(controlled_color))
	if thinking_brain != brain or model == null or model.position_revision != starting_revision:
		return null
	if plan == null or plan.action == null:
		return null
	var action := plan.action
	var thought = ChessAiThoughtData.new()
	thought.model_revision = model.position_revision
	thought.color = controlled_color
	thought.action_kind = action.kind
	thought.piece_coordinate = action.piece.coordinate
	thought.piece_type_id = action.piece.get_position_type_id()
	thought.target = action.target
	thought.path.assign(action.path)
	thought.score = plan.score
	thought.brain_id = plan.brain_id
	thought.analyzed_leaf_count = plan.analyzed_leaf_count
	thought.search_profile = plan.search_profile.duplicate(true)
	thought.candidates = plan.candidates.duplicate(true)
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


func capture_debug_context() -> Dictionary:
	return {
		"brain": get_brain_name(), "brain_kind": brain_kind, "color": controlled_color,
		"rng_state": str(rng.state), "king_safety_turns": king_safety_turns_remaining,
		"brain_state": brain.capture_debug_state() if brain != null else {},
	}

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
	var executed_origin := matching.piece.coordinate
	var consumes_safety_turn := king_safety_turns_remaining > 0
	var accepted: bool
	if matching.kind == ChessPrimaryAction.Kind.MOVE:
		if matching.path.size() > 1:
			accepted = await model.submit_move_path(matching.piece, matching.path)
		else:
			accepted = await model.submit_move(matching.piece, matching.target)
	elif matching.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		accepted = await model.submit_active_ability(matching.piece as KingPiece, matching.target)
	else:
		accepted = await model.submit_archer_charge(matching.piece as ArcherKing)
	if accepted and consumes_safety_turn and safety_revision_before_action == _king_safety_revision:
		king_safety_turns_remaining -= 1
	if accepted and brain != null:
		brain.on_action_executed(matching, executed_origin)
	if accepted and execution_mode == ExecutionMode.MANUAL:
		await _resolve_manual_reactions()
	return accepted

func step() -> bool:
	if await think() == null:
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
	if action.piece is WraithKing:
		return _wraith_summon_is_tactically_available(action.piece as WraithKing)
	if action.piece is MinotaurKing:
		var occupant: ModelPiece = model.board[action.target.x][action.target.y]
		return occupant == null or occupant.color != action.piece.color
	if action.piece is NecromancerKing:
		return not _is_doomed_bone_pawn_square(action.piece.color, action.target)
	if action.piece is QuarterlyInitiativeKing:
		var quarterly := action.piece as QuarterlyInitiativeKing
		if model.global_turn_number % 4 != 0:
			if model.global_turn_number < QUARTERLY_MIN_HP_SACRIFICE_ROUND or quarterly.current_hp <= 2:
				return false
		var recipient: ModelPiece = model.board[action.target.x][action.target.y]
		if recipient == null:
			return false
		var options := _quarterly_options_for_current_cycle(recipient, [&"pawn", &"knight", &"bishop", &"rook"])
		return _best_quarterly_grant(recipient, options).score > -INF
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
	elif action.kind == ChessPrimaryAction.Kind.ARCHER_CHARGE:
		score += 2.0
	elif action.kind == ChessPrimaryAction.Kind.MOVE:
		score += _score_movement_path(action.piece, action.path)
	score += _score_arc_mortar_safety(action)
	var friendly_king := model.get_king(controlled_color)
	if friendly_king is RhetoricianKing:
		score += _score_rhetorician_action(action, friendly_king as RhetoricianKing, target_piece)
	elif friendly_king is QuarterlyInitiativeKing and action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.piece == friendly_king and target_piece != null:
		score += _score_quarterly_action(target_piece)
	return score


func _score_arc_mortar_safety(action: ChessPrimaryAction) -> float:
	if model.autonomous_entities.is_empty():
		return 0.0
	var current_exposure := _arc_mortar_exposure(_current_board_state())
	var projected_exposure := _arc_mortar_exposure(_project_board_after(action))
	return current_exposure - projected_exposure


func _arc_mortar_exposure(board: Dictionary) -> float:
	var exposure := 0.0
	for entity in model.autonomous_entities:
		if entity.type_id != &"arc_mortar":
			continue
		var landing_turn := int(entity.custom_state.get("landing_turn", model.global_turn_number + CannonKing.ARC_MORTAR_DELAY_ROUNDS))
		var rounds_remaining := maxi(1, landing_turn - model.global_turn_number)
		var urgency := MORTAR_DISTANT_URGENCY
		if rounds_remaining == 1:
			urgency = MORTAR_IMMINENT_URGENCY
		elif rounds_remaining == 2:
			urgency = MORTAR_NEAR_URGENCY
		for coordinate in model.get_mortar_area(entity.coordinate):
			var occupant = board.get(coordinate)
			if not occupant is ModelPiece or occupant.color != controlled_color:
				continue
			var piece := occupant as ModelPiece
			var piece_exposure := _get_piece_value(piece) * urgency
			if piece.current_hp <= CannonKing.ARC_MORTAR_DAMAGE:
				piece_exposure *= MORTAR_LETHAL_MULTIPLIER
			exposure += piece_exposure
	return exposure


func _score_quarterly_action(recipient: ModelPiece) -> float:
	var options := _quarterly_options_for_current_cycle(recipient, [&"pawn", &"knight", &"bishop", &"rook"])
	var best := _best_quarterly_grant(recipient, options)
	if float(best.score) == -INF:
		return -INF
	var cycle_score := QUARTERLY_FREE_CYCLE_REWARD if model.global_turn_number % 4 == 0 else -QUARTERLY_OFF_CYCLE_COST
	return cycle_score + float(best.score)


func _quarterly_options_for_current_cycle(recipient: ModelPiece, options: Array) -> Array:
	if model.global_turn_number % 4 == 0:
		return options
	return _quarterly_sacrifice_worthy_options(recipient, options)


func _quarterly_sacrifice_worthy_options(recipient: ModelPiece, options: Array) -> Array[StringName]:
	var worthy: Array[StringName] = []
	for raw_option in options:
		var option := StringName(raw_option)
		if _quarterly_grant_is_sacrifice_worthy(recipient, option):
			worthy.append(option)
	return worthy


func _quarterly_grant_is_sacrifice_worthy(recipient: ModelPiece, movement_type: StringName) -> bool:
	if _quarterly_grant_is_redundant(recipient, movement_type):
		return false
	var native_moves: Array = recipient.get_legal_moves()
	var board := _current_board_state()
	var qualifying_fork_targets := 0
	for destination in model._get_moves_as(recipient, movement_type):
		if destination in native_moves:
			continue
		var target: ModelPiece = model.board[destination.x][destination.y]
		if target == null or target.color == recipient.color:
			continue
		if target.is_king:
			return true
		if target.type in ["queen", "rook"] or (target.type in ["bishop", "knight"] and not _piece_is_protected(target, board)):
			qualifying_fork_targets += 1
			if qualifying_fork_targets >= 2:
				return true
	return false


func _best_quarterly_grant(recipient: ModelPiece, options: Array) -> Dictionary:
	var best_score := -INF
	var best_options: Array[StringName] = []
	for raw_option in options:
		var option := StringName(raw_option)
		var score := _score_quarterly_grant(recipient, option)
		if score > best_score:
			best_score = score
			best_options.assign([option])
		elif is_equal_approx(score, best_score):
			best_options.append(option)
	return {"score": best_score, "options": best_options}


func _score_quarterly_grant(recipient: ModelPiece, movement_type: StringName) -> float:
	if _quarterly_grant_is_redundant(recipient, movement_type):
		return -INF
	var score := 1.0
	if recipient.type == "pawn":
		score += QUARTERLY_PAWN_UPGRADE_REWARD
	elif (recipient.type == "rook" and movement_type == &"bishop") or (recipient.type == "bishop" and movement_type == &"rook"):
		score += QUARTERLY_QUEEN_HYBRID_REWARD

	var native_moves: Array = recipient.get_legal_moves()
	var board := _current_board_state()
	for destination in model._get_moves_as(recipient, movement_type):
		if destination in native_moves:
			continue
		var target: ModelPiece = model.board[destination.x][destination.y]
		if target == null or target.color == recipient.color:
			continue
		if target.is_king:
			score += QUARTERLY_KING_TARGET_REWARD
		elif not _piece_is_protected(target, board):
			score += QUARTERLY_UNPROTECTED_TARGET_REWARD + _get_piece_value(target)
		else:
			score += _get_piece_value(target) * 0.5
	return score


func _quarterly_grant_is_redundant(recipient: ModelPiece, movement_type: StringName) -> bool:
	if movement_type in recipient.granted_movement_types:
		return true
	match movement_type:
		&"pawn":
			return recipient.type == "pawn"
		&"knight":
			return recipient.type == "knight"
		&"bishop":
			return recipient.type in ["bishop", "queen"]
		&"rook":
			return recipient.type in ["rook", "queen"]
	return true


func _piece_is_protected(piece: ModelPiece, board: Dictionary) -> bool:
	for coordinate in board:
		var defender = board[coordinate]
		if defender is ModelPiece and defender != piece and defender.color == piece.color:
			if _piece_attacks_square(defender, coordinate, piece.coordinate, board):
				return true
	return false


func _score_rhetorician_action(action: ChessPrimaryAction, king: RhetoricianKing, target_piece: ModelPiece) -> float:
	var score := 0.0
	if action.kind == ChessPrimaryAction.Kind.MOVE and target_piece != null and target_piece.color != controlled_color and target_piece.type == "knight":
		score += RHETORICIAN_KNIGHT_CAPTURE_BONUS

	var current_board := _current_board_state()
	if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece == king:
		var destination := action.target
		var projected := _project_board_after(action)
		for coordinate in current_board:
			var enemy = current_board[coordinate]
			if not enemy is ModelPiece or enemy.color == controlled_color:
				continue
			var old_distance := _grid_distance(coordinate, king.coordinate)
			var new_distance := _grid_distance(coordinate, destination)
			if old_distance == 2 and _piece_attacks_square(enemy, coordinate, king.coordinate, current_board):
				if new_distance == 1 and projected.has(coordinate):
					score += RHETORICIAN_CLOSE_THREAT_REWARD
			if old_distance == 1 and enemy.type in ["queen", "rook", "bishop"] and new_distance == 2:
				score -= RHETORICIAN_BACK_UP_PENALTY

	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and action.piece == king and target_piece != null:
		var target_origin := target_piece.coordinate
		if _grid_distance(target_origin, king.coordinate) == 2 and _piece_attacks_square(target_piece, target_origin, king.coordinate, current_board):
			score += RHETORICIAN_PULL_THREAT_REWARD
			var delta := king.coordinate - target_origin
			var pulled_coordinate := target_origin + Vector2i(signi(delta.x), signi(delta.y))
			var projected := _project_board_after(action)
			if _friendly_nonking_attacks_square(pulled_coordinate, projected, king):
				score += RHETORICIAN_PULL_ALLY_ATTACK_BONUS
	return score


func _friendly_nonking_attacks_square(target: Vector2i, board: Dictionary, king: RhetoricianKing) -> bool:
	for coordinate in board:
		var ally = board[coordinate]
		if ally is ModelPiece and ally.color == controlled_color and ally != king:
			if _piece_attacks_square(ally, coordinate, target, board):
				return true
	return false


func _grid_distance(first: Vector2i, second: Vector2i) -> int:
	var delta := second - first
	return maxi(absi(delta.x), absi(delta.y))


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
	var king: ModelPiece
	for coordinate in board:
		var occupant = board[coordinate]
		if occupant is ModelPiece and occupant.is_king and occupant.color == controlled_color:
			king_coordinate = coordinate
			king = occupant
			break
	if king_coordinate.x < 0:
		return 999
	return _king_threat_count(king, king_coordinate, board)


func _king_threat_count(king: ModelPiece, king_coordinate: Vector2i, board: Dictionary) -> int:
	var threats := 0
	for coordinate in board:
		var piece = board[coordinate]
		if not piece is ModelPiece or piece.color == king.color:
			continue
		if king is RhetoricianKing and _is_adjacent(coordinate, king_coordinate):
			continue
		if _piece_attacks_square(piece, coordinate, king_coordinate, board):
			threats += 1
			continue
		if piece is ArakneKing and piece.is_active_ability_ready() and _is_adjacent(coordinate, king_coordinate):
			threats += 1
		elif piece is MinotaurKing and piece.is_active_ability_ready() and _charge_attacks_square(coordinate, king_coordinate, board):
			threats += 1
	return threats


func _wraith_summon_is_tactically_available(king: WraithKing) -> bool:
	if model.get_wraith_entities_from_source(king.piece_id).size() >= WraithKing.MAX_ACTIVE_WRAITHS:
		return false
	var board := _current_board_state()
	if _king_threat_count(king, king.coordinate, board) > 0:
		return false
	var opposing_king := model.get_king(model.get_other_color(king.color))
	if opposing_king != null and _king_threat_count(opposing_king, opposing_king.coordinate, board) > 0:
		return false
	return true


func _project_board_after(action: ChessPrimaryAction) -> Dictionary:
	var projected := _current_board_state()

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
	elif action.piece is RhetoricianKing:
		var compelled: ModelPiece = model.board[action.target.x][action.target.y]
		if compelled != null:
			var delta := action.piece.coordinate - compelled.coordinate
			var destination := compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))
			if destination != action.piece.coordinate and model.is_in_bounds(destination.x, destination.y):
				projected.erase(compelled.coordinate)
				projected.erase(destination)
				projected[destination] = compelled
	return projected


func _current_board_state() -> Dictionary:
	var result := {}
	for row in range(model.board.size()):
		for column in range(model.board[row].size()):
			var piece: ModelPiece = model.board[row][column]
			if piece != null:
				result[Vector2i(row, column)] = piece
	return result


func _piece_attacks_square(piece: ModelPiece, origin: Vector2i, target: Vector2i, board: Dictionary) -> bool:
	var board_size := Vector2i(model.board.size(), model.board[0].size() if not model.board.is_empty() else 0)
	var position := ChessAttackPosition.from_occupancy(board_size, board)
	return piece.can_directly_attack_square(origin, target, position)


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
	if brain != null:
		var pending := model.get_pending_reaction()
		var preferred = brain.choose_reaction_target(
			model,
			calling_piece,
			String(pending.get("action_type", "")),
			pending.get("event_data"),
			targets
		)
		if preferred is Vector2i and preferred in targets:
			return preferred
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

	if await think() == null:
		return
	if (
		execution_mode != ExecutionMode.AUTO
		or (generation >= 0 and generation != _schedule_generation)
		or model == null
		or model.battle_over
		or model.current_turn != controlled_color
	):
		clear_thought()
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


func _on_board_rebuilt(_board: Array) -> void:
	clear_thought()
	if brain != null:
		brain.reset_session(&"position_replaced")


func _on_action_cancelled() -> void:
	_schedule_primary_action()


func _on_forced_pass_sequence_finished() -> void:
	_schedule_primary_action()


func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, _targets: Array) -> void:
	if execution_mode == ExecutionMode.AUTO and calling_piece.color == controlled_color:
		_schedule_reaction()

func _on_movement_type_selection_requested(king: QuarterlyInitiativeKing, target: ModelPiece, options: Array[StringName]) -> void:
	if execution_mode == ExecutionMode.DISABLED or king.color != controlled_color or options.is_empty():
		return
	var eligible_options := _quarterly_options_for_current_cycle(target, options)
	var best := _best_quarterly_grant(target, eligible_options)
	var best_options: Array = best.options
	if best_options.is_empty():
		return
	call_deferred("_submit_movement_type_choice", best_options[rng.randi_range(0, best_options.size() - 1)])

func _submit_movement_type_choice(choice: StringName) -> void:
	model.submit_movement_type_grant(choice)


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
