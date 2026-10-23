extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name RhetoricianKingAiLayer

const LUNACY_VALUE := 2.0
const SOCRATIC_TURN_VALUE := 8.0


func supports(king_type: StringName) -> bool:
	return king_type == &"rhetorician_king"


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is RhetoricianKing:
		return 0.0
	var compelled: ModelPiece = model.board[action.target.x][action.target.y]
	if compelled == null:
		return 0.0
	# Generic targeting scores the compelled piece as captured. It survives; the
	# occupant of its forced destination is the piece actually captured.
	var result := -_piece_value(compelled)
	var delta := action.piece.coordinate - compelled.coordinate
	var destination := compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))
	if model.is_in_bounds(destination.x, destination.y):
		var occupant: ModelPiece = model.board[destination.x][destination.y]
		if occupant != null:
			result += _piece_value(occupant) if occupant.color != action.piece.color else -_piece_value(occupant)
	return result


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is RhetoricianKing:
		return false
	var compelled: ModelPiece = model.board[action.target.x][action.target.y]
	if compelled == null:
		return false
	var delta := action.piece.coordinate - compelled.coordinate
	var destination := compelled.coordinate + Vector2i(signi(delta.x), signi(delta.y))
	if not model.is_in_bounds(destination.x, destination.y):
		return false
	var occupant: ModelPiece = model.board[destination.x][destination.y]
	return occupant != null or compelled.is_king or _piece_value(compelled) >= 5.0


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var enemy := model.get_other_color(perspective)
	return (
		float(model.lunacy_by_color.get(enemy, 0) - model.lunacy_by_color.get(perspective, 0)) * LUNACY_VALUE
		+ float(model.socratic_turns_by_color.get(enemy, 0) - model.socratic_turns_by_color.get(perspective, 0)) * SOCRATIC_TURN_VALUE
	)


func _piece_value(piece: ModelPiece) -> float:
	if piece.is_king: return 100.0
	match piece.type:
		"queen": return 9.0
		"rook": return 5.0
		"bishop", "knight": return 3.0
	return 1.0
