extends RefCounted
class_name ChessBoardProjection

## Maps authoritative model coordinates onto a mildly foreshortened 2D board.
## All rendered cells share points from one intersection grid so their surfaces,
## highlights, and hit regions cannot drift apart.

const VIEWPORT_HEIGHT_WIDTH_RATIO := 0.90
const VIEWPORT_WIDTH_CAP_RATIO := 0.64
const PROJECTED_DEPTH_RATIO := 0.70
const FAR_EDGE_WIDTH_RATIO := 0.88

var rows: int = 8
var columns: int = 8
var viewing_color: String = "white"
var intersections: Array = []
var corners := PackedVector2Array()


func configure(
	viewport_size: Vector2,
	board_rows: int,
	board_columns: int,
	new_viewing_color: String = "white"
) -> void:
	rows = maxi(board_rows, 1)
	columns = maxi(board_columns, 1)
	viewing_color = new_viewing_color if new_viewing_color == "black" else "white"

	var near_width := minf(
		viewport_size.y * VIEWPORT_HEIGHT_WIDTH_RATIO,
		viewport_size.x * VIEWPORT_WIDTH_CAP_RATIO
	)
	var projected_depth := near_width * PROJECTED_DEPTH_RATIO
	var far_width := near_width * FAR_EDGE_WIDTH_RATIO
	var center := viewport_size * 0.5
	var top_y := center.y - projected_depth * 0.5
	var bottom_y := center.y + projected_depth * 0.5

	var far_left := Vector2(center.x - far_width * 0.5, top_y).round()
	var far_right := Vector2(center.x + far_width * 0.5, top_y).round()
	var near_right := Vector2(center.x + near_width * 0.5, bottom_y).round()
	var near_left := Vector2(center.x - near_width * 0.5, bottom_y).round()
	corners = PackedVector2Array([far_left, far_right, near_right, near_left])

	intersections.clear()
	for display_row in range(rows + 1):
		var row_fraction := float(display_row) / float(rows)
		var left_point := far_left.lerp(near_left, row_fraction)
		var right_point := far_right.lerp(near_right, row_fraction)
		var intersection_row: Array[Vector2] = []
		for display_column in range(columns + 1):
			var column_fraction := float(display_column) / float(columns)
			intersection_row.append(right_point.lerp(left_point, 1.0 - column_fraction).round())
		intersections.append(intersection_row)


func get_display_coordinate(model_coordinate: Vector2i) -> Vector2i:
	if viewing_color == "black":
		return Vector2i(rows - 1 - model_coordinate.x, columns - 1 - model_coordinate.y)
	return model_coordinate


func get_cell_polygon(model_coordinate: Vector2i) -> PackedVector2Array:
	var display_coordinate := get_display_coordinate(model_coordinate)
	var row := display_coordinate.x
	var column := display_coordinate.y
	return PackedVector2Array([
		intersections[row][column],
		intersections[row][column + 1],
		intersections[row + 1][column + 1],
		intersections[row + 1][column],
	])


func get_cell_anchor(model_coordinate: Vector2i) -> Vector2:
	var polygon := get_cell_polygon(model_coordinate)
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	return (center / polygon.size()).round()


func get_board_outline() -> PackedVector2Array:
	return corners.duplicate()
