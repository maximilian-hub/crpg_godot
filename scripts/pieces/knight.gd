extends ModelPiece
class_name Knight

func _init(p_color: String, p_type: String, p_coordinate: Vector2i):
	super._init(p_color, p_type, p_coordinate) # Pass arguments up

func get_legal_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y
	var color = color
	var moves := []
	var offsets = [
		Vector2i(2, 1), Vector2i(2, -1),
		Vector2i(-2, 1), Vector2i(-2, -1),
		Vector2i(1, 2), Vector2i(-1, 2),
		Vector2i(1, -2), Vector2i(-1, -2),
	]

	for offset in offsets:
		var target_pos = Vector2i(row, col) + offset
		if model.is_in_bounds(target_pos.x, target_pos.y):
			var target = model.board[target_pos.x][target_pos.y]
			if target == null or target.color != color:
				moves.append(target_pos)

	return moves
