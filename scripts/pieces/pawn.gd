extends ModelPiece
class_name Pawn

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "pawn"

func get_legal_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y
	var direction = -1 if color == "white" else 1
	var moves := []

	var forward_one = row + direction
	
	if model.is_in_bounds(forward_one, col) and model.board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))

		var forward_two = row + (direction * 2)
		if not has_moved and model.is_in_bounds(forward_two, col) and model.board[forward_two][col] == null:
			moves.append(Vector2i(forward_two, col))

	for dc in [-1, 1]:
		var diag_col = col + dc
		if model.is_in_bounds(forward_one, diag_col):
			var target = model.board[forward_one][diag_col]
			if target != null and target.color != color:
				moves.append(Vector2i(forward_one, diag_col))

	# En passant
	if model.last_move.has("piece") and model.last_move["piece"].type == "pawn":
		var last_from = model.last_move["from"]
		var last_to = model.last_move["to"]
		if abs(last_to.x - last_from.x) == 2 and last_to.x == row:
			for dc in [-1, 1]:
				var side_col = col + dc
				if model.is_in_bounds(row, side_col) and last_to.y == side_col:
					var en_passant_row = row + direction
					moves.append(Vector2i(en_passant_row, side_col))

	return moves
