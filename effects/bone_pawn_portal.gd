extends Node2D
class_name BonePawnSummonPortal

const DISPLAY_SCALE := Vector2(0.5, 0.5)

const OPEN_DURATION := 0.12
const CLOSE_DURATION := 0.15
var presentation_scale := 1.0

func configure_presentation_scale(value: float) -> void:
	presentation_scale = maxf(value, 0.01)

func _open_scale() -> Vector2:
	return DISPLAY_SCALE * presentation_scale

func _ready() -> void:
	z_index = -1
	scale = _open_scale() * 0.05
	modulate.a = 0.0

func open() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", _open_scale(), OPEN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, OPEN_DURATION)
	await tween.finished

func close() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", _open_scale() * 0.05, CLOSE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, CLOSE_DURATION)
	await tween.finished
	queue_free()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, 42.0, Color(0.055, 0.005, 0.09, 0.9))
	draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 64, Color(0.36, 0.02, 0.58, 0.95), 5.0, true)
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 64, Color(0.65, 0.12, 0.9, 0.8), 3.0, true)
	draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 48, Color(0.2, 0.0, 0.34, 0.95), 7.0, true)
	for mote in [Vector2(-25, -15), Vector2(-8, 22), Vector2(13, -20), Vector2(29, 10)]:
		draw_circle(mote, 2.5, Color(0.72, 0.24, 1.0, 0.9))
