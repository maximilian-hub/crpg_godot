#~~~~~~~~NEW FILE: model_piece.gd~~~~~~~~~~~~
extends Node
class_name ModelPiece

# Base class for all pieces.
# Considered part of the Model component of the chess game scene.

var model: ChessBoardModel = null	# set in inject_dependencies() in chess_model.gd


var color: String 	# black, white
var type: String 	# pawn, knight, bishop, minotaur king, etc
var coordinate: Vector2i

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

func get_position_type_id() -> StringName:
	return ChessPieceCatalog.normalize_type_id(StringName(type))

func capture_piece_state() -> ChessPieceState:
	var state := ChessPieceState.new()
	state.type_id = get_position_type_id()
	state.color = color
	state.coordinate = coordinate
	state.max_hp = max_hp
	state.current_hp = current_hp
	state.attack_power = attack_power
	state.has_moved = has_moved
	state.stunned = stunned
	state.stun_timer = stun_timer
	if self is KingPiece:
		state.current_cooldown = (self as KingPiece).current_cooldown
	state.custom_state = capture_custom_state()
	return state

func restore_piece_state(state: ChessPieceState) -> void:
	max_hp = state.max_hp
	current_hp = state.current_hp
	attack_power = state.attack_power
	has_moved = state.has_moved
	stunned = state.stunned
	stun_timer = state.stun_timer
	if self is KingPiece:
		(self as KingPiece).current_cooldown = state.current_cooldown
	restore_custom_state(state.custom_state)

func capture_custom_state() -> Dictionary:
	return {}

func restore_custom_state(_state: Dictionary) -> void:
	pass
	
	
	
	
func get_legal_moves() -> Array:
	return []

func take_damage(damage: int = 1):
	current_hp -= damage
	var destroyed = current_hp <= 0
	
	if destroyed:
		model.destroy_piece(self, true) 
	else:
		model.piece_damaged.emit(self, damage, current_hp, max_hp)
		
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
	model.piece_stunned.emit(self, duration)

func decrement_stun_timer():
	stun_timer -= 1
	if stun_timer == 0: unstun()

func unstun():
	stunned = false
	model.piece_recovered.emit(self)

func get_selection_targets(action_type: String, event_data) -> Array:
	return []

## Override for queued reactions that do not require a target selection.
func resolve_automatic_reaction(action_type: String, event_data) -> void:
	pass
