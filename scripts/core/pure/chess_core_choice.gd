extends RefCounted
class_name ChessCoreChoice

var kind: StringName = &""
var piece_id := ""
var options: Array[StringName] = []


func copy() -> ChessCoreChoice:
	var result := ChessCoreChoice.new()
	result.kind = kind
	result.piece_id = piece_id
	result.options.assign(options)
	return result
