# model_piece.gd
class_name ModelPiece
extends Resource # or Object, but Resource makes serialization easier later

var color: String 	# black, white
var type: String 	# pawn, knight, bishop, minotaur king, etc
var coordinate: Vector2i
var view_node: Node

var max_hp: int = 1
var current_hp: int = 1

var has_moved: bool = false
var stunned: bool = false
var cooldown: int = 0

func _init(_color: String, _type: String, _coordinate: Vector2i):
	color = _color
	type = _type
	coordinate = _coordinate

	match type:
		"minotaur_king":
			max_hp = 4
		_:
			max_hp = 1
	
	current_hp = max_hp

func take_damage() -> bool:
	current_hp -= 1
	return current_hp <= 0

func is_enemy(other: ModelPiece) -> bool:
	return color != other.color

func print_piece():
	print("~~~~~~~~~~~~~~~~~~~~")
	print("type:", type)
	print("color:", color)
	print("coordinate:", coordinate)
	print("max hp:", max_hp)
	print("current hp:", current_hp)
	print("~~~~~~~~~~~~~~~~~~~~")
