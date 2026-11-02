extends RefCounted
class_name MinotaurCoreRules

const TYPE_ID := &"minotaur_king"
const ABILITY_ID := &"charge"
const CHARGE_DAMAGE := 2
const RAGE_DAMAGE := 1
const SELF_STUN_DURATION := 2
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func base_cooldown() -> int:
	return 4


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var target := piece.coordinate + direction
		var empty_count := 0
		while _in_bounds(target) and state.occupant(target) == null:
			empty_count += 1
			target += direction
		if empty_count < 2:
			continue
		# Match MinotaurKing exactly: the first piece in the lane is a target
		# regardless of color; an unobstructed lane targets its final square.
		result.append(target if _in_bounds(target) else target - direction)
	return result


static func active_effect(_state: ChessCoreState, piece: ChessCorePiece, target: ChessCorePiece) -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"charge": true,
		"damage": CHARGE_DAMAGE,
		"empty_target": target == null,
		"source_coordinate": piece.coordinate,
	}


static func _in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < 8 and coordinate.y < 8
