extends RefCounted
class_name DialogueTextSpan

enum Kind { COLOR, CAPITALIZATION, FONT_SIZE, JIGGLE }

var kind: Kind
var start_index := 0
var end_index := 0
var value := ""


func _init(new_kind: Kind = Kind.COLOR, new_start_index: int = 0, new_end_index: int = 0, new_value: String = "") -> void:
	kind = new_kind
	start_index = new_start_index
	end_index = new_end_index
	value = new_value
