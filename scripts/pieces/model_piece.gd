extends Node
class_name ModelPiece

# Base class for all pieces.
# Considered part of the Model component of the chess game scene.

var model: Node = null	# set in inject_dependencies() in model.gd
var view: Node = null	# set in inject_dependencies() in model.gd
var board: Array = []
var hp_bar_scene = preload("res://ui/hp_bar.tscn")


var color: String 	# black, white
var type: String 	# pawn, knight, bishop, minotaur king, etc
var coordinate: Vector2i
var view_node: Node # the node visually representing this piece on the screen

var max_hp: int = 1
var current_hp: int = 1
var attack_power: int = 1

var has_moved: bool = false
var stunned: bool = false
var cooldown: int = 0

func _init(_color: String, _type: String, _coordinate: Vector2i):
	color = _color
	type = _type
	coordinate = _coordinate	
	current_hp = max_hp

func take_damage() -> bool:
	current_hp -= 1
	view.spawn_splatter(coordinate)
	var hp_bar = $HpBar
	view_node.update_hp(current_hp) # Notify the view layer
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
