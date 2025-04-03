#~~~~~~~~NEW FILE: model_piece.gd~~~~~~~~~~~~
extends Node
class_name ModelPiece

# Base class for all pieces.
# Considered part of the Model component of the chess game scene.

var model: Node = null	# set in inject_dependencies() in model.gd
var view: Node = null	# set in inject_dependencies() in model.gd
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
var stun_timer: int = 0
var cooldown: int = 0

var is_king: bool = false

func _init(_color: String, _type: String, _coordinate: Vector2i):
	color = _color
	type = _type
	coordinate = _coordinate	
	current_hp = max_hp


func take_damage(damage: int = 1):
	current_hp -= 1
	var destroyed = current_hp <= 0
	
	if destroyed:
		destroy()
	else:
		view.spawn_splatter(coordinate)
		var hp_bar = $HpBar
		view_node.update_hp(current_hp) # Notify the view layer

func destroy():
	model.board[coordinate.x][coordinate.y] = null
	view.destroy_piece(view_node)		

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

func _on_turn_changed(current_turn: String):
	if current_turn == color: decrement_stun_timer()
	pass

func active_target_selected(coord: Vector2i):
	pass

func stun(duration: int = 2):
	print("stunned :( owie")
	stunned = true
	stun_timer = duration
	view.spawn_stun_stars(view_node)

func decrement_stun_timer():
	stun_timer -= 1
	if stun_timer == 0: unstun()

func unstun():
	stunned = false
	print("not stunned anymore hehe")
	view.remove_stun_stars(coordinate)
		# TODO: remove visual stun effect
		
