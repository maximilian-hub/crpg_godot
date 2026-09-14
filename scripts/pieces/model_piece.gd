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
		state.cooldown_reset_pending = (self as KingPiece).cooldown_reset_pending
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
		(self as KingPiece).cooldown_reset_pending = state.cooldown_reset_pending
	restore_custom_state(state.custom_state)

func capture_custom_state() -> Dictionary:
	return {}

func restore_custom_state(_state: Dictionary) -> void:
	pass
	
	
	
	
func get_legal_moves() -> Array:
	return []

## Ordered landing paths for legal movement actions. Most pieces have one
## landing; multi-step pieces override this without flattening route identity.
func get_legal_move_paths() -> Array:
	var paths: Array = []
	for destination in get_legal_moves():
		paths.append([destination])
	return paths

func take_damage(damage: int = 1):
	current_hp -= damage
	# Damage presentation belongs to the hit regardless of whether the piece
	# survives it. Emit while the model and its PieceView are still registered so
	# listeners can present the impact before destruction begins.
	model.piece_damaged.emit(self, damage, current_hp, max_hp)
	if current_hp <= 0:
		model.destroy_piece(self, true)
		
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
	if current_turn == color and stunned:
		decrement_stun_timer()

func _on_piece_destroyed(piece: ModelPiece):
	pass

func active_target_selected(coord: Vector2i):
	pass # override

func stun(duration: int = 2):
	stunned = true
	stun_timer = duration
	model.piece_stunned.emit(self, duration)

func decrement_stun_timer():
	if stun_timer <= 0:
		stun_timer = 0
		return
	stun_timer -= 1
	if stun_timer == 0 and stunned:
		unstun()

func unstun():
	stunned = false
	model.piece_recovered.emit(self)

func get_selection_targets(action_type: String, event_data) -> Array:
	return []

## Override for queued reactions that do not require a target selection.
func resolve_automatic_reaction(action_type: String, event_data) -> void:
	pass
