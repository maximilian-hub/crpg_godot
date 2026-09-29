extends Node

const TRANSITION_SCENE := preload("res://scenes/ui/battle_spiral_transition.tscn")
const TransitionScript := preload("res://scripts/ui/battle_spiral_transition.gd")
const RendererScript := preload("res://scripts/ui/battle_spiral_renderer.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_spiral_order(17, 17)
	_test_spiral_order(20, 20)
	_test_spiral_order(5, 3)
	_test_spiral_order(1, 6)
	_test_spiral_order(7, 1)
	_test_requested_direction()
	_test_clipped_coverage(Vector2i(135, 135), 8)
	_test_clipped_coverage(Vector2i(160, 160), 8)
	await _test_presenter_lifecycle()
	if failures.is_empty():
		print("BATTLE SPIRAL TRANSITION CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("BATTLE SPIRAL TRANSITION FAILURE: ", failure)
		get_tree().quit(1)


func _test_spiral_order(columns: int, rows: int) -> void:
	var order: Array[Vector2i] = TransitionScript.build_spiral_order(columns, rows)
	var unique := {}
	var in_bounds := true
	for cell in order:
		unique[cell] = true
		in_bounds = in_bounds and cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows
	_check(order.size() == columns * rows, "%dx%d spiral contains every cell" % [columns, rows])
	_check(unique.size() == order.size() and in_bounds, "%dx%d spiral contains no duplicates or invalid cells" % [columns, rows])


func _test_requested_direction() -> void:
	var order: Array[Vector2i] = TransitionScript.build_spiral_order(3, 3)
	var expected := [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1),
		Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 1),
	]
	_check(order == expected, "spiral walks down, right, up, left, then inward")


func _test_clipped_coverage(logical_size: Vector2i, cell_size: int) -> void:
	var renderer: Control = RendererScript.new()
	add_child(renderer)
	var columns := ceili(float(logical_size.x) / float(cell_size))
	var rows := ceili(float(logical_size.y) / float(cell_size))
	renderer.configure(logical_size, cell_size, TransitionScript.build_spiral_order(columns, rows))
	var area := 0.0
	var inside := true
	var logical_rect := Rect2(Vector2.ZERO, Vector2(logical_size))
	for cell in renderer.cell_order:
		var rect: Rect2 = renderer.cell_rect(cell)
		area += rect.size.x * rect.size.y
		inside = inside and logical_rect.encloses(rect)
	_check(is_equal_approx(area, float(logical_size.x * logical_size.y)), "%s clipped cells cover every logical pixel" % logical_size)
	_check(inside, "%s edge cells remain within the logical viewport" % logical_size)
	renderer.queue_free()


func _test_presenter_lifecycle() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(135, 135)
	add_child(viewport)
	var frame := Control.new()
	frame.position = Vector2(20, 10)
	frame.size = Vector2(1080, 1080)
	add_child(frame)
	var presenter: Node = TRANSITION_SCENE.instantiate()
	add_child(presenter)
	await get_tree().process_frame

	await presenter.play_inward(viewport, frame, true)
	_check(presenter.renderer.is_fully_covered() and presenter.renderer.cell_order.size() == 17 * 17, "135x135 immediate cover reaches every generated cell")
	_check(presenter.logical_canvas.custom_viewport == viewport and presenter.logical_canvas is CanvasLayer, "logical overlay targets the overworld viewport through a camera-independent CanvasLayer")
	_check(presenter.root_blackout_layer.visible, "root-space letterbox blackout remains separate from logical spiral geometry")
	_check(is_equal_approx(presenter.battle_reveal_time, 3.0), "presenter exposes the authored three-second battle reveal cue")
	presenter.release_visual_cover()
	_check(presenter.audio_player.playing, "releasing the visual cover leaves transition audio playing for overlap")
	presenter.reset()
	_check(not presenter.logical_canvas.visible and presenter.logical_canvas.custom_viewport == presenter.get_viewport() and presenter.renderer.cell_order.is_empty(), "reset detaches the temporary viewport and clears stale cells")

	presenter.play_inward(viewport, frame)
	presenter.set_process(false)
	presenter._reveal_tick()
	_check(presenter.renderer.revealed_cell_count == presenter.cells_per_tick, "one animation tick reveals one discrete configured chunk")
	presenter.reset()
	viewport.size = Vector2i(160, 160)
	await presenter.play_inward(viewport, frame, true)
	_check(presenter.renderer.is_fully_covered() and presenter.renderer.cell_order.size() == 20 * 20, "the reusable presenter rebuilds cleanly for a later 160x160 run")
	presenter.reset()
	presenter.queue_free()
	frame.queue_free()
	viewport.queue_free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
