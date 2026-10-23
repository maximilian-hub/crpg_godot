extends RefCounted
class_name DupreTacticalMap

enum Completeness { COMPLETE_DIRECT, INCREMENTAL_DIRECT, FALLBACK_REBUILD, UNKNOWN }

var revision := -1
var board_size := Vector2i.ZERO
var occupancy: Dictionary = {}
var attacks_by_piece: Dictionary = {}
var attackers_by_square: Dictionary = {}
var piece_coordinates: Dictionary = {}
var completeness := Completeness.COMPLETE_DIRECT
var build_usec := 0
var direct_attack_calls := 0
var incremental_recalculations := 0
var query_usec := 0
var _position: ChessAttackPosition


static func from_model(model: ChessBoardModel) -> DupreTacticalMap:
	var pieces := {}
	for row in model.board:
		for piece in row:
			if piece != null:
				pieces[piece.coordinate] = piece
	return _build(Vector2i(model.board.size(), model.board[0].size() if not model.board.is_empty() else 0), pieces, model.position_revision)


static func _build(size: Vector2i, pieces: Dictionary, source_revision := -1) -> DupreTacticalMap:
	var started := Time.get_ticks_usec()
	var result := DupreTacticalMap.new()
	result.revision = source_revision
	result.board_size = size
	result.occupancy = pieces.duplicate()
	result._position = ChessAttackPosition.from_occupancy(size, pieces)
	for origin in pieces:
		var piece = pieces[origin]
		if piece is ModelPiece:
			result.piece_coordinates[piece.piece_id] = origin
	result.build_usec = Time.get_ticks_usec() - started
	return result


func project(projected_occupancy: Dictionary) -> DupreTacticalMap:
	var result := _build(board_size, projected_occupancy, revision)
	result.completeness = Completeness.INCREMENTAL_DIRECT
	# The view is cheap and lazy: only relationships requested for this action
	# are calculated. Count changed real pieces for useful profiling.
	for square in _changed_squares(projected_occupancy):
		if occupancy.get(square) is ModelPiece or projected_occupancy.get(square) is ModelPiece:
			result.incremental_recalculations += 1
	return result


func rebuild_projection(projected_occupancy: Dictionary) -> DupreTacticalMap:
	var result := _build(board_size, projected_occupancy, revision)
	result.completeness = Completeness.FALLBACK_REBUILD
	return result


func attackers(square: Vector2i, color := "") -> Array:
	_ensure_attackers(square)
	var result: Array = []
	for piece in attackers_by_square.get(square, []):
		if color.is_empty() or piece.color == color:
			result.append(piece)
	return result


func attacks_from(piece: ModelPiece) -> Array[Vector2i]:
	if attacks_by_piece.has(piece.piece_id):
		return attacks_by_piece[piece.piece_id]
	var started := Time.get_ticks_usec()
	var result: Array[Vector2i] = []
	var origin: Vector2i = piece_coordinates.get(piece.piece_id, piece.coordinate)
	if occupancy.get(origin) != piece or piece.stunned:
		attacks_by_piece[piece.piece_id] = result
		return result
	# Policy only needs relationships to pieces, not a 64-square mobility map.
	for target in occupancy:
		direct_attack_calls += 1
		if piece.can_directly_attack_square(origin, target, _position):
			result.append(target)
	attacks_by_piece[piece.piece_id] = result
	query_usec += Time.get_ticks_usec() - started
	return result


func attack_count(square: Vector2i, color := "") -> int:
	return attackers(square, color).size()


func king_attackers(color: String) -> Array:
	for coordinate in occupancy:
		var piece = occupancy[coordinate]
		if piece is ModelPiece and piece.color == color and piece.is_king:
			return attackers(coordinate, _other_color(color))
	return []


func is_hanging(piece: ModelPiece) -> bool:
	var coordinate: Vector2i = piece_coordinates.get(piece.piece_id, piece.coordinate)
	return attack_count(coordinate, _other_color(piece.color)) > 0 and attack_count(coordinate, piece.color) == 0


func newly_exposed_undefended_value(projected: DupreTacticalMap, color: String, value_of: Callable) -> float:
	var highest := 0.0
	for coordinate in projected.occupancy:
		var piece = projected.occupancy[coordinate]
		if not piece is ModelPiece or piece.color != color or piece.is_king:
			continue
		var value := float(value_of.call(piece))
		if value < 3.0:
			continue
		var old_coordinate: Vector2i = piece_coordinates.get(piece.piece_id, coordinate)
		var was_attacked := attack_count(old_coordinate, _other_color(color)) > 0
		var becomes_attacked := projected.attack_count(coordinate, _other_color(color)) > 0
		var remains_defended := projected.attack_count(coordinate, color) > 0
		if not was_attacked and becomes_attacked and not remains_defended:
			highest = maxf(highest, value)
	return highest


func equivalent_to(other: DupreTacticalMap) -> bool:
	if other == null or occupancy.size() != other.occupancy.size():
		return false
	# Force both lazy maps across every square for a strong debug/test check.
	for row in range(board_size.x):
		for column in range(board_size.y):
			var square := Vector2i(row, column)
			if _piece_ids(attackers(square)) != _piece_ids(other.attackers(square)):
				return false
	return true


func _ensure_attackers(square: Vector2i) -> void:
	if attackers_by_square.has(square):
		return
	var started := Time.get_ticks_usec()
	var result: Array = []
	for origin in occupancy:
		var piece = occupancy[origin]
		if not piece is ModelPiece or piece.stunned:
			continue
		direct_attack_calls += 1
		if piece.can_directly_attack_square(origin, square, _position):
			result.append(piece)
	attackers_by_square[square] = result
	query_usec += Time.get_ticks_usec() - started


func _changed_squares(projected: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var all := {}
	for square in occupancy: all[square] = true
	for square in projected: all[square] = true
	for square in all:
		if occupancy.get(square) != projected.get(square):
			changed.append(square)
	return changed


static func _piece_ids(pieces: Array) -> Array[String]:
	var result: Array[String] = []
	for piece in pieces: result.append(piece.piece_id)
	result.sort()
	return result


static func _other_color(color: String) -> String:
	return "black" if color == "white" else "white"
