extends Control
class_name BattleSpiralRenderer

var logical_size := Vector2i.ZERO
var cell_size := 8
var cell_order: Array[Vector2i] = []
var revealed_cell_count := 0


func configure(size: Vector2i, requested_cell_size: int, order: Array[Vector2i]) -> void:
	logical_size = size
	cell_size = maxi(1, requested_cell_size)
	cell_order.assign(order)
	revealed_cell_count = 0
	position = Vector2.ZERO
	size = Vector2(logical_size)
	queue_redraw()


func reveal_through(count: int) -> void:
	var next_count := clampi(count, 0, cell_order.size())
	if next_count == revealed_cell_count:
		return
	revealed_cell_count = next_count
	queue_redraw()


func clear() -> void:
	logical_size = Vector2i.ZERO
	cell_order.clear()
	revealed_cell_count = 0
	queue_redraw()


func is_fully_covered() -> bool:
	return not cell_order.is_empty() and revealed_cell_count == cell_order.size()


func cell_rect(cell: Vector2i) -> Rect2:
	var origin := cell * cell_size
	var clipped_size := Vector2i(
		mini(cell_size, logical_size.x - origin.x),
		mini(cell_size, logical_size.y - origin.y)
	)
	return Rect2(Vector2(origin), Vector2(maxi(0, clipped_size.x), maxi(0, clipped_size.y)))


func _draw() -> void:
	for index in range(revealed_cell_count):
		draw_rect(cell_rect(cell_order[index]), Color.BLACK, true)
