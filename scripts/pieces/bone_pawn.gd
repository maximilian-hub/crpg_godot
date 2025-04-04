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

	var forward_one = row + direction
	
	if model.is_in_bounds(forward_one, col) and model.board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))

	for dc in [-1, 1]:
		var diag_col = col + dc
		if model.is_in_bounds(forward_one, diag_col):
			var target = model.board[forward_one][diag_col]
			if target != null and target.color != color:
				moves.append(Vector2i(forward_one, diag_col))



	return moves
