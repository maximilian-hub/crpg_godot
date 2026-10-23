extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name MinotaurKingAiLayer

const EMPTY_WALL_STUN_PENALTY := 6.0


func supports(king_type: StringName) -> bool:
	return king_type == &"minotaur_king"


func active_ability_is_lethal(action: ChessPrimaryAction, target: ModelPiece) -> bool:
	return (
		action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY
		and action.piece is MinotaurKing
		and action.target == target.coordinate
		and target.color != action.piece.color
		and target.current_hp <= 2
	)


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is MinotaurKing:
		return 0.0
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	if target == null:
		return -EMPTY_WALL_STUN_PENALTY
	# The generic CPU score assumes targeting means capturing. Correct that for
	# durable Charge targets, which take two damage but retain their square.
	if target.current_hp > 2:
		return -_piece_value(target) + minf(2.0, float(target.current_hp)) / float(target.current_hp) * _piece_value(target)
	return 2.0 if target.is_king else 0.5


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is MinotaurKing:
		return false
	var target: ModelPiece = model.board[action.target.x][action.target.y]
	return target != null and target.color != action.piece.color and (target.is_king or target.current_hp <= 2 or _piece_value(target) >= 3.0)


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var result := 0.0
	for color in [perspective, model.get_other_color(perspective)]:
		var king: ModelPiece = model.get_king(color)
		if not king is MinotaurKing or not (king as MinotaurKing).is_active_ability_ready():
			continue
		var pressure := 0.0
		for target_coordinate in (king as MinotaurKing).get_active_ability_targets():
			var target: ModelPiece = model.board[target_coordinate.x][target_coordinate.y]
			if target != null and target.color != color:
				pressure = maxf(pressure, 5.0 if target.is_king else minf(_piece_value(target), 3.0))
		result += pressure if color == perspective else -pressure
	return result


func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
