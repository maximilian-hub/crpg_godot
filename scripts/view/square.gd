extends Area2D
class_name SquareView

var coordinate: Vector2i
signal square_clicked(coordinate: Vector2i)
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
	$Highlight.visible = true

func clear_highlight() -> void:
	$Highlight.visible = false
