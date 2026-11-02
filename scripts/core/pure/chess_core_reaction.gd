extends RefCounted
class_name ChessCoreReaction

var calling_piece_id := ""
var action_type: StringName = &""
var priority := 0
var sequence := 0
var event_coordinate := Vector2i(-1, -1)


func copy() -> ChessCoreReaction:
	var result := ChessCoreReaction.new()
	result.calling_piece_id = calling_piece_id
	result.action_type = action_type
	result.priority = priority
	result.sequence = sequence
	result.event_coordinate = event_coordinate
	return result
