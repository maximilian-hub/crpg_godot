extends Node2D
class_name ChessLightning2D

const RIFT_SHADER := preload("res://effects/chess_lightning_rift.gdshader")

var points := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var main_rift_segments: Array[PackedVector2Array] = []
var branch_rift_segments: Array[Array] = []
var impact_paths: Array[PackedVector2Array] = []
var impact_rift_segments: Array[Array] = []
var width := 4.0
var visible_strength := 0.0
var checker_size := 8.0
var edge_roughness := 3.0
var curve_max := 36.0
var impact_bolt_count := 5
var impact_radius_min := 18.0
var impact_radius_max := 52.0
var impact_bolt_width := 3.0
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
	# Avoid consuming an RNG value at zero so disabling the curve reproduces
	# the previous seeded jagged path exactly.
	var main_curve := rng.randf_range(-curve_max, curve_max) if curve_max > 0.0 else 0.0
	points = _make_path(start, finish, segment_length, displacement, rng, main_curve)
	main_rift_segments = _make_rift_segments(points, width, edge_roughness, rng)
	branches.clear()
	branch_rift_segments.clear()
	impact_paths.clear()
	impact_rift_segments.clear()
	if beam and points.size() > 3:
		for branch_index in range(branch_count):
			var origin_index := rng.randi_range(1, points.size() - 2)
			var origin := points[origin_index]
			var direction := (finish - start).normalized().rotated(rng.randf_range(-1.4, 1.4))
			var branch_end := origin + direction * rng.randf_range(35.0, 90.0)
			var branch := _make_path(origin, branch_end, segment_length, displacement * 0.65, rng)
			branches.append(branch)
			branch_rift_segments.append(_make_rift_segments(branch, maxf(width * 0.45, 1.0), edge_roughness * 0.65, rng))
	var minimum_radius := minf(impact_radius_min, impact_radius_max)
	var maximum_radius := maxf(impact_radius_min, impact_radius_max)
	for impact_index in range(maxi(impact_bolt_count, 0)):
		var direction := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var radius := rng.randf_range(maxf(minimum_radius, 0.0), maxf(maximum_radius, 0.0))
		var impact_end := finish + direction * radius
		var impact_path := _make_path(finish, impact_end, segment_length, displacement * 0.45, rng)
		impact_paths.append(impact_path)
		# Impact bolts begin with body at the strike and taper to a one-pixel
		# outer point, making the contact read as an outward discharge.
		impact_rift_segments.append(_make_rift_segments(impact_path, impact_bolt_width, edge_roughness * 0.5, rng, false, true))
	rift_material.set_shader_parameter("checker_size", checker_size)
	queue_redraw()


## Builds only the radial contact bolts used where activation lightning strikes
## a King, allowing other effects to reuse the same hit-marker language.
func configure_impact_marker(center: Vector2, radius: float, marker_width: float, seed: int, bolt_count := 5) -> void:
	points.clear()
	branches.clear()
	main_rift_segments.clear()
	branch_rift_segments.clear()
	impact_paths.clear()
	impact_rift_segments.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var resolved_radius := maxf(radius, 1.0)
	for _index in range(maxi(bolt_count, 1)):
		var direction := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var impact_end := center + direction * rng.randf_range(resolved_radius * 0.55, resolved_radius)
		var impact_path := _make_path(center, impact_end, maxf(resolved_radius * 0.28, 2.0), resolved_radius * 0.18, rng)
		impact_paths.append(impact_path)
		impact_rift_segments.append(_make_rift_segments(impact_path, marker_width, edge_roughness * 0.5, rng, false, true))
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
	impact_paths.clear()
	impact_rift_segments.clear()
	show_strength(0.0)


func _make_path(start: Vector2, finish: Vector2, segment_length: float, displacement: float, rng: RandomNumberGenerator, curve_offset := 0.0) -> PackedVector2Array:
	var path := PackedVector2Array([start])
	var delta := finish - start
	var distance := delta.length()
	var segment_count := maxi(int(ceil(distance / maxf(segment_length, 2.0))), 2)
	var baseline_normal := Vector2(-delta.y, delta.x).normalized()
	for index in range(1, segment_count):
		var progress := float(index) / float(segment_count)
		var envelope := sin(progress * PI)
		var curve_envelope := 4.0 * progress * (1.0 - progress)
		var curved_baseline := start.lerp(finish, progress) + baseline_normal * curve_offset * curve_envelope
		# Differentiate the quadratic baseline so the jagged displacement is
		# perpendicular to the local curve rather than the original straight ray.
		var curve_tangent := (delta + baseline_normal * curve_offset * 4.0 * (1.0 - 2.0 * progress)).normalized()
		var curve_normal := Vector2(-curve_tangent.y, curve_tangent.x)
		path.append(curved_baseline + curve_normal * rng.randf_range(-displacement, displacement) * envelope)
	path.append(finish)
	return path


func _make_rift_segments(path: PackedVector2Array, path_width: float, roughness: float, rng: RandomNumberGenerator, taper_start := true, taper_end := true) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if path.size() < 2:
		return result
	var left_widths := PackedFloat32Array()
	var right_widths := PackedFloat32Array()
	for index in range(path.size()):
		var progress := float(index) / float(path.size() - 1)
		var envelope := sin(progress * PI)
		var taper := 1.0
		if taper_start and taper_end:
			taper = envelope
		elif taper_start:
			taper = progress
		elif taper_end:
			taper = 1.0 - progress
		taper = maxf(taper, 0.12)
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
	if (main_rift_segments.is_empty() and impact_rift_segments.is_empty()) or visible_strength <= 0.0:
		return
	for segment in main_rift_segments:
		draw_colored_polygon(segment, Color.WHITE)
	for branch_segments in branch_rift_segments:
		for segment in branch_segments:
			draw_colored_polygon(segment, Color(1.0, 1.0, 1.0, 0.85))
	for impact_segments in impact_rift_segments:
		for segment in impact_segments:
			draw_colored_polygon(segment, Color.WHITE)
