extends RefCounted
class_name ChessAttackPosition

const LineOfSight := preload("res://scripts/core/chess_line_of_sight.gd")

var board_size := Vector2i.ZERO
var occupancy: Dictionary = {}
var _visibility_cache: Dictionary = {}


static func from_board(board: Array) -> ChessAttackPosition:
	var position := ChessAttackPosition.new()
	position.board_size = Vector2i(board.size(), board[0].size() if not board.is_empty() else 0)
	for row_index in range(board.size()):
		for column_index in range(board[row_index].size()):
			if board[row_index][column_index] != null:
				position.occupancy[Vector2i(row_index, column_index)] = board[row_index][column_index]
	return position


static func from_occupancy(size: Vector2i, pieces: Dictionary) -> ChessAttackPosition:
	var position := ChessAttackPosition.new()
	position.board_size = size
	position.occupancy = pieces.duplicate()
	return position


func is_in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < board_size.x and coordinate.y < board_size.y


func has_occupant(coordinate: Vector2i) -> bool:
	return occupancy.has(coordinate)


func get_occupant(coordinate: Vector2i):
	return occupancy.get(coordinate)


func get_color(coordinate: Vector2i) -> String:
	var occupant = get_occupant(coordinate)
	if occupant is ModelPiece:
		return occupant.color
	if occupant is Dictionary:
		return String(occupant.get("color", ""))
	return ""


func to_board_array() -> Array:
	var board: Array = []
	for row_index in range(board_size.x):
		var row: Array = []
		row.resize(board_size.y)
		row.fill(null)
		board.append(row)
	for coordinate in occupancy:
		if is_in_bounds(coordinate):
			board[coordinate.x][coordinate.y] = occupancy[coordinate]
	return board


func get_visibility_map(origin: Vector2i, minimum_visibility := LineOfSight.DEFAULT_VISIBILITY_THRESHOLD) -> Dictionary:
	var cache_key := "%s:%s:%0.6f" % [origin.x, origin.y, minimum_visibility]
	if not _visibility_cache.has(cache_key):
		_visibility_cache[cache_key] = LineOfSight.build_visibility_map(to_board_array(), origin, minimum_visibility)
	return _visibility_cache[cache_key]
