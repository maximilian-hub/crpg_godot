extends ModelPiece
class_name Bishop

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "bishop"
	

func get_legal_moves() -> Array:
	return _ordered_sliding_moves([
		Vector2i(-1, -1), Vector2i(-1, 1),
		Vector2i(1, 1), Vector2i(1, -1),
	])

func _ordered_sliding_moves(directions: Array) -> Array:
	var moves := []
	var position := get_live_attack_position()
	for direction in directions:
		var target: Vector2i = coordinate + direction
		while position.is_in_bounds(target):
			if not can_natively_attack_square(coordinate, target, position):
				break
			var occupant = position.get_occupant(target)
			if occupant == null:
				moves.append(target)
			elif position.get_color(target) != color:
				moves.append(target)
				break
			else:
				break
			target += direction
	return moves
