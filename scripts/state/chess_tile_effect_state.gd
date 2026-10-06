extends Resource
class_name ChessTileEffectState

@export var effect_id: String = ""
@export var type_id: StringName = &""
@export var coordinate := Vector2i.ZERO
@export var owner_color: String = ""
@export var source_piece_id: String = ""
@export var custom_state: Dictionary = {}

func copy() -> ChessTileEffectState:
	var result := ChessTileEffectState.new()
	result.effect_id = effect_id
	result.type_id = type_id
	result.coordinate = coordinate
	result.owner_color = owner_color
	result.source_piece_id = source_piece_id
	result.custom_state = custom_state.duplicate(true)
	return result
