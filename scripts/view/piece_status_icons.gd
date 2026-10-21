extends Node2D
class_name PieceStatusIcons

var statuses: Array[StringName] = []

func set_statuses(values: Array[StringName]) -> void:
	statuses.assign(values)
	visible = not statuses.is_empty()
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for index in statuses.size():
		var center := Vector2(index * 18.0, 0.0)
		draw_circle(center, 8.0, Color(0.04, 0.05, 0.09, 0.94))
		draw_arc(center, 7.0, 0.0, TAU, 24, Color.WHITE, 1.2, true)
		var label := "X" if statuses[index] == &"suppressed" else "💧"
		var size := 10 if statuses[index] == &"suppressed" else 9
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, center + Vector2(-width * 0.5, 3.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("ff626f") if statuses[index] == &"suppressed" else Color("72d9ff"))
