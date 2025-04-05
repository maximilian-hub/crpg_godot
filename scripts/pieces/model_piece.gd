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
		destroy()
	else:
		view.spawn_splatter(coordinate)
		view_node.update_hp(current_hp) # Notify the view layer

#func destroy():
	#model.board[coordinate.x][coordinate.y] = null
	#view.destroy_piece(view_node)		

func destroy():
	const RAISE_DEAD_TRIGGER_TYPES = ["knight", "bishop", "rook", "queen"]
	if type in RAISE_DEAD_TRIGGER_TYPES:
		var destroyed_coord = self.coordinate 
		# Iterate through the whole board to find any Necromancer Kings
		for r in range(model.board.size()):
			for c in range(model.board[r].size()):
				var piece = model.board[r][c]
				# Check if the piece is a Necromancer King
				if piece is NecromancerKing:
					# Call the passive handler method on the Necromancer King instance
					# Pass the piece that was just destroyed
					piece._on_other_piece_destroyed(self)

	# --- Original Destruction Logic ---
	# Remove piece data from the model's board array
	if is_instance_valid(model):
		model.board[coordinate.x][coordinate.y] = null
	# Tell the view to remove the visual representation (if valid)
	if is_instance_valid(view) and is_instance_valid(view_node):
		view.destroy_piece(view_node) # View handles visual removal + effects

	# Note: ModelPiece extends Node but is usually just treated as data.
	# It's not typically added to the scene tree directly, so queue_free()
	# might not be needed here unless you explicitly add ModelPiece nodes somewhere.
	# If they *are* added to the tree, uncomment the line below.
	# queue_free()

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
		
