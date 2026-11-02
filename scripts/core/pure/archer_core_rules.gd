extends RefCounted
class_name ArcherCoreRules

const TYPES: Array[StringName] = [
	&"archer_king", &"archer_king_draw", &"archer_king_quiver",
	&"archer_king_combination", &"archer_king_charge",
]
const DRAW_TYPES: Array[StringName] = [&"archer_king_draw", &"archer_king_combination"]
const QUIVER_TYPES: Array[StringName] = [&"archer_king_quiver", &"archer_king_combination"]
const CHARGE_TYPE: StringName = &"archer_king_charge"
const BASE_COOLDOWN := 4
const VOLLEY_SQUARE_COUNT := 6


static func base_cooldown() -> int:
	return BASE_COOLDOWN


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	if is_suppressed(state, piece) or (uses_draw(piece) and is_drawing(piece)):
		return []
	return [piece.coordinate]


static func active_effect(_state: ChessCoreState, piece: ChessCorePiece, _target: ChessCorePiece) -> Dictionary:
	return {"ability_id": &"volley_of_arrows", "archer_volley": true, "piece_id": piece.piece_id}


static func uses_draw(piece: ChessCorePiece) -> bool:
	return piece.type_id in DRAW_TYPES


static func uses_quiver(piece: ChessCorePiece) -> bool:
	return piece.type_id in QUIVER_TYPES


static func uses_charge(piece: ChessCorePiece) -> bool:
	return piece.type_id == CHARGE_TYPE


static func is_drawing(piece: ChessCorePiece) -> bool:
	return draw_target(piece) != Vector2i(-1, -1) or charge_level(piece) > 0


static func draw_target(piece: ChessCorePiece) -> Vector2i:
	var value = piece.custom_state.get("draw_target", [-1, -1])
	return Vector2i(int(value[0]), int(value[1])) if value is Array and value.size() == 2 else Vector2i(-1, -1)


static func charge_level(piece: ChessCorePiece) -> int:
	return clampi(int(piece.custom_state.get("charge_level", 0)), 0, 3)


static func arrows(piece: ChessCorePiece) -> int:
	return clampi(int(piece.custom_state.get("arrows", 2)), 0, 2)


static func is_suppressed(state: ChessCoreState, piece: ChessCorePiece) -> bool:
	for row in range(maxi(0, piece.coordinate.x - 1), mini(8, piece.coordinate.x + 2)):
		for column in range(maxi(0, piece.coordinate.y - 1), mini(8, piece.coordinate.y + 2)):
			var other := state.occupant(Vector2i(row, column))
			if other != null and other.color != piece.color:
				return true
	return false


static func can_ranged_attack(state: ChessCoreState, piece: ChessCorePiece, target: Vector2i) -> bool:
	if is_suppressed(state, piece) or (uses_quiver(piece) and arrows(piece) <= 0):
		return false
	var defender := state.occupant(target)
	if defender == null or defender.color == piece.color:
		return false
	var distance := maxi(absi(target.x - piece.coordinate.x), absi(target.y - piece.coordinate.y))
	var maximum_range := 3
	if uses_charge(piece):
		var level := charge_level(piece)
		if level <= 0: return false
		maximum_range = level + 1
	if distance < 2 or distance > maximum_range:
		return false
	var position := ChessAttackPosition.from_occupancy(state.board_size, state.occupancy)
	return position.get_visibility_map(piece.coordinate).has(target)


static func validate_custom_state(piece: ChessPieceState) -> bool:
	var allowed := ["draw_target", "draw_target_piece_id", "draw_turns_waited", "charge_level", "arrows"]
	if piece.custom_state.keys().any(func(key): return String(key) not in allowed): return false
	var target = piece.custom_state.get("draw_target", [-1, -1])
	if not (target is Array and target.size() == 2): return false
	var coordinate := Vector2i(int(target[0]), int(target[1]))
	return (coordinate == Vector2i(-1, -1) or (coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < 8 and coordinate.y < 8)) \
		and int(piece.custom_state.get("draw_turns_waited", 0)) >= 0 \
		and int(piece.custom_state.get("charge_level", 0)) in [0, 1, 2, 3] \
		and int(piece.custom_state.get("arrows", 2)) in [0, 1, 2]


static func normalize_custom_state(piece: ChessCorePiece) -> void:
	var target := draw_target(piece)
	piece.custom_state = {
		"draw_target": [target.x, target.y],
		"draw_target_piece_id": String(piece.custom_state.get("draw_target_piece_id", "")),
		"draw_turns_waited": maxi(0, int(piece.custom_state.get("draw_turns_waited", 0))),
		"charge_level": charge_level(piece),
		"arrows": arrows(piece),
	}
