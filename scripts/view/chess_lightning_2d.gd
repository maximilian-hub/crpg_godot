extends Node2D
class_name ChessLightning2D

const RIFT_SHADER := preload("res://effects/chess_lightning_rift.gdshader")

var points := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var main_rift_segments: Array[PackedVector2Array] = []
var branch_rift_segments: Array[Array] = []
var width := 4.0
var visible_strength := 0.0
var checker_size := 8.0
var edge_roughness := 3.0
var rift_material: ShaderMaterial


func _init() -> void:
	rift_material = ShaderMaterial.new()
	rift_material.shader = RIFT_SHADER
	material = rift_material
	rift_material.set_shader_parameter("checker_size", checker_size)
	rift_material.set_shader_parameter("visible_strength", visible_strength)


func configure_path(start: Vector2, finish: Vector2, segment_length: float, displacement: float, seed: int, beam := false, branch_count := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	points = _make_path(start, finish, segment_length, displacement, rng)
	main_rift_segments = _make_rift_segments(points, width, edge_roughness, rng)
	branches.clear()
	branch_rift_segments.clear()
	if beam and points.size() > 3:
		for branch_index in range(branch_count):
			var origin_index := rng.randi_range(1, points.size() - 2)
			var origin := points[origin_index]
			var direction := (finish - start).normalized().rotated(rng.randf_range(-1.4, 1.4))
			var branch_end := origin + direction * rng.randf_range(35.0, 90.0)
			var branch := _make_path(origin, branch_end, segment_length, displacement * 0.65, rng)
			branches.append(branch)
			branch_rift_segments.append(_make_rift_segments(branch, maxf(width * 0.45, 1.0), edge_roughness * 0.65, rng))
	rift_material.set_shader_parameter("checker_size", checker_size)
	queue_redraw()


func show_strength(value: float) -> void:
	visible_strength = clampf(value, 0.0, 1.0)
	visible = visible_strength > 0.0
	rift_material.set_shader_parameter("visible_strength", visible_strength)
	queue_redraw()


func clear() -> void:
	points.clear()
	branches.clear()
	main_rift_segments.clear()
	branch_rift_segments.clear()
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


func _make_rift_segments(path: PackedVector2Array, path_width: float, roughness: float, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if path.size() < 2:
		return result
	var left_widths := PackedFloat32Array()
	var right_widths := PackedFloat32Array()
	for index in range(path.size()):
		var envelope := sin(float(index) / float(path.size() - 1) * PI)
		var taper := maxf(envelope, 0.12)
		var half_width := maxf(path_width * 0.5 * taper, 0.5)
		left_widths.append(maxf(half_width + rng.randf_range(-roughness, roughness) * envelope, 0.5))
		right_widths.append(maxf(half_width + rng.randf_range(-roughness, roughness) * envelope, 0.5))
	for index in range(path.size() - 1):
		var tangent := (path[index + 1] - path[index]).normalized()
		if tangent.is_zero_approx():
			continue
		var normal := Vector2(-tangent.y, tangent.x)
		# Extending by one pixel makes neighboring strips overlap at their
		# corners, avoiding pinholes without requiring a self-intersecting mesh.
		var start := path[index] - tangent
		var finish := path[index + 1] + tangent
		result.append(PackedVector2Array([
			(start + normal * left_widths[index]).round(),
			(finish + normal * left_widths[index + 1]).round(),
			(finish - normal * right_widths[index + 1]).round(),
			(start - normal * right_widths[index]).round(),
		]))
	return result


func _draw() -> void:
	if main_rift_segments.is_empty() or visible_strength <= 0.0:
		return
	for segment in main_rift_segments:
		draw_colored_polygon(segment, Color.WHITE)
	for branch_segments in branch_rift_segments:
		for segment in branch_segments:
			draw_colored_polygon(segment, Color(1.0, 1.0, 1.0, 0.85))
