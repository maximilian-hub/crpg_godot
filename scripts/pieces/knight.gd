extends ModelPiece
class_name Knight

func _init(p_color: String, p_coordinate: Vector2i):
	super._init(p_color, p_coordinate) # Pass arguments up
	type = "knight"

func get_legal_moves() -> Array:
	var moves := []
	var position := get_live_attack_position()
	var offsets = [
		Vector2i(2, 1), Vector2i(2, -1),
		Vector2i(-2, 1), Vector2i(-2, -1),
		Vector2i(1, 2), Vector2i(-1, 2),
		Vector2i(1, -2), Vector2i(-1, -2),
	]
	for offset in offsets:
		var target: Vector2i = coordinate + Vector2i(offset)
		if not can_natively_attack_square(coordinate, target, position):
			continue
		var occupant = position.get_occupant(target)
		if occupant == null or position.get_color(target) != color:
			moves.append(target)
	return moves
