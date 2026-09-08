extends Node2D
class_name ChessSelectionOrb2D

var radius := 13.0
var opacity := 0.68
var speed := 1.15
var core_color := Color.WHITE
var accent_color := Color.CYAN
var elapsed := 0.0
var duration_scale := 1.0


func configure(new_radius: float, new_opacity: float, new_speed: float, core: Color, accent: Color) -> void:
	radius = new_radius
	opacity = new_opacity
	speed = new_speed
	core_color = core
	accent_color = accent
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta * speed / maxf(duration_scale, 0.01)
	queue_redraw()


func _draw() -> void:
	var breathe := 1.0 + sin(elapsed * TAU) * 0.06
	var r := radius * breathe
	var glow := accent_color
	glow.a = opacity * 0.22
	draw_circle(Vector2.ZERO, r, glow, false, 2.0, false)
	var shell := core_color.lerp(accent_color, 0.5 + sin(elapsed * 3.7) * 0.25)
	shell.a = opacity
	draw_arc(Vector2.ZERO, r * 0.72, 0.0, TAU, 16, shell, 2.0, false)
	for index in range(4):
		var angle := elapsed * (1.0 if index % 2 == 0 else -0.7) + float(index) * TAU / 4.0
		var point := Vector2.RIGHT.rotated(angle) * r
		draw_rect(Rect2((point - Vector2.ONE).round(), Vector2(2, 2)), shell)
