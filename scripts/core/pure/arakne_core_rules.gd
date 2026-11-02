extends RefCounted
class_name ArakneCoreRules

const TYPE_ID := &"arakne_king"
const ABILITY_ID := &"spike_burst"
const DAMAGE := 1
const DIAGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(-1, 1),
	Vector2i(1, 1), Vector2i(1, -1),
]


static func base_cooldown() -> int:
	return 1


static func movement_paths(state: ChessCoreState, piece: ChessCorePiece, ordinary_destinations: Array[Vector2i]) -> Array[Array]:
	var result: Array[Array] = []
	for intermediate in ordinary_destinations:
		result.append([intermediate])
		# Captures and castling never begin Skitter.
		if state.occupant(intermediate) != null or maxi(absi(intermediate.x - piece.coordinate.x), absi(intermediate.y - piece.coordinate.y)) != 1:
			continue
		for offset in DIAGONAL_OFFSETS:
			var destination := intermediate + offset
			if not _in_bounds(destination):
				continue
			var occupant := state.occupant(destination)
			# The origin becomes empty after the first landing.
			if occupant == null or occupant == piece:
				result.append([intermediate, destination])
	return result


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row_delta in range(-1, 2):
		for column_delta in range(-1, 2):
			if row_delta == 0 and column_delta == 0:
				continue
			var target := piece.coordinate + Vector2i(row_delta, column_delta)
			if not _in_bounds(target):
				continue
			var occupant := state.occupant(target)
			if occupant != null and occupant.color != piece.color:
				result.append(target)
	return result


static func active_effect(_state: ChessCoreState, _piece: ChessCorePiece, target: ChessCorePiece) -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"target_piece_id": target.piece_id,
		"damage": DAMAGE,
	}


static func _in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < 8 and coordinate.y < 8
