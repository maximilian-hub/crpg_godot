extends Area2D

func set_sprite(spriteName: String):
	var sprite = $Sprite2D
	var texture = load("res://assets/pieces/" + spriteName + ".png")
	sprite.texture = texture
