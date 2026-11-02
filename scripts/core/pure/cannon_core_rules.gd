extends RefCounted
class_name CannonCoreRules

const TYPE_ID := &"cannon_king"
const ABILITY_ID := &"arc_mortar"
const DAMAGE := 1
const RANGE := 5
const DELAY_ROUNDS := 3
const BASE_COOLDOWN := 4


static func base_cooldown() -> int:
	return BASE_COOLDOWN


static func active_targets(_state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(7):
		for column in range(7):
			var anchor := Vector2i(row, column)
			var delta := anchor - piece.coordinate
			if maxi(absi(delta.x), absi(delta.y)) <= RANGE: result.append(anchor)
	return result


static func active_effect(state: ChessCoreState, piece: ChessCorePiece, _target: ChessCorePiece) -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"arc_mortar": true,
		"owner_color": piece.color,
		"landing_turn": state.global_turn_number + DELAY_ROUNDS,
	}


static func area(anchor: Vector2i) -> Array[Vector2i]:
	return [anchor, anchor + Vector2i(0, 1), anchor + Vector2i(1, 0), anchor + Vector2i(1, 1)]
