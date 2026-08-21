extends Resource
class_name ChessPieceState

@export var type_id: StringName = &"pawn"
@export_enum("white", "black") var color: String = "white"
@export var coordinate: Vector2i = Vector2i.ZERO
@export var max_hp: int = 1
@export var current_hp: int = 1
@export var attack_power: int = 1
@export var has_moved: bool = false
@export var stunned: bool = false
@export var stun_timer: int = 0
@export var current_cooldown: int = 0
@export var custom_state: Dictionary = {}

func copy() -> ChessPieceState:
	var result := ChessPieceState.new()
	result.type_id = type_id
	result.color = color
	result.coordinate = coordinate
	result.max_hp = max_hp
	result.current_hp = current_hp
	result.attack_power = attack_power
	result.has_moved = has_moved
	result.stunned = stunned
	result.stun_timer = stun_timer
	result.current_cooldown = current_cooldown
	result.custom_state = custom_state.duplicate(true)
	return result
