#~~~~~~~~NEW FILE: model_piece.gd~~~~~~~~~~~~
extends Node
class_name ModelPiece

# Base class for all pieces.
# Considered part of the Model component of the chess game scene.

var model: ChessBoardModel = null	# set in inject_dependencies() in chess_model.gd
var view: ChessBoardView = null	# set in inject_dependencies() in chess_model.gd
var controller: ChessBoardController = null # set in inject_dependencies() in chess_model.gd
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

func _init(_color: String, _coordinate: Vector2i):
	color = _color
	coordinate = _coordinate	
	current_hp = max_hp
	
	
	
	
func get_legal_moves() -> Array:
	return []

func take_damage(damage: int = 1):
	current_hp -= damage
	var destroyed = current_hp <= 0
	
	if destroyed:
		model.destroy_piece(self, true) 
	else:
		if is_instance_valid(view_node):
			view.spawn_splatter(coordinate)
			view_node.update_hp(current_hp) # Notify the view layer	
		else:
			printerr("take_damage: Tried to update visuals for piece ", type, " at ", coordinate, " but its view_node is invalid.")

#func destroy():
	#view.destroy_piece(view_node) # i keep getting an error here...
		## Gemini ;-;
		## Seemingly randomly, I'll get an error here.
		## I can make a bunch of moves,
		## And then I'll move a piece to an empty square, 
		## And this happens!
		## error is: Invalid type in function 'destroy_piece' in base 'Node2D (chess_board.gd)'. The Object-derived class of argument 1 (previously freed) is not a subclass of the expected argument class.
		## 
	#model.destroy_piece(self)

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

func _on_piece_destroyed(piece: ModelPiece):
	pass

func active_target_selected(coord: Vector2i):
	pass # override

func stun(duration: int = 2):
	stunned = true
	stun_timer = duration
	view.spawn_stun_stars(view_node)

func decrement_stun_timer():
	stun_timer -= 1
	if stun_timer == 0: unstun()

func unstun():
	stunned = false
	view.remove_stun_stars(coordinate)

func get_selection_targets(action_type: String, event_data) -> Array:
	return []		

func _on_selection_processing_start(piece: ModelPiece): pass
func _on_selection_processing_end(): pass
