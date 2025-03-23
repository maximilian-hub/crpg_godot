extends Area2D

var coordinate: Vector2i
var model: ModelPiece

func _ready():
	pass

func set_model(model_data: ModelPiece):
	model = model_data
	update_sprite()

func update_sprite():
	var sprite_name = model.color + "_" + model.type
	var sprite = $Sprite2D
	sprite.texture = load("res://assets/pieces/" + sprite_name + ".png")
	
	if model.type == "minotaur_king":
		sprite.scale = Vector2(0.13, 0.13)
