extends Control
class_name BoardPiecePaletteItem

signal selected(item)
signal drag_requested(item)

const PIECE_SCENE := preload("res://scenes/piece.tscn")
const DRAG_THRESHOLD := 6.0

var type_id: StringName = &""
var color := ""
var is_cursor_tool := false
var is_delete_tool := false
var selected_state := false
var interaction_enabled := true
var preview: PieceView = null
var shortcut_label: Label = null
var press_position := Vector2.ZERO
var press_active := false
var drag_started := false

func configure_piece(piece_type_id: StringName, piece_color: String) -> void:
	type_id = piece_type_id
	color = piece_color
	is_cursor_tool = false
	preview = PIECE_SCENE.instantiate()
	preview.input_pickable = false
	preview.set_model(ChessPieceCatalog.create_piece(type_id, color, Vector2i.ZERO))
	add_child(preview)
	_layout_content()

func configure_cursor() -> void:
	is_cursor_tool = true
	shortcut_label = Label.new()
	shortcut_label.text = "Esc"
	shortcut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_label.add_theme_font_size_override("font_size", 10)
	shortcut_label.add_theme_color_override("font_color", Color("d8c6a0"))
	shortcut_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	shortcut_label.offset_left = -27.0
	shortcut_label.offset_top = -18.0
	shortcut_label.offset_right = -3.0
	shortcut_label.offset_bottom = -2.0
	add_child(shortcut_label)
	queue_redraw()

func configure_delete() -> void:
	is_delete_tool = true
	queue_redraw()

func set_selected_state(value: bool) -> void:
	selected_state = value
	queue_redraw()

func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value
	modulate.a = 1.0 if value else 0.42
	if not value:
		press_active = false
		drag_started = false

func _ready() -> void:
	custom_minimum_size = Vector2(62, 54)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_layout_content)
	_layout_content()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_active = true
			drag_started = false
			press_position = event.position
			selected.emit(self)
			accept_event()
		else:
			press_active = false
			drag_started = false
	elif event is InputEventMouseMotion and press_active and not is_cursor_tool and not is_delete_tool and not drag_started:
		if event.position.distance_to(press_position) >= DRAG_THRESHOLD:
			drag_started = true
			drag_requested.emit(self)
			accept_event()

func _layout_content() -> void:
	if not is_node_ready():
		return
	if preview != null and preview.sprite.texture != null:
		var texture_size := preview.sprite.texture.get_size()
		var available := Vector2(maxf(size.x - 14.0, 1.0), maxf(size.y - 8.0, 1.0))
		var fit_scale := minf(available.x / texture_size.x, available.y / texture_size.y)
		preview.scale = Vector2.ONE * fit_scale
		preview.position = Vector2(size.x * 0.5, size.y - 4.0)

func _draw() -> void:
	var fill := Color("4a4850") if selected_state else Color("343239")
	var border := Color("d1a43a") if selected_state else Color("5e5a66")
	draw_style_box(_make_style(fill, border), Rect2(Vector2.ZERO, size))
	if is_cursor_tool:
		var center := size * 0.5
		var points := PackedVector2Array([
			center + Vector2(-12, -17), center + Vector2(13, 5),
			center + Vector2(3, 7), center + Vector2(9, 18),
			center + Vector2(2, 21), center + Vector2(-4, 10),
			center + Vector2(-12, 18),
		])
		draw_colored_polygon(points, Color("f1eee7"))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color("201e26"), 2.0, true)
	elif is_delete_tool:
		var center := size * 0.5
		var body := Rect2(center + Vector2(-10, -9), Vector2(20, 24))
		draw_rect(body, Color("f1eee7"), true)
		draw_rect(body, Color("201e26"), false, 2.0)
		draw_rect(Rect2(center + Vector2(-13, -14), Vector2(26, 5)), Color("f1eee7"), true)
		draw_rect(Rect2(center + Vector2(-13, -14), Vector2(26, 5)), Color("201e26"), false, 2.0)
		draw_line(center + Vector2(-5, -17), center + Vector2(5, -17), Color("201e26"), 3.0)
		for x in [-5.0, 0.0, 5.0]:
			draw_line(center + Vector2(x, -5), center + Vector2(x, 10), Color("201e26"), 1.5)

func _make_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3 if selected_state else 1)
	style.set_corner_radius_all(5)
	return style
