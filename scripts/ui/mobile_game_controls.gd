extends Control
class_name MobileGameControls

## Touch-only game controls that emit the same actions used by keyboard input.
## Keeping this at the root presentation level lets it survive scene swaps and
## remain available for dialogue presented over either exploration or battle.

@export var force_visible_for_testing := false
@export_range(0.04, 0.12, 0.005) var button_radius_ratio := 0.072
@export_range(0.2, 1.0, 0.05) var idle_opacity := 0.42
@export_range(0.2, 1.0, 0.05) var pressed_opacity := 0.78

var gameplay_controls_requested := false
var dialogue_controls_requested := false
var pointer_actions: Dictionary = {}
var action_press_counts: Dictionary = {}
var action_regions: Dictionary = {}
var button_radius := 64.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_rebuild_layout)
	_refresh_visibility()
	_rebuild_layout()


func set_gameplay_controls_requested(requested: bool) -> void:
	gameplay_controls_requested = requested
	_refresh_visibility()


func set_dialogue_controls_requested(requested: bool) -> void:
	dialogue_controls_requested = requested
	_refresh_visibility()


func set_force_visible_for_testing(value: bool) -> void:
	force_visible_for_testing = value
	_refresh_visibility()


func _refresh_visibility() -> void:
	var touch_device := OS.has_feature("mobile") or OS.has_feature("android")
	var should_show := (touch_device or force_visible_for_testing) and (
		gameplay_controls_requested or dialogue_controls_requested
	)
	if visible == should_show:
		set_process_input(should_show)
		return
	visible = should_show
	set_process_input(should_show)
	if not should_show:
		_release_all_actions()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_update_pointer_action(touch.index, _action_at(touch.position))
		else:
			_update_pointer_action(touch.index, &"")
		if touch.index in pointer_actions or _action_at(touch.position) != &"":
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var previous_action: StringName = pointer_actions.get(drag.index, &"")
		var next_action := _action_at(drag.position)
		_update_pointer_action(drag.index, next_action)
		if previous_action != &"" or next_action != &"":
			get_viewport().set_input_as_handled()


func _update_pointer_action(pointer_index: int, next_action: StringName) -> void:
	var previous_action: StringName = pointer_actions.get(pointer_index, &"")
	if previous_action == next_action:
		return
	if previous_action != &"":
		_release_action(previous_action)
		pointer_actions.erase(pointer_index)
	if next_action != &"":
		pointer_actions[pointer_index] = next_action
		_press_action(next_action)
	queue_redraw()


func _press_action(action: StringName) -> void:
	var press_count := int(action_press_counts.get(action, 0)) + 1
	action_press_counts[action] = press_count
	if press_count == 1:
		_emit_action(action, true)


func _release_action(action: StringName) -> void:
	var press_count := maxi(0, int(action_press_counts.get(action, 0)) - 1)
	if press_count == 0:
		action_press_counts.erase(action)
		_emit_action(action, false)
	else:
		action_press_counts[action] = press_count


func _release_all_actions() -> void:
	for action: StringName in action_press_counts.keys():
		_emit_action(action, false)
	action_press_counts.clear()
	pointer_actions.clear()


func _emit_action(action: StringName, pressed: bool) -> void:
	var action_event := InputEventAction.new()
	action_event.action = action
	action_event.pressed = pressed
	action_event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(action_event)


func _action_at(point: Vector2) -> StringName:
	for action: StringName in action_regions:
		var center: Vector2 = action_regions[action]
		if point.distance_squared_to(center) <= button_radius * button_radius:
			return action
	return &""


func _rebuild_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)
	if OS.has_feature("mobile") or OS.has_feature("android"):
		var display_safe_area := Rect2(DisplayServer.get_display_safe_area())
		if (
			display_safe_area.size.x > 0.0
			and display_safe_area.size.y > 0.0
			and display_safe_area.position.x >= 0.0
			and display_safe_area.position.y >= 0.0
			and display_safe_area.end.x <= viewport_size.x + 1.0
			and display_safe_area.end.y <= viewport_size.y + 1.0
		):
			safe_rect = display_safe_area
	var layout := calculate_layout(viewport_size, safe_rect, button_radius_ratio)
	button_radius = layout.button_radius
	action_regions = layout.regions
	queue_redraw()


static func calculate_layout(
	viewport_size: Vector2,
	safe_rect: Rect2,
	radius_ratio := 0.072
) -> Dictionary:
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		safe_rect = Rect2(Vector2.ZERO, viewport_size)
	var short_side := minf(safe_rect.size.x, safe_rect.size.y)
	var radius := clampf(short_side * radius_ratio, 38.0, 92.0)
	var edge_margin := radius * 0.55
	var dpad_center := Vector2(
		safe_rect.position.x + edge_margin + radius * 2.15,
		safe_rect.end.y - edge_margin - radius * 2.15
	)
	var dpad_step := radius * 1.35
	var a_center := Vector2(
		safe_rect.end.x - edge_margin - radius,
		safe_rect.end.y - edge_margin - radius * 1.55
	)
	var b_center := a_center + Vector2(-radius * 2.15, radius * 0.55)
	return {
		"button_radius": radius,
		"regions": {
			&"move_up": dpad_center + Vector2.UP * dpad_step,
			&"move_down": dpad_center + Vector2.DOWN * dpad_step,
			&"move_left": dpad_center + Vector2.LEFT * dpad_step,
			&"move_right": dpad_center + Vector2.RIGHT * dpad_step,
			&"interact": a_center,
			&"back": b_center,
		},
	}


func _draw() -> void:
	if not visible:
		return
	for action: StringName in action_regions:
		var center: Vector2 = action_regions[action]
		var pressed := int(action_press_counts.get(action, 0)) > 0
		var opacity := pressed_opacity if pressed else idle_opacity
		var fill := Color(0.08, 0.07, 0.12, opacity)
		var outline := Color(0.92, 0.84, 0.64, minf(1.0, opacity + 0.18))
		draw_circle(center, button_radius, fill)
		draw_arc(center, button_radius - 2.0, 0.0, TAU, 32, outline, 3.0, true)
		if action == &"interact" or action == &"back":
			_draw_letter(center, "A" if action == &"interact" else "B", outline)
		else:
			_draw_direction(center, DIRECTIONS_FOR_ACTION[action], outline)


const DIRECTIONS_FOR_ACTION := {
	&"move_up": Vector2.UP,
	&"move_down": Vector2.DOWN,
	&"move_left": Vector2.LEFT,
	&"move_right": Vector2.RIGHT,
}


func _draw_direction(center: Vector2, direction: Vector2, color: Color) -> void:
	var forward := direction * button_radius * 0.42
	var side := Vector2(-direction.y, direction.x) * button_radius * 0.28
	var back := -direction * button_radius * 0.24
	draw_colored_polygon(PackedVector2Array([
		center + forward,
		center + back + side,
		center + back - side,
	]), color)


func _draw_letter(center: Vector2, letter: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(18, roundi(button_radius * 0.72))
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := center - Vector2(text_size.x * 0.5, -text_size.y * 0.34)
	draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
