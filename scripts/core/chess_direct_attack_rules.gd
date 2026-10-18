extends RefCounted
class_name ChessDirectAttackRules


static func movement_type_attacks_square(movement_type: StringName, color: String, origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	if not position.is_in_bounds(target) or origin == target:
		return false
	var delta := target - origin
	match movement_type:
		&"pawn":
			var direction := -1 if color == "white" else 1
			return delta.x == direction and absi(delta.y) == 1
		&"knight":
			return Vector2i(absi(delta.x), absi(delta.y)) in [Vector2i(1, 2), Vector2i(2, 1)]
		&"bishop":
			return absi(delta.x) == absi(delta.y) and _ray_is_clear(origin, target, position)
		&"rook":
			return (delta.x == 0 or delta.y == 0) and _ray_is_clear(origin, target, position)
	return false


static func queen_attacks_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	return movement_type_attacks_square(&"rook", "", origin, target, position) or movement_type_attacks_square(&"bishop", "", origin, target, position)


static func _ray_is_clear(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	var delta := target - origin
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var coordinate := origin + step
	while coordinate != target:
		if position.has_occupant(coordinate):
			return false
		coordinate += step
	return true
