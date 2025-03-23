extends Area2D

var hasMoved = false
var coordinate: Vector2i

func _ready():
	pass

func set_sprite(spriteName: String):
	var sprite = $Sprite2D
	var texture = load("res://assets/pieces/" + spriteName + ".png")
	sprite.texture = texture
	print("set_sprite(" + spriteName + ") from piece.gd")
