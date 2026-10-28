extends RefCounted
class_name ChessActionCodec


static func describe(action: ChessPrimaryAction, origin: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if action == null or action.piece == null: return {}
	var from := action.piece.coordinate if origin.x < 0 else origin
	return {
		"kind": action.kind,
		"color": action.piece.color,
		"piece_id": action.piece.piece_id,
		"piece_type": String(action.piece.get_position_type_id()),
		"from": [from.x, from.y],
		"target": [action.target.x, action.target.y],
		"path": action.path.map(func(value: Vector2i): return [value.x, value.y]),
	}


static func label(descriptor: Dictionary) -> String:
	if descriptor.is_empty(): return "Gameplay action"
	var kind := int(descriptor.get("kind", ChessPrimaryAction.Kind.MOVE))
	var piece := String(descriptor.get("piece_type", "piece")).capitalize()
	var target: Variant = descriptor.get("target", [])
	var square: String = "(%s, %s)" % [target[0], target[1]] if target is Array and target.size() == 2 else "?"
	match kind:
		ChessPrimaryAction.Kind.ACTIVE_ABILITY: return "%s ability → %s" % [piece, square]
		ChessPrimaryAction.Kind.ARCHER_CHARGE: return "%s charge" % piece
		_: return "%s → %s" % [piece, square]
