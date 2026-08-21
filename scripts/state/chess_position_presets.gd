extends RefCounted
class_name ChessPositionPresets

static func empty() -> ChessPosition:
	return ChessPosition.new()

static func normal_start() -> ChessPosition:
	var position := empty()
	var back := [&"rook", &"knight", &"bishop", &"queen", &"necromancer_king", &"bishop", &"knight", &"rook"]
	for column in range(8):
		_add(position, back[column], "black", Vector2i(0, column))
		_add(position, &"pawn", "black", Vector2i(1, column))
		_add(position, &"pawn", "white", Vector2i(6, column))
		var white_type: StringName = &"arakne_king" if column == 4 else back[column]
		_add(position, white_type, "white", Vector2i(7, column))
	return position

static func debug_layout() -> ChessPosition:
	var position := empty()
	for item in [
		[&"rook", "black", Vector2i(0, 0)], [&"knight", "black", Vector2i(0, 1)],
		[&"bishop", "black", Vector2i(0, 2)], [&"queen", "black", Vector2i(0, 3)],
		[&"bishop", "black", Vector2i(0, 5)], [&"knight", "black", Vector2i(0, 6)],
		[&"rook", "black", Vector2i(0, 7)], [&"bone_pawn", "black", Vector2i(1, 5)],
		[&"minotaur_king", "black", Vector2i(3, 3)], [&"pawn", "white", Vector2i(3, 4)],
		[&"bishop", "white", Vector2i(4, 4)], [&"bishop", "white", Vector2i(2, 2)],
		[&"rook", "white", Vector2i(7, 0)], [&"necromancer_king", "white", Vector2i(7, 4)],
		[&"rook", "white", Vector2i(7, 7)],
	]:
		_add(position, item[0], item[1], item[2])
	return position

static func _add(position: ChessPosition, type_id: StringName, color: String, coordinate: Vector2i) -> void:
	var piece := ChessPieceCatalog.create_piece(type_id, color, coordinate)
	position.pieces.append(piece.capture_piece_state())
