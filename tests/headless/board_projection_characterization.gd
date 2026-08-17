extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_geometry(Vector2(1920, 1080))
	_test_geometry(Vector2(960, 540))
	_test_player_relative_orientation()
	if failures.is_empty():
		print("BOARD PROJECTION CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _test_geometry(viewport_size: Vector2) -> void:
	var projection := ChessBoardProjection.new()
	projection.configure(viewport_size, 8, 8, "white")
	var outline := projection.get_board_outline()
	_expect(outline[1].x - outline[0].x < outline[2].x - outline[3].x, "far edge is narrower than near edge")
	for point in outline:
		_expect(point.x >= 0.0 and point.x <= viewport_size.x, "board outline stays within viewport width")
		_expect(point.y >= 0.0 and point.y <= viewport_size.y, "board outline stays within viewport height")
	for row in range(8):
		for column in range(7):
			var left := projection.get_cell_polygon(Vector2i(row, column))
			var right := projection.get_cell_polygon(Vector2i(row, column + 1))
			_expect(left[1] == right[0] and left[2] == right[3], "horizontal neighbors share their complete edge")
	for row in range(7):
		for column in range(8):
			var far_cell := projection.get_cell_polygon(Vector2i(row, column))
			var near_cell := projection.get_cell_polygon(Vector2i(row + 1, column))
			_expect(far_cell[3] == near_cell[0] and far_cell[2] == near_cell[1], "vertical neighbors share their complete edge")


func _test_player_relative_orientation() -> void:
	var white_view := ChessBoardProjection.new()
	white_view.configure(Vector2(1920, 1080), 8, 8, "white")
	var black_view := ChessBoardProjection.new()
	black_view.configure(Vector2(1920, 1080), 8, 8, "black")
	_expect(white_view.get_cell_anchor(Vector2i(7, 0)).y > white_view.get_cell_anchor(Vector2i(0, 0)).y, "White back rank is nearest from White's seat")
	_expect(black_view.get_cell_anchor(Vector2i(0, 0)).y > black_view.get_cell_anchor(Vector2i(7, 0)).y, "Black back rank is nearest from Black's seat")
	_expect(black_view.get_cell_anchor(Vector2i(0, 0)).x > black_view.get_cell_anchor(Vector2i(0, 7)).x, "Black viewpoint reverses files")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
