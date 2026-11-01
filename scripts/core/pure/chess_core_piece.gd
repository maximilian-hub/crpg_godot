extends RefCounted
class_name ChessCorePiece

var type_id: StringName = &"pawn"
var piece_id := ""
var color := "white"
var coordinate := Vector2i.ZERO
var max_hp := 1
var current_hp := 1
var attack_power := 1
var has_moved := false
var stunned := false
var stun_timer := 0


static func from_piece_state(source: ChessPieceState) -> ChessCorePiece:
	var result := ChessCorePiece.new()
	result.type_id = ChessPieceCatalog.normalize_type_id(source.type_id)
	result.piece_id = source.piece_id
	result.color = source.color
	result.coordinate = source.coordinate
	result.max_hp = source.max_hp
	result.current_hp = source.current_hp
	result.attack_power = source.attack_power
	result.has_moved = source.has_moved
	result.stunned = source.stunned
	result.stun_timer = source.stun_timer
	return result


func copy() -> ChessCorePiece:
	var result := ChessCorePiece.new()
	result.type_id = type_id
	result.piece_id = piece_id
	result.color = color
	result.coordinate = coordinate
	result.max_hp = max_hp
	result.current_hp = current_hp
	result.attack_power = attack_power
	result.has_moved = has_moved
	result.stunned = stunned
	result.stun_timer = stun_timer
	return result


func to_piece_state() -> ChessPieceState:
	var result := ChessPieceState.new()
	result.type_id = type_id
	result.piece_id = piece_id
	result.color = color
	result.coordinate = coordinate
	result.max_hp = max_hp
	result.current_hp = current_hp
	result.attack_power = attack_power
	result.has_moved = has_moved
	result.stunned = stunned
	result.stun_timer = stun_timer
	return result


func is_king() -> bool:
	return type_id == &"classic_king"
