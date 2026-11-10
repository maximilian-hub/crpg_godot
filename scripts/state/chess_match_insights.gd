extends Node
class_name ChessMatchInsights

## Match-long counters and pure position analysis for the optional diagnostic HUD.
## "Check" means that an opposing legal action can damage the King now.
## "Checkmate" means every legal response still lets the opponent damage the
## King on its immediately following turn. The pure rules simulation includes
## active abilities, reactions, autonomous entities, and turn-entry effects.

signal changed(snapshot: Dictionary)

const COLORS := ["white", "black"]
const CENTER_SQUARES := [
	Vector2i(4, 3), # d4
	Vector2i(4, 4), # e4
	Vector2i(3, 3), # d5
	Vector2i(3, 4), # e5
]
const MATERIAL_VALUES := {
	&"pawn": 1,
	&"bone_pawn": 1,
	&"knight": 3,
	&"bishop": 3,
	&"rook": 5,
	&"queen": 9,
}

var model: ChessBoardModel
var ability_uses := {"white": 0, "black": 0}
var checks_received := {"white": 0, "black": 0}
var mate_threats_received := {"white": 0, "black": 0}
var ready_turns_unused := {"white": 0, "black": 0}
var center_control_streak := 0
var center_controller := ""

var _pending_action: Dictionary = {}
var _turn_started_ready := {"white": false, "black": false}
var _position_metrics: Dictionary = {}


func configure(value: ChessBoardModel) -> void:
	if model == value:
		return
	_disconnect_model()
	model = value
	if model == null:
		return
	model.primary_action_committed.connect(_on_primary_action_committed)
	model.settled_action_completed.connect(_on_settled_action_completed)
	model.board_rebuilt.connect(_on_board_rebuilt)
	reset()


func reset() -> void:
	ability_uses = {"white": 0, "black": 0}
	checks_received = {"white": 0, "black": 0}
	mate_threats_received = {"white": 0, "black": 0}
	ready_turns_unused = {"white": 0, "black": 0}
	center_control_streak = 0
	center_controller = ""
	_pending_action.clear()
	_turn_started_ready = {"white": false, "black": false}
	if model != null:
		_turn_started_ready[model.current_turn] = _king_ability_ready(model.current_turn)
	_refresh_position(false)
	_count_turn_entry_threats()
	changed.emit(snapshot())


func snapshot() -> Dictionary:
	return {
		"material": _position_metrics.get("material", _empty_side_metric()),
		"center": _position_metrics.get("center", _empty_side_metric()),
		"center_controller": center_controller,
		"center_control_streak": center_control_streak,
		"ability_uses": ability_uses.duplicate(),
		"checks_received": checks_received.duplicate(),
		"mate_threats_received": mate_threats_received.duplicate(),
		"ready_turns_unused": ready_turns_unused.duplicate(),
		"in_check": _position_metrics.get("in_check", {"white": false, "black": false}),
		"in_checkmate": _position_metrics.get("in_checkmate", {"white": false, "black": false}),
	}


func _on_primary_action_committed(descriptor: Dictionary) -> void:
	_pending_action = descriptor.duplicate(true)


func _on_settled_action_completed() -> void:
	if not _pending_action.is_empty():
		var owner := String(_pending_action.get("color", ""))
		if owner in COLORS:
			var used_ability := int(_pending_action.get("kind", -1)) == ChessPrimaryAction.Kind.ACTIVE_ABILITY
			if used_ability:
				ability_uses[owner] = int(ability_uses[owner]) + 1
			elif bool(_turn_started_ready.get(owner, false)):
				ready_turns_unused[owner] = int(ready_turns_unused[owner]) + 1
	_pending_action.clear()
	_refresh_position(true)
	_count_turn_entry_threats()
	_turn_started_ready[model.current_turn] = _king_ability_ready(model.current_turn)
	changed.emit(snapshot())


func _on_board_rebuilt(_board: Array) -> void:
	reset()


func _refresh_position(advance_center_streak: bool) -> void:
	if model == null:
		_position_metrics = {}
		return
	var imported := ClassicChessCore.import_position(model.capture_position())
	if not bool(imported.get("ok", false)):
		_position_metrics = {}
		return
	var state: ChessCoreState = imported.state
	var material := material_counts(state)
	var center := center_counts(state)
	var next_controller := leading_color(center)
	if advance_center_streak:
		if next_controller.is_empty():
			center_controller = ""
			center_control_streak = 0
		elif next_controller == center_controller:
			center_control_streak += 1
		else:
			center_controller = next_controller
			center_control_streak = 1
	else:
		center_controller = next_controller
		center_control_streak = 0
	var in_check := {"white": false, "black": false}
	var in_mate := {"white": false, "black": false}
	if not state.battle_over and state.current_turn in COLORS:
		in_check[state.current_turn] = is_king_in_check(state, state.current_turn)
		in_mate[state.current_turn] = is_king_mate_threatened(state, state.current_turn)
	_position_metrics = {
		"material": material,
		"center": center,
		"in_check": in_check,
		"in_checkmate": in_mate,
	}


func _count_turn_entry_threats() -> void:
	if model == null or model.battle_over or model.current_turn not in COLORS:
		return
	var color := model.current_turn
	var in_check: Dictionary = _position_metrics.get("in_check", {})
	var in_mate: Dictionary = _position_metrics.get("in_checkmate", {})
	if bool(in_check.get(color, false)):
		checks_received[color] = int(checks_received[color]) + 1
	if bool(in_mate.get(color, false)):
		mate_threats_received[color] = int(mate_threats_received[color]) + 1


