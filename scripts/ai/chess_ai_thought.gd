extends RefCounted
class_name ChessAiThought

var model_revision: int
var color: String
var action_kind: ChessPrimaryAction.Kind
var piece_coordinate: Vector2i
var piece_type_id: StringName
var target: Vector2i
var path: Array[Vector2i] = []
var score: float
var brain_id: StringName = &"ryck"
var analyzed_leaf_count := 0
var search_profile: Dictionary = {}
var candidates: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	return {
		"brain_id": String(brain_id), "color": color, "score": score,
		"selected": {"kind": action_kind, "piece_type": String(piece_type_id), "from": [piece_coordinate.x, piece_coordinate.y], "target": [target.x, target.y], "path": path.map(func(value: Vector2i): return [value.x, value.y])},
		"analyzed_leaf_count": analyzed_leaf_count,
		"search_profile": search_profile.duplicate(true),
		"candidates": candidates.duplicate(true),
	}
