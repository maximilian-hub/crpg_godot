extends ModelPiece
class_name Rook

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "rook"

func get_legal_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y

	var moves := []
	var directions = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]

	for dir in directions:
		var r = row + dir.x
		var c = col + dir.y
		while model.is_in_bounds(r, c):
			var target = model.board[r][c]
			if target == null:
				moves.append(Vector2i(r, c))
			elif target.color == color:
				break
			else:
				moves.append(Vector2i(r, c))
				break
			r += dir.x
			c += dir.y

	return moves
