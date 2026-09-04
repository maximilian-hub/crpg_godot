extends Node2D
class_name ChessCaptureClackEffect

const DURATION := 0.18
const RAY_COUNT := 8

var elapsed := 0.0
var world_scale := 1.0


func configure(scale_factor: float) -> void:
	world_scale = maxf(scale_factor, 0.01)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(elapsed / DURATION, 0.0, 1.0)
	var alpha := 1.0 - progress
	var inner_radius := lerpf(3.0, 12.0, progress) * world_scale
	var outer_radius := inner_radius + lerpf(7.0, 2.0, progress) * world_scale
	var color := Color(1.0, 1.0, 1.0, alpha)
	var width := maxf(round(2.0 * world_scale), 1.0)
	for index in range(RAY_COUNT):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(RAY_COUNT))
		draw_line((direction * inner_radius).round(), (direction * outer_radius).round(), color, width)
	var core_size := maxf(round(3.0 * world_scale * (1.0 - progress * 0.5)), 1.0)
	draw_rect(Rect2(Vector2.ONE * -core_size * 0.5, Vector2.ONE * core_size), Color(1.0, 1.0, 1.0, alpha))
