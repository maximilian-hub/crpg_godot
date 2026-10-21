#~~~~~~~~NEW FILE: model_piece.gd~~~~~~~~~~~~
extends Node
class_name ModelPiece

const DirectAttackRules := preload("res://scripts/core/chess_direct_attack_rules.gd")

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
	restore_custom_state(state.custom_state)

func capture_custom_state() -> Dictionary:
	return {}

func restore_custom_state(_state: Dictionary) -> void:
	pass
	
	
	
	
func get_legal_moves() -> Array:
	return []

## Side-effect-free direct-attack contract used by both live rules and AI
## projections. Active abilities are deliberately outside this interface.
func can_directly_attack_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	if can_natively_attack_square(origin, target, position):
		return true
	for movement_type in granted_movement_types:
		if DirectAttackRules.movement_type_attacks_square(movement_type, color, origin, target, position):
			return true
	return false


func can_natively_attack_square(origin: Vector2i, target: Vector2i, position: ChessAttackPosition) -> bool:
	match get_position_type_id():
		&"pawn", &"bone_pawn":
			return DirectAttackRules.movement_type_attacks_square(&"pawn", color, origin, target, position)
		&"knight":
			return DirectAttackRules.movement_type_attacks_square(&"knight", color, origin, target, position)
		&"bishop":
			return DirectAttackRules.movement_type_attacks_square(&"bishop", color, origin, target, position)
		&"rook":
			return DirectAttackRules.movement_type_attacks_square(&"rook", color, origin, target, position)
		&"queen":
			return DirectAttackRules.queen_attacks_square(origin, target, position)
	return false


func get_live_attack_position() -> ChessAttackPosition:
	return ChessAttackPosition.from_board(model.board)


func get_native_direct_move_destinations() -> Array:
	var destinations: Array = []
	var position := get_live_attack_position()
	for row_index in range(position.board_size.x):
		for column_index in range(position.board_size.y):
			var target := Vector2i(row_index, column_index)
			if not can_natively_attack_square(coordinate, target, position):
				continue
			var occupant = position.get_occupant(target)
			if occupant == null or position.get_color(target) != color:
				destinations.append(target)
	return destinations

## Ordered landing paths for legal movement actions. Most pieces have one
## landing; multi-step pieces override this without flattening route identity.
func get_legal_move_paths() -> Array:
	var paths: Array = []
	for destination in get_legal_moves():
		paths.append([destination])
	return paths

func grant_movement_type(movement_type: StringName) -> void:
	if movement_type in [&"pawn", &"knight", &"bishop", &"rook"] and movement_type not in granted_movement_types:
		granted_movement_types.append(movement_type)
		movement_type_granted.emit(movement_type)

func take_damage(damage: int = 1):
	if has_method("incoming_damage_multiplier"):
		damage *= int(call("incoming_damage_multiplier"))
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
