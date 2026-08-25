extends RefCounted
class_name ChessBoardProjection

## Maps authoritative model coordinates onto a mildly foreshortened 2D board.
## All rendered cells share points from one intersection grid so their surfaces,
## highlights, and hit regions cannot drift apart.

const DEFAULT_VIEWPORT_HEIGHT_WIDTH_RATIO := 0.90
const DEFAULT_VIEWPORT_WIDTH_CAP_RATIO := 0.64
const DEFAULT_PROJECTED_DEPTH_RATIO := 0.70
const DEFAULT_FAR_EDGE_WIDTH_RATIO := 0.88
const DEFAULT_VERTICAL_CENTER_RATIO := 0.50
const REFERENCE_NEAR_EDGE_WIDTH := 972.0

var rows: int = 8
var columns: int = 8
var viewing_color: String = "white"
var intersections: Array = []
var corners := PackedVector2Array()
var near_edge_width := REFERENCE_NEAR_EDGE_WIDTH


func configure(
	viewport_size: Vector2,
	board_rows: int,
	board_columns: int,
	new_viewing_color: String = "white",
	viewport_height_width_ratio: float = DEFAULT_VIEWPORT_HEIGHT_WIDTH_RATIO,
	viewport_width_cap_ratio: float = DEFAULT_VIEWPORT_WIDTH_CAP_RATIO,
	projected_depth_ratio: float = DEFAULT_PROJECTED_DEPTH_RATIO,
	far_edge_width_ratio: float = DEFAULT_FAR_EDGE_WIDTH_RATIO,
	vertical_center_ratio: float = DEFAULT_VERTICAL_CENTER_RATIO
) -> void:
	rows = maxi(board_rows, 1)
	columns = maxi(board_columns, 1)
	viewing_color = new_viewing_color if new_viewing_color == "black" else "white"

	near_edge_width = minf(
		viewport_size.y * viewport_height_width_ratio,
		viewport_size.x * viewport_width_cap_ratio
	)
	var projected_depth := near_edge_width * projected_depth_ratio
	var far_width := near_edge_width * far_edge_width_ratio
	var center := Vector2(viewport_size.x * 0.5, viewport_size.y * vertical_center_ratio)
	var top_y := center.y - projected_depth * 0.5
	var bottom_y := center.y + projected_depth * 0.5

	var far_left := Vector2(center.x - far_width * 0.5, top_y).round()
	var far_right := Vector2(center.x + far_width * 0.5, top_y).round()
	var near_right := Vector2(center.x + near_edge_width * 0.5, bottom_y).round()
	var near_left := Vector2(center.x - near_edge_width * 0.5, bottom_y).round()
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


func get_model_coordinate(display_coordinate: Vector2i) -> Vector2i:
	# The current White identity / Black 180-degree transform is its own inverse.
	return get_display_coordinate(display_coordinate)


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


func get_cell_center(model_coordinate: Vector2i) -> Vector2:
	var polygon := get_cell_polygon(model_coordinate)
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	return (center / polygon.size()).round()


func get_piece_ground_anchor(model_coordinate: Vector2i, forward_bias: float = 0.0) -> Vector2:
	var polygon := get_cell_polygon(model_coordinate)
	var center := get_cell_center(model_coordinate)
	var near_edge_midpoint := (polygon[2] + polygon[3]) * 0.5
	return center.lerp(near_edge_midpoint, clampf(forward_bias, 0.0, 1.0)).round()


## Compatibility alias for callers that need the geometric center of a cell.
func get_cell_anchor(model_coordinate: Vector2i) -> Vector2:
	return get_cell_center(model_coordinate)


func get_board_outline() -> PackedVector2Array:
	return corners.duplicate()


func get_near_edge_width() -> float:
	return near_edge_width


func get_presentation_scale() -> float:
	return near_edge_width / REFERENCE_NEAR_EDGE_WIDTH
