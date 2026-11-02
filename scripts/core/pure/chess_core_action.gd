extends RefCounted
class_name ChessCoreAction

enum Kind { MOVE, ACTIVE_ABILITY, ARCHER_CHARGE }

var kind := Kind.MOVE
var piece_id := ""
var color := ""
var from := Vector2i.ZERO
var target := Vector2i.ZERO
var path: Array[Vector2i] = []


func copy() -> ChessCoreAction:
	var result := ChessCoreAction.new()
	result.kind = kind
	result.piece_id = piece_id
	result.color = color
	result.from = from
	result.target = target
	result.path.assign(path)
	return result


func key() -> String:
	return "%d|%s|%d,%d|%d,%d|%s" % [kind, piece_id, from.x, from.y, target.x, target.y, path]
