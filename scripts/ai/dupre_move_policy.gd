extends RefCounted
class_name DupreMovePolicy

const REVERSAL_PENALTY := 4.0
const BACK_RANK_ROOK_SHUFFLE_PENALTY := 1.25
const DEVELOPMENT_REWARD := 2.0
const ROOK_ACTIVITY_REWARD := 1.5
const SAFE_RESCUE_MULTIPLIER := 1.25
const HANGING_DESTINATION_MULTIPLIER := 1.5
const THREAT_MULTIPLIER := 0.6

var player: ChessCpuPlayer
var model: ChessBoardModel
var color: String
var previous_own_actions: Dictionary


func _init(p_player: ChessCpuPlayer, p_previous_own_action: Dictionary = {}) -> void:
	player = p_player
	model = player.model
	color = player.controlled_color
	previous_own_actions = p_previous_own_action


func score(action: ChessPrimaryAction) -> float:
	if player._is_immediate_win(action):
		return 10000.0
	var result := player._score_primary_action(action)
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return result
	var origin := action.piece.coordinate
	var destination := action.target
	var target: ModelPiece = model.board[destination.x][destination.y]
	var quiet := target == null
	var back_rank := model.get_back_rank(action.piece.color)

	if action.piece.type in ["knight", "bishop"] and origin.x == back_rank and destination.x != back_rank:
		result += DEVELOPMENT_REWARD
	elif action.piece.type == "pawn":
		var starting_rank := back_rank - 1 if action.piece.color == "white" else back_rank + 1
		if origin.x == starting_rank:
			result += DEVELOPMENT_REWARD * 0.45
	elif action.piece.type == "rook":
		if origin.x == back_rank and destination.x != back_rank:
			result += ROOK_ACTIVITY_REWARD
		elif quiet and origin.x == back_rank and destination.x == back_rank:
			result -= BACK_RANK_ROOK_SHUFFLE_PENALTY

	if action.piece.type in ["knight", "bishop", "queen"]:
		result += float(_center_distance(origin) - _center_distance(destination)) * 0.2
	if _is_immediate_reversal(action):
		result -= REVERSAL_PENALTY

	var current_board := _occupancy()
	var projected := _project_normal_move(action, current_board)
	var piece_value := _piece_value(action.piece)
	var was_attacked := _square_attacked_by(origin, _other_color(color), current_board)
	var becomes_attacked := _square_attacked_by(destination, _other_color(color), projected)
	if was_attacked and not becomes_attacked and piece_value >= 3.0:
		result += piece_value * SAFE_RESCUE_MULTIPLIER
	elif becomes_attacked and piece_value >= 3.0:
		result -= piece_value * HANGING_DESTINATION_MULTIPLIER

	var best_threat := 0.0
	var attack_position := ChessAttackPosition.from_occupancy(Vector2i(model.board.size(), model.board[0].size()), projected)
	for coordinate in projected:
		var enemy = projected[coordinate]
		if enemy is ModelPiece and enemy.color != color:
			if action.piece.can_directly_attack_square(destination, coordinate, attack_position):
				best_threat = maxf(best_threat, 8.0 if enemy.is_king else _piece_value(enemy))
	result += best_threat * THREAT_MULTIPLIER
	return result


func is_valuable_piece_threatened(piece: ModelPiece) -> bool:
	return not piece.is_king and _piece_value(piece) >= 5.0 and _square_attacked_by(piece.coordinate, _other_color(piece.color), _occupancy())


func _is_immediate_reversal(action: ChessPrimaryAction) -> bool:
	var previous: Dictionary = previous_own_actions.get(action.piece.piece_id, {})
	# Accept the original single-action shape as well; it is useful to isolated
	# policy callers and older serialized prototype fixtures.
	if previous.is_empty() and previous_own_actions.get("piece_id", "") == action.piece.piece_id:
		previous = previous_own_actions
	return (
		not previous.is_empty()
		and action.kind == ChessPrimaryAction.Kind.MOVE
		and previous.get("from", Vector2i(-1, -1)) == action.target
		and previous.get("to", Vector2i(-1, -1)) == action.piece.coordinate
	)


func _project_normal_move(action: ChessPrimaryAction, board: Dictionary) -> Dictionary:
	var result := board.duplicate()
	result.erase(action.piece.coordinate)
	result.erase(action.target)
	if action.piece.type == "pawn" and action.piece.coordinate.y != action.target.y and model.board[action.target.x][action.target.y] == null:
		result.erase(Vector2i(action.piece.coordinate.x, action.target.y))
	result[action.target] = action.piece
	return result


func _square_attacked_by(target: Vector2i, attacker_color: String, board: Dictionary) -> bool:
	var position := ChessAttackPosition.from_occupancy(Vector2i(model.board.size(), model.board[0].size()), board)
	for origin in board:
		var piece = board[origin]
		if piece is ModelPiece and piece.color == attacker_color and not piece.stunned:
			if piece.can_directly_attack_square(origin, target, position):
				return true
	return false


func _occupancy() -> Dictionary:
	var result := {}
	for row in model.board:
		for piece in row:
			if piece != null:
				result[piece.coordinate] = piece
	return result


func _piece_value(piece: ModelPiece) -> float:
	return player._get_piece_value(piece)


func _other_color(value: String) -> String:
	return "black" if value == "white" else "white"


func _center_distance(coordinate: Vector2i) -> int:
	return mini(
		absi(coordinate.x - 3) + absi(coordinate.y - 3),
		absi(coordinate.x - 4) + absi(coordinate.y - 4)
	)
