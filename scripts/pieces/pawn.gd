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
	var forward_one_is_clear := (
		model.is_in_bounds(forward_one, col)
		and model.board[forward_one][col] == null
	)

	if forward_one_is_clear:
		moves.append(Vector2i(forward_one, col))

		# A pawn may move two squares only when both the intermediate
		# square and the destination are empty.
		var forward_two = row + (direction * 2)
		if (
			not has_moved
			and model.is_in_bounds(forward_two, col)
			and model.board[forward_two][col] == null
		):
			moves.append(Vector2i(forward_two, col))

	for dc in [-1, 1]:
		var diag_col = col + dc
		if model.is_in_bounds(forward_one, diag_col):
			var target = model.board[forward_one][diag_col]
			if target != null and target.color != color:
				moves.append(Vector2i(forward_one, diag_col))

	# En passant uses immutable move metadata. The optional piece reference may
	# be absent in a simulation after that piece is destroyed or transformed.
	var last_from = model.last_move.get("from")
	var last_to = model.last_move.get("to")
	var last_piece_type: String = model.last_move.get("piece_type", "")
	var last_piece_color: String = model.last_move.get("piece_color", "")
	if (
		last_piece_type == "pawn"
		and last_piece_color != color
		and last_from is Vector2i
		and last_to is Vector2i
		and abs(last_to.x - last_from.x) == 2
		and last_to.x == row
		and abs(last_to.y - col) == 1
		and model.is_in_bounds(last_to.x, last_to.y)
	):
		var adjacent_piece: ModelPiece = model.board[last_to.x][last_to.y]
		if (
			adjacent_piece != null
			and adjacent_piece.type == "pawn"
			and adjacent_piece.color == last_piece_color
		):
			moves.append(Vector2i(row + direction, last_to.y))

	return moves
