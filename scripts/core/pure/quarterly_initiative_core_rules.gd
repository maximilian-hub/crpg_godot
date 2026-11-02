extends RefCounted
class_name QuarterlyInitiativeCoreRules

const TYPE_ID := &"quarterly_initiative_king"
const ABILITY_ID := &"stakeholder_pandering"
const GRANT_OPTIONS: Array[StringName] = [&"pawn", &"knight", &"bishop", &"rook"]


static func base_cooldown() -> int:
	return 2


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for candidate in state.pieces:
		if candidate != piece and candidate.color == piece.color:
			result.append(candidate.coordinate)
	return result


static func active_effect(state: ChessCoreState, piece: ChessCorePiece, target: ChessCorePiece) -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"movement_grant": true,
		"hp_cost": 0 if state.global_turn_number % 4 == 0 else 1,
		"target_piece_id": target.piece_id if target != null else "",
		"options": GRANT_OPTIONS.duplicate(),
	}
