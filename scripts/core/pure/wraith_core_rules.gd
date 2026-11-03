extends RefCounted
class_name WraithCoreRules

const TYPE_ID := &"wraith_king"
const ABILITY_ID := &"summon_wraith"
const DAMAGE := 1
const MOVE_INTERVAL_ROUNDS := 3
const MAX_ACTIVE_WRAITHS := 2
const CURSE_MARK_RANDOM_STREAM: StringName = &"wraith_curse_mark"


static func base_cooldown() -> int:
	return 0


static func active_targets(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var owned := entities_from_source(state, piece.piece_id)
	var replacement: ChessCoreAutonomousEntity = owned[0] if owned.size() >= MAX_ACTIVE_WRAITHS else null
	var unavailable := {}
	for entity in owned:
		if entity != replacement:
			unavailable[entity.target_piece_id] = true
	for candidate in state.pieces:
		if candidate.current_hp > 0 and candidate.color != piece.color and not unavailable.has(candidate.piece_id):
			result.append(candidate.coordinate)
	result.sort_custom(func(a: Vector2i, b: Vector2i): return [a.x, a.y] < [b.x, b.y])
	return result


static func active_effect(_state: ChessCoreState, _piece: ChessCorePiece, target: ChessCorePiece) -> Dictionary:
	return {
		"ability_id": ABILITY_ID,
		"summon_wraith": true,
		"target_piece_id": target.piece_id if target != null else "",
	}


static func entities_from_source(state: ChessCoreState, source_piece_id: String) -> Array[ChessCoreAutonomousEntity]:
	var result: Array[ChessCoreAutonomousEntity] = []
	for entity in state.autonomous_entities:
		if entity.type_id == &"wraith" and entity.source_piece_id == source_piece_id:
			result.append(entity)
	return result
