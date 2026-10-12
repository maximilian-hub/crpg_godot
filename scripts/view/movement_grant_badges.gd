extends Node2D
class_name MovementGrantBadges

const BADGE_RADIUS := 7.0
const BADGE_GAP := 2.0
const FONT_SIZE := 10
const LABELS := {
	&"pawn": "P",
	&"knight": "N",
	&"bishop": "B",
	&"rook": "R",
}
const COLORS := {
	&"pawn": Color("79b8ff"),
	&"knight": Color("d69cff"),
	&"bishop": Color("72e6b1"),
	&"rook": Color("ffbd66"),
}

var movement_types: Array[StringName] = []
var pop_tween: Tween = null


func set_movement_types(values: Array[StringName], animate := false) -> void:
	movement_types.assign(values)
	visible = not movement_types.is_empty()
	queue_redraw()
	if animate and visible:
		_play_pop()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for index in movement_types.size():
		var movement_type := movement_types[index]
		if not LABELS.has(movement_type):
			continue
		var center := Vector2(index * (BADGE_RADIUS * 2.0 + BADGE_GAP), 0.0)
		draw_circle(center, BADGE_RADIUS + 2.0, Color(0.05, 0.04, 0.08, 0.92), true, -1.0, true)
		draw_circle(center, BADGE_RADIUS, COLORS.get(movement_type, Color.WHITE), true, -1.0, true)
		draw_arc(center, BADGE_RADIUS, 0.0, TAU, 24, Color(1.0, 0.94, 0.72), 1.25, true)
		var label: String = LABELS[movement_type]
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, center + Vector2(-label_width * 0.5, 3.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.08, 0.06, 0.10))


func _play_pop() -> void:
	if pop_tween != null and pop_tween.is_valid():
		pop_tween.kill()
	scale = Vector2.ONE * 0.25
	pop_tween = create_tween()
	pop_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "scale", Vector2.ONE * 1.18, 0.18)
	pop_tween.tween_property(self, "scale", Vector2.ONE, 0.10)
