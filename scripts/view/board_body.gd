extends Node2D
class_name BoardBodyView

## Temporary generated physical-board renderer. It deliberately depends only on
## projected outline geometry and presentation style, allowing its internals to
## be replaced later by textured or tile-based board art.

@onready var shadow: Polygon2D = $Shadow
@onready var shadow_mid: Polygon2D = $ShadowMid
@onready var shadow_soft: Polygon2D = $ShadowSoft
@onready var left_thickness: Polygon2D = $Thickness/Left
@onready var right_thickness: Polygon2D = $Thickness/Right
@onready var front_thickness: Polygon2D = $Thickness/Front
@onready var far_frame: Polygon2D = $TopFrame/Far
@onready var right_frame: Polygon2D = $TopFrame/Right
@onready var near_frame: Polygon2D = $TopFrame/Near
@onready var left_frame: Polygon2D = $TopFrame/Left
@onready var material_frame: Node2D = $MaterialFrame


func configure(
	board_outline: PackedVector2Array,
	presentation_scale: float,
	visual_style: Resource
) -> void:
	if board_outline.size() != 4 or visual_style == null:
		return

	var frame_width: float = float(visual_style.reference_frame_width) * presentation_scale
	var thickness: float = float(visual_style.reference_thickness) * presentation_scale
	var shadow_offset: Vector2 = Vector2(visual_style.reference_shadow_offset) * presentation_scale
	var shadow_softness: float = float(visual_style.reference_shadow_softness) * presentation_scale
	var outer: PackedVector2Array = _offset_convex_polygon(board_outline, frame_width)
	var down: Vector2 = Vector2.DOWN * thickness

	far_frame.polygon = PackedVector2Array([outer[0], outer[1], board_outline[1], board_outline[0]])
	right_frame.polygon = PackedVector2Array([outer[1], outer[2], board_outline[2], board_outline[1]])
	near_frame.polygon = PackedVector2Array([outer[3], board_outline[3], board_outline[2], outer[2]])
	left_frame.polygon = PackedVector2Array([outer[0], board_outline[0], board_outline[3], outer[3]])

	left_thickness.polygon = PackedVector2Array([outer[0], outer[3], outer[3] + down, outer[0] + down])
	right_thickness.polygon = PackedVector2Array([outer[1], outer[2], outer[2] + down, outer[1] + down])
	front_thickness.polygon = PackedVector2Array([outer[3], outer[2], outer[2] + down, outer[3] + down])
	var shadow_origin := down + shadow_offset
	shadow.polygon = _translated_polygon(outer, shadow_origin)
	shadow_mid.polygon = _translated_polygon(_offset_convex_polygon(outer, shadow_softness * 0.45), shadow_origin)
	shadow_soft.polygon = _translated_polygon(_offset_convex_polygon(outer, shadow_softness), shadow_origin)
	# Material UVs consistently run along the outer edge first, then return along
	# the inner edge. The flat Polygon2Ds use mixed winding for draw order, which
	# would otherwise make the near and left rails sample differently.
	var top_quads: Array[PackedVector2Array] = [
		PackedVector2Array([outer[0], outer[1], board_outline[1], board_outline[0]]),
		PackedVector2Array([outer[1], outer[2], board_outline[2], board_outline[1]]),
		PackedVector2Array([outer[2], outer[3], board_outline[3], board_outline[2]]),
		PackedVector2Array([outer[3], outer[0], board_outline[0], board_outline[3]]),
	]
	var edge_quads: Array[PackedVector2Array] = [left_thickness.polygon, right_thickness.polygon, front_thickness.polygon]
	material_frame.configure(top_quads, edge_quads, presentation_scale, visual_style)

	far_frame.color = visual_style.frame_top_color
	right_frame.color = visual_style.frame_top_color
	near_frame.color = visual_style.frame_top_color
	left_frame.color = visual_style.frame_top_color
	front_thickness.color = visual_style.frame_front_color
	left_thickness.color = visual_style.frame_side_color
	right_thickness.color = visual_style.frame_side_color
	var shadow_color: Color = visual_style.shadow_color
	shadow.color = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a * 0.65)
	shadow_mid.color = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a * 0.32)
	shadow_soft.color = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a * 0.14)
	var show_shadow := bool(visual_style.board_shadow_enabled)
	shadow.visible = show_shadow
	shadow_mid.visible = show_shadow
	shadow_soft.visible = show_shadow
	var show_flat_frame := not bool(visual_style.frame_material_enabled)
	$TopFrame.visible = show_flat_frame
	$Thickness.visible = show_flat_frame


func _offset_convex_polygon(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(polygon.size()):
		var previous := polygon[(index - 1 + polygon.size()) % polygon.size()]
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var previous_direction := (current - previous).normalized()
		var next_direction := (next - current).normalized()
		var previous_normal := Vector2(previous_direction.y, -previous_direction.x)
		var next_normal := Vector2(next_direction.y, -next_direction.x)
		var first_line_point := current + previous_normal * distance
		var second_line_point := current + next_normal * distance
		result.append(_line_intersection(
			first_line_point,
			previous_direction,
			second_line_point,
			next_direction
		).round())
	return result


func _line_intersection(first_point: Vector2, first_direction: Vector2, second_point: Vector2, second_direction: Vector2) -> Vector2:
	var denominator := first_direction.cross(second_direction)
	if is_zero_approx(denominator):
		return first_point
	var distance := (second_point - first_point).cross(second_direction) / denominator
	return first_point + first_direction * distance


func _translated_polygon(polygon: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var translated := PackedVector2Array()
	for point in polygon:
		translated.append((point + offset).round())
	return translated
