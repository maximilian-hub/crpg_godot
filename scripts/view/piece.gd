extends Area2D

var coordinate: Vector2i
var model: ModelPiece

func _ready():
	pass

func set_model(model_data: ModelPiece):
	model = model_data
	update_sprite()

func set_sprite(sprite_name: String): # "white_queen"
	var sprite = $Sprite2D
	sprite.texture = load("res://assets/pieces/" + sprite_name + ".png")


func update_sprite():
	var sprite_name = model.color + "_" + model.type
	var sprite = $Sprite2D
	sprite.texture = load("res://assets/pieces/" + sprite_name + ".png")
	
	if model.type == "minotaur_king":
		sprite.scale = Vector2(0.5, 0.5)

func update_hp(new_hp: int):
	print("piece.gd, about to check if i've got a HpBar!")
	model.current_hp = new_hp
	if has_node("HpBar"):
		print("piece.gd here, calling update_hp!")
		$HpBar.set_hp(new_hp, model.max_hp)
