extends Area2D

var coordinate: Vector2i

func _ready():
	connect("input_event", _on_input_event)

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Clicked tile at", coordinate)

func set_color(color: Color):
	var sprite = $Sprite2D
	sprite.modulate = color

func highlight():
	$Highlight.visible = true
	print("im a lil square and im LIGHTING UP!!!!!")

func clear_highlight():
	$Highlight.visible = false
