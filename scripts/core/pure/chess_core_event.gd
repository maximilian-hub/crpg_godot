extends RefCounted
class_name ChessCoreEvent

var kind: StringName = &""
var data: Dictionary = {}


static func make(event_kind: StringName, event_data := {}) -> ChessCoreEvent:
	var result := ChessCoreEvent.new()
	result.kind = event_kind
	result.data = event_data.duplicate(true)
	return result


func to_dictionary() -> Dictionary:
	return {"kind": kind, "data": data.duplicate(true)}
