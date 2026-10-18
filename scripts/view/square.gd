extends Area2D
class_name SquareView

const DEFAULT_HIGHLIGHT_COLOR := Color(0.905882, 0.745098, 0.0470588, 0.392157)
const AREA_PREVIEW_COLOR := Color(1.0, 0.20, 0.04, 0.72)
const OBSCURED_HIGHLIGHT_COLOR := Color(0.92, 0.08, 0.08, 0.62)

var coordinate: Vector2i
signal square_clicked(coordinate: Vector2i)
signal square_touch_clicked(coordinate: Vector2i)
signal editor_pointer_pressed(coordinate: Vector2i)
signal editor_pointer_entered(coordinate: Vector2i)
signal editor_pointer_exited(coordinate: Vector2i)

func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(func(): editor_pointer_entered.emit(coordinate))
	mouse_exited.connect(func(): editor_pointer_exited.emit(coordinate))

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		square_clicked.emit(coordinate)
		editor_pointer_pressed.emit(coordinate)
	elif event is InputEventScreenTouch and event.pressed:
		square_touch_clicked.emit(coordinate)
		editor_pointer_pressed.emit(coordinate)

func configure_geometry(model_coordinate: Vector2i, points: PackedVector2Array) -> void:
	coordinate = model_coordinate
	$Surface.polygon = points
	$CollisionPolygon2D.polygon = points
	$Highlight.polygon = points

func set_color(color: Color) -> void:
	$Surface.color = color

func set_surface_visible(value: bool) -> void:
	$Surface.visible = value

func highlight() -> void:
	$Highlight.color = DEFAULT_HIGHLIGHT_COLOR
	$Highlight.visible = true

func highlight_area_preview() -> void:
	$Highlight.color = AREA_PREVIEW_COLOR
	$Highlight.visible = true

func highlight_obscured() -> void:
	$Highlight.color = OBSCURED_HIGHLIGHT_COLOR
	$Highlight.visible = true

func clear_highlight() -> void:
	$Highlight.visible = false
