extends Area2D

var hasMoved = false
var coordinate: Vector2i
var type: String
var color: String

func _ready():
	pass

func set_sprite(spriteName: String):
	var sprite = $Sprite2D
	var texture = load("res://assets/pieces/" + spriteName + ".png")
	sprite.texture = texture
	print("set_sprite(" + spriteName + ") from piece.gd")
	color = spriteName.split("_")[0]
	type = spriteName.split("_")[1]
	
	

func get_color():
	return color

func get_type():
	return type
