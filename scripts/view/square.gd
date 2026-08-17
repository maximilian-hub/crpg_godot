extends Area2D
class_name SquareView

var coordinate: Vector2i
signal square_clicked(coordinate: Vector2i)

func _ready() -> void:
	input_event.connect(_on_input_event)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		square_clicked.emit(coordinate)

func configure_geometry(model_coordinate: Vector2i, points: PackedVector2Array) -> void:
	coordinate = model_coordinate
	$Surface.polygon = points
	$CollisionPolygon2D.polygon = points
	$Highlight.polygon = points

func set_color(color: Color) -> void:
	$Surface.color = color

func highlight() -> void:
	$Highlight.visible = true

func clear_highlight() -> void:
	$Highlight.visible = false
