extends RefCounted
class_name DupreMovePolicy

const REVERSAL_PENALTY := 4.0
const BACK_RANK_ROOK_SHUFFLE_PENALTY := 1.25
const DEVELOPMENT_REWARD := 2.0
const ROOK_ACTIVITY_REWARD := 1.5
const SAFE_RESCUE_MULTIPLIER := 1.25
const HANGING_DESTINATION_MULTIPLIER := 1.5
const THREAT_MULTIPLIER := 0.6
const NEW_KING_THREAT_PENALTY := 10000.0
const EXPOSED_UNDEFENDED_ALLY_MULTIPLIER := 4.0

var player: ChessCpuPlayer
var model: ChessBoardModel
var color: String
var previous_own_actions: Dictionary
var tactical_map: DupreTacticalMap
var _projected_maps: Dictionary = {}


func _init(p_player: ChessCpuPlayer, p_previous_own_action: Dictionary = {}, p_tactical_map: DupreTacticalMap = null) -> void:
	player = p_player
	model = player.model
	color = player.controlled_color
	previous_own_actions = p_previous_own_action
	tactical_map = p_tactical_map if p_tactical_map != null else DupreTacticalMap.from_model(model)


func score(action: ChessPrimaryAction) -> float:
	if player._is_immediate_win(action):
		return 10000.0
	var result := player._score_primary_action(action)
	if action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
		return result
	if creates_new_king_threat(action):
		result -= NEW_KING_THREAT_PENALTY
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

	var projected := projected_map(action)
	var piece_value := _piece_value(action.piece)
	var projected_piece_coordinate := destination if projected.occupancy.get(destination) == action.piece else origin
	var was_attacked := tactical_map.attack_count(origin, _other_color(color)) > 0
	var becomes_attacked := projected.attack_count(projected_piece_coordinate, _other_color(color)) > 0
	if was_attacked and not becomes_attacked and piece_value >= 3.0:
		result += piece_value * SAFE_RESCUE_MULTIPLIER
	elif becomes_attacked and piece_value >= 3.0:
		result -= piece_value * HANGING_DESTINATION_MULTIPLIER

	var best_threat := 0.0
	for coordinate in projected.occupancy:
		var enemy = projected.occupancy[coordinate]
		if enemy is ModelPiece and enemy.color != color:
			if coordinate in projected.attacks_from(action.piece):
				best_threat = maxf(best_threat, 8.0 if enemy.is_king else _piece_value(enemy))
	result += best_threat * THREAT_MULTIPLIER
	result -= newly_exposed_undefended_value(action) * EXPOSED_UNDEFENDED_ALLY_MULTIPLIER
	return result


func creates_new_king_threat(action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return false
	var king: ModelPiece = model.get_king(color)
	if king == null:
		return false
	var projected := projected_map(action)
	var projected_coordinate := action.target if action.piece == king and projected.occupancy.get(action.target) == king else king.coordinate
	var current := tactical_map.attack_count(king.coordinate, _other_color(color))
	return projected.attack_count(projected_coordinate, _other_color(color)) > current


func newly_exposed_undefended_value(action: ChessPrimaryAction) -> float:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return 0.0
	return tactical_map.newly_exposed_undefended_value(projected_map(action), color, _piece_value)


func is_valuable_piece_threatened(piece: ModelPiece) -> bool:
	return not piece.is_king and _piece_value(piece) >= 5.0 and tactical_map.attack_count(piece.coordinate, _other_color(piece.color)) > 0


func projected_map(action: ChessPrimaryAction) -> DupreTacticalMap:
	var key := "%s|%s|%s|%s" % [action.piece.piece_id, action.kind, action.target, action.path]
	if not _projected_maps.has(key):
		_projected_maps[key] = tactical_map.project(player._project_board_after(action))
	return _projected_maps[key]


func direct_king_threat_count_after(action: ChessPrimaryAction) -> int:
	var king: ModelPiece = model.get_king(color)
	if king == null:
		return 0
	var projected := projected_map(action)
	var coordinate := action.target if action.piece == king and projected.occupancy.get(action.target) == king else king.coordinate
	return projected.attack_count(coordinate, _other_color(color))


func capture_material_swing(action: ChessPrimaryAction) -> float:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return 0.0
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null or target.color == color or target.current_hp > action.piece.attack_power:
		return 0.0
	var result := _piece_value(target)
	var projected := projected_map(action)
	if projected.attack_count(action.target, _other_color(color)) > 0:
		result -= _piece_value(action.piece)
	return result


func captures_current_king_attacker(action: ChessPrimaryAction) -> bool:
	if action.kind != ChessPrimaryAction.Kind.MOVE:
		return false
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null or target.color == color or target.current_hp > action.piece.attack_power:
		return false
	for attacker in tactical_map.king_attackers(color):
		if attacker == target:
			return true
	return false


func projection_metrics() -> Dictionary:
	var recalculations := 0
	var attack_calls := 0
	var projection_usec := 0
	for projected in _projected_maps.values():
		recalculations += projected.incremental_recalculations
		attack_calls += projected.direct_attack_calls
		projection_usec += projected.build_usec + projected.query_usec
	return {
		"count": _projected_maps.size(),
		"recalculations": recalculations,
		"attack_calls": attack_calls,
		"usec": projection_usec,
	}


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


func _piece_value(piece: ModelPiece) -> float:
	return player._get_piece_value(piece)


func _other_color(value: String) -> String:
	return "black" if value == "white" else "white"


func _center_distance(coordinate: Vector2i) -> int:
	return mini(
		absi(coordinate.x - 3) + absi(coordinate.y - 3),
		absi(coordinate.x - 4) + absi(coordinate.y - 4)
	)
