extends RefCounted
class_name ChessCoreTileEffect

var effect_id := ""
var type_id: StringName = &""
var coordinate := Vector2i.ZERO
var owner_color := ""
var source_piece_id := ""
var custom_state := {}


static func from_effect_state(source: ChessTileEffectState) -> ChessCoreTileEffect:
	var result := ChessCoreTileEffect.new()
	result.effect_id = source.effect_id
	result.type_id = source.type_id
	result.coordinate = source.coordinate
	result.owner_color = source.owner_color
	result.source_piece_id = source.source_piece_id
	result.custom_state = source.custom_state.duplicate(true)
	return result


func copy() -> ChessCoreTileEffect:
	var result := ChessCoreTileEffect.new()
	result.effect_id = effect_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result


func to_effect_state() -> ChessTileEffectState:
	var result := ChessTileEffectState.new()
	result.effect_id = effect_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result
