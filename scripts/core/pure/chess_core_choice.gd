extends RefCounted
class_name ChessCoreChoice

var kind: StringName = &""
var piece_id := ""
var action_type: StringName = &""
var sequence := 0
var event_coordinate := Vector2i(-1, -1)
var options: Array = []


func copy() -> ChessCoreChoice:
	var result := ChessCoreChoice.new()
	result.kind = kind
	result.piece_id = piece_id
	result.action_type = action_type
	result.sequence = sequence
	result.event_coordinate = event_coordinate
	result.options.assign(options)
	return result
