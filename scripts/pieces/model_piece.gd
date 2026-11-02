#~~~~~~~~NEW FILE: model_piece.gd~~~~~~~~~~~~
extends Node
class_name ModelPiece

signal movement_type_granted(movement_type: StringName)

# Base class for all pieces.
# Considered part of the Model component of the chess game scene.

var model: ChessBoardModel = null	# set in inject_dependencies() in chess_model.gd


var color: String 	# black, white
var type: String 	# pawn, knight, bishop, minotaur king, etc
var coordinate: Vector2i
var piece_id: String = ""

var max_hp: int = 1
var current_hp: int = 1
var attack_power: int = 1

var has_moved: bool = false
var stunned: bool = false
var stun_timer: int = 0
var cooldown: int = 0

var is_king: bool = false
var granted_movement_types: Array[StringName] = []

func _init(_color: String, _coordinate: Vector2i):
	color = _color
	coordinate = _coordinate	
	current_hp = max_hp

func get_position_type_id() -> StringName:
	return ChessPieceCatalog.normalize_type_id(StringName(type))

func capture_piece_state() -> ChessPieceState:
	var state := ChessPieceState.new()
	state.type_id = get_position_type_id()
	state.piece_id = piece_id
	state.color = color
	state.coordinate = coordinate
	state.max_hp = max_hp
	state.current_hp = current_hp
	state.attack_power = attack_power
	state.has_moved = has_moved
	state.stunned = stunned
	state.stun_timer = stun_timer
	state.granted_movement_types.assign(granted_movement_types)
	if self is KingPiece:
		state.current_cooldown = (self as KingPiece).current_cooldown
		state.cooldown_reset_pending = (self as KingPiece).cooldown_reset_pending
		state.initial_cooldown_turn_pending = (self as KingPiece).initial_cooldown_turn_pending
	state.custom_state = capture_custom_state()
	return state

func restore_piece_state(state: ChessPieceState) -> void:
	piece_id = state.piece_id
	max_hp = state.max_hp
	current_hp = state.current_hp
	attack_power = state.attack_power
	has_moved = state.has_moved
	stunned = state.stunned
	stun_timer = state.stun_timer
	granted_movement_types.assign(state.granted_movement_types)
	if self is KingPiece:
		(self as KingPiece).current_cooldown = state.current_cooldown
		(self as KingPiece).cooldown_reset_pending = state.cooldown_reset_pending
		(self as KingPiece).initial_cooldown_turn_pending = state.initial_cooldown_turn_pending
	restore_custom_state(state.custom_state)

func capture_custom_state() -> Dictionary:
	return {}

func restore_custom_state(_state: Dictionary) -> void:
	pass
	
	
	
	
func get_legal_moves() -> Array:
	return model.get_legal_moves(self) if model != null else []

## Side-effect-free direct-attack contract used by both live rules and AI
## projections. Active abilities are deliberately outside this interface.
func can_directly_attack_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	return ClassicChessCore.directly_attacks_in_occupancy(
		position.get_core_piece(self, origin), origin, target, position.get_core_occupancy()
	)


func get_live_attack_position() -> ChessAttackPosition:
	return ChessAttackPosition.from_board(model.board)


## Ordered landing paths for legal movement actions. Most pieces have one
## landing; path-dependent pieces are supplied by the authoritative core.
func get_legal_move_paths() -> Array:
	return model.get_legal_move_paths(self) if model != null else []

func grant_movement_type(movement_type: StringName) -> void:
	if movement_type in [&"pawn", &"knight", &"bishop", &"rook"] and movement_type not in granted_movement_types:
		granted_movement_types.append(movement_type)
		movement_type_granted.emit(movement_type)

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
