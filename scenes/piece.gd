extends Area2D

signal piece_clicked(piece)
var hasMoved = false
var coordinate: Vector2

func _ready():
	connect("input_event", _on_input_event)

func _on_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("piece_clicked", self)

func set_sprite(spriteName: String):
	var sprite = $Sprite2D
	var texture = load("res://assets/pieces/" + spriteName + ".png")
	sprite.texture = texture
	