func _king_ability_ready(color: String) -> bool:
	if model == null:
		return false
	var king := model.get_king(color) as KingPiece
	return king != null and king.has_active_ability() and king.is_active_ability_ready()


func _disconnect_model() -> void:
	if model == null:
		return
	if model.primary_action_committed.is_connected(_on_primary_action_committed):
		model.primary_action_committed.disconnect(_on_primary_action_committed)
	if model.settled_action_completed.is_connected(_on_settled_action_completed):
		model.settled_action_completed.disconnect(_on_settled_action_completed)
	if model.board_rebuilt.is_connected(_on_board_rebuilt):
		model.board_rebuilt.disconnect(_on_board_rebuilt)


static func material_counts(state: ChessCoreState) -> Dictionary:
	var result := {"white": 0, "black": 0}
	if state == null:
		return result
	for piece in state.pieces:
		if piece.color in COLORS and not piece.is_king():
			result[piece.color] = int(result[piece.color]) + int(MATERIAL_VALUES.get(piece.type_id, 1))
	return result


static func center_counts(state: ChessCoreState) -> Dictionary:
	var result := {"white": 0, "black": 0}
	if state == null:
		return result
	for coordinate in CENTER_SQUARES:
		var piece := state.occupant(coordinate)
		if piece != null and piece.color in COLORS:
			result[piece.color] = int(result[piece.color]) + 1
	return result


static func leading_color(counts: Dictionary) -> String:
	var white := int(counts.get("white", 0))
	var black := int(counts.get("black", 0))
	if white == black:
		return ""
	return "white" if white > black else "black"


static func is_king_in_check(state: ChessCoreState, king_color: String) -> bool:
	if state == null or state.battle_over or _king_in_state(state, king_color) == null:
		return false
	var attacker := _other_color(king_color)
	var attack_turn := state.copy()
	attack_turn.current_turn = attacker
	attack_turn.resolution_context.clear()
	attack_turn.pending_choice = null
	for action in ClassicChessCore.analysis_actions(attack_turn, attacker):
		if _action_can_damage_king(attack_turn, action, king_color):
			return true
	return false


static func is_king_mate_threatened(state: ChessCoreState, king_color: String) -> bool:
	if (
		state == null
		or state.battle_over
		or state.current_turn != king_color
		or _king_in_state(state, king_color) == null
	):
		return false
	var responses := ClassicChessCore.legal_actions(state, king_color)
	if responses.is_empty():
		return _forced_pass_leaves_damage_inevitable(state, king_color)
	for response in responses:
		var result := ClassicChessCore.resolve_action(state, response, false)
		for outcome in _settled_outcomes(result):
			var king := _king_in_state(outcome, king_color)
			if king != null and not outcome.battle_over and not _opponent_can_damage_king(outcome, king_color):
				return false
			if king != null and outcome.battle_over and outcome.battle_result == king_color:
				return false
	return true


static func _forced_pass_leaves_damage_inevitable(state: ChessCoreState, king_color: String) -> bool:
	var result := ClassicChessCore.resolve_forced_passes(state, false)
	var outcomes := _settled_outcomes(result)
	if outcomes.is_empty():
		return false
	for outcome in outcomes:
		var king := _king_in_state(outcome, king_color)
		if king != null and not outcome.battle_over and not _opponent_can_damage_king(outcome, king_color):
			return false
		if king != null and outcome.battle_over and outcome.battle_result == king_color:
			return false
	return true


static func _opponent_can_damage_king(state: ChessCoreState, king_color: String) -> bool:
	var king := _king_in_state(state, king_color)
	if king == null:
		return true
	if state.battle_over:
		return false
	var attacker := _other_color(king_color)
	if state.current_turn != attacker:
		return false
	var actions := ClassicChessCore.legal_actions(state, attacker)
	if actions.is_empty():
		var passed := ClassicChessCore.resolve_forced_passes(state, false)
		for outcome in _settled_outcomes(passed):
			if _king_took_damage(state, outcome, king_color):
				return true
		return false
	for action in actions:
		if _action_can_damage_king(state, action, king_color):
			return true
	return false


static func _action_can_damage_king(state: ChessCoreState, action: ChessCoreAction, king_color: String) -> bool:
	var result := ClassicChessCore.resolve_action(state, action, false)
	for outcome in _settled_outcomes(result):
		if _king_took_damage(state, outcome, king_color):
			return true
	return false


static func _king_took_damage(before: ChessCoreState, after: ChessCoreState, king_color: String) -> bool:
	var original := _king_in_state(before, king_color)
	if original == null:
		return false
	var resolved := after.piece_by_id(original.piece_id) if after != null else null
	return resolved == null or resolved.current_hp < original.current_hp


static func _settled_outcomes(result: ChessCoreStepResult) -> Array[ChessCoreState]:
	var outcomes: Array[ChessCoreState] = []
	if result == null or result.status in [ChessCoreStepResult.Status.REJECTED, ChessCoreStepResult.Status.UNSUPPORTED]:
		return outcomes
	if result.status == ChessCoreStepResult.Status.COMPLETED:
		outcomes.append(result.state)
		return outcomes
	if result.status != ChessCoreStepResult.Status.PENDING_CHOICE or result.choice == null:
		return outcomes
	for option in result.choice.options:
		var resolved := ClassicChessCore.resolve_choice(result.state, option, false)
		outcomes.append_array(_settled_outcomes(resolved))
	return outcomes


static func _king_in_state(state: ChessCoreState, color: String) -> ChessCorePiece:
	if state == null:
		return null
	for piece in state.pieces:
		if piece.color == color and piece.is_king():
			return piece
	return null


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"


static func _empty_side_metric() -> Dictionary:
	return {"white": 0, "black": 0}
