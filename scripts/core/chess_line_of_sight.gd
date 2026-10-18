extends RefCounted
class_name ChessLineOfSight

const DEFAULT_VISIBILITY_THRESHOLD := 0.6
const CHECKPOINT_OFFSET := 0.25
const EPSILON := 0.000001


## Returns the unlimited-range visibility scores that meet the supplied cutoff.
## Coordinates use the model's (row, column) convention.
static func build_visibility_map(board: Array, origin: Vector2i, minimum_visibility := DEFAULT_VISIBILITY_THRESHOLD) -> Dictionary:
	var result := {}
	if not _is_in_bounds(board, origin):
		return result

	for row_index in range(board.size()):
		for column_index in range(board[row_index].size()):
			var destination := Vector2i(row_index, column_index)
			var score := _visibility_score(board, origin, destination)
			if score + EPSILON >= minimum_visibility:
				result[destination] = score
	return result


static func _visibility_score(board: Array, origin: Vector2i, destination: Vector2i) -> float:
	if origin == destination:
		return 1.0

	var source_point := _cell_center(origin)
	var destination_point := _cell_center(destination)
	var direction := (destination_point - source_point).normalized()
	var perpendicular := Vector2(direction.y, -direction.x) * CHECKPOINT_OFFSET
	var checkpoints := [
		destination_point,
		destination_point + perpendicular,
		destination_point - perpendicular,
	]
	var clear_rays := 0
	for checkpoint: Vector2 in checkpoints:
		if not _ray_is_blocked(board, origin, destination, source_point, checkpoint):
			clear_rays += 1
	return 1.0 if clear_rays == 3 else float(clear_rays) / 3.0


static func _ray_is_blocked(board: Array, origin: Vector2i, destination: Vector2i, source: Vector2, endpoint: Vector2) -> bool:
	for row_index in range(board.size()):
		for column_index in range(board[row_index].size()):
			var coordinate := Vector2i(row_index, column_index)
			if coordinate == origin or coordinate == destination or board[row_index][column_index] == null:
				continue
			if _is_adjacent_diagonal_corridor_blocker(origin, destination, coordinate):
				continue
			if _segment_intersects_cell(source, endpoint, coordinate):
				return true
	return false


## A cardinally adjacent piece leaves open the two exact 45-degree corridors
## passing its corners. It still blocks straight and off-diagonal sightlines;
## other pieces farther along an open corridor continue to block normally.
static func _is_adjacent_diagonal_corridor_blocker(origin: Vector2i, destination: Vector2i, blocker: Vector2i) -> bool:
	var destination_delta := destination - origin
	var blocker_delta := blocker - origin
	return (
		destination_delta.x != 0
		and absi(destination_delta.x) == absi(destination_delta.y)
		and (
			blocker_delta == Vector2i(signi(destination_delta.x), 0)
			or blocker_delta == Vector2i(0, signi(destination_delta.y))
		)
	)


## Liang-Barsky segment/AABB intersection with closed cell boundaries. Closed
## boundaries intentionally count both cells when a ray passes through a corner.
static func _segment_intersects_cell(source: Vector2, endpoint: Vector2, coordinate: Vector2i) -> bool:
	var cell_min := Vector2(coordinate.y, coordinate.x)
	var cell_max := cell_min + Vector2.ONE
	return _segment_intersects_bounds(source, endpoint, cell_min, cell_max)


static func _segment_intersects_bounds(source: Vector2, endpoint: Vector2, cell_min: Vector2, cell_max: Vector2) -> bool:
	var delta := endpoint - source
	var t_min := 0.0
	var t_max := 1.0

	for axis in range(2):
		var start: float = source[axis]
		var step: float = delta[axis]
		var lower: float = cell_min[axis]
		var upper: float = cell_max[axis]
		if absf(step) <= EPSILON:
			if start < lower - EPSILON or start > upper + EPSILON:
				return false
			continue
		var first := (lower - start) / step
		var second := (upper - start) / step
		if first > second:
			var swap := first
			first = second
			second = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, second)
		if t_min > t_max + EPSILON:
			return false
	return true


static func _cell_center(coordinate: Vector2i) -> Vector2:
	return Vector2(coordinate.y + 0.5, coordinate.x + 0.5)


static func _is_in_bounds(board: Array, coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.x < board.size() and coordinate.y >= 0 and coordinate.y < board[coordinate.x].size()
