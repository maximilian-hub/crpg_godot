extends Node2D
class_name ChessLightning2D

var points := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var width := 4.0
var visible_strength := 0.0
var checker_size := 8.0


func configure_path(start: Vector2, finish: Vector2, segment_length: float, displacement: float, seed: int, beam := false, branch_count := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	points = _make_path(start, finish, segment_length, displacement, rng)
	branches.clear()
	if beam and points.size() > 3:
		for branch_index in range(branch_count):
			var origin_index := rng.randi_range(1, points.size() - 2)
			var origin := points[origin_index]
			var direction := (finish - start).normalized().rotated(rng.randf_range(-1.4, 1.4))
			var branch_end := origin + direction * rng.randf_range(35.0, 90.0)
			branches.append(_make_path(origin, branch_end, segment_length, displacement * 0.65, rng))
	queue_redraw()


func show_strength(value: float) -> void:
	visible_strength = clampf(value, 0.0, 1.0)
	visible = visible_strength > 0.0
	queue_redraw()


func clear() -> void:
	points.clear()
	branches.clear()
	show_strength(0.0)


func _make_path(start: Vector2, finish: Vector2, segment_length: float, displacement: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var path := PackedVector2Array([start])
	var delta := finish - start
	var distance := delta.length()
	var segment_count := maxi(int(ceil(distance / maxf(segment_length, 2.0))), 2)
	var normal := Vector2(-delta.y, delta.x).normalized()
	for index in range(1, segment_count):
		var progress := float(index) / float(segment_count)
		var envelope := sin(progress * PI)
		path.append(start.lerp(finish, progress) + normal * rng.randf_range(-displacement, displacement) * envelope)
	path.append(finish)
	return path


func _draw() -> void:
	if points.size() < 2 or visible_strength <= 0.0:
		return
	_draw_checker_path(points, width, visible_strength)
	for branch in branches:
		_draw_checker_path(branch, maxf(width * 0.45, 1.0), visible_strength * 0.85)


func _draw_checker_path(path: PackedVector2Array, path_width: float, strength: float) -> void:
	for index in range(path.size() - 1):
		var color := Color.WHITE if index % 2 == 0 else Color("090912")
		color.a = strength
		draw_line(path[index].round(), path[index + 1].round(), color, path_width, false)
