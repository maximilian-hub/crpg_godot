extends Area2D

var coordinate: Vector2

func _ready():
	connect("input_event", _on_input_event)

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Clicked tile at", coordinate)

func set_color(color: Color):
	var sprite = $Sprite2D
	print("uh")
	if sprite == null:
		push_error("Sprite2D not found on tile!")
		print("um")
	else:
		sprite.modulate = color
		print("sprite modulated to ", color)
