#~~~~~~~~NEW FILE: piece.gd~~~~~~~~~~~~
# Attached to the piece scene.
# The View layer for each piece.

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
	elif model.type == "bone_pawn":
		sprite.scale = Vector2(0.125, 0.125)
	elif model.type == "necromancer_king":
		sprite.scale = Vector2(0.13,0.13)

func update_hp(new_hp: int):
	model.current_hp = new_hp
	if has_node("HpBar"):
		$HpBar.set_hp(new_hp, model.max_hp)
