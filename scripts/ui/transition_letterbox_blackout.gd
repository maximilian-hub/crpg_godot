extends Control
class_name TransitionLetterboxBlackout

var frame_rect := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_frame_rect(value: Rect2) -> void:
	frame_rect = value
	queue_redraw()


func _draw() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, size)
	var clipped := frame_rect.intersection(viewport_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		draw_rect(viewport_rect, Color.BLACK, true)
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, clipped.position.y)), Color.BLACK, true)
	draw_rect(Rect2(Vector2(0.0, clipped.end.y), Vector2(size.x, size.y - clipped.end.y)), Color.BLACK, true)
	draw_rect(Rect2(Vector2(0.0, clipped.position.y), Vector2(clipped.position.x, clipped.size.y)), Color.BLACK, true)
	draw_rect(Rect2(Vector2(clipped.end.x, clipped.position.y), Vector2(size.x - clipped.end.x, clipped.size.y)), Color.BLACK, true)
