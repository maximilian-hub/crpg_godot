extends RefCounted
class_name RhetoricianCoreRules

const TYPE_ID := &"rhetorician_king"
const ABILITY_ID := &"can_logic_move_them"
const BASE_COOLDOWN := 4
const LUNACY_THRESHOLD := 5
const SOCRATIC_TURN_COUNT := 2


static func base_cooldown() -> int:
	return BASE_COOLDOWN


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for candidate in state.pieces:
		if candidate.color == piece.color or candidate.current_hp <= 0:
			continue
		var delta := candidate.coordinate - piece.coordinate
		if maxi(absi(delta.x), absi(delta.y)) == 2:
			result.append(candidate.coordinate)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return [a.x, a.y] < [b.x, b.y])
	return result


static func active_effect(_state: ChessCoreState, piece: ChessCorePiece, target: ChessCorePiece) -> Dictionary:
	var destination := Vector2i(-1, -1)
	if target != null:
		destination = target.coordinate
		var delta := piece.coordinate - target.coordinate
		destination += Vector2i(signi(delta.x), signi(delta.y))
	return {
		"ability_id": ABILITY_ID,
		"compel": true,
		"target_piece_id": target.piece_id if target != null else "",
		"destination": destination,
	}
