##~~~~~~~~NEW FILE: bone_pawn.gd~~~~~~~~~~~~
extends ModelPiece
class_name BonePawn

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "bone_pawn"

func get_legal_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y
	var direction = -1 if color == "white" else 1
	var moves := []
	var attack_position := get_live_attack_position()

	var forward_one = row + direction
	
	if model.is_in_bounds(forward_one, col) and model.board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))

	for dc in [-1, 1]:
		var diag_col = col + dc
		var attack_target := Vector2i(forward_one, diag_col)
		if can_natively_attack_square(coordinate, attack_target, attack_position):
			var target = model.board[forward_one][diag_col]
			if target != null and target.color != color:
				moves.append(attack_target)
	


	return moves

func _on_turn_changed(current_turn: String):
	super._on_turn_changed(current_turn)

func _on_dead_row() -> bool:
	return coordinate.x == model.get_back_rank(model.get_other_color(color))
