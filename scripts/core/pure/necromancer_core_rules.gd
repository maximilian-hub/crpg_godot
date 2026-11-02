extends RefCounted
class_name NecromancerCoreRules

const TYPE_ID := &"necromancer_king"
const ABILITY_ID := &"summon_bone_pawn"


static func base_cooldown() -> int:
	return 2


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var back_rank := 7 if piece.color == "white" else 0
	var furthest_rank := back_rank
	# Preserve ChessBoardModel's current furthest-rank scans exactly, including
	# their excluded terminal row/column bounds.
	if piece.color == "white":
		furthest_rank = 8
		for row in range(7):
			for column in range(8):
				var occupant := state.occupant(Vector2i(row, column))
				if occupant != null and occupant.color == piece.color:
					furthest_rank = mini(furthest_rank, row)
					break
		for row in range(furthest_rank, back_rank + 1):
			for column in range(8):
				var target := Vector2i(row, column)
				if state.occupant(target) == null: result.append(target)
	else:
		for row in range(7):
			for column in range(7):
				var occupant := state.occupant(Vector2i(row, column))
				if occupant != null and occupant.color == piece.color:
					furthest_rank = maxi(furthest_rank, row)
					break
		for row in range(back_rank, furthest_rank + 1):
			for column in range(8):
				var target := Vector2i(row, column)
				if state.occupant(target) == null: result.append(target)
	return result


static func active_effect(_state: ChessCoreState, _piece: ChessCorePiece, _target: ChessCorePiece) -> Dictionary:
	return {"ability_id": ABILITY_ID, "summon_type": &"bone_pawn"}
