extends RefCounted
class_name ChessCoreAutonomousEntity

var entity_id := ""
var type_id: StringName = &""
var coordinate := Vector2i.ZERO
var owner_color := ""
var source_piece_id := ""
var target_piece_id := ""
var custom_state := {}


static func from_entity_state(source: ChessAutonomousEntityState) -> ChessCoreAutonomousEntity:
	var result := ChessCoreAutonomousEntity.new()
	result.entity_id = source.entity_id
	result.type_id = source.type_id
	result.coordinate = source.coordinate
	result.owner_color = source.owner_color
	result.source_piece_id = source.source_piece_id
	result.target_piece_id = source.target_piece_id
	result.custom_state = source.custom_state.duplicate(true)
	return result


func copy() -> ChessCoreAutonomousEntity:
	var result := ChessCoreAutonomousEntity.new()
	result.entity_id = entity_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.target_piece_id = target_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result


func to_entity_state() -> ChessAutonomousEntityState:
	var result := ChessAutonomousEntityState.new()
	result.entity_id = entity_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.target_piece_id = target_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result
