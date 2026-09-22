extends Control
class_name DialoguePortraitShadow

var enabled := false
var opening_insets := Vector4.ZERO
var edge_thickness := Vector4.ZERO
var edge_opacity := Vector4.ZERO
var shadow_color := Color(0.02, 0.025, 0.03, 1.0)
var frame_overlap := 0
var bottom_offset := 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func configure(
	new_enabled: bool,
	new_opening_insets: Vector4,
	new_edge_thickness: Vector4,
	new_edge_opacity: Vector4,
	new_shadow_color: Color,
	new_frame_overlap: int,
	new_bottom_offset: int = 0
) -> void:
	enabled = new_enabled
	opening_insets = new_opening_insets
	edge_thickness = new_edge_thickness
	edge_opacity = new_edge_opacity
	shadow_color = new_shadow_color
	frame_overlap = maxi(0, new_frame_overlap)
	bottom_offset = new_bottom_offset
	queue_redraw()


func shadow_bands() -> Array:
	var bands: Array = []
	if not enabled:
		return bands
	var opening := Rect2(
		Vector2(opening_insets.x, opening_insets.y),
		Vector2(maxf(0.0, size.x - opening_insets.x - opening_insets.z), maxf(0.0, size.y - opening_insets.y - opening_insets.w))
	)
	if opening.size.x <= 0.0 or opening.size.y <= 0.0:
		return bands
	_add_vertical_bands(bands, opening, true, roundi(edge_thickness.x), edge_opacity.x)
	_add_horizontal_bands(bands, opening, true, roundi(edge_thickness.y), edge_opacity.y, 0)
	_add_vertical_bands(bands, opening, false, roundi(edge_thickness.z), edge_opacity.z)
	_add_horizontal_bands(bands, opening, false, roundi(edge_thickness.w), edge_opacity.w, bottom_offset)
	return bands


func _draw() -> void:
	for band in shadow_bands():
		draw_rect(band.rect, band.color, true)


func _add_vertical_bands(bands: Array, opening: Rect2, from_start: bool, thickness: int, opacity: float) -> void:
	thickness = maxi(0, thickness)
	opacity = clampf(opacity, 0.0, 1.0)
	if thickness == 0 or opacity <= 0.0:
		return
	if frame_overlap > 0:
		var overlap_x := opening.position.x - frame_overlap if from_start else opening.end.x
		bands.append({"rect": Rect2(overlap_x, opening.position.y - frame_overlap, frame_overlap, opening.size.y + frame_overlap * 2), "color": _color_with_opacity(opacity)})
	for index in range(thickness):
		var x := opening.position.x + index if from_start else opening.end.x - 1.0 - index
		var strength := opacity * float(thickness - index) / float(thickness)
		bands.append({"rect": Rect2(x, opening.position.y, 1.0, opening.size.y), "color": _color_with_opacity(strength)})


func _add_horizontal_bands(bands: Array, opening: Rect2, from_start: bool, thickness: int, opacity: float, offset: int) -> void:
	thickness = maxi(0, thickness)
	opacity = clampf(opacity, 0.0, 1.0)
	if thickness == 0 or opacity <= 0.0:
		return
	if frame_overlap > 0:
		var overlap_y := (opening.position.y - frame_overlap if from_start else opening.end.y) + offset
		bands.append({"rect": Rect2(opening.position.x - frame_overlap, overlap_y, opening.size.x + frame_overlap * 2, frame_overlap), "color": _color_with_opacity(opacity)})
	for index in range(thickness):
		var y := (opening.position.y + index if from_start else opening.end.y - 1.0 - index) + offset
		var strength := opacity * float(thickness - index) / float(thickness)
		bands.append({"rect": Rect2(opening.position.x, y, opening.size.x, 1.0), "color": _color_with_opacity(strength)})


func _color_with_opacity(opacity: float) -> Color:
	var result := shadow_color
	result.a *= opacity
	return result
